import AudioProcessor
import DSP
import Foundation
import ModelInference
import Utilities

// Create a synchronous simulation class for benchmarking
class BenchmarkModelInference {
    // Define model types to match ModelInference
    enum ModelType {
        case speakerEncoder
        case voiceConverter
        case vocoder
    }

    // Simulate model loading
    func loadModel(modelPath: String, modelType: ModelType) -> Bool {
        // Simulate model loading delay
        Thread.sleep(forTimeInterval: 0.01)
        return true
    }

    // Simulate voice conversion synchronously
    func processVoiceConversion(melSpectrogram: [[Float]]) -> [[Float]]? {
        // Simulate processing delay based on input size
        let processingTime = Double(melSpectrogram.count * melSpectrogram[0].count) / 1_000_000.0
        Thread.sleep(forTimeInterval: processingTime)

        // Return simulated result with same dimensions
        return melSpectrogram
    }

    // Simulate audio generation synchronously
    func generateAudio(melSpectrogram: [[Float]]) -> [Float]? {
        // Simulate generation delay based on input size
        let generationTime = Double(melSpectrogram.count * melSpectrogram[0].count) / 500_000.0
        Thread.sleep(forTimeInterval: generationTime)

        // Return simulated audio (1 second per 100 frames)
        let sampleRate: Float = 44100.0
        let audioLength = Int(sampleRate * Float(melSpectrogram.count) / 100.0)
        return [Float](repeating: 0.0, count: max(1000, audioLength))
    }
}

/// A simple benchmarking utility with enhanced reporting
class Benchmark {
    private let name: String
    private var startTime: CFAbsoluteTime = 0
    private var results: [CFAbsoluteTime] = []

    init(name: String) {
        self.name = name
    }

    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
    }

    func stop() {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        results.append(elapsed)
    }

    func run(iterations: Int = 10, warmup: Int = 3, _ operation: () -> Void) {
        print("Running benchmark: \(name)")

        // Warmup runs
        for _ in 0..<warmup {
            operation()
        }

        // Timed runs
        for i in 1...iterations {
            start()
            operation()
            stop()
            print("  Run \(i): \(String(format: "%.6f", results.last!))s")
        }

        // Calculate statistics
        let total = results.reduce(0, +)
        let average = total / Double(results.count)

        let variance = results.map { pow($0 - average, 2) }.reduce(0, +) / Double(results.count)
        let stdDev = sqrt(variance)
        let relativeStdDev = (stdDev / average) * 100

        print("  ┌─────────────────────────────────────────────")
        print("  │ Average: \(String(format: "%.6f", average))s")
        print(
            "  │ Std Dev: \(String(format: "%.6f", stdDev))s (\(String(format: "%.2f", relativeStdDev))%)"
        )
        print("  └─────────────────────────────────────────────")
        print("")

        // Return to baseline memory if possible
        autoreleasepool {}
    }
}

/// Benchmark configuration
struct BenchmarkConfig {
    let iterations: Int
    let warmupIterations: Int
    let audioLength: Float  // in seconds
    let fftSize: Int
    let hopSize: Int
    let melBands: Int
    let sampleRate: Float
    let runCategory: BenchmarkCategory

    enum BenchmarkCategory: String, CaseIterable {
        case all = "all"
        case dsp = "dsp"
        case audio = "audio"
        case model = "model"
        case critical = "critical"
    }

    static let standard = BenchmarkConfig(
        iterations: 10,
        warmupIterations: 3,
        audioLength: 5.0,
        fftSize: 1024,
        hopSize: 256,
        melBands: 80,
        sampleRate: 44100.0,
        runCategory: .all
    )

