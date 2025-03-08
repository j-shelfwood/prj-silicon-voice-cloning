import Audio
import AudioProcessor
import DSP
import Foundation
import ML
import ModelInference
import Utilities

/// Protocol for CLI commands
public protocol Command {
    /// The name of the command as used in the CLI
    static var commandName: String { get }

    /// A short description of what the command does
    static var description: String { get }

    /// Execute the command
    @MainActor
    func execute() async throws
}

/// Main router for CLI commands
@MainActor
public class CommandRouter {
    // MARK: - Properties

    /// The audio processor for handling audio I/O
    private let audioProcessor: AudioProcessorProtocol

    /// The DSP processor for signal processing
    private let dsp: DSP

    /// The model inference engine
    private let modelInference: ModelInference

    /// The voice cloner
    private let voiceCloner: VoiceCloner

    /// Dictionary of available commands
    private var commands: [String: Command.Type] = [:]

    // MARK: - Initialization

    /// Initialize the command router with required dependencies
    /// - Parameters:
    ///   - audioProcessor: The audio processor for handling audio I/O
    ///   - dsp: The DSP processor for signal processing
    ///   - modelInference: The model inference engine
    ///   - voiceCloner: The voice cloner
    public init(
        audioProcessor: AudioProcessorProtocol,
        dsp: DSP,
        modelInference: ModelInference,
        voiceCloner: VoiceCloner
    ) {
        self.audioProcessor = audioProcessor
        self.dsp = dsp
        self.modelInference = modelInference
        self.voiceCloner = voiceCloner

        registerCommands()
    }

    // MARK: - Command Registration

    /// Register all available commands
    private func registerCommands() {
        register(TestAudioCommand.self)
        register(TestPassthroughCommand.self)
        register(TestLatencyCommand.self)
        register(TestDSPCommand.self)
        register(TestMLCommand.self)
        register(TestPipelineCommand.self)
        register(RecordTargetVoiceCommand.self)
        register(TestVoiceCloningCommand.self)
        register(FileBasedVoiceCloningCommand.self)
        register(HelpCommand.self)
    }

    /// Register a command
    /// - Parameter commandType: The command type to register
    private func register(_ commandType: Command.Type) {
        commands[commandType.commandName] = commandType
    }

    // MARK: - Command Execution

    /// Route and execute a command based on command line arguments
    /// - Parameter arguments: The command line arguments
    /// - Returns: True if the command was executed successfully, false otherwise
    public func routeAndExecute(arguments: [String]) async -> Bool {
        guard arguments.count > 1 else {
            await showHelp()
            return true
        }

        let commandName = arguments[1]

        if let commandType = commands[commandName] {
            do {
                let command = try createCommand(type: commandType)
                try await command.execute()
                return true
            } catch {
                Utilities.log("Error executing command: \(error)")
                return false
            }
        } else {
            Utilities.log("Unknown command: \(commandName)")
            await showHelp()
            return false
        }
    }

    /// Create a command instance based on its type
    /// - Parameter type: The command type
    /// - Returns: An instance of the command
    private func createCommand(type: Command.Type) throws -> Command {
        switch type {
        case is TestAudioCommand.Type:
            return TestAudioCommand(audioProcessor: audioProcessor)
        case is TestPassthroughCommand.Type:
            return TestPassthroughCommand(audioProcessor: audioProcessor)
        case is TestLatencyCommand.Type:
            return TestLatencyCommand(audioProcessor: audioProcessor)
        case is TestDSPCommand.Type:
            return TestDSPCommand(audioProcessor: audioProcessor, dsp: dsp)
        case is TestMLCommand.Type:
            return TestMLCommand(modelInference: modelInference)
        case is TestPipelineCommand.Type:
            return TestPipelineCommand(
                audioProcessor: audioProcessor, dsp: dsp, modelInference: modelInference)
        case is RecordTargetVoiceCommand.Type:
            return RecordTargetVoiceCommand(
                audioProcessor: audioProcessor, voiceCloner: voiceCloner)
        case is TestVoiceCloningCommand.Type:
            return TestVoiceCloningCommand(audioProcessor: audioProcessor, voiceCloner: voiceCloner)
        case is FileBasedVoiceCloningCommand.Type:
            return FileBasedVoiceCloningCommand(voiceCloner: voiceCloner)
        case is HelpCommand.Type:
            return HelpCommand(availableCommands: commands)
        default:
            throw CommandError.unknownCommandType
        }
    }

