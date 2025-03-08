import DSP
import Foundation
import Utilities

/// A class for cloning voices in real-time.
/// This class integrates the SpeakerEncoder, VoiceConverter, and Vocoder components.
@MainActor
public class VoiceCloner {
    /// The speaker encoder for extracting voice characteristics
    private let speakerEncoder: SpeakerEncoder

    /// The voice converter for transforming voice characteristics
    private let voiceConverter: VoiceConverter

    /// The vocoder for generating audio from spectrograms
    private let vocoder: Vocoder

    /// The DSP processor for audio feature extraction
    private let dsp: DSP

    /// The target speaker embedding
    private var targetEmbedding: [Float]?

    /// Initialize a new VoiceCloner
    /// - Parameters:
    ///   - speakerEncoder: The speaker encoder for extracting voice characteristics
    ///   - voiceConverter: The voice converter for transforming voice characteristics
    ///   - vocoder: The vocoder for generating audio from spectrograms
    ///   - dsp: The DSP processor for audio feature extraction
    public init(
        speakerEncoder: SpeakerEncoder = SpeakerEncoder(),
        voiceConverter: VoiceConverter = VoiceConverter(),
        vocoder: Vocoder = Vocoder(),
        dsp: DSP = DSP()
    ) {
        self.speakerEncoder = speakerEncoder
        self.voiceConverter = voiceConverter
        self.vocoder = vocoder
        self.dsp = dsp
    }

    /// Set the target voice from an audio sample
    /// - Parameters:
    ///   - audioSample: The audio sample of the target voice
    ///   - sampleRate: The sample rate of the audio
    public func setTargetVoice(audioSample: [Float], sampleRate: Double) {
        // Extract a mel spectrogram from the audio sample
        // Generate spectrogram from audio
        let spectrogram = dsp.generateSpectrogram(inputBuffer: audioSample)

        // Convert spectrogram to mel spectrogram
        let melSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)

        // Extract a speaker embedding from the mel spectrogram
        targetEmbedding = speakerEncoder.extractEmbedding(from: melSpectrogram)

        Utilities.log("Target voice set with embedding of dimension \(targetEmbedding?.count ?? 0)")
    }

    /// Clone a voice in real-time
    /// - Parameters:
    ///   - inputAudio: The input audio to clone
    ///   - sampleRate: The sample rate of the audio
    /// - Returns: The cloned audio
    public func cloneVoice(inputAudio: [Float], sampleRate: Double) -> [Float] {
        guard let targetEmbedding = targetEmbedding else {
            Utilities.log("Error: Target voice not set")
            return inputAudio
        }

        // Extract a mel spectrogram from the input audio
        // Generate spectrogram from audio
        let spectrogram = dsp.generateSpectrogram(inputBuffer: inputAudio)

        // Convert spectrogram to mel spectrogram
        let sourceSpectrogram = dsp.specToMelSpec(spectrogram: spectrogram)

        // Convert the source spectrogram to the target voice
        let convertedSpectrogram = voiceConverter.convert(
            sourceSpectrogram: sourceSpectrogram,
            targetEmbedding: targetEmbedding
        )

        // Generate audio from the converted spectrogram
        let outputAudio = vocoder.generateAudio(from: convertedSpectrogram)

        return outputAudio
    }

    /// Check if a target voice is set
    /// - Returns: True if a target voice is set, false otherwise
    public func hasTargetVoice() -> Bool {
        return targetEmbedding != nil
    }

    /// Clear the target voice
    public func clearTargetVoice() {
        targetEmbedding = nil
        Utilities.log("Target voice cleared")
    }
}
