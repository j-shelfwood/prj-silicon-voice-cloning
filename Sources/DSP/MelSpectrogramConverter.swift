import Accelerate
import Foundation
import Utilities
import os.lock

/// A class for converting linear frequency spectrograms to mel-scale spectrograms.
/// This class handles the creation and application of mel filterbanks for audio analysis.
public class MelSpectrogramConverter {
    private let sampleRate: Float
    private let melBands: Int
    private let minFrequency: Float
    private let maxFrequency: Float
    private let useHTK: Bool
    private var melFilterbank: [[Float]] = []

    // Cache for vectorized operations
    private var flatFilterbank: [Float]?
    private var filterBankStrides: [Int]?
    private var lastSpectrogramWidth: Int?

    // Pre-allocated buffers for processing
    private var processedBuffer: [Float]?
    private var resultBuffer: [Float]?

    // Thread safety
    private var filterBankLock = os_unfair_lock()

    // Cache for results
    private var resultCache: [String: [[Float]]] = [:]
    private var cacheMaxSize = 5
    private var cacheLock = os_unfair_lock()

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
     Generate a hash key for caching based on input parameters
     */
    private func cacheKey(spectrogram: [[Float]], operation: String) -> String {
        guard !spectrogram.isEmpty else { return "" }

        // Use dimensions and a sample of values as the key
        let rows = spectrogram.count
        let cols = spectrogram[0].count

        // Sample a few values from the spectrogram
        var samples = ""
        let sampleRows = min(3, rows)
        let sampleCols = min(3, cols)

        for i in 0..<sampleRows {
            let rowIndex = (i * rows) / sampleRows
            for j in 0..<sampleCols {
                let colIndex = (j * cols) / sampleCols
                samples += String(format: "%.2f", spectrogram[rowIndex][colIndex])
            }
        }

        return "\(operation)_\(rows)_\(cols)_\(samples)"
    }

    /**
     Check if result is in cache
     */
    private func getCachedResult(key: String) -> [[Float]]? {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        return resultCache[key]
    }

    /**
     Store result in cache
     */
    private func cacheResult(key: String, result: [[Float]]) {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        // If cache is full, remove oldest entry
        if resultCache.count >= cacheMaxSize {
            let firstKey = resultCache.keys.first ?? ""
            resultCache.removeValue(forKey: firstKey)
        }

        resultCache[key] = result
    }

