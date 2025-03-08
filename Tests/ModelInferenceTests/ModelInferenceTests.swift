import XCTest

@testable import DSP
@testable import ModelInference
@testable import Utilities

final class ModelInferenceTests: XCTestCase {
    var modelInference: ModelInference!

    @MainActor
    override func setUp() async throws {
        // Create a configuration that simulates model loading for tests
        let config = ModelInference.InferenceConfig(simulateModelLoading: true)
        modelInference = ModelInference(config: config)
    }

    override func tearDown() {
        modelInference = nil
    }

    @MainActor
    func testInitialization() {
        XCTAssertNotNil(modelInference, "ModelInference should initialize successfully")

        // Test with custom configuration
        let config = ModelInference.InferenceConfig(
            useNeuralEngine: false, useGPU: true, useCPUOnly: false, simulateModelLoading: true)
        let customModelInference = ModelInference(config: config)
        XCTAssertNotNil(customModelInference, "ModelInference should initialize with custom config")
    }

    func testInferenceConfig() {
        // Test default configuration
        let defaultConfig = ModelInference.InferenceConfig()
        XCTAssertTrue(defaultConfig.useNeuralEngine, "Default config should use Neural Engine")
        XCTAssertTrue(defaultConfig.useGPU, "Default config should use GPU")
        XCTAssertFalse(defaultConfig.useCPUOnly, "Default config should not be CPU only")
        XCTAssertFalse(
            defaultConfig.simulateModelLoading, "Default config should not simulate model loading")

        // Test custom configuration
        let customConfig = ModelInference.InferenceConfig(
            useNeuralEngine: false, useGPU: false, useCPUOnly: true, simulateModelLoading: true)
        XCTAssertFalse(customConfig.useNeuralEngine, "Custom config should not use Neural Engine")
        XCTAssertFalse(customConfig.useGPU, "Custom config should not use GPU")
        XCTAssertTrue(customConfig.useCPUOnly, "Custom config should be CPU only")
        XCTAssertTrue(
            customConfig.simulateModelLoading, "Custom config should simulate model loading")
    }

    @MainActor
    func testLoadModel() {
        // Test with a non-existent path (should succeed with simulation)
        let nonExistentPath = "/path/to/nonexistent/model.mlmodel"
        let loadResult = modelInference.loadModel(
            modelPath: nonExistentPath, modelType: .voiceConverter)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Test with a different model type
        let loadResult2 = modelInference.loadModel(
            modelPath: "/path/to/another/model.mlmodel", modelType: .vocoder)
        XCTAssertTrue(loadResult2, "Loading another model should succeed with simulation enabled")
    }

    @MainActor
    func testVoiceConversion() async {
        // Create test mel-spectrogram
        let melSpectrogram = createTestMelSpectrogram(frames: 10, bands: 40)

        // Test without loading a model first
        let result1 = await modelInference.processVoiceConversion(melSpectrogram: melSpectrogram)
        XCTAssertNil(result1, "Voice conversion should fail without a loaded model")

        // Load a voice conversion model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .voiceConverter)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Test with loaded model
        let result2 = await modelInference.processVoiceConversion(melSpectrogram: melSpectrogram)
        XCTAssertNotNil(result2, "Voice conversion should succeed with loaded model")
        XCTAssertEqual(
            result2?.count, melSpectrogram.count,
            "Converted mel-spectrogram should have the same number of frames")
    }

    @MainActor
    func testAudioGeneration() async {
        // Create test mel-spectrogram
        let melSpectrogram = createTestMelSpectrogram(frames: 10, bands: 40)

        // Test without loading a model first
        let result1 = await modelInference.generateAudio(melSpectrogram: melSpectrogram)
        XCTAssertNil(result1, "Audio generation should fail without a loaded model")

        // Load a vocoder model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .vocoder)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Test with loaded model
        let result2 = await modelInference.generateAudio(melSpectrogram: melSpectrogram)
        XCTAssertNotNil(result2, "Audio generation should succeed with loaded model")
        XCTAssertGreaterThan(
            result2?.count ?? 0, 0, "Generated audio should have a non-zero length")
    }

    @MainActor
    func testSpeakerEmbedding() async {
        // Create test audio samples
        let audioSamples = createTestAudioSamples(length: 16000)  // 1 second at 16kHz

        // Test without loading a model first
        let result1 = await modelInference.extractSpeakerEmbedding(audioSamples: audioSamples)
        XCTAssertNil(result1, "Speaker embedding extraction should fail without a loaded model")

        // Load a speaker encoder model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .speakerEncoder)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Test with loaded model
        let result2 = await modelInference.extractSpeakerEmbedding(audioSamples: audioSamples)
        XCTAssertNotNil(result2, "Speaker embedding extraction should succeed with loaded model")
        XCTAssertEqual(
            result2?.count, 256, "Speaker embedding should have the expected dimension")

        // Check that the embedding is normalized
        if let embedding = result2 {
            let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
            XCTAssertEqual(
                norm, 1.0, accuracy: 1e-5, "Speaker embedding should be normalized to unit length")
        }
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

    func testRunInference() async {
        // Since the current implementation returns nil, we can only test that it doesn't crash
        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let output: [Float]? = await modelInference.runInference(input: input)

        XCTAssertNil(output, "Inference should return nil with placeholder implementation")

        // TODO: When real implementation is added, test with a real model and check the output
    }

    @MainActor
    func testModelTypeChecking() async {
        // Load a vocoder model
        let modelPath = "/path/to/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: modelPath, modelType: .vocoder)
        XCTAssertTrue(loadResult, "Loading model should succeed with simulation enabled")

        // Test with wrong model type
        let result1 = await modelInference.processVoiceConversion(
            melSpectrogram: createTestMelSpectrogram(frames: 10, bands: 40))
        XCTAssertNil(
            result1,
            "Voice conversion should fail with wrong model type (expected converter, got vocoder)")

        // Test with correct model type
        let result2 = await modelInference.generateAudio(
            melSpectrogram: createTestMelSpectrogram(frames: 10, bands: 40))
        XCTAssertNotNil(
            result2, "Audio generation should succeed with correct model type (vocoder)")
    }

    // MARK: - Helper methods

    private func createTestMelSpectrogram(frames: Int, bands: Int) -> [[Float]] {
        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: bands), count: frames)
        for i in 0..<frames {
            for j in 0..<bands {
                melSpectrogram[i][j] = Float.random(in: 0.0...1.0)
            }
        }
        return melSpectrogram
    }

    private func createTestAudioSamples(length: Int) -> [Float] {
        var samples = [Float](repeating: 0.0, count: length)
        for i in 0..<length {
            samples[i] = sin(2.0 * Float.pi * 440.0 * Float(i) / 16000.0)
        }
        return samples
    }
}
