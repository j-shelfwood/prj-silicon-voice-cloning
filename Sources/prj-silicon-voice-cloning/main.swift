// The Swift Programming Language
// https://docs.swift.org/swift-book

// Real-Time Voice Cloning on Apple Silicon (M3 Max)
// Main entry point for the CLI application

import Foundation
import AudioProcessor
import DSP
import ModelInference
import Utilities

// Print welcome message
Utilities.log("Real-Time Voice Cloning on Apple Silicon")
Utilities.log("----------------------------------------")
Utilities.log("Welcome to the CLI interface for real-time voice conversion!")

// Initialize components
let audioProcessor = AudioProcessor()
let dsp = DSP(fftSize: 1024)
let modelInference = ModelInference()

// Basic CLI argument handling
let arguments = CommandLine.arguments

if arguments.count > 1 {
    let command = arguments[1]
    switch command {
    case "test-audio":
        Utilities.log("Testing audio output with a sine wave...")

        // Generate a 440Hz sine wave for 2 seconds at 44.1kHz
        Utilities.startTimer(id: "sine_generation")
        let sineWave = Utilities.generateSineWave(frequency: 440.0, sampleRate: 44100.0, duration: 2.0)
        let generationTime = Utilities.endTimer(id: "sine_generation")

        Utilities.log("Generated sine wave with \(sineWave.count) samples in \(String(format: "%.2f", generationTime))ms")

        // Play the sine wave
        Utilities.log("Playing sine wave...")
        let _ = audioProcessor.playAudio(sineWave)

    case "test-passthrough":
        Utilities.log("Testing audio pass-through (microphone → speakers)...")
        Utilities.log("This will capture audio from your microphone and play it through your speakers.")
        Utilities.log("Press Ctrl+C to stop.")

        // Set up a simple pass-through (no processing)
        audioProcessor.audioProcessingCallback = { buffer in
            return buffer // Just pass the audio through without modification
        }

        // Start audio capture and processing
        if audioProcessor.startCapture() {
            Utilities.log("Audio pass-through started. Speak into your microphone to hear your voice.")

            // Keep the program running until user interrupts
            RunLoop.main.run()
        } else {
            Utilities.log("Failed to start audio pass-through!")
        }

    case "test-latency":
        Utilities.log("Testing audio processing latency...")

        // Set up a simple pass-through to measure latency
        audioProcessor.audioProcessingCallback = { buffer in
            return buffer // Just pass the audio through without modification
        }

        // Start audio capture and processing
        if audioProcessor.startCapture() {
            Utilities.log("Audio processing started for latency testing.")
            Utilities.log("Speak into your microphone to generate audio.")
            Utilities.log("Press Enter to stop and see latency measurement.")

            // Wait for user to press Enter
            _ = readLine()

            // Stop capture and display latency
            audioProcessor.stopCapture()
            let latency = audioProcessor.measuredLatency
            Utilities.log("Measured audio processing latency: \(String(format: "%.2f", latency)) ms")
        } else {
            Utilities.log("Failed to start audio processing for latency test!")
        }

    case "test-dsp":
        Utilities.log("Testing DSP with live audio...")

        // Set up an audio processing pipeline that applies FFT and IFFT (just for testing)
        audioProcessor.audioProcessingCallback = { buffer in
            // Perform FFT (in real implementation, this would feed into the ML model)
            Utilities.startTimer(id: "fft")
            let _ = dsp.performFFT(inputBuffer: buffer)
            let fftTime = Utilities.endTimer(id: "fft")

            // Log FFT performance occasionally
            if Int.random(in: 0...100) < 5 { // Log ~5% of the time to avoid console spam
                Utilities.log("FFT processing time: \(String(format: "%.2f", fftTime)) ms")
            }

            // For now, just return the input buffer (pass-through)
            return buffer
        }

        // Start audio capture and processing
        if audioProcessor.startCapture() {
            Utilities.log("Audio processing with DSP started.")
            Utilities.log("Press Enter to stop.")

            // Wait for user to press Enter
            _ = readLine()

            // Stop capture
            audioProcessor.stopCapture()
        } else {
            Utilities.log("Failed to start audio processing with DSP!")
        }

    case "test-ml":
        Utilities.log("Testing ML capabilities...")

        // Check if Core ML is available
        Utilities.log("Core ML available: \(modelInference.isCoreMLAvailable())")
        Utilities.log(modelInference.getAvailableComputeUnits())

    case "help":
        fallthrough
    default:
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
} else {
    Utilities.log("\nNo command specified. Use 'help' for available commands.")
}
