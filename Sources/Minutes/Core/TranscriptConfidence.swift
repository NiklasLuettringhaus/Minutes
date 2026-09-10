import Foundation

/// What the Transcription Model said about its own certainty (FR-95, AD-52).
///
/// **Deliberately not a rating, and the product may not render it as one.** The
/// two engines report different quantities — Whisper a mean token
/// log-probability, Parakeet a per-token score — on scales that were never
/// calibrated against transcription accuracy on this corpus or any other. Two
/// numbers that are not the same quantity must not be shown side by side as if a
/// reader could compare them, and a single number must not be shown as if it
/// meant a probability of being right.
///
/// What it *is* good for is the thing FR-95 asks for: telling one Meeting from
/// another without re-running transcription, and giving AD-46's trust gate
/// something to consult that is finer than a boolean.
struct TranscriptConfidence: Equatable, Sendable, Codable {
    /// Word-weighted mean over the Utterances that carry one, 0...1.
    var mean: Double
    /// Words the engine scored.
    var wordsScored: Int
    /// Words in the Transcript altogether.
    var wordsTotal: Int

    /// How much of the Transcript the figure is drawn from. A mean over 4% of the
    /// words says almost nothing about the other 96%, and a surface that hid that
    /// would be inviting the reader to over-read it.
    var coverage: Double {
        wordsTotal > 0 ? Double(wordsScored) / Double(wordsTotal) : 0
    }
}
