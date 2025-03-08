import XCTest

@testable import DSP

final class StreamingMelProcessorTests: DSPBaseTestCase {
    var processor: StreamingMelProcessor!
    let hopSize = 256
    let melBands = 40

    override func setUp() {
        super.setUp()
        processor = StreamingMelProcessor(
            fftSize: fftSize,
            hopSize: hopSize,
            sampleRate: sampleRate,
            melBands: melBands,
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
            fftSize: fftSize * 2,
            hopSize: hopSize * 2,
            sampleRate: 48000.0,
            melBands: melBands * 2,
            minFrequency: 20.0,
            maxFrequency: 20000.0
        )
        XCTAssertNotNil(customProcessor)
        XCTAssertEqual(customProcessor.getBufferLength(), 0)
    }

    func testAddSamples() {
        let testSamples = [Float](repeating: 0.5, count: 1000)
        processor.addSamples(testSamples)
        XCTAssertEqual(processor.getBufferLength(), 1000)

        // Add more samples to test buffer size limiting
        processor.addSamples(testSamples)
        XCTAssertLessThanOrEqual(processor.getBufferLength(), fftSize * 3)
    }

    func testProcessMelSpectrogram() {
        let sineWave = generateTestSignal(duration: 0.5)
        processor.addSamples(sineWave)

        // Process all available frames
        let (melFrames, samplesConsumed) = processor.processMelSpectrogram()

        // Use the utility method for verification
        DSPTestUtilities.verifyMelSpectrogramProperties(
            melSpectrogram: melFrames,
            expectedBands: melBands
        )
        XCTAssertGreaterThan(samplesConsumed, 0)

        // Instead of trying to calculate the exact number, which depends on internal implementation
        // details of StreamingMelProcessor, let's verify that:
        // 1. Some samples were consumed (already checked above)
        // 2. The number of samples consumed is reasonable (less than or equal to the input)
        XCTAssertLessThanOrEqual(
            samplesConsumed, sineWave.count,
            "Should not consume more samples than provided")

        // We can also check that the number of frames produced matches our expectations
        let expectedFrameCount = (samplesConsumed - fftSize) / hopSize + 1
        XCTAssertEqual(
            melFrames.count, expectedFrameCount,
            "Number of frames should match the calculation based on samples consumed")

        // Test with empty buffer
        processor.reset()
        let (emptyFrames, zeroConsumed) = processor.processMelSpectrogram()
        XCTAssertTrue(emptyFrames.isEmpty)
        XCTAssertEqual(zeroConsumed, 0)
    }

    func testProcessLogMelSpectrogram() {
        let sineWave = generateTestSignal(duration: 0.5)
        processor.addSamples(sineWave)

        // Process all available frames
        let (logMelFrames, samplesConsumed) = processor.processLogMelSpectrogram()

        DSPTestUtilities.verifyLogMelSpectrogramProperties(
            logMelSpectrogram: logMelFrames,
            expectedBands: melBands
        )
        XCTAssertGreaterThan(samplesConsumed, 0)

        // Test with empty buffer
        processor.reset()
        let (emptyFrames, zeroConsumed) = processor.processLogMelSpectrogram()
        XCTAssertTrue(emptyFrames.isEmpty)
        XCTAssertEqual(zeroConsumed, 0)
    }

    func testMinFramesProcessing() {
        let sineWave = generateTestSignal(duration: 2.0)  // 2 seconds of audio
        processor.addSamples(sineWave)

        // Request specific number of frames
        let requestedFrames = 5
        let (melFrames, _) = processor.processMelSpectrogram(minFrames: requestedFrames)

        XCTAssertEqual(melFrames.count, requestedFrames)

        // Request more frames than available
        let (limitedFrames, _) = processor.processMelSpectrogram(minFrames: 1000)
        XCTAssertLessThan(limitedFrames.count, 1000)
    }

    func testReset() {
        let testSamples = [Float](repeating: 0.5, count: 1000)
        processor.addSamples(testSamples)
        XCTAssertGreaterThan(processor.getBufferLength(), 0)

        processor.reset()
        XCTAssertEqual(processor.getBufferLength(), 0)
    }
}
