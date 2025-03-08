import AudioToolbox
import XCTest

@testable import AudioProcessor
@testable import Utilities

final class MockAudioProcessorTests: XCTestCase {
    var mockAudioProcessor: MockAudioProcessor!

    override func setUp() {
        super.setUp()
        mockAudioProcessor = MockAudioProcessor()
    }

    override func tearDown() {
        mockAudioProcessor.stopCapture()
        mockAudioProcessor = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(mockAudioProcessor, "MockAudioProcessor should initialize successfully")
        XCTAssertFalse(
            mockAudioProcessor.isRunning, "MockAudioProcessor should not be running initially")
        XCTAssertNil(
            mockAudioProcessor.audioProcessingCallback,
            "MockAudioProcessor should not have a callback initially")
    }

    func testMockConfiguration() {
        // Test default configuration
        // We can't directly access the config property, so we'll test the behavior instead

        // Default configuration should allow capture to succeed
        XCTAssertTrue(
            mockAudioProcessor.startCapture(),
            "Capture should succeed with default configuration")
        mockAudioProcessor.stopCapture()

        // Default configuration should allow playback to succeed
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)
        XCTAssertTrue(
            mockAudioProcessor.playAudio(sineWave),
            "Playback should succeed with default configuration")

        // Default latency should be 20ms (as defined in MockConfig)
        XCTAssertEqual(
            mockAudioProcessor.measuredLatency, 20.0, accuracy: 0.001,
            "Default latency should be 20ms")

        // Test custom configuration
        let customConfig = MockAudioProcessor.MockConfig(
            captureSucceeds: false,
            playbackSucceeds: false,
            simulatedLatencyMs: 25.0
        )

        let customMock = MockAudioProcessor(config: customConfig)
        XCTAssertFalse(
            customMock.startCapture(),
            "Capture should fail with custom config")

        XCTAssertFalse(
            customMock.playAudio(sineWave),
            "Playback should fail with custom config")

        XCTAssertEqual(
            customMock.measuredLatency, 25.0, accuracy: 0.001,
            "Latency should match custom config")
    }

    func testMeasuredLatency() {
        // For the mock implementation, this should use the simulated latency
        let latency = mockAudioProcessor.measuredLatency
        XCTAssertEqual(
            latency, 20.0, accuracy: 0.001,
            "Latency should match configured value")

        // Test with custom latency
        let customMock = MockAudioProcessor(
            config: MockAudioProcessor.MockConfig(simulatedLatencyMs: 25.0))
        XCTAssertEqual(
            customMock.measuredLatency, 25.0, accuracy: 0.001,
            "Latency should match custom value")
    }

    func testMockConfigurationFailures() {
        // Create a mock with capture failure
        let failCaptureMock = MockAudioProcessor(
            config: MockAudioProcessor.MockConfig(captureSucceeds: false))
        XCTAssertFalse(
            failCaptureMock.startCapture(), "Capture should fail with this configuration")

        // Create a mock with playback failure
        let failPlaybackMock = MockAudioProcessor(
            config: MockAudioProcessor.MockConfig(playbackSucceeds: false))
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)
        XCTAssertFalse(
            failPlaybackMock.playAudio(sineWave), "Playback should fail with this configuration")
    }

    func testPlayAudio() {
        // Generate a short test tone
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)

        // Test playing the audio
        let result = mockAudioProcessor.playAudio(sineWave)

        // The playback should succeed with default configuration
        XCTAssertTrue(result, "Audio playback should succeed")

        // After playback, the processor should not be running
        XCTAssertFalse(
            mockAudioProcessor.isRunning, "MockAudioProcessor should not be running after playback")
    }

    func testStartStopCapture() {
        // Test start capture
        XCTAssertTrue(
            mockAudioProcessor.startCapture(), "Start capture should succeed with default config")
        XCTAssertTrue(
            mockAudioProcessor.isRunning, "isRunning should be true after successful start")

        // Test stop capture
        mockAudioProcessor.stopCapture()
        XCTAssertFalse(mockAudioProcessor.isRunning, "isRunning should be false after stop")
    }
}
