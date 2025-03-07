import XCTest

@testable import DSP

final class StreamingMelProcessorTests: XCTestCase {
    var processor: StreamingMelProcessor!

    override func setUp() {
        super.setUp()
        processor = StreamingMelProcessor(
            fftSize: 1024,
            hopSize: 256,
            sampleRate: 44100.0,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: 8000.0
        )
    }

    override func tearDown() {
        processor = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(processor)
        XCTAssertEqual(processor.getBufferLength(), 0)

        // Test with different parameters
        let customProcessor = StreamingMelProcessor(
            fftSize: 2048,
            hopSize: 512,
            sampleRate: 48000.0,
            melBands: 80,
            minFrequency: 20.0,
            maxFrequency: 20000.0
        )
        XCTAssertNotNil(customProcessor)
        XCTAssertEqual(customProcessor.getBufferLength(), 0)
    }

    func testAddSamples() {
        let testSamples = Array(repeating: Float(0.5), count: 1000)
        processor.addSamples(testSamples)
        XCTAssertEqual(processor.getBufferLength(), 1000)

        // Add more samples to test buffer size limiting
        processor.addSamples(testSamples)
        XCTAssertLessThanOrEqual(processor.getBufferLength(), 1024 * 3)
    }

    func testProcessMelSpectrogram() {
        // Generate a test signal (440 Hz sine wave)
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let frequency: Float = 440.0
        let numSamples = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<numSamples {
            let t = Float(i) / sampleRate
            samples.append(sin(2.0 * .pi * frequency * t))
        }

        processor.addSamples(samples)

        // Process all available frames
        let (melFrames, samplesConsumed) = processor.processMelSpectrogram()

        XCTAssertFalse(melFrames.isEmpty)
        XCTAssertEqual(melFrames[0].count, 40)  // Number of mel bands
        XCTAssertGreaterThan(samplesConsumed, 0)

        // Verify no NaN or infinite values
        for frame in melFrames {
            for value in frame {
                XCTAssertFalse(value.isNaN)
                XCTAssertFalse(value.isInfinite)
            }
        }

        // Test with empty buffer
        processor.reset()
        let (emptyFrames, zeroConsumed) = processor.processMelSpectrogram()
        XCTAssertTrue(emptyFrames.isEmpty)
        XCTAssertEqual(zeroConsumed, 0)
    }

    func testProcessLogMelSpectrogram() {
        // Generate a test signal (440 Hz sine wave)
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let frequency: Float = 440.0
        let numSamples = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<numSamples {
            let t = Float(i) / sampleRate
            samples.append(sin(2.0 * .pi * frequency * t))
        }

        processor.addSamples(samples)

        // Process all available frames
        let (logMelFrames, samplesConsumed) = processor.processLogMelSpectrogram()

        XCTAssertFalse(logMelFrames.isEmpty)
        XCTAssertEqual(logMelFrames[0].count, 40)  // Number of mel bands
        XCTAssertGreaterThan(samplesConsumed, 0)

        // Verify values are within expected dB range and no NaN/infinite values
        for frame in logMelFrames {
            for value in frame {
                XCTAssertFalse(value.isNaN)
                XCTAssertFalse(value.isInfinite)
                XCTAssertLessThanOrEqual(value, 0.0)  // dB values should be <= 0
                XCTAssertGreaterThanOrEqual(value, -80.0)  // Typical floor for dB values
            }
        }

        // Test with empty buffer
        processor.reset()
        let (emptyFrames, zeroConsumed) = processor.processLogMelSpectrogram()
        XCTAssertTrue(emptyFrames.isEmpty)
        XCTAssertEqual(zeroConsumed, 0)
    }

    func testMinFramesProcessing() {
        // Generate 2 seconds of audio
        let sampleRate: Float = 44100.0
        let duration: Float = 2.0
        let frequency: Float = 440.0
        let numSamples = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<numSamples {
            let t = Float(i) / sampleRate
            samples.append(sin(2.0 * .pi * frequency * t))
        }

        processor.addSamples(samples)

        // Request specific number of frames
        let requestedFrames = 5
        let (melFrames, _) = processor.processMelSpectrogram(minFrames: requestedFrames)

        XCTAssertEqual(melFrames.count, requestedFrames)

        // Request more frames than available
        let (limitedFrames, _) = processor.processMelSpectrogram(minFrames: 1000)
        XCTAssertLessThan(limitedFrames.count, 1000)
    }

    func testReset() {
        let testSamples = Array(repeating: Float(0.5), count: 1000)
        processor.addSamples(testSamples)
        XCTAssertGreaterThan(processor.getBufferLength(), 0)

        processor.reset()
        XCTAssertEqual(processor.getBufferLength(), 0)
    }

    func testPerformanceOfMelSpectrogram() {
        // Generate 5 seconds of audio for performance testing
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0
        let frequency: Float = 440.0
        let numSamples = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<numSamples {
            let t = Float(i) / sampleRate
            samples.append(sin(2.0 * .pi * frequency * t))
        }

        processor.addSamples(samples)

        measure {
            let (_, _) = processor.processMelSpectrogram()
        }
    }

    func testPerformanceOfLogMelSpectrogram() {
        // Generate 5 seconds of audio for performance testing
        let sampleRate: Float = 44100.0
        let duration: Float = 5.0
        let frequency: Float = 440.0
        let numSamples = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<numSamples {
            let t = Float(i) / sampleRate
            samples.append(sin(2.0 * .pi * frequency * t))
        }

        processor.addSamples(samples)

        measure {
            let (_, _) = processor.processLogMelSpectrogram()
        }
    }
}
