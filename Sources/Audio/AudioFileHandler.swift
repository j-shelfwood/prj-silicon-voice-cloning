import AudioToolbox
import Foundation
import Utilities

/// A utility class for loading and saving audio files.
public class AudioFileHandler {
    /// Error types that can occur during audio file operations
    public enum AudioFileError: Error {
        case fileNotFound(String)
        case invalidFormat(String)
        case readError(String)
        case writeError(String)
    }

    /// Load an audio file and convert it to a Float array
    /// - Parameters:
    ///   - url: The URL of the audio file to load
    ///   - sampleRate: Optional output parameter to receive the sample rate of the loaded audio
    /// - Returns: A tuple containing the audio data as a Float array and the sample rate
    public static func loadAudioFile(at url: URL) throws -> (audioData: [Float], sampleRate: Double)
    {
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileError.fileNotFound("Audio file not found at path: \(url.path)")
        }

        // Open the audio file
        var audioFile: AudioFileID?
        var status = AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile)

        guard status == noErr, let audioFile = audioFile else {
            throw AudioFileError.readError("Failed to open audio file: \(status)")
        }

        defer {
            AudioFileClose(audioFile)
        }

        // Get the audio file format
        var dataFormat = AudioStreamBasicDescription()
        var dataFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioFileGetProperty(
            audioFile, kAudioFilePropertyDataFormat, &dataFormatSize, &dataFormat)

        guard status == noErr else {
            throw AudioFileError.invalidFormat("Failed to get audio file format: \(status)")
        }

        // Get the audio file size
        var fileSize: UInt64 = 0
        var fileSizeSize = UInt32(MemoryLayout<UInt64>.size)
        status = AudioFileGetProperty(
            audioFile, kAudioFilePropertyAudioDataByteCount, &fileSizeSize, &fileSize)

        guard status == noErr else {
            throw AudioFileError.readError("Failed to get audio file size: \(status)")
        }

        // Read the audio data
        let bufferSize = UInt32(fileSize)
        var audioData = [UInt8](repeating: 0, count: Int(bufferSize))
        var bytesRead = bufferSize

        status = AudioFileReadBytes(audioFile, false, 0, &bytesRead, &audioData)

        guard status == noErr else {
            throw AudioFileError.readError("Failed to read audio file data: \(status)")
        }

        // Convert the audio data to Float array based on the format
        var floatArray: [Float] = []

        switch dataFormat.mFormatID {
        case kAudioFormatLinearPCM:
            if dataFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                // Float format
                let floatCount = Int(bytesRead) / MemoryLayout<Float>.size
                audioData.withUnsafeBytes { rawBuffer in
                    let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                    floatArray = Array(floatBuffer.prefix(floatCount))
                }
            } else if dataFormat.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
                // Integer format
                if dataFormat.mBitsPerChannel == 16 {
                    // 16-bit PCM
                    let sampleCount = Int(bytesRead) / MemoryLayout<Int16>.size
                    audioData.withUnsafeBytes { rawBuffer in
                        let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                        floatArray = Array(int16Buffer.prefix(sampleCount)).map {
                            Float($0) / Float(Int16.max)
                        }
                    }
                } else if dataFormat.mBitsPerChannel == 24 {
                    // 24-bit PCM (3 bytes per sample)
                    let sampleCount = Int(bytesRead) / 3
                    floatArray = [Float](repeating: 0.0, count: sampleCount)

                    for i in 0..<sampleCount {
                        let byteIndex = i * 3
                        if byteIndex + 2 < audioData.count {
                            // Combine 3 bytes into a 32-bit integer, then convert to float
                            let byte1 = Int32(audioData[byteIndex])
                            let byte2 = Int32(audioData[byteIndex + 1])
                            let byte3 = Int32(audioData[byteIndex + 2])

                            // Combine bytes (little-endian)
                            var sample = (byte3 << 16) | (byte2 << 8) | byte1

                            // Sign extension for negative values
                            if (sample & 0x800000) != 0 {
                                sample = sample | Int32(bitPattern: 0xFF00_0000)
                            }

                            // Normalize to [-1.0, 1.0]
                            floatArray[i] = Float(sample) / Float(0x7FFFFF)
                        }
                    }
                } else if dataFormat.mBitsPerChannel == 32 {
                    // 32-bit PCM
                    let sampleCount = Int(bytesRead) / MemoryLayout<Int32>.size
                    audioData.withUnsafeBytes { rawBuffer in
                        let int32Buffer = rawBuffer.bindMemory(to: Int32.self)
                        floatArray = Array(int32Buffer.prefix(sampleCount)).map {
                            Float($0) / Float(Int32.max)
                        }
                    }
                }
            }
        default:
            throw AudioFileError.invalidFormat("Unsupported audio format: \(dataFormat.mFormatID)")
        }

        // If the audio is stereo or multi-channel, convert to mono by averaging channels
        if dataFormat.mChannelsPerFrame > 1 {
            let channelCount = Int(dataFormat.mChannelsPerFrame)
            let frameCount = floatArray.count / channelCount
            var monoArray = [Float](repeating: 0.0, count: frameCount)

            for frame in 0..<frameCount {
                var sum: Float = 0.0
                for channel in 0..<channelCount {
                    let index = frame * channelCount + channel
                    if index < floatArray.count {
                        sum += floatArray[index]
                    }
                }
                monoArray[frame] = sum / Float(channelCount)
            }

            floatArray = monoArray
        }

        return (floatArray, Double(dataFormat.mSampleRate))
    }

    /// Save audio data to a file
    /// - Parameters:
    ///   - audioData: The audio data to save
    ///   - url: The URL where the audio file should be saved
    ///   - sampleRate: The sample rate of the audio data
    public static func saveAudioFile(audioData: [Float], to url: URL, sampleRate: Double) throws {
        // Create the audio format
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        // Create the audio file
        var audioFile: AudioFileID?
        var status = AudioFileCreateWithURL(
            url as CFURL,
            kAudioFileWAVEType,
            &audioFormat,
            .eraseFile,
            &audioFile
        )

        guard status == noErr, let audioFile = audioFile else {
            throw AudioFileError.writeError("Failed to create audio file: \(status)")
        }

        defer {
            AudioFileClose(audioFile)
        }

        // Write the audio data
        var bytesToWrite = UInt32(audioData.count * MemoryLayout<Float>.size)
        status = AudioFileWriteBytes(
            audioFile,
            false,
            0,
            &bytesToWrite,
            audioData
        )

        guard status == noErr else {
            throw AudioFileError.writeError("Failed to write audio data: \(status)")
        }
    }
}
