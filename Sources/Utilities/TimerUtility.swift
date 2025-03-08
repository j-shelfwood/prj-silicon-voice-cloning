import Foundation
import os.lock

/// Utility functions for timing operations in the voice cloning system.
public class TimerUtility {
    /// Dictionary to store timer start times
    nonisolated(unsafe) private static var timers: [String: CFAbsoluteTime] = [:]

    /// Lock for thread safety
    nonisolated(unsafe) private static var timerLock = os_unfair_lock()

    /// Cache for frequently used timers
    nonisolated(unsafe) private static var timerCache: [String: Double] = [:]
    nonisolated(unsafe) private static var cacheDuration: TimeInterval = 0.1  // Cache duration in seconds
    nonisolated(unsafe) private static var cacheTimestamps: [String: TimeInterval] = [:]

    /**
     Start a timer with the given ID

     - Parameter id: Unique identifier for this timer
     */
    public static func startTimer(id: String) {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        timers[id] = CFAbsoluteTimeGetCurrent()
    }

    /**
     End a timer and return the elapsed time in milliseconds

     - Parameter id: Identifier of the timer to end
     - Returns: Elapsed time in milliseconds
     */
    @MainActor
    public static func endTimer(id: String) -> Double {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        guard let startTime = timers[id] else {
            LoggerUtility.debug("Warning: Timer with ID '\(id)' doesn't exist")
            return 0.0
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let elapsedTime = (endTime - startTime) * 1000.0  // Convert to milliseconds
        timers.removeValue(forKey: id)
        return elapsedTime
    }

    /**
     Get the last measured time for a timer without restarting it

     - Parameter id: Identifier of the timer to check
     - Returns: Last measured time in milliseconds, or nil if not available
     */
    public static func getLastMeasuredTime(id: String) -> Double? {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        // Check if we have a cached result
        if let cachedTime = timerCache[id],
            let timestamp = cacheTimestamps[id],
            CFAbsoluteTimeGetCurrent() - timestamp < cacheDuration
        {
            return cachedTime
        }

        return nil
    }

    /**
     Check if a timer with the given ID exists

     - Parameter id: Identifier of the timer to check
     - Returns: Boolean indicating whether the timer exists
     */
    public static func timerExists(id: String) -> Bool {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        return timers[id] != nil
    }

    /**
     Get all active timer IDs

     - Returns: Array of active timer IDs
     */
    public static func activeTimers() -> [String] {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        return Array(timers.keys)
    }

    /**
     Reset all timers
     */
    public static func resetAllTimers() {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        timers.removeAll()
        timerCache.removeAll()
        cacheTimestamps.removeAll()
    }

    /**
     Set the cache duration for timer results

     - Parameter duration: Duration in seconds
     */
    public static func setCacheDuration(duration: TimeInterval) {
        os_unfair_lock_lock(&timerLock)
        defer { os_unfair_lock_unlock(&timerLock) }

        cacheDuration = duration
    }
}
