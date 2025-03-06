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
Utilities.log("Welcome to the CLI interface for real-time voice cloning!")

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
        let _ = audioProcessor.playAudio(sineWave)

    case "test-dsp":
        Utilities.log("Testing DSP with a sine wave...")

        // Generate a 440Hz sine wave for 1 second at 44.1kHz
        let sineWave = Utilities.generateSineWave(frequency: 440.0, sampleRate: 44100.0, duration: 1.0)

        // Perform FFT
        Utilities.startTimer(id: "fft")
        let fftResult = dsp.performFFT(inputBuffer: sineWave)
        let fftTime = Utilities.endTimer(id: "fft")

        Utilities.log("Performed FFT in \(String(format: "%.2f", fftTime))ms")

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
        Utilities.log("  test-audio    Test audio output with a sine wave")
        Utilities.log("  test-dsp      Test DSP functionality")
        Utilities.log("  test-ml       Test ML capabilities")
        Utilities.log("  help          Show this help message")
    }
} else {
    Utilities.log("\nNo command specified. Use 'help' for available commands.")
}
