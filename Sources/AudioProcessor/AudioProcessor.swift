import AudioToolbox
import Foundation
import os.lock

/// Main class for handling real-time audio input and output using Core Audio's AudioUnit framework.
///
/// This class provides the infrastructure for capturing audio from the microphone,
/// processing it, and playing it back through the system audio output.
public class AudioProcessor {

    /**
     Audio format settings for consistent use throughout the audio pipeline
     */
    public struct AudioFormatSettings {
        public static let sampleRate: Double = 44100.0
        public static let channelCount: UInt32 = 1
        public static let bytesPerSample: UInt32 = 4
        public static let bitsPerChannel: UInt32 = 32
        public static let framesPerBuffer: UInt32 = 512
        public static let bufferPoolSize: Int = 8  // Number of buffers in the pool
        public static let maxTimestamps: Int = 100  // Maximum number of timestamps to store

        /**
         Creates a new AudioStreamBasicDescription with our standard format settings

         - Returns: Properly configured AudioStreamBasicDescription for Float32 mono PCM
         */
        static func createASBD() -> AudioStreamBasicDescription {
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

    // Running state
    private var stateLock = os_unfair_lock()
    private var _isRunning = false
    public var isRunning: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _isRunning
    }

    // Audio units
    internal var inputAudioUnit: AudioUnit?
    internal var outputAudioUnit: AudioUnit?

    // Buffer management
    internal var capturedAudioBuffer: [Float] = []
    internal var bufferLock = os_unfair_lock()

    // Buffer pool for reusing audio buffers
    private var bufferPool: [[Float]] = []
    private var bufferPoolIndex = 0
    private var bufferPoolLock = os_unfair_lock()

    // Timestamp management with circular buffers
    internal var captureTimestamps: [Double]
    private var captureTimestampIndex = 0
    internal var playbackTimestamps: [Double]
    private var playbackTimestampIndex = 0
    private var timestampLock = os_unfair_lock()

    /**
     Callback function for audio processing

     - Parameter [Float]: Input audio buffer
     - Returns: Processed audio buffer to be played back
     */
    public var audioProcessingCallback: (([Float]) -> [Float])?

    // Cache for latency calculation
    private var _cachedLatency: Double = 0.0
    private var _lastLatencyCalculationTime: TimeInterval = 0
    private let latencyCacheDuration: TimeInterval = 0.5  // Cache latency for 500ms

    /**
     Initializes a new AudioProcessor instance
     */
    public init() {
        // Pre-allocate timestamp arrays
        captureTimestamps = Array(repeating: 0.0, count: AudioFormatSettings.maxTimestamps)
        playbackTimestamps = Array(repeating: 0.0, count: AudioFormatSettings.maxTimestamps)

        // Initialize buffer pool
        initializeBufferPool()

        print("AudioProcessor initialized")
    }

    deinit {
        stopCapture()
    }

    /**
     Initialize the buffer pool with pre-allocated buffers
     */
    private func initializeBufferPool() {
        let bufferSize = Int(AudioFormatSettings.framesPerBuffer)
        bufferPool = (0..<AudioFormatSettings.bufferPoolSize).map { _ in
            [Float](repeating: 0.0, count: bufferSize)
        }
    }

    /**
     Get a buffer from the pool

     - Returns: A pre-allocated buffer from the pool
     */
    internal func getBufferFromPool() -> [Float] {
        os_unfair_lock_lock(&bufferPoolLock)
        defer { os_unfair_lock_unlock(&bufferPoolLock) }

        let buffer = bufferPool[bufferPoolIndex]
        bufferPoolIndex = (bufferPoolIndex + 1) % bufferPool.count
        return buffer
    }

    /**
     Add a capture timestamp to the circular buffer

     - Parameter timestamp: The timestamp to add
     */
    internal func addCaptureTimestamp(_ timestamp: Double) {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        captureTimestamps[captureTimestampIndex] = timestamp
        captureTimestampIndex = (captureTimestampIndex + 1) % AudioFormatSettings.maxTimestamps
    }

    /**
     Add a playback timestamp to the circular buffer

     - Parameter timestamp: The timestamp to add
     */
    internal func addPlaybackTimestamp(_ timestamp: Double) {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        playbackTimestamps[playbackTimestampIndex] = timestamp
        playbackTimestampIndex = (playbackTimestampIndex + 1) % AudioFormatSettings.maxTimestamps
    }

