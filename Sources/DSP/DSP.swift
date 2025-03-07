import Accelerate
import AudioProcessor
import Foundation
import Utilities

/// Class for audio signal processing operations using Apple's Accelerate framework.
/// Provides functionality for converting time-domain audio signals into frequency
/// domain representations required for voice conversion models.
public class DSP {

    private var fftSetup: vDSP.FFT<DSPSplitComplex>?
    private var fftSize: Int
    private var windowBuffer: [Float]

    // Default audio settings
    private let defaultSampleRate: Float = 44100.0

    // Number of mel bands for mel spectrogram
    private let melBands = 80
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

        // Initialize mel filterbank
        self.melFilterbank = createMelFilterbank(
            fftSize: fftSize,
            sampleRate: defaultSampleRate,
            melBands: melBands,
            minFreq: minFrequency,
            maxFreq: maxFrequency)

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
        // Check if spectrogram is empty
        guard !spectrogram.isEmpty else {
            Utilities.log("Error: Empty spectrogram provided to specToMelSpec")
            return []
        }

        guard let melFilterbank = melFilterbank else {
            Utilities.log("Error: Mel filterbank not initialized")
            return spectrogram
        }

        let numFrames = spectrogram.count
        let numBins = spectrogram[0].count

        // Ensure filterbank dimensions match
        guard numBins == melFilterbank[0].count else {
            Utilities.log("Error: Filterbank dimensions don't match spectrogram")
            return spectrogram
        }

        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: melBands), count: numFrames)

        // Apply mel filterbank to each frame
        for i in 0..<numFrames {
            let frame = spectrogram[i]

            // Apply each mel filter
            for j in 0..<melBands {
                // Dot product of frame with filterbank row
                var sum: Float = 0.0
                vDSP_dotpr(frame, 1, melFilterbank[j], 1, &sum, vDSP_Length(numBins))
                melSpectrogram[i][j] = sum
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
     - Returns: Mel filterbank matrix (melBands x fftSize/2)
     */
    private func createMelFilterbank(
        fftSize: Int, sampleRate: Float, melBands: Int, minFreq: Float, maxFreq: Float
    ) -> [[Float]] {
        let numBins = fftSize / 2

        // Convert min and max frequencies to mel scale
        let minMel = 2595.0 * log10(1.0 + minFreq / 700.0)
        let maxMel = 2595.0 * log10(1.0 + maxFreq / 700.0)

        // Create equally spaced points in mel scale
        let melPoints = stride(
            from: minMel, through: maxMel, by: (maxMel - minMel) / Float(melBands + 1)
        ).map { Float($0) }

        // Convert mel points back to frequency
        let freqPoints = melPoints.map { 700.0 * (pow(10.0, $0 / 2595.0) - 1.0) }

        // Convert frequency points to FFT bin indices
        let binPoints = freqPoints.map { Int(floor($0 * Float(fftSize) / sampleRate)) }

        // Create filterbank matrix
        var filterbank = [[Float]](
            repeating: [Float](repeating: 0.0, count: numBins), count: melBands)

        for i in 0..<melBands {
            let leftBin = binPoints[i]
            let centerBin = binPoints[i + 1]
            let rightBin = binPoints[i + 2]

            // Create triangular filter
            for j in leftBin..<centerBin {
                if j < numBins && j >= 0 {
                    filterbank[i][j] = Float(j - leftBin) / Float(centerBin - leftBin)
                }
            }

            for j in centerBin..<rightBin {
                if j < numBins && j >= 0 {
                    filterbank[i][j] = Float(rightBin - j) / Float(rightBin - centerBin)
                }
            }
        }

        return filterbank
    }
}
