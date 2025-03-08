import AudioToolbox
import XCTest

@testable import AudioProcessor
@testable import Utilities

final class AudioProcessorTests: XCTestCase {
    // Test both the real and mock implementations
    var realAudioProcessor: AudioProcessor!
    var mockAudioProcessor: MockAudioProcessor!

    // Use this as the main processor for tests
    var audioProcessor: AudioProcessorProtocol!

    // Flag to control whether to use the real implementation or mock
    // Set to false to avoid actual audio playback and microphone access
    let useRealAudioHardware = false

    override func setUp() {
        super.setUp()

        // Always initialize both, but only use one for tests
        realAudioProcessor = AudioProcessor()
        mockAudioProcessor = MockAudioProcessor()

        // Choose which implementation to use for tests
        audioProcessor = useRealAudioHardware ? realAudioProcessor : mockAudioProcessor
    }

    override func tearDown() {
        audioProcessor.stopCapture()
        audioProcessor = nil
        realAudioProcessor = nil
        mockAudioProcessor = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(audioProcessor, "AudioProcessor should initialize successfully")
        XCTAssertFalse(audioProcessor.isRunning, "AudioProcessor should not be running initially")
        XCTAssertNil(
            audioProcessor.audioProcessingCallback,
            "AudioProcessor should not have a callback initially")
    }

    func testAudioFormatSettings() {
        // This test only applies to the real implementation
        // Test that the audio format settings are correctly configured
        let asbd = AudioProcessor.AudioFormatSettings.createASBD()

        XCTAssertEqual(asbd.mSampleRate, 44100.0, "Sample rate should be 44.1kHz")
        XCTAssertEqual(asbd.mFormatID, kAudioFormatLinearPCM, "Format ID should be linear PCM")
        XCTAssertEqual(asbd.mChannelsPerFrame, 1, "Channel count should be 1 (mono)")
        XCTAssertEqual(asbd.mBitsPerChannel, 32, "Bits per channel should be 32")
        XCTAssertEqual(asbd.mBytesPerFrame, 4, "Bytes per frame should be 4")
        XCTAssertEqual(asbd.mBytesPerPacket, 4, "Bytes per packet should be 4")
        XCTAssertEqual(asbd.mFramesPerPacket, 1, "Frames per packet should be 1")

        // Test that the format flags include float, packed, and non-interleaved
        let expectedFlags =
            kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
        XCTAssertEqual(asbd.mFormatFlags, expectedFlags, "Format flags should be correctly set")
    }

    func testPlayAudio() {
        // Generate a short test tone
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)

        // Test playing the audio
        let result = audioProcessor.playAudio(sineWave)

        // The playback should succeed
        XCTAssertTrue(result, "Audio playback should succeed")

        // After playback, the processor should not be running
        XCTAssertFalse(
            audioProcessor.isRunning, "AudioProcessor should not be running after playback")
    }

    func testPlayAudioWhileRunning() throws {
        // Start capture to make the processor running
        let captureResult = audioProcessor.startCapture()

        // Skip the test if capture fails (might happen in CI environments without audio hardware)
        guard captureResult else {
            throw XCTSkip("Skipping test because audio capture failed to start")
        }

        // Generate a test tone
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 0.1)

        // Try to play audio while the processor is running
        let result = audioProcessor.playAudio(sineWave)

        // The playback should fail because the processor is already running
        XCTAssertFalse(result, "Audio playback should fail when processor is already running")

        // Clean up
        audioProcessor.stopCapture()
    }

    func testAudioProcessingCallback() {
        // Create a simple processing callback that doubles the amplitude
        audioProcessor.audioProcessingCallback = { buffer in
            return buffer.map { $0 * 2.0 }
        }

        // Create a test buffer
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Process the buffer through the callback
        let processedBuffer = audioProcessor.audioProcessingCallback!(testBuffer)

        // Check that the buffer was processed correctly
        XCTAssertEqual(
            processedBuffer.count, testBuffer.count, "Processed buffer should have the same length")

        for i in 0..<testBuffer.count {
            XCTAssertEqual(
                processedBuffer[i], testBuffer[i] * 2.0, accuracy: 0.001,
                "Each sample should be doubled")
        }
    }

    func testStartStopCapture() throws {
        // This test might be skipped in CI environments without audio hardware
        let result = audioProcessor.startCapture()

        if result {
            XCTAssertTrue(
                audioProcessor.isRunning, "AudioProcessor should be running after successful start")

            // Stop capture
            audioProcessor.stopCapture()
            XCTAssertFalse(
                audioProcessor.isRunning, "AudioProcessor should not be running after stop")
        } else {
            // If we couldn't start capture (e.g., no audio hardware), skip the test
            throw XCTSkip("Skipping test because audio capture failed to start")
        }
    }

    func testStartCaptureWhileRunning() throws {
        // First start
        let firstResult = audioProcessor.startCapture()

        // Skip if first start fails
        guard firstResult else {
            throw XCTSkip("Skipping test because audio capture failed to start")
        }

        // Try to start again while already running
        let secondResult = audioProcessor.startCapture()

        // Should return true but not restart
        XCTAssertTrue(secondResult, "Starting capture while already running should return true")
        XCTAssertTrue(audioProcessor.isRunning, "AudioProcessor should still be running")

        // Clean up
        audioProcessor.stopCapture()
    }
}