    /**
     Convert a linear frequency spectrogram to a mel-scaled spectrogram

     - Parameter spectrogram: Linear frequency spectrogram (time x frequency)
     - Returns: Mel-scaled spectrogram (time x mel_bands)
     */
    public func specToMelSpec(spectrogram: [[Float]]) -> [[Float]] {
        // Check if spectrogram is empty
        guard !spectrogram.isEmpty && !spectrogram[0].isEmpty else {
            LoggerUtility.debug("Error: Empty spectrogram provided to specToMelSpec")
            return []
        }

        // Check cache first
        let cacheKey = self.cacheKey(spectrogram: spectrogram, operation: "mel")
        if let cached = getCachedResult(key: cacheKey) {
            return cached
        }

        // Create mel filterbank if not already created
        if melFilterbank.isEmpty {
            melFilterbank = createMelFilterbank(fftSize: spectrogram[0].count * 2)
        }

        // Check if filterbank creation was successful
        guard !melFilterbank.isEmpty else {
            LoggerUtility.debug("Error: Failed to create mel filterbank")
            return []
        }

        // Get dimensions
        let numFrames = spectrogram.count
        let numBins = spectrogram[0].count

        // Pre-allocate the mel spectrogram
        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: melBands), count: numFrames)

        // Check if we need to prepare the flat filterbank for vectorized operations
        os_unfair_lock_lock(&filterBankLock)
        if flatFilterbank == nil || lastSpectrogramWidth != numBins {
            // Flatten the filterbank for vectorized operations
            flatFilterbank = [Float](repeating: 0.0, count: melBands * numBins)
            filterBankStrides = [Int](repeating: 0, count: melBands)

            for i in 0..<melBands {
                filterBankStrides![i] = i * numBins
                for j in 0..<numBins {
                    flatFilterbank![i * numBins + j] = melFilterbank[i][j]
                }
            }

            lastSpectrogramWidth = numBins
        }

        // We don't need these buffers for the current implementation, but keep the properties for future use
        if processedBuffer == nil || processedBuffer!.count != numBins {
            processedBuffer = [Float](repeating: 0.0, count: numBins)
        }

        if resultBuffer == nil || resultBuffer!.count != melBands {
            resultBuffer = [Float](repeating: 0.0, count: melBands)
        }

        // Create a buffer for the filterbank slice to avoid creating a new array for each dot product
        var filterBankSlice = [Float](repeating: 0.0, count: numBins)

        let localFlatFilterbank = flatFilterbank!
        let localFilterBankStrides = filterBankStrides!
        os_unfair_lock_unlock(&filterBankLock)

        // Process each frame using vectorized operations
        for i in 0..<numFrames {
            // Get the current frame
            let frame = spectrogram[i]

            // Use vDSP for matrix multiplication (dot product for each mel band)
            for j in 0..<melBands {
                let filterBankOffset = localFilterBankStrides[j]

                // Copy the filterbank slice to the buffer
                for k in 0..<numBins {
                    filterBankSlice[k] = localFlatFilterbank[filterBankOffset + k]
                }

                // Perform dot product: sum(frame[k] * filterbank[j][k])
                var sum: Float = 0.0
                vDSP_dotpr(frame, 1, filterBankSlice, 1, &sum, vDSP_Length(numBins))

                // Replace NaN values with zeros
                melSpectrogram[i][j] = sum.isNaN ? 0.0 : sum
            }
        }

        // Cache the result
        cacheResult(key: cacheKey, result: melSpectrogram)

        return melSpectrogram
    }

    /**
     Convert a mel-spectrogram to a log-mel-spectrogram

     - Parameters:
        - melSpectrogram: Mel-scaled spectrogram
        - ref: Reference value for log scaling (default: 1.0)
        - floor: Floor value to clip small values (default: 1e-5)
        - minDb: Minimum dB value to clip results (default: -80.0)
        - maxDb: Maximum dB value to clip results (default: 0.0)
     - Returns: Log-mel-spectrogram
     */
    public func melToLogMel(
        melSpectrogram: [[Float]],
        ref: Float = 1.0,
        floor: Float = 1e-5,
        minDb: Float = -80.0,
        maxDb: Float = 0.0
    ) -> [[Float]] {
        // Check if mel spectrogram is empty
        guard !melSpectrogram.isEmpty && !melSpectrogram[0].isEmpty else {
            LoggerUtility.debug("Error: Empty mel-spectrogram provided to melToLogMel")
            return []
        }

        // Check cache first
        let cacheKey = self.cacheKey(
            spectrogram: melSpectrogram, operation: "logmel_\(ref)_\(floor)_\(minDb)_\(maxDb)")
        if let cached = getCachedResult(key: cacheKey) {
            return cached
        }

        // Get dimensions
        let numFrames = melSpectrogram.count
        let numBands = melSpectrogram[0].count
        let totalElements = numFrames * numBands

        // Flatten the mel spectrogram for vectorized operations
        var flatMel = [Float](repeating: 0.0, count: totalElements)
        var flatLogMel = [Float](repeating: 0.0, count: totalElements)

        // Copy data to flat array
        for i in 0..<numFrames {
            let rowOffset = i * numBands
            for j in 0..<numBands {
                flatMel[rowOffset + j] = melSpectrogram[i][j]
            }
        }

        // Create mutable copies of the constants for vDSP functions
        var floorValue = floor
        var refValue = ref
        var minDbValue = minDb
        var maxDbValue = maxDb

        // Apply floor (threshold) using vDSP_vthres
        vDSP_vthres(flatMel, 1, &floorValue, &flatMel, 1, vDSP_Length(totalElements))

        // Divide by reference value using vDSP_vsdiv
        vDSP_vsdiv(flatMel, 1, &refValue, &flatMel, 1, vDSP_Length(totalElements))

        // Compute log10 using vForce
        var count = Int32(totalElements)
        vvlog10f(&flatLogMel, flatMel, &count)

        // Multiply by 10.0 using vDSP_vsmul
        var ten: Float = 10.0
        vDSP_vsmul(flatLogMel, 1, &ten, &flatLogMel, 1, vDSP_Length(totalElements))

        // Clip to range [minDb, maxDb] using vDSP_vclip
        vDSP_vclip(
            flatLogMel, 1, &minDbValue, &maxDbValue, &flatLogMel, 1, vDSP_Length(totalElements))

        // Reshape back to 2D array
        var logMelSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: numBands), count: numFrames)
        for i in 0..<numFrames {
            let rowOffset = i * numBands
            for j in 0..<numBands {
                logMelSpectrogram[i][j] = flatLogMel[rowOffset + j]
            }
        }

        // Cache the result
        cacheResult(key: cacheKey, result: logMelSpectrogram)

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

        // For each mel band
        for i in 0..<melBands {
            // For each FFT bin
            for j in 0..<numBins {
                // Lower and upper slopes
                if j > binPoints[i] && j < binPoints[i + 1] {
                    // Lower slope
                    filterbank[i][j] =
                        Float(j - binPoints[i]) / Float(binPoints[i + 1] - binPoints[i])
                } else if j > binPoints[i + 1] && j < binPoints[i + 2] {
                    // Upper slope
                    filterbank[i][j] =
                        Float(binPoints[i + 2] - j) / Float(binPoints[i + 2] - binPoints[i + 1])
                }
            }

            // Normalize the filterbank row to ensure area under the triangle is 1
            var rowSum: Float = 0.0
            vDSP_sve(filterbank[i], 1, &rowSum, vDSP_Length(numBins))

            if rowSum > 0.0 {
                // Use a temporary scalar for the reciprocal
                let recipRowSum = 1.0 / rowSum

                // Apply normalization to each element in the row
                for j in 0..<numBins {
                    filterbank[i][j] *= recipRowSum
                }
            }
        }

        return filterbank
    }
}
