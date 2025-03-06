# Plan

## 🚀 **Step 1: Define the Core Pipeline**

Clearly define which scenario you’re targeting first:

- **Live voice conversion**: Transform a user’s live voice in real-time (e.g., during Discord calls).
- **Text-to-speech (TTS)**: Input text and generate cloned character speech in real-time.

_For Discord voice calls (e.g., voice imitation of Uncle Iroh), you'd typically focus initially on live **voice conversion** (microphone input → cloned voice output)._

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

**Goal:** Compute efficient audio features required by your voice cloning model (e.g., Mel Spectrograms) from raw audio buffers.

### Tasks:

- Leverage **Accelerate (vDSP)** for real-time FFT and Mel-spectrogram computations:
  - Compute spectrograms from audio frames using `vDSP.FFT`.
  - Ensure these computations run comfortably under your audio callback interval (~10 ms).

**Tools & Libraries:**

- Accelerate Framework (`vDSP_fft_zrip`, `vDSP_mmul`)
- Swift wrappers (SwiftAccelerate) for convenience

---

## 🤖 **Step 4: Select and Prototype Your ML Model**

Choose a voice cloning pipeline:

- **Option A (Proven, moderate complexity):**

  - Speaker Encoder (e.g., GE2E from SV2TTS)
  - FastSpeech 2 (text → spectrogram or audio features)
  - HiFi-GAN vocoder (spectrogram → waveform)

- **Option B (simpler, ultra-fast):**
  - RAVE or LPCNet for waveform synthesis (fewer parameters, higher speed but moderate quality).

### Practical Recommendation:

- Begin with **FastSpeech 2 + HiFi-GAN** to balance high quality and fast inference.
- Optionally integrate a GE2E-like **speaker encoder** for zero-shot voice adaptation.

---

## 🛠 **Step 4b: Port & Optimize Models for Core ML**

**Goal:** Convert chosen models to native Core ML format for GPU/ANE execution.

### Tasks:

- Train or obtain pre-trained FastSpeech 2 and HiFi-GAN models (PyTorch).
- Convert models using **`coremltools`**.
- Quantize models to 16-bit precision for Neural Engine efficiency.

**Tools:**

- `coremltools` (Apple’s official Core ML model converter)
- PyTorch or TensorFlow for model training or obtaining checkpoints from open projects (Coqui, RTVC, etc.)

---

## 🎯 **Step 4: Implement Model Inference Pipeline**

### Goal:

Integrate your converted Core ML models into a Swift pipeline.

### Tasks:

- Load Core ML models (`.mlmodel`) in Swift.
- Integrate inference into your audio callback pipeline (or a dedicated background thread, communicating via ring buffer).

**Tips for Real-time:**

- Perform neural inference asynchronously on GPU/Neural Engine.
- Pre-allocate buffers, ensure zero heap allocations during real-time execution.
- Measure inference latency (target < 30 ms per buffer).

**Tools:**

- Core ML Swift APIs (`MLModel.prediction(input:)`)

---

## 🛠 **Step 4a: Filling Gaps – Custom Layers**

If Core ML doesn't directly support certain operations (e.g., custom upsampling in HiFi-GAN):

- Implement missing layers as **custom Core ML layers** using Metal shaders (`MetalPerformanceShaders`).
- Directly use `MPSGraph` if greater GPU flexibility is required.

This is your primary custom development area—anticipate writing Metal shaders and custom Swift layers.

---

## 🎛️ **Step 4: Performance Tuning & Optimization**

### Benchmark & Profile:

- Measure end-to-end latency (microphone input → neural inference → audio output).
- Profile using Apple’s **Instruments app** (CPU/GPU/ANE usage).
- Tune buffer sizes, model complexity, and precision to meet your latency target (~under 100 ms round-trip latency).

**Key metrics:**

- **Real-time factor (RTF)**: aim below 0.2 for comfort.
- CPU/GPU usage: ensure neural inference fits comfortably within GPU/ANE performance envelope.

---

## 📊 **Step 5: Voice Adaptation (Speaker Embedding)**

To achieve zero-shot cloning (like Uncle Iroh’s voice):

- Integrate a speaker encoder (GE2E or similar model).
- Convert speaker embedding network to Core ML (simpler, small model).
- Generate embeddings quickly (sub-50 ms) and pass them to the FastSpeech model as conditional inputs.

---

## 📌 **Step 6: Benchmark, Profile, and Iterate**

### Use Profiling Tools:

- **Xcode Instruments**:
  - “Core ML Instrument” (to verify GPU/ANE usage)
  - “Time Profiler” (to measure bottlenecks in C/Swift code)
  - “Metal System Trace” (GPU profiling)

Iteratively optimize model layers, memory management, and audio buffering based on profiling results.

---

## 📖 **Recommended Ecosystem & Reading:**

### Existing Projects:

- **[Real-Time Voice Cloning (SV2TTS)](https://github.com/CorentinJ/Real-Time-Voice-Cloning)**: Study pipeline and model integration.
- **[Coqui TTS](https://github.com/coqui-ai/TTS)**: Rich collection of trained models (FastSpeech, Tacotron, HiFi-GAN).
- **[Mycroft Mimic 3](https://github.com/MycroftAI/mimic3)**: Excellent reference for minimal-latency implementations.

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

- [Tacotron 2](https://arxiv.org/abs/1712.05884) (Google)
- [FastSpeech 2](https://arxiv.org/abs/2006.04558)
- [VITS](https://arxiv.org/abs/2106.06103)
- [RAVE (Realtime Audio Variational autoEncoder)](https://arxiv.org/abs/2111.05011) for ultra-fast vocoding.

---

## 🤝 **Collaboration Opportunities**:

- Engage with Apple engineers via **Apple Developer Forums** and WWDC labs.
- Collaborate or discuss ideas with communities like **Coqui TTS** and **Mycroft Mimic 3** for insights on native model porting.

---

## 🗓 **Your Immediate Next Actions**:

- **Begin setting up AudioUnit** input/output in Swift.
- Choose a **FastSpeech2 + HiFi-GAN** model combo, convert it to Core ML, and start testing inference performance.
- Prototype a minimal end-to-end pipeline within the next few weeks, then iterate and optimize.

---

By following this roadmap, you'll be able to leverage your M3 Max’s native hardware fully, building a real-time, high-quality voice cloning system completely in C or Swift, optimized for minimal latency and maximum performance.
