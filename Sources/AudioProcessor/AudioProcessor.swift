import AudioToolbox
import Foundation

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

    public private(set) var isRunning = false
    internal var inputAudioUnit: AudioUnit?
    internal var outputAudioUnit: AudioUnit?
    internal var capturedAudioBuffer: [Float] = []
    internal let bufferLock = NSLock()

    /**
     Callback function for audio processing

     - Parameter [Float]: Input audio buffer
     - Returns: Processed audio buffer to be played back
     */
    public var audioProcessingCallback: (([Float]) -> [Float])?

    internal var captureTimestamps: [Double] = []
    internal var playbackTimestamps: [Double] = []

    /**
     Initializes a new AudioProcessor instance
     */
    public init() {
        print("AudioProcessor initialized")
    }

    deinit {
        stopCapture()
    }

    /**
     Starts capturing audio from the default input device and setting up audio output

     - Returns: Boolean indicating success or failure
     */
    public func startCapture() -> Bool {
        guard !isRunning else {
            print("Audio capture already running")
            return true
        }

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

        isRunning = true
        print("Audio capture started")
        return true
    }

    /**
     Stops capturing audio and releases audio resources
     */
    public func stopCapture() {
        guard isRunning else { return }

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

        isRunning = false
        print("Audio capture stopped")
    }

    /**
     Plays audio through the default output device
     This is a simplified method for testing - real-time playback happens through the
     render callback of the output audio unit

     - Parameter buffer: Audio samples to play
     - Returns: Boolean indicating success or failure
     */
    public func playAudio(_ buffer: [Float]) -> Bool {
        guard !isRunning else {
            print(
                "Audio system is already running in real-time mode. Use the processing callback instead."
            )
            return false
        }

        guard setupOutputAudioUnit() else {
            print("Failed to set up output audio unit for playback")
            return false
        }

        bufferLock.lock()
        capturedAudioBuffer = buffer
        bufferLock.unlock()

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

        print("Playback completed")
        return true
    }

    /**
     Returns the measured latency of the audio processing pipeline in milliseconds
     */
    public var measuredLatency: Double {
        guard !captureTimestamps.isEmpty && !playbackTimestamps.isEmpty else {
            return 0.0
        }

        let count = min(captureTimestamps.count, playbackTimestamps.count)
        guard count > 0 else { return 0.0 }

        var totalLatency = 0.0
        for i in 0..<count {
            totalLatency += playbackTimestamps[i] - captureTimestamps[i]
        }

        return (totalLatency / Double(count)) * 1000.0
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
        let capturedBuffer = Array(bufferPointer)

        let timestamp = CFAbsoluteTimeGetCurrent()
        audioProcessor.captureTimestamps.append(timestamp)

        audioProcessor.bufferLock.lock()
        audioProcessor.capturedAudioBuffer = capturedBuffer
        audioProcessor.bufferLock.unlock()
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

    audioProcessor.bufferLock.lock()
    var processedBuffer = audioProcessor.capturedAudioBuffer
    audioProcessor.bufferLock.unlock()

    if let processingCallback = audioProcessor.audioProcessingCallback {
        processedBuffer = processingCallback(processedBuffer)
    }

    let timestamp = CFAbsoluteTimeGetCurrent()
    audioProcessor.playbackTimestamps.append(timestamp)

    let copyLength = min(Int(inNumberFrames), processedBuffer.count)
    if copyLength > 0 {
        for i in 0..<copyLength {
            outputData[i] = processedBuffer[i]
        }

        if copyLength < Int(inNumberFrames) {
            for i in copyLength..<Int(inNumberFrames) {
                outputData[i] = 0.0
            }
        }
    } else {
        for i in 0..<Int(inNumberFrames) {
            outputData[i] = 0.0
        }
    }

    return noErr
}
