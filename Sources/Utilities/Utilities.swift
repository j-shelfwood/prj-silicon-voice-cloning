import Foundation

/**
 Utility functions for the voice cloning system including timing,
 logging, and audio generation helpers.
 */
public class Utilities {

    @MainActor
    private static var timers: [String: CFAbsoluteTime] = [:]

    /**
     Start a timer with the given ID

     - Parameter id: Unique identifier for this timer
     */
    @MainActor
    public static func startTimer(id: String) {
        timers[id] = CFAbsoluteTimeGetCurrent()
    }

    /**
     End a timer and return the elapsed time in milliseconds

     - Parameter id: Identifier of the timer to end
     - Returns: Elapsed time in milliseconds
     */
    @MainActor
    public static func endTimer(id: String) -> Double {
        guard let startTime = timers[id] else {
            print("Warning: Timer with ID '\(id)' doesn't exist")
            return 0
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let elapsedTime = (endTime - startTime) * 1000
        timers.removeValue(forKey: id)

        return elapsedTime
    }

    /**
     Log a message with a timestamp

     - Parameter message: The message to log
     */
    public static func log(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    /**
     Generate a sine wave for testing audio output

     - Parameters:
       - frequency: Frequency of the sine wave in Hz
       - sampleRate: Sample rate in Hz
       - duration: Duration of the sine wave in seconds
     - Returns: Array of float samples representing the sine wave
     */
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