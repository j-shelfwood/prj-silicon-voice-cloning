import Foundation

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

        public init(
            captureSucceeds: Bool = true, playbackSucceeds: Bool = true,
            simulatedLatencyMs: Double = 20.0
        ) {
            self.captureSucceeds = captureSucceeds
            self.playbackSucceeds = playbackSucceeds
            self.simulatedLatencyMs = simulatedLatencyMs
        }
    }

    /// Configuration for this mock instance
    private let config: MockConfig

    /// Initializes a new MockAudioProcessor with the specified configuration
    public init(config: MockConfig = MockConfig()) {
        self.config = config
        print("MockAudioProcessor initialized")
    }

    /// Simulates starting audio capture
    public func startCapture() -> Bool {
        guard !isRunning else {
            print("Audio capture already running")
            return true
        }

        guard config.captureSucceeds else {
            print("Failed to set up input audio unit (simulated failure)")
            return false
        }

        isRunning = true
        print("Audio capture started (simulated)")
        return true
    }

    /// Simulates stopping audio capture
    public func stopCapture() {
        guard isRunning else { return }

        isRunning = false
        print("Audio capture stopped (simulated)")
    }

    /// Simulates playing audio
    public func playAudio(_ buffer: [Float]) -> Bool {
        guard !isRunning else {
            print(
                "Audio system is already running in real-time mode. Use the processing callback instead."
            )
            return false
        }

        guard config.playbackSucceeds else {
            print("Failed to set up output audio unit for playback (simulated failure)")
            return false
        }

        capturedAudioBuffer = buffer

        // Process the buffer if a callback is set
        if let processingCallback = audioProcessingCallback {
            let _ = processingCallback(buffer)
        }

        // Record timestamps for latency calculation
        let now = CFAbsoluteTimeGetCurrent()
        captureTimestamps.append(now)
        playbackTimestamps.append(now + (config.simulatedLatencyMs / 1000.0))

        // Simulate playback duration without actually sleeping
        let playbackDuration = Double(buffer.count) / 44100.0
        print("Playback completed (simulated duration: \(playbackDuration) seconds)")

        return true
    }

    /// Returns the simulated latency
    public var measuredLatency: Double {
        if !captureTimestamps.isEmpty && !playbackTimestamps.isEmpty {
            let count = min(captureTimestamps.count, playbackTimestamps.count)
            var totalLatency = 0.0
            for i in 0..<count {
                totalLatency += playbackTimestamps[i] - captureTimestamps[i]
            }
            return (totalLatency / Double(count)) * 1000.0
        } else {
            return config.simulatedLatencyMs
        }
    }
}
