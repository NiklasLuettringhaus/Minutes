import Foundation

/// AD-39 / FR-77: what a Note says about *which Meeting it is*, and nothing else.
///
/// AD-9 forbids parsing a Note back into state, and that rule stands. The line it
/// never had to draw is between a file's **identity** and its **content**: reading
/// which Meeting a file belongs to is not reading the meeting out of it. This type
/// is where that line is enforced, and it is enforced by the type rather than by
/// discipline — there is no field here that could hold a title, a summary or an
/// utterance, so a future change that wanted one would have to alter this file and
/// argue with this comment.
///
/// Why it exists at all: `Meeting.noteFilename` used to be the only link between a
/// Meeting and its Note, so the link was a *name* — the one property of a file a
/// user is most likely to change. A rename in Finder severed it permanently, and
/// the app's own remedy for the break made it unrecoverable.
struct NoteIdentity: Equatable, Sendable {
    /// The Meeting's ID, stamped by `NoteWriter` since increment 7.
    let meetingID: String?
    /// The Meeting's start time. Present in every Note ever written, which is what
    /// makes the fifteen Notes that predate `meetingID` identifiable at all.
    let startedAt: Date?
    /// Whether the frontmatter claims Minutes wrote this file.
    let writtenByMinutes: Bool

    /// True when this file carries enough for the app to claim it (AD-43).
    ///
    /// A Markdown file the user wrote themselves has none of these, so it is never
    /// listed, never linked automatically and never touched. The Notes Folder is
    /// the user's folder; an app that enumerates a user's unrelated documents has
    /// overstepped.
    var isMinutesNote: Bool {
        meetingID != nil || (writtenByMinutes && startedAt != nil)
    }

    /// Whether this file is that Meeting's Note.
    ///
    /// The ID is preferred and decides on its own. `startedAt` is the fallback for
    /// a Note written before the stamp existed, and it is compared with a one-second
    /// tolerance because the frontmatter's ISO string is second-precision
    /// (`withInternetDateTime`) while `Meeting.startedAt` is not — a real Note reads
    /// `2026-09-03T07:30:38Z` against a record holding fractional seconds.
    func matches(_ m: Meeting) -> Bool {
        if let id = meetingID { return id == m.id }
        guard writtenByMinutes, let t = startedAt else { return false }
        return abs(t.timeIntervalSince(m.startedAt)) < 1
    }

    /// Reads the YAML frontmatter block and stops at its closing `---`.
    ///
    /// Returns nil when the text does not open with `---`, so an arbitrary Markdown
    /// document is rejected rather than scanned. Only three keys are read; every
    /// other line in the block is ignored, and nothing past the block is looked at.
    static func parse(frontmatterOf text: String) -> NoteIdentity? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        lines.removeFirst()

        var id: String?
        var started: Date?
        var byMinutes = false
        var closed = false

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "---" { closed = true; break }
            guard let colon = t.firstIndex(of: ":") else { continue }
            let key = String(t[t.startIndex..<colon])
            let raw = unquote(String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            switch key {
            case Key.meetingID: if !raw.isEmpty { id = raw }
            case Key.startedAt: started = Self.date(from: raw)
            case Key.generatedBy: byMinutes = raw.hasPrefix("Minutes")
            default: continue
            }
        }
        // An unterminated block is not frontmatter. Without this a 4 KB prose file
        // whose first line happens to be `---` would be read as a Note's header.
        guard closed else { return nil }
        return NoteIdentity(meetingID: id, startedAt: started, writtenByMinutes: byMinutes)
    }

    /// The frontmatter keys this type knows about. Named here so `NoteWriter` and
    /// the reader cannot drift — one writes them, one reads them, neither spells
    /// them itself.
    enum Key {
        static let meetingID = "minutes_id"
        static let startedAt = "started_at"
        static let generatedBy = "generated_by"
    }

    /// The number of bytes worth reading to find a frontmatter block.
    ///
    /// Measured, not guessed: the longest frontmatter among the fifteen real Notes
    /// is 753 bytes — a fourteen-speaker meeting, where the `participants`,
    /// `in_room` and `remote` lists carry the length. 4 KB leaves five times that
    /// headroom while keeping the read bounded, which matters because one real Note
    /// is 72 KB and a folder may hold hundreds.
    static let headBytes = 4096

    // MARK: - Scalars

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        return String(s.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// `NoteWriter` emits `.withInternetDateTime`; both forms are accepted because
    /// a hand-edited Note is a file the app must still be able to identify.
    private static func date(from s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
