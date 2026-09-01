import Foundation
import WhisperKit
import SpeakerKit

/// AD-28: an adapter, and the only place in the identification path that knows
/// Apple exists.
///
/// It reuses the Diarizer's own machinery rather than adding a second embedding
/// stack: `diarize()` already clusters a recording by speaker and returns a
/// centroid per cluster, which is exactly a voice fingerprint. Running it on a
/// deliberate single-speaker sample is a slightly unusual use of a diarizer, and
/// it buys the one thing enrolment genuinely needs beyond an embedding — an
/// answer to "was there more than one person talking?", which a bare embedder
/// could not give.
///
/// No new dependency. `argmax-oss-swift` 1.1.0 is already linked for
/// transcription and diarization, and the models are already fetched lazily on
/// first `diarize()`, so a machine that has completed one meeting can enrol with
/// no network.
struct SpeakerKitVoiceEmbedder: VoiceEmbedding {

    /// Stored beside every fingerprint this produces (AD-29). The model version
    /// is part of the identity, because a pyannote v4 vector and a hypothetical
    /// v5 vector are not comparable and a bare "speakerkit" would hide that.
    ///
    /// Declared `static` and referenced by name from `Pipeline`, which tags the
    /// diarizer's own per-cluster centroids with it. Those centroids come from the
    /// same models as this embedder's, so the tag is correct — but only because
    /// they share one declaration. Two types each writing the string would agree
    /// today and diverge the first time either changed, and AD-29's whole purpose
    /// is that such a divergence must be *detectable* rather than silent.
    static let producerID = "speakerkit/pyannote-v4-community-1"
    var producer: String { Self.producerID }

    func embed(url: URL) async throws -> VoiceEmbeddingResult {
        let box = try await MLEngine.shared.speakerKit()

        let samples: [Float]
        do {
            // 16 kHz mono, which is what the recording already is — the writer
            // stores that rate, so this is a read rather than a resample.
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        } catch {
            throw MinutesError.voiceSampleUnreadable(error.localizedDescription)
        }
        // Under ~1 s the diarizer returns nothing useful, and a fingerprint from
        // it would be noise wearing a person's name.
        guard samples.count > 16_000 else {
            throw MinutesError.voiceSampleTooShort(seconds: Double(samples.count) / 16_000)
        }

        let result: DiarizationResult
        do {
            result = try await box.kit.diarize(audioArray: samples, options: nil)
        } catch {
            throw MinutesError.voiceEmbeddingFailed(error.localizedDescription)
        }

        // Speaking time per cluster. The dominant speaker is the one who spoke
        // longest, not the one who spoke first — a "hello" from the wrong side of
        // the room must not become the fingerprint.
        var seconds: [Int: TimeInterval] = [:]
        for seg in result.segments {
            guard let id = seg.speaker.speakerId else { continue }
            seconds[id, default: 0] += TimeInterval(seg.endTime - seg.startTime)
        }
        let totalSpeech = seconds.values.reduce(0, +)
        guard let dominant = seconds.max(by: { $0.value < $1.value })?.key,
              totalSpeech > 0 else {
            throw MinutesError.voiceSampleSilent
        }
        guard let vector = result.speakerCentroidEmbeddings[dominant], !vector.isEmpty else {
            throw MinutesError.voiceEmbeddingFailed(
                "The recording was analysed but produced no usable voice fingerprint.")
        }

        // Never log the vector, and never log its values (PRD §9.1). The shape
        // and the counts are diagnosable; the contents are the sensitive part.
        Log.transcribe.info(
            "voice embedded voices=\(seconds.count) speech=\(totalSpeech, format: .fixed(precision: 1))s dims=\(vector.count)")

        return VoiceEmbeddingResult(
            fingerprint: VoiceFingerprint(vector: vector, producer: producer),
            voicesFound: seconds.count,
            speechSeconds: totalSpeech,
            dominantShare: seconds[dominant]! / totalSpeech)
    }
}