    /// Show help information
    private func showHelp() async {
        let helpCommand = HelpCommand(availableCommands: commands)
        try? await helpCommand.execute()
    }
}

// MARK: - Command Error

/// Errors that can occur during command execution
enum CommandError: Error {
    case unknownCommandType
    case invalidArguments(String)
    case fileNotFound(String)
    case audioProcessingFailed(String)
}

// MARK: - Command Implementations

/// Command for testing audio output with a sine wave
struct TestAudioCommand: Command {
    static var commandName: String { "test-audio" }
    static var description: String { "Test audio input/output with a sine wave" }

    private let audioProcessor: AudioProcessorProtocol

    init(audioProcessor: AudioProcessorProtocol) {
        self.audioProcessor = audioProcessor
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Testing audio output with a sine wave...")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        Utilities.startTimer(id: "sine_generation")
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 2.0)
        let generationTime = Utilities.endTimer(id: "sine_generation")

        Utilities.log(
            "Generated sine wave with \(sineWave.count) samples in \(String(format: "%.2f", generationTime))ms"
        )

        // Reduce volume to 20% of original
        let volumeScale: Float = 0.2
        let quieterSineWave = sineWave.map { $0 * volumeScale }

        Utilities.log("Playing sine wave at \(Int(volumeScale * 100))% volume...")

        // Play the sine wave
        if !mutableAudioProcessor.playAudio(quieterSineWave) {
            throw CommandError.audioProcessingFailed("Failed to play audio")
        }

        Utilities.log("Sine wave playback complete")
    }
}

/// Command for testing real-time audio pass-through
struct TestPassthroughCommand: Command {
    static var commandName: String { "test-passthrough" }
    static var description: String { "Test microphone to speaker pass-through" }

    private let audioProcessor: AudioProcessorProtocol

    init(audioProcessor: AudioProcessorProtocol) {
        self.audioProcessor = audioProcessor
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Testing audio pass-through (microphone → speakers)...")
        Utilities.log(
            "This will capture audio from your microphone and play it through your speakers.")
        Utilities.log("Press Enter to stop.")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        mutableAudioProcessor.audioProcessingCallback = { buffer in
            return buffer
        }

        if mutableAudioProcessor.startCapture() {
            Utilities.log(
                "Audio pass-through started. Speak into your microphone to hear your voice.")

            // Wait for user input
            _ = readLine()
            mutableAudioProcessor.stopCapture()

            Utilities.log("Audio pass-through stopped")
        } else {
            throw CommandError.audioProcessingFailed("Failed to start audio pass-through")
        }
    }
}

/// Command for testing and measuring audio processing latency
struct TestLatencyCommand: Command {
    static var commandName: String { "test-latency" }
    static var description: String { "Measure audio processing latency" }

    private let audioProcessor: AudioProcessorProtocol

    init(audioProcessor: AudioProcessorProtocol) {
        self.audioProcessor = audioProcessor
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Testing audio processing latency...")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        mutableAudioProcessor.audioProcessingCallback = { buffer in
            return buffer
        }

        if mutableAudioProcessor.startCapture() {
            Utilities.log("Audio processing started for latency testing.")
            Utilities.log("Speak into your microphone to generate audio.")
            Utilities.log("Press Enter to stop and see latency measurement.")

            _ = readLine()

            mutableAudioProcessor.stopCapture()
            let latency = mutableAudioProcessor.measuredLatency
            Utilities.log(
                "Measured audio processing latency: \(String(format: "%.2f", latency)) ms")
        } else {
            throw CommandError.audioProcessingFailed(
                "Failed to start audio processing for latency test")
        }
    }
}

/// Command for testing DSP functionality with live audio
struct TestDSPCommand: Command {
    static var commandName: String { "test-dsp" }
    static var description: String { "Test DSP functionality with live audio" }