    static func fromCommandLine() -> BenchmarkConfig {
        let args = CommandLine.arguments

        var iterations = standard.iterations
        var warmup = standard.warmupIterations
        var audioLength = standard.audioLength
        var fftSize = standard.fftSize
        var hopSize = standard.hopSize
        var melBands = standard.melBands
        var sampleRate = standard.sampleRate
        var category = standard.runCategory

        for i in 1..<args.count {
            let arg = args[i]

            if arg == "--iterations" || arg == "-i", i + 1 < args.count {
                iterations = Int(args[i + 1]) ?? iterations
            } else if arg == "--warmup" || arg == "-w", i + 1 < args.count {
                warmup = Int(args[i + 1]) ?? warmup
            } else if arg == "--audio-length" || arg == "-a", i + 1 < args.count {
                audioLength = Float(args[i + 1]) ?? audioLength
            } else if arg == "--fft-size" || arg == "-f", i + 1 < args.count {
                fftSize = Int(args[i + 1]) ?? fftSize
            } else if arg == "--hop-size" || arg == "-h", i + 1 < args.count {
                hopSize = Int(args[i + 1]) ?? hopSize
            } else if arg == "--mel-bands" || arg == "-m", i + 1 < args.count {
                melBands = Int(args[i + 1]) ?? melBands
            } else if arg == "--sample-rate" || arg == "-s", i + 1 < args.count {
                sampleRate = Float(args[i + 1]) ?? sampleRate
            } else if arg == "--category" || arg == "-c", i + 1 < args.count {
                if let cat = BenchmarkCategory(rawValue: args[i + 1].lowercased()) {
                    category = cat
                }
            } else if arg == "--help" {
                printUsage()
                exit(0)
            }
        }

        return BenchmarkConfig(
            iterations: iterations,
            warmupIterations: warmup,
            audioLength: audioLength,
            fftSize: fftSize,
            hopSize: hopSize,
            melBands: melBands,
            sampleRate: sampleRate,
            runCategory: category
        )
    }

    static func printUsage() {
        print(
            """
            Usage: benchmarks [options]

            Options:
              --iterations, -i <num>     Number of benchmark iterations (default: \(standard.iterations))
              --warmup, -w <num>         Number of warmup iterations (default: \(standard.warmupIterations))
              --audio-length, -a <sec>   Length of test audio in seconds (default: \(standard.audioLength))
              --fft-size, -f <size>      FFT size (default: \(standard.fftSize))
              --hop-size, -h <size>      Hop size (default: \(standard.hopSize))
              --mel-bands, -m <bands>    Number of mel bands (default: \(standard.melBands))
              --sample-rate, -s <rate>   Sample rate in Hz (default: \(standard.sampleRate))
              --category, -c <category>  Benchmark category to run (default: \(standard.runCategory.rawValue))
                                         Categories: \(BenchmarkCategory.allCases.map { $0.rawValue }.joined(separator: ", "))
              --help                     Show this help message
            """)
    }
}

