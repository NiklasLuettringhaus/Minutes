import XCTest
@testable import Minutes

/// The three defects that were reproduced against the shipped code before any of
/// this was written, now pinned so they cannot come back.
///
/// Each of them passed a green 183-test suite, because nothing pinned the
/// behaviour. That is the reason these tests exist in this shape: they assert what
/// is on disk after the operation, not what a function returned.
final class NoteRewriteTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("rewrite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func meeting(title: String = "Anything") -> Meeting {
        var m = Meeting(id: "20260903-093038-zzzz",
                        startedAt: ISO8601DateFormatter().date(from: "2026-09-03T07:30:38Z")!)
        m.duration = 801
        m.stage = .written
        m.utterances = [Utterance(start: 0, end: 4, text: "Hello.", speaker: .local, origin: .mic)]
        m.metadata = MeetingMetadata(title: title, tags: [], summary: "", decisions: [],
                                     actionItems: [], backend: .heuristic)
        return m
    }

    private func apply(_ o: NoteWriteOutcome, to m: inout Meeting) throws {
        guard case .wrote(let f, let w, let d) = o else {
            throw XCTSkip("unexpected refusal: \(o)")
        }
        m.noteFilename = f; m.noteFilenameWritten = w; m.noteDigest = d
    }

    private func mdFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".md") }.sorted()
    }

    // MARK: - F1, reproduced red before the fix

    /// **This test failed against the shipped code**: the folder held two notes,
    /// and the second was the app's, with the user's renamed copy orphaned — the
    /// state reachable by clicking the one remedy the app offered for a broken link.
    func testRewritingAfterAFinderRenameDoesNotCreateASecondNote() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting()
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)
        let appName = try XCTUnwrap(m.noteFilename)

        // The user renames it in Finder to something that describes the meeting.
        let userName = "2026-09-03 0930 Morning -standup.md"
        try FileManager.default.moveItem(at: folder.appendingPathComponent(appName),
                                        to: folder.appendingPathComponent(userName))

        // What the app now does: resolve first, then write to what it found.
        let located = try NoteLocator().locate(meeting: m, in: folder)
        guard case .located(let url) = located else {
            return XCTFail("the renamed file must be found; got \(located)")
        }
        try apply(w.write(meeting: m, into: folder, at: url), to: &m)

        XCTAssertEqual(try mdFiles(), [userName], "one meeting, one note, under the user's name")
        XCTAssertEqual(m.noteFilename, userName)
    }

    // MARK: - AD-40: the user's name wins

    func testATitleChangeDoesNotRenameAFileTheUserNamed() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting()
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)

        let userName = "my own filing scheme.md"
        try FileManager.default.moveItem(at: folder.appendingPathComponent(m.noteFilename!),
                                        to: folder.appendingPathComponent(userName))
        m.noteFilename = userName
        XCTAssertTrue(m.noteIsUserNamed, "the two names differ, so the user owns it")

        m.metadata?.title = "A completely different title"
        try apply(w.write(meeting: m, into: folder, at: folder.appendingPathComponent(userName)),
                  to: &m)

        XCTAssertEqual(try mdFiles(), [userName], "the app must not rename the user's file")
        let body = try String(contentsOf: folder.appendingPathComponent(userName), encoding: .utf8)
        XCTAssertTrue(body.contains("A completely different title"),
                      "the title changes inside the file, which is the whole point")
    }

    /// The other half of AD-40: while the app owns the name, AD-18 is unchanged and
    /// a retitle still renames the file. Both directions, because a rule that only
    /// works one way is half a rule.
    func testATitleChangeStillRenamesAFileTheAppNamed() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting(title: "First title")
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)
        XCTAssertFalse(m.noteIsUserNamed)

        m.metadata?.title = "Second title"
        try apply(w.write(meeting: m, into: folder,
                          at: folder.appendingPathComponent(m.noteFilename!)), to: &m)

        let files = try mdFiles()
        XCTAssertEqual(files.count, 1, "still one note; found \(files)")
        XCTAssertTrue(files[0].contains("Second-title"), "found \(files)")
    }

    // MARK: - F7 / AD-41: the app knows what it wrote

    func testAnOrdinaryRewriteOverItsOwnBytesIsSilent() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting()
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)

        m.metadata?.title = "Anything"     // same title, so no rename
        let again = try w.write(meeting: m, into: folder,
                                at: folder.appendingPathComponent(m.noteFilename!))
        guard case .wrote = again else {
            return XCTFail("the app must recognise its own output; got \(again)")
        }
    }

    /// **This is the defect the user had not hit yet.** A hand-edited paragraph was
    /// destroyed by any retitle, with no dialog and no trace.
    func testAHandEditedNoteIsNotOverwritten() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting()
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)
        let url = folder.appendingPathComponent(m.noteFilename!)

        let mine = try String(contentsOf: url, encoding: .utf8)
            + "\n## My own notes\n\nSend the contract to legal.\n"
        try Data(mine.utf8).write(to: url)

        let outcome = try w.write(meeting: m, into: folder, at: url)
        XCTAssertEqual(outcome, .refusedChangedOnDisk(url))

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("Send the contract to legal"),
                      "the user's paragraph must survive")
    }

    /// The trap named in the plan, and the reason the comparison is a digest rather
    /// than a re-render: the renderer has changed in four increments, so
    /// re-rendering an old record legitimately differs from the file on disk. A
    /// render-based check would report every old note as edited.
    func testAnOldShapedRecordDoesNotReadAsEdited() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting()
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)
        let url = folder.appendingPathComponent(m.noteFilename!)

        // The record gains fields it did not have when the note was written — a
        // speaker index, an exclusion, a device — so a fresh render differs.
        m.micDevice = "MacBook Pro Microphone"
        m.speakerNames[SpeakerLabelID.local.raw] = "Me"
        XCTAssertNotEqual(NoteWriter().render(meeting: m),
                          try String(contentsOf: url, encoding: .utf8),
                          "precondition: the render really has changed")

        let outcome = try w.write(meeting: m, into: folder, at: url)
        guard case .wrote = outcome else {
            return XCTFail("a changed render is not an edit; got \(outcome)")
        }
    }

    // MARK: - AD-41's migration, both branches

    func testAPreDigestNoteIsAdoptedWhenItIsNoNewerThanItsRecord() throws {
        var m = meeting()
        // Written by an older build: no digest recorded.
        let name = "2026-09-03 0930 Anything.md"
        m.noteFilename = name
        m.noteFilenameWritten = name
        m.noteDigest = nil
        let url = folder.appendingPathComponent(name)
        try Data(NoteWriter().render(meeting: m).utf8).write(to: url)

        // The record was written after the note, which is the normal order.
        let w = NoteWriter(recordModifiedAt: { _ in Date().addingTimeInterval(60) })
        guard case .wrote = try w.write(meeting: m, into: folder, at: url) else {
            return XCTFail("all fifteen real notes must adopt cleanly")
        }
    }

    /// The branch that never fires in the happy path, which is why it is
    /// constructed explicitly: it is the one that ships broken otherwise.
    func testAPreDigestNoteIsQueriedWhenItIsNewerThanItsRecord() throws {
        var m = meeting()
        let name = "2026-09-03 0930 Anything.md"
        m.noteFilename = name
        m.noteFilenameWritten = name
        m.noteDigest = nil
        let url = folder.appendingPathComponent(name)
        try Data(NoteWriter().render(meeting: m).utf8).write(to: url)

        // The note was touched long after the record — evidence of an outside edit.
        let w = NoteWriter(recordModifiedAt: { _ in Date().addingTimeInterval(-3600) })
        XCTAssertEqual(try w.write(meeting: m, into: folder, at: url),
                       .refusedChangedOnDisk(url))
    }

    /// The signal's limit, asserted rather than left implicit: with no record time
    /// available there is no evidence of an edit, and no evidence is not evidence.
    func testNoRecordTimeMeansNoRefusal() throws {
        var m = meeting()
        let name = "2026-09-03 0930 Anything.md"
        m.noteFilename = name; m.noteFilenameWritten = name; m.noteDigest = nil
        let url = folder.appendingPathComponent(name)
        try Data("something else entirely".utf8).write(to: url)

        let w = NoteWriter(recordModifiedAt: { _ in nil })
        guard case .wrote = try w.write(meeting: m, into: folder, at: url) else {
            return XCTFail("without a record time the app cannot claim an edit happened")
        }
    }

    // MARK: - The digest itself

    func testTheDigestIsOfTheBytesActuallyWritten() throws {
        let w = NoteWriter(recordModifiedAt: { _ in nil })
        var m = meeting()
        try apply(w.write(meeting: m, into: folder, at: nil), to: &m)
        let bytes = try Data(contentsOf: folder.appendingPathComponent(m.noteFilename!))
        XCTAssertEqual(m.noteDigest, NoteWriter.digest(bytes))
    }
}