    /**
     Get valid capture timestamps (non-zero values)

     - Returns: Array of valid timestamps
     */
    internal func getValidCaptureTimestamps() -> [Double] {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        return captureTimestamps.filter { $0 > 0 }
    }

    /**
     Get valid playback timestamps (non-zero values)

     - Returns: Array of valid timestamps
     */
    internal func getValidPlaybackTimestamps() -> [Double] {
        os_unfair_lock_lock(&timestampLock)
        defer { os_unfair_lock_unlock(&timestampLock) }

        return playbackTimestamps.filter { $0 > 0 }
    }

    /**
     Starts capturing audio from the default input device and setting up audio output

     - Returns: Boolean indicating success or failure
     */
    public func startCapture() -> Bool {
        os_unfair_lock_lock(&stateLock)
        guard !_isRunning else {
            os_unfair_lock_unlock(&stateLock)
            print("Audio capture already running")
            return true
        }
        os_unfair_lock_unlock(&stateLock)

        guard setupInputAudioUnit() else {
            print("Failed to set up input audio unit")
            return false
        }

        guard setupOutputAudioUnit() else {
            print("Failed to set up output audio unit")
            return false
        }

        var status = AudioUnitInitialize(inputAudioUnit!)
        guard status == noErr else {
            print("Failed to initialize input audio unit: \(status)")
            return false
        }

        status = AudioUnitInitialize(outputAudioUnit!)
        guard status == noErr else {
            print("Failed to initialize output audio unit: \(status)")
            return false
        }

        status = AudioOutputUnitStart(inputAudioUnit!)
        guard status == noErr else {
            print("Failed to start input audio unit: \(status)")
            return false
        }

        status = AudioOutputUnitStart(outputAudioUnit!)
        guard status == noErr else {
            print("Failed to start output audio unit: \(status)")
            return false
        }

        os_unfair_lock_lock(&stateLock)
        _isRunning = true
        os_unfair_lock_unlock(&stateLock)

        print("Audio capture started (simulated)")
        return true
    }

    /**
     Stops capturing audio and releases audio resources
     */
    public func stopCapture() {
        os_unfair_lock_lock(&stateLock)
        guard _isRunning else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        _isRunning = false
        os_unfair_lock_unlock(&stateLock)

        if let inputAudioUnit = inputAudioUnit {
            AudioOutputUnitStop(inputAudioUnit)
            AudioUnitUninitialize(inputAudioUnit)
            AudioComponentInstanceDispose(inputAudioUnit)
            self.inputAudioUnit = nil
        }

        if let outputAudioUnit = outputAudioUnit {
            AudioOutputUnitStop(outputAudioUnit)
            AudioUnitUninitialize(outputAudioUnit)
            AudioComponentInstanceDispose(outputAudioUnit)
            self.outputAudioUnit = nil
        }

        print("Audio capture stopped (simulated)")
    }

    /**
     Plays audio through the default output device
     This is a simplified method for testing - real-time playback happens through the
     render callback of the output audio unit

     - Parameter buffer: Audio samples to play
     - Returns: Boolean indicating success or failure
     */
    public func playAudio(_ buffer: [Float]) -> Bool {
        os_unfair_lock_lock(&stateLock)
        let currentlyRunning = _isRunning
        os_unfair_lock_unlock(&stateLock)

        guard !currentlyRunning else {
            print(
                "Audio system is already running in real-time mode. Use the processing callback instead."
            )
            return false
        }

        guard setupOutputAudioUnit() else {
            print("Failed to set up output audio unit for playback")
            return false
        }

        os_unfair_lock_lock(&bufferLock)
        capturedAudioBuffer = buffer
        os_unfair_lock_unlock(&bufferLock)

        var status = AudioUnitInitialize(outputAudioUnit!)
        guard status == noErr else {
            print("Failed to initialize output audio unit: \(status)")
            return false
        }

        status = AudioOutputUnitStart(outputAudioUnit!)
        guard status == noErr else {
            print("Failed to start output audio unit: \(status)")
            return false
        }

        let playbackDuration = Double(buffer.count) / AudioFormatSettings.sampleRate
        Thread.sleep(forTimeInterval: playbackDuration)

        AudioOutputUnitStop(outputAudioUnit!)
        AudioUnitUninitialize(outputAudioUnit!)
        AudioComponentInstanceDispose(outputAudioUnit!)
        outputAudioUnit = nil

        print(
            "Playback completed (simulated duration: \(String(format: "%.1f", playbackDuration)) seconds)"
        )
        return true
    }

