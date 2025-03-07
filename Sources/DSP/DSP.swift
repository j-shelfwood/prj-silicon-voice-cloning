import Accelerate
import AudioProcessor
import Foundation
import Utilities

/// Class for audio signal processing operations using Apple's Accelerate framework.
/// Provides functionality for converting time-domain audio signals into frequency
/// domain representations required for voice conversion models.
/// DSP: Digital Signal Processing
public class DSP {

    private var fftSetup: vDSP.FFT<DSPSplitComplex>?
    private var fftSize: Int
    private var windowBuffer: [Float]

    // Default audio settings
    private let defaultSampleRate: Float = 44100.0

    // Number of mel bands for mel spectrogram
    private let melBands = 40
    // Frequency range for mel spectrogram (Hz)
    private let minFrequency: Float = 0.0
    private let maxFrequency: Float = 8000.0
    // Mel filterbank matrix
    private var melFilterbank: [[Float]]?

    /**
     Initialize a new DSP instance with the specified FFT size

     - Parameter fftSize: Size of the FFT to perform (default: 1024)
     */
    public init(fftSize: Int = 1024) {
        self.fftSize = fftSize

        // Create a Hann window for better spectral analysis
        self.windowBuffer = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&windowBuffer, vDSP_Length(fftSize), Int32(0))

