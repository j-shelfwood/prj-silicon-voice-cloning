// Utilities.swift
// Helper utilities and performance profiling tools

import Foundation

/// Class containing utility functions for the voice cloning system
public class Utilities {
    // Timer for measuring performance
    @MainActor
    private static var timers: [String: CFAbsoluteTime] = [:]

    /// Start a timer with the given ID
    @MainActor
    public static func startTimer(id: String) {
        timers[id] = CFAbsoluteTimeGetCurrent()
    }

    /// End a timer and return the elapsed time in milliseconds
    @MainActor
    public static func endTimer(id: String) -> Double {
        guard let startTime = timers[id] else {
            print("Warning: Timer with ID '\(id)' doesn't exist")
            return 0
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let elapsedTime = (endTime - startTime) * 1000 // Convert to milliseconds
        timers.removeValue(forKey: id)

        return elapsedTime
    }

    /// Log a message with a timestamp
    public static func log(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    /// Generate a sine wave for testing audio output
    public static func generateSineWave(frequency: Float, sampleRate: Float, duration: Float) -> [Float] {
        let numSamples = Int(sampleRate * duration)
        var sineWave = [Float](repeating: 0.0, count: numSamples)

        for i in 0..<numSamples {
            let phase = 2.0 * Float.pi * frequency * Float(i) / sampleRate
            sineWave[i] = sin(phase)
        }

        return sineWave
    }
}