import Accelerate
import Foundation
import Utilities
import os.lock

/// A class dedicated to performing Fast Fourier Transform (FFT) operations on audio signals.
/// Uses Apple's Accelerate framework for high-performance FFT computation.
public class FFTProcessor {
    private var fftSetup: vDSP.FFT<DSPSplitComplex>?
    private var fftSize: Int
    private var windowBuffer: [Float]

    // Pre-allocated buffers for FFT operations
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudeBuffer: [Float]
    private var dbMagnitudeBuffer: [Float]

    // Thread safety
    private var bufferLock = os_unfair_lock()

    // Cache for FFT results
    private var resultCache: [String: [Float]] = [:]
    private var cacheMaxSize = 10
    private var cacheLock = os_unfair_lock()

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

        // Pre-allocate buffers
        let halfSize = fftSize / 2
        self.realBuffer = [Float](repeating: 0.0, count: halfSize)
        self.imagBuffer = [Float](repeating: 0.0, count: halfSize)
        self.magnitudeBuffer = [Float](repeating: 0.0, count: halfSize)
        self.dbMagnitudeBuffer = [Float](repeating: 0.0, count: halfSize)

        // Log initialization
        LoggerUtility.debug("FFTProcessor initialized with FFT size: \(fftSize)")
    }

    /**
     Generate a hash key for caching based on input buffer
     */
    private func cacheKey(inputBuffer: [Float]) -> String {
        // Use first few samples and length as a simple hash
        let sampleCount = min(10, inputBuffer.count)
        var samples = ""
        for i in 0..<sampleCount {
            samples += String(format: "%.2f", inputBuffer[i])
        }
        return "\(samples)_\(inputBuffer.count)"
    }

    /**
     Check if result is in cache
     */
    private func getCachedResult(key: String) -> [Float]? {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        return resultCache[key]
    }

    /**
     Store result in cache
     */
    private func cacheResult(key: String, result: [Float]) {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        // If cache is full, remove oldest entry
        if resultCache.count >= cacheMaxSize {
            let firstKey = resultCache.keys.first ?? ""
            resultCache.removeValue(forKey: firstKey)
        }

        resultCache[key] = result
    }

    /**
     Perform a forward FFT on the input buffer.

     - Parameter inputBuffer: Audio samples in time domain
     - Returns: Magnitude spectrum in frequency domain (dB scale)
     */
    public func performFFT(inputBuffer: [Float]) -> [Float] {
        // Ensure input buffer is large enough
        guard inputBuffer.count >= fftSize else {
            // Use LoggerUtility.debug instead of print
            LoggerUtility.debug(
                "Error: Input buffer too small for FFT. Expected at least \(fftSize) samples, got \(inputBuffer.count)."
            )
            return []
        }

        // Check cache first
        let key = cacheKey(inputBuffer: inputBuffer)
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        // Create a copy of the input buffer to avoid modifying the original
        var inputCopy = [Float](repeating: 0.0, count: fftSize)

        // Copy input data using vDSP_mmov for better performance
        let copyLength = min(fftSize, inputBuffer.count)
        vDSP_mmov(inputBuffer, &inputCopy, vDSP_Length(copyLength), 1, vDSP_Length(copyLength), 1)

        // Apply window function to reduce spectral leakage using vDSP_vmul
        vDSP_vmul(inputCopy, 1, windowBuffer, 1, &inputCopy, 1, vDSP_Length(fftSize))

        // Prepare split complex buffer for FFT
        let halfSize = fftSize / 2

        // Acquire lock for shared buffers
        os_unfair_lock_lock(&bufferLock)

        // Create local copies of the pre-allocated buffers
        var localRealBuffer = realBuffer
        var localImagBuffer = imagBuffer
        var localMagnitudeBuffer = magnitudeBuffer
        var localDbMagnitudeBuffer = dbMagnitudeBuffer

        os_unfair_lock_unlock(&bufferLock)

        // Safely use pointers with withUnsafeMutableBufferPointer
        return localRealBuffer.withUnsafeMutableBufferPointer { realPtr in
            localImagBuffer.withUnsafeMutableBufferPointer { imagPtr in
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
                    LoggerUtility.debug("Error: FFT setup not initialized")
                    return []
                }

                fftSetup.forward(input: splitComplex, output: &splitComplex)

                // Calculate magnitude spectrum using vDSP_zvmags
                vDSP_zvmags(&splitComplex, 1, &localMagnitudeBuffer, 1, vDSP_Length(halfSize))

                // Convert to dB scale with proper scaling
                // Scale factor for FFT: 2.0 / fftSize
                var scaleFactor = 2.0 / Float(fftSize)
                vDSP_vsmul(
                    localMagnitudeBuffer, 1, &scaleFactor, &localMagnitudeBuffer, 1,
                    vDSP_Length(halfSize))

                // Add small value to avoid log(0)
                var epsilon: Float = 1e-10
                vDSP_vsadd(
                    localMagnitudeBuffer, 1, &epsilon, &localMagnitudeBuffer, 1,
                    vDSP_Length(halfSize))

                // Convert to dB: 10 * log10(x)
                var ten: Float = 10.0
                vDSP_vdbcon(
                    localMagnitudeBuffer, 1, &ten, &localDbMagnitudeBuffer, 1,
                    vDSP_Length(halfSize), 0)

                // Cache the result
                cacheResult(key: key, result: Array(localDbMagnitudeBuffer))

                return Array(localDbMagnitudeBuffer)
            }
        }
    }

    /// Get the size of the FFT
    public var size: Int {
        return fftSize
    }
}
