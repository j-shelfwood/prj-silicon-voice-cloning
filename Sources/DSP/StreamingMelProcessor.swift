import Foundation
import Utilities

/// A class for processing audio in real-time chunks to produce mel-spectrograms.
/// This is optimized for streaming use cases where audio arrives in small buffers.
public class StreamingMelProcessor {
    private let spectrogramGenerator: SpectrogramGenerator
    private let melConverter: MelSpectrogramConverter
    private let hopSize: Int
    private let sampleRate: Float
    private let melBands: Int

    // Buffer to store audio samples that haven't been processed yet
    private var audioBuffer: [Float] = []
    // The maximum number of samples to keep in the buffer
    private var maxBufferSize: Int

    /**
     Initialize a new StreamingMelProcessor

     - Parameters:
        - fftSize: Size of the FFT to perform
        - hopSize: Number of samples to advance between FFT windows
        - sampleRate: Audio sample rate in Hz
        - melBands: Number of mel bands for the mel spectrogram
        - minFrequency: Minimum frequency in Hz for mel scale
        - maxFrequency: Maximum frequency in Hz for mel scale
     */
    public init(
        fftSize: Int = 1024,
        hopSize: Int? = nil,
        sampleRate: Float = 44100.0,
        melBands: Int = 40,
        minFrequency: Float = 0.0,
        maxFrequency: Float = 8000.0
    ) {
        self.spectrogramGenerator = SpectrogramGenerator(
            fftSize: fftSize, hopSize: hopSize ?? (fftSize / 2))
        self.melConverter = MelSpectrogramConverter(
            sampleRate: sampleRate,
            melBands: melBands,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency
        )
        self.hopSize = hopSize ?? (fftSize / 2)
        self.sampleRate = sampleRate
        self.melBands = melBands

        // Keep enough samples for at least 2 FFT windows to ensure smooth processing
        self.maxBufferSize = fftSize * 3

        // Use print instead of Utilities.log to avoid MainActor requirement
        print(
            "StreamingMelProcessor initialized with FFT size: \(fftSize), hop size: \(self.hopSize)"
        )
    }

    /**
     Process a chunk of audio samples and update the internal buffer

     - Parameter samples: New audio samples to process
     */
    public func addSamples(_ samples: [Float]) {
        // Add new samples to the buffer
        audioBuffer.append(contentsOf: samples)

        // Trim buffer if it gets too large
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(audioBuffer.count - maxBufferSize)
        }
    }

    /**
     Process the current audio buffer and generate mel-spectrogram frames

     - Parameter minFrames: Minimum number of frames to generate (or nil to process all available)
     - Returns: Array of mel-spectrogram frames and the number of samples consumed
     */
    public func processMelSpectrogram(minFrames: Int? = nil) -> (
        melFrames: [[Float]], samplesConsumed: Int
    ) {
        // Check if we have enough samples for at least one FFT window
        guard audioBuffer.count >= spectrogramGenerator.fftSize else {
            return ([], 0)
        }

        // Calculate how many complete frames we can process
        let availableFrames = (audioBuffer.count - spectrogramGenerator.fftSize) / hopSize + 1

        // Determine how many frames to actually process
        let framesToProcess = minFrames != nil ? min(availableFrames, minFrames!) : availableFrames

        // If no frames to process, return empty
        if framesToProcess <= 0 {
            return ([], 0)
        }

        // Calculate how many samples will be consumed
        let samplesToConsume = (framesToProcess - 1) * hopSize + spectrogramGenerator.fftSize

        // Generate spectrogram from the buffer
        let spectrogram = spectrogramGenerator.generateSpectrogram(
            inputBuffer: Array(audioBuffer.prefix(samplesToConsume)),
            hopSize: hopSize
        )

        // Convert to mel spectrogram
        let melSpectrogram = melConverter.specToMelSpec(spectrogram: spectrogram)

        // Remove the consumed samples from the buffer
        if samplesToConsume > 0 {
            audioBuffer.removeFirst(samplesToConsume)
        }

        return (melSpectrogram, samplesToConsume)
    }

    /**
     Process the current audio buffer and generate log-mel-spectrogram frames

     - Parameter minFrames: Minimum number of frames to generate (or nil to process all available)
     - Returns: Array of log-mel-spectrogram frames and the number of samples consumed
     */
    public func processLogMelSpectrogram(minFrames: Int? = nil) -> (
        logMelFrames: [[Float]], samplesConsumed: Int
    ) {
        let (melFrames, samplesConsumed) = processMelSpectrogram(minFrames: minFrames)

        if melFrames.isEmpty {
            return ([], samplesConsumed)
        }

        // Convert to log-mel spectrogram
        let logMelFrames = melConverter.melToLogMel(melSpectrogram: melFrames)

        return (logMelFrames, samplesConsumed)
    }

    /**
     Reset the internal audio buffer
     */
    public func reset() {
        audioBuffer.removeAll()
    }

    /**
     Get the current buffer length in samples

     - Returns: Number of samples in the buffer
     */
    public func getBufferLength() -> Int {
        return audioBuffer.count
    }
}