        let log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)

        // Initialize mel filterbank with Slaney-style mel scale (default)
        self.melFilterbank = createMelFilterbank(
            fftSize: fftSize,
            sampleRate: defaultSampleRate,
            melBands: melBands,
            minFreq: minFrequency,
            maxFreq: maxFrequency,
            useHTK: false)  // Use Slaney-style mel scale by default

        Utilities.log("DSP initialized with FFT size: \(fftSize)")
    }

    /**
     Perform a forward FFT on the input buffer

     - Parameter inputBuffer: Audio samples in time domain
     - Returns: Magnitude spectrum in frequency domain
     */
    public func performFFT(inputBuffer: [Float]) -> [Float] {
        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            Utilities.log(
                "Error: Input buffer too small for FFT. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return Array(repeating: 0.0, count: fftSize / 2)
        }

        // Create a copy of the input buffer to avoid modifying the original
        var inputCopy = Array(inputBuffer.prefix(fftSize))

        // Apply window function to reduce spectral leakage
        vDSP_vmul(inputCopy, 1, windowBuffer, 1, &inputCopy, 1, vDSP_Length(fftSize))

        // Prepare split complex buffer for FFT
        let halfSize = fftSize / 2
        var realp = [Float](repeating: 0.0, count: halfSize)
        var imagp = [Float](repeating: 0.0, count: halfSize)

        // Safely use pointers with withUnsafeMutableBufferPointer
        return realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                // Create split complex with safe pointers
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                // Convert real input to split complex format
                inputCopy.withUnsafeBytes { inputPtr in
                    let ptr = inputPtr.bindMemory(to: DSPComplex.self).baseAddress!
                    vDSP_ctoz(ptr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }

                // Perform forward FFT
                guard let fftSetup = fftSetup else {
                    Utilities.log("Error: FFT setup not initialized")
                    return Array(repeating: 0.0, count: fftSize / 2)
                }

                // Use the FFT setup to perform the forward transform
                fftSetup.forward(input: splitComplex, output: &splitComplex)

                // Calculate magnitude spectrum
                var magnitudes = [Float](repeating: 0.0, count: halfSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

                // Scale magnitudes
                var scaleFactor = Float(1.0) / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scaleFactor, &magnitudes, 1, vDSP_Length(halfSize))

                // Convert to dB scale (optional)
                // 10 * log10(x) for power spectrum
                var dbMagnitudes = [Float](repeating: 0.0, count: halfSize)
                var zeroReference: Float = 1.0
                vDSP_vdbcon(
                    magnitudes, 1, &zeroReference, &dbMagnitudes, 1, vDSP_Length(halfSize), 1)

                return dbMagnitudes
            }
        }
    }

    /**
     Generate a spectrogram from the input buffer

     - Parameters:
       - inputBuffer: Audio samples in time domain
       - hopSize: Number of samples to advance between FFT windows
     - Returns: 2D array representing the spectrogram (time x frequency)
     */
    public func generateSpectrogram(inputBuffer: [Float], hopSize: Int = 256) -> [[Float]] {
        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            Utilities.log(
                "Error: Input buffer too small for spectrogram generation. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return []
        }

        // Calculate number of frames
        let numFrames = max(1, (inputBuffer.count - fftSize) / hopSize + 1)
        var spectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: fftSize / 2), count: numFrames)

        // Process each frame
        for i in 0..<numFrames {
            let startIdx = i * hopSize
            let endIdx = startIdx + fftSize

            // Ensure we don't go out of bounds
            guard endIdx <= inputBuffer.count else {
                // If we can't get a full frame, just use what we have and pad with zeros
                var frame = Array(inputBuffer[startIdx..<inputBuffer.count])
                frame.append(contentsOf: [Float](repeating: 0.0, count: endIdx - inputBuffer.count))
                spectrogram[i] = performFFT(inputBuffer: frame)
                continue
            }

            // Extract frame and perform FFT
            let frame = Array(inputBuffer[startIdx..<endIdx])
            spectrogram[i] = performFFT(inputBuffer: frame)
        }

        return spectrogram
    }

    /**
     Convert spectrogram to mel-spectrogram using mel filterbank

     - Parameter spectrogram: Linear frequency spectrogram
     - Returns: Mel-scaled spectrogram
     */
    public func specToMelSpec(spectrogram: [[Float]]) -> [[Float]] {
        guard !spectrogram.isEmpty else {
            Utilities.log("Error: Empty spectrogram provided to specToMelSpec")
            return []
        }

        let numFrames = spectrogram.count
        let numFreqBins = spectrogram[0].count

        // Create mel filterbank if not already created
        if melFilterbank == nil {
            melFilterbank = createMelFilterbank(
                fftSize: numFreqBins * 2,
                sampleRate: defaultSampleRate,
                melBands: melBands,
                minFreq: 0,
                maxFreq: defaultSampleRate / 2
            )
        }

        guard let filterbank = melFilterbank else {
            Utilities.log("Error: Failed to create mel filterbank")
            return []
        }

        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: melBands), count: numFrames)

        // Apply mel filterbank to each frame
        for i in 0..<numFrames {
            for j in 0..<melBands {
                var sum: Float = 0.0
                for k in 0..<numFreqBins {
                    if k < filterbank[j].count {
                        sum += spectrogram[i][k] * filterbank[j][k]
                    }
                }
                melSpectrogram[i][j] = sum
            }
        }

        // Ensure all values are non-negative
        for i in 0..<numFrames {
            for j in 0..<melBands {
                melSpectrogram[i][j] = max(0.0, melSpectrogram[i][j])
            }
        }

        return melSpectrogram
    }

    /**
     Create a mel filterbank matrix for converting linear frequency to mel scale

     - Parameters:
       - fftSize: Size of the FFT
       - sampleRate: Audio sample rate in Hz
       - melBands: Number of mel bands
       - minFreq: Minimum frequency in Hz
       - maxFreq: Maximum frequency in Hz
       - useHTK: Whether to use HTK-style mel scale formula (default: false)
     - Returns: Mel filterbank matrix (melBands x fftSize/2)
     */
    private func createMelFilterbank(
        fftSize: Int, sampleRate: Float, melBands: Int, minFreq: Float, maxFreq: Float,
        useHTK: Bool = false
    ) -> [[Float]] {
        let numBins = fftSize / 2

        // Ensure frequencies are within valid range
        let minFreq = max(0.0, min(minFreq, sampleRate / 2.0))
        let maxFreq = max(minFreq, min(maxFreq, sampleRate / 2.0))

        // Convert min and max frequencies to mel scale
        let minMel: Float
        let maxMel: Float

        if useHTK {
            // HTK-style mel scale: mel = 2595 * log10(1 + f/700)
            minMel = 2595.0 * log10(1.0 + minFreq / 700.0)
            maxMel = 2595.0 * log10(1.0 + maxFreq / 700.0)
        } else {
            // Slaney-style mel scale: mel = 1127 * ln(1 + f/700)
            minMel = 1127.0 * logf(1.0 + minFreq / 700.0)
            maxMel = 1127.0 * logf(1.0 + maxFreq / 700.0)
        }

        // Create array to hold mel points
        var melPoints = [Float](repeating: 0.0, count: melBands + 2)

        // Create equally spaced points in mel scale
        let melStep = (maxMel - minMel) / Float(melBands + 1)
        for i in 0...melBands + 1 {
            melPoints[i] = minMel + Float(i) * melStep
        }

        // Convert mel points back to frequency
        var freqPoints = [Float](repeating: 0.0, count: melBands + 2)
        for i in 0...melBands + 1 {
            if useHTK {
                freqPoints[i] = 700.0 * (pow(10.0, melPoints[i] / 2595.0) - 1.0)
            } else {
                freqPoints[i] = 700.0 * (exp(melPoints[i] / 1127.0) - 1.0)
            }
        }

        // Convert frequency points to FFT bin indices
        var binPoints = [Int](repeating: 0, count: melBands + 2)
        for i in 0...melBands + 1 {
            binPoints[i] = Int(floor(freqPoints[i] * Float(fftSize) / sampleRate))
            // Clamp to valid range
            binPoints[i] = max(0, min(binPoints[i], numBins - 1))
        }

        // Create filterbank matrix
        var filterbank = [[Float]](
            repeating: [Float](repeating: 0.0, count: numBins), count: melBands)

        for i in 0..<melBands {
            let leftBin = binPoints[i]
            let centerBin = binPoints[i + 1]
            let rightBin = binPoints[i + 2]

            // Skip if bins are too close (would create unstable filters)
            if rightBin - leftBin < 2 {
                Utilities.log(
                    "Warning: Mel filter \(i) has too narrow bandwidth. Consider using fewer mel bands."
                )
                continue
            }

            // Create triangular filter
            for j in leftBin...rightBin {
                if j < numBins && j >= 0 {
                    if j < centerBin {
                        // Left side of triangle
                        if centerBin > leftBin {
                            filterbank[i][j] = Float(j - leftBin) / Float(centerBin - leftBin)
                        }
                    } else {
                        // Right side of triangle
                        if rightBin > centerBin {
                            filterbank[i][j] = Float(rightBin - j) / Float(rightBin - centerBin)
                        }
                    }
                }
            }

            // Normalize the filter to have unit area (optional but recommended)
            let filterSum = filterbank[i].reduce(0, +)
            if filterSum > 0 {
                for j in 0..<numBins {
                    filterbank[i][j] /= filterSum
                }
            }
        }

        return filterbank
    }

    /**
     Convert mel-spectrogram to log-mel-spectrogram

     - Parameters:
       - melSpectrogram: Mel-scaled spectrogram
       - ref: Reference value for log scaling (default: 1.0)
       - floor: Floor value to clip small values (default: 1e-5)
     - Returns: Log-mel-spectrogram
     */
    public func melToLogMel(melSpectrogram: [[Float]], ref: Float = 1.0, floor: Float = 1e-5)
        -> [[Float]]
    {
        guard !melSpectrogram.isEmpty else {
            Utilities.log("Error: Empty mel-spectrogram provided to melToLogMel")
            return []
        }

        var logMelSpectrogram: [[Float]] = []
        let minDb: Float = -80.0  // Minimum dB value to clip to

        // Find the maximum value in the mel spectrogram for normalization
        var maxValue: Float = 0.0
        for frame in melSpectrogram {
            for value in frame {
                maxValue = max(maxValue, value)
            }
        }

        // If maxValue is too small, use a default value to avoid division by zero
        maxValue = max(maxValue, 1e-5)

        for frame in melSpectrogram {
            var logMelFrame: [Float] = []

            for value in frame {
                // Clip small values to avoid log(0)
                let clippedValue = max(value, floor)

                // Calculate log10 manually and convert to dB
                let logValue = 10.0 * log10(clippedValue / maxValue)

                // Clip to minimum dB
                let clippedLogValue = max(logValue, minDb)

                logMelFrame.append(clippedLogValue)
            }

            logMelSpectrogram.append(logMelFrame)
        }

        return logMelSpectrogram
    }
}