/// Run all benchmarks
func runAllBenchmarks(config: BenchmarkConfig = .standard) {
    print("╔═══════════════════════════════════════════════════════════════════════════╗")
    print("║                     Voice Cloning Performance Benchmarks                   ║")
    print("╚═══════════════════════════════════════════════════════════════════════════╝")
    print("Configuration:")
    print("  Iterations: \(config.iterations)")
    print("  Warmup Iterations: \(config.warmupIterations)")
    print("  Audio Length: \(config.audioLength) seconds")
    print("  FFT Size: \(config.fftSize)")
    print("  Hop Size: \(config.hopSize)")
    print("  Mel Bands: \(config.melBands)")
    print("  Sample Rate: \(config.sampleRate) Hz")
    print("  Category: \(config.runCategory.rawValue)")
    print("")

    // Generate test audio
    let sineWave = Utilities.generateSineWave(
        frequency: 440.0,
        sampleRate: config.sampleRate,
        duration: config.audioLength
    )

    // Initialize components
    let dsp = DSP(fftSize: config.fftSize, sampleRate: config.sampleRate)
    let fftProcessor = FFTProcessor(fftSize: config.fftSize)
    let spectrogramGenerator = SpectrogramGenerator(fftSize: config.fftSize)
    let melConverter = MelSpectrogramConverter(
        sampleRate: config.sampleRate,
        melBands: config.melBands,
        minFrequency: 0.0,
        maxFrequency: config.sampleRate / 2.0
    )
    let streamingProcessor = StreamingMelProcessor(
        fftSize: config.fftSize,
        hopSize: config.hopSize,
        sampleRate: config.sampleRate,
        melBands: config.melBands
    )
    let modelInference = ModelInference(
        config: ModelInference.InferenceConfig(simulateModelLoading: true))

    // Run DSP benchmarks
    if [.all, .dsp, .critical].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           DSP BENCHMARKS                                   ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Benchmark 1: Sine Wave Generation
        let sineWaveBenchmark = Benchmark(name: "Sine Wave Generation (10s)")
        sineWaveBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = Utilities.generateSineWave(
                frequency: 440.0,
                sampleRate: config.sampleRate,
                duration: 10.0
            )
        }

        // Benchmark 2: FFT Processing
        let fftBenchmark = Benchmark(name: "FFT Processing")
        fftBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = fftProcessor.performFFT(inputBuffer: sineWave)
        }

        // Benchmark 3: Spectrogram Generation
        let spectrogramBenchmark = Benchmark(name: "Spectrogram Generation")
        spectrogramBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = spectrogramGenerator.generateSpectrogram(
                inputBuffer: sineWave,
                hopSize: config.hopSize
            )
        }

        // Benchmark 4: Parallel Spectrogram Generation
        let parallelSpectrogramBenchmark = Benchmark(name: "Parallel Spectrogram Generation")
        parallelSpectrogramBenchmark.run(
            iterations: config.iterations, warmup: config.warmupIterations
        ) {
            _ = spectrogramGenerator.generateSpectrogramParallel(
                inputBuffer: sineWave,
                hopSize: config.hopSize
            )
        }

        // Generate a spectrogram for the next benchmarks
        let spectrogram = spectrogramGenerator.generateSpectrogram(
            inputBuffer: sineWave,
            hopSize: config.hopSize
        )

        // Benchmark 5: Mel Spectrogram Conversion
        let melSpecBenchmark = Benchmark(name: "Mel Spectrogram Conversion")
        melSpecBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = melConverter.specToMelSpec(spectrogram: spectrogram)
        }

        // Generate a mel spectrogram for the next benchmark
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Benchmark 6: Log Mel Spectrogram Conversion
        let logMelBenchmark = Benchmark(name: "Log Mel Spectrogram Conversion")
        logMelBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = melConverter.melToLogMel(melSpectrogram: melSpectrogram)
        }

        // Benchmark 7: Streaming Mel Processor
        let streamingBenchmark = Benchmark(name: "Streaming Mel Processor")
        streamingBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            streamingProcessor.reset()
            streamingProcessor.addSamples(sineWave)
            _ = streamingProcessor.processMelSpectrogram()
        }

        // Benchmark 8: End-to-End DSP Pipeline
        let endToEndBenchmark = Benchmark(name: "End-to-End DSP Pipeline")
        endToEndBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave)
            let melSpec = dsp.specToMelSpec(spectrogram: spectrogram)
            _ = dsp.melToLogMel(melSpectrogram: melSpec)
        }
    }

    // Run Audio benchmarks
    if [.all, .audio].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           AUDIO BENCHMARKS                                 ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Audio processing benchmarks would go here
        // Since we're using mock audio processor for tests, we'll just add a placeholder
        let audioBenchmark = Benchmark(name: "Audio Processing (Mock)")
        audioBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let processor = MockAudioProcessor()
            _ = processor.startCapture()  // Use the result to avoid warning
            Thread.sleep(forTimeInterval: 0.01)  // Simulate a small amount of processing
            processor.stopCapture()
        }
    }

    // Run Model benchmarks
    if [.all, .model, .critical].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           MODEL BENCHMARKS                                 ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Benchmark 9: Model Loading (simulated)
        let modelLoadingBenchmark = Benchmark(name: "Model Loading (Simulated)")
        modelLoadingBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = modelInference.loadModel(
                modelPath: "/path/to/model.mlmodel",
                modelType: .voiceConverter
            )
        }

        // Create test mel spectrogram for model inference
        let spectrogram = spectrogramGenerator.generateSpectrogram(
            inputBuffer: sineWave,
            hopSize: config.hopSize
        )
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Benchmark 10: Voice Conversion (simulated)
        let voiceConversionBenchmark = Benchmark(name: "Voice Conversion (Simulated)")
        voiceConversionBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations)
        {
            // Create a benchmark simulation instance
            let benchmarkInference = BenchmarkModelInference()
            _ = benchmarkInference.loadModel(
                modelPath: "/path/to/model.mlmodel", modelType: .voiceConverter)

            // Use the synchronous simulation
            _ = benchmarkInference.processVoiceConversion(melSpectrogram: melSpectrogram)
        }

        // Benchmark 11: Audio Generation (simulated)
        let audioGenBenchmark = Benchmark(name: "Audio Generation (Simulated)")
        audioGenBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            // Create a benchmark simulation instance
            let benchmarkInference = BenchmarkModelInference()
            _ = benchmarkInference.loadModel(
                modelPath: "/path/to/model.mlmodel", modelType: .vocoder)

            // Use the synchronous simulation
            _ = benchmarkInference.generateAudio(melSpectrogram: melSpectrogram)
        }
    }

    // Run Critical Path benchmarks
    if [.critical].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                      CRITICAL PATH BENCHMARKS                              ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Benchmark 12: End-to-End Voice Cloning Pipeline (simulated)
        let e2eBenchmark = Benchmark(name: "End-to-End Voice Cloning Pipeline (Simulated)")
        e2eBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            // Create a benchmark simulation instance
            let benchmarkInference = BenchmarkModelInference()
            _ = benchmarkInference.loadModel(
                modelPath: "/path/to/model.mlmodel", modelType: .voiceConverter)
            _ = benchmarkInference.loadModel(
                modelPath: "/path/to/model.mlmodel", modelType: .vocoder)

            // 1. Process audio to mel spectrogram
            let spectrogram = dsp.generateSpectrogram(inputBuffer: sineWave)
            let melSpec = dsp.specToMelSpec(spectrogram: spectrogram)
            let logMelSpec = dsp.melToLogMel(melSpectrogram: melSpec)

            // 2. Run voice conversion (simulated) using synchronous simulation
            if let convertedMel = benchmarkInference.processVoiceConversion(
                melSpectrogram: logMelSpec)
            {
                // 3. Generate audio from converted mel (simulated) using synchronous simulation
                _ = benchmarkInference.generateAudio(melSpectrogram: convertedMel)
            }
        }

        // Benchmark 13: Streaming Voice Conversion (simulated)
        let streamingVCBenchmark = Benchmark(name: "Streaming Voice Conversion (Simulated)")
        streamingVCBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            // Create a benchmark simulation instance
            let benchmarkInference = BenchmarkModelInference()
            _ = benchmarkInference.loadModel(
                modelPath: "/path/to/model.mlmodel", modelType: .voiceConverter)
            _ = benchmarkInference.loadModel(
                modelPath: "/path/to/model.mlmodel", modelType: .vocoder)

            // 1. Reset streaming processor
            streamingProcessor.reset()

            // 2. Process in chunks to simulate streaming
            let chunkSize = 4096
            let chunks = sineWave.count / chunkSize

            for i in 0..<chunks {
                let start = i * chunkSize
                let end = min(start + chunkSize, sineWave.count)
                let chunk = Array(sineWave[start..<end])

                // Add chunk to processor
                streamingProcessor.addSamples(chunk)

                // Process if we have enough frames
                let melSpecResult = streamingProcessor.processMelSpectrogram()

                // Only process if we got actual mel frames
                if !melSpecResult.melFrames.isEmpty {
                    // Convert to log mel - extract just the mel frames from the tuple
                    let logMelSpec = melConverter.melToLogMel(
                        melSpectrogram: melSpecResult.melFrames)

                    // Simulate voice conversion and audio generation using synchronous simulation
                    if let convertedMel = benchmarkInference.processVoiceConversion(
                        melSpectrogram: logMelSpec)
                    {
                        _ = benchmarkInference.generateAudio(melSpectrogram: convertedMel)
                    }
                }
            }
        }
    }

    print("╔═══════════════════════════════════════════════════════════════════════════╗")
    print("║                         BENCHMARK COMPLETE                                 ║")
    print("╚═══════════════════════════════════════════════════════════════════════════╝")
}

// Run the benchmarks with command line arguments
runAllBenchmarks(config: BenchmarkConfig.fromCommandLine())
