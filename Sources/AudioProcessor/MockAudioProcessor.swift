import Foundation
import Utilities

/// A mock implementation of AudioProcessorProtocol for testing purposes.
/// This implementation simulates audio processing without using actual audio hardware,
/// making it suitable for unit tests and CI environments.
public class MockAudioProcessor: AudioProcessorProtocol {
    /// Indicates whether the audio processor is currently running
    public private(set) var isRunning = false

    /// Callback function for audio processing
    public var audioProcessingCallback: (([Float]) -> [Float])?

    /// Simulated captured audio buffer
    private var capturedAudioBuffer: [Float] = []

    /// Timestamps for measuring latency
    private var captureTimestamps: [Double] = []
    private var playbackTimestamps: [Double] = []

    /// Configuration options for the mock processor
    public struct MockConfig {
        /// Whether startCapture() should succeed
        var captureSucceeds: Bool = true
        /// Whether playAudio() should succeed
        var playbackSucceeds: Bool = true
        /// Simulated latency in milliseconds
        var simulatedLatencyMs: Double = 20.0
        /// Whether to log debug messages
        var enableLogging: Bool = false

        public init(
            captureSucceeds: Bool = true,
            playbackSucceeds: Bool = true,
            simulatedLatencyMs: Double = 20.0,
            enableLogging: Bool = false
        ) {
            self.captureSucceeds = captureSucceeds
            self.playbackSucceeds = playbackSucceeds
            self.simulatedLatencyMs = simulatedLatencyMs
            self.enableLogging = enableLogging
        }
    }

    /// Configuration for this mock instance
    private let config: MockConfig

    /// Initializes a new MockAudioProcessor with the specified configuration
    public init(config: MockConfig = MockConfig()) {
        self.config = config
        logDebug("MockAudioProcessor initialized")
    }

    /// Simulates starting audio capture
    public func startCapture() -> Bool {
        guard !isRunning else {
            logDebug("MockAudioProcessor: Audio capture already running")
            return true
        }

        guard config.captureSucceeds else {
            logDebug("MockAudioProcessor: Audio capture failed (simulated failure)")
            return false
        }

        isRunning = true
        logDebug("Audio capture started (simulated)")

        // Start a timer to simulate audio callbacks
        startAudioCallbackTimer()

        return true
    }

    /// Simulates stopping audio capture
    public func stopCapture() {
        guard isRunning else {
            logDebug("MockAudioProcessor: Audio capture not running")
            return
        }

        isRunning = false
        logDebug("Audio capture stopped (simulated)")

        // Stop the audio callback timer
        stopAudioCallbackTimer()
    }

    /// Simulates playing audio
    public func playAudio(_ buffer: [Float]) -> Bool {
        // Check if the processor is already running in real-time mode
        guard !isRunning else {
            logDebug("MockAudioProcessor: Cannot play audio while running in real-time mode")
            return false
        }

        guard config.playbackSucceeds else {
            logDebug("MockAudioProcessor: Audio playback failed (simulated failure)")
            return false
        }

        // Record timestamp for latency measurement
        let timestamp = Date().timeIntervalSince1970 * 1000
        playbackTimestamps.append(timestamp)

        logDebug("Audio played (simulated): \(buffer.count) samples")
        return true
    }

    /// Returns the measured latency
    public var measuredLatency: Double {
        return config.simulatedLatencyMs
    }

    // MARK: - Private Methods

    private var audioCallbackTimer: Timer?

    /// Starts a timer to simulate audio callbacks
    private func startAudioCallbackTimer() {
        // Stop any existing timer
        stopAudioCallbackTimer()

        // Create a new timer that fires every 100ms
        audioCallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            self?.simulateAudioCallback()
        }
    }

    /// Stops the audio callback timer
    private func stopAudioCallbackTimer() {
        audioCallbackTimer?.invalidate()
        audioCallbackTimer = nil
    }

    /// Simulates an audio callback with generated audio data
    private func simulateAudioCallback() {
        guard isRunning else { return }

        // Generate a buffer of test audio data (sine wave)
        let bufferSize = 512
        var buffer = [Float](repeating: 0.0, count: bufferSize)

        // Generate a simple sine wave at 440 Hz
        let sampleRate: Double = 44100.0
        let frequency: Double = 440.0

        for i in 0..<bufferSize {
            let time = Double(i) / sampleRate
            buffer[i] = Float(sin(2.0 * Double.pi * frequency * time))
        }

        // Record timestamp for latency measurement
        let timestamp = Date().timeIntervalSince1970 * 1000
        captureTimestamps.append(timestamp)

        // Process the buffer through the callback if one is set
        if let callback = audioProcessingCallback {
            let processedBuffer = callback(buffer)

            // Simulate playback of the processed buffer
            _ = playAudio(processedBuffer)
        }
    }

    /// Log a debug message if logging is enabled
    private func logDebug(_ message: String) {
        if config.enableLogging {
            LoggerUtility.debug(message)
        }
    }
}
