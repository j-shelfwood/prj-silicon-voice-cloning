import AudioToolbox
import XCTest

@testable import Audio

final class RealTimeAudioPipelineTests: XCTestCase {
    var audioPipeline: RealTimeAudioPipeline!

    override func setUp() {
        super.setUp()
        audioPipeline = RealTimeAudioPipeline()
    }

    override func tearDown() {
        audioPipeline.stop()
        audioPipeline = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(audioPipeline, "RealTimeAudioPipeline should initialize successfully")
        XCTAssertFalse(
            audioPipeline.isRunning, "RealTimeAudioPipeline should not be running initially")
        XCTAssertNil(
            audioPipeline.audioProcessingCallback,
            "RealTimeAudioPipeline should not have a callback initially")
    }

    func testConfiguration() {
        // Test custom configuration
        let customConfig = RealTimeAudioPipeline.Configuration(
            sampleRate: 48000.0,
            channelCount: 2,
            bytesPerSample: 4,
            bitsPerChannel: 32,
            framesPerBuffer: 1024
        )

        let customPipeline = RealTimeAudioPipeline(configuration: customConfig)
        XCTAssertNotNil(
            customPipeline, "RealTimeAudioPipeline should initialize with custom configuration")
    }

    func testStartStop() {
        // Note: In test environment, AudioUnitManager will be in simulation mode
        // so these operations should succeed without actual audio hardware

        // Test start
        XCTAssertTrue(audioPipeline.start(), "Start should succeed in test environment")
        XCTAssertTrue(audioPipeline.isRunning, "isRunning should be true after start")

        // Test stop
        audioPipeline.stop()
        XCTAssertFalse(audioPipeline.isRunning, "isRunning should be false after stop")
    }

    func testPlayAudio() {
        // Create a test buffer
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Test playing audio
        XCTAssertTrue(
            audioPipeline.playAudio(testBuffer), "playAudio should succeed in test environment")

        // After playback, pipeline should not be running
        XCTAssertFalse(
            audioPipeline.isRunning, "isRunning should be false after playback completes")
    }

    func testAudioProcessingCallback() {
        // Create a simple processing callback that doubles the amplitude
        audioPipeline.audioProcessingCallback = { buffer in
            return buffer.map { $0 * 2.0 }
        }

        // Create a test buffer
        let testBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Process the buffer through the callback
        let processedBuffer = audioPipeline.audioProcessingCallback!(testBuffer)

        // Check that the buffer was processed correctly
        XCTAssertEqual(
            processedBuffer.count, testBuffer.count,
            "Processed buffer should have the same length"
        )

        for i in 0..<testBuffer.count {
            XCTAssertEqual(
                processedBuffer[i], testBuffer[i] * 2.0, accuracy: 0.001,
                "Each sample should be doubled"
            )
        }
    }

    func testMeasuredLatency() {
        // Initially should be zero
        XCTAssertEqual(audioPipeline.measuredLatency, 0.0, "Initial latency should be zero")

        // We can't directly test latency measurement as it depends on timestamps
        // recorded during actual audio processing, but we can verify the property exists
        XCTAssertNotNil(audioPipeline.measuredLatency, "Should be able to get measured latency")
    }

    func testPipelineIntegration() {
        // This test verifies that the pipeline correctly connects input and output
        // Start the pipeline
        XCTAssertTrue(audioPipeline.start(), "Pipeline should start successfully")

        // Set a processing callback
        audioPipeline.audioProcessingCallback = { buffer in
            // Process the buffer (double the amplitude)
            return buffer.map { $0 * 2.0 }
        }

        // Stop the pipeline
        audioPipeline.stop()

        // We can't directly test the data flow through the pipeline in a unit test
        // without actual audio hardware, but we can verify the pipeline was set up
        XCTAssertNotNil(audioPipeline.audioProcessingCallback, "Processing callback should be set")
    }
}
