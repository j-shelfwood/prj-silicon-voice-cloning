import Accelerate
import XCTest

@testable import DSP
@testable import Utilities

final class FFTProcessorTests: XCTestCase {
    var fftProcessor: FFTProcessor!

    override func setUp() {
        super.setUp()
        fftProcessor = FFTProcessor(fftSize: 1024)
    }

    override func tearDown() {
        fftProcessor = nil
        super.tearDown()
    }

    func testInitialization() {
        // Test that FFTProcessor initializes with the correct FFT size
        XCTAssertNotNil(fftProcessor, "FFTProcessor should initialize successfully")
        XCTAssertEqual(fftProcessor.size, 1024, "FFT size should be 1024")

        // Test with different FFT sizes
        let processor256 = FFTProcessor(fftSize: 256)
        XCTAssertNotNil(processor256, "FFTProcessor should initialize with FFT size 256")
        XCTAssertEqual(processor256.size, 256, "FFT size should be 256")

        let processor2048 = FFTProcessor(fftSize: 2048)
        XCTAssertNotNil(processor2048, "FFTProcessor should initialize with FFT size 2048")
        XCTAssertEqual(processor2048.size, 2048, "FFT size should be 2048")
    }

    func testPerformFFT() {
        // Generate a simple sine wave for testing
        let sampleRate: Float = 44100.0
        let frequency: Float = 1000.0  // 1kHz tone
        let duration: Float = 1.0

        let sineWave = Utilities.generateSineWave(
            frequency: frequency, sampleRate: sampleRate, duration: duration)

        // Perform FFT on the sine wave
        let spectrum = fftProcessor.performFFT(inputBuffer: sineWave)

        // Check the output size
        XCTAssertEqual(spectrum.count, 1024 / 2, "FFT output should have fftSize/2 elements")

        // Test for peak at the expected frequency bin
        // For a 1kHz tone at 44.1kHz sample rate with 1024-point FFT:
        // bin = frequency * fftSize / sampleRate = 1000 * 1024 / 44100 ≈ 23.2
        let expectedBin = Int(frequency / (sampleRate / Float(1024)))

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
        let smallBuffer = [Float](repeating: 0.0, count: 512)  // Half the FFT size

        // Should not crash and return a buffer of the expected size
        let spectrum = fftProcessor.performFFT(inputBuffer: smallBuffer)
        XCTAssertEqual(
            spectrum.count, 1024 / 2,
            "FFT output should have fftSize/2 elements even with small input")

        // All values should be zero since we provided insufficient samples
        for value in spectrum {
            XCTAssertEqual(value, 0.0, "Spectrum values should be zero for insufficient input")
        }
    }

    func testPerformanceOfFFT() {
        // Generate a large test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 10.0  // 10 seconds of audio
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Measure the performance of the FFT operation
        measure {
            for _ in 0..<10 {  // Perform 10 FFTs to get a good measurement
                _ = fftProcessor.performFFT(inputBuffer: sineWave)
            }
        }
    }
}
