import AudioProcessor
import DSP
import Foundation
import ML
import ModelInference
import Utilities

@MainActor
func main() async {
    Utilities.log("Real-Time Voice Cloning on Apple Silicon")
    Utilities.log("----------------------------------------")
    Utilities.log("Welcome to the CLI interface for real-time voice conversion!")

    // Use MockAudioProcessor for testing to avoid audio hardware issues
    #if DEBUG
        let audioProcessor: AudioProcessorProtocol = MockAudioProcessor()
    #else
        let audioProcessor: AudioProcessorProtocol = AudioProcessor()
    #endif

    let dsp = DSP(fftSize: 1024)
    let modelInference = ModelInference()
    let voiceCloner = VoiceCloner(dsp: dsp)

    await handleCommandLineArguments(
        audioProcessor: audioProcessor, dsp: dsp, modelInference: modelInference,
        voiceCloner: voiceCloner)
}

// Call the async main function from the synchronous entry point and keep the program running
let task = Task { @MainActor in
    await main()
}

// Keep the program running until the task completes
// This is necessary because Swift's async/await requires the program to stay alive
// until async tasks complete
RunLoop.main.run(until: Date(timeIntervalSinceNow: 60))  // Allow up to 60 seconds for tasks to complete

/// Process command line arguments and execute the appropriate action
@MainActor
func handleCommandLineArguments(
    audioProcessor: AudioProcessorProtocol, dsp: DSP, modelInference: ModelInference,
    voiceCloner: VoiceCloner
) async {
    let arguments = CommandLine.arguments

    guard arguments.count > 1 else {
        showHelp()
        return
    }

    let command = arguments[1]

    switch command {
    case "test-audio":
        await testAudio(audioProcessor: audioProcessor)

    case "test-passthrough":
        await testPassthrough(audioProcessor: audioProcessor)

    case "test-latency":
        await testLatency(audioProcessor: audioProcessor)

    case "test-dsp":
        await testDSP(audioProcessor: audioProcessor, dsp: dsp)

    case "test-ml":
        testML(modelInference: modelInference)

    case "test-pipeline":
        await testMinimalPipeline(
            audioProcessor: audioProcessor, dsp: dsp, modelInference: modelInference)

    case "record-target-voice":
        await recordTargetVoice(audioProcessor: audioProcessor, voiceCloner: voiceCloner)

    case "test-voice-cloning":
        await testVoiceCloning(audioProcessor: audioProcessor, voiceCloner: voiceCloner)

    case "help":
        showHelp()

    default:
        Utilities.log("Unknown command: \(command)")
        showHelp()
    }
}

/// Show help information
@MainActor
func showHelp() {
    Utilities.log("Usage: prj-silicon-voice-cloning [command]")
    Utilities.log("")
    Utilities.log("Available commands:")
    Utilities.log("  test-audio         Test audio input/output")
    Utilities.log("  test-passthrough   Test audio passthrough")
    Utilities.log("  test-latency       Measure audio processing latency")
    Utilities.log("  test-dsp           Test DSP functionality with live audio")
    Utilities.log("  test-ml            Test ML capabilities")
    Utilities.log("  test-pipeline      Test minimal end-to-end pipeline")
    Utilities.log("  record-target-voice Record a target voice for cloning")
    Utilities.log("  test-voice-cloning Test voice cloning with live audio")
    Utilities.log("  help               Show this help information")
}

/// Test audio playback using a sine wave
@MainActor
func testAudio(audioProcessor: AudioProcessorProtocol) async {
    Utilities.log("Testing audio output with a sine wave...")

    // Create a mutable copy of the audio processor
    var mutableAudioProcessor = audioProcessor

    Utilities.startTimer(id: "sine_generation")
    let sineWave = Utilities.generateSineWave(frequency: 440.0, sampleRate: 44100.0, duration: 2.0)
    let generationTime = Utilities.endTimer(id: "sine_generation")

    Utilities.log(
        "Generated sine wave with \(sineWave.count) samples in \(String(format: "%.2f", generationTime))ms"
    )

    // Reduce volume to 20% of original
    let volumeScale: Float = 0.2
    let quieterSineWave = sineWave.map { $0 * volumeScale }

    Utilities.log("Playing sine wave at \(Int(volumeScale * 100))% volume...")
    mutableAudioProcessor.audioProcessingCallback = { buffer in
        return buffer
    }
}

