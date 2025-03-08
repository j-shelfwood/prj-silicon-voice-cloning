import AudioToolbox
import Foundation
import Utilities
import os.lock

/// Manages audio output playback to the speakers using Core Audio's AudioUnit framework.
public class AudioOutputProcessor {

    /// Configuration options for audio output
    public struct Configuration {
        public let sampleRate: Double
        public let channelCount: UInt32
        public let bytesPerSample: UInt32
        public let bitsPerChannel: UInt32
        public let framesPerBuffer: UInt32
        public let bufferPoolSize: Int  // Added buffer pool size configuration
        public let maxTimestamps: Int  // Maximum number of timestamps to store

        public init(
            sampleRate: Double = 44100.0,
            channelCount: UInt32 = 1,
            bytesPerSample: UInt32 = 4,
            bitsPerChannel: UInt32 = 32,
            framesPerBuffer: UInt32 = 512,
            bufferPoolSize: Int = 8,  // Default to 8 buffers in the pool
            maxTimestamps: Int = 100  // Default to storing 100 timestamps
        ) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.bytesPerSample = bytesPerSample
            self.bitsPerChannel = bitsPerChannel
            self.framesPerBuffer = framesPerBuffer
            self.bufferPoolSize = bufferPoolSize
            self.maxTimestamps = maxTimestamps
        }

        /// Creates an AudioStreamBasicDescription with the current configuration
        public func createASBD() -> AudioStreamBasicDescription {
            var asbd = AudioStreamBasicDescription()
            asbd.mSampleRate = sampleRate
            asbd.mFormatID = kAudioFormatLinearPCM
            asbd.mFormatFlags =
                kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved
            asbd.mBytesPerPacket = bytesPerSample
            asbd.mFramesPerPacket = 1
            asbd.mBytesPerFrame = bytesPerSample
            asbd.mChannelsPerFrame = channelCount
            asbd.mBitsPerChannel = bitsPerChannel
            return asbd
        }
    }

    // Only create AudioUnitManager when needed
    internal var audioUnitManager: AudioUnitManager?
    internal let config: Configuration

    // Buffer management
    internal var outputAudioBuffer: [Float] = []
    internal var bufferLock = os_unfair_lock()

    // Buffer pool for reusing audio buffers
    private var bufferPool: [[Float]] = []
    private var bufferPoolIndex = 0
    private var bufferPoolLock = os_unfair_lock()

    // Timestamp management with circular buffer
    internal var playbackTimestamps: [Double] = []
    private var timestampIndex = 0
    private var timestampLock = os_unfair_lock()

    // Running state
    private var stateLock = os_unfair_lock()
    private var _isRunning = false

    /// Callback function for generating audio data
    public var audioDataProvider: (() -> [Float])?

    /// Flag indicating if the output processor is running
    public var isRunning: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _isRunning
    }

    /// Initializes a new AudioOutputProcessor instance
    /// - Parameter configuration: Configuration options for audio output
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        // No AudioUnitManager creation here - defer until start()

        // Initialize buffer pool
        initializeBufferPool()

        // Pre-allocate timestamp array
        playbackTimestamps = Array(repeating: 0.0, count: config.maxTimestamps)
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
    internal func getBufferFromPool() -> [Float] {
        os_unfair_lock_lock(&bufferPoolLock)
        defer { os_unfair_lock_unlock(&bufferPoolLock) }

        let buffer = bufferPool[bufferPoolIndex]
        bufferPoolIndex = (bufferPoolIndex + 1) % bufferPool.count
        return buffer
    }

    /// Add a timestamp to the circular buffer
    internal func addTimestamp(_ timestamp: Double) {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        playbackTimestamps[timestampIndex] = timestamp
        timestampIndex = (timestampIndex + 1) % config.maxTimestamps
    }

    /// Starts audio output to the default output device
    /// - Returns: Boolean indicating success or failure
    public func start() -> Bool {
        os_unfair_lock_lock(&stateLock)
        guard !_isRunning else {
            os_unfair_lock_unlock(&stateLock)
            LoggerUtility.debug("Audio output already running")
            return true
        }
        os_unfair_lock_unlock(&stateLock)

        // Create and configure the audio unit manager only when needed
        if audioUnitManager == nil {
            let auConfig = AudioUnitManager.Configuration(
                sampleRate: config.sampleRate,
                channelCount: config.channelCount,
                bytesPerSample: config.bytesPerSample,
                bitsPerChannel: config.bitsPerChannel,
                framesPerBuffer: config.framesPerBuffer
            )

            audioUnitManager = AudioUnitManager(type: .output, configuration: auConfig)
        }

        // Set up the render callback
        let outputCallbackStruct = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard audioUnitManager?.setup(renderCallback: outputCallbackStruct) == true else {
            LoggerUtility.debug("Failed to set up output audio unit")
            return false
        }

        guard audioUnitManager?.initialize() == true else {
            LoggerUtility.debug("Failed to initialize output audio unit")
            return false
        }

        guard audioUnitManager?.start() == true else {
            LoggerUtility.debug("Failed to start output audio unit")
            return false
        }

        os_unfair_lock_lock(&stateLock)
        _isRunning = true
        os_unfair_lock_unlock(&stateLock)

        LoggerUtility.debug("Audio output started")
        return true
    }

    /// Stops audio output and releases audio resources
    public func stop() {
        os_unfair_lock_lock(&stateLock)
        guard _isRunning else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        _isRunning = false
        os_unfair_lock_unlock(&stateLock)

        _ = audioUnitManager?.stop()
        audioUnitManager?.dispose()
        audioUnitManager = nil

        LoggerUtility.debug("Audio output stopped")
    }

    /// Plays a buffer of audio samples through the output device
    /// - Parameter buffer: Audio samples to play
    /// - Returns: Boolean indicating success or failure
    public func playAudio(_ buffer: [Float]) -> Bool {
        os_unfair_lock_lock(&stateLock)
        let currentlyRunning = _isRunning
        os_unfair_lock_unlock(&stateLock)

        guard !currentlyRunning else {
            LoggerUtility.debug(
                "Audio output is already running in real-time mode. Use the data provider instead."
            )
            return false
        }

        os_unfair_lock_lock(&bufferLock)
        outputAudioBuffer = buffer
        os_unfair_lock_unlock(&bufferLock)

        // Start output for playback
        if start() {
            // Calculate playback duration and wait
            let playbackDuration = Double(buffer.count) / config.sampleRate
            Thread.sleep(forTimeInterval: playbackDuration)

            // Stop after playback
            stop()

            LoggerUtility.debug(
                "Playback completed (simulated duration: \(String(format: "%.1f", playbackDuration)) seconds)"
            )
            return true
        }

        return false
    }

    /// Sets the output audio buffer
    /// - Parameter buffer: Audio buffer to set
    public func setOutputAudioBuffer(_ buffer: [Float]) {
        os_unfair_lock_lock(&bufferLock)
        outputAudioBuffer = buffer
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Gets the current output audio buffer
    /// - Returns: Array of audio samples
    public func getOutputAudioBuffer() -> [Float] {
        os_unfair_lock_lock(&bufferLock)
        defer { os_unfair_lock_unlock(&bufferLock) }
        return outputAudioBuffer
    }

    /// Returns the timestamps of played audio
    public func getPlaybackTimestamps() -> [Double] {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        // Return only the valid timestamps (non-zero)
        return playbackTimestamps.filter { $0 > 0 }
    }
}