    /**
     Returns the measured latency of the audio processing pipeline in milliseconds
     */
    public var measuredLatency: Double {
        // Check if we have a recent cached value
        let now = Date().timeIntervalSince1970
        if now - _lastLatencyCalculationTime < latencyCacheDuration {
            return _cachedLatency
        }

        let captureTimestamps = getValidCaptureTimestamps()
        let playbackTimestamps = getValidPlaybackTimestamps()

        guard !captureTimestamps.isEmpty && !playbackTimestamps.isEmpty else {
            return 0.0
        }

        let count = min(captureTimestamps.count, playbackTimestamps.count)
        guard count > 0 else { return 0.0 }

        var totalLatency = 0.0
        for i in 0..<count {
            totalLatency += playbackTimestamps[i] - captureTimestamps[i]
        }

        // Cache the result
        _cachedLatency = (totalLatency / Double(count)) * 1000.0
        _lastLatencyCalculationTime = now

        return _cachedLatency
    }

    /**
     Sets up the AudioUnit for capturing input from the microphone

     - Returns: Boolean indicating success or failure
     */
    private func setupInputAudioUnit() -> Bool {
        var inputComponentDescription = AudioComponentDescription()
        inputComponentDescription.componentType = kAudioUnitType_Output
        inputComponentDescription.componentSubType = kAudioUnitSubType_HALOutput
        inputComponentDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        inputComponentDescription.componentFlags = 0
        inputComponentDescription.componentFlagsMask = 0

        guard let inputComponent = AudioComponentFindNext(nil, &inputComponentDescription) else {
            print("Failed to find input audio component")
            return false
        }

        var status = AudioComponentInstanceNew(inputComponent, &inputAudioUnit)
        guard status == noErr, inputAudioUnit != nil else {
            print("Failed to create input audio unit: \(status)")
            return false
        }

        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            inputAudioUnit!,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            print("Failed to enable input: \(status)")
            return false
        }

        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            inputAudioUnit!,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            print("Failed to disable output: \(status)")
            return false
        }

