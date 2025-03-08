import AudioToolbox
import Foundation
import Utilities
import os.lock

/// Manages audio input capture from the microphone using Core Audio's AudioUnit framework.
public class AudioInputProcessor {

    /// Configuration options for audio input
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
    internal var capturedAudioBuffer: [Float] = []
    internal var bufferLock = os_unfair_lock()

    // Buffer pool for reusing audio buffers
    private var bufferPool: [[Float]] = []
    private var bufferPoolIndex = 0
    private var bufferPoolLock = os_unfair_lock()

    // Timestamp management with circular buffer
    internal var captureTimestamps: [Double] = []
    private var timestampIndex = 0
    private var timestampLock = os_unfair_lock()

    // Running state
    private var stateLock = os_unfair_lock()
    private var _isRunning = false

    /// Callback function for audio processing
    public var audioDataCallback: (([Float]) -> Void)?

    /// Flag indicating if the input processor is running
    public var isRunning: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _isRunning
    }

    /// Initializes a new AudioInputProcessor instance
    /// - Parameter configuration: Configuration options for audio input
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        // No AudioUnitManager creation here - defer until start()

        // Initialize buffer pool
        initializeBufferPool()

        // Pre-allocate timestamp array
        captureTimestamps = Array(repeating: 0.0, count: config.maxTimestamps)
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

        // Create a copy of the buffer to return
        var buffer = bufferPool[bufferPoolIndex]
        bufferPoolIndex = (bufferPoolIndex + 1) % bufferPool.count
        return buffer
    }

    /// Add a timestamp to the circular buffer
    internal func addTimestamp(_ timestamp: Double) {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        captureTimestamps[timestampIndex] = timestamp
        timestampIndex = (timestampIndex + 1) % config.maxTimestamps
    }

    /// Starts capturing audio from the default input device
    /// - Returns: Boolean indicating success or failure
    public func start() -> Bool {
        os_unfair_lock_lock(&stateLock)
        guard !_isRunning else {
            os_unfair_lock_unlock(&stateLock)
            LoggerUtility.debug("Audio input capture already running")
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

            audioUnitManager = AudioUnitManager(type: .input, configuration: auConfig)
        }

        // Set up the render callback
        let inputCallbackStruct = AURenderCallbackStruct(
            inputProc: inputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard audioUnitManager?.setup(renderCallback: inputCallbackStruct) == true else {
            LoggerUtility.debug("Failed to set up input audio unit")
            return false
        }

        guard audioUnitManager?.initialize() == true else {
            LoggerUtility.debug("Failed to initialize input audio unit")
            return false
        }

        guard audioUnitManager?.start() == true else {
            LoggerUtility.debug("Failed to start input audio unit")
            return false
        }

        os_unfair_lock_lock(&stateLock)
        _isRunning = true
        os_unfair_lock_unlock(&stateLock)

        LoggerUtility.debug("Audio input capture started")
        return true
    }

    /// Stops capturing audio and releases audio resources
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

        LoggerUtility.debug("Audio input capture stopped")
    }

    /// Gets the latest captured audio buffer
    /// - Returns: Array of audio samples
    public func getCapturedAudioBuffer() -> [Float] {
        os_unfair_lock_lock(&bufferLock)
        defer { os_unfair_lock_unlock(&bufferLock) }
        return capturedAudioBuffer
    }

    /// Sets the captured audio buffer (primarily for testing)
    /// - Parameter buffer: Audio buffer to set
    public func setCapturedAudioBuffer(_ buffer: [Float]) {
        os_unfair_lock_lock(&bufferLock)
        capturedAudioBuffer = buffer
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Returns the timestamps of captured audio
    public func getCaptureTimestamps() -> [Double] {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        // Return only the valid timestamps (non-zero)
        return captureTimestamps.filter { $0 > 0 }
    }
}

/// Input render callback - called when audio is captured from the microphone
private func inputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

    let audioProcessor = Unmanaged<AudioInputProcessor>.fromOpaque(inRefCon).takeUnretainedValue()

    var bufferList = AudioBufferList()
    bufferList.mNumberBuffers = 1

    var buffer = AudioBuffer()
    buffer.mNumberChannels = audioProcessor.config.channelCount
    buffer.mDataByteSize = inNumberFrames * audioProcessor.config.bytesPerSample

    // Use a pre-allocated buffer if possible
    let audioData = UnsafeMutablePointer<Float>.allocate(capacity: Int(inNumberFrames))
    buffer.mData = UnsafeMutableRawPointer(audioData)

    bufferList.mBuffers = buffer

    let inputUnit = audioProcessor.audioUnitManager?.getAudioUnit()
    var status: OSStatus = noErr

    if let inputUnit = inputUnit {
        status = AudioUnitRender(
            inputUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)

        if status == noErr {
            let bufferPointer = UnsafeBufferPointer<Float>(
                start: audioData, count: Int(inNumberFrames))

            // Create a new array from the buffer pointer
            var capturedBuffer = [Float](repeating: 0.0, count: bufferPointer.count)

            // Copy data into the buffer
            for i in 0..<bufferPointer.count {
                capturedBuffer[i] = bufferPointer[i]
            }

            let timestamp = CFAbsoluteTimeGetCurrent()
            audioProcessor.addTimestamp(timestamp)

            os_unfair_lock_lock(&audioProcessor.bufferLock)
            audioProcessor.capturedAudioBuffer = capturedBuffer
            os_unfair_lock_unlock(&audioProcessor.bufferLock)

            // Call the callback if set
            if let callback = audioProcessor.audioDataCallback {
                callback(capturedBuffer)
            }
        }
    }

    audioData.deallocate()

    return status
}
