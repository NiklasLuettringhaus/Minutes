import SwiftUI
import AppKit

/// `--uishot [outdir]`: renders the app's own panes to PNG files, with fixture
/// data, at several widths.
///
/// **Why this exists.** Every other check in this project can be run from a
/// terminal — `swift test`, `--doctor`, `--selftest` — and the one thing that
/// could not was the one thing that kept breaking. Two increments shipped layout
/// defects that 149 passing tests said nothing about: a speaker row that
/// collapsed to one character per line, and chips inside a selected row that
/// painted themselves unreadable. Both were obvious in a screenshot and invisible
/// from a terminal, so they were found by the user rather than by the build.
///
/// The alternative was screen capture, and it does not work here: `osascript` has
/// no assistive access on this machine and `screencapture` blocks on a permission
/// prompt. `ImageRenderer` needs neither, because an app rendering its own view
/// tree is not capturing anyone's screen. It also does something screen capture
/// cannot: render the **hard cases on demand** — fourteen speakers, a 40-character
/// name, a 320pt column — without recording fourteen meetings first.
///
/// What it cannot do: prove the running app looks like this. `ImageRenderer` walks
/// the same view tree AppKit does, so a layout bug reproduces faithfully, but it
/// resolves no `@FocusState`, runs no animation, and knows nothing about the real
/// window's size. It answers "does this layout hold at this width", not "is the
/// app correct".
enum UIShot {

    /// True while `--uishot` is rendering. `ShotScroll` reads it to substitute a
    /// plain `VStack` for a `ScrollView`, which `ImageRenderer` will not lay out.
    ///
    /// Deliberately `nonisolated(unsafe)`: it is written once on the main thread
    /// before any rendering and never again, and making it an actor-isolated
    /// property would force every `ShotScroll` body — i.e. every pane — through an
    /// isolation check for a flag that is false in every shipped run.
    nonisolated(unsafe) static var isRendering = false

    /// Widths worth checking, and why each one.
    ///
    /// The defects that shipped were all *narrow-column* defects, and the default
    /// window is wide — which is why they survived every look until a user
    /// dragged the sidebar out.
    private static let widths: [(name: String, width: CGFloat)] = [
        ("narrow", 320),   // detail column with the sidebar open and the window small
        ("medium", 460),   // the shape in the user's screenshots
        ("wide", 720),     // a comfortable full-window detail column
    ]

    @MainActor
    static func run() {
        isRendering = true
        defer { isRendering = false }
        let args = CommandLine.arguments
        let outDir: URL = {
            if let i = args.firstIndex(of: "--uishot"), i + 1 < args.count,
               !args[i + 1].hasPrefix("-") {
                return URL(fileURLWithPath: args[i + 1])
            }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("ui-shots")
        }()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        setbuf(stdout, nil)
        print("=== Minutes UI shots ===")
        print("out: \(outDir.path)")

        // Fixtures, not the user's meetings. Deterministic, and they contain the
        // cases that break rather than the cases that happen to exist.
        let app = AppState.shared
        app.setMeetings(Fixtures.all)
        // The four Note Link states, one per fixture, so every one is renderable
        // at every width. Increment 7: these are the states whose *copy* is the
        // whole feature, and copy that overflows is a defect like any other.
        app.setNoteLinks(Fixtures.noteLinks)
        app.setUnclaimedNotes(Fixtures.unclaimedNotes)

        var written = 0

        func shoot(_ name: String, _ width: CGFloat, _ height: CGFloat?,
                   @ViewBuilder _ content: () -> some View) {
            let view = content()
                .environmentObject(AppState.shared)
                .environmentObject(Preferences.shared)
                .frame(width: width)
                .frame(minHeight: height ?? 1, alignment: .top)
                .background(Tok.surfaceWindow)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let img = renderer.nsImage,
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("  ✗ \(name) — render failed")
                return
            }
            let url = outDir.appendingPathComponent("\(name).png")
            do {
                try png.write(to: url)
                written += 1
                let pad = name.padding(toLength: max(name.count, 32), withPad: " ", startingAt: 0)
                print("  ✓ \(pad) \(Int(img.size.width)) x \(Int(img.size.height))")
            } catch {
                print("  ✗ \(name) — \(error.localizedDescription)")
            }
        }

        // MARK: The cases that have actually broken

