import XCTest

@testable import DSP
@testable import Utilities

final class MelSpectrogramConverterTests: DSPBaseTestCase {
    var melConverter: MelSpectrogramConverter!
    var spectrogramGenerator: SpectrogramGenerator!

    override func setUp() {
        super.setUp()
        melConverter = MelSpectrogramConverter(
            sampleRate: sampleRate,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )
        spectrogramGenerator = SpectrogramGenerator(fftSize: fftSize)
    }

    override func tearDown() {
        melConverter = nil
        spectrogramGenerator = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(melConverter, "MelSpectrogramConverter should initialize successfully")

        // Test with different parameters
        let customConverter = MelSpectrogramConverter(
            sampleRate: 48000.0,
            melBands: 80,
            minFrequency: 20.0,
            maxFrequency: 20000.0,
            useHTK: true
        )
        XCTAssertNotNil(
            customConverter,
            "MelSpectrogramConverter should initialize with custom parameters")
    }

    func testSpecToMelSpec() {
        // Create a test spectrogram
        let spectrogram = createTestSpectrogram(frames: 10, bins: fftSize / 2)

        // Convert to mel spectrogram
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Verify the dimensions
        XCTAssertEqual(
            melSpectrogram.count, spectrogram.count,
            "Mel spectrogram should have the same number of frames")
        XCTAssertGreaterThan(melSpectrogram[0].count, 0, "Each frame should have mel bands")

        // Test with empty spectrogram
        let emptySpectrogram: [[Float]] = []
        let emptyMelSpec = melConverter.specToMelSpec(spectrogram: emptySpectrogram)
        XCTAssertTrue(emptyMelSpec.isEmpty, "Mel spectrogram should be empty for empty input")
    }

    func testMelToLogMel() {
        // Create a test mel spectrogram
        let melBands = 40  // Use a fixed value for testing
        let melSpectrogram = createTestMelSpectrogram(frames: 10, bands: melBands)

        // Convert to log mel spectrogram
        let logMelSpectrogram = melConverter.melToLogMel(melSpectrogram: melSpectrogram)

        // Verify the dimensions
        XCTAssertEqual(
            logMelSpectrogram.count, melSpectrogram.count,
            "Log mel spectrogram should have the same number of frames")
        XCTAssertEqual(
            logMelSpectrogram[0].count, melSpectrogram[0].count,
            "Each frame should have the same number of bands")

        // Verify that values are logarithmic (should be less than the original values)
        for i in 0..<logMelSpectrogram.count {
            for j in 0..<logMelSpectrogram[i].count {
                // Skip zero or negative values
                if melSpectrogram[i][j] > 0 {
                    XCTAssertLessThan(
                        logMelSpectrogram[i][j], melSpectrogram[i][j],
                        "Log values should be less than original values")
                }
            }
        }

        // Test with empty mel spectrogram
        let emptyMelSpec: [[Float]] = []
        let emptyLogMelSpec = melConverter.melToLogMel(melSpectrogram: emptyMelSpec)
        XCTAssertTrue(
            emptyLogMelSpec.isEmpty, "Log mel spectrogram should be empty for empty input")
    }

    // MARK: - Helper methods

    private func createTestSpectrogram(frames: Int, bins: Int) -> [[Float]] {
        var spectrogram = [[Float]](repeating: [Float](repeating: 0.0, count: bins), count: frames)

        // Fill with some test values
        for i in 0..<frames {
            for j in 0..<bins {
                spectrogram[i][j] = Float.random(in: 0.0...1.0)
            }
        }

        return spectrogram
    }

    private func createTestMelSpectrogram(frames: Int, bands: Int) -> [[Float]] {
        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: bands), count: frames)

        // Fill with some test values
        for i in 0..<frames {
            for j in 0..<bands {
                melSpectrogram[i][j] = Float.random(in: 0.0...1.0)
            }
        }

        return melSpectrogram
    }
}