    private let audioProcessor: AudioProcessorProtocol
    private let dsp: DSP

    init(audioProcessor: AudioProcessorProtocol, dsp: DSP) {
        self.audioProcessor = audioProcessor
        self.dsp = dsp
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Testing DSP with live audio...")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        mutableAudioProcessor.audioProcessingCallback = { [dsp] buffer in
            Task { @MainActor in
                Utilities.startTimer(id: "fft")
            }

            let _ = dsp.performFFT(inputBuffer: buffer)

            var fftTime: Double = 0
            Task { @MainActor in
                fftTime = Utilities.endTimer(id: "fft")

                if Int.random(in: 0...100) < 5 {
                    Utilities.log("FFT processing time: \(String(format: "%.2f", fftTime)) ms")
                }
            }

            return buffer
        }

        if mutableAudioProcessor.startCapture() {
            Utilities.log("Audio processing with DSP started.")
            Utilities.log("Press Enter to stop.")

            _ = readLine()
            mutableAudioProcessor.stopCapture()

            Utilities.log("Audio processing with DSP stopped")
        } else {
            throw CommandError.audioProcessingFailed("Failed to start audio processing with DSP")
        }
    }
}

/// Command for testing ML capabilities
struct TestMLCommand: Command {
    static var commandName: String { "test-ml" }
    static var description: String { "Test ML capabilities" }

    private let modelInference: ModelInference

    init(modelInference: ModelInference) {
        self.modelInference = modelInference
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Testing ML capabilities...")
        Utilities.log("Core ML available: \(modelInference.isCoreMLAvailable())")
        Utilities.log(modelInference.getAvailableComputeUnits())
    }
}

/// Command for testing a minimal end-to-end pipeline
struct TestPipelineCommand: Command {
    static var commandName: String { "test-pipeline" }
    static var description: String { "Test minimal end-to-end pipeline" }

    private let audioProcessor: AudioProcessorProtocol
    private let dsp: DSP
    private let modelInference: ModelInference

    init(audioProcessor: AudioProcessorProtocol, dsp: DSP, modelInference: ModelInference) {
        self.audioProcessor = audioProcessor
        self.dsp = dsp
        self.modelInference = modelInference
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Testing minimal end-to-end pipeline...")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        // Step 1: Set up audio processing callback
        mutableAudioProcessor.audioProcessingCallback = { inputBuffer in
            // Step 2: Convert audio to mel spectrogram
            let spectrogram = dsp.generateSpectrogram(inputBuffer: inputBuffer)
            let _ = dsp.specToMelSpec(spectrogram: spectrogram)

            // Step 3: For now, just return the input (placeholder for model inference)
            // In a complete implementation, this would:
            // - Pass the mel spectrogram to a voice conversion model
            // - Convert the output back to audio
            return inputBuffer
        }

        // Step 4: Start audio processing
        if mutableAudioProcessor.startCapture() {
            Utilities.log("Audio processing started. Press Ctrl+C to stop.")

            // Keep running until user interrupts
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)  // Sleep for 1 second
                Utilities.log("Pipeline running... (Ctrl+C to stop)")
            }
        } else {
            throw CommandError.audioProcessingFailed("Failed to start audio capture")
        }
    }
}

/// Command for recording a target voice for cloning
struct RecordTargetVoiceCommand: Command {
    static var commandName: String { "record-target-voice" }
    static var description: String { "Record a target voice for cloning" }

    private let audioProcessor: AudioProcessorProtocol
    private let voiceCloner: VoiceCloner

