import XCTest
@testable import Minutes

/// AD-9 / AD-18 / FR-32 / FR-33 — the Note is the product's actual deliverable.
final class NoteWriterTests: XCTestCase {

    private func sampleMeeting(title: String = "Pricing page redesign") -> Meeting {
        var m = Meeting(id: "20260831-140000-abcd",
                        startedAt: ISO8601DateFormatter().date(from: "2026-08-31T14:00:00Z")!)
        m.duration = 1325
        m.stage = .written
        m.systemStreamCaptured = true
        m.diarizationSucceeded = true
        m.transcriptionModel = "openai_whisper-large-v3-v20240930_turbo_632MB"
        m.speakerNames = [SpeakerLabelID.local.raw: "Me",
                          SpeakerLabelID.remote(0).raw: "Mikkel"]
        m.utterances = [
            Utterance(start: 0, end: 4, text: "Let's talk about the pricing page.", speaker: .local, origin: .mic),
            Utterance(start: 4, end: 8, text: "It confuses customers.", speaker: .remote(0), origin: .system),
            Utterance(start: 8, end: 12, text: "Agreed, let's simplify it.", speaker: .remote(0), origin: .system),
            Utterance(start: 12, end: 16, text: "I'll do the copy.", speaker: .local, origin: .mic),
        ]
        m.metadata = MeetingMetadata(
            title: title, tags: ["pricing", "redesign"],
            summary: "The pricing page confuses customers so it will be simplified.",
            decisions: [Decision(text: "Simplify the pricing page.", at: 8)],
            actionItems: [ActionItem(text: "Write the new copy.", owner: "Me", at: 12)],
            backend: .heuristic)
        return m
    }

    func testFrontmatterIsParseableYAML() throws {
        let out = NoteWriter().render(meeting: sampleMeeting())
        XCTAssertTrue(out.hasPrefix("---\n"))
        let fm = out.components(separatedBy: "\n---\n")[0]
        XCTAssertTrue(fm.contains("title: \"Pricing page redesign\""))
        XCTAssertTrue(fm.contains("tags: [\"pricing\", \"redesign\"]"), "tags must be a YAML list")
        XCTAssertTrue(fm.contains("participants: [\"Me\", \"Mikkel\"]"))
        // Provenance is never ambiguous (FR-30).
        XCTAssertTrue(fm.contains("metadata_backend: \"heuristic\""))
        XCTAssertTrue(fm.contains("system_audio_captured: true"))
    }

    /// FR-32: a title with a colon or a quote must not break the YAML.
    func testHostileTitleIsEscaped() throws {
        let m = sampleMeeting(title: "Q3: the \"big\" reset")
        let out = NoteWriter().render(meeting: m)
        let fm = out.components(separatedBy: "\n---\n")[0]
        XCTAssertTrue(fm.contains(#"title: "Q3: the \"big\" reset""#), "got: \(fm)")
    }

    /// FR-33: a speaker's continuous speech is not fragmented line by line.
    func testConsecutiveUtterancesGrouped() {
        let out = NoteWriter().render(meeting: sampleMeeting())
        let mikkelBlocks = out.components(separatedBy: "Mikkel**").count - 1
        XCTAssertEqual(mikkelBlocks, 1, "Mikkel's two consecutive lines should form one block")
        XCTAssertTrue(out.contains("It confuses customers. Agreed, let's simplify it."))
    }

    /// FR-33: empty sections are omitted rather than left as empty headings.
    func testEmptySectionsOmitted() {
        var m = sampleMeeting()
        m.metadata?.decisions = []
        m.metadata?.actionItems = []
        let out = NoteWriter().render(meeting: m)
        XCTAssertFalse(out.contains("## Decisions"))
        XCTAssertFalse(out.contains("## Action items"))
        XCTAssertTrue(out.contains("## Summary"))
    }

    /// FR-7: a mic-only transcript must never read as a monologue.
    func testMicOnlyIsDisclosedInTheBody() {
        var m = sampleMeeting()
        m.systemStreamCaptured = false
        let out = NoteWriter().render(meeting: m)
        XCTAssertTrue(out.contains("Only the microphone was captured"))
    }

    func testInferredSpeakerIsMarked() {
        var m = sampleMeeting()
        m.inferredSpeakers = [SpeakerLabelID.remote(0).raw]
        let out = NoteWriter().render(meeting: m)
        XCTAssertTrue(out.contains("~Mikkel"), "an auto-applied name must be recognisable as inferred")
    }

    func testDecisionCitesTimestamp() {
        let out = NoteWriter().render(meeting: sampleMeeting())
        XCTAssertTrue(out.contains("*(00:08)*"), "decisions must reference where they came from")
    }

    // MARK: - Filename ownership (AD-18)

    func testWritesOneFileAndReportsItsName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let name = try NoteWriter().write(meeting: sampleMeeting(), into: dir)
        XCTAssertTrue(name.hasSuffix(".md"))
        XCTAssertTrue(name.contains("Pricing-page-redesign"))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertEqual(files.count, 1)
    }

    /// AD-18: one Meeting must never yield two Notes after a rename.
    func testRenameMovesTheFileRatherThanCreatingASecond() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let w = NoteWriter()
        var m = sampleMeeting()
        m.noteFilename = try w.write(meeting: m, into: dir)

        m.metadata?.title = "Pricing rethink"
        m.noteFilename = try w.write(meeting: m, into: dir)

        let mds = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertEqual(mds.count, 1, "renaming must not leave two notes; found \(mds)")
        XCTAssertTrue(m.noteFilename?.contains("Pricing-rethink") ?? false)
    }

    func testSlugIsFilesystemSafe() {
        XCTAssertEqual(NoteWriter.slug("Q3: the \"big\"/reset"), "Q3-the-big-reset")
        XCTAssertEqual(NoteWriter.slug(""), "meeting")
    }

    func testAtomicWriteReplacesExistingContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("x.json")
        try MeetingStore.atomicWrite(Data("first".utf8), to: f)
        try MeetingStore.atomicWrite(Data("second".utf8), to: f)
        XCTAssertEqual(try String(contentsOf: f, encoding: .utf8), "second")
        // No temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "found \(leftovers)")
    }
}
