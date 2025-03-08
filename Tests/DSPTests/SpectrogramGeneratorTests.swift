import XCTest

@testable import DSP
@testable import Utilities

final class SpectrogramGeneratorTests: DSPBaseTestCase {
    var spectrogramGenerator: SpectrogramGenerator!

    override func setUp() {
        super.setUp()
        spectrogramGenerator = SpectrogramGenerator(fftSize: fftSize)
    }

    override func tearDown() {
        spectrogramGenerator = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(spectrogramGenerator, "SpectrogramGenerator should initialize successfully")
        XCTAssertEqual(
            spectrogramGenerator.fftSize, fftSize, "FFT size should match initialized value")

        // Test with custom hop size
        let customHopGenerator = SpectrogramGenerator(fftSize: fftSize, hopSize: fftSize / 2)
        XCTAssertNotNil(
            customHopGenerator, "SpectrogramGenerator should initialize with custom hop size")
        XCTAssertEqual(
            customHopGenerator.fftSize, fftSize, "FFT size should match initialized value")
    }

    func testGenerateSpectrogram() {
        // Create a signal that changes frequency halfway through
        let duration: Float = 1.0
        let firstHalf = generateTestSignal(frequency: 440.0, duration: duration / 2)
        let secondHalf = generateTestSignal(frequency: 880.0, duration: duration / 2)

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

        // Test dimensions
        let hopSize = fftSize / 4  // Default hop size
        let expectedFrames = (signal.count - fftSize) / hopSize + 1
        DSPTestUtilities.verifySpectrogramProperties(
            spectrogram: spectrogram,
            expectedFrames: expectedFrames,
            expectedBins: fftSize / 2
        )

        // Test with custom hop size
        let customHopSize = fftSize / 2
        let spectrogramCustomHop = spectrogramGenerator.generateSpectrogram(
            inputBuffer: signal,
            hopSize: customHopSize
        )
        let expectedFramesCustomHop = (signal.count - fftSize) / customHopSize + 1
        DSPTestUtilities.verifySpectrogramProperties(
            spectrogram: spectrogramCustomHop,
            expectedFrames: expectedFramesCustomHop,
            expectedBins: fftSize / 2
        )

        // Verify frequency content
        if spectrogram.count >= 2 {
            // Get the bin indices for 440Hz and 880Hz
            let bin440 = DSPTestUtilities.expectedFrequencyBin(frequency: 440.0)
            let bin880 = DSPTestUtilities.expectedFrequencyBin(frequency: 880.0)

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

            XCTAssertGreaterThan(
                earlyEnergy440, earlyEnergy880,
                "Early frames should have more energy at 440Hz than 880Hz"
            )
            XCTAssertGreaterThan(
                lateEnergy880, lateEnergy440,
                "Late frames should have more energy at 880Hz than 440Hz"
            )
        }
    }

    func testGenerateSpectrogramWithSmallBuffer() {
        let smallBuffer = [Float](repeating: 0.0, count: fftSize / 2)
        let spectrogram = spectrogramGenerator.generateSpectrogram(inputBuffer: smallBuffer)
        XCTAssertTrue(
            spectrogram.isEmpty,
            "Spectrogram should be empty for input smaller than FFT size"
        )
    }

    func testPerformanceWithLargeFFTSize() {
        // Test with a larger FFT size
        let largeFFTGenerator = SpectrogramGenerator(fftSize: 4096)
        let sineWave = generateTestSignal(duration: 5.0)

        measurePerformance(iterations: 3) {
            _ = largeFFTGenerator.generateSpectrogram(inputBuffer: sineWave, hopSize: 1024)
        }
    }

