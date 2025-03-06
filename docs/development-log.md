# Development Log: Real-Time Voice Cloning on Apple Silicon

This document serves as an ongoing development log for our Real-Time Voice Cloning project, tracking progress, technical discoveries, and important decisions. Each entry will include technical details about Swift, Core Audio, ML implementation, and our progress toward the overall goal of sub-100ms voice cloning.

## 2024-03-06: Project Setup and Initial Structure

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

## 2024-03-06: Pipeline Decision - Focus on Voice Conversion

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
