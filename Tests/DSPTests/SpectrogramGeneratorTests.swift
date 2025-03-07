import XCTest

@testable import DSP
@testable import Utilities

final class SpectrogramGeneratorTests: XCTestCase {
    var spectrogramGenerator: SpectrogramGenerator!

    override func setUp() {
        super.setUp()
        spectrogramGenerator = SpectrogramGenerator(fftSize: 1024)
    }

    override func tearDown() {
        spectrogramGenerator = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(spectrogramGenerator, "SpectrogramGenerator should initialize successfully")
        XCTAssertEqual(spectrogramGenerator.fftSize, 1024, "FFT size should be 1024")

        // Test with custom hop size
        let customHopGenerator = SpectrogramGenerator(fftSize: 1024, hopSize: 512)
        XCTAssertNotNil(
            customHopGenerator, "SpectrogramGenerator should initialize with custom hop size")
        XCTAssertEqual(customHopGenerator.fftSize, 1024, "FFT size should be 1024")
    }

    func testGenerateSpectrogram() {
        // Create a signal that changes frequency halfway through
        let sampleRate: Float = 44100
        let duration: Float = 1.0
        let firstHalf = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration / 2)
        let secondHalf = Utilities.generateSineWave(
            frequency: 880.0, sampleRate: sampleRate, duration: duration / 2)

        // Combine the two halves
        var signal = [Float](repeating: 0.0, count: Int(sampleRate * duration))
        for i in 0..<firstHalf.count {
            signal[i] = firstHalf[i]
        }
        for i in 0..<secondHalf.count {
            signal[i + firstHalf.count] = secondHalf[i]
        }

        // Generate spectrogram with default hop size
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: signal)

        // Test that the spectrogram has the expected dimensions
        let hopSize = 256  // Default hop size (fftSize/4)
        let expectedFrames = (signal.count - 1024) / hopSize + 1

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
        let spectrogramCustomHop = spectrogramGenerator.generateSpectrogram(
            inputBuffer: signal, hopSize: customHopSize)
        let expectedFramesCustomHop = (signal.count - 1024) / customHopSize + 1

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
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: smallBuffer)
        XCTAssertTrue(
            spectrogram.isEmpty,
            "Spectrogram should be empty for input smaller than FFT size")
    }

    func testPerformanceOfSpectrogram() {
        // Generate a large test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0  // 5 seconds of audio
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Measure the performance of the spectrogram generation
        measure {
            _ = spectrogramGenerator.generateSpectrogram(inputBuffer: sineWave, hopSize: 256)
        }
    }
}
