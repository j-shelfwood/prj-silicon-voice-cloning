import AudioToolbox
import Foundation

/// Manages audio output playback to the speakers using Core Audio's AudioUnit framework.
public class AudioOutputProcessor {

    /// Configuration options for audio output
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
    internal var outputAudioBuffer: [Float] = []
    internal let bufferLock = NSLock()
    internal var playbackTimestamps: [Double] = []

    /// Callback function for generating audio data
    public var audioDataProvider: (() -> [Float])?

    /// Flag indicating if the output processor is running
    public private(set) var isRunning = false

    /// Initializes a new AudioOutputProcessor instance
    /// - Parameter configuration: Configuration options for audio output
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        // No AudioUnitManager creation here - defer until start()
    }

    deinit {
        stop()
    }

    /// Starts audio output to the default output device
    /// - Returns: Boolean indicating success or failure
    public func start() -> Bool {
        guard !isRunning else {
            print("Audio output already running")
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

            audioUnitManager = AudioUnitManager(type: .output, configuration: auConfig)
        }

        // Set up the render callback
        let outputCallbackStruct = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard audioUnitManager?.setup(renderCallback: outputCallbackStruct) == true else {
            print("Failed to set up output audio unit")
            return false
        }

        guard audioUnitManager?.initialize() == true else {
            print("Failed to initialize output audio unit")
            return false
        }

        guard audioUnitManager?.start() == true else {
            print("Failed to start output audio unit")
            return false
        }

        isRunning = true
        print("Audio output started")
        return true
    }

    /// Stops audio output and releases audio resources
    public func stop() {
        guard isRunning else { return }

        _ = audioUnitManager?.stop()
        audioUnitManager?.dispose()
        audioUnitManager = nil

        isRunning = false
        print("Audio output stopped")
    }

    /// Plays a buffer of audio samples through the output device
    /// - Parameter buffer: Audio samples to play
    /// - Returns: Boolean indicating success or failure
    public func playAudio(_ buffer: [Float]) -> Bool {
        guard !isRunning else {
            print(
                "Audio output is already running in real-time mode. Use the data provider instead.")
            return false
        }

        bufferLock.lock()
        outputAudioBuffer = buffer
        bufferLock.unlock()

        // Start output for playback
        if start() {
            // Calculate playback duration and wait
            let playbackDuration = Double(buffer.count) / config.sampleRate
            Thread.sleep(forTimeInterval: playbackDuration)

            // Stop after playback
            stop()
            return true
        }

        return false
    }

    /// Sets the output audio buffer
    /// - Parameter buffer: Audio buffer to set
    public func setOutputAudioBuffer(_ buffer: [Float]) {
        bufferLock.lock()
        outputAudioBuffer = buffer
        bufferLock.unlock()
    }

    /// Gets the current output audio buffer
    /// - Returns: Array of audio samples
    public func getOutputAudioBuffer() -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return outputAudioBuffer
    }

    /// Returns the timestamps of played audio
    public func getPlaybackTimestamps() -> [Double] {
        return playbackTimestamps
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
        audioProcessor.bufferLock.lock()
        processedBuffer = audioProcessor.outputAudioBuffer
        audioProcessor.bufferLock.unlock()
    }

    let timestamp = CFAbsoluteTimeGetCurrent()
    audioProcessor.playbackTimestamps.append(timestamp)

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
