import XCTest
@testable import Minutes

/// Epic 8 — the increment driven by first use of the shipped build.

// MARK: - Story 8.4: curating remembered voices (FR-51)

final class SpeakerDirectoryCurationTests: XCTestCase {
    private var url: URL!
    private var dir: SpeakerDirectory!

    override func setUp() async throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speakers-\(UUID().uuidString).json")
        dir = SpeakerDirectory(url: url)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testSummariesExposeNameSamplesAndDate() async {
        await dir.remember(name: "Mikkel", centroid: [1, 0, 0])
        await dir.remember(name: "Mikkel", centroid: [0.9, 0.1, 0])
        await dir.remember(name: "Anna", centroid: [0, 1, 0])

        let s = await dir.summaries()
        XCTAssertEqual(s.map(\.name), ["Anna", "Mikkel"], "sorted case-insensitively by name")
        XCTAssertEqual(s.first { $0.name == "Mikkel" }?.samples, 2,
                       "sample count is what makes a match judgeable")
        XCTAssertEqual(s.first { $0.name == "Anna" }?.samples, 1)
    }

    /// The point of a correction is that what was learned about the voice survives.
    func testRenameKeepsTheLearnedVoice() async {
        await dir.remember(name: "Speaker 1", centroid: [1, 0, 0])
        await dir.remember(name: "Speaker 1", centroid: [1, 0, 0])

        let ok = await dir.rename(from: "Speaker 1", to: "Mikkel")
        XCTAssertTrue(ok)

        let s = await dir.summaries()
        XCTAssertEqual(s.map(\.name), ["Mikkel"])
        XCTAssertEqual(s.first?.samples, 2, "sample count is carried, not reset")

        // The centroid is carried too, so the renamed profile still matches.
        let matched = await dir.match(centroid: [1, 0, 0])
        XCTAssertEqual(matched, "Mikkel")
    }

    /// Renaming onto an existing name is the fix for one person recorded as two.
    func testRenameOntoAnExistingNameMerges() async {
        await dir.remember(name: "Mikkel", centroid: [1, 0, 0])
        await dir.remember(name: "Mikkel", centroid: [1, 0, 0])
        await dir.remember(name: "Speaker 2", centroid: [1, 0, 0])

        await dir.rename(from: "Speaker 2", to: "Mikkel")

        let s = await dir.summaries()
        XCTAssertEqual(s.count, 1, "two profiles collapse into one")
        XCTAssertEqual(s.first?.name, "Mikkel")
        XCTAssertEqual(s.first?.samples, 3, "samples are summed, not overwritten")
    }

    func testRenameIsCaseInsensitiveOnTheSourceName() async {
        await dir.remember(name: "Mikkel", centroid: [1, 0, 0])
        let ok = await dir.rename(from: "mikkel", to: "Mikkel H")
        XCTAssertTrue(ok)
        let names = await dir.summaries().map(\.name)
        XCTAssertEqual(names, ["Mikkel H"])
    }

    func testRenameRejectsEmptyAndUnknown() async {
        await dir.remember(name: "Mikkel", centroid: [1, 0, 0])
        let blank = await dir.rename(from: "Mikkel", to: "   ")
        XCTAssertFalse(blank, "a blank name would make the profile unreachable")
        let unknown = await dir.rename(from: "Nobody", to: "Someone")
        XCTAssertFalse(unknown)
        let names = await dir.summaries().map(\.name)
        XCTAssertEqual(names, ["Mikkel"], "a rejected rename changes nothing")
    }

    func testForgetOneLeavesTheRest() async {
        await dir.remember(name: "Mikkel", centroid: [1, 0, 0])
        await dir.remember(name: "Anna", centroid: [0, 1, 0])
        await dir.forget(name: "Mikkel")
        let names = await dir.summaries().map(\.name)
        XCTAssertEqual(names, ["Anna"], "forgetting one is not forgetting all")
    }

    func testRenameSurvivesReload() async {
        await dir.remember(name: "Speaker 1", centroid: [1, 0, 0])
        await dir.rename(from: "Speaker 1", to: "Mikkel")
        let reloaded = SpeakerDirectory(url: url)
        let names = await reloaded.summaries().map(\.name)
        XCTAssertEqual(names, ["Mikkel"], "the rename is persisted, not in-memory")
    }
}

// MARK: - Story 8.5: the Recording pulse (FR-50)

final class RecordingPulseTests: XCTestCase {

