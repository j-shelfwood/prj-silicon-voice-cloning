import Foundation

/// Utility functions for generating and processing audio signals.
public class AudioSignalUtility {
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
        let numSamples = Int(sampleRate * duration)
        var sineWave = [Float](repeating: 0.0, count: numSamples)

        for i in 0..<numSamples {
            let phase = 2.0 * Float.pi * frequency * Float(i) / sampleRate
            sineWave[i] = sin(phase)
        }

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
        let numSamples = Int(sampleRate * duration)
        var squareWave = [Float](repeating: 0.0, count: numSamples)

        let samplesPerCycle = sampleRate / frequency

        for i in 0..<numSamples {
            let cyclePosition = Float(i).truncatingRemainder(dividingBy: samplesPerCycle)
            squareWave[i] = cyclePosition < samplesPerCycle / 2 ? 1.0 : -1.0
        }

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
        let numSamples = Int(sampleRate * duration)
        var sawtoothWave = [Float](repeating: 0.0, count: numSamples)

        let samplesPerCycle = sampleRate / frequency

        for i in 0..<numSamples {
            let cyclePosition = Float(i).truncatingRemainder(dividingBy: samplesPerCycle)
            sawtoothWave[i] = (cyclePosition / samplesPerCycle) * 2.0 - 1.0
        }

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
        let numSamples = Int(sampleRate * duration)
        var noise = [Float](repeating: 0.0, count: numSamples)

        for i in 0..<numSamples {
            noise[i] = Float.random(in: -1.0...1.0)
        }

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
        return buffer.map { $0 * gain }
    }
}
