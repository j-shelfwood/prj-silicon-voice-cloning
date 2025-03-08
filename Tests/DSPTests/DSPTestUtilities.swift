import XCTest

@testable import DSP
@testable import Utilities

class DSPTestUtilities {
    // Common test parameters
    static let defaultSampleRate: Float = 44100.0
    static let defaultFrequency: Float = 440.0  // A4 note
    static let defaultFFTSize: Int = 1024

    /// Generate a test signal with specified parameters
    static func generateTestSignal(
        frequency: Float = defaultFrequency,
        sampleRate: Float = defaultSampleRate,
        duration: Float = 1.0
    ) -> [Float] {
        return Utilities.generateSineWave(
            frequency: frequency,
            sampleRate: sampleRate,
            duration: duration
        )
    }

    /// Calculate the expected frequency bin for a given frequency
    static func expectedFrequencyBin(
        frequency: Float,
        sampleRate: Float = defaultSampleRate,
        fftSize: Int = defaultFFTSize
    ) -> Int {
        return Int(frequency / (sampleRate / Float(fftSize)))
    }

    /// Verify spectrogram dimensions and basic properties
    static func verifySpectrogramProperties(
        spectrogram: [[Float]],
        expectedFrames: Int? = nil,
        expectedBins: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            spectrogram.isEmpty, "Spectrogram should not be empty", file: file, line: line)
        if let expectedFrames = expectedFrames {
            XCTAssertEqual(
                spectrogram.count, expectedFrames, "Unexpected number of frames", file: file,
                line: line)
        }
        XCTAssertEqual(
            spectrogram[0].count, expectedBins, "Unexpected number of frequency bins", file: file,
            line: line)
    }

    /// Verify mel spectrogram dimensions and properties
    static func verifyMelSpectrogramProperties(
        melSpectrogram: [[Float]],
        expectedFrames: Int? = nil,
        expectedBands: Int = 40,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            melSpectrogram.isEmpty, "Mel spectrogram should not be empty", file: file, line: line)
        if let expectedFrames = expectedFrames {
            XCTAssertEqual(
                melSpectrogram.count, expectedFrames, "Unexpected number of frames", file: file,
                line: line)
        }
        XCTAssertEqual(
            melSpectrogram[0].count, expectedBands, "Unexpected number of mel bands", file: file,
            line: line)

        // Verify no invalid values
        for frame in melSpectrogram {
            for value in frame {
                XCTAssertFalse(
                    value.isNaN, "Mel spectrogram should not contain NaN values", file: file,
                    line: line)
                XCTAssertFalse(
                    value.isInfinite, "Mel spectrogram should not contain infinite values",
                    file: file, line: line)
            }
        }
    }

    /// Verify log-mel spectrogram dimensions and properties
    static func verifyLogMelSpectrogramProperties(
        logMelSpectrogram: [[Float]],
        expectedFrames: Int? = nil,
        expectedBands: Int = 40,
        minDb: Float = -80.0,
        maxDb: Float = 0.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            logMelSpectrogram.isEmpty, "Log-mel spectrogram should not be empty", file: file,
            line: line)
        if let expectedFrames = expectedFrames {
            XCTAssertEqual(
                logMelSpectrogram.count, expectedFrames, "Unexpected number of frames", file: file,
                line: line)
        }
        XCTAssertEqual(
            logMelSpectrogram[0].count, expectedBands, "Unexpected number of mel bands", file: file,
            line: line)

        // Verify values are within dB range and valid
        for frame in logMelSpectrogram {
            for value in frame {
                XCTAssertFalse(
                    value.isNaN, "Log-mel spectrogram should not contain NaN values", file: file,
                    line: line)
                XCTAssertFalse(
                    value.isInfinite, "Log-mel spectrogram should not contain infinite values",
                    file: file, line: line)
                XCTAssertLessThanOrEqual(
                    value, maxDb, "Maximum log-mel value should be <= \(maxDb) dB", file: file,
                    line: line)
                XCTAssertGreaterThanOrEqual(
                    value, minDb, "Minimum log-mel value should be >= \(minDb) dB", file: file,
                    line: line)
            }
        }
    }
}
