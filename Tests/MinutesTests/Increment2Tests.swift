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

// MARK: - Story 8.5: the Recording indicator (FR-49; FR-50 withdrawn)

/// FR-50's pulse was withdrawn on use — the solid red circle reads better. What
/// these tests protect is what FR-2 and NFR-7 always required and what the pulse
/// was explicitly never allowed to carry: Recording is distinguishable by
/// silhouette and tint alone, with no motion involved.
final class RecordingIndicatorTests: XCTestCase {

    @MainActor
    func testRecordingIsDistinctFromIdleAndCarriesItsOwnColour() {
        let idle = MenuBarIcon.image(for: .idle)
        let rec = MenuBarIcon.image(for: .recording(since: Date(), degraded: false))
        XCTAssertFalse(rec.isTemplate, "Recording carries its own colour, not the menu bar's")
        XCTAssertTrue(idle.isTemplate, "Idle is tinted by the system")
        XCTAssertNotEqual(rec.size, .zero)
        XCTAssertNotEqual(idle.tiffRepresentation, rec.tiffRepresentation,
                          "the two states must differ in silhouette, not only in tint")
    }

    /// The point of the revert: the Recording icon is the same image every time it
    /// is asked for. Nothing varies, so nothing invites a second look to work out
    /// whether it is varying.
    @MainActor
    func testTheRecordingIconIsSteady() {
        let a = MenuBarIcon.image(for: .recording(since: Date(), degraded: false))
        let b = MenuBarIcon.image(for: .recording(since: Date().addingTimeInterval(90),
                                                  degraded: true))
        XCTAssertEqual(a.tiffRepresentation, b.tiffRepresentation,
                       "the dot must not change with elapsed time or degradation")
        XCTAssertTrue(a === b, "and it is built once rather than per tick (NFR-3)")
    }