/// Output render callback - called when audio output is needed
private func outputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

    let audioProcessor = Unmanaged<AudioOutputProcessor>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let ioData = ioData, ioData.pointee.mNumberBuffers > 0 else {
        return kAudioUnitErr_InvalidParameter
    }

    let outputBuffer = UnsafeMutableAudioBufferListPointer(ioData)[0]
    guard let outputDataRaw = outputBuffer.mData else {
        return kAudioUnitErr_InvalidParameter
    }

    let outputData = outputDataRaw.bindMemory(to: Float.self, capacity: Int(inNumberFrames))

    // Get audio data either from the buffer or the provider
    var processedBuffer: [Float] = []

    if let dataProvider = audioProcessor.audioDataProvider {
        // Get fresh data from the provider
        processedBuffer = dataProvider()
    } else {
        // Use the existing buffer
        os_unfair_lock_lock(&audioProcessor.bufferLock)
        processedBuffer = audioProcessor.outputAudioBuffer
        os_unfair_lock_unlock(&audioProcessor.bufferLock)
    }

    let timestamp = CFAbsoluteTimeGetCurrent()
    audioProcessor.addTimestamp(timestamp)

    // Copy data to the output buffer
    let copyLength = min(Int(inNumberFrames), processedBuffer.count)
    if copyLength > 0 {
        for i in 0..<copyLength {
            outputData[i] = processedBuffer[i]
        }

        // Zero-fill any remaining frames
        if copyLength < Int(inNumberFrames) {
            for i in copyLength..<Int(inNumberFrames) {
                outputData[i] = 0.0
            }
        }
    } else {
        // If no data, output silence
        for i in 0..<Int(inNumberFrames) {
            outputData[i] = 0.0
        }
    }

    return noErr
}
