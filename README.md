# Real-Time Voice Cloning on Apple Silicon (M3 Max)

## 🚀 Project Overview

This project aims to build a real-time, low-latency AI voice cloning system optimized for Apple Silicon (e.g., ARM M3 Max). The primary objective is to enable live voice conversion during Discord or other live communication calls—such as replicating character voices (e.g., Uncle Iroh from Avatar)—using native Swift for maximum performance and integration.

## 🎯 Goals

- Achieve sub-100ms total latency for live voice conversion.
- Transform a user's voice into target character voices in real-time during Discord calls.
- Utilize Apple Silicon hardware (CPU, GPU, Neural Engine) efficiently, without performance overhead from Docker, Python runtimes, or virtualization layers.
- Build a foundational understanding of native Apple APIs including Core Audio, Accelerate, and Core ML.

## ⚙️ Technical Approach

The project involves:

- **Core Audio & AudioUnits** for minimal-latency audio input/output.
- **Accelerate Framework (vDSP, BNNS)** for high-performance signal processing and neural computation.
- **Metal and Core ML** for leveraging GPU and Neural Engine acceleration.
- Porting state-of-the-art voice conversion models from Python to native Core ML implementations.
- A carefully designed data pipeline to ensure real-time processing with deterministic latency.
- Audio routing to capture microphone input and feed processed audio to communication apps.

## 📦 Project Structure

```bash
.
├── Package.swift
└── Sources/
    ├── CLI/                        # Command-line interface implementation
    ├── Audio/                      # Core Audio handling (input/output)
    ├── AudioProcessor/             # Audio processing implementation
    ├── DSP/                        # Signal processing via Accelerate (FFT, Mel-spectrogram)
    ├── ML/                         # Machine learning utilities
    ├── ModelInference/             # Core ML model integration and inference
    ├── Benchmarks/                 # Performance benchmarking utility
    ├── Utilities/                  # Helper utilities and performance profiling tools
    └── prj-silicon-voice-cloning/  # Main executable entry point
```

## 🚧 Development Plan

1. **Core Audio CLI Implementation:** Establish basic audio I/O via AudioUnits.
2. **Real-Time DSP**: Implement real-time FFT and audio transformations using Accelerate framework.
3. **Core ML Integration**: Load and run machine learning models for voice conversion using Swift.
4. **Voice Conversion Pipeline**: Integrate speaker embedding models and voice conversion models.
5. **Audio Routing**: Set up proper routing to capture and output audio for Discord integration.
6. **Performance Tuning**: Optimize for ultra-low latency, benchmark performance, and refine implementation iteratively.

## 📌 Technologies & Tools

- Swift (for native integration and rapid development)
- Core Audio and AudioUnits for audio streaming
- Accelerate Framework (vDSP, BNNS Graph)
- Core ML & Metal APIs for on-device neural inference acceleration
- Git and CLI workflows for streamlined development (minimal Xcode UI dependency)

## 🛠 Setup

```bash
# Clone repository
git clone https://github.com/yourusername/real-time-voice-cloning.git
cd real-time-voice-cloning

# Build the project
swift build

# Run the application with help command to see available options
swift run prj-silicon-voice-cloning help

# Run tests
swift test

# Run benchmarks
swift run benchmarks
```

## 📋 Available Commands

The CLI provides several commands for testing and using the voice cloning system:

```bash
# Show help information
swift run prj-silicon-voice-cloning help

# Test audio output with a sine wave
swift run prj-silicon-voice-cloning test-audio

# Test microphone to speaker pass-through
swift run prj-silicon-voice-cloning test-passthrough

# Measure audio processing latency
swift run prj-silicon-voice-cloning test-latency

# Test DSP functionality with live audio
swift run prj-silicon-voice-cloning test-dsp

# Test ML capabilities
swift run prj-silicon-voice-cloning test-ml

# Test minimal end-to-end pipeline
swift run prj-silicon-voice-cloning test-pipeline

# Record a target voice for cloning
swift run prj-silicon-voice-cloning record-target-voice

# Test voice cloning with live audio
swift run prj-silicon-voice-cloning test-voice-cloning

# Clone voice from audio files
swift run prj-silicon-voice-cloning clone-from-file --target-voice <target.wav> --source-voice <source.wav> --output <output.wav>
```

## 🗓 Roadmap

| Milestone                           | Status    |
| ----------------------------------- | --------- |
| Swift + Core Audio Fundamentals     | Completed |
| DSP with Accelerate (FFT)           | Completed |
| Core ML Model Integration           | Completed |
| Logging System Implementation       | Completed |
| Voice Conversion Pipeline           | In Progress |
| Audio Routing for Discord           | Planned   |
| Optimization and Profiling          | Ongoing   |

## 📖 Additional Resources

- [Swift Language Guide](https://docs.swift.org/swift-book/)
- [Core Audio Documentation](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- [Core ML Guide](https://developer.apple.com/documentation/coreml)
- [Accelerate Framework Documentation](https://developer.apple.com/documentation/accelerate)

## 📈 Contributions

Contributions, suggestions, and optimizations are welcome! Feel free to open issues or pull requests.

---

Built with ❤️ for speed, performance, and Apple Silicon native power.

## 🧪 Testing & Benchmarking

### Testing

This project follows a strict separation between functional tests and performance benchmarks:

- **Test Suite**: Focuses exclusively on functional correctness, not performance
  - Run with `swift test`
  - Should complete quickly and reliably
  - No performance assertions or timing-dependent tests

### Benchmarking

A dedicated benchmarking utility is provided for performance measurement:

- **Benchmark Utility**: Comprehensive performance measurement tool
  - Run with `swift run benchmarks [options]`
  - Provides detailed statistics (average, standard deviation)
  - Supports customization via command-line arguments

#### Benchmark Options

```bash
# Run all benchmarks with default settings
swift run benchmarks

# Run only critical path benchmarks
swift run benchmarks --category critical

# Customize iterations and warmup runs
swift run benchmarks --iterations 10 --warmup 3

# Customize audio parameters
swift run benchmarks --audio-length 10.0 --fft-size 2048 --hop-size 512
```

#### Developer Guidelines

- Always use the benchmarking utility for performance measurements
- Never add performance-related tests to the main test suite
- Run benchmarks before and after optimization changes
- Include benchmark results when submitting performance-related PRs

## 📝 Logging System

The project includes a comprehensive logging system with configurable log levels:

- **DEBUG**: Detailed information for development and troubleshooting
- **INFO**: General operational information
- **WARNING**: Potential issues that don't prevent execution
- **ERROR**: Critical issues that may cause failures

Log levels can be configured in code:

```swift
// Set the current log level
LoggerUtility.currentLogLevel = .debug  // Show all logs including debug
LoggerUtility.currentLogLevel = .info   // Show only info, warning, and error logs
```

The logging system provides:
- Timestamp formatting for all log messages
- Thread-safe logging operations
- Consistent output formatting
- Clear separation between library code and user interface
