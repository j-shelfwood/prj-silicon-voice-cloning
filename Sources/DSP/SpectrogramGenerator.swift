import Accelerate
import Foundation
import Utilities

/// A class for generating spectrograms from audio signals using FFT analysis.
/// This class handles the conversion of time-domain audio signals into
/// time-frequency representations (spectrograms).
public class SpectrogramGenerator {
    private let fftProcessor: FFTProcessor
    private let defaultHopSize: Int

    // Pre-allocated buffer for frame extraction
    private var frameBuffer: [Float]

    /**
     Initialize a new SpectrogramGenerator instance.

     - Parameters:
        - fftSize: Size of the FFT to perform (must be a power of 2)
        - hopSize: Number of samples to advance between FFT windows (default: fftSize/4)
     */
    public init(fftSize: Int = 1024, hopSize: Int? = nil) {
        self.fftProcessor = FFTProcessor(fftSize: fftSize)
        self.defaultHopSize = hopSize ?? fftSize / 4
        self.frameBuffer = [Float](repeating: 0.0, count: fftSize)
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

        // Pre-allocate the entire spectrogram array
        var spectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: fftSize / 2), count: numFrames)

        // Process each frame
        for i in 0..<numFrames {
            let startIdx = i * hopSize
            let endIdx = min(startIdx + fftSize, inputBuffer.count)

            if endIdx - startIdx == fftSize {
                // Fast path: direct slice without copying
                // Convert ArraySlice to Array
                let frame = Array(inputBuffer[startIdx..<endIdx])
                spectrogram[i] = fftProcessor.performFFT(inputBuffer: frame)
            } else {
                // Partial frame: reset buffer, copy available samples, and zero-pad
                // Clear the buffer
                for j in 0..<fftSize {
                    frameBuffer[j] = 0.0
                }

                let availableSamples = endIdx - startIdx
                if availableSamples > 0 {
                    // Copy available samples
                    for j in 0..<availableSamples {
                        frameBuffer[j] = inputBuffer[startIdx + j]
                    }
                }

                spectrogram[i] = fftProcessor.performFFT(inputBuffer: frameBuffer)
            }
        }

        return spectrogram
    }

    /**
     Generate a spectrogram from the input buffer using parallel processing.

     - Parameters:
        - inputBuffer: Audio samples in time domain
        - hopSize: Optional custom hop size (if not provided, uses the default)
        - useParallel: Whether to use parallel processing (default: true)
     - Returns: 2D array representing the spectrogram (time x frequency)
     */
    public func generateSpectrogramParallel(
        inputBuffer: [Float],
        hopSize: Int? = nil,
        useParallel: Bool = true
    ) -> [[Float]] {
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

        // Pre-allocate the entire spectrogram array
        var spectrogram = [[Float]](
            repeating: [Float](repeating: 0.0, count: fftSize / 2), count: numFrames)

        // If the input is small or parallel processing is disabled, use the sequential version
        if numFrames < 8 || !useParallel {
            return generateSpectrogram(inputBuffer: inputBuffer, hopSize: hopSize)
        }

        // Use concurrent processing for larger inputs
        let queue = DispatchQueue(label: "com.spectrogramGenerator.queue", attributes: .concurrent)
        let group = DispatchGroup()

        // Create a lock for thread-safe access to the spectrogram array
        let lock = NSLock()

        // Process frames in parallel
        for i in 0..<numFrames {
            queue.async(group: group) {
                let startIdx = i * hopSize
                let endIdx = min(startIdx + fftSize, inputBuffer.count)

                var frameResult: [Float]

                if endIdx - startIdx == fftSize {
                    // Fast path: direct slice without copying
                    let frame = Array(inputBuffer[startIdx..<endIdx])
                    frameResult = self.fftProcessor.performFFT(inputBuffer: frame)
                } else {
                    // Partial frame: create a local buffer, copy samples, and zero-pad
                    var localFrameBuffer = [Float](repeating: 0.0, count: fftSize)

                    let availableSamples = endIdx - startIdx
                    if availableSamples > 0 {
                        // Copy available samples
                        for j in 0..<availableSamples {
                            localFrameBuffer[j] = inputBuffer[startIdx + j]
                        }
                    }

                    frameResult = self.fftProcessor.performFFT(inputBuffer: localFrameBuffer)
                }

                // Thread-safe update of the spectrogram array
                lock.lock()
                spectrogram[i] = frameResult
                lock.unlock()
            }
        }

        // Wait for all tasks to complete
        group.wait()

        return spectrogram
    }

    /// Get the size of the FFT used by this generator
    public var fftSize: Int {
        return fftProcessor.size
    }
}
