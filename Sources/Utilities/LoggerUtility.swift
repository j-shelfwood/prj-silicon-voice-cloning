import Foundation
import os.lock

/// Utility functions for logging in the voice cloning system.
public class LoggerUtility {
    /// Log levels for controlling verbosity
    public enum LogLevel: Int, Comparable, Sendable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        var prefix: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            }
        }

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// Current log level (messages below this level will not be logged)
    nonisolated(unsafe) private static var _currentLogLevel: LogLevel = .info

    /// Whether to include timestamps in log messages
    nonisolated(unsafe) private static var _includeTimestamps: Bool = true

    /// Whether to include log levels in log messages
    nonisolated(unsafe) private static var _includeLogLevels: Bool = true

    /// Lock for thread safety
    nonisolated(unsafe) private static var logLock = os_unfair_lock()

    /// Log buffer for batched output
    nonisolated(unsafe) private static var logBuffer: [String] = []
    nonisolated(unsafe) private static var bufferSize = 10
    nonisolated(unsafe) private static var useBuffer = false

    /// Date formatter for timestamps (cached for performance)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Current log level (thread-safe access)
    public static var currentLogLevel: LogLevel {
        get {
            os_unfair_lock_lock(&logLock)
            defer { os_unfair_lock_unlock(&logLock) }
            return _currentLogLevel
        }
        set {
            os_unfair_lock_lock(&logLock)
            _currentLogLevel = newValue
            os_unfair_lock_unlock(&logLock)
        }
    }

    /// Whether to include timestamps in log messages (thread-safe access)
    public static var includeTimestamps: Bool {
        get {
            os_unfair_lock_lock(&logLock)
            defer { os_unfair_lock_unlock(&logLock) }
            return _includeTimestamps
        }
        set {
            os_unfair_lock_lock(&logLock)
            _includeTimestamps = newValue
            os_unfair_lock_unlock(&logLock)
        }
    }

    /// Whether to include log levels in log messages (thread-safe access)
    public static var includeLogLevels: Bool {
        get {
            os_unfair_lock_lock(&logLock)
            defer { os_unfair_lock_unlock(&logLock) }
            return _includeLogLevels
        }
        set {
            os_unfair_lock_lock(&logLock)
            _includeLogLevels = newValue
            os_unfair_lock_unlock(&logLock)
        }
    }

    /**
     Configure log buffering

     - Parameters:
       - enabled: Whether to enable log buffering
       - size: Maximum number of log messages to buffer before flushing
     */
    public static func configureBuffering(enabled: Bool, size: Int = 10) {
        os_unfair_lock_lock(&logLock)

        useBuffer = enabled
        bufferSize = size

        // Flush buffer if disabling
        if !enabled && !logBuffer.isEmpty {
            flushBufferUnsafe()
        }

        os_unfair_lock_unlock(&logLock)
    }

    /**
     Flush the log buffer (not thread-safe, for internal use)
     */
    private static func flushBufferUnsafe() {
        for message in logBuffer {
            print(message)
        }
        logBuffer.removeAll()
    }

    /**
     Flush the log buffer (thread-safe)
     */
    public static func flushBuffer() {
        os_unfair_lock_lock(&logLock)
        flushBufferUnsafe()
        os_unfair_lock_unlock(&logLock)
    }

    /**
     Log a message with a timestamp

     - Parameters:
       - message: The message to log
       - level: The log level of the message
     */
    public static func log(_ message: String, level: LogLevel = .info) {
        os_unfair_lock_lock(&logLock)
        defer { os_unfair_lock_unlock(&logLock) }

        // Only log if the message level is at or above the current log level
        guard level >= _currentLogLevel else { return }

        var logMessage = ""

        // Add timestamp if enabled
        if _includeTimestamps {
            let timestamp = dateFormatter.string(from: Date())
            logMessage += "[\(timestamp)] "
        }

        // Add log level if enabled
        if _includeLogLevels {
            logMessage += "[\(level.prefix)] "
        }

        // Add the actual message
        logMessage += message

        // Either buffer or print directly
        if useBuffer {
            logBuffer.append(logMessage)

            // Flush if buffer is full
            if logBuffer.count >= bufferSize {
                flushBufferUnsafe()
            }
        } else {
            // Print directly (buffering is disabled since useBuffer is a constant)
            print(logMessage)
        }
    }

    /**
     Log a debug message

     - Parameter message: The debug message to log
     */
    public static func debug(_ message: String) {
        log(message, level: .debug)
    }

    /**
     Log an info message

     - Parameter message: The info message to log
     */
    public static func info(_ message: String) {
        log(message, level: .info)
    }

    /**
     Log a warning message

     - Parameter message: The warning message to log
     */
    public static func warning(_ message: String) {
        log(message, level: .warning)
    }

    /**
     Log an error message

     - Parameter message: The error message to log
     */
    public static func error(_ message: String) {
        log(message, level: .error)
    }
}
