import XCTest

@testable import Utilities

final class UtilitiesTests: XCTestCase {
    func testSineWaveGeneration() {
        // Test with default parameters
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 1.0)

        // Check the length
        XCTAssertEqual(
            sineWave.count, 44100, "Sine wave should have 44100 samples for 1 second at 44.1kHz")

        // Check that values are within range [-1, 1]
        for sample in sineWave {
            XCTAssertGreaterThanOrEqual(sample, -1.0, "Sample should be >= -1.0")
            XCTAssertLessThanOrEqual(sample, 1.0, "Sample should be <= 1.0")
        }

        // Test with custom parameters
        let customSineWave = Utilities.generateSineWave(
            frequency: 880.0, sampleRate: 48000.0, duration: 0.5)

        // Check the length
        XCTAssertEqual(
            customSineWave.count, 24000,
            "Sine wave should have 24000 samples for 0.5 seconds at 48kHz")
    }

    @MainActor
    func testTimerFunctionality() {
        // Test that the timer functions correctly measure elapsed time
        Utilities.startTimer(id: "test")

        // Sleep for a known duration
        let sleepDuration = 0.1  // 100ms
        Thread.sleep(forTimeInterval: sleepDuration)

        let elapsed = Utilities.endTimer(id: "test")

        // Check that the elapsed time is approximately correct (with some tolerance for timing variations)
        XCTAssertTrue(
            elapsed >= sleepDuration * 1000 * 0.9,
            "Timer should measure at least 90% of the expected duration")
        XCTAssertTrue(
            elapsed <= sleepDuration * 1000 * 1.5,
            "Timer should not measure more than 150% of the expected duration")
    }

    func testLoggingFunctionality() {
        // Since we can't easily capture stdout in Swift tests, we'll just verify that the log function doesn't crash
        XCTAssertNoThrow(Utilities.log("Test log message"), "Logging should not throw an exception")

        // Log multiple messages to ensure it handles different inputs correctly
        XCTAssertNoThrow(Utilities.log(""), "Logging an empty string should not throw")
        XCTAssertNoThrow(
            Utilities.log("Special characters: !@#$%^&*()"),
            "Logging special characters should not throw")
        XCTAssertNoThrow(
            Utilities.log("Unicode: 你好, 世界"), "Logging Unicode characters should not throw")
    }
}
