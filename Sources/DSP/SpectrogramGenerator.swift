import Accelerate
import Foundation
import Utilities
import os.lock

/// A class for generating spectrograms from audio signals using FFT analysis.
/// This class handles the conversion of time-domain audio signals into
/// time-frequency representations (spectrograms).
public class SpectrogramGenerator: @unchecked Sendable {
    private let fftProcessor: FFTProcessor
    private let defaultHopSize: Int

    // Pre-allocated buffer for frame extraction
    private var frameBuffer: [Float]

    // Pre-allocated buffer for frame extraction optimization
    private var extractionBuffer: UnsafeMutablePointer<Float>?
    private var extractionBufferSize: Int = 0

    // Buffer pool for parallel processing
    private var bufferPool: [[Float]] = []
    private var bufferPoolIndex = 0
    private var bufferPoolLock = os_unfair_lock()
    private let bufferPoolSize = 8

    // Cache for spectrogram results
    private var spectrogramCache: [String: [[Float]]] = [:]
    private var cacheMaxSize = 5
    private var cacheLock = os_unfair_lock()

    /**
     Initialize a new SpectrogramGenerator instance.

     - Parameters:
        - fftSize: Size of the FFT to perform (must be a power of 2)
        - hopSize: Number of samples to advance between FFT windows (default: fftSize/4)
     */
    public init(fftSize: Int = 1024, hopSize: Int? = nil) {
        self.fftProcessor = FFTProcessor(fftSize: fftSize)
        self.defaultHopSize = hopSize ?? fftSize / 4
        self.frameBuffer = [Float](repeating: 0.0, count: fftSize)

        // Initialize extraction buffer
        self.extractionBuffer = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        self.extractionBufferSize = fftSize

        // Initialize buffer pool
        initializeBufferPool(fftSize: fftSize)
    }

    deinit {
        // Free the extraction buffer
        if let buffer = extractionBuffer {
            buffer.deallocate()
            extractionBuffer = nil
        }
    }

    /**
     Initialize the buffer pool with pre-allocated buffers
     */
    private func initializeBufferPool(fftSize: Int) {
        bufferPool = (0..<bufferPoolSize).map { _ in
            [Float](repeating: 0.0, count: fftSize)
        }
    }

    /**
     Get a buffer from the pool

     - Returns: A pre-allocated buffer from the pool
     */
    private func getBufferFromPool() -> [Float] {
        os_unfair_lock_lock(&bufferPoolLock)
        defer { os_unfair_lock_unlock(&bufferPoolLock) }

        let buffer = bufferPool[bufferPoolIndex]
        bufferPoolIndex = (bufferPoolIndex + 1) % bufferPool.count
        return buffer
    }

    /**
     Generate a hash key for caching based on input parameters
     */
    private func cacheKey(inputBuffer: [Float], hopSize: Int) -> String {
        // Use first few samples, length, and hopSize as a simple hash
        let sampleCount = min(10, inputBuffer.count)
        var samples = ""
        for i in 0..<sampleCount {
            samples += String(format: "%.2f", inputBuffer[i])
        }
        return "\(samples)_\(inputBuffer.count)_\(hopSize)"
    }

    /**
     Check if result is in cache
     */
    private func getCachedResult(key: String) -> [[Float]]? {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        return spectrogramCache[key]
    }

    /**
     Store result in cache
     */
    private func cacheResult(key: String, result: [[Float]]) {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        // If cache is full, remove oldest entry
        if spectrogramCache.count >= cacheMaxSize {
            let firstKey = spectrogramCache.keys.first ?? ""
            spectrogramCache.removeValue(forKey: firstKey)
        }

        spectrogramCache[key] = result
    }

