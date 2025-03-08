// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "prj-silicon-voice-cloning",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "prj-silicon-voice-cloning",
            targets: ["prj-silicon-voice-cloning"]
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
            name: "prj-silicon-voice-cloning",
            dependencies: ["Audio", "AudioProcessor", "DSP", "ModelInference", "Utilities"]
        ),
        .executableTarget(
            name: "Benchmarks",
            dependencies: ["Audio", "AudioProcessor", "DSP", "ModelInference", "Utilities"]
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
            dependencies: ["Utilities"]
        ),
        .target(
            name: "ModelInference",
            dependencies: ["Utilities"]
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
            dependencies: ["ModelInference"]
        ),
        .testTarget(
            name: "FeatureTests",
            dependencies: [
                "prj-silicon-voice-cloning", "Audio", "AudioProcessor", "DSP", "ModelInference",
                "Utilities",
            ]
        ),
    ]
)
