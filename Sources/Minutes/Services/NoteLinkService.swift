import Foundation

/// What the app knows about where a Meeting's Note is (AD-39, FR-78).
///
/// There is no `broken` case here on purpose. Broken exists for one turn — between
/// an existence check failing and reconciliation answering — and it is never a
/// state the user sees. Rendering it as *"your note is missing"* was the original
/// defect: a claim the app had not yet earned, made while the user was looking at
/// the file in Finder.
enum NoteLinkState: Equatable, Sendable {
    /// A file is there. `userNamed` is true when its name is the user's rather
    /// than the one the app derived (AD-40).
    case linked(url: URL, userNamed: Bool)
    /// More than one file claims this Meeting. The app names them and picks none.
    case ambiguous([URL])
    /// Minutes looked in the folder and found nothing.
    case notFound
    /// No folder is configured, so nothing has been looked for. Distinct from
    /// `notFound`, because "I could not look" and "I looked and it is gone" are
    /// different statements and only one of them is about the user's files.
    case unknown

    /// The only thing Reveal and Open may be conditioned on.
    ///
    /// They used to be conditioned on *a filename is recorded*, which is why
    /// `Open in Editor` handed the user macOS's own "the file does not exist"
    /// alert — the defect reported as "it says file not found".
    var locatedURL: URL? {
        if case .linked(let url, _) = self { return url }
        return nil
    }

    var isResolved: Bool { locatedURL != nil }
}

/// Reconciliation policy: when to look, what to persist, what to publish.
///
/// A service rather than an adapter because these are decisions, not I/O: no view
/// and no adapter gets to choose when a folder is scanned or what a failed scan
/// writes to the record.
@MainActor
enum NoteLinkService {

    static var locator: NoteLocating = NoteLocator()
    /// Injectable so a test can assert what reconciliation *persists* against a
    /// temp-rooted store rather than against the user's real library.
    static var store: MeetingStore = .shared

    /// Resolves every complete Meeting's Note Link.
    ///
    /// **Cheap when nothing is broken.** One `stat` per Meeting that claims a
    /// Note, and the folder is not read at all unless one of those fails. That is
    /// the answer to PRD §13 Q12 — by mechanism rather than by measurement, since
    /// the expensive path only runs in the case where the app is about to make a
    /// claim about the user's folder and had better be right.
    ///
    /// A single positive identification is persisted, because *this file is this
    /// Meeting's Note* is durable. Ambiguity and absence persist nothing: a folder
    /// that is temporarily unreachable must not be able to write a false claim
    /// into history.
    static func reconcile(_ meetings: [Meeting], in folder: URL?) async -> [String: NoteLinkState] {
        guard let folder else {
            return meetings.reduce(into: [:]) { out, m in
                if m.isComplete, m.noteFilename != nil { out[m.id] = .unknown }
            }
        }
        let fm = FileManager.default
        var out: [String: NoteLinkState] = [:]

        for m in meetings {
            guard m.isComplete, let recorded = m.noteFilename else { continue }
            let at = folder.appendingPathComponent(recorded)
            if fm.fileExists(atPath: at.path) {
                await backfillWrittenName(for: m, itsOwnName: recorded)
                out[m.id] = .linked(url: at, userNamed: !m.appOwnsNoteName(recorded))
                continue
            }
            // Only now is the folder read.
            switch (try? locator.locate(meeting: m, in: folder)) ?? .notFound {
            case .located(let url):
                // Computed *before* the write, from the copy in hand. Reading it
                // back off `m` after `persist` gave the stale value, so the state
                // reported and the state persisted disagreed — the reported one
                // said the name was the user's while the writer said it was the
                // app's and would have renamed the file back. Found by running
                // `--doctor` against the real library after a hand rename.
                let appsOwnName = m.noteFilenameWritten ?? m.noteFilename
                await persist(url, for: m)
                out[m.id] = .linked(url: url, userNamed: url.lastPathComponent != appsOwnName)
            case .ambiguous(let urls):
                out[m.id] = .ambiguous(urls)
            case .notFound:
                out[m.id] = .notFound
            }
        }
        return out
    }

