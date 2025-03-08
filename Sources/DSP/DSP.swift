import Accelerate
import AudioProcessor
import Foundation
import Utilities

/// Class for audio signal processing operations.
/// This class now serves as a high-level facade for the DSP components,
/// delegating operations to specialized classes.
public class DSP {
    private let fftProcessor: FFTProcessor
    private let spectrogramGenerator: SpectrogramGenerator
    private let melConverter: MelSpectrogramConverter

    /**
     Initialize a new DSP instance with the specified FFT size

     - Parameter fftSize: Size of the FFT to perform (default: 1024)
     - Parameter sampleRate: Sample rate of the audio (default: 44100.0)
     */
    public init(fftSize: Int = 1024, sampleRate: Float = 44100.0) {
        self.fftProcessor = FFTProcessor(fftSize: fftSize)
        self.spectrogramGenerator = SpectrogramGenerator(fftSize: fftSize)
        self.melConverter = MelSpectrogramConverter(
            sampleRate: sampleRate,
            melBands: 40,
            minFrequency: 0.0,
            maxFrequency: sampleRate / 5.5  // ~8000 Hz for 44.1kHz
        )

        Utilities.log("DSP initialized with FFT size: \(fftSize), sample rate: \(sampleRate)")
    }

    /**
     Perform a forward FFT on the input buffer

     - Parameter inputBuffer: Audio samples in time domain
     - Returns: Magnitude spectrum in frequency domain
     */
    public func performFFT(inputBuffer: [Float]) -> [Float] {
        return fftProcessor.performFFT(inputBuffer: inputBuffer)
    }

    /**
     Generate a spectrogram from the input buffer

     - Parameters:
       - inputBuffer: Audio samples in time domain
       - hopSize: Number of samples to advance between FFT windows
     - Returns: 2D array representing the spectrogram (time x frequency)
     */
    public func generateSpectrogram(inputBuffer: [Float], hopSize: Int = 256) -> [[Float]] {
        return spectrogramGenerator.generateSpectrogram(inputBuffer: inputBuffer, hopSize: hopSize)
    }

    /**
     Convert spectrogram to mel-spectrogram using mel filterbank

     - Parameter spectrogram: Linear frequency spectrogram
     - Returns: Mel-scaled spectrogram
     */
    public func specToMelSpec(spectrogram: [[Float]]) -> [[Float]] {
        return melConverter.specToMelSpec(spectrogram: spectrogram)
    }

    /**
     Convert mel-spectrogram to log-mel-spectrogram

     - Parameters:
       - melSpectrogram: Mel-scaled spectrogram
       - ref: Reference value for log scaling (default: 1.0)
       - floor: Floor value to clip small values (default: 1e-5)
     - Returns: Log-mel-spectrogram
     */
    public func melToLogMel(melSpectrogram: [[Float]], ref: Float = 1.0, floor: Float = 1e-5)
        -> [[Float]]
    {
        return melConverter.melToLogMel(melSpectrogram: melSpectrogram, ref: ref, floor: floor)
    }
}
