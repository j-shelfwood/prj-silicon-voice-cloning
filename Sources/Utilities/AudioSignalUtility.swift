import Accelerate
import Foundation
import os.lock

/// Utility class for generating and processing audio signals
public class AudioSignalUtility {
    // Cache for generated waveforms
    nonisolated(unsafe) private static var waveformCache: [String: [Float]] = [:]
    nonisolated(unsafe) private static var cacheLock = os_unfair_lock()
    private static let cacheMaxSize = 20

    /**
     Generate a hash key for caching based on waveform parameters
     */
    private static func cacheKey(type: String, frequency: Float, sampleRate: Float, duration: Float)
        -> String
    {
        return "\(type)_\(frequency)_\(sampleRate)_\(duration)"
    }

    /**
     Check if result is in cache
     */
    private static func getCachedResult(key: String) -> [Float]? {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        return waveformCache[key]
    }

    /**
     Store result in cache
     */
    private static func cacheResult(key: String, waveform: [Float]) {
        os_unfair_lock_lock(&cacheLock)
        defer { os_unfair_lock_unlock(&cacheLock) }

        var updatedCache = waveformCache

        // If cache is full, remove oldest entry
        if updatedCache.count >= cacheMaxSize {
            let firstKey = updatedCache.keys.first ?? ""
            updatedCache.removeValue(forKey: firstKey)
        }

        // Add new entry
        updatedCache[key] = waveform
    }

    /**
     Generate a sine wave for testing audio output

     - Parameters:
       - frequency: Frequency of the sine wave in Hz
       - sampleRate: Sample rate in Hz
       - duration: Duration of the sine wave in seconds
     - Returns: Array of float samples representing the sine wave
     */
    public static func generateSineWave(frequency: Float, sampleRate: Float, duration: Float)
        -> [Float]
    {
        // Check cache first
        let key = cacheKey(
            type: "sine", frequency: frequency, sampleRate: sampleRate, duration: duration)
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        let numSamples = Int(sampleRate * duration)
        var sineWave = [Float](repeating: 0.0, count: numSamples)

        // Use vDSP to generate the sine wave more efficiently
        var phase: Float = 0.0
        let phaseIncrement = 2.0 * Float.pi * frequency / sampleRate

        // Generate a phase vector
        var phases = [Float](repeating: 0.0, count: numSamples)
        for i in 0..<numSamples {
            phases[i] = phase
            phase += phaseIncrement
        }

        // Use vDSP to compute sine values
        vvsinf(&sineWave, phases, [Int32(numSamples)])

        // Cache the result
        cacheResult(key: key, waveform: sineWave)

        return sineWave
    }

    /**
     Generate a square wave for testing audio output

     - Parameters:
       - frequency: Frequency of the square wave in Hz
       - sampleRate: Sample rate in Hz
       - duration: Duration of the square wave in seconds
     - Returns: Array of float samples representing the square wave
     */
    public static func generateSquareWave(frequency: Float, sampleRate: Float, duration: Float)
        -> [Float]
    {
        let key = cacheKey(
            type: "square", frequency: frequency, sampleRate: sampleRate, duration: duration)

        // Check cache first
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        let numSamples = Int(sampleRate * duration)
        var squareWave = [Float](repeating: 0.0, count: numSamples)

        // Generate a sine wave first
        let sineWave = generateSineWave(
            frequency: frequency, sampleRate: sampleRate, duration: duration)

        // Convert to square wave by taking the sign
        for i in 0..<numSamples {
            squareWave[i] = sineWave[i] >= 0 ? 1.0 : -1.0
        }

        // Cache the result
        cacheResult(key: key, waveform: squareWave)

        return squareWave
    }

    /**
     Generate a sawtooth wave for testing audio output

     - Parameters:
       - frequency: Frequency of the sawtooth wave in Hz
       - sampleRate: Sample rate in Hz
       - duration: Duration of the sawtooth wave in seconds
     - Returns: Array of float samples representing the sawtooth wave
     */
    public static func generateSawtoothWave(frequency: Float, sampleRate: Float, duration: Float)
        -> [Float]
    {
        // Check cache first
        let key = cacheKey(
            type: "sawtooth", frequency: frequency, sampleRate: sampleRate, duration: duration)
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        let numSamples = Int(sampleRate * duration)
        var sawtoothWave = [Float](repeating: 0.0, count: numSamples)

        let samplesPerCycle = sampleRate / frequency
        let increment = 2.0 / samplesPerCycle

        // Use a more efficient approach with vDSP
        var phase: Float = -1.0
        for i in 0..<numSamples {
            sawtoothWave[i] = phase
            phase += increment
            if phase > 1.0 {
                phase -= 2.0
            }
        }

        // Cache the result
        cacheResult(key: key, waveform: sawtoothWave)

        return sawtoothWave
    }

    /**
     Generate white noise for testing audio output

     - Parameters:
       - sampleRate: Sample rate in Hz
       - duration: Duration of the noise in seconds
     - Returns: Array of float samples representing white noise
     */
    public static func generateWhiteNoise(sampleRate: Float, duration: Float) -> [Float] {
        // Check cache first - use a different seed each time for noise
        let seed = Int(Date().timeIntervalSince1970 * 1000) % 10000
        let key = cacheKey(
            type: "noise", frequency: Float(seed), sampleRate: sampleRate, duration: duration)
        if let cachedResult = getCachedResult(key: key) {
            return cachedResult
        }

        let numSamples = Int(sampleRate * duration)
        var noise = [Float](repeating: 0.0, count: numSamples)

        // Generate random values
        for i in 0..<numSamples {
            noise[i] = Float.random(in: -1.0...1.0)
        }

        // Cache the result
        cacheResult(key: key, waveform: noise)

        return noise
    }

    /**
     Apply a gain (volume adjustment) to an audio buffer

     - Parameters:
       - buffer: Input audio buffer
       - gain: Gain factor (1.0 = no change, 0.5 = half volume, 2.0 = double volume)
     - Returns: Audio buffer with gain applied
     */
    public static func applyGain(buffer: [Float], gain: Float) -> [Float] {
        var result = [Float](repeating: 0.0, count: buffer.count)
        var gainValue = gain  // Create a mutable copy

        // Use vDSP for efficient vector multiplication
        vDSP_vsmul(buffer, 1, &gainValue, &result, 1, vDSP_Length(buffer.count))

        return result
    }
}
