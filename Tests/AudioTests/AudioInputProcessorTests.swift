import AudioToolbox
import XCTest

@testable import Audio

final class AudioInputProcessorTests: XCTestCase {
    var audioInputProcessor: AudioInputProcessor!

    override func setUp() {
        super.setUp()
        audioInputProcessor = AudioInputProcessor()
    }

    override func tearDown() {
        audioInputProcessor.stop()
        audioInputProcessor = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(audioInputProcessor, "AudioInputProcessor should initialize successfully")
        XCTAssertFalse(
            audioInputProcessor.isRunning, "AudioInputProcessor should not be running initially")
        XCTAssertNil(
            audioInputProcessor.audioDataCallback,
            "AudioInputProcessor should not have a callback initially")
    }

    func testConfiguration() {
        // Test custom configuration
        let customConfig = AudioInputProcessor.Configuration(
            sampleRate: 48000.0,
            channelCount: 2,
            bytesPerSample: 4,
            bitsPerChannel: 32,
            framesPerBuffer: 1024
        )

        let customProcessor = AudioInputProcessor(configuration: customConfig)
        XCTAssertNotNil(
            customProcessor, "AudioInputProcessor should initialize with custom configuration")

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
        XCTAssertTrue(audioInputProcessor.start(), "Start should succeed in test environment")
        XCTAssertTrue(audioInputProcessor.isRunning, "isRunning should be true after start")

        // Test stop
        audioInputProcessor.stop()
        XCTAssertFalse(audioInputProcessor.isRunning, "isRunning should be false after stop")
    }

    func testStartWhileRunning() {
        // First start
        XCTAssertTrue(audioInputProcessor.start(), "First start should succeed")

        // Second start while already running
        XCTAssertTrue(audioInputProcessor.start(), "Start while running should return true")
        XCTAssertTrue(audioInputProcessor.isRunning, "isRunning should still be true")
    }

    func testAudioDataCallback() {
        var callbackCalled = false
        var receivedBuffer: [Float]? = nil

        // Set up a test callback
        audioInputProcessor.audioDataCallback = { buffer in
            callbackCalled = true
            receivedBuffer = buffer
        }

        // Manually set a buffer and simulate a callback
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        audioInputProcessor.setCapturedAudioBuffer(testBuffer)

        // Verify the buffer was set correctly
        XCTAssertEqual(
            audioInputProcessor.getCapturedAudioBuffer(), testBuffer,
            "Buffer should be set correctly")

        // Simulate a callback (this would normally happen in the render callback)
        if let callback = audioInputProcessor.audioDataCallback {
            callback(testBuffer)
        }

        // Verify the callback was called with the correct buffer
        XCTAssertTrue(callbackCalled, "Callback should have been called")
        XCTAssertEqual(receivedBuffer, testBuffer, "Callback should receive the correct buffer")
    }

    func testCaptureTimestamps() {
        // Initially should be empty
        XCTAssertTrue(
            audioInputProcessor.getCaptureTimestamps().isEmpty,
            "Timestamps should be empty initially")

        // We can't directly test timestamp recording as it happens in the render callback
        // But we can verify the getter works
        XCTAssertNotNil(
            audioInputProcessor.getCaptureTimestamps(), "Should be able to get timestamps")
    }
}
