import Accelerate
import Foundation
import Utilities
import os.lock

/// A class for generating spectrograms from audio signals using FFT analysis.
/// This class handles the conversion of time-domain audio signals into
/// time-frequency representations (spectrograms).
public class SpectrogramGenerator {
    private let fftProcessor: FFTProcessor
    private let defaultHopSize: Int

    // Pre-allocated buffer for frame extraction
    private var frameBuffer: [Float]

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

        // Initialize buffer pool
        initializeBufferPool(fftSize: fftSize)
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
            print(
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

        // Process each frame
        for i in 0..<numFrames {
            let startIdx = i * hopSize
            let endIdx = min(startIdx + fftSize, inputBuffer.count)

            if endIdx - startIdx == fftSize {
                // Fast path: direct slice without copying
                // Use withUnsafeBufferPointer for better performance
                let frame = inputBuffer.withUnsafeBufferPointer { bufferPtr in
                    return Array(
                        UnsafeBufferPointer(
                            start: bufferPtr.baseAddress!.advanced(by: startIdx),
                            count: fftSize))
                }
                spectrogram[i] = fftProcessor.performFFT(inputBuffer: frame)
            } else {
                // Partial frame: reset buffer, copy available samples, and zero-pad
                // Clear the buffer using vDSP for better performance
                var zero: Float = 0.0
                vDSP_vfill(&zero, &frameBuffer, 1, vDSP_Length(fftSize))

                let availableSamples = endIdx - startIdx
                if availableSamples > 0 {
                    // Copy available samples using vDSP for better performance
                    inputBuffer.withUnsafeBufferPointer { bufferPtr in
                        frameBuffer.withUnsafeMutableBufferPointer { framePtr in
                            vDSP_mmov(
                                bufferPtr.baseAddress!.advanced(by: startIdx),
                                framePtr.baseAddress!,
                                vDSP_Length(availableSamples),
                                1,
                                vDSP_Length(availableSamples),
                                vDSP_Length(fftSize)
                            )
                        }
                    }
                }

                spectrogram[i] = fftProcessor.performFFT(inputBuffer: frameBuffer)
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
            print(
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
        var lock = os_unfair_lock()

        // Determine optimal batch size based on number of frames
        let batchSize = max(1, min(4, numFrames / 8))
        let batches = (numFrames + batchSize - 1) / batchSize

        // Process frames in parallel batches
        for batchIndex in 0..<batches {
            queue.async(group: group) {
                let startFrame = batchIndex * batchSize
                let endFrame = min(startFrame + batchSize, numFrames)

                for i in startFrame..<endFrame {
                    let startIdx = i * hopSize
                    let endIdx = min(startIdx + fftSize, inputBuffer.count)

                    var frameResult: [Float]

                    if endIdx - startIdx == fftSize {
                        // Fast path: direct slice without copying
                        // Use withUnsafeBufferPointer for better performance
                        let frame = inputBuffer.withUnsafeBufferPointer { bufferPtr in
                            return Array(
                                UnsafeBufferPointer(
                                    start: bufferPtr.baseAddress!.advanced(by: startIdx),
                                    count: fftSize))
                        }
                        frameResult = self.fftProcessor.performFFT(inputBuffer: frame)
                    } else {
                        // Partial frame: get a buffer from the pool
                        var localFrameBuffer = self.getBufferFromPool()

                        // Clear the buffer using vDSP
                        var zero: Float = 0.0
                        vDSP_vfill(&zero, &localFrameBuffer, 1, vDSP_Length(fftSize))

                        let availableSamples = endIdx - startIdx
                        if availableSamples > 0 {
                            // Copy available samples using vDSP
                            inputBuffer.withUnsafeBufferPointer { bufferPtr in
                                localFrameBuffer.withUnsafeMutableBufferPointer { framePtr in
                                    vDSP_mmov(
                                        bufferPtr.baseAddress!.advanced(by: startIdx),
                                        framePtr.baseAddress!,
                                        vDSP_Length(availableSamples),
                                        1,
                                        vDSP_Length(availableSamples),
                                        vDSP_Length(fftSize)
                                    )
                                }
                            }
                        }

                        frameResult = self.fftProcessor.performFFT(inputBuffer: localFrameBuffer)
                    }

                    // Thread-safe update of the spectrogram array
                    os_unfair_lock_lock(&lock)
                    spectrogram[i] = frameResult
                    os_unfair_lock_unlock(&lock)
                }
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