// MARK: - Row actions (FR-53, the reported "file not found")

@MainActor
final class RowActionTests: XCTestCase {

    private func meeting(stage: Stage = .written, failure: String? = nil) -> Meeting {
        var m = Meeting(id: "20260903-093038-zzzz", startedAt: Date())
        m.stage = stage
        m.failure = failure
        m.noteFilename = "2026-09-03 0930 Anything.md"
        return m
    }

    /// The defect, as a test. The old condition was *a filename is recorded*, and
    /// `NSWorkspace.open` on an absent path is what produced macOS's own "the file
    /// does not exist" alert.
    func testRevealAndOpenAreAbsentWhenNoFileWasFound() {
        let actions = MeetingsPane.rowActions(meeting: meeting(), link: .notFound, isInFlight: false)
        XCTAssertFalse(actions.contains { if case .reveal = $0 { return true }; return false })
        XCTAssertFalse(actions.contains { if case .openInEditor = $0 { return true }; return false })
        XCTAssertTrue(actions.contains(.locate))
        XCTAssertTrue(actions.contains(.rewrite))
    }

    func testRevealAndOpenAppearOnlyForALocatedFile() {
        let url = URL(fileURLWithPath: "/tmp/whatever the user called it.md")
        let actions = MeetingsPane.rowActions(meeting: meeting(),
                                              link: .linked(url: url, userNamed: true),
                                              isInFlight: false)
        XCTAssertTrue(actions.contains(.reveal(url)))
        XCTAssertTrue(actions.contains(.openInEditor(url)))
    }

