# Development Log: Real-Time Voice Cloning on Apple Silicon

This document serves as an ongoing development log for our Real-Time Voice Cloning project, tracking progress, technical discoveries, and important decisions. Each entry will include technical details about Swift, Core Audio, ML implementation, and our progress toward the overall goal of sub-100ms voice cloning.

## 2025-03-06: Project Setup and Initial Structure

### Progress Summary

- Set up Swift package with proper modular structure
- Created placeholder implementations for core components
- Successfully built and ran basic CLI with test commands
- Established project architecture following best practices

### Technical Details & Learnings

#### Swift Package Manager

- Swift 6.0 syntax requires careful type handling (e.g., `vDSP_Length` vs `Int` in FFT setup)
- Package dependencies between modules need explicit declaration in Package.swift
- Target directory structure must match the naming convention (e.g., `Sources/target-name/`)
- Swift concurrency requires proper actor isolation (`@MainActor` for shared mutable state)

#### Architecture Notes

- Created modular approach with clear separation of concerns:
  - `AudioProcessor`: Core Audio handling
  - `DSP`: Signal processing via Accelerate framework
  - `ModelInference`: Core ML integration
  - `Utilities`: Helper functions and timing tools
- Both microphone capture and audio playback will be handled by AudioUnits for minimal latency

#### Core Audio & DSP Notes

- FFT setup in Accelerate framework requires proper log2n calculation
- Performance is critical - we need to keep all DSP operations under ~10ms
- Will need proper buffer management between audio callback and processing threads

#### ML Integration Notes

- Core ML availability needs to be checked at runtime
- We'll need to measure inference times for both CPU and Neural Engine execution
- Model quantization will likely be necessary to meet real-time requirements

### Next Steps

- Implement actual AudioUnit for real-time audio I/O
- Complete FFT implementation with proper vDSP usage
- Begin investigating FastSpeech 2 and HiFi-GAN model conversion

### Open Questions

- What buffer size will give the best latency/stability tradeoff? (Initial target: 256 samples)
- Will we need a custom ring buffer implementation for thread communication?
- Can we achieve <100ms latency with full neural processing pipeline?

---

## 2025-03-06: Pipeline Decision - Focus on Voice Conversion

### Decision Summary

- **Chosen approach**: Live voice conversion for Discord calls
- **Target use case**: Transform user's voice to character voices (e.g., Uncle Iroh) in real-time
- **Not pursuing**: Text-to-speech approach (may revisit later)

### Technical Implications

#### Pipeline Architecture

- Input: Live microphone audio from user
- Processing: Convert voice characteristics while preserving speech content
- Output: Transformed audio to Discord or other communication apps
- Target latency: <100ms end-to-end to maintain conversation flow

#### Components Affected

- **AudioProcessor**: Must capture system audio or microphone and route output to virtual device
- **DSP**: Focus on efficient feature extraction optimized for voice characteristics
- **ML Models**: Need speaker encoding and voice conversion models rather than TTS
- **Output Handling**: May need virtual audio device or audio routing system for Discord integration

### Next Steps (Revised)

1. Implement AudioUnit for real-time input/output with focus on capturing microphone
2. Research voice conversion models that balance quality and speed
3. Investigate audio routing options to feed processed audio to Discord
4. Begin work on feature extraction (mel-spectrograms) optimized for voice characteristics

### Open Questions

- Which voice conversion model architecture will best balance quality and speed?
- How will we handle audio device routing to feed into Discord?
- Will we need custom virtual audio device drivers?

---

## 2025-03-06: Real-Time Audio Processing Implementation

### Progress Summary

- Implemented real AudioUnit functionality for microphone input and audio output
- Created a complete audio processing pipeline with callbacks for real-time audio processing
- Added audio pass-through, latency testing, and DSP integration to the CLI interface
- Implemented thread-safe audio buffer handling and latency measurement

### Technical Details & Learnings

#### Core Audio Implementation

