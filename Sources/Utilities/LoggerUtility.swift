import Foundation

/// Utility functions for logging in the voice cloning system.
public class LoggerUtility {
    /// Log levels for controlling verbosity
    public enum LogLevel: Int {
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
    }

    /// Current log level (messages below this level will not be logged)
    @MainActor
    public static var currentLogLevel: LogLevel = .info

    /// Whether to include timestamps in log messages
    @MainActor
    public static var includeTimestamps: Bool = true

    /// Whether to include log levels in log messages
    @MainActor
    public static var includeLogLevels: Bool = true

    /**
     Log a message with a timestamp

     - Parameters:
       - message: The message to log
       - level: The log level of the message
     */
    @MainActor
    public static func log(_ message: String, level: LogLevel = .info) {
        // Skip if message level is below current log level
        guard level.rawValue >= currentLogLevel.rawValue else {
            return
        }

        var logMessage = ""

        // Add timestamp if enabled
        if includeTimestamps {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let timestamp = dateFormatter.string(from: Date())
            logMessage += "[\(timestamp)] "
        }

        // Add log level if enabled
        if includeLogLevels {
            logMessage += "[\(level.prefix)] "
        }

        // Add the actual message
        logMessage += message

        // Print to console
        print(logMessage)
    }

    /**
     Log a debug message

     - Parameter message: The debug message to log
     */
    @MainActor
    public static func debug(_ message: String) {
        log(message, level: .debug)
    }

    /**
     Log an info message

     - Parameter message: The info message to log
     */
    @MainActor
    public static func info(_ message: String) {
        log(message, level: .info)
    }

    /**
     Log a warning message

     - Parameter message: The warning message to log
     */
    @MainActor
    public static func warning(_ message: String) {
        log(message, level: .warning)
    }

    /**
     Log an error message

     - Parameter message: The error message to log
     */
    @MainActor
    public static func error(_ message: String) {
        log(message, level: .error)
    }
}