    @MainActor
    func testEveryStateHasADistinctSilhouette() {
        let images = [
            MenuBarIcon.image(for: .idle),
            MenuBarIcon.image(for: .recording(since: Date(), degraded: false)),
            MenuBarIcon.image(for: .transcribing(meetingID: "x", title: nil)),
            MenuBarIcon.image(for: .idle, isAsking: true),
        ].map(\.tiffRepresentation)
        XCTAssertEqual(Set(images).count, images.count,
                       "four distinguishable states, greyscale included (FR-2, NFR-7)")
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

// MARK: - Speaker index, exclusions, and the unidentified in-room label

final class SpeakerIndexAndExclusionTests: XCTestCase {

    private func meeting() -> Meeting {
        var m = Meeting(id: "m", startedAt: Date(timeIntervalSince1970: 1_772_000_000))
        m.stage = .written
        m.duration = 120
        m.systemStreamCaptured = true
        m.diarizationSucceeded = true
        m.multipleInRoom = true
        m.micDevice = "Niklas’s AirPods Pro"
        m.systemSource = "system audio — Slack"
        m.speakerNames = ["local": "Me", "room-1": "In-room 1", "remote-0": "Speaker 1"]
        m.utterances = [
            Utterance(start: 0, end: 2, text: "Mine.", speaker: .local, origin: .mic),
            Utterance(start: 2, end: 4, text: "Beside me.", speaker: .inRoom(1), origin: .mic),
            Utterance(start: 4, end: 6, text: "Also beside me.", speaker: .inRoom(1), origin: .mic),
            Utterance(start: 6, end: 8, text: "The far end.", speaker: .remote(0), origin: .system),
        ]
        m.metadata = MeetingMetadata(title: "T", tags: [], summary: "",
                                     decisions: [], actionItems: [], backend: .heuristic)
        return m
    }

    /// What the user asked for: an index naming who spoke and what through.
    func testIndexNamesTheDeviceEachSpeakerCameThrough() {
        let note = NoteWriter().render(meeting: meeting())
        XCTAssertTrue(note.contains("## Speakers"))
        XCTAssertTrue(note.contains("Niklas’s AirPods Pro"), "the mic hardware is named")
        XCTAssertTrue(note.contains("system audio — Slack"), "the far end names its source")
        // The index precedes the transcript.
        XCTAssertLessThan(note.range(of: "## Speakers")!.lowerBound,
                          note.range(of: "## Transcript")!.lowerBound)
    }

    func testIndexCountsLinesPerSpeaker() {
        let note = NoteWriter().render(meeting: meeting())
        // In-room 1 spoke twice, the others once each.
        XCTAssertTrue(note.contains("| In-room 1 | 2 |"), note)
        XCTAssertTrue(note.contains("| Me | 1 |"), note)
    }

    func testExcludedSpeakerLeavesTheTranscriptButNotTheRecord() {
        var m = meeting()
        m.excludedSpeakers = [SpeakerLabelID.inRoom(1).raw]
        let note = NoteWriter().render(meeting: m)
        XCTAssertFalse(note.contains("Beside me."), "excluded speech is out of the note")
        XCTAssertTrue(note.contains("Mine."), "everyone else stays")
        XCTAssertTrue(note.contains("The far end."))
        XCTAssertEqual(m.utterances.count, 4, "the record is untouched")
    }

    /// A note that quietly omits speech is less trustworthy than one that says so.
    func testExclusionIsDisclosedInTheNote() {
        var m = meeting()
        m.excludedSpeakers = [SpeakerLabelID.inRoom(1).raw]
        let note = NoteWriter().render(meeting: m)
        XCTAssertTrue(note.contains("excluded"), "the omission is stated")
        XCTAssertTrue(note.contains("In-room 1"), "and names who")
        XCTAssertTrue(note.contains("still in Minutes"), "and says it is recoverable")
    }

    func testExcludingEveryoneSaysSoRatherThanClaimingNoSpeech() {
        var m = meeting()
        m.excludedSpeakers = m.speakers.map(\.raw)
        let note = NoteWriter().render(meeting: m)
        XCTAssertTrue(note.contains("Every speaker in this meeting has been excluded."))
        XCTAssertFalse(note.contains("*No speech was transcribed.*"),
                       "there was speech; it was excluded — a different fact")
    }

    /// The mislabel found in the first real meeting: unplaceable mic speech was
    /// rendered as the user's own words.
    func testUnplaceableMicSpeechIsNotAttributedToTheUser() {
        let mic = [DiarizedSpan(start: 2, end: 4, speakerIndex: 1)]
        let u = [
            Utterance(start: 2, end: 4, text: "placed", speaker: .local, origin: .mic),
            Utterance(start: 40, end: 42, text: "unplaceable", speaker: .local, origin: .mic),
        ]
        let out = Pipeline.assign(micSpans: mic, systemSpans: [],
                                  multipleInRoom: true, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.inRoom(1))
        XCTAssertEqual(out[1].speaker, .inRoomUnidentified,
                       "with several voices on the mic, unplaceable speech is not 'Me'")
        XCTAssertTrue(out[1].speaker.isInRoom, "but it is still structurally in-room")
    }

    /// One voice on the mic is still the user, placed or not.
    func testSingleVoiceOnTheMicStaysTheUser() {
        let u = [Utterance(start: 40, end: 42, text: "mine", speaker: .local, origin: .mic)]
        let out = Pipeline.assign(micSpans: [], systemSpans: [],
                                  multipleInRoom: false, to: u)
        XCTAssertEqual(out[0].speaker, .local)
    }

    func testUnidentifiedLabelReadsHonestly() {
        var m = meeting()
        m.utterances = [Utterance(start: 0, end: 1, text: "x",
                                  speaker: .inRoomUnidentified, origin: .mic)]
        XCTAssertEqual(m.displayName(for: .inRoomUnidentified), "In-room, unidentified")
    }
}

/// FR-12 — how the Detection Prompt reaches the user is a choice.
///
/// **The rule that matters is the fallback.** A preference whose selected value
/// can result in *no prompt at all* is how a real Teams call went unprompted
/// with nothing to show for it — the defect the floating panel was added for.
/// So the panel appears whenever notifications cannot deliver, whatever the
/// user picked, and these tests pin that rather than the wording.
final class PromptDeliveryTests: XCTestCase {

    private typealias Choice = Preferences.PromptDelivery

    /// What `DetectionService` decides, as a pure function of the two inputs.
    /// Kept in the test rather than reached for in the service, because the
    /// service's own call site is two lines and a `@MainActor` polling loop.
    private func surfaces(_ c: Choice, canNotify: Bool) -> (panel: Bool, notification: Bool) {
        (panel: c.showsPanel || !canNotify,
         notification: c.showsNotification && canNotify)
    }

    func testExactlyOneSurfaceUnlessBothWasChosen() {
        // Asserted field by field: a tuple of two Bools is not Equatable.
        var s = surfaces(.panel, canNotify: true)
        XCTAssertTrue(s.panel); XCTAssertFalse(s.notification)
        s = surfaces(.notification, canNotify: true)
        XCTAssertFalse(s.panel); XCTAssertTrue(s.notification)
        s = surfaces(.both, canNotify: true)
        XCTAssertTrue(s.panel); XCTAssertTrue(s.notification)
    }

    /// The fallback, and the reason the preference is safe to expose.
    func testTheAskAlwaysArrivesEvenWithNotificationsUnavailable() {
        for c in Choice.allCases {
            let s = surfaces(c, canNotify: false)
            XCTAssertTrue(s.panel, "\(c.rawValue) must fall back to the panel")
            XCTAssertFalse(s.notification, "\(c.rawValue) cannot post without permission")
        }
        // And with permission, every choice still reaches the user somehow.
        for c in Choice.allCases {
            let s = surfaces(c, canNotify: true)
            XCTAssertTrue(s.panel || s.notification, "\(c.rawValue) reaches nobody")
        }
    }

    func testOnlyThePanelChoiceNeedsNoNotificationPermission() {
        XCTAssertFalse(Choice.panel.needsNotifications)
        XCTAssertTrue(Choice.notification.needsNotifications)
        XCTAssertTrue(Choice.both.needsNotifications)
    }

    /// Every option is describable in the pane beside the option itself, so the
    /// wording cannot drift away from the choice it belongs to.
    func testEveryChoiceCarriesItsOwnTitleAndDetail() {
        for c in Choice.allCases {
            XCTAssertFalse(c.title.isEmpty, c.rawValue)
            XCTAssertFalse(c.detail.isEmpty, c.rawValue)
        }
        XCTAssertEqual(Set(Choice.allCases.map(\.title)).count, Choice.allCases.count,
                       "two options must not share a label")
    }

    /// The raw values are persisted in `UserDefaults`, so renaming one silently
    /// resets every existing install to the default.
    func testRawValuesArePersistedAndMustNotChange() {
        XCTAssertEqual(Choice.panel.rawValue, "panel")
        XCTAssertEqual(Choice.notification.rawValue, "notification")
        XCTAssertEqual(Choice.both.rawValue, "both")
        XCTAssertEqual(Choice(rawValue: "nonsense"), nil,
                       "an unknown stored value must not decode to a real choice")
    }
}
