import XCTest
@testable import Minutes

/// A locator that counts. The cost claim in `NoteLinkService.reconcile` is the
/// answer to PRD §13 Q12, and increment 6 taught the lesson that a rule stated
/// only in a comment is a rule that gets reverted with every test green.
private final class CountingLocator: NoteLocating, @unchecked Sendable {
    var locateCalls = 0
    var unclaimedCalls = 0
    var answer: NoteLocation = .notFound
    var orphans: [UnclaimedNote] = []

    func locate(meeting: Meeting, in folder: URL) throws -> NoteLocation {
        locateCalls += 1
        return answer
    }
    func unclaimed(meetings: [Meeting], in folder: URL) throws -> [UnclaimedNote] {
        unclaimedCalls += 1
        return orphans
    }
}

@MainActor
final class NoteLinkServiceTests: XCTestCase {

    private var folder: URL!
    private var storeRoot: URL!
    private var store: MeetingStore!
    private var counting: CountingLocator!
    private var previousLocator: NoteLocating!
    private var previousStore: MeetingStore!

    override func setUp() async throws {
        let fm = FileManager.default
        folder = fm.temporaryDirectory.appendingPathComponent("links-\(UUID().uuidString)", isDirectory: true)
        storeRoot = fm.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // A temp-rooted store, so nothing here can reach the real library.
        store = MeetingStore(root: storeRoot)
        counting = CountingLocator()
        previousLocator = NoteLinkService.locator
        previousStore = NoteLinkService.store
        NoteLinkService.locator = counting
        NoteLinkService.store = store
    }

