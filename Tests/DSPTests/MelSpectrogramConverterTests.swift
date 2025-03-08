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
        // Generate a real spectrogram using a sine wave
        let signal = generateTestSignal(frequency: 440.0, duration: 0.5)

        // Generate spectrogram
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: signal)
        XCTAssertFalse(spectrogram.isEmpty, "Spectrogram should not be empty")

        // Convert to mel spectrogram
        let melSpec = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Check dimensions
        XCTAssertEqual(
            melSpec.count, spectrogram.count,
            "Mel spectrogram should have same number of frames as spectrogram")
        XCTAssertEqual(melSpec[0].count, 40, "Mel spectrogram should have 40 mel bands")

        // Check values
        for frame in melSpec {
            for value in frame {
                XCTAssertFalse(value.isNaN, "Mel spectrogram should not contain NaN values")
                XCTAssertFalse(
                    value.isInfinite, "Mel spectrogram should not contain infinite values")
                XCTAssertGreaterThanOrEqual(
                    value, 0.0, "Mel spectrogram values should be non-negative")
            }
        }

        // Test with empty input
        let emptyMelSpec = melConverter.specToMelSpec(spectrogram: [])
        XCTAssertTrue(emptyMelSpec.isEmpty, "Mel spectrogram should be empty for empty input")
    }

    func testMelToLogMel() {
        // Generate a real spectrogram using a sine wave
        let signal = generateTestSignal(frequency: 440.0, duration: 0.5)

        // Generate spectrogram and convert to mel spectrogram
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: signal)
        let melSpec = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Convert to log-mel spectrogram
        let logMelSpec = melConverter.melToLogMel(melSpectrogram: melSpec)

        // Check dimensions
        XCTAssertEqual(
            logMelSpec.count, melSpec.count,
            "Log-mel spectrogram should have same number of frames as mel spectrogram")
        XCTAssertEqual(
            logMelSpec[0].count, melSpec[0].count,
            "Log-mel spectrogram should have same number of mel bands")

        // Check values
        var hasValues = false
        var minValue: Float = 0.0
        var maxValue: Float = 0.0

        for frame in logMelSpec {
            XCTAssertFalse(frame.isEmpty, "Log-mel spectrogram frame should not be empty")
            for value in frame {
                XCTAssertFalse(value.isNaN, "Log-mel spectrogram should not contain NaN values")
                XCTAssertFalse(
                    value.isInfinite, "Log-mel spectrogram should not contain infinite values")

                if !hasValues {
                    minValue = value
                    maxValue = value
                    hasValues = true
                } else {
                    minValue = min(minValue, value)
                    maxValue = max(maxValue, value)
                }
            }
        }

        // Check that values are in dB scale (should be <= 0)
        XCTAssertLessThanOrEqual(maxValue, 0.0, "Maximum log-mel value should be <= 0 dB")
        XCTAssertGreaterThanOrEqual(minValue, -80.0, "Minimum log-mel value should be >= -80 dB")

        // Test with empty input
        let emptyLogMelSpec = melConverter.melToLogMel(melSpectrogram: [])
        XCTAssertTrue(
            emptyLogMelSpec.isEmpty, "Log-mel spectrogram should be empty for empty input")
    }

    func testPerformanceOfMelSpecConversion() {
        // Generate a large test signal
        let signal = generateTestSignal(frequency: 440.0, duration: 5.0)

        // Generate spectrogram
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: signal)

        // Measure the performance of the mel spectrogram conversion
        measure {
            _ = melConverter.specToMelSpec(spectrogram: spectrogram)
        }
    }

    func testPerformanceOfLogMelConversion() {
        // Generate a large test signal
        let signal = generateTestSignal(frequency: 440.0, duration: 5.0)

        // Generate spectrogram and mel spectrogram
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: signal)
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Measure the performance of the log-mel spectrogram conversion
        measure {
            _ = melConverter.melToLogMel(melSpectrogram: melSpectrogram)
        }
    }
}
