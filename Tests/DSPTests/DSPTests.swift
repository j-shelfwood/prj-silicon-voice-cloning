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
        let spectrum = dsp.performFFT(inputBuffer: smallBuffer)
        XCTAssertEqual(
            spectrum.count, 1024 / 2,
            "FFT output should have fftSize/2 elements even with small input")
    }

    func testGenerateSpectrogram() {
        // Generate a test signal with two different frequencies
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5

        // Create a signal that changes frequency halfway through
        let halfSamples = Int(sampleRate * duration / 2)
        let firstHalf = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration / 2)
        let secondHalf = Utilities.generateSineWave(
            frequency: 880.0, sampleRate: sampleRate, duration: duration / 2)

        var combinedSignal = [Float](repeating: 0.0, count: firstHalf.count + secondHalf.count)
        combinedSignal.replaceSubrange(0..<firstHalf.count, with: firstHalf)
        combinedSignal.replaceSubrange(firstHalf.count..<combinedSignal.count, with: secondHalf)

        // Generate spectrogram with default hop size
        let spectrogram = dsp.generateSpectrogram(inputBuffer: combinedSignal)

        // Test that the spectrogram has the expected dimensions
        let hopSize = 256  // Default hop size
        let expectedFrames = (combinedSignal.count - 1024) / hopSize + 1

        XCTAssertEqual(
            spectrogram.count, expectedFrames,
            "Spectrogram should have the expected number of frames"
        )
        XCTAssertEqual(
            spectrogram[0].count, 1024 / 2,
            "Each frame should have fftSize/2 frequency bins"
        )

        // Test with custom hop size
        let customHopSize = 512
        let spectrogramCustomHop = dsp.generateSpectrogram(
            inputBuffer: combinedSignal, hopSize: customHopSize)
        let expectedFramesCustomHop = (combinedSignal.count - 1024) / customHopSize + 1

        XCTAssertEqual(
            spectrogramCustomHop.count, expectedFramesCustomHop,
            "Spectrogram with custom hop size should have the expected number of frames"
        )

        // Verify that the spectrogram captures the frequency change
        // This is a basic check - we expect higher energy in different bins for the two halves
        if spectrogram.count >= 2 {
            // Get the bin indices for 440Hz and 880Hz
            let bin440 = Int(440.0 * 1024.0 / sampleRate)
            let bin880 = Int(880.0 * 1024.0 / sampleRate)

            // Check early frame (should have more energy at 440Hz)
            let earlyFrame = spectrogram[0]
            // Check late frame (should have more energy at 880Hz)
            let lateFrame = spectrogram[spectrogram.count - 1]

            // Allow for some spectral leakage
            let earlyEnergy440 = earlyFrame[
                max(0, bin440 - 1)...min(earlyFrame.count - 1, bin440 + 1)
            ].reduce(0, +)
            let earlyEnergy880 = earlyFrame[
                max(0, bin880 - 1)...min(earlyFrame.count - 1, bin880 + 1)
            ].reduce(0, +)

            let lateEnergy440 = lateFrame[max(0, bin440 - 1)...min(lateFrame.count - 1, bin440 + 1)]
                .reduce(0, +)
            let lateEnergy880 = lateFrame[max(0, bin880 - 1)...min(lateFrame.count - 1, bin880 + 1)]
                .reduce(0, +)

            // In the early frames, 440Hz should have more energy
            XCTAssertGreaterThan(
                earlyEnergy440, earlyEnergy880,
                "Early frames should have more energy at 440Hz than 880Hz"
            )

            // In the late frames, 880Hz should have more energy
            XCTAssertGreaterThan(
                lateEnergy880, lateEnergy440,
                "Late frames should have more energy at 880Hz than 440Hz"
            )
        }
    }

    func testGenerateSpectrogramWithSmallBuffer() {
        // Test with a buffer smaller than FFT size
        let smallBuffer = [Float](repeating: 0.0, count: 512)  // Half the FFT size

        // Should return an empty array
        let spectrogram = dsp.generateSpectrogram(inputBuffer: smallBuffer)
        XCTAssertEqual(
            spectrogram.count, 0, "Spectrogram should be empty for input smaller than FFT size")
    }

    func testSpecToMelSpec() {
        // Generate a real spectrogram to test with
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave)
        XCTAssertFalse(spectrogram.isEmpty, "Spectrogram should not be empty")

        // Convert to mel spectrogram
        let melSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)

        // Test dimensions
        XCTAssertEqual(
            melSpectrogram.count, spectrogram.count,
            "Mel spectrogram should have the same number of frames as the input spectrogram"
        )

        // Test that mel spectrogram has the expected number of mel bands (80 by default)
        XCTAssertEqual(
            melSpectrogram[0].count, 80,
            "Mel spectrogram should have 80 mel bands"
        )

        // Test that the mel spectrogram has non-zero values
        let hasNonZeroValues = melSpectrogram.flatMap { $0 }.contains { $0 != 0 }
        XCTAssertTrue(hasNonZeroValues, "Mel spectrogram should contain non-zero values")
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

    func testPerformanceOfSpectrogram() {
        // Generate a large test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0  // 5 seconds of audio
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Measure the performance of the spectrogram generation
        measure {
            _ = dsp.generateSpectrogram(inputBuffer: sineWave, hopSize: 256)
        }
    }

    func testPerformanceOfMelSpectrogram() {
        // Generate a large test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0  // 5 seconds of audio
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Generate spectrogram
        let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave, hopSize: 256)

        // Measure the performance of the mel spectrogram conversion
        measure {
            _ = dsp.specToMelSpec(spectrogram: spectrogram)
        }
    }
}
