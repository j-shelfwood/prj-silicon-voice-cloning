import AudioToolbox
import XCTest

@testable import Audio

final class AudioUnitManagerTests: XCTestCase {
    var audioUnitManager: AudioUnitManager!

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        audioUnitManager?.dispose()
        audioUnitManager = nil
        super.tearDown()
    }

    func testInitialization() {
        audioUnitManager = AudioUnitManager(type: .input)
        XCTAssertNotNil(audioUnitManager)

        audioUnitManager = AudioUnitManager(type: .output)
        XCTAssertNotNil(audioUnitManager)
    }

    func testCustomConfiguration() {
        let config = AudioUnitManager.Configuration(
            sampleRate: 48000.0,
            channelCount: 2,
            bytesPerSample: 4,
            bitsPerChannel: 32,
            framesPerBuffer: 1024
        )

        audioUnitManager = AudioUnitManager(type: .output, configuration: config)
        XCTAssertNotNil(audioUnitManager)

        let asbd = config.createASBD()
        XCTAssertEqual(asbd.mSampleRate, 48000.0)
        XCTAssertEqual(asbd.mChannelsPerFrame, 2)
        XCTAssertEqual(asbd.mBytesPerFrame, 4)
        XCTAssertEqual(asbd.mBitsPerChannel, 32)
    }

    func testSetupAndLifecycle() {
        audioUnitManager = AudioUnitManager(type: .output)

        // Test setup
        XCTAssertTrue(audioUnitManager.setup())
        XCTAssertNil(audioUnitManager.getAudioUnit())  // Nil in test mode

        // Test initialization
        XCTAssertTrue(audioUnitManager.initialize())

        // Test start/stop
        XCTAssertTrue(audioUnitManager.start())
        XCTAssertTrue(audioUnitManager.isRunning)
        XCTAssertTrue(audioUnitManager.stop())
        XCTAssertFalse(audioUnitManager.isRunning)

        // Test disposal
        audioUnitManager.dispose()
        XCTAssertNil(audioUnitManager.getAudioUnit())
        XCTAssertFalse(audioUnitManager.isRunning)
    }

    func testRenderCallback() {
        audioUnitManager = AudioUnitManager(type: .output)

        let renderCallback: AURenderCallback = {
            (
                inRefCon,
                ioActionFlags,
                inTimeStamp,
                inBusNumber,
                inNumberFrames,
                ioData
            ) -> OSStatus in
            return noErr
        }

        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = renderCallback
        callbackStruct.inputProcRefCon = nil

        XCTAssertTrue(audioUnitManager.setup(renderCallback: callbackStruct))
    }

    func testInputConfiguration() {
        audioUnitManager = AudioUnitManager(type: .input)
        XCTAssertTrue(audioUnitManager.setup())

        // In test mode, we verify that setup succeeds but returns nil for the AudioUnit
        XCTAssertNil(audioUnitManager.getAudioUnit())

        // Test the lifecycle in simulated mode
        XCTAssertTrue(audioUnitManager.initialize())
        XCTAssertTrue(audioUnitManager.start())
        XCTAssertTrue(audioUnitManager.isRunning)
        XCTAssertTrue(audioUnitManager.stop())
        XCTAssertFalse(audioUnitManager.isRunning)
    }

    func testOutputConfiguration() {
        audioUnitManager = AudioUnitManager(type: .output)
        XCTAssertTrue(audioUnitManager.setup())

        // In test mode, we verify that setup succeeds but returns nil for the AudioUnit
        XCTAssertNil(audioUnitManager.getAudioUnit())

        // Test the lifecycle in simulated mode
        XCTAssertTrue(audioUnitManager.initialize())
        XCTAssertTrue(audioUnitManager.start())
        XCTAssertTrue(audioUnitManager.isRunning)
        XCTAssertTrue(audioUnitManager.stop())
        XCTAssertFalse(audioUnitManager.isRunning)
    }

    func testErrorHandling() {
        audioUnitManager = AudioUnitManager(type: .output)

        // Test starting without setup
        XCTAssertFalse(audioUnitManager.start())

        // Test initializing without setup
        XCTAssertFalse(audioUnitManager.initialize())

        // Test stopping without setup
        XCTAssertFalse(audioUnitManager.stop())
    }

    func testSimulationMode() {
        // Test explicit simulation mode
        let config = AudioUnitManager.Configuration(simulateAudioUnit: true)
        audioUnitManager = AudioUnitManager(type: .output, configuration: config)

        XCTAssertTrue(audioUnitManager.setup())
        XCTAssertNil(audioUnitManager.getAudioUnit())
        XCTAssertTrue(audioUnitManager.initialize())
        XCTAssertTrue(audioUnitManager.start())
        XCTAssertTrue(audioUnitManager.isRunning)
        XCTAssertTrue(audioUnitManager.stop())
        XCTAssertFalse(audioUnitManager.isRunning)

        // Test automatic simulation in test environment
        audioUnitManager = AudioUnitManager(type: .input)
        XCTAssertTrue(audioUnitManager.setup())
        XCTAssertNil(audioUnitManager.getAudioUnit())
    }
}