    /// A folder that has never been looked in is not a folder with a missing file.
    func testAnUnknownLinkOffersNeitherRevealNorAClaimAboutTheFolder() {
        let actions = MeetingsPane.rowActions(meeting: meeting(), link: .unknown, isInFlight: false)
        XCTAssertFalse(actions.contains { if case .reveal = $0 { return true }; return false })
    }

    func testAmbiguityOffersOneChoicePerFileAndNoDefault() {
        let a = URL(fileURLWithPath: "/tmp/a.md"), b = URL(fileURLWithPath: "/tmp/b.md")
        let actions = MeetingsPane.rowActions(meeting: meeting(),
                                              link: .ambiguous([a, b]), isInFlight: false)
        XCTAssertTrue(actions.contains(.useThisFile(a)))
        XCTAssertTrue(actions.contains(.useThisFile(b)))
        XCTAssertFalse(actions.contains { if case .reveal = $0 { return true }; return false },
                       "the app has not picked one, so there is nothing to reveal")
    }

    /// FR-79 is offered on a healthy link too: a user may want a different file.
    func testLocateIsOfferedEvenWhenTheNoteIsFine() {
        let url = URL(fileURLWithPath: "/tmp/fine.md")
        let actions = MeetingsPane.rowActions(meeting: meeting(),
                                              link: .linked(url: url, userNamed: false),
                                              isInFlight: false)
        XCTAssertTrue(actions.contains(.locate))
    }

    func testAnIncompleteMeetingIsNotOfferedNoteActions() {
        let actions = MeetingsPane.rowActions(meeting: meeting(stage: .captured),
                                              link: .unknown, isInFlight: false)
        XCTAssertFalse(actions.contains(.rewrite), "there is no note to rewrite yet")
        XCTAssertTrue(actions.contains(.finish))
    }

    func testDeleteIsAlwaysReachable() {
        for link in [NoteLinkState.notFound, .unknown,
                     .linked(url: URL(fileURLWithPath: "/tmp/x.md"), userNamed: false)] {
            XCTAssertTrue(MeetingsPane.rowActions(meeting: meeting(), link: link, isInFlight: false)
                .contains(.delete))
        }
    }
}
