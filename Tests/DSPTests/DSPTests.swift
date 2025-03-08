import Accelerate
import XCTest

@testable import DSP
@testable import Utilities

final class DSPTests: DSPBaseTestCase {
    var dsp: DSP!

    override func setUp() {
        super.setUp()
        dsp = DSP(fftSize: fftSize)
    }

    override func tearDown() {
        dsp = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(dsp, "DSP should initialize successfully")

        // Test with different FFT sizes
        let sizes = [256, 2048]
        for size in sizes {
            let processor = DSP(fftSize: size)
            XCTAssertNotNil(processor, "DSP should initialize with FFT size \(size)")
        }
    }

    func testEndToEndProcessing() {
        // Generate a test signal
        let sineWave = generateTestSignal()

        // Test FFT processing
        let spectrum = dsp.performFFT(inputBuffer: sineWave)
        XCTAssertEqual(spectrum.count, fftSize / 2, "FFT output should have fftSize/2 elements")

        // Test spectrogram generation
        let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave)
        let hopSize = 256  // Default hop size
        let expectedFrames = (sineWave.count - fftSize) / hopSize + 1
        DSPTestUtilities.verifySpectrogramProperties(
            spectrogram: spectrogram,
            expectedFrames: expectedFrames,
            expectedBins: fftSize / 2
        )

        // Test mel spectrogram conversion
        let melSpec = dsp.specToMelSpec(spectrogram: spectrogram)
        DSPTestUtilities.verifyMelSpectrogramProperties(
            melSpectrogram: melSpec,
            expectedFrames: expectedFrames
        )

        // Test log-mel spectrogram conversion
        let logMelSpec = dsp.melToLogMel(melSpectrogram: melSpec)
        DSPTestUtilities.verifyLogMelSpectrogramProperties(
            logMelSpectrogram: logMelSpec,
            expectedFrames: expectedFrames
        )
    }

    func testEmptyInputHandling() {
        // Test empty input for FFT
        let emptySpectrum = dsp.performFFT(inputBuffer: [])
        XCTAssertEqual(emptySpectrum.count, fftSize / 2, "FFT should handle empty input gracefully")

        // Test empty input for spectrogram
        let emptySpectrogram = dsp.generateSpectrogram(inputBuffer: [])
        XCTAssertTrue(emptySpectrogram.isEmpty, "Spectrogram should be empty for empty input")

        // Test empty input for mel spectrogram
        let emptyMelSpec = dsp.specToMelSpec(spectrogram: [])
        XCTAssertTrue(emptyMelSpec.isEmpty, "Mel spectrogram should be empty for empty input")

        // Test empty input for log-mel spectrogram
        let emptyLogMelSpec = dsp.melToLogMel(melSpectrogram: [])
        XCTAssertTrue(
            emptyLogMelSpec.isEmpty, "Log-mel spectrogram should be empty for empty input")
    }

    func testPerformanceEndToEnd() {
        let sineWave = generateTestSignal(duration: 5.0)  // 5 seconds of audio

        measurePerformance { [unowned self] in
            let spectrogram = self.dsp.generateSpectrogram(inputBuffer: sineWave)
            let melSpec = self.dsp.specToMelSpec(spectrogram: spectrogram)
            _ = self.dsp.melToLogMel(melSpectrogram: melSpec)
        }
    }

    func testSampleRateInitialization() {
        // Test with different sample rates
        let sampleRates: [Float] = [22050.0, 48000.0]
        for rate in sampleRates {
            let processor = DSP(fftSize: fftSize, sampleRate: rate)
            XCTAssertNotNil(processor, "DSP should initialize with sample rate \(rate)")

            // Generate a test signal at this sample rate
            let customSampleRateSignal = Utilities.generateSineWave(
                frequency: 440.0, sampleRate: rate, duration: 0.5)

            // Verify processing works with this sample rate
            let spectrum = processor.performFFT(inputBuffer: customSampleRateSignal)
            XCTAssertEqual(spectrum.count, fftSize / 2, "FFT output should have fftSize/2 elements")
        }
    }
}