- Used `AudioComponentFindNext` and `AudioComponentInstanceNew` to create input/output AudioUnits
- Set up HAL I/O for microphone input and DefaultOutput for speakers
- Implemented render callbacks for both input and output processing
- Buffer management is critical - used `NSLock` for thread-safe access to shared audio buffers
- Created a processing chain: input callback → buffer → processing callback → output callback

#### Swift and Audio Memory Management

- Swift concurrency warnings around static mutable variables required adjustment:
  - Replaced static `let asbd` with a function that creates a new ASBD when needed
  - Used explicit locks to ensure thread safety with shared audio buffers
- Memory management for audio data in C-style callbacks is tricky:
  - Had to manually allocate and deallocate memory for the audio buffer in the callback
  - Used `UnsafeMutablePointer<Float>` and `UnsafeBufferPointer` for efficient audio data handling

#### Audio Pipeline Customization

- Added a customizable audio processing callback to allow for flexible audio transformations
- Implemented both streaming (real-time) mode and one-shot playback mode for testing
- Frame size set to 512 samples (~11.6ms at 44.1kHz) for a good latency/stability balance
- Used mono audio format (single channel) with 32-bit float samples for simplicity and quality

### Next Steps

1. Implement real-time FFT and spectral processing in the DSP module
2. Create a more sophisticated audio buffer management system for handling variable-sized frames
3. Begin researching and implementing voice conversion models suitable for real-time use
4. Test latency in real-world scenarios to ensure we meet our <100ms target

### Open Questions

- How to optimize the audio pipeline for minimum latency while maintaining stability?
- What's the optimal buffer size for our voice conversion application?
- Do we need to implement a more sophisticated ring buffer for audio data?
- How can we route the processed audio to Discord without excessive additional latency?

---

## 2025-03-07: Test Infrastructure and Mocking Implementation

### Progress Summary

- Implemented a protocol-based mocking system for audio processing
- Created a comprehensive test suite that doesn't require actual audio hardware
- Added ModelInferenceTests target to the package
- Fixed access level issues for proper protocol conformance

### Technical Details & Learnings

#### Protocol-Based Mocking

- Created `AudioProcessorProtocol` to define the interface for audio processing components
- Implemented `MockAudioProcessor` that simulates audio operations without hardware access
- Used dependency injection to allow tests to run with either real or mock implementations
- Added configuration options to simulate different failure scenarios for robust testing

#### Swift Access Control

- Adjusted access levels for AudioProcessor properties to support protocol conformance:
  - Changed `isRunning` from `private` to `public private(set)` to allow read-only access
  - Made internal properties accessible to tests with `@testable import`
  - Used explicit type casting for nil assignments in tearDown methods

#### Test Infrastructure

- Added a flag `useRealAudioHardware` to control whether tests use real or mock implementations
- Created tests that verify both basic functionality and edge cases
- Implemented specific tests for mock configuration failures
- Ensured all tests can run in CI environments without audio hardware

#### Benefits Observed

- Tests no longer play actual sounds or request microphone permissions
- Test suite runs faster without audio hardware initialization
- More reliable testing in CI environments
- Better isolation of components for unit testing

### Next Steps

1. Extend mocking approach to other hardware-dependent components
2. Implement more comprehensive tests for the audio processing pipeline
3. Add performance benchmarks for critical audio processing operations
4. Continue with real-time FFT and spectral processing implementation

### Challenges & Solutions

- Protocol conformance issues: Solved by adjusting access levels and adding proper property attributes
- Test isolation: Addressed by creating a configurable mock implementation
- CI compatibility: Ensured tests can run without audio hardware by defaulting to mock implementation

---

## 2025-03-07: DSP Implementation with Accelerate Framework

### Progress Summary

- Implemented real FFT functionality using Apple's Accelerate framework
- Added proper spectrogram and mel-spectrogram generation
- Created comprehensive test suite for DSP operations
- Optimized memory management for real-time performance

### Technical Details & Learnings

#### Accelerate Framework Integration

