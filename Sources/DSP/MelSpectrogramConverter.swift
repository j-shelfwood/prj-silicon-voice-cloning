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
            Utilities.log("Error: Empty spectrogram provided to specToMelSpec")
            return []
        }

        let numFrames = spectrogram.count
        let numFreqBins = spectrogram[0].count

        // Create mel filterbank if not already created
        if melFilterbank == nil {
            melFilterbank = createMelFilterbank(
                fftSize: numFreqBins * 2  // Multiply by 2 because spectrogram has fftSize/2 bins
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
}
