import AudioToolbox
import Foundation

/// Protocol defining the interface for audio processing components.
/// This allows for creating mock implementations for testing.
public protocol AudioProcessorProtocol {
    /// Indicates whether the audio processor is currently running
    var isRunning: Bool { get }

    /// Callback function for audio processing
    var audioProcessingCallback: (([Float]) -> [Float])? { get set }

    /// Returns the measured latency of the audio processing pipeline in milliseconds
    var measuredLatency: Double { get }

    /// Starts capturing audio from the default input device and setting up audio output
    func startCapture() -> Bool

    /// Stops capturing audio and releases audio resources
    func stopCapture()

    /// Plays audio through the default output device
    func playAudio(_ buffer: [Float]) -> Bool
}

// Extend the AudioProcessor class to conform to this protocol
extension AudioProcessor: AudioProcessorProtocol {}
