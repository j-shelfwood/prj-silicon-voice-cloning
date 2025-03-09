// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "prj-silicon-voice-cloning",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "prj-silicon-voice-cloning",
            targets: ["CLI"]
        ),
        .executable(
            name: "benchmarks",
            targets: ["Benchmarks"]
        ),
        .library(
            name: "Audio",
            targets: ["Audio"]
        ),
        .library(
            name: "AudioProcessor",
            targets: ["AudioProcessor"]
        ),
        .library(
            name: "DSP",
            targets: ["DSP"]
        ),
        .library(
            name: "ML",
            targets: ["ML"]
        ),
        .library(
            name: "ModelInference",
            targets: ["ModelInference"]
        ),
        .library(
            name: "Utilities",
            targets: ["Utilities"]
        ),
    ],
    dependencies: [
        // Dependencies will be added here if needed
    ],
    targets: [
        .executableTarget(
            name: "CLI",
            dependencies: ["Audio", "AudioProcessor", "DSP", "ML", "ModelInference", "Utilities"]
        ),
        .executableTarget(
            name: "Benchmarks",
            dependencies: ["Audio", "AudioProcessor", "DSP", "ML", "ModelInference", "Utilities"]
        ),
        .target(
            name: "Audio",
            dependencies: ["Utilities"]
        ),
        .target(
            name: "AudioProcessor",
            dependencies: ["Audio"]
        ),
        .target(
            name: "DSP",
            dependencies: ["Utilities", "AudioProcessor"]
        ),
        .target(
            name: "ML",
            dependencies: ["Utilities", "DSP"]
        ),
        .target(
            name: "ModelInference",
            dependencies: ["Utilities", "ML", "DSP"]
        ),
        .target(
            name: "Utilities",
            dependencies: []
        ),
        // Test targets
        .testTarget(
            name: "AudioTests",
            dependencies: ["Audio"]
        ),
        .testTarget(
            name: "UtilitiesTests",
            dependencies: ["Utilities"]
        ),
        .testTarget(
            name: "DSPTests",
            dependencies: ["DSP"]
        ),
        .testTarget(
            name: "AudioProcessorTests",
            dependencies: ["AudioProcessor"]
        ),
        .testTarget(
            name: "ModelInferenceTests",
            dependencies: ["ModelInference", "ML"]
        ),
        .testTarget(
            name: "FeatureTests",
            dependencies: [
                "CLI", "Audio", "AudioProcessor", "DSP", "ML",
                "ModelInference", "Utilities",
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
