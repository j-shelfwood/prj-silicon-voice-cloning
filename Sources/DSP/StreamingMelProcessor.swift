import Accelerate
import Foundation
import Utilities
import os.lock

/// A class for processing audio in real-time chunks to produce mel-spectrograms.
/// This is optimized for streaming use cases where audio arrives in small buffers.
public class StreamingMelProcessor: @unchecked Sendable {
    // Configuration parameters
    private let fftSize: Int
    private let hopSize: Int
    private let sampleRate: Float
    private let melBands: Int
    private let minFrequency: Float
    private let maxFrequency: Float

    // Processing components
    private let fftProcessor: FFTProcessor
    private let melConverter: MelSpectrogramConverter

    // Pre-allocated frame buffer for extraction
    private var frameBuffer: UnsafeMutablePointer<Float>

    // Audio buffer
    private var audioBuffer: [Float] = []
    private var bufferLock = os_unfair_lock()

    // Caching for performance
    private var melCache: [String: [[Float]]] = [:]
    private var logMelCache: [String: [[Float]]] = [:]
    private var cacheLock = os_unfair_lock()

    // Pre-allocated spectrogram buffer for batch processing
    private var spectrogramBuffer: [[Float]] = []

    // Maximum buffer size to prevent memory issues
    private let maxBufferSize = 1_000_000  // ~23 seconds at 44.1kHz

    /**
     Initialize a new StreamingMelProcessor.

     - Parameters:
        - fftSize: Size of the FFT window
        - hopSize: Hop size between frames
        - sampleRate: Sample rate of the audio
        - melBands: Number of mel bands
        - minFrequency: Minimum frequency for mel bands
        - maxFrequency: Maximum frequency for mel bands
     */
    public init(
        fftSize: Int = 1024,
        hopSize: Int = 256,
        sampleRate: Float = 44100,
        melBands: Int = 80,
        minFrequency: Float = 0,
        maxFrequency: Float = 8000
    ) {
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.sampleRate = sampleRate
        self.melBands = melBands
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency

        self.fftProcessor = FFTProcessor(fftSize: fftSize)
        self.melConverter = MelSpectrogramConverter(
            sampleRate: sampleRate,
            melBands: melBands,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency
        )

        // Allocate frame buffer
        self.frameBuffer = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
    }

    deinit {
        // Free the frame buffer
        frameBuffer.deallocate()
    }

    /**
     Add new audio samples to the buffer.

     - Parameter samples: New audio samples to add
     */
    public func addSamples(_ samples: [Float]) {
        os_unfair_lock_lock(&bufferLock)
        defer { os_unfair_lock_unlock(&bufferLock) }

        // Reserve capacity to avoid multiple reallocations
        if audioBuffer.capacity < audioBuffer.count + samples.count {
            audioBuffer.reserveCapacity(audioBuffer.count + samples.count)
        }

        audioBuffer.append(contentsOf: samples)

        // Trim buffer if it gets too large
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(audioBuffer.count - maxBufferSize)
        }

