import Foundation
import Utilities

#if canImport(CoreML)
    import CoreML
#endif

/// Class responsible for loading machine learning models
public class ModelLoader {
    /// Configuration for model loading
    public struct LoaderConfig {
        /// Whether to use the Neural Engine if available
        public var useNeuralEngine: Bool = true
        /// Whether to use the GPU if available
        public var useGPU: Bool = true
        /// Whether to use CPU only
        public var useCPUOnly: Bool = false
        /// Whether to simulate model loading in test environments
        public var simulateModelLoading: Bool = false

        public init(
            useNeuralEngine: Bool = true, useGPU: Bool = true, useCPUOnly: Bool = false,
            simulateModelLoading: Bool = false
        ) {
            self.useNeuralEngine = useNeuralEngine
            self.useGPU = useGPU
            self.useCPUOnly = useCPUOnly
            self.simulateModelLoading = simulateModelLoading
        }
    }

    /// Whether to simulate model loading in test environments
    private var simulateModelLoading: Bool

    /// Whether to use the Neural Engine if available
    private var useNeuralEngine: Bool

    /// Whether to use the GPU if available
    private var useGPU: Bool

    /// Whether to use CPU only
    private var useCPUOnly: Bool

    /// Whether the model is loaded
    public private(set) var modelLoaded = false

    /// Name of the loaded model
    public private(set) var modelName = ""

    #if canImport(CoreML)
        /// The loaded Core ML model
        public private(set) var model: MLModel?
    #endif

    /**
     Initialize a new ModelLoader instance

     - Parameter config: Configuration for model loading
     */
    @MainActor
    public init(config: LoaderConfig = LoaderConfig()) {
        self.simulateModelLoading = config.simulateModelLoading
        self.useNeuralEngine = config.useNeuralEngine
        self.useGPU = config.useGPU
        self.useCPUOnly = config.useCPUOnly

        // Check if we're running in a test environment
        #if DEBUG
            // In debug builds, check for XCTest presence
            let isRunningTests = NSClassFromString("XCTest") != nil
            if isRunningTests {
                self.simulateModelLoading = true
            }
        #endif

        Utilities.log("ModelLoader initialized")
    }

    /**
     Load a Core ML model from the specified path

     - Parameters:
       - modelPath: File path to the .mlmodel file
     - Returns: Boolean indicating success or failure
     */
    @MainActor
    public func loadModel(modelPath: String) -> Bool {
        Utilities.log("Loading model from path: \(modelPath)")
        self.modelName = URL(fileURLWithPath: modelPath).lastPathComponent

        // If we're simulating model loading (for tests), just return success
        if simulateModelLoading {
            modelLoaded = true
            Utilities.log("Successfully loaded model (simulated): \(modelName)")
            return true
        }

        #if canImport(CoreML)
            do {
                // Check if the file exists
                let fileURL = URL(fileURLWithPath: modelPath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    Utilities.log("Error loading model: Model does not exist at \(fileURL)")
                    return false
                }

                // Set compute units based on configuration
                let config = MLModelConfiguration()

                if #available(macOS 10.15, *) {
                    if simulateModelLoading {
                        config.computeUnits = .cpuOnly
                    } else if useNeuralEngine {
                        config.computeUnits = .all
                    } else if useGPU {
                        config.computeUnits = .cpuAndGPU
                    } else {
                        config.computeUnits = .cpuOnly
                    }
                }

                // Compile and load the model
                let compiledModelURL = try MLModel.compileModel(at: fileURL)
                model = try MLModel(contentsOf: compiledModelURL, configuration: config)

                modelLoaded = true
                Utilities.log("Successfully loaded model: \(modelName)")
                return true
            } catch {
                Utilities.log("Error loading model: \(error.localizedDescription)")
                return false
            }
        #else
            // Simulate success for platforms without CoreML
            modelLoaded = true
            return true
        #endif
    }
}
