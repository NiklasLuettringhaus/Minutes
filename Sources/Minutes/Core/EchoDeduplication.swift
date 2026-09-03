import Foundation

/// The Transcript's half of the echo rule: drop a Mic Stream Utterance only when
/// the audio *and* the text agree that it repeats the far end (FR-90, AD-47).
///
/// **Why two signals and not one.** The audio test alone was calibrated at 86%
/// recall for **13% of the user's own words** — the user talking over the far
/// end, deleted along with the echo. That is an acceptable error rate for
/// Diarization, which is robust to missing frames, and an unacceptable one for a
/// transcript, which is a record of what somebody said.
///
/// Requiring text agreement removes the cost entirely, **by construction**: this
/// can only ever drop an Utterance that substantially repeats one already held on
/// the System Stream, so nothing unique can be lost. What it gives up is recall
/// on partial overlaps, where echo and a room voice fall inside one Utterance;
/// those survive, and are counted in the residual rather than hidden.
///
/// **The evidence that the text half is sound is indirect and worth stating.**
/// Its label is the ground truth, so its precision cannot be measured against
/// itself. Two things stand in for that: on the nine recordings that fail the
/// recording gate, seven contain **literally zero** coincidentally duplicated
/// words (the other two, 44 and 7); and of the words this would remove on the
/// three affected recordings, **98% sit in Utterances longer than two words**.
/// Coincidental agreement is short — someone in the room saying "yeah" as the
/// far end says "yeah". Verbatim repetition of a multi-word sentence at the same
/// instant is the loudspeaker.
enum EchoDeduplication {

    /// How alike two Utterances must read before one is called a repeat of the
    /// other.
    ///
    /// **0.6**, carried over from the calibration, which measured duplicate
    /// counts of 906, 3,918 and 1,498 words at this value on the three affected
    /// recordings and 0–44 on the nine clean ones.
    static let textSimilarityThreshold = 0.6

    /// One Utterance, reduced to what this decision needs.
    struct Span: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String

        func overlaps(_ other: Span) -> Bool {
            start < other.end && other.start < end
        }
    }

    /// What the rule did, so the Meeting can report it instead of asserting it.
    struct Outcome: Equatable, Sendable {
        /// Indices into the mic spans that were dropped.
        var droppedIndices: [Int]
        var droppedWords: Int
        var retainedWords: Int
        /// Mic words still repeating a System Stream Utterance after the rule
        /// ran — the partial overlaps the Utterance-level test cannot reach.
        var residualDuplicateWords: Int

        var droppedProportion: Double {
            let total = droppedWords + retainedWords
            return total > 0 ? Double(droppedWords) / Double(total) : 0
        }
    }

    /// Applies the rule.
    ///
    /// `echoFlagged` is the audio half — normally `analysis.isMostlyEcho(from:to:)`.
    /// It is injected rather than read from an `EchoAnalysis` so the two halves
    /// can be tested apart, and so a caller can prove the text half never fires
    /// on its own.
    static func apply(mic: [Span],
                      system: [Span],
                      echoFlagged: (Span) -> Bool,
                      similarityThreshold: Double = Self.textSimilarityThreshold) -> Outcome {
        var dropped: [Int] = []
        var droppedWords = 0
        var retainedWords = 0
        var residual = 0

        for (index, span) in mic.enumerated() {
            let words = tokens(span.text)
            guard !words.isEmpty else { continue }
            let repeatsFarEnd = system.contains { other in
                span.overlaps(other)
                    && similarity(words, tokens(other.text)) >= similarityThreshold
            }

            // Both halves must agree. The order of the checks is deliberate:
            // the text test is what makes this safe, so it is never skipped.
            if repeatsFarEnd, echoFlagged(span) {
                dropped.append(index)
                droppedWords += words.count
            } else {
                retainedWords += words.count
                if repeatsFarEnd { residual += words.count }
            }
        }
        return Outcome(droppedIndices: dropped,
                       droppedWords: droppedWords,
                       retainedWords: retainedWords,
                       residualDuplicateWords: residual)
    }

    // MARK: - Text

    /// Lowercased word tokens, punctuation removed.
    ///
    /// Deliberately not the transcript normaliser used for filler stripping
    /// (FR-31): this compares two machine transcriptions of *the same audio*,
    /// so the engine's own inconsistencies — punctuation, capitalisation — are
    /// the only noise that needs removing.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Sørensen–Dice similarity over token multisets, 0...1.
    ///
    /// Multiset rather than set, so "yeah yeah yeah" against "yeah" does not
    /// score 1.0. Token-level rather than character-level: two transcriptions of
    /// the same sentence differ by whole words, and character overlap would
    /// score two unrelated English sentences suspiciously high.
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for token in a { counts[token, default: 0] += 1 }
        var shared = 0
        for token in b {
            if let n = counts[token], n > 0 {
                counts[token] = n - 1
                shared += 1
            }
        }
        return 2.0 * Double(shared) / Double(a.count + b.count)
    }
}