        var defaultInputDevice = AudioDeviceID()
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultInputDevice)
        guard status == noErr else {
            print("Failed to get default input device: \(status)")
            return false
        }

        status = AudioUnitSetProperty(
            inputAudioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &defaultInputDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            print("Failed to set input device: \(status)")
            return false
        }

        var asbd = AudioFormatSettings.createASBD()
        status = AudioUnitSetProperty(
            inputAudioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else {
            print("Failed to set input format: \(status)")
            return false
        }

        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: inputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        status = AudioUnitSetProperty(
            inputAudioUnit!,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &inputCallbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else {
            print("Failed to set input callback: \(status)")
            return false
        }

        var maxFramesPerSlice: UInt32 = AudioFormatSettings.framesPerBuffer
        status = AudioUnitSetProperty(
            inputAudioUnit!,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxFramesPerSlice,
            UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            print("Failed to set input buffer size: \(status)")
            return false
        }

        return true
    }

    /**
     Sets up the AudioUnit for playing audio to the speakers

     - Returns: Boolean indicating success or failure
     */
    private func setupOutputAudioUnit() -> Bool {
        var outputComponentDescription = AudioComponentDescription()
        outputComponentDescription.componentType = kAudioUnitType_Output
        outputComponentDescription.componentSubType = kAudioUnitSubType_DefaultOutput
        outputComponentDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        outputComponentDescription.componentFlags = 0
        outputComponentDescription.componentFlagsMask = 0

        guard let outputComponent = AudioComponentFindNext(nil, &outputComponentDescription) else {
            print("Failed to find output audio component")
            return false
        }

        var status = AudioComponentInstanceNew(outputComponent, &outputAudioUnit)
        guard status == noErr, outputAudioUnit != nil else {
            print("Failed to create output audio unit: \(status)")
            return false
        }

        var asbd = AudioFormatSettings.createASBD()
        status = AudioUnitSetProperty(
            outputAudioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else {
            print("Failed to set output format: \(status)")
            return false
        }

        var outputCallbackStruct = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        status = AudioUnitSetProperty(
            outputAudioUnit!,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Global,
            0,
            &outputCallbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else {
            print("Failed to set output callback: \(status)")
            return false
        }

        var maxFramesPerSlice: UInt32 = AudioFormatSettings.framesPerBuffer
        status = AudioUnitSetProperty(
            outputAudioUnit!,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxFramesPerSlice,
            UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            print("Failed to set output buffer size: \(status)")
            return false
        }

        return true
    }
}

/// Input render callback - called when audio is captured from the microphone
///
/// - Parameters:
///   - inRefCon: Reference to the AudioProcessor instance
///   - ioActionFlags: Flags that describe the operations to be performed
///   - inTimeStamp: The time at which the data will be rendered
///   - inBusNumber: The bus number for the render operation
///   - inNumberFrames: The number of frames to render
///   - ioData: The audio data to be rendered
/// - Returns: Status code indicating success or failure
private func inputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

    let audioProcessor = Unmanaged<AudioProcessor>.fromOpaque(inRefCon).takeUnretainedValue()

    var bufferList = AudioBufferList()
    bufferList.mNumberBuffers = 1

    var buffer = AudioBuffer()
    buffer.mNumberChannels = AudioProcessor.AudioFormatSettings.channelCount
    buffer.mDataByteSize = inNumberFrames * AudioProcessor.AudioFormatSettings.bytesPerSample

    let audioData = UnsafeMutablePointer<Float>.allocate(capacity: Int(inNumberFrames))
    buffer.mData = UnsafeMutableRawPointer(audioData)

    bufferList.mBuffers = buffer

    let inputUnit = audioProcessor.inputAudioUnit!
    let status = AudioUnitRender(
        inputUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)

    if status == noErr {
        let bufferPointer = UnsafeBufferPointer<Float>(start: audioData, count: Int(inNumberFrames))

        // Create a new array from the buffer pointer
        var capturedBuffer = [Float](repeating: 0.0, count: bufferPointer.count)

        // Copy data into the buffer
        for i in 0..<bufferPointer.count {
            capturedBuffer[i] = bufferPointer[i]
        }

        let timestamp = CFAbsoluteTimeGetCurrent()
        audioProcessor.addCaptureTimestamp(timestamp)

        os_unfair_lock_lock(&audioProcessor.bufferLock)
        audioProcessor.capturedAudioBuffer = capturedBuffer
        os_unfair_lock_unlock(&audioProcessor.bufferLock)
    }

    audioData.deallocate()

    return status
}

/// Output render callback - called when audio output is needed
///
/// - Parameters:
///   - inRefCon: Reference to the AudioProcessor instance
///   - ioActionFlags: Flags that describe the operations to be performed
///   - inTimeStamp: The time at which the data will be rendered
///   - inBusNumber: The bus number for the render operation
///   - inNumberFrames: The number of frames to render
///   - ioData: The audio data to be rendered
/// - Returns: Status code indicating success or failure
private func outputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

    let audioProcessor = Unmanaged<AudioProcessor>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let ioData = ioData, ioData.pointee.mNumberBuffers > 0 else {
        return kAudioUnitErr_InvalidParameter
    }

    let outputBuffer = UnsafeMutableAudioBufferListPointer(ioData)[0]
    guard let outputDataRaw = outputBuffer.mData else {
        return kAudioUnitErr_InvalidParameter
    }

    let outputData = outputDataRaw.bindMemory(to: Float.self, capacity: Int(inNumberFrames))

    // Get audio data from the buffer
    os_unfair_lock_lock(&audioProcessor.bufferLock)
    var processedBuffer = audioProcessor.capturedAudioBuffer
    os_unfair_lock_unlock(&audioProcessor.bufferLock)

    // Apply processing if callback is set
    if let processingCallback = audioProcessor.audioProcessingCallback {
        processedBuffer = processingCallback(processedBuffer)
    }

    let timestamp = CFAbsoluteTimeGetCurrent()
    audioProcessor.addPlaybackTimestamp(timestamp)

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