    override func tearDown() async throws {
        NoteLinkService.locator = previousLocator
        NoteLinkService.store = previousStore
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: storeRoot)
    }

    private func meeting(_ id: String, note: String?, written: String? = nil) -> Meeting {
        var m = Meeting(id: id, startedAt: Date())
        m.stage = .written
        m.noteFilename = note
        m.noteFilenameWritten = written ?? note
        return m
    }

    private func touch(_ name: String) throws {
        try Data("---\ngenerated_by: Minutes\n---\n".utf8)
            .write(to: folder.appendingPathComponent(name))
    }

    // MARK: - The cost claim (PRD §13 Q12)

    /// **Zero folder reads when nothing is broken.** This is the whole reason the
    /// note-present check can stay on every reload.
    func testALibraryWithNoBrokenLinkReadsNothing() async throws {
        try touch("a.md"); try touch("b.md"); try touch("c.md")
        let ms = [meeting("m1", note: "a.md"), meeting("m2", note: "b.md"), meeting("m3", note: "c.md")]

        let states = await NoteLinkService.reconcile(ms, in: folder)

        XCTAssertEqual(counting.locateCalls, 0, "a healthy library must not read the folder")
        XCTAssertEqual(states.count, 3)
        XCTAssertTrue(states.values.allSatisfy(\.isResolved))
    }

    func testOnlyTheBrokenLinkCostsALookup() async throws {
        try touch("a.md"); try touch("c.md")
        counting.answer = .located(folder.appendingPathComponent("renamed.md"))
        let ms = [meeting("m1", note: "a.md"), meeting("m2", note: "gone.md"), meeting("m3", note: "c.md")]

        _ = await NoteLinkService.reconcile(ms, in: folder)
        XCTAssertEqual(counting.locateCalls, 1, "one broken link, one lookup")
    }

    /// An unfinished Meeting is not missing its Note, so it is not a candidate.
    func testAnIncompleteMeetingIsNeitherCheckedNorReported() async throws {
        var m = meeting("m1", note: nil)
        m.stage = .captured
        let states = await NoteLinkService.reconcile([m], in: folder)
        XCTAssertEqual(counting.locateCalls, 0)
        XCTAssertNil(states["m1"])
    }

    // MARK: - What is persisted, and what is not

    func testASingleMatchIsPersistedBecauseItIsDurable() async throws {
        _ = try await store.create(id: "m1", startedAt: Date())
        _ = try await store.update(id: "m1") {
            $0.stage = .written
            $0.noteFilename = "gone.md"
            $0.noteFilenameWritten = "gone.md"
        }
        let m = try await store.load(id: "m1")
        counting.answer = .located(folder.appendingPathComponent("the user renamed it.md"))

        _ = await NoteLinkService.reconcile([m], in: folder)

        let after = try await store.load(id: "m1")
        XCTAssertEqual(after.noteFilename, "the user renamed it.md")
        XCTAssertTrue(after.noteIsUserNamed, "the app did not choose that name")
    }

    /// The rule that keeps a transient filesystem condition out of history.
    func testAbsenceAndAmbiguityPersistNothing() async throws {
        for (id, answer) in [("m1", NoteLocation.notFound),
                             ("m2", .ambiguous([folder.appendingPathComponent("a.md"),
                                                folder.appendingPathComponent("b.md")]))] {
            _ = try await store.create(id: id, startedAt: Date())
            _ = try await store.update(id: id) {
                $0.stage = .written
                $0.noteFilename = "gone.md"
                $0.noteFilenameWritten = "gone.md"
            }
            let m = try await store.load(id: id)
            counting.answer = answer

            _ = await NoteLinkService.reconcile([m], in: folder)

            let after = try await store.load(id: id)
            XCTAssertEqual(after.noteFilename, "gone.md",
                           "\(answer) must not rewrite the record")
        }
    }

    /// A folder the app cannot see is not a folder with missing files. Saying the
    /// note is gone would be a claim about the user's files the app cannot support.
    func testNoFolderYieldsUnknownRatherThanNotFound() async throws {
        let states = await NoteLinkService.reconcile([meeting("m1", note: "a.md")], in: nil)
        XCTAssertEqual(states["m1"], .unknown)
        XCTAssertEqual(counting.locateCalls, 0)
    }

    // MARK: - The states the UI reads

    func testARelinkedFileIsReportedAsUserNamed() async throws {
        counting.answer = .located(folder.appendingPathComponent("mine.md"))
        let states = await NoteLinkService.reconcile(
            [meeting("m1", note: "gone.md", written: "gone.md")], in: folder)
        guard case .linked(_, let userNamed) = states["m1"] else {
            return XCTFail("expected a link; got \(String(describing: states["m1"]))")
        }
        XCTAssertTrue(userNamed)
    }

    func testAnAppNamedFileIsNotReportedAsUserNamed() async throws {
        try touch("app.md")
        let states = await NoteLinkService.reconcile(
            [meeting("m1", note: "app.md", written: "app.md")], in: folder)
        XCTAssertEqual(states["m1"], .linked(url: folder.appendingPathComponent("app.md"),
                                             userNamed: false))
    }

    // MARK: - Adoption (FR-79)

    func testAdoptingAFileRecordsItsCurrentBytesAsTheBaseline() async throws {
        _ = try await store.create(id: "m1", startedAt: Date())
        let chosen = folder.appendingPathComponent("theirs.md")
        try Data("a file Minutes did not write".utf8).write(to: chosen)

        await NoteLinkService.adopt(chosen, for: "m1")

        let after = try await store.load(id: "m1")
        XCTAssertEqual(after.noteFilename, "theirs.md")
        XCTAssertEqual(after.noteDigest, NoteWriter.digest(try Data(contentsOf: chosen)),
                       "adopting must not immediately read as a conflict")
        XCTAssertTrue(after.noteIsUserNamed, "the user picked this file by hand")
    }

    // MARK: - Unclaimed (FR-82)

    func testDismissedOrphansAreFilteredOutOfTheListing() async throws {
        let a = UnclaimedNote(url: folder.appendingPathComponent("kept.md"), startedAt: Date())
        let b = UnclaimedNote(url: folder.appendingPathComponent("dismissed.md"), startedAt: Date())
        counting.orphans = [a, b]

        let before = Preferences.shared.dismissedUnclaimedNotes
        defer { Preferences.shared.dismissedUnclaimedNotes = before }
        Preferences.shared.dismissedUnclaimedNotes = ["dismissed.md"]

        let out = await NoteLinkService.unclaimed([], in: folder)
        XCTAssertEqual(out.map(\.filename), ["kept.md"])
    }
}

// MARK: - AD-40's migration for records that predate it

@MainActor
final class LegacyNoteNameMigrationTests: XCTestCase {

