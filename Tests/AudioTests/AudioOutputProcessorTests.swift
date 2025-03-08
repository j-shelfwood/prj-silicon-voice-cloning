import AudioToolbox
import XCTest

@testable import Audio

final class AudioOutputProcessorTests: XCTestCase {
    var audioOutputProcessor: AudioOutputProcessor!

    override func setUp() {
        super.setUp()
        audioOutputProcessor = AudioOutputProcessor()
    }

    override func tearDown() {
        audioOutputProcessor.stop()
        audioOutputProcessor = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(audioOutputProcessor, "AudioOutputProcessor should initialize successfully")
        XCTAssertFalse(
            audioOutputProcessor.isRunning, "AudioOutputProcessor should not be running initially")
        XCTAssertNil(
            audioOutputProcessor.audioDataProvider,
            "AudioOutputProcessor should not have a provider initially")
    }

    func testConfiguration() {
        // Test custom configuration
        let customConfig = AudioOutputProcessor.Configuration(
            sampleRate: 48000.0,
            channelCount: 2,
            bytesPerSample: 4,
            bitsPerChannel: 32,
            framesPerBuffer: 1024
        )

        let customProcessor = AudioOutputProcessor(configuration: customConfig)
        XCTAssertNotNil(
            customProcessor, "AudioOutputProcessor should initialize with custom configuration")

        // Test ASBD creation
        let asbd = customConfig.createASBD()
        XCTAssertEqual(asbd.mSampleRate, 48000.0, "Sample rate should match configuration")
        XCTAssertEqual(asbd.mChannelsPerFrame, 2, "Channel count should match configuration")
        XCTAssertEqual(asbd.mBytesPerFrame, 4, "Bytes per frame should match configuration")
        XCTAssertEqual(asbd.mBitsPerChannel, 32, "Bits per channel should match configuration")
    }

    func testStartStop() {
        // Note: In test environment, AudioUnitManager will be in simulation mode
        // so these operations should succeed without actual audio hardware

        // Test start
        XCTAssertTrue(audioOutputProcessor.start(), "Start should succeed in test environment")
        XCTAssertTrue(audioOutputProcessor.isRunning, "isRunning should be true after start")

        // Test stop
        audioOutputProcessor.stop()
        XCTAssertFalse(audioOutputProcessor.isRunning, "isRunning should be false after stop")
    }

    func testStartWhileRunning() {
        // First start
        XCTAssertTrue(audioOutputProcessor.start(), "First start should succeed")

        // Second start while already running
        XCTAssertTrue(audioOutputProcessor.start(), "Start while running should return true")
        XCTAssertTrue(audioOutputProcessor.isRunning, "isRunning should still be true")
    }

    func testPlayAudio() {
        // Create a test buffer
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Test playing audio
        XCTAssertTrue(
            audioOutputProcessor.playAudio(testBuffer),
            "playAudio should succeed in test environment")

        // After playback, processor should not be running
        XCTAssertFalse(
            audioOutputProcessor.isRunning, "isRunning should be false after playback completes")
    }

    func testPlayAudioWhileRunning() {
        // Start the processor
        XCTAssertTrue(audioOutputProcessor.start(), "Start should succeed")

        // Create a test buffer
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Try to play audio while running
        XCTAssertFalse(
            audioOutputProcessor.playAudio(testBuffer), "playAudio should fail when already running"
        )

        // Processor should still be running
        XCTAssertTrue(audioOutputProcessor.isRunning, "isRunning should still be true")
    }

    func testAudioDataProvider() {
        // Create a test provider
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        audioOutputProcessor.audioDataProvider = {
            return testBuffer
        }

        // Verify the provider is set
        XCTAssertNotNil(audioOutputProcessor.audioDataProvider, "Provider should be set")

        // Call the provider and verify it returns the expected buffer
        if let provider = audioOutputProcessor.audioDataProvider {
            let providedBuffer = provider()
            XCTAssertEqual(providedBuffer, testBuffer, "Provider should return the expected buffer")
        } else {
            XCTFail("Provider should not be nil")
        }
    }

    func testBufferManagement() {
        // Test setting and getting the output buffer
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        audioOutputProcessor.setOutputAudioBuffer(testBuffer)
        let retrievedBuffer = audioOutputProcessor.getOutputAudioBuffer()

        XCTAssertEqual(retrievedBuffer, testBuffer, "Retrieved buffer should match the set buffer")
    }

    func testPlaybackTimestamps() {
        // Initially should be empty
        XCTAssertTrue(
            audioOutputProcessor.getPlaybackTimestamps().isEmpty,
            "Timestamps should be empty initially")

        // We can't directly test timestamp recording as it happens in the render callback
        // But we can verify the getter works
        XCTAssertNotNil(
            audioOutputProcessor.getPlaybackTimestamps(), "Should be able to get timestamps")
    }
}
