import Foundation
import Utilities

/// Class for tracking performance metrics of machine learning model inference
public class PerformanceTracker {
    /// Performance metrics for model inference
    public struct PerformanceMetrics {
        /// Time taken for inference in milliseconds
        public var inferenceTime: Double = 0.0
        /// Number of frames processed
        public var framesProcessed: Int = 0
        /// Real-time factor (time taken / audio duration)
        public var realTimeFactor: Double = 0.0
        /// Memory usage in megabytes
        public var memoryUsageMB: Double = 0.0
        /// CPU usage percentage
        public var cpuUsagePercent: Double = 0.0

        public init() {}

        /// Returns a string representation of the metrics
        public var description: String {
            return """
                Inference Time: \(String(format: "%.2f", inferenceTime)) ms
                Frames Processed: \(framesProcessed)
                Real-Time Factor: \(String(format: "%.3f", realTimeFactor))
                Memory Usage: \(String(format: "%.2f", memoryUsageMB)) MB
                CPU Usage: \(String(format: "%.1f", cpuUsagePercent))%
                """
        }
    }

    /// Latest performance metrics
    public private(set) var metrics = PerformanceMetrics()

    /// History of performance metrics
    public private(set) var metricsHistory: [PerformanceMetrics] = []

    /// Maximum number of metrics to keep in history
    private let maxHistorySize: Int

    /**
     Initialize a new PerformanceTracker

     - Parameter maxHistorySize: Maximum number of metrics to keep in history
     */
    @MainActor
    public init(maxHistorySize: Int = 100) {
        self.maxHistorySize = maxHistorySize
        Utilities.log("PerformanceTracker initialized")
    }

    /**
     Update metrics with new values

     - Parameters:
       - inferenceTime: Time taken for inference in milliseconds
       - framesProcessed: Number of frames processed
       - audioDuration: Duration of audio in seconds
     */
    @MainActor
    public func updateMetrics(inferenceTime: Double, framesProcessed: Int, audioDuration: Double) {
        metrics.inferenceTime = inferenceTime
        metrics.framesProcessed = framesProcessed

        // Calculate real-time factor
        if audioDuration > 0 {
            metrics.realTimeFactor = inferenceTime / 1000.0 / audioDuration
        } else {
            metrics.realTimeFactor = 0.0
        }

        // Add to history
        metricsHistory.append(metrics)

        // Trim history if needed
        if metricsHistory.count > maxHistorySize {
            metricsHistory.removeFirst(metricsHistory.count - maxHistorySize)
        }

        Utilities.log(
            "Updated performance metrics: RTF=\(String(format: "%.3f", metrics.realTimeFactor))")
    }

    /**
     Get average metrics over the history

     - Returns: Average performance metrics
     */
    public func getAverageMetrics() -> PerformanceMetrics {
        guard !metricsHistory.isEmpty else {
            return PerformanceMetrics()
        }

        var avgMetrics = PerformanceMetrics()

        // Calculate averages
        for metrics in metricsHistory {
            avgMetrics.inferenceTime += metrics.inferenceTime
            avgMetrics.framesProcessed += metrics.framesProcessed
            avgMetrics.realTimeFactor += metrics.realTimeFactor
            avgMetrics.memoryUsageMB += metrics.memoryUsageMB
            avgMetrics.cpuUsagePercent += metrics.cpuUsagePercent
        }

        let count = Double(metricsHistory.count)
        avgMetrics.inferenceTime /= count
        avgMetrics.framesProcessed = Int(Double(avgMetrics.framesProcessed) / count)
        avgMetrics.realTimeFactor /= count
        avgMetrics.memoryUsageMB /= count
        avgMetrics.cpuUsagePercent /= count

        return avgMetrics
    }

    /// Reset all metrics and history
    @MainActor
    public func reset() {
        metrics = PerformanceMetrics()
        metricsHistory.removeAll()
        Utilities.log("Performance metrics reset")
    }
}