    init(audioProcessor: AudioProcessorProtocol, voiceCloner: VoiceCloner) {
        self.audioProcessor = audioProcessor
        self.voiceCloner = voiceCloner
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Recording target voice...")
        Utilities.log("Please speak for 5 seconds to capture your voice characteristics.")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        // Create a buffer to store the recorded audio
        let sampleRate = AudioProcessor.AudioFormatSettings.sampleRate
        let recordingDuration: Double = 5.0
        let recordingBufferSize = Int(sampleRate * recordingDuration)
        var recordingBuffer = [Float](repeating: 0.0, count: recordingBufferSize)
        var recordingIndex = 0
        var isRecording = true

        // Set up audio processing callback to capture audio
        mutableAudioProcessor.audioProcessingCallback = { inputBuffer in
            if isRecording && recordingIndex + inputBuffer.count <= recordingBufferSize {
                // Copy input buffer to recording buffer
                for i in 0..<inputBuffer.count {
                    recordingBuffer[recordingIndex + i] = inputBuffer[i]
                }
                recordingIndex += inputBuffer.count

                // Check if we've recorded enough audio
                if recordingIndex >= recordingBufferSize {
                    isRecording = false
                    Utilities.log("Recording complete!")
                }
            }

            // Return the input buffer for monitoring
            return inputBuffer
        }

        // Start audio processing
        if mutableAudioProcessor.startCapture() {
            Utilities.log("Recording started. Please speak now...")

            // Wait for recording to complete
            while isRecording {
                try await Task.sleep(nanoseconds: 100_000_000)  // Sleep for 0.1 second
                let progress = Double(recordingIndex) / Double(recordingBufferSize) * 100.0
                Utilities.log("Recording progress: \(Int(progress))%")
            }

            // Stop audio processing
            mutableAudioProcessor.stopCapture()

            // Set the target voice
            voiceCloner.setTargetVoice(audioSample: recordingBuffer, sampleRate: sampleRate)

            Utilities.log("Target voice set successfully!")
        } else {
            throw CommandError.audioProcessingFailed("Failed to start audio capture")
        }
    }
}

/// Command for testing voice cloning with live audio
struct TestVoiceCloningCommand: Command {
    static var commandName: String { "test-voice-cloning" }
    static var description: String { "Test voice cloning with live audio" }

    private let audioProcessor: AudioProcessorProtocol
    private let voiceCloner: VoiceCloner

    init(audioProcessor: AudioProcessorProtocol, voiceCloner: VoiceCloner) {
        self.audioProcessor = audioProcessor
        self.voiceCloner = voiceCloner
    }

    @MainActor
    func execute() async throws {
        // Check if a target voice is set
        guard voiceCloner.hasTargetVoice() else {
            throw CommandError.invalidArguments(
                "No target voice set. Please record a target voice first using the 'record-target-voice' command."
            )
        }

        Utilities.log("Testing voice cloning...")
        Utilities.log("Your voice will be converted to the target voice in real-time.")
        Utilities.log("Press Ctrl+C to stop.")

        // Create a copy of the audio processor
        var mutableAudioProcessor = audioProcessor

        // Set up audio processing callback for voice cloning
        mutableAudioProcessor.audioProcessingCallback = { inputBuffer in
            // Clone the voice
            let outputBuffer = voiceCloner.cloneVoice(
                inputAudio: inputBuffer,
                sampleRate: AudioProcessor.AudioFormatSettings.sampleRate
            )

            // Return the cloned audio
            return outputBuffer
        }

        // Start audio processing
        if mutableAudioProcessor.startCapture() {
            Utilities.log("Voice cloning started. Speak into the microphone...")

            // Keep running until user interrupts
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)  // Sleep for 1 second
                Utilities.log("Voice cloning running... (Ctrl+C to stop)")
            }
        } else {
            throw CommandError.audioProcessingFailed("Failed to start audio capture")
        }
    }
}

/// Command for file-based voice cloning
struct FileBasedVoiceCloningCommand: Command {
    static var commandName: String { "clone-from-file" }
    static var description: String { "Clone voice from audio files" }

    private let voiceCloner: VoiceCloner

    init(voiceCloner: VoiceCloner) {
        self.voiceCloner = voiceCloner
    }

