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
        let spectrogram = dsp.generateSpectrogram(inputBuffer: signal)

        // Test that the spectrogram has the expected dimensions
        let hopSize = 256  // Default hop size
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
        let spectrogramCustomHop = dsp.generateSpectrogram(
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
        let spectrogram = dsp.generateSpectrogram(inputBuffer: smallBuffer)
        XCTAssertEqual(
            spectrogram.count, 0, "Spectrogram should be empty for input smaller than FFT size")
    }

    func testSpecToMelSpec() {
        // Generate a real spectrogram using a sine wave
        let sampleRate: Float = 44100
        let duration: Float = 0.5
        let signal = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Generate spectrogram
        let spectrogram = dsp.generateSpectrogram(inputBuffer: signal)
        XCTAssertFalse(spectrogram.isEmpty, "Spectrogram should not be empty")

        // Convert to mel spectrogram
        let melSpec = dsp.specToMelSpec(spectrogram: spectrogram)

        // Check dimensions
        XCTAssertEqual(
            melSpec.count, spectrogram.count,
            "Mel spectrogram should have same number of frames as spectrogram")
        XCTAssertEqual(melSpec[0].count, 40, "Mel spectrogram should have 40 mel bands")

        // Check values
        for frame in melSpec {
            XCTAssertFalse(frame.isEmpty, "Mel spectrogram frame should not be empty")
            for value in frame {
                XCTAssertFalse(value.isNaN, "Mel spectrogram should not contain NaN values")
                XCTAssertFalse(
                    value.isInfinite, "Mel spectrogram should not contain infinite values")
                XCTAssertGreaterThanOrEqual(
                    value, 0, "Mel spectrogram values should be non-negative")
            }
        }

        // Test with empty input
        let emptyMelSpec = dsp.specToMelSpec(spectrogram: [])
        XCTAssertTrue(emptyMelSpec.isEmpty, "Mel spectrogram should be empty for empty input")
    }

    func testMelToLogMel() {
        // Generate a real spectrogram using a sine wave
        let sampleRate: Float = 44100
        let duration: Float = 0.5
        let signal = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Generate spectrogram and convert to mel spectrogram
        let spectrogram = dsp.generateSpectrogram(inputBuffer: signal)
        let melSpec = dsp.specToMelSpec(spectrogram: spectrogram)

        // Convert to log-mel spectrogram
        let logMelSpec = dsp.melToLogMel(melSpectrogram: melSpec)

        // Check dimensions
        XCTAssertEqual(
            logMelSpec.count, melSpec.count,
            "Log-mel spectrogram should have same number of frames as mel spectrogram")
        XCTAssertEqual(logMelSpec[0].count, 40, "Log-mel spectrogram should have 40 mel bands")

        // Check values
        var hasValues = false
        var minValue: Float = 0
        var maxValue: Float = -Float.infinity

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
        let emptyLogMelSpec = dsp.melToLogMel(melSpectrogram: [])
        XCTAssertTrue(
            emptyLogMelSpec.isEmpty, "Log-mel spectrogram should be empty for empty input")
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

    func testPerformanceOfLogMelSpectrogram() {
        // Generate a large test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0  // 5 seconds of audio
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Generate spectrogram and mel spectrogram
        let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave, hopSize: 256)
        let melSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)

        // Measure the performance of the log-mel spectrogram conversion
        measure {
            _ = dsp.melToLogMel(melSpectrogram: melSpectrogram)
        }
    }

    // MARK: - StreamingMelProcessor Tests

    func testStreamingMelProcessorInitialization() {
        let processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        XCTAssertNotNil(processor, "StreamingMelProcessor should initialize successfully")
        XCTAssertEqual(processor.getBufferLength(), 0, "Initial buffer should be empty")
    }

    func testStreamingMelProcessorAddSamples() {
        let processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Add some samples
        let samples = [Float](repeating: 0.5, count: 500)
        processor.addSamples(samples)

        XCTAssertEqual(processor.getBufferLength(), 500, "Buffer should contain added samples")

        // Add more samples
        processor.addSamples(samples)
        XCTAssertEqual(processor.getBufferLength(), 1000, "Buffer should contain all added samples")

        // Add enough samples to trigger buffer trimming
        let largeSamples = [Float](repeating: 0.5, count: 4000)
        processor.addSamples(largeSamples)

        // Buffer should be trimmed to maxBufferSize (fftSize * 3 = 3072)
        XCTAssertEqual(
            processor.getBufferLength(), 3072, "Buffer should be trimmed to maxBufferSize")

        // Reset buffer
        processor.reset()
        XCTAssertEqual(processor.getBufferLength(), 0, "Buffer should be empty after reset")
    }

    func testStreamingMelProcessorWithInsufficientSamples() {
        let processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Add fewer samples than fftSize
        let samples = [Float](repeating: 0.5, count: 512)
        processor.addSamples(samples)

        // Should return empty results since we don't have enough samples
        let (melFrames, samplesConsumed) = processor.processMelSpectrogram()

        XCTAssertTrue(melFrames.isEmpty, "Should return empty mel frames with insufficient samples")
        XCTAssertEqual(samplesConsumed, 0, "No samples should be consumed with insufficient data")
        XCTAssertEqual(processor.getBufferLength(), 512, "Buffer should remain unchanged")
    }

    func testStreamingMelProcessorProcessing() {
        let fftSize = 1024
        let hopSize = 256
        let processor = StreamingMelProcessor(
            fftSize: fftSize,
            hopSize: hopSize,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Generate a test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5  // 0.5 seconds
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Add all samples at once
        processor.addSamples(sineWave)

        // Process all available frames
        let (melFrames, samplesConsumed) = processor.processMelSpectrogram()

        // Verify we got some frames
        XCTAssertFalse(melFrames.isEmpty, "Should generate at least one frame")
        XCTAssertEqual(melFrames[0].count, 40, "Each frame should have 40 mel bands")

        // Verify some samples were consumed
        XCTAssertGreaterThan(samplesConsumed, 0, "Should consume some samples")

        // Buffer should have remaining samples or be empty
        XCTAssertLessThanOrEqual(
            processor.getBufferLength(), sineWave.count, "Buffer should not grow")
    }

    func testStreamingMelProcessorChunkedProcessing() {
        let fftSize = 1024
        let hopSize = 256
        let processor = StreamingMelProcessor(
            fftSize: fftSize,
            hopSize: hopSize,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Generate a test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 1.0  // 1 second
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Split into chunks
        let chunkSize = 1000
        var allMelFrames: [[Float]] = []
        var totalSamplesConsumed = 0

        for i in stride(from: 0, to: sineWave.count, by: chunkSize) {
            let end = min(i + chunkSize, sineWave.count)
            let chunk = Array(sineWave[i..<end])

            // Add chunk to processor
            processor.addSamples(chunk)

            // Process available frames
            let (melFrames, samplesConsumed) = processor.processMelSpectrogram()
            allMelFrames.append(contentsOf: melFrames)
            totalSamplesConsumed += samplesConsumed
        }

        // Process any remaining frames
        let (finalMelFrames, finalSamplesConsumed) = processor.processMelSpectrogram()
        allMelFrames.append(contentsOf: finalMelFrames)
        totalSamplesConsumed += finalSamplesConsumed

        // Verify we got some frames
        XCTAssertFalse(allMelFrames.isEmpty, "Should generate at least one frame")

        // Check that all frames have the correct dimensions
        for frame in allMelFrames {
            XCTAssertEqual(frame.count, 40, "Each frame should have 40 mel bands")
        }
    }

    func testStreamingLogMelSpectrogram() {
        let processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Generate a test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        processor.addSamples(sineWave)

        // Process log-mel spectrogram
        let (logMelFrames, _) = processor.processLogMelSpectrogram()

        XCTAssertFalse(logMelFrames.isEmpty, "Should generate log-mel frames")
        XCTAssertEqual(logMelFrames[0].count, 40, "Each frame should have 40 mel bands")

        // Check log-mel values
        for frame in logMelFrames {
            for value in frame {
                XCTAssertFalse(value.isNaN, "Log-mel values should not be NaN")
                XCTAssertFalse(value.isInfinite, "Log-mel values should not be infinite")
                XCTAssertLessThanOrEqual(value, 0.0, "Log-mel values should be <= 0 dB")
                XCTAssertGreaterThanOrEqual(value, -80.0, "Log-mel values should be >= -80 dB")
            }
        }
    }

    func testStreamingProcessorWithMinFrames() {
        let processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Generate a test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 1.0
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        processor.addSamples(sineWave)

        // Request only 5 frames
        let minFrames = 5
        let (melFrames, _) = processor.processMelSpectrogram(minFrames: minFrames)

        // Verify we got the requested number of frames or fewer (if not enough samples)
        XCTAssertLessThanOrEqual(
            melFrames.count, minFrames, "Should generate at most the requested number of frames")
        XCTAssertGreaterThan(melFrames.count, 0, "Should generate at least one frame")

        // Process remaining frames
        let (remainingFrames, _) = processor.processMelSpectrogram()

        // Verify we got some remaining frames or none
        XCTAssertGreaterThanOrEqual(
            remainingFrames.count, 0, "Should have zero or more remaining frames")
    }

    func testPerformanceOfStreamingProcessor() {
        let processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )

        // Generate a large test signal
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0  // 5 seconds
        let sineWave = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Measure performance of processing in chunks
        measure {
            processor.reset()

            // Process in chunks of 4096 samples (typical audio buffer size)
            let chunkSize = 4096
            for i in stride(from: 0, to: sineWave.count, by: chunkSize) {
                let end = min(i + chunkSize, sineWave.count)
                let chunk = Array(sineWave[i..<end])

                processor.addSamples(chunk)
                _ = processor.processLogMelSpectrogram()
            }
        }
    }
}