    /// A status light that blinks out looks like a fault, and the ask was to
    /// animate it *slightly*.
    func testPulseNeverReadsAsOff() {
        for phase in 0..<16 {
            let a = MenuBarIcon.pulseAlpha(phase)
            XCTAssertGreaterThanOrEqual(a, 0.5, "phase \(phase) dipped too far")
            XCTAssertLessThanOrEqual(a, 1.0)
        }
    }

    func testPulseCyclesOverFourPhasesAndIsSymmetric() {
        let cycle = (0..<4).map { MenuBarIcon.pulseAlpha($0) }
        XCTAssertEqual(cycle[0], 1.0, "the cycle peaks at full strength")
        XCTAssertEqual(cycle[1], cycle[3], "rise and fall match, so it breathes rather than sawtooths")
        XCTAssertLessThan(cycle[2], cycle[1], "and reaches its minimum in the middle")
        XCTAssertEqual(MenuBarIcon.pulseAlpha(4), cycle[0], "phase wraps")
        XCTAssertEqual(MenuBarIcon.pulseAlpha(9), cycle[1])
    }

    /// FR-50: Recording must stay identifiable without the animation (NFR-7).
    @MainActor
    func testRecordingIsDistinctFromIdleAtEveryPhase() {
        let idle = MenuBarIcon.image(for: .idle)
        for phase in 0..<4 {
            let rec = MenuBarIcon.image(for: .recording(since: Date(), degraded: false),
                                        pulsePhase: phase)
            XCTAssertFalse(rec.isTemplate, "Recording carries its own colour, not the menu bar's")
            XCTAssertNotEqual(rec.size, .zero)
            XCTAssertTrue(idle.isTemplate, "Idle is tinted by the system")
        }
    }

    /// Idle and Transcribing do not animate, so the phase must not reach them.
    @MainActor
    func testOnlyRecordingRespondsToThePhase() {
        let a = MenuBarIcon.image(for: .idle, pulsePhase: 0).tiffRepresentation
        let b = MenuBarIcon.image(for: .idle, pulsePhase: 2).tiffRepresentation
        XCTAssertEqual(a, b, "Idle is phase-independent")

        let t0 = MenuBarIcon.image(for: .transcribing(meetingID: "x", title: nil), pulsePhase: 0)
            .tiffRepresentation
        let t2 = MenuBarIcon.image(for: .transcribing(meetingID: "x", title: nil), pulsePhase: 2)
            .tiffRepresentation
        XCTAssertEqual(t0, t2, "Transcribing is phase-independent")
    }
}

// MARK: - Story 8.1: the missing-note check (FR-53)

final class MissingNoteTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func meeting(_ id: String, stage: Stage, note: String?) -> Meeting {
        var m = Meeting(id: id, startedAt: Date())
        m.stage = stage
        m.noteFilename = note
        return m
    }

    /// Mirrors AppStateBridge.missingNoteIDs, whose only non-trivial part is which
    /// Meetings are candidates at all.
    private func missing(_ ms: [Meeting], in folder: URL) -> Set<String> {
        let fm = FileManager.default
        var out: Set<String> = []
        for m in ms {
            guard m.isComplete, let f = m.noteFilename else { continue }
            if !fm.fileExists(atPath: folder.appendingPathComponent(f).path) { out.insert(m.id) }
        }
        return out
    }

    func testACompleteMeetingWithNoFileIsMissing() {
        let ms = [meeting("a", stage: .written, note: "gone.md")]
        XCTAssertEqual(missing(ms, in: folder), ["a"])
    }

    func testACompleteMeetingWithItsFileIsNotMissing() throws {
        try "x".write(to: folder.appendingPathComponent("here.md"), atomically: true, encoding: .utf8)
        let ms = [meeting("a", stage: .written, note: "here.md")]
        XCTAssertTrue(missing(ms, in: folder).isEmpty)
    }

    /// An unfinished Meeting has no Note to be missing — calling it broken would
    /// mislabel every interrupted recording.
    func testAnUnfinishedMeetingIsNeverMissingItsNote() {
        let ms = [
            meeting("a", stage: .captured, note: nil),
            meeting("b", stage: .transcribed, note: nil),
            meeting("c", stage: .metadata, note: "not-written-yet.md"),
        ]
        XCTAssertTrue(missing(ms, in: folder).isEmpty)
    }

    func testOnlyTheAbsentOnesAreReported() throws {
        try "x".write(to: folder.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        let ms = [
            meeting("a", stage: .written, note: "one.md"),
            meeting("b", stage: .written, note: "two.md"),
            meeting("c", stage: .written, note: "three.md"),
        ]
        XCTAssertEqual(missing(ms, in: folder), ["b", "c"])
    }
}