    @MainActor
    func execute() async throws {
        Utilities.log("File-based voice cloning...")

        // Parse command line arguments for file paths
        let arguments = CommandLine.arguments

        // Check for required arguments
        guard arguments.count >= 7 else {
            throw CommandError.invalidArguments(
                "Usage: \(Self.commandName) --target-voice <target.wav> --source-voice <source.wav> --output <output.wav>"
            )
        }

        // Extract file paths from arguments
        var targetVoicePath: String?
        var sourceVoicePath: String?
        var outputPath: String?

        var i = 2
        while i < arguments.count {
            switch arguments[i] {
            case "--target-voice":
                if i + 1 < arguments.count {
                    targetVoicePath = arguments[i + 1]
                    i += 2
                } else {
                    throw CommandError.invalidArguments("Missing value for --target-voice")
                }
            case "--source-voice":
                if i + 1 < arguments.count {
                    sourceVoicePath = arguments[i + 1]
                    i += 2
                } else {
                    throw CommandError.invalidArguments("Missing value for --source-voice")
                }
            case "--output":
                if i + 1 < arguments.count {
                    outputPath = arguments[i + 1]
                    i += 2
                } else {
                    throw CommandError.invalidArguments("Missing value for --output")
                }
            default:
                i += 1
            }
        }

        // Validate file paths
        guard let targetVoicePath = targetVoicePath else {
            throw CommandError.invalidArguments("Missing --target-voice argument")
        }

        guard let sourceVoicePath = sourceVoicePath else {
            throw CommandError.invalidArguments("Missing --source-voice argument")
        }

        guard let outputPath = outputPath else {
            throw CommandError.invalidArguments("Missing --output argument")
        }

        // Load target voice file
        Utilities.log("Loading target voice file: \(targetVoicePath)")
        let targetVoiceURL = URL(fileURLWithPath: targetVoicePath)

        do {
            let (targetAudio, targetSampleRate) = try AudioFileHandler.loadAudioFile(
                at: targetVoiceURL)
            Utilities.log(
                "Target voice loaded: \(targetAudio.count) samples at \(targetSampleRate) Hz")

            // Set the target voice
            voiceCloner.setTargetVoice(audioSample: targetAudio, sampleRate: targetSampleRate)
            Utilities.log("Target voice set successfully")

            // Load source voice file
            Utilities.log("Loading source voice file: \(sourceVoicePath)")
            let sourceVoiceURL = URL(fileURLWithPath: sourceVoicePath)
            let (sourceAudio, sourceSampleRate) = try AudioFileHandler.loadAudioFile(
                at: sourceVoiceURL)
            Utilities.log(
                "Source voice loaded: \(sourceAudio.count) samples at \(sourceSampleRate) Hz")

            // Clone the voice
            Utilities.log("Cloning voice...")
            Utilities.startTimer(id: "voice_cloning")
            let outputAudio = voiceCloner.cloneVoice(
                inputAudio: sourceAudio, sampleRate: sourceSampleRate)
            let cloningTime = Utilities.endTimer(id: "voice_cloning")
            Utilities.log("Voice cloning completed in \(String(format: "%.2f", cloningTime)) ms")

            // Save the output file
            Utilities.log("Saving output to: \(outputPath)")
            let outputURL = URL(fileURLWithPath: outputPath)
            try AudioFileHandler.saveAudioFile(
                audioData: outputAudio, to: outputURL, sampleRate: sourceSampleRate)
            Utilities.log("Output saved successfully")

        } catch let error as AudioFileHandler.AudioFileError {
            switch error {
            case .fileNotFound(let message):
                throw CommandError.fileNotFound(message)
            case .invalidFormat(let message), .readError(let message), .writeError(let message):
                throw CommandError.audioProcessingFailed(message)
            }
        } catch {
            throw CommandError.audioProcessingFailed("Unexpected error: \(error)")
        }
    }
}

/// Command for showing help information
struct HelpCommand: Command {
    static var commandName: String { "help" }
    static var description: String { "Show this help information" }

    private let availableCommands: [String: Command.Type]

    init(availableCommands: [String: Command.Type]) {
        self.availableCommands = availableCommands
    }

    @MainActor
    func execute() async throws {
        Utilities.log("Usage: prj-silicon-voice-cloning [command]")
        Utilities.log("")
        Utilities.log("Available commands:")

        // Sort commands alphabetically for consistent output
        let sortedCommands = availableCommands.keys.sorted()

        for commandName in sortedCommands {
            if let commandType = availableCommands[commandName] {
                Utilities.log(
                    "  \(commandName.padding(toLength: 20, withPad: " ", startingAt: 0)) \(commandType.description)"
                )
            }
        }
    }
}
