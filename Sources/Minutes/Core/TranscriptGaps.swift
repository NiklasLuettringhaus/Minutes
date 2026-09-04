import Foundation

/// A stretch of a recording that produced no usable text (FR-96, AD-52).
///
/// **A gap is not silence, and the whole requirement is that distinction.**
/// "Nothing was said here" and "we could not make out what was said here" are
/// different statements about the same seconds, and only the second one means a
/// summary built on the transcript is incomplete. Conflating them is how the
/// failure hides: an interval that produces no Utterance looks exactly like a
/// pause.
struct TranscriptGap: Equatable, Sendable, Codable {
    var start: TimeInterval
    var end: TimeInterval
    /// Which Stream it is a gap in. A gap on the far end and a gap in the room
    /// are different problems for a reader.
    var stream: StreamKind

    var duration: TimeInterval { max(0, end - start) }
}

/// Finding them.
///
/// The engines cannot help here, and it is worth saying why rather than leaving
/// the next reader to discover it. Whisper's own rejection signals —
/// `[BLANK_AUDIO]`, a `noSpeechProb` over 0.6, a whole-segment hallucination —
/// all mean *silence*, which is the opposite of a gap. Parakeet reports nothing
/// at all for an interval it produced no tokens for. So the only evidence that
/// separates the two is the **audio**: signal was present and no Utterance
/// covers it.
enum TranscriptGaps {

    /// The shortest run worth reporting.
    ///
    /// **2 seconds.** Not tuned against recordings — it is the length below which
    /// the statement stops being useful: an Utterance boundary routinely leaves a
    /// second of speech tail uncovered, and reporting those would put dozens of
    /// meaningless marks in a transcript and teach a reader to ignore all of
    /// them, including the one that mattered. Two seconds of unrecognised speech
    /// is about six words.
    static let minimumSeconds: TimeInterval = 2.0

    /// Share of a candidate interval that must carry signal before it counts as
    /// speech the app failed on rather than a pause.
    ///
    /// A gap that is mostly silence is a pause with a bit of noise in it.
    static let minimumActiveShare = 0.5

    /// Builds gaps from a per-frame activity mask and the intervals that *are*
    /// covered.
    ///
    /// `excluded` is subtracted from the result, and that clause is load-bearing:
    /// **Echo-excluded audio is never a gap** (FR-96). It is speech Minutes has,
    /// once, on the other Stream — reporting it as unreadable would present a
    /// working feature as a failure, and on the worst real recording that would
    /// mean claiming to have lost 45% of the microphone.
    static func find(active: [Bool],
                     frameSeconds: TimeInterval,
                     covered: [ClosedRange<TimeInterval>],
                     excluded: [ClosedRange<TimeInterval>] = [],
                     stream: StreamKind,
                     minimumSeconds: TimeInterval = Self.minimumSeconds) -> [TranscriptGap] {
        guard !active.isEmpty, frameSeconds > 0 else { return [] }

        // Mark every frame that is spoken for, by an Utterance or by exclusion.
        var spokenFor = [Bool](repeating: false, count: active.count)
        for range in covered + excluded {
            let first = max(0, Int(range.lowerBound / frameSeconds))
            let last = min(active.count - 1, Int(range.upperBound / frameSeconds))
            guard first <= last else { continue }
            for i in first...last { spokenFor[i] = true }
        }

        var out: [TranscriptGap] = []
        var runStart: Int?
        func close(at end: Int) {
            guard let s = runStart else { return }
            runStart = nil
            let seconds = Double(end - s) * frameSeconds
            guard seconds >= minimumSeconds else { return }
            let activeCount = (s..<end).filter { active[$0] }.count
            guard Double(activeCount) / Double(end - s) >= minimumActiveShare else { return }
            out.append(TranscriptGap(start: Double(s) * frameSeconds,
                                     end: Double(end) * frameSeconds,
                                     stream: stream))
        }
        for i in 0..<active.count {
            if active[i], !spokenFor[i] {
                if runStart == nil { runStart = i }
            } else {
                close(at: i)
            }
        }
        close(at: active.count)
        return out
    }

    /// Total unreadable time across a set of gaps.
    static func total(_ gaps: [TranscriptGap]) -> TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }

    /// What to tell a reader, or nil when there is nothing worth saying (FR-96).
    ///
    /// Names the amount and how many places, and says plainly that the summary is
    /// built on less than the whole meeting — which is the consequence, and the
    /// only reason the sentence exists.
    static func explanation(_ gaps: [TranscriptGap]) -> String? {
        guard !gaps.isEmpty else { return nil }
        let seconds = total(gaps)
        guard seconds >= minimumSeconds else { return nil }
        let places = gaps.count == 1 ? "one place" : "\(gaps.count) places"
        let amount = seconds < 90
            ? String(format: "%.0f seconds", seconds)
            : String(format: "%.0f minutes", (seconds / 60).rounded())
        return "Minutes could not make out about \(amount) of this recording, in "
             + "\(places). That speech is missing from the transcript below, and from "
             + "anything derived from it."
    }
}
