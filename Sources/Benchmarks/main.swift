import AVFoundation
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

/// Load audio samples from an m4a file
func loadAudioFromFile(filePath: String) -> [Float]? {
    let url: URL

    // Handle both URL strings and file paths
    if filePath.hasPrefix("http://") || filePath.hasPrefix("https://") {
        guard let httpUrl = URL(string: filePath) else {
            print("Error: Invalid URL: \(filePath)")
            return nil
        }
        url = httpUrl
    } else {
        url = URL(fileURLWithPath: filePath)
    }

    do {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("Error: Failed to create audio buffer")
            return nil
        }

        try audioFile.read(into: buffer)

        // Convert to mono if needed
        if let floatChannelData = buffer.floatChannelData {
            let channelCount = Int(format.channelCount)
            let frameLength = Int(buffer.frameLength)

            if channelCount == 1 {
                // Already mono
                return Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
            } else {
                // Convert to mono by averaging channels
                var monoSamples = [Float](repeating: 0.0, count: frameLength)

                for frame in 0..<frameLength {
                    var sum: Float = 0.0
                    for channel in 0..<channelCount {
                        sum += floatChannelData[channel][frame]
                    }
                    monoSamples[frame] = sum / Float(channelCount)
                }

                return monoSamples
            }
        }

        print("Error: Failed to get float channel data")
        return nil
    } catch {
        print("Error loading audio file: \(error)")
        return nil
    }
}

