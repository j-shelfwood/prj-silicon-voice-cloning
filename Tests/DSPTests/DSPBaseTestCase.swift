import XCTest
import Utilities
@testable import DSP

class DSPBaseTestCase: XCTestCase {
    // Common test parameters
    var sampleRate: Float = DSPTestUtilities.defaultSampleRate
    var fftSize: Int = DSPTestUtilities.defaultFFTSize

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

    // Common test setup
    override func setUp() {
        super.setUp()
        // Add common setup code that all DSP tests might need
        Utilities.log("Setting up DSP test with sample rate: \(sampleRate), FFT size: \(fftSize)")
    }

    override func tearDown() {
        super.tearDown()
    }

    // Performance test helper
    func measurePerformance(
        iterations: Int = 10,
        file: StaticString = #file,
        line: UInt = #line,
        operation: () -> Void
    ) {
        measure {
            for _ in 0..<iterations {
                operation()
            }
        }
    }
}