/// A class for processing audio in real-time chunks to produce mel-spectrograms.
/// This is optimized for streaming use cases where audio arrives in small buffers.
public class StreamingMelProcessor {
    private var dsp: DSP
    private var fftSize: Int
    private var hopSize: Int
    private var sampleRate: Float
    private var melBands: Int

    // Buffer to store audio samples that haven't been processed yet
    private var audioBuffer: [Float] = []
    // The maximum number of samples to keep in the buffer
    private var maxBufferSize: Int

    /**
     Initialize a new StreamingMelProcessor

     - Parameters:
       - fftSize: Size of the FFT to perform
       - hopSize: Number of samples to advance between FFT windows
       - sampleRate: Audio sample rate in Hz
       - melBands: Number of mel bands for the mel spectrogram
       - minFrequency: Minimum frequency in Hz for mel scale
       - maxFrequency: Maximum frequency in Hz for mel scale
     */
    public init(
        fftSize: Int, hopSize: Int, sampleRate: Float, melBands: Int, minFrequency: Float,
        maxFrequency: Float
    ) {
        self.dsp = DSP(fftSize: fftSize)
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.sampleRate = sampleRate
        self.melBands = melBands

        // Keep enough samples for at least 2 FFT windows to ensure smooth processing
        self.maxBufferSize = fftSize * 3

        Utilities.log(
            "StreamingMelProcessor initialized with FFT size: \(fftSize), hop size: \(hopSize)")
    }

