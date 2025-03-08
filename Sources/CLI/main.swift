import AudioProcessor
import DSP
import Foundation
import ML
import ModelInference
import Utilities

@MainActor
func main() async {
    // Configure logging
    LoggerUtility.currentLogLevel = .debug

    Utilities.log("Real-Time Voice Cloning on Apple Silicon")
    Utilities.log("----------------------------------------")
    Utilities.log("Welcome to the CLI interface for real-time voice conversion!")

    // Use MockAudioProcessor for testing to avoid audio hardware issues
    #if DEBUG
        let mockConfig = MockAudioProcessor.MockConfig(
            captureSucceeds: true,
            playbackSucceeds: true,
            simulatedLatencyMs: 20.0,
            enableLogging: true
        )
        let audioProcessor: AudioProcessorProtocol = MockAudioProcessor(config: mockConfig)
    #else
        let audioProcessor: AudioProcessorProtocol = AudioProcessor()
    #endif

    let dsp = DSP(fftSize: 1024)
    let modelInference = ModelInference()
    let voiceCloner = VoiceCloner(dsp: dsp)

    // Create the command router
    let commandRouter = CommandRouter(
        audioProcessor: audioProcessor,
        dsp: dsp,
        modelInference: modelInference,
        voiceCloner: voiceCloner
    )

    // Route and execute the command
    let success = await commandRouter.routeAndExecute(arguments: CommandLine.arguments)

    // Exit with appropriate status code
    exit(success ? 0 : 1)
}

// Call the async main function from the synchronous entry point
Task { @MainActor in
    await main()
}

// Keep the program running until the task completes or is interrupted
RunLoop.main.run()
