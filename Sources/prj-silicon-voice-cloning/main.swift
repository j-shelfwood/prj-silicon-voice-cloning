import AudioProcessor
import DSP
import Foundation
import ModelInference
import Utilities

@MainActor
func main() async {
    Utilities.log("Real-Time Voice Cloning on Apple Silicon")
    Utilities.log("----------------------------------------")
    Utilities.log("Welcome to the CLI interface for real-time voice conversion!")

    let audioProcessor = AudioProcessor()
    let dsp = DSP(fftSize: 1024)
    let modelInference = ModelInference()

    await handleCommandLineArguments(
        audioProcessor: audioProcessor, dsp: dsp, modelInference: modelInference)
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
    audioProcessor: AudioProcessor, dsp: DSP, modelInference: ModelInference
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

    case "help":
        showHelp()

    default:
        Utilities.log("Unknown command: \(command)")
        showHelp()
    }
}

/// Display help information for all available commands
func showHelp() {
    Utilities.log("\nUsage:")
    Utilities.log("  swift run prj-silicon-voice-cloning [command]")
    Utilities.log("\nAvailable commands:")
    Utilities.log("  test-audio       Test audio output with a sine wave")
    Utilities.log("  test-passthrough Test microphone to speaker pass-through")
    Utilities.log("  test-latency     Measure audio processing latency")
    Utilities.log("  test-dsp         Test DSP functionality with live audio")
    Utilities.log("  test-ml          Test ML capabilities")
    Utilities.log("  help             Show this help message")
}

/// Test audio playback using a sine wave
@MainActor
func testAudio(audioProcessor: AudioProcessor) async {
    Utilities.log("Testing audio output with a sine wave...")

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
    let _ = audioProcessor.playAudio(quieterSineWave)
}

/// Test real-time audio pass-through (microphone to speakers)
@MainActor
func testPassthrough(audioProcessor: AudioProcessor) async {
    Utilities.log("Testing audio pass-through (microphone → speakers)...")
    Utilities.log("This will capture audio from your microphone and play it through your speakers.")
    Utilities.log("Press Enter to stop.")

    audioProcessor.audioProcessingCallback = { buffer in
        return buffer
    }

    if audioProcessor.startCapture() {
        Utilities.log("Audio pass-through started. Speak into your microphone to hear your voice.")

        // Wait for user input instead of RunLoop.main.run()
        _ = readLine()
        audioProcessor.stopCapture()
    } else {
        Utilities.log("Failed to start audio pass-through!")
    }
}

/// Test and measure audio processing latency
@MainActor
func testLatency(audioProcessor: AudioProcessor) async {
    Utilities.log("Testing audio processing latency...")

    audioProcessor.audioProcessingCallback = { buffer in
        return buffer
    }

    if audioProcessor.startCapture() {
        Utilities.log("Audio processing started for latency testing.")
        Utilities.log("Speak into your microphone to generate audio.")
        Utilities.log("Press Enter to stop and see latency measurement.")

        _ = readLine()

        audioProcessor.stopCapture()
        let latency = audioProcessor.measuredLatency
        Utilities.log("Measured audio processing latency: \(String(format: "%.2f", latency)) ms")
    } else {
        Utilities.log("Failed to start audio processing for latency test!")
    }
}

/// Test DSP functionality with live audio
@MainActor
func testDSP(audioProcessor: AudioProcessor, dsp: DSP) async {
    Utilities.log("Testing DSP with live audio...")

    audioProcessor.audioProcessingCallback = { [dsp] buffer in
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

    if audioProcessor.startCapture() {
        Utilities.log("Audio processing with DSP started.")
        Utilities.log("Press Enter to stop.")

        _ = readLine()
        audioProcessor.stopCapture()
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