/// Test real-time audio pass-through (microphone to speakers)
@MainActor
func testPassthrough(audioProcessor: AudioProcessorProtocol) async {
    Utilities.log("Testing audio pass-through (microphone → speakers)...")
    Utilities.log("This will capture audio from your microphone and play it through your speakers.")
    Utilities.log("Press Enter to stop.")

    // Create a mutable copy of the audio processor
    var mutableAudioProcessor = audioProcessor

    mutableAudioProcessor.audioProcessingCallback = { buffer in
        return buffer
    }

    if mutableAudioProcessor.startCapture() {
        Utilities.log("Audio pass-through started. Speak into your microphone to hear your voice.")

        // Wait for user input instead of RunLoop.main.run()
        _ = readLine()
        mutableAudioProcessor.stopCapture()
    } else {
        Utilities.log("Failed to start audio pass-through!")
    }
}

/// Test and measure audio processing latency
@MainActor
func testLatency(audioProcessor: AudioProcessorProtocol) async {
    Utilities.log("Testing audio processing latency...")

    // Create a mutable copy of the audio processor
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
        Utilities.log("Measured audio processing latency: \(String(format: "%.2f", latency)) ms")
    } else {
        Utilities.log("Failed to start audio processing for latency test!")
    }
}

/// Test DSP functionality with live audio
@MainActor
func testDSP(audioProcessor: AudioProcessorProtocol, dsp: DSP) async {
    Utilities.log("Testing DSP with live audio...")

    // Create a mutable copy of the audio processor
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
    } else {
        Utilities.log("Failed to start audio processing with DSP!")
    }
}

/// Test ML capabilities of the system
@MainActor
func testML(modelInference: ModelInference) {
    Utilities.log("Testing ML capabilities...")
    Utilities.log("Core ML available: \(modelInference.isCoreMLAvailable())")
    Utilities.log(modelInference.getAvailableComputeUnits())
}

/// Test a minimal end-to-end pipeline for voice conversion
@MainActor
func testMinimalPipeline(
    audioProcessor: AudioProcessorProtocol, dsp: DSP, modelInference: ModelInference
) async {
    Utilities.log("Testing minimal end-to-end pipeline...")

    // Create a mutable copy of the audio processor
    var mutableAudioProcessor = audioProcessor

    // Step 1: Set up audio processing callback
    mutableAudioProcessor.audioProcessingCallback = { inputBuffer in
        // Step 2: Convert audio to mel spectrogram
        let spectrogram = dsp.generateSpectrogram(inputBuffer: inputBuffer)
        let melSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)

        // Step 3: For now, just return the input (placeholder for model inference)
        // In a complete implementation, this would:
        // - Pass the mel spectrogram to a voice conversion model
        // - Convert the output back to audio
        return inputBuffer
    }

    // Step 4: Start audio processing
    do {
        if mutableAudioProcessor.startCapture() {
            Utilities.log("Audio processing started. Press Ctrl+C to stop.")

            // Keep running until user interrupts
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)  // Sleep for 1 second
                Utilities.log("Pipeline running... (Ctrl+C to stop)")
            }
        } else {
            Utilities.log("Error: Failed to start audio capture")
        }
    } catch {
        Utilities.log("Error: \(error)")
    }
}

/// Record a target voice for cloning
@MainActor
func recordTargetVoice(audioProcessor: AudioProcessorProtocol, voiceCloner: VoiceCloner) async {
    Utilities.log("Recording target voice...")
    Utilities.log("Please speak for 5 seconds to capture your voice characteristics.")

    // Create a mutable copy of the audio processor
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
    do {
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
            Utilities.log("Error: Failed to start audio capture")
        }
    } catch {
        Utilities.log("Error: \(error)")
    }
}

/// Test voice cloning with live audio
@MainActor
func testVoiceCloning(audioProcessor: AudioProcessorProtocol, voiceCloner: VoiceCloner) async {
    // Check if a target voice is set
    guard voiceCloner.hasTargetVoice() else {
        Utilities.log("Error: No target voice set. Please record a target voice first.")
        Utilities.log("Use the 'record-target-voice' command to record a target voice.")
        return
    }

    Utilities.log("Testing voice cloning...")
    Utilities.log("Your voice will be converted to the target voice in real-time.")
    Utilities.log("Press Ctrl+C to stop.")

    // Create a mutable copy of the audio processor
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
    do {
        if mutableAudioProcessor.startCapture() {
            Utilities.log("Voice cloning started. Speak into the microphone...")

            // Keep running until user interrupts
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)  // Sleep for 1 second
                Utilities.log("Voice cloning running... (Ctrl+C to stop)")
            }
        } else {
            Utilities.log("Error: Failed to start audio capture")
        }
    } catch {
        Utilities.log("Error: \(error)")
    }
}
