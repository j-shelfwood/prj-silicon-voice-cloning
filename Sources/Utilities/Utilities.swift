import Foundation

/// Main utility class that provides access to all utility functions.
/// This class serves as a facade for the specialized utility classes.
public class Utilities {
    /**
     Start a timer with the given ID

     - Parameter id: Unique identifier for this timer
     */
    @MainActor
    public static func startTimer(id: String) {
        TimerUtility.startTimer(id: id)
    }

    /**
     End a timer and return the elapsed time in milliseconds

     - Parameter id: Identifier of the timer to end
     - Returns: Elapsed time in milliseconds
     */
    @MainActor
    public static func endTimer(id: String) -> Double {
        return TimerUtility.endTimer(id: id)
    }

    /**
     Log a message with a timestamp

     - Parameter message: The message to log
     */
    @MainActor
    public static func log(_ message: String) {
        LoggerUtility.log(message)
    }

    /**
     Generate a sine wave for testing audio output

     - Parameters:
       - frequency: Frequency of the sine wave in Hz
       - sampleRate: Sample rate in Hz
       - duration: Duration of the sine wave in seconds
     - Returns: Array of float samples representing the sine wave
     */
    public static func generateSineWave(frequency: Float, sampleRate: Float, duration: Float)
        -> [Float]
    {
        return AudioSignalUtility.generateSineWave(
            frequency: frequency, sampleRate: sampleRate, duration: duration)
    }
}
