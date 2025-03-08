# Plan

## 🚀 **Step 1: Define the Core Pipeline**

We have decided to focus on:

- **Live voice conversion**: Transform a user's live voice in real-time during Discord calls
- Target use case: Voice imitation of character voices (e.g., Uncle Iroh from Avatar)

_This approach focuses on converting the user's voice characteristics while preserving the speech content, rather than generating speech from text._

---

## 🔧 **Step 2: Set Up Native Audio Processing**

**Goal:** Achieve real-time audio input and output with minimal latency.

### Tasks:

- **Implement AudioUnit Callback** in Swift or Objective-C:

  - Capture microphone input via Core Audio (AudioUnits).
  - Output audio buffer back via a Core Audio render callback.
  - Benchmark buffer sizes: start with 128 or 256-frame buffers (approx. 2–5ms latency).

- Test this pipeline:
  - Initially pass-through (no processing).
  - Verify latency (should target < 10 ms at this stage).

**Recommended APIs:**

- Core Audio: `AudioUnitRender`, `AURenderCallbackStruct`
- AVFoundation: `AVAudioEngine` (higher-level, slightly higher latency than pure AudioUnits)

---

## 📐 **Step 3: Implement Audio Feature Extraction**

**Goal:** Compute efficient audio features required by your voice conversion model (e.g., Mel Spectrograms) from raw audio buffers.

### Tasks:

- Leverage **Accelerate (vDSP)** for real-time FFT and Mel-spectrogram computations:
  - Compute spectrograms from audio frames using `vDSP.FFT`.
  - Ensure these computations run comfortably under your audio callback interval (~10 ms).

**Tools & Libraries:**

- Accelerate Framework (`vDSP_fft_zrip`, `vDSP_mmul`)
- Swift wrappers (SwiftAccelerate) for convenience

---

## 🤖 **Step 4: Select and Prototype Your ML Model**

Choose a voice conversion pipeline:

- **Option A (Voice Conversion with encoder-decoder):**

  - Speaker Encoder to extract voice characteristics
  - Voice Conversion model (e.g., AutoVC, FragmentVC)
  - Vocoder (e.g., HiFi-GAN) to generate output waveform

- **Option B (Direct waveform modeling):**
  - RAVE or similar models for direct waveform transformation
  - Fewer parameters, higher speed but potentially moderate quality

### Practical Recommendation:

- Begin with an **encoder-decoder + vocoder** approach for better voice quality
- Use pre-trained models as much as possible, focusing on porting to Core ML

---

## 🛠 **Step 5: Port & Optimize Models for Core ML**

**Goal:** Convert chosen models to native Core ML format for GPU/ANE execution.

### Tasks:

- Convert voice conversion models from PyTorch/TensorFlow to Core ML using `coremltools`
- Quantize models to 16-bit precision for Neural Engine efficiency
- Optimize model architecture for lowest possible latency

**Tools:**

- `coremltools` (Apple's official Core ML model converter)
- PyTorch or TensorFlow for model training or obtaining checkpoints

---

## 🎯 **Step 6: Implement Model Inference Pipeline**

### Goal:

Integrate your converted Core ML models into a Swift pipeline.

### Tasks:

- Load Core ML models (`.mlmodel`) in Swift
- Integrate inference into your audio callback pipeline (or a dedicated background thread, communicating via ring buffer)
- Implement a processing chain: audio input → feature extraction → voice conversion → audio output

**Tips for Real-time:**

- Perform neural inference asynchronously on GPU/Neural Engine
- Pre-allocate buffers, ensure zero heap allocations during real-time execution
- Measure inference latency (target < 30 ms per buffer)

**Tools:**

- Core ML Swift APIs (`MLModel.prediction(input:)`)

---

## 🎛️ **Step 7: Audio Routing for Discord**

### Goal:

Enable capturing processed audio into Discord calls.

### Tasks:

- Research options for creating virtual audio devices or routing audio
- Implement audio routing for Discord integration
- Test end-to-end pipeline with actual Discord calls

**Potential approaches:**

- BlackHole or similar virtual audio device
- Custom audio routing using Audio HAL
- Integration with existing audio management tools

---

## 🎛️ **Step 8: Performance Tuning & Optimization**

### Benchmark & Profile:

- Measure end-to-end latency (microphone input → neural inference → audio output → Discord)
- Profile using Apple's **Instruments app** (CPU/GPU/ANE usage)
- Tune buffer sizes, model complexity, and precision to meet your latency target (~under 100 ms round-trip latency)

**Key metrics:**

- **Real-time factor (RTF)**: aim below 0.2 for comfort
- CPU/GPU usage: ensure neural inference fits comfortably within GPU/ANE performance envelope

---

## 📊 **Step 9: Voice Adaptation (Adding More Voices)**

To expand the system's capabilities:

- Implement a voice database with multiple character voices
- Create a UI for selecting different target voices
- Add the ability to record and add new target voices

---

## 📌 **Step 10: Benchmark, Profile, and Iterate**

### Use Profiling Tools:

- **Xcode Instruments**:
  - "Core ML Instrument" (to verify GPU/ANE usage)
  - "Time Profiler" (to measure bottlenecks in C/Swift code)
  - "Metal System Trace" (GPU profiling)

Iteratively optimize model layers, memory management, and audio buffering based on profiling results.

---

## 📖 **Recommended Ecosystem & Reading:**

### Existing Projects:

- **[AutoVC](https://github.com/auspicious3000/autovc)**: Zero-shot voice conversion
- **[FragmentVC](https://github.com/hhguo/FragmentVC)**: Low-latency voice conversion
- **[RAVE](https://github.com/acids-ircam/RAVE)**: Fast neural audio synthesis
- **[CoreML-Models](https://github.com/john-rocky/CoreML-Models)**: Examples of converted ML models

### Relevant Documentation:

- [Apple Accelerate Documentation](https://developer.apple.com/documentation/accelerate)
- [Core Audio Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- [Core ML Optimization Techniques](https://developer.apple.com/documentation/coreml)
- [Metal Performance Shaders (MPS)](https://developer.apple.com/documentation/metalperformanceshaders)

### WWDC Sessions (Critical):

- **[Deploy machine learning and AI models on-device with Core ML](https://developer.apple.com/wwdc24/)**
- **[Bring your ML models to Apple Silicon](https://developer.apple.com/wwdc24/)**
- **[Support real-time ML inference on the CPU (BNNS Graph)](https://developer.apple.com/videos/)**
- **[Optimizing Audio Units](https://developer.apple.com/videos/play/wwdc2023/)** (for detailed guidance on audio latency management)

---

## 📖 **Recommended Papers for Deep Understanding**:

- [AutoVC: Zero-Shot Voice Style Transfer with Only Autoencoder Loss](https://arxiv.org/abs/1905.05879)
- [FragmentVC: Any-to-Any Voice Conversion by Fragment-wise Acoustic and Phonetic Information](https://arxiv.org/abs/2010.14150)
- [RAVE (Realtime Audio Variational autoEncoder)](https://arxiv.org/abs/2111.05011) for ultra-fast conversion

---

## 🗓 **Your Immediate Next Actions**:

- **Begin setting up AudioUnit** input/output in Swift
- Research and select voice conversion models appropriate for real-time use
- Prototype a minimal end-to-end pipeline within the next few weeks, then iterate and optimize

---

By following this roadmap, you'll be able to leverage your M3 Max's native hardware fully, building a real-time, high-quality voice conversion system completely in C or Swift, optimized for minimal latency and maximum performance.
