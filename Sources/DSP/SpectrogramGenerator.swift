import Foundation
import Utilities

/// A class for generating spectrograms from audio signals using FFT analysis.
/// This class handles the conversion of time-domain audio signals into
/// time-frequency representations (spectrograms).
public class SpectrogramGenerator {
    private let fftProcessor: FFTProcessor
    private let defaultHopSize: Int

    /**
     Initialize a new SpectrogramGenerator instance.

     - Parameters:
        - fftSize: Size of the FFT to perform (must be a power of 2)
        - hopSize: Number of samples to advance between FFT windows (default: fftSize/4)
     */
    public init(fftSize: Int = 1024, hopSize: Int? = nil) {
        self.fftProcessor = FFTProcessor(fftSize: fftSize)
        self.defaultHopSize = hopSize ?? fftSize / 4
    }

    /**
     Generate a spectrogram from the input buffer.

     - Parameters:
        - inputBuffer: Audio samples in time domain
        - hopSize: Optional custom hop size (if not provided, uses the default)
     - Returns: 2D array representing the spectrogram (time x frequency)
     */
    public func generateSpectrogram(inputBuffer: [Float], hopSize: Int? = nil) -> [[Float]] {
        let hopSize = hopSize ?? defaultHopSize
        let fftSize = fftProcessor.size

        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            Utilities.log(
                "Error: Input buffer too small for spectrogram generation. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return []
        }

        // Calculate number of frames
        let numFrames = max(1, (inputBuffer.count - fftSize) / hopSize + 1)
        var spectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: fftSize / 2), count: numFrames)

        // Process each frame
        for i in 0..<numFrames {
            let startIdx = i * hopSize
            let endIdx = startIdx + fftSize

            // Ensure we don't go out of bounds
            guard endIdx <= inputBuffer.count else {
                // If we can't get a full frame, just use what we have and pad with zeros
                var frame = Array(inputBuffer[startIdx..<inputBuffer.count])
                frame.append(contentsOf: [Float](repeating: 0.0, count: endIdx - inputBuffer.count))
                spectrogram[i] = fftProcessor.performFFT(inputBuffer: frame)
                continue
            }

            // Extract frame and perform FFT
            let frame = Array(inputBuffer[startIdx..<endIdx])
            spectrogram[i] = fftProcessor.performFFT(inputBuffer: frame)
        }

        return spectrogram
    }

    /// Get the size of the FFT used by this generator
    public var fftSize: Int {
        return fftProcessor.size
    }
}
