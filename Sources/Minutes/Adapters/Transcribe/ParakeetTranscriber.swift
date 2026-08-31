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

    func transcribe(url: URL, model: String) async throws -> [TranscribedSegment] {
        let manager = try await MLEngine.shared.parakeet(version: ParakeetModel.version(for: model))
        do {
            let result = try await manager.transcribe(url)
            guard let timings = result.tokenTimings, !timings.isEmpty else {
                // No timings: still return the text as one span rather than lose it.
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return [] }
                return [TranscribedSegment(start: 0, end: result.duration, text: text)]
            }
            return Self.segments(from: timings)
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
            buffer = []
            guard !text.isEmpty else { return }
            out.append(TranscribedSegment(start: first.startTime, end: last.endTime, text: text))
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