        // Clear caches when new samples are added
        os_unfair_lock_lock(&cacheLock)
        melCache.removeAll(keepingCapacity: true)
        logMelCache.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&cacheLock)
    }

    /**
     Generate a cache key for the current state.

     - Parameter frameCount: Number of frames to process
     - Returns: A unique cache key
     */
    private func cacheKey(frameCount: Int) -> String {
        return "frames_\(frameCount)_buffer_\(audioBuffer.count)"
    }

    /**
     Process audio buffer to generate mel spectrogram frames.

     - Parameter frameCount: Number of frames to generate
     - Returns: Array of mel spectrogram frames
     */
    public func processMelSpectrogram(frameCount: Int) -> [[Float]] {
        // Check cache first
        let key = cacheKey(frameCount: frameCount)

        os_unfair_lock_lock(&cacheLock)
        if let cached = melCache[key] {
            os_unfair_lock_unlock(&cacheLock)
            return cached
        }
        os_unfair_lock_unlock(&cacheLock)

        // Lock buffer for reading
        os_unfair_lock_lock(&bufferLock)
        let buffer = audioBuffer
        os_unfair_lock_unlock(&bufferLock)

        // Check if we have enough samples
        let samplesNeeded = fftSize + (frameCount - 1) * hopSize
        guard buffer.count >= samplesNeeded else {
            return []
        }

        // Pre-allocate or resize the spectrogram buffer if needed
        if spectrogramBuffer.count < frameCount {
            spectrogramBuffer = [[Float]](
                repeating: [Float](repeating: 0.0, count: fftSize / 2),
                count: frameCount
            )
        }

        // Process frames using optimized extraction
        buffer.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }

            for i in 0..<frameCount {
                let startIdx = buffer.count - samplesNeeded + i * hopSize

                // Clear the frame buffer
                var zero: Float = 0.0
                vDSP_vfill(&zero, frameBuffer, 1, vDSP_Length(fftSize))

                // Copy frame data using vDSP
                vDSP_mmov(
                    baseAddress.advanced(by: startIdx),
                    frameBuffer,
                    vDSP_Length(fftSize),
                    1,
                    vDSP_Length(fftSize),
                    vDSP_Length(1)
                )

                // Create a temporary array from the buffer for FFT processing
                let frame = Array(UnsafeBufferPointer(start: frameBuffer, count: fftSize))
                spectrogramBuffer[i] = fftProcessor.performFFT(inputBuffer: frame)
            }
        }

        // Convert to mel spectrogram using batch processing
        let melSpectrogram = melConverter.specToMelSpec(
            spectrogram: spectrogramBuffer[0..<frameCount].map { $0 })

        // Cache the result
        os_unfair_lock_lock(&cacheLock)
        melCache[key] = melSpectrogram
        os_unfair_lock_unlock(&cacheLock)

        return melSpectrogram
    }

    /**
     Process audio buffer to generate mel spectrogram frames.

     - Returns: Tuple containing mel spectrogram frames and number of samples consumed
     */
    public func processMelSpectrogram() -> ([[Float]], Int) {
        // Determine how many frames we can process
        os_unfair_lock_lock(&bufferLock)
        let bufferSize = audioBuffer.count
        os_unfair_lock_unlock(&bufferLock)

        if bufferSize < fftSize {
            return ([], 0)
        }

        let frameCount = (bufferSize - fftSize) / hopSize + 1
        let melSpectrogram = processMelSpectrogram(frameCount: frameCount)
        let samplesConsumed = frameCount > 0 ? fftSize + (frameCount - 1) * hopSize : 0

        return (melSpectrogram, samplesConsumed)
    }

    /**
     Process audio buffer to generate mel spectrogram frames with minimum frame count.

     - Parameter minFrames: Minimum number of frames to generate
     - Returns: Tuple containing mel spectrogram frames and number of samples consumed
     */
    public func processMelSpectrogram(minFrames: Int) -> ([[Float]], Int) {
        let melSpectrogram = processMelSpectrogram(frameCount: minFrames)
        let samplesConsumed =
            melSpectrogram.count > 0 ? fftSize + (melSpectrogram.count - 1) * hopSize : 0

        return (melSpectrogram, samplesConsumed)
    }

    /**
     Process audio buffer to generate log-mel spectrogram frames.

     - Parameters:
        - frameCount: Number of frames to generate
        - ref: Reference value for log scaling
        - minLevel: Minimum level for clipping
        - minDb: Minimum dB value for output clipping (default: -80.0)
        - maxDb: Maximum dB value for output clipping (default: 0.0)
     - Returns: Array of log-mel spectrogram frames
     */
    public func processLogMelSpectrogram(
        frameCount: Int,
        ref: Float = 1.0,
        minLevel: Float = 1e-5,
        minDb: Float = -80.0,
        maxDb: Float = 0.0
    ) -> [[Float]] {
        // Check cache first
        let key =
            "\(cacheKey(frameCount: frameCount))_ref_\(ref)_min_\(minLevel)_minDb_\(minDb)_maxDb_\(maxDb)"

        os_unfair_lock_lock(&cacheLock)
        if let cached = logMelCache[key] {
            os_unfair_lock_unlock(&cacheLock)
            return cached
        }
        os_unfair_lock_unlock(&cacheLock)

        // Get mel spectrogram
        let melFrames = processMelSpectrogram(frameCount: frameCount)

        // Convert to log scale
        let logMelFrames = melConverter.melToLogMel(
            melSpectrogram: melFrames, ref: ref, floor: minLevel, minDb: minDb, maxDb: maxDb)

        // Cache the result
        os_unfair_lock_lock(&cacheLock)
        logMelCache[key] = logMelFrames
        os_unfair_lock_unlock(&cacheLock)

        return logMelFrames
    }

    /**
     Process audio buffer to generate log-mel spectrogram frames.

     - Parameters:
        - minDb: Minimum dB value for output clipping (default: -80.0)
        - maxDb: Maximum dB value for output clipping (default: 0.0)
     - Returns: Tuple containing log-mel spectrogram frames and number of samples consumed
     */
    public func processLogMelSpectrogram(
        minDb: Float = -80.0,
        maxDb: Float = 0.0
    ) -> ([[Float]], Int) {
        // Determine how many frames we can process
        os_unfair_lock_lock(&bufferLock)
        let bufferSize = audioBuffer.count
        os_unfair_lock_unlock(&bufferLock)

        if bufferSize < fftSize {
            return ([], 0)
        }

        let frameCount = (bufferSize - fftSize) / hopSize + 1
        let logMelSpectrogram = processLogMelSpectrogram(
            frameCount: frameCount,
            minDb: minDb,
            maxDb: maxDb
        )
        let samplesConsumed = frameCount > 0 ? fftSize + (frameCount - 1) * hopSize : 0

        return (logMelSpectrogram, samplesConsumed)
    }

    /**
     Reset the processor by clearing the audio buffer and caches.
     */
    public func reset() {
        os_unfair_lock_lock(&bufferLock)
        audioBuffer.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&bufferLock)

        os_unfair_lock_lock(&cacheLock)
        melCache.removeAll(keepingCapacity: true)
        logMelCache.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&cacheLock)
    }

    /**
     Get the current buffer length.

     - Returns: Number of samples in the buffer
     */
    public func getBufferLength() -> Int {
        os_unfair_lock_lock(&bufferLock)
        defer { os_unfair_lock_unlock(&bufferLock) }

        return audioBuffer.count
    }
}
