import Foundation

/// Strips speech disfluencies from a transcript.
///
/// Borrowed from FluidVoice, and it earns its place more in a meeting transcript
/// than in dictation: nobody rereads their own dictation, but a 40-minute
/// meeting transcript is unreadable when every other clause opens with "um, uh,
/// so, like".
///
/// Matched on whole words only — "um" must never be cut out of "number" — and
/// the punctuation left behind is repaired, because "So, um, we decided" turning
/// into "So, , we decided" is worse than leaving the filler in.
enum FillerWords {

    /// Defaults cover the disfluencies Whisper actually emits. Editable by the user.
    static let defaults: [String] = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "er", "err", "erm", "ah", "ahh",
        "eh", "ehh", "hmm", "hm", "mm", "mmm", "urm", "ugh", "uhm", "mhm",
    ]

    /// Removes filler words, then repairs the spacing and punctuation.
    static func strip(_ text: String, words: [String]) -> String {
        guard !words.isEmpty, !text.isEmpty else { return text }

        let escaped = words
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .sorted { $0.count > $1.count }          // longest first: "umm" before "um"
            .joined(separator: "|")

        // A filler plus any comma that only existed to separate it.
        let pattern = "(?i)\\b(?:\(escaped))\\b\\s*,?"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }

        var s = re.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")

        s = repair(s)
        // If stripping left nothing but punctuation, the line was pure filler.
        let bare = s.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        return bare.isEmpty ? "" : s
    }

    /// Collapses the gaps and stray punctuation removal leaves behind.
    static func repair(_ input: String) -> String {
        var s = input
        let fixes: [(String, String)] = [
            ("\\s{2,}", " "),          // doubled spaces
            ("\\s+([,.!?;:])", "$1"),  // space before punctuation
            ("([,;:])\\s*([,.!?;:])", "$2"),  // stacked punctuation
            ("^[\\s,;:]+", ""),        // leading comma left by a stripped opener
            ("\\(\\s*\\)", ""),        // emptied parentheses
        ]
        for (p, r) in fixes {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Re-capitalise when a stripped opener exposed a lowercase word.
        if let f = s.first, f.isLowercase {
            s = f.uppercased() + s.dropFirst()
        }
        return s
    }
}
