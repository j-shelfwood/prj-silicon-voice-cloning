import Utilities
import XCTest

@testable import DSP

class DSPBaseTestCase: XCTestCase {
    // Common test parameters
    var sampleRate: Float = DSPTestUtilities.defaultSampleRate
    var fftSize: Int = DSPTestUtilities.defaultFFTSize

    var testBuffer: [Float] = []

    // Test signal generation
    func generateTestSignal(
        frequency: Float = DSPTestUtilities.defaultFrequency,
        duration: Float = 1.0
    ) -> [Float] {
        return DSPTestUtilities.generateTestSignal(
            frequency: frequency,
            sampleRate: sampleRate,
            duration: duration
        )
    }

    // Add missing method
    func generateTestBuffer() -> [Float] {
        return generateTestSignal(duration: 1.0)
    }

    // Common test setup
    override func setUp() {
        super.setUp()

        // Log the test setup
        LoggerUtility.debug(
            "Setting up DSP test with sample rate: \(sampleRate), FFT size: \(fftSize)")

        // Generate test data
        testBuffer = generateTestBuffer()
    }

    override func tearDown() {
        super.tearDown()
    }
}