    private var folder: URL!
    private var storeRoot: URL!
    private var store: MeetingStore!
    private var previousStore: MeetingStore!
    private var previousLocator: NoteLocating!

    override func setUp() async throws {
        let fm = FileManager.default
        folder = fm.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        storeRoot = fm.temporaryDirectory.appendingPathComponent("lstore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        store = MeetingStore(root: storeRoot)
        previousStore = NoteLinkService.store
        previousLocator = NoteLinkService.locator
        NoteLinkService.store = store
        NoteLinkService.locator = NoteLocator()
    }
    override func tearDown() async throws {
        NoteLinkService.store = previousStore
        NoteLinkService.locator = previousLocator
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: storeRoot)
    }

    /// A record from before increment 7 whose file is still where it was: the name
    /// on disk is the name the app wrote, and that is worth recording once.
    func testAHealthyLegacyRecordLearnsTheNameTheAppWrote() async throws {
        _ = try await store.create(id: "20260901-093248-evi3", startedAt: Date())
        _ = try await store.update(id: "20260901-093248-evi3") {
            $0.stage = .written
            $0.noteFilename = "2026-09-01 0932 Something.md"
            $0.noteFilenameWritten = nil          // the legacy shape
        }
        try Data("---\ngenerated_by: Minutes\n---\n".utf8)
            .write(to: folder.appendingPathComponent("2026-09-01 0932 Something.md"))

        let m = try await store.load(id: "20260901-093248-evi3")
        let states = await NoteLinkService.reconcile([m], in: folder)

        XCTAssertEqual(states[m.id], .linked(url: folder.appendingPathComponent("2026-09-01 0932 Something.md"),
                                             userNamed: false))
        let after = try await store.load(id: m.id)
        XCTAssertEqual(after.noteFilenameWritten, "2026-09-01 0932 Something.md")
        XCTAssertFalse(after.noteIsUserNamed)
    }

    /// **The bug the live run found.** A legacy record whose file the user renamed:
    /// before the backfill the reported state said "named by you" while the writer
    /// would have said "mine" and renamed it back — the exact defect the increment
    /// exists to remove, surviving inside its own fix.
    func testARenamedLegacyFileIsRecordedAsTheUsersAndIsNotRenamedBack() async throws {
        let id = "20260903-103103-y774"
        _ = try await store.create(id: id, startedAt: ISO8601DateFormatter().date(from: "2026-09-03T08:31:03Z")!)
        _ = try await store.update(id: id) {
            $0.stage = .written
            $0.metadata = MeetingMetadata(title: "Something", tags: [], summary: "",
                                          decisions: [], actionItems: [], backend: .heuristic)
            $0.noteFilename = "2026-09-03 1031 Something.md"
            $0.noteFilenameWritten = nil          // the legacy shape
        }
        // The user renamed it in Finder. Only the new file exists.
        let userName = "2026-09-03 1031 renamed by hand in Finder.md"
        try Data("---\nstarted_at: 2026-09-03T08:31:03Z\ngenerated_by: Minutes\n---\n".utf8)
            .write(to: folder.appendingPathComponent(userName))

        var m = try await store.load(id: id)
        let states = await NoteLinkService.reconcile([m], in: folder)

        guard case .linked(_, let userNamed) = states[id] else {
            return XCTFail("the renamed file must be found; got \(String(describing: states[id]))")
        }
        XCTAssertTrue(userNamed, "the app did not choose that name")

        m = try await store.load(id: id)
        XCTAssertEqual(m.noteFilename, userName)
        XCTAssertEqual(m.noteFilenameWritten, "2026-09-03 1031 Something.md",
                       "the name being replaced is the name the app wrote")

        // And now the part the reported state and the writer used to disagree on.
        XCTAssertFalse(m.appOwnsNoteName(userName),
                       "the writer must agree that this name is the user's")

        let w = NoteWriter(recordModifiedAt: { _ in nil })
        m.metadata?.title = "A different title entirely"
        _ = try w.write(meeting: m, into: folder, at: folder.appendingPathComponent(userName))

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertEqual(files, [userName], "a retitle must not rename the user's file back")
    }
}
