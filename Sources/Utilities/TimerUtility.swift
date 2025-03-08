import Foundation

/// Utility functions for timing operations in the voice cloning system.
public class TimerUtility {
    /// Dictionary to store timer start times
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
     Check if a timer with the given ID exists

     - Parameter id: Identifier of the timer to check
     - Returns: Boolean indicating whether the timer exists
     */
    @MainActor
    public static func timerExists(id: String) -> Bool {
        return timers[id] != nil
    }

    /**
     Get all active timer IDs

     - Returns: Array of active timer IDs
     */
    @MainActor
    public static func activeTimers() -> [String] {
        return Array(timers.keys)
    }

    /**
     Reset all timers
     */
    @MainActor
    public static func resetAllTimers() {
        timers.removeAll()
    }
}
