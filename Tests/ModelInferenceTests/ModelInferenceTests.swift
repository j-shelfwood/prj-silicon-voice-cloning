import XCTest

@testable import DSP
@testable import ModelInference
@testable import Utilities

final class ModelInferenceTests: XCTestCase {
    var modelInference: ModelInference!

    override func setUp() {
        super.setUp()
        // Create a configuration that simulates model loading for tests
        let config = ModelInference.InferenceConfig(simulateModelLoading: true)
        modelInference = ModelInference(config: config)
    }

    override func tearDown() {
        modelInference = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(modelInference, "ModelInference should initialize successfully")

        // Test initialization with custom config
        let config = ModelInference.InferenceConfig(
            useNeuralEngine: false, useGPU: true, useCPUOnly: false, simulateModelLoading: true)
        let customModelInference = ModelInference(config: config)
        XCTAssertNotNil(customModelInference, "ModelInference should initialize with custom config")
    }

    func testCoreMLAvailability() {
        // This should always return true on Apple platforms
        let available = modelInference.isCoreMLAvailable()

        #if canImport(CoreML)
            XCTAssertTrue(available, "Core ML should be available on this platform")
        #else
            XCTAssertFalse(available, "Core ML should not be available on this platform")
        #endif
    }

    func testGetAvailableComputeUnits() {
        let computeUnits = modelInference.getAvailableComputeUnits()

        XCTAssertFalse(computeUnits.isEmpty, "Available compute units string should not be empty")
        XCTAssertTrue(computeUnits.contains("CPU"), "Available compute units should include CPU")

        // Note: These assertions might fail on platforms without GPU or Neural Engine
        // XCTAssertTrue(computeUnits.contains("GPU"), "Available compute units should include GPU")
        // XCTAssertTrue(computeUnits.contains("Neural Engine"), "Available compute units should include Neural Engine")
    }

    func testLoadModel() {
        // Test with a non-existent path (should succeed with simulation)
        let nonExistentPath = "/path/to/nonexistent/model.mlmodel"
        let loadResult = modelInference.loadModel(
            modelPath: nonExistentPath, modelType: .voiceConverter)

        XCTAssertTrue(
            loadResult,
            "Loading non-existent model should return true with simulation enabled")

        // Test with a different model type
        let loadResult2 = modelInference.loadModel(
            modelPath: "/path/to/another/model.mlmodel", modelType: .vocoder)
        XCTAssertTrue(loadResult2, "Loading another model should succeed with simulation enabled")
    }

    func testRunInference() async {
        // Since the current implementation returns nil, we can only test that it doesn't crash
        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let output: [Float]? = await modelInference.runInference(input: input)

        XCTAssertNil(output, "Inference should return nil with placeholder implementation")

        // TODO: When real implementation is added, test with a real model and check the output
    }

    func testProcessVoiceConversion() async {
        // Load a voice conversion model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .voiceConverter)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Create a test mel-spectrogram
        let melSpectrogram = createTestMelSpectrogram(frames: 100, bands: 40)

        // Process the mel-spectrogram
        let convertedMel = await modelInference.processVoiceConversion(
            melSpectrogram: melSpectrogram)

        // Verify the result
        XCTAssertNotNil(convertedMel, "Voice conversion should return a result")
        XCTAssertEqual(
            convertedMel?.count, melSpectrogram.count,
            "Converted mel should have the same number of frames")
        XCTAssertEqual(
            convertedMel?[0].count, melSpectrogram[0].count,
            "Converted mel should have the same number of bands")

        // Check performance metrics
        let metrics = modelInference.getPerformanceMetrics()
        XCTAssertGreaterThan(metrics.inferenceTime, 0, "Inference time should be greater than 0")
        XCTAssertEqual(
            metrics.framesProcessed, melSpectrogram.count, "Frames processed should match input")
        XCTAssertGreaterThan(metrics.realTimeFactor, 0, "Real-time factor should be greater than 0")
    }

    func testGenerateAudio() async {
        // Load a vocoder model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .vocoder)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Create a test mel-spectrogram
        let melSpectrogram = createTestMelSpectrogram(frames: 100, bands: 40)

        // Generate audio from the mel-spectrogram
        let waveform = await modelInference.generateAudio(melSpectrogram: melSpectrogram)

        // Verify the result
        XCTAssertNotNil(waveform, "Audio generation should return a result")
        XCTAssertGreaterThan(waveform?.count ?? 0, 0, "Waveform should have samples")

        // Check performance metrics
        let metrics = modelInference.getPerformanceMetrics()
        XCTAssertGreaterThan(metrics.inferenceTime, 0, "Inference time should be greater than 0")
        XCTAssertEqual(
            metrics.framesProcessed, melSpectrogram.count, "Frames processed should match input")
        XCTAssertGreaterThan(metrics.realTimeFactor, 0, "Real-time factor should be greater than 0")
    }

    func testExtractSpeakerEmbedding() async {
        // Load a speaker encoder model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .speakerEncoder)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Create test audio samples
        let sampleRate: Float = 44100.0
        let duration: Float = 3.0
        let audioSamples = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: sampleRate, duration: duration)

        // Extract speaker embedding
        let embedding = await modelInference.extractSpeakerEmbedding(audioSamples: audioSamples)

        // Verify the result
        XCTAssertNotNil(embedding, "Speaker embedding extraction should return a result")
        XCTAssertEqual(embedding?.count, 256, "Speaker embedding should have 256 dimensions")

        // Check performance metrics
        let metrics = modelInference.getPerformanceMetrics()
        XCTAssertGreaterThan(metrics.inferenceTime, 0, "Inference time should be greater than 0")
    }

    func testModelTypeChecking() async {
        // Load a vocoder model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .vocoder)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Try to use it as a voice converter (should fail)
        let melSpectrogram = createTestMelSpectrogram(frames: 10, bands: 40)
        let convertedMel = await modelInference.processVoiceConversion(
            melSpectrogram: melSpectrogram)
        XCTAssertNil(convertedMel, "Voice conversion should fail with wrong model type")

        // Try to use it as a speaker encoder (should fail)
        let audioSamples = Utilities.generateSineWave(
            frequency: 440.0, sampleRate: 44100.0, duration: 1.0)
        let embedding = await modelInference.extractSpeakerEmbedding(audioSamples: audioSamples)
        XCTAssertNil(embedding, "Speaker embedding extraction should fail with wrong model type")

        // Use it as a vocoder (should succeed)
        let waveform = await modelInference.generateAudio(melSpectrogram: melSpectrogram)
        XCTAssertNotNil(waveform, "Audio generation should succeed with correct model type")
    }

    func testModelLoadingPerformance() {
        // Measure the performance of loading a model
        measure {
            for _ in 0..<10 {
                _ = modelInference.loadModel(
                    modelPath: "/path/to/model.mlmodel", modelType: .voiceConverter)
            }
        }
    }

    // MARK: - Helper methods

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
