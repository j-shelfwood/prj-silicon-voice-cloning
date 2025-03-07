import Accelerate
import XCTest

@testable import DSP
@testable import Utilities

final class DSPTests: XCTestCase {
    var dsp: DSP!

    override func setUp() {
        super.setUp()
        dsp = DSP(fftSize: 1024)
    }

    override func tearDown() {
        dsp = nil
        super.tearDown()
    }

    func testInitialization() {
        // Test that DSP initializes with the correct FFT size
        XCTAssertNotNil(dsp, "DSP should initialize successfully")

        // Test with different FFT sizes
        let dsp256 = DSP(fftSize: 256)
        XCTAssertNotNil(dsp256, "DSP should initialize with FFT size 256")

        let dsp2048 = DSP(fftSize: 2048)
        XCTAssertNotNil(dsp2048, "DSP should initialize with FFT size 2048")
    }

    func testPerformFFT() {
        // Generate a simple sine wave for testing
        let sampleRate: Float = 44100.0
        let frequency: Float = 1000.0  // 1kHz tone
        let duration: Float = 1.0

        let sineWave = Utilities.generateSineWave(
            frequency: frequency, sampleRate: sampleRate, duration: duration)

        // Perform FFT on the sine wave
        let spectrum = dsp.performFFT(inputBuffer: sineWave)

        // Since the current implementation is a placeholder, we can only test the output size
        // Once the real implementation is added, we should test that the spectrum has a peak at the expected frequency
        XCTAssertEqual(spectrum.count, 1024 / 2, "FFT output should have fftSize/2 elements")

        // TODO: When real FFT implementation is added, test for peak at the expected frequency bin
        // let expectedBin = Int(frequency / (sampleRate / Float(dsp.fftSize)))
        // XCTAssertTrue(spectrum[expectedBin-1...expectedBin+1].contains(where: { $0 > spectrum.max()! * 0.8 }),
        //               "FFT should show a peak near the input frequency")
    }

    func testGenerateSpectrogram() {
        // Generate a test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Generate spectrogram with default hop size
        let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave)

        // Test that the spectrogram has the expected dimensions
        let hopSize = 256  // Default hop size
        let expectedFrames = (sineWave.count - 1024) / hopSize + 1

        XCTAssertEqual(
            spectrogram.count, expectedFrames,
            "Spectrogram should have the expected number of frames")
        XCTAssertEqual(
            spectrogram[0].count, 1024 / 2, "Each frame should have fftSize/2 frequency bins")

        // Test with custom hop size
        let customHopSize = 512
        let spectrogramCustomHop = dsp.generateSpectrogram(
            inputBuffer: sineWave, hopSize: customHopSize)
        let expectedFramesCustomHop = (sineWave.count - 1024) / customHopSize + 1

        XCTAssertEqual(
            spectrogramCustomHop.count, expectedFramesCustomHop,
            "Spectrogram with custom hop size should have the expected number of frames")
    }

    func testSpecToMelSpec() {
        // Create a mock spectrogram
        let mockSpectrogram = Array(
            repeating: Array(repeating: Float(1.0), count: 1024 / 2), count: 10)

        // Convert to mel spectrogram
        let melSpectrogram = dsp.specToMelSpec(spectrogram: mockSpectrogram)

        // Test that the mel spectrogram has the same dimensions as the input
        // (This is true for the placeholder implementation, but will change when real implementation is added)
        XCTAssertEqual(
            melSpectrogram.count, mockSpectrogram.count,
            "Mel spectrogram should have the same number of frames as the input spectrogram")
        XCTAssertEqual(
            melSpectrogram[0].count, mockSpectrogram[0].count,
            "Mel spectrogram frames should have the same number of bins as the input spectrogram")

        // TODO: When real implementation is added, test that the mel spectrogram has the expected number of mel bins
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
                _ = dsp.performFFT(inputBuffer: sineWave)
            }
        }
    }
}
