import XCTest
@testable import Utilities

final class UtilitiesTests: XCTestCase {
    func testSineWaveGeneration() {
        // Test that a 440Hz sine wave at 44.1kHz has the expected properties
        let frequency: Float = 440.0
        let sampleRate: Float = 44100.0
        let duration: Float = 0.1  // 100ms is enough for testing

        let sineWave = Utilities.generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration)

        // Check the length of the generated sine wave
        XCTAssertEqual(sineWave.count, Int(sampleRate * duration), "Sine wave should have the expected number of samples")

        // Check the amplitude (should be between -1 and 1)
        for sample in sineWave {
            XCTAssertGreaterThanOrEqual(sample, -1.0, "Sample should be >= -1.0")
            XCTAssertLessThanOrEqual(sample, 1.0, "Sample should be <= 1.0")
        }

        // Check zero crossings - a 440Hz sine wave should cross zero about 44 times in 0.1 seconds
        // (440 cycles per second = 44 cycles in 0.1 seconds, each cycle has 2 zero crossings)
        var zeroCrossings = 0
        for i in 1..<sineWave.count {
            if (sineWave[i-1] < 0 && sineWave[i] >= 0) || (sineWave[i-1] >= 0 && sineWave[i] < 0) {
                zeroCrossings += 1
            }
        }

        // Allow for some margin of error due to sampling
        let expectedZeroCrossings = Int(frequency * duration * 2)
        XCTAssertTrue(abs(zeroCrossings - expectedZeroCrossings) <= 2,
                     "Zero crossings should be approximately \(expectedZeroCrossings), but was \(zeroCrossings)")
    }

    @MainActor
    func testTimerFunctionality() {
        // Test that the timer functions correctly measure elapsed time
        Utilities.startTimer(id: "test")

        // Sleep for a known duration
        let sleepDuration = 0.1 // 100ms
        Thread.sleep(forTimeInterval: sleepDuration)

        let elapsed = Utilities.endTimer(id: "test")

        // Check that the elapsed time is approximately correct (with some tolerance for timing variations)
        XCTAssertTrue(elapsed >= sleepDuration * 1000 * 0.9, "Timer should measure at least 90% of the expected duration")
        XCTAssertTrue(elapsed <= sleepDuration * 1000 * 1.5, "Timer should not measure more than 150% of the expected duration")
    }
}