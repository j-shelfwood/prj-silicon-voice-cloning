import AudioToolbox
import Foundation
import Utilities
import os.lock  // Import for os_unfair_lock

/// Manages a real-time audio processing pipeline that captures audio input,
/// processes it, and sends it to audio output with minimal latency.
public class RealTimeAudioPipeline {

    /// Configuration options for the audio pipeline
    public struct Configuration {
        public let sampleRate: Double
        public let channelCount: UInt32
        public let bytesPerSample: UInt32
        public let bitsPerChannel: UInt32
        public let framesPerBuffer: UInt32
        public let bufferPoolSize: Int  // Added buffer pool size configuration

        public init(
            sampleRate: Double = 44100.0,
            channelCount: UInt32 = 1,
            bytesPerSample: UInt32 = 4,
            bitsPerChannel: UInt32 = 32,
            framesPerBuffer: UInt32 = 512,
            bufferPoolSize: Int = 8  // Default to 8 buffers in the pool
        ) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.bytesPerSample = bytesPerSample
            self.bitsPerChannel = bitsPerChannel
            self.framesPerBuffer = framesPerBuffer
            self.bufferPoolSize = bufferPoolSize
        }
    }

    // Use lazy initialization for processors
    private var _inputProcessor: AudioInputProcessor?
    private var _outputProcessor: AudioOutputProcessor?
    private let config: Configuration

    // Thread safety for running state
    private var stateLock = os_unfair_lock()
    private var _isRunning = false

    // Buffer pool for audio processing to reduce allocations
    private var bufferPool: [[Float]] = []
    private var bufferPoolIndex = 0
    private var bufferPoolLock = os_unfair_lock()

    // Lazily initialize the input processor
    private var inputProcessor: AudioInputProcessor {
        if _inputProcessor == nil {
            let inputConfig = AudioInputProcessor.Configuration(
                sampleRate: config.sampleRate,
                channelCount: config.channelCount,
                bytesPerSample: config.bytesPerSample,
                bitsPerChannel: config.bitsPerChannel,
                framesPerBuffer: config.framesPerBuffer
            )
            _inputProcessor = AudioInputProcessor(configuration: inputConfig)
        }
        return _inputProcessor!
    }

    // Lazily initialize the output processor
    private var outputProcessor: AudioOutputProcessor {
        if _outputProcessor == nil {
            let outputConfig = AudioOutputProcessor.Configuration(
                sampleRate: config.sampleRate,
                channelCount: config.channelCount,
                bytesPerSample: config.bytesPerSample,
                bitsPerChannel: config.bitsPerChannel,
                framesPerBuffer: config.framesPerBuffer
            )
            _outputProcessor = AudioOutputProcessor(configuration: outputConfig)
        }
        return _outputProcessor!
    }

    /// Audio processing callback that transforms input audio to output audio
    public var audioProcessingCallback: (([Float]) -> [Float])?

    /// Flag indicating if the pipeline is running
    public var isRunning: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }

        // Only check processors if we think we're running
        if !_isRunning {
            return false
        }

        // Verify processors are initialized and running
        guard let inputProc = _inputProcessor, let outputProc = _outputProcessor else {
            _isRunning = false
            return false
        }

        let actuallyRunning = inputProc.isRunning && outputProc.isRunning
        if !actuallyRunning {
            _isRunning = false
        }
        return actuallyRunning
    }

    /// Initializes a new RealTimeAudioPipeline instance
    /// - Parameter configuration: Configuration options for the audio pipeline
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        // Initialize the buffer pool
        initializeBufferPool()
    }

    deinit {
        stop()
    }

    /// Initialize the buffer pool with pre-allocated buffers
    private func initializeBufferPool() {
        let bufferSize = Int(config.framesPerBuffer)
        bufferPool = (0..<config.bufferPoolSize).map { _ in
            [Float](repeating: 0.0, count: bufferSize)
        }
    }

    /// Get a buffer from the pool
    private func getBufferFromPool() -> [Float] {
        os_unfair_lock_lock(&bufferPoolLock)
        defer { os_unfair_lock_unlock(&bufferPoolLock) }

        let buffer = bufferPool[bufferPoolIndex]
        bufferPoolIndex = (bufferPoolIndex + 1) % bufferPool.count
        return buffer
    }

    /// Sets up the connections between input and output processors
    private func setupPipeline() {
        // Only set up if not already done
        if inputProcessor.audioDataCallback == nil {
            // When input processor receives audio data, process it and send to output
            inputProcessor.audioDataCallback = { [weak self] inputBuffer in
                guard let self = self else { return }

                // Apply processing if callback is set, otherwise pass through
                let processedBuffer: [Float]
                if let processingCallback = self.audioProcessingCallback {
                    // Get a pre-allocated buffer for the result
                    var resultBuffer = self.getBufferFromPool()

                    // Process the input and copy to our buffer
                    let processed = processingCallback(inputBuffer)

                    // If the processed buffer is a different size, we can't use our pool
                    if processed.count == resultBuffer.count {
                        // Copy the data to our pre-allocated buffer
                        for i in 0..<processed.count {
                            resultBuffer[i] = processed[i]
                        }
                    } else {
                        // If sizes don't match, just use the returned buffer
                        resultBuffer = processed
                    }

                    processedBuffer = resultBuffer
                } else {
                    processedBuffer = inputBuffer
                }

                // Send to output
                self.outputProcessor.setOutputAudioBuffer(processedBuffer)
            }
        }

        if outputProcessor.audioDataProvider == nil {
            // Set up output processor to use the latest processed buffer
            outputProcessor.audioDataProvider = { [weak self] in
                guard let self = self else { return [] }
                return self.outputProcessor.getOutputAudioBuffer()
            }
        }
    }

    /// Starts the real-time audio pipeline
    /// - Returns: Boolean indicating success or failure
    public func start() -> Bool {
        // Set up the pipeline connections before starting
        setupPipeline()

        // Start output first to ensure it's ready to receive audio
        guard outputProcessor.start() else {
            LoggerUtility.debug("Failed to start audio output")
            return false
        }

        // Then start input to begin capturing
        guard inputProcessor.start() else {
            // If input fails, stop output
            outputProcessor.stop()
            LoggerUtility.debug("Failed to start audio input")
            return false
        }

        // Update running state
        os_unfair_lock_lock(&stateLock)
        _isRunning = true
        os_unfair_lock_unlock(&stateLock)

        LoggerUtility.debug("Real-time audio pipeline started")
        return true
    }

    /// Stops the real-time audio pipeline
    public func stop() {
        // Update running state first
        os_unfair_lock_lock(&stateLock)
        _isRunning = false
        os_unfair_lock_unlock(&stateLock)

        // Only stop if processors were initialized
        _inputProcessor?.stop()
        _outputProcessor?.stop()

        LoggerUtility.debug("Real-time audio pipeline stopped")
    }

    /// Plays a buffer of audio samples through the output device
    /// - Parameter buffer: Audio samples to play
    /// - Returns: Boolean indicating success or failure
    public func playAudio(_ buffer: [Float]) -> Bool {
        // This is a convenience method that delegates to the output processor
        return outputProcessor.playAudio(buffer)
    }

    // Cache for latency calculation to avoid recalculating frequently
    private var _cachedLatency: Double = 0.0
    private var _lastLatencyCalculationTime: TimeInterval = 0
    private let latencyCacheDuration: TimeInterval = 0.5  // Cache latency for 500ms

    /// Returns the measured latency of the audio processing pipeline in milliseconds
    public var measuredLatency: Double {
        // Check if we have a recent cached value
        let now = Date().timeIntervalSince1970
        if now - _lastLatencyCalculationTime < latencyCacheDuration {
            return _cachedLatency
        }

        // Only calculate if processors are initialized
        guard _inputProcessor != nil, _outputProcessor != nil else {
            return 0.0
        }

        let inputTimestamps = inputProcessor.getCaptureTimestamps()
        let outputTimestamps = outputProcessor.getPlaybackTimestamps()

        guard !inputTimestamps.isEmpty && !outputTimestamps.isEmpty else {
            return 0.0
        }

        let count = min(inputTimestamps.count, outputTimestamps.count)
        guard count > 0 else { return 0.0 }

        var totalLatency = 0.0
        for i in 0..<count {
            totalLatency += outputTimestamps[i] - inputTimestamps[i]
        }

        // Cache the result
        _cachedLatency = (totalLatency / Double(count)) * 1000.0  // Convert to milliseconds
        _lastLatencyCalculationTime = now

        return _cachedLatency
    }
}