/// Benchmark configuration
struct BenchmarkConfig {
    let iterations: Int
    let warmupIterations: Int
    let audioFilePath: String
    let audioLength: Float  // in seconds, used only if audioFilePath is empty
    let fftSize: Int
    let hopSize: Int
    let melBands: Int
    let sampleRate: Float
    let runCategory: BenchmarkCategory
    let maxAudioDuration: Float  // maximum duration to use from audio file (in seconds)

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
        audioFilePath: "Assets/target-clone-voice-sample.m4a",
        audioLength: 5.0,
        fftSize: 1024,
        hopSize: 256,
        melBands: 80,
        sampleRate: 44100.0,
        runCategory: .all,
        maxAudioDuration: 2.0  // Use only 2 seconds of audio for benchmarks
    )

    static func fromCommandLine() -> BenchmarkConfig {
        let args = CommandLine.arguments

        var iterations = standard.iterations
        var warmup = standard.warmupIterations
        var audioFilePath = standard.audioFilePath
        var audioLength = standard.audioLength
        var fftSize = standard.fftSize
        var hopSize = standard.hopSize
        var melBands = standard.melBands
        var sampleRate = standard.sampleRate
        var category = standard.runCategory
        var maxAudioDuration = standard.maxAudioDuration

        for i in 1..<args.count {
            let arg = args[i]

            if arg == "--iterations" || arg == "-i", i + 1 < args.count {
                iterations = Int(args[i + 1]) ?? iterations
            } else if arg == "--warmup" || arg == "-w", i + 1 < args.count {
                warmup = Int(args[i + 1]) ?? warmup
            } else if arg == "--audio-file" || arg == "-f", i + 1 < args.count {
                audioFilePath = args[i + 1]
            } else if arg == "--audio-length" || arg == "-a", i + 1 < args.count {
                audioLength = Float(args[i + 1]) ?? audioLength
            } else if arg == "--fft-size", i + 1 < args.count {
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
            } else if arg == "--max-duration" || arg == "-d", i + 1 < args.count {
                maxAudioDuration = Float(args[i + 1]) ?? maxAudioDuration
            } else if arg == "--help" {
                printUsage()
                exit(0)
            }
        }

        return BenchmarkConfig(
            iterations: iterations,
            warmupIterations: warmup,
            audioFilePath: audioFilePath,
            audioLength: audioLength,
            fftSize: fftSize,
            hopSize: hopSize,
            melBands: melBands,
            sampleRate: sampleRate,
            runCategory: category,
            maxAudioDuration: maxAudioDuration
        )
    }

    static func printUsage() {
        print(
            """
            Usage: benchmarks [options]

            Options:
              --iterations, -i <num>     Number of benchmark iterations (default: \(standard.iterations))
              --warmup, -w <num>         Number of warmup iterations (default: \(standard.warmupIterations))
              --audio-file, -f <path>    Path to audio file for benchmarks (default: \(standard.audioFilePath))
              --audio-length, -a <sec>   Length of test audio in seconds (used if no file, default: \(standard.audioLength))
              --max-duration, -d <sec>   Maximum duration to use from audio file (default: \(standard.maxAudioDuration))
              --fft-size <size>          FFT size (default: \(standard.fftSize))
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
@MainActor
func runAllBenchmarks(config: BenchmarkConfig = .standard) {
    print("╔═══════════════════════════════════════════════════════════════════════════╗")
    print("║                     Voice Cloning Performance Benchmarks                   ║")
    print("╚═══════════════════════════════════════════════════════════════════════════╝")
    print("Configuration:")
    print("  Iterations: \(config.iterations)")
    print("  Warmup Iterations: \(config.warmupIterations)")
    print("  Audio File: \(config.audioFilePath)")
    print("  Max Audio Duration: \(config.maxAudioDuration) seconds")
    print("  FFT Size: \(config.fftSize)")
    print("  Hop Size: \(config.hopSize)")
    print("  Mel Bands: \(config.melBands)")
    print("  Sample Rate: \(config.sampleRate) Hz")
    print("  Category: \(config.runCategory.rawValue)")
    print("")

    // Generate or load test audio
    var audioSamples: [Float] = []

    if let loadedAudio = loadAudioFromFile(filePath: config.audioFilePath) {
        print("Successfully loaded audio from \(config.audioFilePath)")

        // Limit audio duration if needed
        let maxSamples = Int(config.maxAudioDuration * config.sampleRate)
        if loadedAudio.count > maxSamples {
            audioSamples = Array(loadedAudio.prefix(maxSamples))
            print(
                "Using first \(config.maxAudioDuration) seconds of audio (\(audioSamples.count) samples)"
            )
        } else {
            audioSamples = loadedAudio
            print(
                "Using entire audio file (\(audioSamples.count) samples, \(Float(audioSamples.count) / config.sampleRate) seconds)"
            )
        }
    } else {
        print("Failed to load audio file, generating sine wave instead")
        audioSamples = Utilities.generateSineWave(
            frequency: 440.0,
            sampleRate: config.sampleRate,
            duration: config.audioLength
        )
        print("Generated \(audioSamples.count) samples of sine wave")
    }

    // Initialize components
    let _ = DSP(fftSize: config.fftSize, sampleRate: config.sampleRate)
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

    // Use the BenchmarkModelInference class instead of ModelInference to avoid @MainActor issues
    let benchmarkModelInference = BenchmarkModelInference()

    // Run DSP benchmarks
    if [.all, .dsp, .critical].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           DSP BENCHMARKS                                   ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Benchmark: FFT Processing
        let fftBenchmark = Benchmark(name: "FFT Processing")
        fftBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let _ = fftProcessor.performFFT(inputBuffer: Array(audioSamples.prefix(config.fftSize)))
        }

        // Benchmark: Spectrogram Generation
        let spectrogramBenchmark = Benchmark(name: "Spectrogram Generation")
        spectrogramBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let _ = spectrogramGenerator.generateSpectrogram(
                inputBuffer: audioSamples, hopSize: config.hopSize)
        }

        // Benchmark: Mel Spectrogram Conversion
        let melSpecBenchmark = Benchmark(name: "Mel Spectrogram Conversion")
        // Generate a smaller spectrogram for benchmarking
        let spectrogram = spectrogramGenerator.generateSpectrogram(
            inputBuffer: audioSamples, hopSize: config.hopSize)
        melSpecBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let _ = melConverter.specToMelSpec(spectrogram: spectrogram)
        }

        // Benchmark: Log Mel Spectrogram Conversion
        let logMelBenchmark = Benchmark(name: "Log Mel Spectrogram Conversion")
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)
        logMelBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let _ = melConverter.melToLogMel(melSpectrogram: melSpectrogram)
        }

        // Benchmark: Streaming Mel Processing
        let streamingBenchmark = Benchmark(name: "Streaming Mel Processing")
        streamingBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            streamingProcessor.reset()
            streamingProcessor.addSamples(audioSamples)
            let _ = streamingProcessor.processMelSpectrogram()
        }

        // Benchmark: End-to-End DSP Pipeline
        let pipelineBenchmark = Benchmark(name: "End-to-End DSP Pipeline")
        pipelineBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            let spec = spectrogramGenerator.generateSpectrogram(
                inputBuffer: audioSamples, hopSize: config.hopSize)
            let melSpec = melConverter.specToMelSpec(spectrogram: spec)
            let _ = melConverter.melToLogMel(melSpectrogram: melSpec)
        }
    }

    // Run ML benchmarks
    if [.all, .model].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           ML BENCHMARKS                                    ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Create test mel spectrogram for ML benchmarks
        let spectrogram = spectrogramGenerator.generateSpectrogram(
            inputBuffer: audioSamples, hopSize: config.hopSize)
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Benchmark: Model Loading
        let modelLoadingBenchmark = Benchmark(name: "Model Loading (Simulated)")
        modelLoadingBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            _ = benchmarkModelInference.loadModel(
                modelPath: "/path/to/model.mlmodel",
                modelType: .voiceConverter
            )
        }

        // Benchmark: Voice Conversion
        let voiceConversionBenchmark = Benchmark(name: "Voice Conversion (Simulated)")
        voiceConversionBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations)
        {
            _ = benchmarkModelInference.processVoiceConversion(melSpectrogram: melSpectrogram)
        }

        // Benchmark: Audio Generation
        let audioGenerationBenchmark = Benchmark(name: "Audio Generation (Simulated)")
        audioGenerationBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations)
        {
            _ = benchmarkModelInference.generateAudio(melSpectrogram: melSpectrogram)
        }
    }

    // Run audio processing benchmarks
    if [.all, .audio].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           AUDIO BENCHMARKS                                 ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Benchmark: Audio Processing (Mock)
        let audioProcessingBenchmark = Benchmark(name: "Audio Processing (Mock)")
        audioProcessingBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations)
        {
            // Simulate audio processing with a simple gain adjustment
            let _ = audioSamples.map { $0 * 0.5 }
        }
    }

    // Run critical path benchmarks (end-to-end voice cloning pipeline)
    if [.all, .critical].contains(config.runCategory) {
        print("╔═══════════════════════════════════════════════════════════════════════════╗")
        print("║                           CRITICAL PATH BENCHMARKS                         ║")
        print("╚═══════════════════════════════════════════════════════════════════════════╝")

        // Benchmark: End-to-End Voice Cloning Pipeline
        let e2eBenchmark = Benchmark(name: "End-to-End Voice Cloning Pipeline")
        e2eBenchmark.run(iterations: config.iterations, warmup: config.warmupIterations) {
            // 1. Generate spectrogram
            let spec = spectrogramGenerator.generateSpectrogram(
                inputBuffer: audioSamples, hopSize: config.hopSize)

            // 2. Convert to mel spectrogram
            let melSpec = melConverter.specToMelSpec(spectrogram: spec)

            // 3. Convert to log mel spectrogram
            let _ = melConverter.melToLogMel(melSpectrogram: melSpec)

            // 4. Process through voice conversion model (simulated)
            let convertedMelSpec = benchmarkModelInference.processVoiceConversion(
                melSpectrogram: melSpec)!

            // 5. Generate audio from converted mel spectrogram (simulated)
            let _ = benchmarkModelInference.generateAudio(melSpectrogram: convertedMelSpec)
        }
    }
}

// Run the benchmarks with command line arguments
Task { @MainActor in
    await runBenchmarksAsync(config: BenchmarkConfig.fromCommandLine())
}

// Keep the program running until benchmarks complete
RunLoop.main.run(until: Date(timeIntervalSinceNow: 300))  // 5 minutes timeout

@MainActor
func runBenchmarksAsync(config: BenchmarkConfig) async {
    runAllBenchmarks(config: config)
}
