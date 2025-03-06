// AudioProcessor.swift
// Core Audio handling for real-time audio input/output

import Foundation
import AudioToolbox

/// A class for handling real-time audio input and output using Core Audio's AudioUnit framework
public class AudioProcessor {
    // MARK: - Types and Constants

    /// Audio format settings
    struct AudioFormatSettings {
        static let sampleRate: Double = 44100.0
        static let channelCount: UInt32 = 1 // Mono
        static let bytesPerSample: UInt32 = 4 // Float32
        static let bitsPerChannel: UInt32 = 32
        static let framesPerBuffer: UInt32 = 512 // ~11.6ms at 44.1kHz

        // Create a new ASBD instance each time it's needed rather than storing as static
        static func createASBD() -> AudioStreamBasicDescription {
            var asbd = AudioStreamBasicDescription()
            asbd.mSampleRate = sampleRate
            asbd.mFormatID = kAudioFormatLinearPCM
            asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
            asbd.mBytesPerPacket = bytesPerSample
            asbd.mFramesPerPacket = 1
            asbd.mBytesPerFrame = bytesPerSample
            asbd.mChannelsPerFrame = channelCount
            asbd.mBitsPerChannel = bitsPerChannel
            return asbd
        }
    }

    // MARK: - Properties

    /// Flag indicating if audio processing is active
    private var isRunning = false

    /// Input and output AudioUnit components
    var inputAudioUnit: AudioUnit?
    var outputAudioUnit: AudioUnit?

    /// Buffer to hold captured audio data
    var capturedAudioBuffer: [Float] = []

    /// Lock for thread safety when accessing the captured audio buffer
    let bufferLock = NSLock()

    /// Callback for audio processing - will be called when audio is processed
    public var audioProcessingCallback: (([Float]) -> [Float])?

    /// Latency measurement
    var captureTimestamps: [Double] = []
    var playbackTimestamps: [Double] = []

    // MARK: - Initialization

    public init() {
        print("AudioProcessor initialized")
    }

    deinit {
        stopCapture()
    }

    // MARK: - Public Methods

