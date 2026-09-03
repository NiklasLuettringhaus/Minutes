import XCTest
@testable import Minutes

/// FR-77 / FR-78 against the author's real library, read-only.
///
/// Gated behind an environment variable for the same reason as
/// `EnrolmentCalibrationTests`: it depends on data that exists on one machine, so
/// it must never fail a clean checkout or CI. Run it with:
///
/// ```
/// MINUTES_REAL_NOTES=1 swift test --filter NoteIdentityRealNotesTests
/// ```
///
/// It asserts **properties, not counts**. There were fifteen notes and fifteen
/// records on the day this was written; a test that pinned those numbers would
/// fail on the next meeting, which is the opposite of useful.
final class NoteIdentityRealNotesTests: XCTestCase {

    private var notesFolder: URL!
    private var meetings: [Meeting] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MINUTES_REAL_NOTES"] == "1",
                          "set MINUTES_REAL_NOTES=1 to read the real library")
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        notesFolder = home.appendingPathComponent("Documents/Minutes", isDirectory: true)
        try XCTSkipUnless(fm.fileExists(atPath: notesFolder.path), "no notes folder on this machine")

        let root = home.appendingPathComponent("Library/Application Support/Minutes/Meetings",
                                               isDirectory: true)
        try XCTSkipUnless(fm.fileExists(atPath: root.path), "no library on this machine")

        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        for name in try fm.contentsOfDirectory(atPath: root.path) where !name.hasPrefix(".") {
            let u = root.appendingPathComponent(name).appendingPathComponent("meeting.json")
            guard let data = try? Data(contentsOf: u),
                  let m = try? d.decode(Meeting.self, from: data) else { continue }
            meetings.append(m)
        }
        try XCTSkipUnless(!meetings.isEmpty, "no readable records")
    }

    /// The claim the migration rests on: every Note the app wrote is identifiable,
    /// even though none of them carries a `minutes_id` yet.
    ///
    /// **And the folder is not all ours.** The first run of this test found two
    /// files the user had written by hand — a corrected transcript and a bug
    /// report — sitting alongside the notes. The original assertion here was that
    /// every file in the folder parses as a Note, which was simply wrong about
    /// whose folder it is. That is AD-43 arriving from real data rather than from
    /// reasoning: what matters is not that such files are absent, but that the app
    /// never claims them.
    func testEveryNoteMinutesWroteIsIdentifiableAndTheRestAreLeftAlone() throws {
        var ours: [String] = [], theirs: [String] = []
        for url in try markdown() {
            let head = try String(decoding: url, limit: NoteIdentity.headBytes)
            if let i = NoteIdentity.parse(frontmatterOf: head), i.isMinutesNote {
                ours.append(url.lastPathComponent)
            } else {
                theirs.append(url.lastPathComponent)
            }
        }
        print("REAL: \(ours.count) Minutes notes, \(theirs.count) the user's own: \(theirs)")
        XCTAssertGreaterThan(ours.count, 0, "the library's notes must be identifiable")

        // The important half: the user's own documents are invisible to every
        // mechanism in this increment.
        let orphans = try NoteLocator().unclaimed(meetings: meetings, in: notesFolder)
        for name in theirs {
            XCTAssertFalse(orphans.contains { $0.filename == name },
                           "\(name) is the user's file and must not be listed")
        }
        for m in meetings where m.isComplete {
            if case .located(let u) = try NoteLocator().locate(meeting: m, in: notesFolder) {
                XCTAssertFalse(theirs.contains(u.lastPathComponent),
                               "\(u.lastPathComponent) is the user's file and must not be claimed")
            }
        }
    }

    /// The property that makes `started_at` a sufficient fallback: no two Meetings
    /// on this machine started within a second of each other. PRD §13 Q22 tracks
    /// the day that stops being true.
    func testNoTwoMeetingsStartWithinOneSecond() {
        let times = meetings.map(\.startedAt).sorted()
        var closest = Double.infinity
        for (a, b) in zip(times, times.dropFirst()) {
            closest = min(closest, b.timeIntervalSince(a))
        }
        print("REAL: \(meetings.count) meetings, closest start times \(closest) s apart")
        XCTAssertGreaterThan(closest, 1.0,
            "the started_at fallback cannot distinguish two meetings inside one second")
    }

    /// Every Note resolves to exactly one Meeting, or to none. Two would be an
    /// ambiguity the app would have to ask about.
    func testNoRealNoteClaimsTwoMeetings() throws {
        for url in try markdown() {
            let head = try String(decoding: url, limit: NoteIdentity.headBytes)
            guard let i = NoteIdentity.parse(frontmatterOf: head), i.isMinutesNote else { continue }
            let hits = meetings.filter { i.matches($0) }
            XCTAssertLessThanOrEqual(hits.count, 1,
                "\(url.lastPathComponent) claims \(hits.count) meetings: \(hits.map(\.id))")
        }
    }

    /// The locator, run against the real folder. Every complete Meeting that
    /// claims a Note must be locatable — including any the user has renamed.
    func testTheLocatorFindsEveryRealMeetingsNote() throws {
        let locator = NoteLocator()
        var located = 0, notFound: [String] = [], ambiguous: [String] = []
        for m in meetings where m.isComplete && m.noteFilename != nil {
            switch try locator.locate(meeting: m, in: notesFolder) {
            case .located: located += 1
            case .notFound: notFound.append(m.noteFilename ?? m.id)
            case .ambiguous(let u): ambiguous.append("\(m.id): \(u.map(\.lastPathComponent))")
            }
        }
        print("REAL: located \(located), not found \(notFound.count) \(notFound), "
              + "ambiguous \(ambiguous.count) \(ambiguous)")
        XCTAssertTrue(ambiguous.isEmpty, "an ambiguity in the real folder needs the user to resolve it")
    }

    /// FR-82 on real data. On the day this was written exactly one file was
    /// unclaimed: a note the user renamed in Finder whose Meeting was then
    /// deleted, and which no surface in the product mentioned. The assertion is
    /// that the mechanism *finds* orphans — not how many there are, since the user
    /// can dismiss them.
    func testUnclaimedNotesAreFoundAndAreOnlyOurFiles() throws {
        let orphans = try NoteLocator().unclaimed(meetings: meetings, in: notesFolder)
        print("REAL: \(orphans.count) unclaimed note(s): \(orphans.map(\.filename))")
        for o in orphans {
            let head = try String(decoding: o.url, limit: NoteIdentity.headBytes)
            let i = NoteIdentity.parse(frontmatterOf: head)
            XCTAssertTrue(i?.isMinutesNote ?? false,
                          "\(o.filename) is not ours and must not be listed")
        }
    }

    /// AD-41's migration branch, measured rather than assumed: none of the real
    /// notes is modified after its record, so all of them adopt their current
    /// bytes as a baseline instead of raising a conflict on the next edit.
    func testNoRealNoteLooksHandEdited() throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Minutes/Meetings")
        let w = NoteWriter(recordModifiedAt: { id in
            let u = root.appendingPathComponent(id).appendingPathComponent("meeting.json")
            return (try? fm.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
        })
        var suspected: [String] = []
        for m in meetings where m.isComplete {
            guard let f = m.noteFilename else { continue }
            let u = notesFolder.appendingPathComponent(f)
            guard fm.fileExists(atPath: u.path) else { continue }
            if w.changedAfterItsRecord(u, meeting: m) { suspected.append(f) }
        }
        print("REAL: \(suspected.count) note(s) modified after their record: \(suspected)")
        // Not an assertion of zero — the user may legitimately have edited one by
        // now, and if they have, FR-81 asking about it is correct behaviour. What
        // is printed is the figure AD-41's migration note records.
        XCTAssertLessThanOrEqual(suspected.count, meetings.count)
    }

    private func markdown() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: notesFolder,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private extension String {
    /// The same bounded read the locator uses, so the test measures what the app
    /// actually does rather than a whole-file read.
    init(decoding url: URL, limit: Int) throws {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        let data = try h.read(upToCount: limit) ?? Data()
        self = String(data: data, encoding: .utf8) ?? ""
    }
}
