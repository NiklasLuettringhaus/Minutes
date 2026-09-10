import Foundation
import AVFoundation
import FluidAudio

/// NVIDIA Parakeet TDT via CoreML, as a second transcription engine.
///
/// This is why FluidVoice feels so much faster: Parakeet runs roughly an order of
/// magnitude quicker than Whisper on Apple Silicon. It sits behind the same
/// `Transcribing` port as WhisperKit, so the pipeline is unchanged — which is the
/// payoff for having put a port there in the first place (AD-12's pattern).
///
/// The one real difference: Parakeet returns a single text blob plus per-token
/// timings, where Whisper returns ready-made segments. So segments are rebuilt
/// from token timings here.
struct ParakeetTranscriber: Transcribing {

    // Inverse Text Normalization (readability: "two thirty" -> "2:30", "twenty
    // twenty five" -> "2025") was evaluated for this path and deliberately NOT
    // wired in. FluidAudio 0.15.6 ships `TextNormalizer.shared`, whose ITN runs
    // on the native NemoTextProcessing xcframework we already link — so it would
    // actually transform our output, this is not a no-op. It is left out because:
    //
    //   - The ITN entry points (`nemo_normalize`, `nemo_normalize_sentence`) take
    //     no language and have no `_lang` variant — only the TN/TTS direction does
    //     (nemo_text_processing.h). ITN here is English-only, and its false-positive
    //     guard is English NLTagger part-of-speech tagging. Our default is now v3,
    //     which is multilingual, and this is a Danish company — a language the
    //     engine does not support at all (its seven are EN, DE, ES, FR, HI, JA, ZH).
    //     An English number/date/URL grammar run over Danish or German meeting
    //     speech rewrites the wrong spans.
    //   - It is a lossy, irreversible edit of the transcript whose effect on
    //     meeting-transcript readability/WER has never been MEASURED, and this
    //     codebase does not ship quality claims the harness cannot support
    //     (investigation-transcription-quality-2026-09-03 §2, recommendation #2).
    //
    // To adopt it as a measured next step: gate on the recognised language (English
    // only until FluidAudio exposes a multilingual ITN), add an ITN readability
    // score to Scripts/eval against the AMI references, and apply it per finalized
    // segment text in `segments(from:)` below — never to `result.text`, which after
    // rewriting no longer maps to the token timings the segments are built from.

    func transcribe(url: URL, model: String) async throws -> Transcription {
        let manager = try await MLEngine.shared.parakeet(version: ParakeetModel.version(for: model))
        do {
            let result = try await manager.transcribe(url)
            guard let timings = result.tokenTimings, !timings.isEmpty else {
                // No timings: still return the text as one span rather than lose it.
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return Transcription(segments: []) }
                return Transcription(segments: [
                    TranscribedSegment(start: 0, end: result.duration, text: text,
                                       confidence: Double(result.confidence))
                ])
            }
            return Transcription(segments: Self.segments(from: timings))
        } catch {
            throw MinutesError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Groups tokens into readable segments: break on sentence-ending punctuation,
    /// on a pause longer than `gap`, or when a segment gets long enough that it
    /// would be unwieldy in a transcript.
    static func segments(from timings: [TokenTiming],
                         gap: TimeInterval = 0.7,
                         maxSeconds: TimeInterval = 18) -> [TranscribedSegment] {
        var out: [TranscribedSegment] = []
        var buffer: [TokenTiming] = []

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let text = buffer.map(\.token).joined()
                .replacingOccurrences(of: "▁", with: " ")   // SentencePiece word boundary
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // FR-95. Parakeet reports a confidence per token; a segment's is the
            // mean over the tokens it was built from. The port carried none until
            // increment 10, so the adapter was computing this and dropping it.
            let scores = buffer.map { Double($0.confidence) }.filter { $0.isFinite }
            let confidence = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            buffer = []
            guard !text.isEmpty else { return }
            out.append(TranscribedSegment(start: first.startTime, end: last.endTime,
                                          text: text, confidence: confidence))
        }

        for t in timings {
            if let last = buffer.last, t.startTime - last.endTime > gap { flush() }
            if let first = buffer.first, t.endTime - first.startTime > maxSeconds { flush() }
            buffer.append(t)
            let trimmed = t.token.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") { flush() }
        }
        flush()
        return out.sorted { $0.start < $1.start }
    }
}

/// The Parakeet variants offered, and where their models live.
enum ParakeetModel {
    /// Our identifiers. Prefixed so `Preferences.model` can carry either engine.
    static let v3 = "parakeet-tdt-0.6b-v3"
    static let v2 = "parakeet-tdt-0.6b-v2-en"

    static func isParakeet(_ id: String) -> Bool { id.hasPrefix("parakeet-") }

    static func version(for id: String) -> AsrModelVersion {
        id == v2 ? .v2 : .v3
    }

    /// Kept under our own models directory, for the same reason as WhisperKit:
    /// the library's default would scatter downloads elsewhere.
    static func directory(for id: String) -> URL {
        ModelStorage.base
            .appendingPathComponent("parakeet", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    static func isDownloaded(_ id: String) -> Bool {
        let dir = directory(for: id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        return AsrModels.modelsExist(at: dir, version: version(for: id))
    }

    static func removeDownload(_ id: String) throws {
        try FileManager.default.removeItem(at: directory(for: id))
    }
}
