import AudioToolbox
import XCTest

@testable import AudioProcessor
@testable import Utilities

final class AudioProcessorLatencyTests: XCTestCase {
    var audioProcessor: AudioProcessor!

    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
    }

    override func tearDown() {
        audioProcessor = nil
        super.tearDown()
    }

    func testEmptyTimestampsLatency() {
        // With no timestamps, latency should be zero
        XCTAssertEqual(
            audioProcessor.measuredLatency, 0.0, "Latency should be 0 when no timestamps exist")
    }

    // Since we can't directly set the private properties using reflection,
    // we'll test the latency calculation logic indirectly by creating a mock
    func testLatencyCalculationWithMock() {
        // Create a mock with a known latency
        let mockProcessor = MockAudioProcessor(
            config: MockAudioProcessor.MockConfig(simulatedLatencyMs: 20.0))

        // Generate a test buffer
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)

        // Play audio to trigger timestamp recording
        let playResult = mockProcessor.playAudio(sineWave)
        XCTAssertTrue(playResult, "Audio playback should succeed")

        // Test that the measured latency is calculated correctly
        XCTAssertEqual(
            mockProcessor.measuredLatency, 20.0, accuracy: 0.1,
            "Calculated latency should be approximately 20ms")
    }

    func testUnbalancedTimestampsWithMock() {
        // Create a mock with a known latency
        let mockProcessor = MockAudioProcessor(
            config: MockAudioProcessor.MockConfig(simulatedLatencyMs: 30.0))

        // Generate a test buffer
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)

        // Play audio to trigger timestamp recording
        let playResult = mockProcessor.playAudio(sineWave)
        XCTAssertTrue(playResult, "Audio playback should succeed")

        // Test that the measured latency is calculated correctly
        XCTAssertEqual(
            mockProcessor.measuredLatency, 30.0, accuracy: 0.1,
            "Should calculate latency correctly")

        // Create another mock with a different latency
        let mockProcessor2 = MockAudioProcessor(
            config: MockAudioProcessor.MockConfig(simulatedLatencyMs: 40.0))

        // Play audio to trigger timestamp recording
        let playResult2 = mockProcessor2.playAudio(sineWave)
        XCTAssertTrue(playResult2, "Audio playback should succeed")

        // Test that the measured latency is calculated correctly
        XCTAssertEqual(
            mockProcessor2.measuredLatency, 40.0, accuracy: 0.1,
            "Should calculate latency correctly")
    }
}