    /// Start capturing audio from the default input device and setting up audio output
    public func startCapture() -> Bool {
        guard !isRunning else {
            print("Audio capture already running")
            return true
        }

        // Set up input audio unit (microphone)
        let setupInputResult = setupInputAudioUnit()
        guard setupInputResult else {
            print("Failed to set up input audio unit")
            return false
        }

        // Set up output audio unit (speakers)
        let setupOutputResult = setupOutputAudioUnit()
        guard setupOutputResult else {
            print("Failed to set up output audio unit")
            return false
        }

        // Start audio processing
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

    /// Stop capturing audio
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

    /// Play audio through the default output device
    /// This is a simplified method for testing - real-time playback happens through the
    /// render callback of the output audio unit
    public func playAudio(_ buffer: [Float]) -> Bool {
        if isRunning {
            print("Audio system is already running in real-time mode. Use the processing callback instead.")
            return false
        }

        // Initialize output audio unit for one-time playback if not in streaming mode
        let setupResult = setupOutputAudioUnit()
        guard setupResult else {
            print("Failed to set up output audio unit for playback")
            return false
        }

        // Store the buffer for playback
        bufferLock.lock()
        capturedAudioBuffer = buffer
        bufferLock.unlock()

        // Initialize and start the output audio unit
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

        // Wait for playback to complete (this is a simplified approach)
        let playbackDuration = Double(buffer.count) / AudioFormatSettings.sampleRate
        Thread.sleep(forTimeInterval: playbackDuration)

        // Clean up
        AudioOutputUnitStop(outputAudioUnit!)
        AudioUnitUninitialize(outputAudioUnit!)
        AudioComponentInstanceDispose(outputAudioUnit!)
        outputAudioUnit = nil

        print("Playback completed")
        return true
    }

    /// Get the measured latency of the audio processing pipeline
    public var measuredLatency: Double {
        // Calculate average latency from timestamps if available
        guard !captureTimestamps.isEmpty && !playbackTimestamps.isEmpty else {
            return 0.0
        }

        // Make sure we have the same number of timestamps
        let count = min(captureTimestamps.count, playbackTimestamps.count)
        guard count > 0 else { return 0.0 }

        // Calculate average latency
        var totalLatency = 0.0
        for i in 0..<count {
            totalLatency += playbackTimestamps[i] - captureTimestamps[i]
        }

        return (totalLatency / Double(count)) * 1000.0 // Convert to milliseconds
    }

    // MARK: - Private Methods

    private func setupInputAudioUnit() -> Bool {
        // Find the default input audio component
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

        // Create the input audio unit
        var status = AudioComponentInstanceNew(inputComponent, &inputAudioUnit)
        guard status == noErr, inputAudioUnit != nil else {
            print("Failed to create input audio unit: \(status)")
            return false
        }

        // Enable input
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(inputAudioUnit!,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    1, // Input element
                                    &enableInput,
                                    UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            print("Failed to enable input: \(status)")
            return false
        }

        // Disable output (we'll use a separate unit for output)
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(inputAudioUnit!,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Output,
                                    0, // Output element
                                    &disableOutput,
                                    UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            print("Failed to disable output: \(status)")
            return false
        }

        // Set the input device to the default input device
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

        status = AudioUnitSetProperty(inputAudioUnit!,
                                    kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global,
                                    0,
                                    &defaultInputDevice,
                                    UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            print("Failed to set input device: \(status)")
            return false
        }

        // Set the input format
        var asbd = AudioFormatSettings.createASBD()
        status = AudioUnitSetProperty(inputAudioUnit!,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    1, // Input element
                                    &asbd,
                                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else {
            print("Failed to set input format: \(status)")
            return false
        }

        // Set the input callback
        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: inputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        status = AudioUnitSetProperty(inputAudioUnit!,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Global,
                                    0,
                                    &inputCallbackStruct,
                                    UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else {
            print("Failed to set input callback: \(status)")
            return false
        }

        // Set buffer size for lower latency
        var maxFramesPerSlice: UInt32 = AudioFormatSettings.framesPerBuffer
        status = AudioUnitSetProperty(inputAudioUnit!,
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

    private func setupOutputAudioUnit() -> Bool {
        // Find the default output audio component
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

        // Create the output audio unit
        var status = AudioComponentInstanceNew(outputComponent, &outputAudioUnit)
        guard status == noErr, outputAudioUnit != nil else {
            print("Failed to create output audio unit: \(status)")
            return false
        }

        // Set the output format
        var asbd = AudioFormatSettings.createASBD()
        status = AudioUnitSetProperty(outputAudioUnit!,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    0, // Output element
                                    &asbd,
                                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else {
            print("Failed to set output format: \(status)")
            return false
        }

        // Set the output callback
        var outputCallbackStruct = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        status = AudioUnitSetProperty(outputAudioUnit!,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Global,
                                    0,
                                    &outputCallbackStruct,
                                    UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else {
            print("Failed to set output callback: \(status)")
            return false
        }

        // Set buffer size for lower latency
        var maxFramesPerSlice: UInt32 = AudioFormatSettings.framesPerBuffer
        status = AudioUnitSetProperty(outputAudioUnit!,
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

// MARK: - Audio Callbacks

/// Input render callback - called when audio is captured from the microphone
private func inputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

    // Get reference to the AudioProcessor instance
    let audioProcessor = Unmanaged<AudioProcessor>.fromOpaque(inRefCon).takeUnretainedValue()

    // Create an AudioBufferList to hold the captured audio
    var bufferList = AudioBufferList()
    bufferList.mNumberBuffers = 1

    var buffer = AudioBuffer()
    buffer.mNumberChannels = AudioProcessor.AudioFormatSettings.channelCount
    buffer.mDataByteSize = inNumberFrames * AudioProcessor.AudioFormatSettings.bytesPerSample

    // Allocate memory for the audio data
    let audioData = UnsafeMutablePointer<Float>.allocate(capacity: Int(inNumberFrames))
    buffer.mData = UnsafeMutableRawPointer(audioData)

    bufferList.mBuffers = buffer

    // Render the audio from the input source
    let inputUnit = audioProcessor.inputAudioUnit!
    let status = AudioUnitRender(inputUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)

    if status == noErr {
        // Create a Swift array from the captured audio data
        let bufferPointer = UnsafeBufferPointer<Float>(start: audioData, count: Int(inNumberFrames))
        let capturedBuffer = Array(bufferPointer)

        // Record capture timestamp for latency measurement
        let timestamp = CFAbsoluteTimeGetCurrent()
        audioProcessor.captureTimestamps.append(timestamp)

        // Store the captured audio in the AudioProcessor
        audioProcessor.bufferLock.lock()
        audioProcessor.capturedAudioBuffer = capturedBuffer
        audioProcessor.bufferLock.unlock()
    }

    // Clean up
    audioData.deallocate()

    return status
}

/// Output render callback - called when audio output is needed
private func outputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

    // Get reference to the AudioProcessor instance
    let audioProcessor = Unmanaged<AudioProcessor>.fromOpaque(inRefCon).takeUnretainedValue()

    // Get the output buffer
    guard let ioData = ioData, ioData.pointee.mNumberBuffers > 0 else {
        return kAudioUnitErr_InvalidParameter
    }

    // Get pointer to output data
    let outputBuffer = UnsafeMutableAudioBufferListPointer(ioData)[0]
    guard let outputDataRaw = outputBuffer.mData else {
        return kAudioUnitErr_InvalidParameter
    }

    let outputData = outputDataRaw.bindMemory(to: Float.self, capacity: Int(inNumberFrames))

    // Process the audio
    audioProcessor.bufferLock.lock()
    var processedBuffer = audioProcessor.capturedAudioBuffer
    audioProcessor.bufferLock.unlock()

    // Apply audio processing if callback is provided
    if let processingCallback = audioProcessor.audioProcessingCallback {
        processedBuffer = processingCallback(processedBuffer)
    }

    // Record playback timestamp for latency measurement
    let timestamp = CFAbsoluteTimeGetCurrent()
    audioProcessor.playbackTimestamps.append(timestamp)

    // Copy the processed audio to the output buffer
    let copyLength = min(Int(inNumberFrames), processedBuffer.count)
    if copyLength > 0 {
        for i in 0..<copyLength {
            outputData[i] = processedBuffer[i]
        }

        // Fill the rest with zeros if needed
        if copyLength < Int(inNumberFrames) {
            for i in copyLength..<Int(inNumberFrames) {
                outputData[i] = 0.0
            }
        }
    } else {
        // If no audio is available, output silence
        for i in 0..<Int(inNumberFrames) {
            outputData[i] = 0.0
        }
    }

    return noErr
}