import AudioToolbox
import Foundation

/// Manages audio input capture from the microphone using Core Audio's AudioUnit framework.
public class AudioInputProcessor {

    /// Configuration options for audio input
    public struct Configuration {
        public let sampleRate: Double
        public let channelCount: UInt32
        public let bytesPerSample: UInt32
        public let bitsPerChannel: UInt32
        public let framesPerBuffer: UInt32

        public init(
            sampleRate: Double = 44100.0,
            channelCount: UInt32 = 1,
            bytesPerSample: UInt32 = 4,
            bitsPerChannel: UInt32 = 32,
            framesPerBuffer: UInt32 = 512
        ) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.bytesPerSample = bytesPerSample
            self.bitsPerChannel = bitsPerChannel
            self.framesPerBuffer = framesPerBuffer
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
    internal var capturedAudioBuffer: [Float] = []
    internal let bufferLock = NSLock()
    internal var captureTimestamps: [Double] = []

    /// Callback function for audio processing
    public var audioDataCallback: (([Float]) -> Void)?

    /// Flag indicating if the input processor is running
    public private(set) var isRunning = false

    /// Initializes a new AudioInputProcessor instance
    /// - Parameter configuration: Configuration options for audio input
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        // No AudioUnitManager creation here - defer until start()
    }

    deinit {
        stop()
    }

    /// Starts capturing audio from the default input device
    /// - Returns: Boolean indicating success or failure
    public func start() -> Bool {
        guard !isRunning else {
            print("Audio input capture already running")
            return true
        }

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
            print("Failed to set up input audio unit")
            return false
        }

        guard audioUnitManager?.initialize() == true else {
            print("Failed to initialize input audio unit")
            return false
        }

        guard audioUnitManager?.start() == true else {
            print("Failed to start input audio unit")
            return false
        }

        isRunning = true
        print("Audio input capture started")
        return true
    }

    /// Stops capturing audio and releases audio resources
    public func stop() {
        guard isRunning else { return }

        _ = audioUnitManager?.stop()
        audioUnitManager?.dispose()
        audioUnitManager = nil

        isRunning = false
        print("Audio input capture stopped")
    }

    /// Gets the latest captured audio buffer
    /// - Returns: Array of audio samples
    public func getCapturedAudioBuffer() -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return capturedAudioBuffer
    }

    /// Sets the captured audio buffer (primarily for testing)
    /// - Parameter buffer: Audio buffer to set
    public func setCapturedAudioBuffer(_ buffer: [Float]) {
        bufferLock.lock()
        capturedAudioBuffer = buffer
        bufferLock.unlock()
    }

    /// Returns the timestamps of captured audio
    public func getCaptureTimestamps() -> [Double] {
        return captureTimestamps
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
            let capturedBuffer = Array(bufferPointer)

            let timestamp = CFAbsoluteTimeGetCurrent()
            audioProcessor.captureTimestamps.append(timestamp)

            audioProcessor.bufferLock.lock()
            audioProcessor.capturedAudioBuffer = capturedBuffer
            audioProcessor.bufferLock.unlock()

            // Call the callback if set
            if let callback = audioProcessor.audioDataCallback {
                callback(capturedBuffer)
            }
        }
    }

    audioData.deallocate()

    return status
}
