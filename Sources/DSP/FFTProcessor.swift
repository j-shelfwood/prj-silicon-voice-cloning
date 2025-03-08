import Accelerate
import Foundation
import Utilities

/// A class dedicated to performing Fast Fourier Transform (FFT) operations on audio signals.
/// Uses Apple's Accelerate framework for high-performance FFT computation.
public class FFTProcessor {
    private var fftSetup: vDSP.FFT<DSPSplitComplex>?
    private var fftSize: Int
    private var windowBuffer: [Float]

    /**
     Initialize a new FFTProcessor instance with the specified FFT size.

     - Parameter fftSize: Size of the FFT to perform (must be a power of 2)
     */
    public init(fftSize: Int = 1024) {
        self.fftSize = fftSize

        // Create a Hann window for better spectral analysis
        self.windowBuffer = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&windowBuffer, vDSP_Length(fftSize), Int32(0))

        let log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)

        Utilities.log("FFTProcessor initialized with FFT size: \(fftSize)")
    }

    /**
     Perform a forward FFT on the input buffer.

     - Parameter inputBuffer: Audio samples in time domain
     - Returns: Magnitude spectrum in frequency domain (dB scale)
     */
    public func performFFT(inputBuffer: [Float]) -> [Float] {
        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            Utilities.log(
                "Error: Input buffer too small for FFT. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return []
        }

        // Create a copy of the input buffer to avoid modifying the original
        var inputCopy = Array(inputBuffer.prefix(fftSize))

        // Apply window function to reduce spectral leakage
        vDSP_vmul(inputCopy, 1, windowBuffer, 1, &inputCopy, 1, vDSP_Length(fftSize))

        // Prepare split complex buffer for FFT
        let halfSize = fftSize / 2
        var realp = [Float](repeating: 0.0, count: halfSize)
        var imagp = [Float](repeating: 0.0, count: halfSize)

        // Safely use pointers with withUnsafeMutableBufferPointer
        return realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                // Create split complex with safe pointers
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                // Convert real input to split complex format
                inputCopy.withUnsafeBytes { inputPtr in
                    let ptr = inputPtr.bindMemory(to: DSPComplex.self).baseAddress!
                    vDSP_ctoz(ptr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }

                // Perform forward FFT
                guard let fftSetup = fftSetup else {
                    Utilities.log("Error: FFT setup not initialized")
                    return []
                }

                // Use the FFT setup to perform the forward transform
                fftSetup.forward(input: splitComplex, output: &splitComplex)

                // Calculate magnitude spectrum
                var magnitudes = [Float](repeating: 0.0, count: halfSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

                // Scale magnitudes
                var scaleFactor = Float(1.0) / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scaleFactor, &magnitudes, 1, vDSP_Length(halfSize))

                // Convert to dB scale
                var dbMagnitudes = [Float](repeating: 0.0, count: halfSize)
                var zeroReference: Float = 1.0
                vDSP_vdbcon(
                    magnitudes, 1, &zeroReference, &dbMagnitudes, 1, vDSP_Length(halfSize), 1)

                return dbMagnitudes
            }
        }
    }

    /// Get the size of the FFT
    public var size: Int {
        return fftSize
    }
}
