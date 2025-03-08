import Accelerate
import XCTest

@testable import DSP
@testable import Utilities

final class FFTProcessorTests: DSPBaseTestCase {
    var fftProcessor: FFTProcessor!

    override func setUp() {
        super.setUp()
        fftProcessor = FFTProcessor(fftSize: fftSize)
    }

    override func tearDown() {
        fftProcessor = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(fftProcessor, "FFTProcessor should initialize successfully")
        XCTAssertEqual(fftProcessor.size, fftSize, "FFT size should match initialized value")

        // Test with different FFT sizes
        let sizes = [256, 2048]
        for size in sizes {
            let processor = FFTProcessor(fftSize: size)
            XCTAssertNotNil(processor, "FFTProcessor should initialize with FFT size \(size)")
            XCTAssertEqual(processor.size, size, "FFT size should be \(size)")
        }
    }

    func testPerformFFT() {
        let frequency: Float = 1000.0  // 1kHz tone
        let sineWave = generateTestSignal(frequency: frequency)
        let spectrum = fftProcessor.performFFT(inputBuffer: sineWave)

        // Check the output size
        XCTAssertEqual(spectrum.count, fftSize / 2, "FFT output should have fftSize/2 elements")

        // Test for peak at the expected frequency bin
        let expectedBin = DSPTestUtilities.expectedFrequencyBin(
            frequency: frequency,
            sampleRate: sampleRate,
            fftSize: fftSize
        )

        // Find the peak bin
        var peakBin = 0
        var peakValue: Float = -Float.infinity
        for (bin, value) in spectrum.enumerated() {
            if value > peakValue {
                peakValue = value
                peakBin = bin
            }
        }

        // Allow for some leakage due to windowing - the peak should be within ±2 bins
        XCTAssertTrue(
            abs(peakBin - expectedBin) <= 2,
            "FFT should show a peak near bin \(expectedBin), but peak was at bin \(peakBin)"
        )
    }

    func testPerformFFTWithSmallBuffer() {
        // Test with a buffer smaller than FFT size
        let smallBuffer = [Float](repeating: 0.0, count: fftSize / 2)
        let spectrum = fftProcessor.performFFT(inputBuffer: smallBuffer)

        // Should return an empty array
        XCTAssertTrue(
            spectrum.isEmpty, "FFT should return empty array for buffer smaller than FFT size")
    }
}