    /// AD-40's migration, done where the information exists.
    ///
    /// A record written before increment 7 has no `noteFilenameWritten`, so
    /// nothing can tell whose name the file carries. Two places know the answer
    /// and only for a moment:
    ///
    /// - a **healthy** link means the recorded name is still on disk, so that name
    ///   is the one the app wrote;
    /// - a **relink** means the recorded name is the one the app wrote, and the
    ///   name just found is the user's.
    ///
    /// Backfilling here is what makes the rule work for the fifteen records that
    /// predate it. Without it a legacy record's renamed file would be renamed
    /// straight back by the next retitle — found by running `--doctor` against the
    /// real library after renaming a note by hand, where the reported state and
    /// the writer's own test disagreed.
    private static func backfillWrittenName(for m: Meeting, itsOwnName name: String) async {
        guard m.noteFilenameWritten == nil else { return }
        _ = try? await store.update(id: m.id) { $0.noteFilenameWritten = name }
    }

    /// Files Minutes wrote that no Meeting claims (FR-82).
    static func unclaimed(_ meetings: [Meeting], in folder: URL?) async -> [UnclaimedNote] {
        guard let folder else { return [] }
        let dismissed = Preferences.shared.dismissedUnclaimedNotes
        let found = (try? locator.unclaimed(meetings: meetings, in: folder)) ?? []
        return found.filter { !dismissed.contains($0.filename) }
    }

    /// One Meeting's link, resolved on demand.
    ///
    /// Used where an answer is needed *now* rather than at the next reload — most
    /// importantly by the delete confirmation, which must describe the filesystem
    /// and not the record (FR-40 as amended).
    static func resolve(_ meeting: Meeting, in folder: URL) async -> NoteLinkState {
        if let recorded = meeting.noteFilename {
            let at = folder.appendingPathComponent(recorded)
            if FileManager.default.fileExists(atPath: at.path) {
                await backfillWrittenName(for: meeting, itsOwnName: recorded)
                return .linked(url: at, userNamed: !meeting.appOwnsNoteName(recorded))
            }
        }
        switch (try? locator.locate(meeting: meeting, in: folder)) ?? .notFound {
        case .located(let url):
            let appsOwnName = meeting.noteFilenameWritten ?? meeting.noteFilename
            await persist(url, for: meeting)
            return .linked(url: url, userNamed: url.lastPathComponent != appsOwnName)
        case .ambiguous(let urls): return .ambiguous(urls)
        case .notFound: return .notFound
        }
    }

    /// The file a destructive action will actually touch, or nil if there is none.
    static func resolvedNoteURL(for meeting: Meeting, in folder: URL) async -> URL? {
        await resolve(meeting, in: folder).locatedURL
    }

    /// Points a Meeting at a file the user chose (FR-79).
    ///
    /// Records the file's current bytes as the digest baseline, so adopting a file
    /// Minutes did not write does not immediately read as a conflict — the moment
    /// the user was warned about is the app's *next* rewrite, not this link.
    static func adopt(_ url: URL, for meetingID: String) async {
        let digest = (try? Data(contentsOf: url)).map(NoteWriter.digest)
        _ = try? await store.update(id: meetingID) { m in
            m.noteFilename = url.lastPathComponent
            m.noteDigest = digest
            // Left as it was — or, for a record that has none, set to a value that
            // cannot equal the chosen name. Either way the comparison in
            // `noteIsUserNamed` now says the user owns this name, which is true:
            // they picked the file by hand.
            if m.noteFilenameWritten == nil { m.noteFilenameWritten = "" }
        }
    }

    private static func persist(_ url: URL, for meeting: Meeting) async {
        guard url.lastPathComponent != meeting.noteFilename else { return }
        // The name being replaced is the name the app wrote — this is the one
        // moment a legacy record can learn it, so it is recorded here rather than
        // guessed later.
        let appsOwnName = meeting.noteFilenameWritten ?? meeting.noteFilename
        _ = try? await store.update(id: meeting.id) {
            $0.noteFilename = url.lastPathComponent
            $0.noteFilenameWritten = appsOwnName
        }
    }
}