    func testParallelSpectrogramGeneration() {
        // Create a signal that changes frequency halfway through
        let duration: Float = 2.0  // Longer duration for parallel processing
        let firstHalf = generateTestSignal(frequency: 440.0, duration: duration / 2)
        let secondHalf = generateTestSignal(frequency: 880.0, duration: duration / 2)

        // Combine the two halves
        var signal = [Float](repeating: 0.0, count: Int(sampleRate * duration))
        for i in 0..<firstHalf.count {
            signal[i] = firstHalf[i]
        }
        for i in 0..<secondHalf.count {
            signal[i + firstHalf.count] = secondHalf[i]
        }

        // Generate spectrograms with both methods
        let hopSize = fftSize / 4
        let sequentialSpectrogram = spectrogramGenerator.generateSpectrogram(
            inputBuffer: signal,
            hopSize: hopSize
        )

        let parallelSpectrogram = spectrogramGenerator.generateSpectrogramParallel(
            inputBuffer: signal,
            hopSize: hopSize
        )

        // Verify both spectrograms have the same dimensions
        XCTAssertEqual(
            sequentialSpectrogram.count,
            parallelSpectrogram.count,
            "Sequential and parallel spectrograms should have the same number of frames"
        )

        if !sequentialSpectrogram.isEmpty && !parallelSpectrogram.isEmpty {
            XCTAssertEqual(
                sequentialSpectrogram[0].count,
                parallelSpectrogram[0].count,
                "Sequential and parallel spectrograms should have the same number of frequency bins"
            )
        }

        // Verify the content is similar (not necessarily identical due to floating-point precision)
        if !sequentialSpectrogram.isEmpty && !parallelSpectrogram.isEmpty {
            var maxDifference: Float = 0.0

            for i in 0..<min(sequentialSpectrogram.count, parallelSpectrogram.count) {
                for j in 0..<min(sequentialSpectrogram[i].count, parallelSpectrogram[i].count) {
                    let diff = abs(sequentialSpectrogram[i][j] - parallelSpectrogram[i][j])
                    maxDifference = max(maxDifference, diff)
                }
            }

            // Allow for small floating-point differences
            XCTAssertLessThan(
                maxDifference,
                0.001,
                "Sequential and parallel spectrograms should produce similar results"
            )
        }
    }

    func testCompareSequentialAndParallelPerformance() {
        let sineWave = generateTestSignal(duration: 10.0)

        // Manually time the operations instead of using XCTest's measure
        var sequentialTimes: [TimeInterval] = []
        var parallelTimes: [TimeInterval] = []

        // Run multiple iterations
        for _ in 0..<5 {
            // Measure sequential
            let sequentialStart = Date()
            _ = spectrogramGenerator.generateSpectrogram(
                inputBuffer: sineWave,
                hopSize: 256
            )
            sequentialTimes.append(-sequentialStart.timeIntervalSinceNow)

            // Measure parallel
            let parallelStart = Date()
            _ = spectrogramGenerator.generateSpectrogramParallel(
                inputBuffer: sineWave,
                hopSize: 256
            )
            parallelTimes.append(-parallelStart.timeIntervalSinceNow)
        }

        // Calculate averages
        let sequentialAvg = sequentialTimes.reduce(0, +) / Double(sequentialTimes.count)
        let parallelAvg = parallelTimes.reduce(0, +) / Double(parallelTimes.count)

        print("Sequential average: \(sequentialAvg) seconds")
        print("Parallel average: \(parallelAvg) seconds")
        print("Speedup: \(sequentialAvg / parallelAvg)x")

        // Optional: Assert that parallel is faster
        XCTAssertLessThan(parallelAvg, sequentialAvg, "Parallel processing should be faster")
    }

    func testPerformanceOfSequentialSpectrogram() {
        let sineWave = generateTestSignal(duration: 10.0)

        print("Sequential processing performance:")
        measurePerformance(iterations: 3) { [unowned self] in
            _ = self.spectrogramGenerator.generateSpectrogram(
                inputBuffer: sineWave,
                hopSize: 256
            )
        }
    }

    func testPerformanceOfParallelSpectrogram() {
        let sineWave = generateTestSignal(duration: 10.0)

        print("Parallel processing performance:")
        measurePerformance(iterations: 3) { [unowned self] in
            _ = self.spectrogramGenerator.generateSpectrogramParallel(
                inputBuffer: sineWave,
                hopSize: 256
            )
        }
    }

    func testPerformanceOfSpectrogramWithHopSize128() {
        let sineWave = generateTestSignal(duration: 10.0)
        measurePerformance(iterations: 5) { [unowned self] in
            _ = self.spectrogramGenerator.generateSpectrogram(
                inputBuffer: sineWave,
                hopSize: 128
            )
        }
    }

    func testPerformanceOfSpectrogramWithHopSize256() {
        let sineWave = generateTestSignal(duration: 10.0)
        measurePerformance(iterations: 5) { [unowned self] in
            _ = self.spectrogramGenerator.generateSpectrogram(
                inputBuffer: sineWave,
                hopSize: 256
            )
        }
    }

    func testPerformanceOfSpectrogramWithHopSize512() {
        let sineWave = generateTestSignal(duration: 10.0)
        measurePerformance(iterations: 5) { [unowned self] in
            _ = self.spectrogramGenerator.generateSpectrogram(
                inputBuffer: sineWave,
                hopSize: 512
            )
        }
    }
}
