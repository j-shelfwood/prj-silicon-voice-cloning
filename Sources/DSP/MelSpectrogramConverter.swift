import Accelerate
import Foundation
import Utilities

/// A class for converting linear frequency spectrograms to mel-scale spectrograms.
/// This class handles the creation and application of mel filterbanks for audio analysis.
public class MelSpectrogramConverter {
    private let sampleRate: Float
    private let melBands: Int
    private let minFrequency: Float
    private let maxFrequency: Float
    private let useHTK: Bool
    private var melFilterbank: [[Float]]?

    // Cache for vectorized operations
    private var flatFilterbank: [Float]?
    private var filterBankStrides: [Int]?
    private var lastSpectrogramWidth: Int?

    /**
     Initialize a new MelSpectrogramConverter instance.

     - Parameters:
        - sampleRate: Audio sample rate in Hz
        - melBands: Number of mel bands (default: 40)
        - minFrequency: Minimum frequency in Hz (default: 0)
        - maxFrequency: Maximum frequency in Hz (default: sampleRate/2)
        - useHTK: Whether to use HTK-style mel scale formula (default: false)
     */
    public init(
        sampleRate: Float = 44100.0,
        melBands: Int = 40,
        minFrequency: Float? = nil,
        maxFrequency: Float? = nil,
        useHTK: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.melBands = melBands
        self.minFrequency = minFrequency ?? 0.0
        self.maxFrequency = maxFrequency ?? (sampleRate / 2.0)
        self.useHTK = useHTK
    }

    /**
     Convert spectrogram to mel-spectrogram using mel filterbank.

     - Parameter spectrogram: Linear frequency spectrogram
     - Returns: Mel-scaled spectrogram
     */
    public func specToMelSpec(spectrogram: [[Float]]) -> [[Float]] {
        guard !spectrogram.isEmpty else {
            print("Error: Empty spectrogram provided to specToMelSpec")
            return []
        }

        let numFrames = spectrogram.count
        let numFreqBins = spectrogram[0].count

        // Create or update mel filterbank if needed
        if melFilterbank == nil || lastSpectrogramWidth != numFreqBins {
            melFilterbank = createMelFilterbank(fftSize: numFreqBins * 2)
            lastSpectrogramWidth = numFreqBins

            // Prepare vectorized filterbank
            if let fb = melFilterbank {
                // Flatten the filterbank for vectorized operations
                flatFilterbank = fb.flatMap { $0 }
                filterBankStrides = Array(repeating: numFreqBins, count: melBands)
            }
        }

        guard melFilterbank != nil,
            let flatFB = flatFilterbank,
            filterBankStrides != nil
        else {
            print("Error: Failed to create mel filterbank")
            return []
        }

        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: melBands), count: numFrames)

        // Flatten the input spectrogram for vectorized operations
        let flatSpectrogram = spectrogram.flatMap { $0 }

        // Process each frame using vDSP
        for i in 0..<numFrames {
            let frameStart = i * numFreqBins
            let frame = Array(flatSpectrogram[frameStart..<frameStart + numFreqBins])

            // Add small epsilon to avoid zero values and ensure positive values
            var processedFrame = [Float](repeating: 0.0, count: frame.count)
            var epsilon: Float = 1e-10
            var maxPossible: Float = Float.greatestFiniteMagnitude

            // First ensure all values are positive
            vDSP_vclip(
                frame, 1, &epsilon, &maxPossible, &processedFrame, 1, vDSP_Length(frame.count))

            // Create mutable array for the frame result
            var frameResult = [Float](repeating: 0.0, count: melBands)

            // Perform matrix multiplication using vDSP
            frameResult.withUnsafeMutableBufferPointer { resultPtr in
                processedFrame.withUnsafeBufferPointer { framePtr in
                    vDSP_mmul(
                        flatFB,  // Matrix A (filterbank)
                        1,  // A row stride
                        framePtr.baseAddress!,  // Matrix B (spectrogram frame)
                        1,  // B row stride
                        resultPtr.baseAddress!,  // Result matrix C
                        1,  // C row stride
                        vDSP_Length(melBands),  // Number of rows in A and C
                        1,  // Number of columns in B and C
                        vDSP_Length(numFreqBins)  // Number of columns in A and rows in B
                    )
                }
            }

            // Ensure non-negative values and add small epsilon
            var clippedResult = frameResult
            vDSP_vclip(
                &frameResult, 1, &epsilon, &maxPossible, &clippedResult, 1, vDSP_Length(melBands))

            melSpectrogram[i] = clippedResult
        }

        return melSpectrogram
    }

    /**
     Convert mel-spectrogram to log-mel-spectrogram.

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
            print("Error: Empty mel-spectrogram provided to melToLogMel")
            return []
        }

        let numFrames = melSpectrogram.count
        let numBands = melSpectrogram[0].count
        var minDb: Float = -80.0  // Minimum dB value to clip to
        var maxDb: Float = 0.0  // Maximum dB value (reference level)

        // Flatten the mel spectrogram for vectorized operations
        let flatMel = melSpectrogram.flatMap { $0 }

        // Ensure all values are positive and above floor
        var processedMel = [Float](repeating: 0.0, count: flatMel.count)
        var floorValue = floor
        var maxPossible: Float = Float.greatestFiniteMagnitude
        vDSP_vclip(
            flatMel, 1, &floorValue, &maxPossible, &processedMel, 1, vDSP_Length(flatMel.count))

        // Find maximum value using vDSP
        var maxValue: Float = 0.0
        vDSP_maxv(processedMel, 1, &maxValue, vDSP_Length(processedMel.count))
        maxValue = max(maxValue, floor)  // Ensure maxValue is at least floor

        // Create buffer for results
        var logMelFlat = [Float](repeating: 0.0, count: flatMel.count)

        // Normalize by maxValue and ensure minimum value
        var recipMaxValue = 1.0 / maxValue
        vDSP_vsmul(processedMel, 1, &recipMaxValue, &logMelFlat, 1, vDSP_Length(flatMel.count))

        // Ensure all values are at least floor after normalization
        vDSP_vclip(
            logMelFlat, 1, &floorValue, &maxPossible, &logMelFlat, 1, vDSP_Length(flatMel.count))

        // Convert to log scale (10 * log10(x))
        var ten: Float = 10.0
        vDSP_vdbcon(logMelFlat, 1, &ten, &logMelFlat, 1, vDSP_Length(flatMel.count), 1)

        // Clip to dB range
        vDSP_vclip(logMelFlat, 1, &minDb, &maxDb, &logMelFlat, 1, vDSP_Length(flatMel.count))

        // Reshape back to 2D array
        var logMelSpectrogram = [[Float]](repeating: [], count: numFrames)
        for i in 0..<numFrames {
            let start = i * numBands
            logMelSpectrogram[i] = Array(logMelFlat[start..<start + numBands])
        }

        return logMelSpectrogram
    }

    /**
     Create a mel filterbank matrix for converting linear frequency to mel scale.

     - Parameter fftSize: Size of the FFT
     - Returns: Mel filterbank matrix (melBands x fftSize/2)
     */
    private func createMelFilterbank(fftSize: Int) -> [[Float]] {
        let numBins = fftSize / 2

        // Ensure frequencies are within valid range
        let minFreq = max(0.0, min(minFrequency, sampleRate / 2.0))
        let maxFreq = max(minFreq, min(maxFrequency, sampleRate / 2.0))

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
                print(
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
}