- Used `vDSP.FFT` for efficient Fast Fourier Transform operations
- Implemented proper windowing with Hann window to reduce spectral leakage
- Created safe memory management with `withUnsafeMutableBufferPointer` for C interoperability
- Achieved excellent performance: FFT processing in microseconds, spectrogram generation in ~6ms

#### Swift Memory Management

- Swift's memory safety features required careful handling of unsafe pointers:
  - Used `withUnsafeMutableBufferPointer` to safely work with C APIs
  - Properly managed memory allocation and deallocation in FFT operations
  - Created safe abstractions around low-level vDSP functions
- Learned that Swift 6.0 has stricter requirements for pointer handling

#### DSP Algorithm Implementation

- Implemented complete audio processing pipeline:
  - FFT with proper windowing and scaling
  - Spectrogram generation with overlapping frames
  - Mel-spectrogram conversion using filterbank matrix
- Added robust error handling for edge cases:
  - Input buffers smaller than FFT size
  - Empty spectrograms
  - Buffer boundary handling

#### Performance Optimization

- Measured performance of critical operations:
  - FFT: ~0.0001 seconds per frame
  - Spectrogram generation: ~0.006 seconds for 5 seconds of audio
  - Mel-spectrogram conversion: ~0.028 seconds for full spectrogram
- These performance metrics confirm we can achieve real-time processing

### Next Steps

1. Implement the mel-filterbank creation function with proper frequency scaling
2. Connect DSP module with ModelInference for complete voice conversion pipeline
3. Optimize for real-time performance, potentially using Metal for GPU acceleration
4. Implement voice conversion models that work with our mel-spectrograms

### Challenges & Solutions

- Memory management issues: Solved with proper use of Swift's pointer APIs
- Module accessibility: Fixed by making AudioFormatSettings public
- Performance concerns: Addressed through careful optimization and benchmarking
- Edge cases: Added robust error handling for various input conditions

---

## 2025-03-07: ModelInference Implementation and Swift Concurrency

### Progress Summary

- Implemented the ModelInference module with Core ML integration
- Added support for different model types (speaker encoder, voice converter, vocoder)
- Fixed actor isolation issues with Swift concurrency
- Enhanced test infrastructure with simulation capabilities

### Technical Details & Learnings

#### Swift Concurrency and Actor Isolation

- Encountered actor isolation issues with timer functions:
  - `Utilities.startTimer()` and `Utilities.endTimer()` were marked with `@MainActor`
  - These functions were being called from synchronous contexts in ModelInference
- Solved by implementing proper async/await pattern:
  - Made inference methods async (`runInference`, `processVoiceConversion`, etc.)
  - Used `await` when calling MainActor-isolated timer functions
  - Updated tests to use async/await pattern with the new method signatures

#### Test Environment Simulation

- Created a robust test environment for ML models:
  - Added `simulateModelLoading` flag to `InferenceConfig` to enable testing without real models
  - Implemented automatic test detection using `NSClassFromString("XCTest")`
  - Enhanced model loading to handle non-existent paths in test environments
  - Added proper file existence checking for real environments
- This approach allows tests to run in CI environments without requiring actual model files

#### Core ML Integration

- Implemented model loading with configurable compute units:
  - Neural Engine for maximum performance on Apple Silicon
  - GPU for older devices or when Neural Engine is unavailable
  - CPU-only option for debugging or compatibility
- Added performance metrics tracking:
  - Inference time in milliseconds
  - Frames processed count
  - Real-time factor calculation (processing time / audio duration)

#### Voice Conversion Pipeline

- Created a complete voice conversion pipeline:
  - Speaker encoder for extracting voice characteristics
  - Voice converter for transforming mel-spectrograms
  - Vocoder for generating audio from mel-spectrograms
- Implemented type checking to ensure models are used correctly
- Added placeholder implementations that will be replaced with actual model inference

### Next Steps

1. Implement actual model inference with Core ML
2. Connect DSP module with ModelInference for end-to-end voice conversion
3. Optimize inference for real-time performance
4. Measure and optimize latency in the complete pipeline

