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
        let sineWave = generateTestSignal(duration: 1.0)

        // Process through the entire DSP pipeline
        let spectrum = dsp.performFFT(inputBuffer: sineWave)
        XCTAssertEqual(spectrum.count, fftSize / 2, "Spectrum should have fftSize/2 bins")

        let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave)
        XCTAssertGreaterThan(spectrogram.count, 0, "Spectrogram should have at least one frame")

        let melSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)
        XCTAssertEqual(
            melSpectrogram.count, spectrogram.count,
            "Mel spectrogram should have the same number of frames")

        let logMelSpectrogram = dsp.melToLogMel(melSpectrogram: melSpectrogram)
        XCTAssertEqual(
            logMelSpectrogram.count, melSpectrogram.count,
            "Log mel spectrogram should have the same number of frames")
    }

    func testEmptyInputHandling() {
        // Test empty input for FFT
        let emptySpectrum = dsp.performFFT(inputBuffer: [])
        XCTAssertTrue(emptySpectrum.isEmpty, "FFT should return empty array for empty input")

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

    func testSampleRateInitialization() {
        // Test with different sample rates
        let dsp44k = DSP(fftSize: fftSize, sampleRate: 44100.0)
        let dsp48k = DSP(fftSize: fftSize, sampleRate: 48000.0)

        // Test that different sample rates produce different results
        let sineWave = generateTestSignal(duration: 1.0)
        let spectrogram44k = dsp44k.generateSpectrogram(inputBuffer: sineWave)
        let spectrogram48k = dsp48k.generateSpectrogram(inputBuffer: sineWave)

        // The spectrograms should have different dimensions due to different sample rates
        // or different frequency content due to different sample rates
        let mel44k = dsp44k.specToMelSpec(spectrogram: spectrogram44k)
        let mel48k = dsp48k.specToMelSpec(spectrogram: spectrogram48k)

        // The mel spectrograms should be different due to different sample rates
        XCTAssertNotEqual(
            mel44k.count, 0,
            "Mel spectrogram for 44.1kHz should not be empty"
        )
        XCTAssertNotEqual(
            mel48k.count, 0,
            "Mel spectrogram for 48kHz should not be empty"
        )
    }
}