    /**
     Generate a spectrogram from the input buffer.

     - Parameters:
        - inputBuffer: Audio samples in time domain
        - hopSize: Optional custom hop size (if not provided, uses the default)
     - Returns: 2D array representing the spectrogram (time x frequency)
     */
    public func generateSpectrogram(inputBuffer: [Float], hopSize: Int? = nil) -> [[Float]] {
        let hopSize = hopSize ?? defaultHopSize
        let fftSize = fftProcessor.size

        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            LoggerUtility.debug(
                "Error: Input buffer too small for spectrogram generation. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return []
        }

        // Check cache first
        let key = cacheKey(inputBuffer: inputBuffer, hopSize: hopSize)
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        // Calculate number of frames
        let numFrames = max(1, (inputBuffer.count - fftSize) / hopSize + 1)

        // Pre-allocate the entire spectrogram array
        var spectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: fftSize / 2), count: numFrames)

        // Ensure extraction buffer is large enough
        if extractionBufferSize < fftSize {
            if let buffer = extractionBuffer {
                buffer.deallocate()
            }
            extractionBuffer = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
            extractionBufferSize = fftSize
        }

        // Process each frame using optimized extraction
        inputBuffer.withUnsafeBufferPointer { inputPtr in
            guard let inputBaseAddress = inputPtr.baseAddress else { return }

            for i in 0..<numFrames {
                let startIdx = i * hopSize
                let endIdx = min(startIdx + fftSize, inputBuffer.count)
                let availableSamples = endIdx - startIdx

                if availableSamples == fftSize {
                    // Fast path: direct extraction without intermediate array allocation
                    // Extract frame directly to a temporary array using vDSP_mmov
                    vDSP_mmov(
                        inputBaseAddress.advanced(by: startIdx),
                        extractionBuffer!,
                        vDSP_Length(fftSize),
                        1,
                        vDSP_Length(fftSize),
                        vDSP_Length(1)
                    )

                    // Create a temporary array from the buffer for FFT processing
                    // This avoids unsafe memory access in the FFT processor
                    let frame = Array(UnsafeBufferPointer(start: extractionBuffer, count: fftSize))
                    spectrogram[i] = fftProcessor.performFFT(inputBuffer: frame)
                } else {
                    // Partial frame: clear buffer and copy available samples
                    // Clear the buffer using vDSP for better performance
                    var zero: Float = 0.0
                    vDSP_vfill(&zero, extractionBuffer!, 1, vDSP_Length(fftSize))

                    if availableSamples > 0 {
                        // Copy available samples using vDSP for better performance
                        vDSP_mmov(
                            inputBaseAddress.advanced(by: startIdx),
                            extractionBuffer!,
                            vDSP_Length(availableSamples),
                            1,
                            vDSP_Length(availableSamples),
                            vDSP_Length(1)
                        )
                    }

                    // Create a temporary array from the buffer for FFT processing
                    let frame = Array(UnsafeBufferPointer(start: extractionBuffer, count: fftSize))
                    spectrogram[i] = fftProcessor.performFFT(inputBuffer: frame)
                }
            }
        }

        // Cache the result
        cacheResult(key: key, result: spectrogram)

        return spectrogram
    }

    /**
     Generate a spectrogram from the input buffer using parallel processing.

     - Parameters:
        - inputBuffer: Audio samples in time domain
        - hopSize: Optional custom hop size (if not provided, uses the default)
        - useParallel: Whether to use parallel processing (default: true)
     - Returns: 2D array representing the spectrogram (time x frequency)
     */
    public func generateSpectrogramParallel(
        inputBuffer: [Float],
        hopSize: Int? = nil,
        useParallel: Bool = true
    ) -> [[Float]] {
        let hopSize = hopSize ?? defaultHopSize
        let fftSize = fftProcessor.size

        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            LoggerUtility.debug(
                "Error: Input buffer too small for spectrogram generation. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return []
        }

        // Check cache first
        let key = cacheKey(inputBuffer: inputBuffer, hopSize: hopSize) + "_parallel"
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        // Calculate number of frames
        let numFrames = max(1, (inputBuffer.count - fftSize) / hopSize + 1)

        // If the input is small or parallel processing is disabled, use the sequential version
        if numFrames < 8 || !useParallel {
            return generateSpectrogram(inputBuffer: inputBuffer, hopSize: hopSize)
        }

        // Pre-allocate the entire spectrogram array
        var spectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: fftSize / 2), count: numFrames)

        // Use concurrent processing for larger inputs
        let queue = DispatchQueue(label: "com.spectrogramGenerator.queue", attributes: .concurrent)
        let group = DispatchGroup()

        // Create a lock for thread-safe access to the spectrogram array
        var spectrogramLock = os_unfair_lock_s()

        // Determine optimal batch size based on number of frames and available cores
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let batchSize = max(1, min(numFrames / processorCount, 8))
        let batches = (numFrames + batchSize - 1) / batchSize

        // Create a copy of the input buffer to avoid Sendable warnings
        let inputCopy = Array(inputBuffer)

        // Process frames in parallel batches
        for batchIndex in 0..<batches {
            queue.async(group: group) { [self] in
                let startFrame = batchIndex * batchSize
                let endFrame = min(startFrame + batchSize, numFrames)

                // Allocate a local extraction buffer for this thread
                let localBuffer = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
                defer { localBuffer.deallocate() }

                // Create a local array for processing
                var localResults = [[Float]](repeating: [], count: endFrame - startFrame)
                var localIndex = 0

                for i in startFrame..<endFrame {
                    let startIdx = i * hopSize
                    let endIdx = min(startIdx + fftSize, inputCopy.count)
                    let availableSamples = endIdx - startIdx

                    // Clear the buffer using vDSP
                    var zero: Float = 0.0
                    vDSP_vfill(&zero, localBuffer, 1, vDSP_Length(fftSize))

                    if availableSamples > 0 {
                        // Copy available samples using vDSP - using the copied input buffer
                        inputCopy.withUnsafeBufferPointer { bufferPtr in
                            guard let inputBaseAddress = bufferPtr.baseAddress else { return }
                            vDSP_mmov(
                                inputBaseAddress.advanced(by: startIdx),
                                localBuffer,
                                vDSP_Length(availableSamples),
                                1,
                                vDSP_Length(availableSamples),
                                vDSP_Length(1)
                            )
                        }
                    }

                    // Create a temporary array from the buffer for FFT processing
                    let frame = Array(UnsafeBufferPointer(start: localBuffer, count: fftSize))
                    let frameResult = self.fftProcessor.performFFT(inputBuffer: frame)

                    // Store in local results array
                    localResults[localIndex] = frameResult
                    localIndex += 1
                }

                // Thread-safe update of the spectrogram array - only lock once per batch
                os_unfair_lock_lock(&spectrogramLock)
                for (offset, result) in localResults.enumerated() {
                    if !result.isEmpty {
                        spectrogram[startFrame + offset] = result
                    }
                }
                os_unfair_lock_unlock(&spectrogramLock)
            }
        }

        // Wait for all tasks to complete
        group.wait()

        // Cache the result
        cacheResult(key: key, result: spectrogram)

        return spectrogram
    }

    /// Get the size of the FFT used by this generator
    public var fftSize: Int {
        return fftProcessor.size
    }
}