    /**
     Process a chunk of audio samples and update the internal buffer

     - Parameter samples: New audio samples to process
     */
    public func addSamples(_ samples: [Float]) {
        // Add new samples to the buffer
        audioBuffer.append(contentsOf: samples)

        // Trim buffer if it gets too large
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(audioBuffer.count - maxBufferSize)
        }
    }

    /**
     Process the current audio buffer and generate mel-spectrogram frames

     - Parameter minFrames: Minimum number of frames to generate (or nil to process all available)
     - Returns: Array of mel-spectrogram frames and the number of samples consumed
     */
    public func processMelSpectrogram(minFrames: Int? = nil) -> (
        melFrames: [[Float]], samplesConsumed: Int
    ) {
        // Check if we have enough samples for at least one FFT window
        guard audioBuffer.count >= fftSize else {
            return ([], 0)
        }

        // Calculate how many complete frames we can process
        let availableFrames = (audioBuffer.count - fftSize) / hopSize + 1

        // Determine how many frames to actually process
        let framesToProcess = minFrames != nil ? min(availableFrames, minFrames!) : availableFrames

        // If no frames to process, return empty
        if framesToProcess <= 0 {
            return ([], 0)
        }

        // Calculate how many samples will be consumed
        let samplesToConsume = (framesToProcess - 1) * hopSize + fftSize

        // Generate spectrogram from the buffer
        let spectrogram = dsp.generateSpectrogram(
            inputBuffer: Array(audioBuffer.prefix(samplesToConsume)),
            hopSize: hopSize
        )

        // Convert to mel spectrogram
        let melSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)

        // Remove the consumed samples from the buffer
        if samplesToConsume > 0 {
            audioBuffer.removeFirst(samplesToConsume)
        }

        return (melSpectrogram, samplesToConsume)
    }

    /**
     Process the current audio buffer and generate log-mel-spectrogram frames

     - Parameter minFrames: Minimum number of frames to generate (or nil to process all available)
     - Returns: Array of log-mel-spectrogram frames and the number of samples consumed
     */
    public func processLogMelSpectrogram(minFrames: Int? = nil) -> (
        logMelFrames: [[Float]], samplesConsumed: Int
    ) {
        let (melFrames, samplesConsumed) = processMelSpectrogram(minFrames: minFrames)

        if melFrames.isEmpty {
            return ([], samplesConsumed)
        }

        // Convert to log-mel spectrogram
        let logMelFrames = dsp.melToLogMel(melSpectrogram: melFrames)

        return (logMelFrames, samplesConsumed)
    }

    /**
     Reset the internal audio buffer
     */
    public func reset() {
        audioBuffer.removeAll()
    }

    /**
     Get the current buffer length in samples

     - Returns: Number of samples in the buffer
     */
    public func getBufferLength() -> Int {
        return audioBuffer.count
    }
}
