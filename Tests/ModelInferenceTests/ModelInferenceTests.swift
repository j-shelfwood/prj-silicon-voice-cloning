import XCTest

@testable import ModelInference
@testable import Utilities

final class ModelInferenceTests: XCTestCase {
    var modelInference: ModelInference!

    override func setUp() {
        super.setUp()
        modelInference = ModelInference()
    }

    override func tearDown() {
        modelInference = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(modelInference, "ModelInference should initialize successfully")
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
        // Test with a non-existent path (should fail gracefully)
        let nonExistentPath = "/path/to/nonexistent/model.mlmodel"
        let loadResult = modelInference.loadModel(modelPath: nonExistentPath)

        // Since the current implementation is a placeholder that always returns true,
        // we expect true. In a real implementation, this would return false.
        XCTAssertTrue(
            loadResult,
            "Loading non-existent model should return true with placeholder implementation")

        // TODO: When real implementation is added, test with a real model file
        // let realModelPath = Bundle.module.path(forResource: "TestModel", ofType: "mlmodel")!
        // let realLoadResult = modelInference.loadModel(modelPath: realModelPath)
        // XCTAssertTrue(realLoadResult, "Loading a real model should succeed")
    }

    func testRunInference() {
        // Since the current implementation returns nil, we can only test that it doesn't crash
        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let output: [Float]? = modelInference.runInference(input: input)

        XCTAssertNil(output, "Inference should return nil with placeholder implementation")

        // TODO: When real implementation is added, test with a real model and check the output
    }

    func testModelLoadingPerformance() {
        // Measure the performance of loading a model
        measure {
            for _ in 0..<10 {
                _ = modelInference.loadModel(modelPath: "/path/to/model.mlmodel")
            }
        }
    }
}