        for (label, w) in widths {
            // The speaker block: the row that collapsed to one character per line.
            shoot("detail-speakers-\(label)", w, nil) {
                MeetingDetail(meeting: Fixtures.crowded)
            }
            // Rows rendered directly, both states. A `List` cannot be rendered at
            // all, and the selected row is where the colour defects live.
            shoot("list-\(label)", w, nil) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Fixtures.all.enumerated()), id: \.element.id) { i, m in
                        MeetingRow(meeting: m, isSelected: i == 0,
                                   isInFlight: m.id == Fixtures.interrupted.id,
                                   noteMissing: false)
                            .padding(.horizontal, Tok.s4)
                            .padding(.vertical, 4)
                            .background(i == 0 ? Color(nsColor: .selectedContentBackgroundColor)
                                               : Color.clear)
                        Divider()
                    }
                }
            }
        }

        // The Note Link states (increment 7). A renamed note, a note nobody can
        // find, and two files claiming one meeting — the last of which is the only
        // place in the product where the app lists files and refuses to choose.
        for (label, w) in widths {
            shoot("detail-note-userNamed-\(label)", w, nil) {
                MeetingDetail(meeting: Fixtures.userRenamed)
            }
            shoot("detail-note-notFound-\(label)", w, nil) {
                MeetingDetail(meeting: Fixtures.noteLost)
            }
            shoot("detail-note-ambiguous-\(label)", w, nil) {
                MeetingDetail(meeting: Fixtures.noteAmbiguous)
            }
            // The decision banner on its own, at every width: two controls and a
            // sentence, which is exactly the shape that collapsed twice before.
            shoot("decision-banner-\(label)", w, nil) {
                DecisionBanner(
                    text: "“a note I renamed and then edited myself.md” has been changed outside Minutes, so the note was not rewritten. Your edit to this meeting is saved either way.",
                    safeLabel: "Keep My Version", safeAction: {},
                    riskyLabel: "Replace With Minutes' Note", riskyAction: {})
                    .padding(Tok.s4)
            }
            shoot("unclaimed-notes-\(label)", w, nil) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Fixtures.unclaimedNotes) { UnclaimedNoteRow(note: $0) }
                }
                .padding(Tok.s4)
            }
        }

        // Long names are their own case: a renamed speaker is usually a real name,
        // and "Christina Nørgaard-Pedersen" is longer than "In-room 3".
        shoot("detail-longnames-medium", 460, nil) {
            MeetingDetail(meeting: Fixtures.longNames)
        }

        // One voice on the microphone: the structural case, and the only one where
        // the app claims an identity with certainty.
        shoot("detail-simple-medium", 460, nil) {
            MeetingDetail(meeting: Fixtures.simple)
        }

        // Every settings pane, at the width where prose competes with controls.
        shoot("summaries-medium", 560, nil) { SummariesPane() }
        shoot("general-medium", 560, nil) { GeneralPane() }
        shoot("getting-started-medium", 560, nil) { GettingStartedPane(selection: .constant(.gettingStarted)) }
        shoot("transcription-medium", 560, nil) { TranscriptionPane() }
        shoot("detection-medium", 560, nil) { DetectionPane() }

        // FR-66's banner, at three widths and with the two shapes that differ:
        // a long reason with a remedy button, and a short one without. A fixture
        // with no error would never render it, which is how a surface that only
        // appears on failure goes unlooked-at.
        for (name, err) in [
            ("failure-mic", MinutesError.microphonePermissionDenied),
            // The real generated reason, from the shape of a real stream: the
            // author's 20260902-110315-hkt0 system stream, 757 s, peak exactly 0.
            ("failure-silence", MinutesError.systemAudioProducedSilence(
                AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 757).failureReason!)),
            ("failure-noremedy", MinutesError.transcriptionFailed("the model returned no segments")),
        ] {
            app.lastError = err
            shoot("\(name)-narrow", 320, nil) { FailureBanner() }
            shoot("\(name)-medium", 560, nil) { FailureBanner() }
            // No in-pane variant: the banner now sits at the window root rather
            // than inside PaneScaffold, and the window root is a
            // NavigationSplitView that ImageRenderer cannot draw. Rendering a
            // pane here would show no banner and imply one is absent.
            shoot("\(name)-wide", 720, nil) { FailureBanner() }
        }
        app.lastError = nil

        print("\n\(written) image(s) written.")
        print("Fixtures only — this proves a layout holds at a width, not that the running app is correct.")
    }

    // MARK: - Fixtures

    /// Deliberately harsher than reality. A fixture that only covers the easy case
    /// is why the hard case shipped.
    enum Fixtures {

        static var all: [Meeting] {
            [crowded, longNames, simple, failed, interrupted,
             userRenamed, noteLost, noteAmbiguous]
        }

        // MARK: - Note link states (increment 7)

        /// A note the user renamed in Finder. Deliberately awkward: a long name,
        /// a space before a hyphen — which `NoteWriter.slug` cannot produce, so it
        /// could only have come from a human — and no relation to the app's title.
        static var userRenamed: Meeting = {
            var m = simpleShaped(id: "20260903-093000-usnm", title: "Actually")
            m.noteFilename = "2026-09-03 0930 Morning -standup, the one about pricing.md"
            m.noteFilenameWritten = "2026-09-03 0930 Actually.md"
            return m
        }()

        /// A note nobody can find. The state whose copy used to be a false claim.
        static var noteLost: Meeting = {
            var m = simpleShaped(id: "20260903-094000-lost", title: "A meeting whose note went missing")
            m.noteFilename = "2026-09-03 0940 A-meeting-whose-note-went-missing.md"
            m.noteFilenameWritten = m.noteFilename
            return m
        }()

        /// Two files claiming one meeting — the only place in the product where
        /// the app lists files and refuses to choose between them.
        static var noteAmbiguous: Meeting = {
            var m = simpleShaped(id: "20260903-095000-ambg", title: "A meeting with two notes")
            m.noteFilename = "2026-09-03 0950 A-meeting-with-two-notes.md"
            m.noteFilenameWritten = m.noteFilename
            return m
        }()

        static var noteLinks: [String: NoteLinkState] {
            let folder = URL(fileURLWithPath: "/Users/you/Documents/Minutes")
            return [
                crowded.id: .linked(url: folder.appendingPathComponent("crowded.md"), userNamed: false),
                longNames.id: .linked(url: folder.appendingPathComponent("long.md"), userNamed: false),
                simple.id: .linked(url: folder.appendingPathComponent("simple.md"), userNamed: false),
                userRenamed.id: .linked(url: folder.appendingPathComponent(userRenamed.noteFilename!),
                                        userNamed: true),
                noteLost.id: .notFound,
                noteAmbiguous.id: .ambiguous([
                    folder.appendingPathComponent("2026-09-03 0950 A-meeting-with-two-notes.md"),
                    folder.appendingPathComponent("2026-09-03 0950 A-meeting-with-two-notes (2).md"),
                ]),
            ]
        }

        static var unclaimedNotes: [UnclaimedNote] {
            let folder = URL(fileURLWithPath: "/Users/you/Documents/Minutes")
            return [
                UnclaimedNote(url: folder.appendingPathComponent("2026-09-03 0930 Morning -standup.md"),
                              startedAt: date(9, 30)),
                UnclaimedNote(url: folder.appendingPathComponent("a note whose meeting I deleted last week.md"),
                              startedAt: nil),
            ]
        }

        /// The minimum shape a detail pane needs, so a Note-link fixture is about
        /// the note and not about the transcript.
        private static func simpleShaped(id: String, title: String) -> Meeting {
            var m = Meeting(id: id, startedAt: date(9, 30))
            m.duration = 801
            m.stage = .written
            m.systemStreamCaptured = true
            m.diarizationSucceeded = true
            m.micDevice = "MacBook Pro Microphone"
            m.utterances = [
                Utterance(start: 0, end: 6, text: "Right, let's go through the list.",
                          speaker: .local, origin: .mic),
                Utterance(start: 6, end: 14, text: "I have three things and the first one is easy.",
                          speaker: .remote(0), origin: .system),
            ]
            m.speakerNames = [SpeakerLabelID.local.raw: "Me",
                              SpeakerLabelID.remote(0).raw: "Speaker 1"]
            m.metadata = MeetingMetadata(title: title, tags: [], summary: "",
                                         decisions: [], actionItems: [], backend: .heuristic)
            return m
        }

        /// Fourteen speakers, mixed places, one excluded, one enrolment-identified.
        /// Modelled on the user's real 8-person huddle with colleagues beside them.
        static var crowded: Meeting = {
            var m = Meeting(id: "20260902-133000-shot", startedAt: date(13, 30))
            m.duration = 3019
            m.stage = .written
            m.systemStreamCaptured = true
            m.diarizationSucceeded = true
            m.multipleInRoom = true
            m.localIdentifiedByEnrolment = true
            m.localMatchDistance = 0.14
            m.micDevice = "MacBook Pro Microphone"
            m.systemSource = "system audio — Microsoft Teams"
            m.noteFilename = "shot.md"
            m.metadata = MeetingMetadata(title: "Platform migration", tags: ["migration", "rollback"],
                                         summary: "", decisions: [], actionItems: [],
                                         backend: .heuristic)
            var t = 0.0
            func say(_ label: SpeakerLabelID, _ text: String, _ dur: Double = 6) {
                m.utterances.append(Utterance(start: t, end: t + dur, text: text,
                                              speaker: label,
                                              origin: label.isRemote ? .system : .mic))
                t += dur
            }
            say(.local, "So the migration window is the part I want to pin down today.")
            say(.inRoom(1), "Right, and the rollback plan needs to be written before we commit.")
            say(.remote(0), "On our side the API contract has not changed, so that is one less thing.")
            say(.inRoom(2), "Do we have the terminal firmware sorted?")
            say(.remote(1), "Partly. Two of the models still need the older payload shape.")
            say(.inRoomUnidentified, "sorry, go on")
            say(.local, "Let us take the firmware separately, it is a different decision.")
            say(.remote(2), "Agreed. I will write it up and send it round this afternoon.")
            for i in 3...7 {
                say(.inRoom(i), "Point \(i) from someone in the room with a reasonably long sentence.")
            }
            for i in 3...6 {
                say(.remote(i), "Remote point \(i), also a sentence of ordinary length.")
            }
            m.speakerNames = [SpeakerLabelID.local.raw: "Me"]
            for i in 1...7 { m.speakerNames[SpeakerLabelID.inRoom(i).raw] = "In-room \(i)" }
            for i in 0...6 { m.speakerNames[SpeakerLabelID.remote(i).raw] = "Speaker \(i + 1)" }
            m.excludedSpeakers = [SpeakerLabelID.inRoom(5).raw]
            m.inferredSpeakers = [SpeakerLabelID.remote(0).raw]
            return m
        }()

        /// Real names, which are longer than `In-room 3` and are what a renamed
        /// speaker actually looks like.
        static var longNames: Meeting = {
            var m = Meeting(id: "20260902-120000-long", startedAt: date(12, 0))
            m.duration = 1840
            m.stage = .written
            m.systemStreamCaptured = true
            m.diarizationSucceeded = true
            m.multipleInRoom = true
            m.micDevice = "AirPods Pro"
            m.systemSource = "system audio — Slack"
            m.noteFilename = "long.md"
            // A deliberately long title, and deliberately *not* borrowed from a real
            // meeting: this repository is public and a meeting title is meeting content
            // (PRD §9.1). The fixture's job is length and awkwardness, which invented
            // words do just as well.
            m.metadata = MeetingMetadata(title: "Quarterly widget rollout and the migration window",
                                         tags: [], summary: "", decisions: [], actionItems: [],
                                         backend: .heuristic)
            m.utterances = [
                Utterance(start: 0, end: 8, text: "The first question is separable.",
                          speaker: .inRoom(0), origin: .mic),
                Utterance(start: 8, end: 16, text: "I disagree, they land in the same release.",
                          speaker: .inRoom(1), origin: .mic),
                Utterance(start: 16, end: 24, text: "Let me check what the vendor said.",
                          speaker: .remote(0), origin: .system),
            ]
            m.speakerNames = [
                SpeakerLabelID.inRoom(0).raw: "Christina Nørgaard-Pedersen",
                SpeakerLabelID.inRoom(1).raw: "Mikkel",
                SpeakerLabelID.remote(0).raw: "Someone From The Vendor Support Desk",
            ]
            m.inferredSpeakers = [SpeakerLabelID.inRoom(0).raw]
            return m
        }()

        /// One voice on the microphone: structural certainty, the simple case.
        static var simple: Meeting = {
            var m = Meeting(id: "20260902-093000-simp", startedAt: date(9, 30))
            m.duration = 63
            m.stage = .written
            m.systemStreamCaptured = true
            m.diarizationSucceeded = true
            m.micDevice = "MacBook Pro Microphone"
            m.noteFilename = "simple.md"
            m.metadata = MeetingMetadata(title: "Spare Part", tags: ["ops"],
                                         summary: "A short call about one broken unit.",
                                         decisions: [Decision(text: "Replace the unit.", at: 30)],
                                         actionItems: [ActionItem(text: "Order a replacement.",
                                                                  owner: "Me", at: 42)],
                                         backend: .heuristic)
            m.utterances = [
                Utterance(start: 0, end: 20, text: "The unit on site three is offline again.",
                          speaker: .local, origin: .mic),
                Utterance(start: 20, end: 40, text: "We have replaced that controller twice now.",
                          speaker: .remote(0), origin: .system),
            ]
            m.speakerNames = [SpeakerLabelID.local.raw: "Me",
                              SpeakerLabelID.remote(0).raw: "Speaker 1"]
            return m
        }()

        static var failed: Meeting = {
            var m = Meeting(id: "20260902-080000-fail", startedAt: date(8, 0))
            m.duration = 300
            m.stage = .transcribed
            m.failure = "Transcription failed. The model file may be incomplete."
            m.metadata = MeetingMetadata(title: "Sorry", tags: [], summary: "",
                                         decisions: [], actionItems: [], backend: .heuristic)
            return m
        }()

        static var interrupted: Meeting = {
            var m = Meeting(id: "20260902-070000-intr", startedAt: date(7, 0))
            m.duration = 120
            m.stage = .captured
            m.metadata = MeetingMetadata(title: "Don", tags: [], summary: "",
                                         decisions: [], actionItems: [], backend: .heuristic)
            return m
        }()

        private static func date(_ h: Int, _ m: Int) -> Date {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            c.hour = h; c.minute = m
            return Calendar.current.date(from: c) ?? Date()
        }
    }
}