### Challenges & Solutions

- Actor isolation issues: Solved by implementing proper async/await pattern
- Test environment challenges: Addressed with simulation capabilities
- Model type safety: Implemented with enum-based type checking
- Performance concerns: Added comprehensive metrics tracking

---

## 2025-03-08: Architectural Refactoring Plan

### Progress Summary

- Received and analyzed comprehensive refactoring proposal
- Identified key areas for modularization and separation of concerns
- Planned gradual migration strategy to maintain stability
- Established new directory structure and module organization

### Technical Details & Learnings

#### Audio Processing Layer Refactoring

- Current monolithic `AudioProcessor` to be split into:
  - `AudioUnitManager`: Core AudioUnit configuration and management
  - `AudioInputProcessor`: Input capture and buffering
  - `AudioOutputProcessor`: Output playback and processing
  - `RealTimeAudioPipeline`: Coordination and flow management
- Benefits:
  - Better separation of concerns
  - Easier testing and optimization
  - Clearer audio flow management
  - Improved error handling and recovery

#### DSP Layer Modularization

- Current `DSP` class to be divided into:
  - `FFTProcessor`: Isolated FFT and windowing operations
  - `SpectrogramGenerator`: Spectrogram computation
  - `MelSpectrogramConverter`: Mel-scale conversion
  - `StreamingMelProcessor`: Real-time processing coordination
- Benefits:
  - Isolated DSP algorithms for better testing
  - Clearer transformation pipeline
  - Easier optimization of individual components
  - Better separation of streaming vs. batch processing

#### Model Inference Restructuring

- Current `ModelInference` to be split into:
  - `ModelLoader`: File I/O and model configuration
  - `ModelRunner` protocol hierarchy: Specialized runners for each model type
  - `PerformanceTracker`: Isolated metrics and monitoring
- Benefits:
  - Clear separation of model loading and inference
  - Protocol-based design for better extensibility
  - Isolated performance monitoring
  - Easier testing and mocking

#### Utilities and CLI Enhancement

- Reorganizing utilities into focused modules:
  - `TimerUtility`: Performance timing
  - `LoggerUtility`: Structured logging
  - `AudioSignalUtility`: Test signal generation
- New `CommandRouter` for CLI organization
- Benefits:
  - Better organized utility functions
  - Improved CLI interface
  - Enhanced testing capabilities

### Implementation Strategy

1. **Phase 1: Foundation**
   - Set up new directory structure
   - Create new module interfaces
   - Implement basic tests for new structure

2. **Phase 2: Audio Layer**
   - Implement `AudioUnitManager`
   - Split input/output processing
   - Create pipeline coordinator
   - Migrate existing functionality

3. **Phase 3: DSP Layer**
   - Implement FFT isolation
   - Create spectrogram modules
   - Set up streaming processor
   - Validate performance

4. **Phase 4: ML Layer**
   - Implement model loading separation
   - Create model runner protocols
   - Set up performance tracking
   - Migrate existing models

5. **Phase 5: Utilities & CLI**
   - Split utility functions
   - Implement command router
   - Update documentation
   - Complete test coverage

### Next Steps

1. Create new directory structure and placeholder files
2. Begin with `AudioUnitManager` implementation
3. Set up CI/CD pipeline for new structure
4. Start gradual migration of existing functionality

### Challenges & Considerations

- Maintaining real-time performance during refactoring
- Ensuring backward compatibility during migration
- Managing increased complexity of more modules
- Balancing separation of concerns with practical integration
- Testing strategy for new modular structure

---

<!-- Template for future entries -->
<!--
## YYYY-MM-DD: [Summary Title]

### Progress Summary
- Key progress point 1
- Key progress point 2

### Technical Details & Learnings

#### [Category]
- Technical point 1
- Technical point 2

### Next Steps
- Next step 1
- Next step 2

### Challenges & Solutions
- Challenge 1: Solution 1
- Challenge 2: Solution 2
-->
