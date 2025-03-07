import AudioToolbox
import Foundation

/// Manages the creation, configuration, and lifecycle of AudioUnit instances.
/// This class encapsulates all low-level AudioUnit interactions, providing a clean interface
/// for audio input and output management.
public class AudioUnitManager {

    /// Represents the type of AudioUnit being managed
    public enum AudioUnitType {
        case input
        case output
    }

    /// Configuration options for AudioUnit setup
    public struct Configuration {
        public let sampleRate: Double
        public let channelCount: UInt32
        public let bytesPerSample: UInt32
        public let bitsPerChannel: UInt32
        public let framesPerBuffer: UInt32
        public let simulateAudioUnit: Bool

        public init(
            sampleRate: Double = 44100.0,
            channelCount: UInt32 = 1,
            bytesPerSample: UInt32 = 4,
            bitsPerChannel: UInt32 = 32,
            framesPerBuffer: UInt32 = 512,
            simulateAudioUnit: Bool = false
        ) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.bytesPerSample = bytesPerSample
            self.bitsPerChannel = bitsPerChannel
            self.framesPerBuffer = framesPerBuffer
            self.simulateAudioUnit = simulateAudioUnit
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

    private var audioUnit: AudioUnit?
    private let unitType: AudioUnitType
    private let config: Configuration
    private var isSetup = false
    private var isInitialized = false
    private var isStarted = false

    /// Creates a new AudioUnitManager instance
    /// - Parameters:
    ///   - type: The type of AudioUnit to manage (input or output)
    ///   - configuration: Configuration options for the AudioUnit
    public init(type: AudioUnitType, configuration: Configuration = Configuration()) {
        self.unitType = type

        // Auto-enable simulation in test environment
        if !configuration.simulateAudioUnit && NSClassFromString("XCTest") != nil {
            self.config = Configuration(
                sampleRate: configuration.sampleRate,
                channelCount: configuration.channelCount,
                bytesPerSample: configuration.bytesPerSample,
                bitsPerChannel: configuration.bitsPerChannel,
                framesPerBuffer: configuration.framesPerBuffer,
                simulateAudioUnit: true
            )
        } else {
            self.config = configuration
        }
    }

    deinit {
        dispose()
    }

    /// Creates and configures the AudioUnit
    /// - Parameter renderCallback: Optional render callback for audio processing
    /// - Returns: Boolean indicating success
    public func setup(renderCallback: AURenderCallbackStruct? = nil) -> Bool {
        if config.simulateAudioUnit {
            isSetup = true
            return true
        }

        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_Output
        componentDescription.componentSubType = kAudioUnitSubType_HALOutput
        componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        componentDescription.componentFlags = 0
        componentDescription.componentFlagsMask = 0

        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            print("Failed to find audio component")
            return false
        }

        var status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr, let audioUnit = audioUnit else {
            print("Failed to create audio unit: \(status)")
            return false
        }

        // Configure IO
        var enableIO: UInt32
        var scope: AudioUnitScope
        var element: AudioUnitElement

        switch unitType {
        case .input:
            enableIO = 1
            scope = kAudioUnitScope_Input
            element = 1
        case .output:
            enableIO = 1
            scope = kAudioUnitScope_Output
            element = 0
        }

        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            scope,
            element,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )

        guard status == noErr else {
            print("Failed to enable IO: \(status)")
            return false
        }

        // Set audio format
        var asbd = config.createASBD()
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            scope,
            element,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        guard status == noErr else {
            print("Failed to set stream format: \(status)")
            return false
        }

        // Set render callback if provided
        if let callback = renderCallback {
            var mutableCallback = callback
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioUnitProperty_SetRenderCallback,
                scope,
                element,
                &mutableCallback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )

            guard status == noErr else {
                print("Failed to set render callback: \(status)")
                return false
            }
        }

        isSetup = true
        return true
    }

    /// Initializes the AudioUnit
    /// - Returns: Boolean indicating success
    public func initialize() -> Bool {
        guard isSetup else { return false }

        if config.simulateAudioUnit {
            isInitialized = true
            return true
        }

        guard let audioUnit = audioUnit else { return false }
        let status = AudioUnitInitialize(audioUnit)
        isInitialized = status == noErr
        return isInitialized
    }

    /// Starts the AudioUnit
    /// - Returns: Boolean indicating success
    public func start() -> Bool {
        guard isInitialized else { return false }

        if config.simulateAudioUnit {
            isStarted = true
            return true
        }

        guard let audioUnit = audioUnit else { return false }
        let status = AudioOutputUnitStart(audioUnit)
        isStarted = status == noErr
        return isStarted
    }

    /// Stops the AudioUnit
    /// - Returns: Boolean indicating success
    public func stop() -> Bool {
        guard isStarted else { return false }

        if config.simulateAudioUnit {
            isStarted = false
            return true
        }

        guard let audioUnit = audioUnit else { return false }
        let status = AudioOutputUnitStop(audioUnit)
        isStarted = status == noErr
        return !isStarted
    }

    /// Uninitializes and disposes of the AudioUnit
    public func dispose() {
        if config.simulateAudioUnit {
            isStarted = false
            isInitialized = false
            isSetup = false
            audioUnit = nil
            return
        }

        if let audioUnit = audioUnit {
            if isStarted {
                AudioOutputUnitStop(audioUnit)
                isStarted = false
            }
            if isInitialized {
                AudioUnitUninitialize(audioUnit)
                isInitialized = false
            }
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
            isSetup = false
        }
    }

    /// Gets the underlying AudioUnit instance
    /// - Returns: The managed AudioUnit instance
    public func getAudioUnit() -> AudioUnit? {
        return config.simulateAudioUnit ? nil : audioUnit
    }

    /// Checks if the AudioUnit is currently running
    public var isRunning: Bool {
        return isStarted
    }
}
