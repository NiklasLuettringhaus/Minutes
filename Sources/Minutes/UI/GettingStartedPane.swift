import SwiftUI
import AppKit

/// FR-46 / FR-47 / FR-48 — the setup surface, following the pattern the user
/// asked for: rows that each explain themselves and carry their own state, with
/// satisfied rows fading back.
struct GettingStartedPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var playground = TestPlayground.shared
    @ObservedObject var enrolment = VoiceEnrolment.shared
    @ObservedObject var catalog = ModelCatalog.shared
    @ObservedObject var notifier = Notifier.shared
    @Binding var selection: MainWindow.Pane

    /// Recomputed on appearance and on window focus, never stored. A permission
    /// revoked in System Settings therefore shows as outstanding again without an
    /// app restart (FR-46).
    @State private var refreshToken = 0

    private var micState: Permissions.MicState { Permissions.micState() }
    private var sysState: Permissions.SystemAudioState { Permissions.systemAudioState() }
    private var modelReady: Bool { ModelCatalog.isDownloaded(prefs.model) }
    private var folderReady: Bool { prefs.notesFolder() != nil }
    private var testPassed: Bool {
        if case .done(let r) = playground.phase { return r.micHadAudio }
        return false
    }

    private var requiredSatisfied: Bool { modelReady && micState.isAuthorized && folderReady }

    var body: some View {
        ShotScroll {
            VStack(alignment: .leading, spacing: Tok.cardGap) {
                header
                quickSetup
                testPlayground
                voiceEnrolment
                howItWorks
            }
            .padding(Tok.paneMargin)
            .id(refreshToken)
        }
        .background(Tok.surfaceWindow)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        catalog.refreshDownloadStates()
        SessionCoordinator.shared.refreshMicAuthorization()
        Task { await Notifier.shared.refreshAuthorization() }
        // Live-derived, like every other row: whether a voice is enrolled is read
        // from the store on appearance, never from a stored completion flag (FR-46).
        Task { await VoiceEnrolment.shared.refresh() }
        refreshToken += 1
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Getting Started").font(.largeTitle)
            Text("Records your meetings, transcribes them on this Mac, and writes Markdown.")
                .font(.body).foregroundStyle(Tok.textSecondary)
        }
    }

    // MARK: - Quick Setup

    private var quickSetup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Quick Setup", trailing: AnyView(
                Button {
                    prefs.didCompleteFirstRun = false
                    selection = .gettingStarted
                    refresh()
                } label: {
                    Label("Run Onboarding Again", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tok.textSecondary)
            ))

            Card {
                // 1 — Model
                ChecklistRow(
                    ordinal: 1,
                    title: "Transcription model ready",
                    subtitle: modelReady
                        ? "\(ModelCatalog.friendlyName(prefs.model)) is downloaded and runs on the Neural Engine."
                        : "Needed to turn recordings into text. Runs entirely on this Mac.",
                    isSatisfied: modelReady
                ) {
                    // A satisfied row still leads somewhere: the place you would
                    // go to check or change the thing it reports.
                    if modelReady {
                        DonePill { selection = .transcription }
                            .help("Open Transcription settings")
                    } else { RowActionButton(title: "Choose Model") { selection = .transcription } }
                }
                RowDivider()

                // 2 — Microphone
                ChecklistRow(
                    ordinal: 2,
                    title: "Microphone access",
                    subtitle: micState.isAuthorized
                        ? "Granted. Your side of the conversation will be recorded."
                        : "Needed to record your side of the conversation.",
                    isSatisfied: micState.isAuthorized
                ) {
                    if micState.isAuthorized {
                        DonePill { Permissions.openMicrophoneSettings() }
                            .help("Open Privacy & Security › Microphone")
                    } else if micState == .denied {
                        RowActionButton(title: "Open Settings") {
                            Permissions.openMicrophoneSettings()
                        }
                    } else {
                        RowActionButton(title: "Grant Access", showsChevron: false) {
                            Task { _ = await Permissions.requestMic(); refresh() }
                        }
                    }
                }
                RowDivider()

                // 3 — System audio. NOT required: the app degrades to Mic-only
                // rather than failing (FR-7), and this row is where the product's
                // hardest constraint becomes visible to the user.
                ChecklistRow(
                    ordinal: 3,
                    title: "System audio capture",
                    subtitle: systemAudioSubtitle,
                    isSatisfied: sysState == .observedWorking,
                    isOptional: true
                ) {
                    if sysState == .observedWorking {
                        DonePill { Permissions.openSystemAudioSettings() }
                            .help("Open Privacy & Security")
                    } else { RowActionButton(title: "Run Test") { runTest() } }
                }
                RowDivider()

                // 4 — Notes folder
                ChecklistRow(
                    ordinal: 4,
                    title: "Notes folder",
                    subtitle: folderReady
                        ? (prefs.notesFolder()?.path ?? "")
                        : "Where the Markdown file for each meeting is written.",
                    isSatisfied: folderReady
                ) {
                    if folderReady && prefs.hasExplicitNotesFolder() {
                        DonePill { if let f = prefs.notesFolder() { NSWorkspace.shared.open(f) } }
                            .help("Show the folder in Finder")
                    } else {
                        RowActionButton(title: "Choose Folder…", showsChevron: false) { chooseFolder() }
                    }
                }
                RowDivider()

                // 5 — Detection prompts. Optional because Minutes falls back to a
                // floating panel, but worth its own row: with this denied the
                // notification path is silently dead, which is how a real Teams
                // call went unprompted with nothing to show for it.
                ChecklistRow(
                    ordinal: 5,
                    title: "Detection prompts",
                    subtitle: notificationSubtitle,
                    isSatisfied: notifier.canDeliver,
                    isOptional: true
                ) {
                    if notifier.canDeliver {
                        DonePill { Notifier.openSettings() }
                            .help("Open Notifications settings")
                    } else if notifier.authorizationStatus == .denied {
                        // macOS will not show its dialog a second time.
                        RowActionButton(title: "Open Settings") { Notifier.openSettings() }
                    } else {
                        RowActionButton(title: "Allow Notifications", showsChevron: false) {
                            Task { await Notifier.shared.requestAuthorization() }
                        }
                    }
                }
                RowDivider()

                // 6 — Test
                ChecklistRow(
                    ordinal: 6,
                    title: "Test your setup",
                    subtitle: testPassed
                        ? "Passed. Minutes can record, transcribe and attribute speech."
                        : "Record five seconds and confirm the whole chain works before a real meeting.",
                    isSatisfied: testPassed,
                    isOptional: true
                ) {
                    if testPassed {
                        DonePill(label: "Passed") { runTest() }
                            .help("Run the test again")
                    } else { RowActionButton(title: "Run Test") { runTest() } }
                }

                RowDivider()

                // 7 — Voice enrolment. Optional, and last: rows never reorder, and
                // renumbering a shipped row to put the newest thing first would
                // disturb a surface the user already knows. Prominence comes from
                // being in this checklist rather than in a settings pane (FR-62).
                ChecklistRow(
                    ordinal: 7,
                    title: "Your voice",
                    subtitle: enrolment.isEnrolled
                        ? "Recorded. When several people share your microphone, Minutes can tell which voice is yours."
                        : "Minutes can tell which voice in the room is yours instead of leaving it unattributed.",
                    isSatisfied: enrolment.isEnrolled,
                    isOptional: true
                ) {
                    if enrolment.isEnrolled {
                        DonePill(label: "Recorded") { selection = .general }
                            .help("See or delete it under General › Remembered voices")
                    } else {
                        RowActionButton(title: "Record Voice", showsChevron: false) {
                            runEnrolment()
                        }
                    }
                }

                if requiredSatisfied {
                    HStack(spacing: Tok.s3) {
                        Image(systemName: "checkmark.circle.fill").font(.caption)
                        Text("Setup complete.").font(.caption).fontWeight(.medium)
                    }
                    .foregroundStyle(Tok.brand)
                    .padding(.top, Tok.s4)
                }
            }
        }
    }

    /// Reads as a trade-off, not a failure — and names the real cause when it
    /// regresses, because rebuilding the app is the most likely reason (PRD §12).

    /// Says what the consequence is, not just what the state is — "denied" alone
    /// leaves the user with no idea that detection still works.
    private var notificationSubtitle: String {
        switch notifier.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Minutes can notify you when a meeting starts."
        case .denied:
            return "Notifications are off for Minutes, so detected meetings appear as a small floating panel instead."
        default:
            return "Not asked yet. Without it, detected meetings appear as a small floating panel."
        }
    }

    private var systemAudioSubtitle: String {
        switch sysState {
        case .observedWorking:
            return "Last recording captured system audio. macOS revokes this when Minutes is rebuilt."
        case .observedNotWorking:
            return "The last recording captured no system audio, so only your side was saved."
        case .unknown:
            return "Captures what the other people say. macOS asks the first time you record — without it, Minutes records only your side."
        }
    }

    // MARK: - Test Playground

    private var testPlayground: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Test Playground")
            Card {
                switch playground.phase {
                case .idle:
                    // Said BEFORE the user starts, so a flat System meter is not a
                    // false negative.
                    StateBanner(kind: .degraded,
                                text: "Play something — a video or music — so Minutes can check it hears system audio.")
                    startButton
                    meters(status: nil)

                case .recording(let remaining):
                    StateBanner(kind: .recording, text: "Recording… \(remaining)s. Say a sentence.")
                    meters(status: nil).padding(.top, Tok.s4)

                case .transcribing:
                    StateBanner(kind: .transcribing, text: "Transcribing on this Mac…")
                    meters(status: nil).padding(.top, Tok.s4)

                case .done(let r):
                    resultCard(r)

                case .failed(let reason):
                    StateBanner(kind: .degraded, text: reason)
                    startButton
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            runTest()
        } label: {
            Label("Start Test", systemImage: "mic.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .tint(Tok.brand)
        .disabled(playground.isRunning)
        .padding(.vertical, Tok.s4)
    }

    private func meters(status: Bool?) -> some View {
        VStack(spacing: 7) {
            LevelMeter(label: "Microphone", level: playground.micLevel, status: nil)
            LevelMeter(label: "System audio", level: playground.systemLevel, status: nil)
        }
    }

    /// Reports the four things that make the test a diagnostic rather than a demo:
    /// the transcript, per-Stream audio presence, the model, and measured
    /// throughput on this machine (FR-47).
    private func resultCard(_ r: TestPlayground.Result) -> some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            Text("“\(r.transcript)”")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                LevelMeter(label: "Microphone", level: r.micHadAudio ? 0.4 : 0,
                           status: r.micHadAudio ? "✓ audio" : "✗ none", statusOK: r.micHadAudio)
                LevelMeter(label: "System audio", level: r.systemHadAudio ? 0.3 : 0,
                           status: r.systemHadAudio ? "✓ audio" : "✗ none", statusOK: r.systemHadAudio)
            }

            Divider()

            HStack(spacing: Tok.s3) {
                FactChip(text: r.micHadAudio ? "Mic ✓" : "Mic ✗", good: r.micHadAudio)
                FactChip(text: r.systemHadAudio ? "System ✓" : "System ✗", good: r.systemHadAudio)
                FactChip(text: ModelCatalog.friendlyName(r.model))
                FactChip(text: String(format: "%.1f s for %.0f s of audio",
                                      r.transcriptionSeconds, r.audioSeconds))
                if !r.extrapolation.isEmpty { FactChip(text: r.extrapolation) }
            }

            if !r.systemHadAudio {
                StateBanner(kind: .degraded, text: """
                    No system audio was captured. Either nothing was playing, or macOS has not \
                    granted system-audio access — it revokes it whenever Minutes is rebuilt.
                    """)
                copyResetCommand
            }

            Button("Run Again") { runTest() }
                .buttonStyle(.bordered)
                .tint(Tok.brand)
                .frame(maxWidth: .infinity)
        }
    }

    private var copyResetCommand: some View {
        HStack(spacing: Tok.s3) {
            Text(Permissions.resetCommand)
                .font(.caption).monospaced()
                .textSelection(.enabled)
                .foregroundStyle(Tok.textSecondary)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Permissions.resetCommand, forType: .string)
            } label: { Image(systemName: "doc.on.doc").font(.caption) }
            .buttonStyle(.borderless)
            .help("Copy the reset command")
        }
        .padding(Tok.s3)
        .background(Tok.separator.opacity(0.35), in: RoundedRectangle(cornerRadius: Tok.rSm))
    }


    // MARK: - Voice enrolment (FR-62)

    /// Deliberately the Test Playground's card, not a new shape. The Playground
    /// already taught the user what a countdown, a level meter and a result made
    /// of measured facts mean — that the app is about to listen and will then say
    /// what it actually heard. Enrolment makes exactly that promise.
    ///
    /// One meter, not two. Enrolment never opens the System Stream, so a System
    /// meter would misdescribe what is being read.
    private var voiceEnrolment: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Your voice")
            Card {
                switch enrolment.phase {
                case .idle:
                    if let e = enrolment.enrolled {
                        enrolledState(e)
                    } else {
                        enrolmentPitch
                    }

                case .recording(let remaining):
                    StateBanner(kind: .recording,
                                text: "Recording… \(remaining)s. Keep talking, and let nobody else talk.")
                    micMeter.padding(.top, Tok.s4)
                    Button("Cancel") { enrolment.cancel() }
                        .buttonStyle(.bordered)
                        .padding(.top, Tok.s4)
                        .help("Stops the recording. Nothing is stored.")

                case .analysing:
                    StateBanner(kind: .transcribing,
                                text: enrolment.isCancelling
                                    ? "Stopping. Nothing will be stored."
                                    : "Working out your voice fingerprint on this Mac…")
                    micMeter.padding(.top, Tok.s4)
                    if !enrolment.isCancelling {
                        // Analysis queues behind transcription (one model at a time),
                        // so this can wait minutes through no fault of its own. A way
                        // out matters more than a progress guess we cannot make.
                        VStack(alignment: .leading, spacing: Tok.s3) {
                            Text("If Minutes is transcribing a meeting, this waits until that finishes — only one model runs at a time.")
                                .font(.caption2).foregroundStyle(Tok.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Cancel") { enrolment.cancel() }
                                .buttonStyle(.bordered)
                                .help("Stops without storing anything.")
                        }
                        .padding(.top, Tok.s4)
                    }

                case .done(let r):
                    // Facts, not a verdict. No score, no "good sample!".
                    VStack(alignment: .leading, spacing: Tok.s4) {
                        StateBanner(kind: .info, text: "Your voice is recorded. The recording itself has been deleted.")
                        HStack(spacing: Tok.s3) {
                            FactChip(text: String(format: "%.0f s of speech", r.speechSeconds), good: true)
                            FactChip(text: r.voicesFound == 1 ? "one voice" : "\(r.voicesFound) voices",
                                     good: r.voicesFound == 1)
                        }
                        enrolmentFooter
                        Button("Re-record") { runEnrolment() }
                            .buttonStyle(.bordered).tint(Tok.brand)
                    }

                case .failed(let reason, let recovery):
                    VStack(alignment: .leading, spacing: Tok.s4) {
                        StateBanner(kind: .degraded, text: reason)
                        if let recovery {
                            Text(recovery).font(.caption).foregroundStyle(Tok.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Nothing was stored.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                        Button {
                            runEnrolment()
                        } label: {
                            Label("Try Again", systemImage: "mic.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 3)
                        }
                        .buttonStyle(.borderedProminent).tint(Tok.brand)
                    }
                }
            }
        }
    }

    /// Said before the user starts, not after: how long, what is kept, what is
    /// deleted, and the one thing they have to do (talk, alone).
    private var enrolmentPitch: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            Text("""
                When you are in a room with other people, your microphone picks up all of them. \
                Minutes can separate those voices but cannot tell which one is you — so it leaves \
                them unattributed rather than guessing.
                """)
                .font(.caption).foregroundStyle(Tok.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Read anything out loud for about \(Int(VoiceEnrolment.captureSeconds)) seconds — a paragraph of an email is fine. Talk normally, and let nobody else talk over you.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            enrolmentFooter

            Button {
                runEnrolment()
            } label: {
                Label("Record my voice", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Tok.brand)
            .disabled(enrolment.isRunning)

            micMeter
        }
    }

    private func enrolledState(_ e: SpeakerDirectory.Summary) -> some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            StateBanner(kind: .info, text: "Minutes knows your voice.")
            HStack(spacing: Tok.s3) {
                if let s = e.speechSeconds {
                    FactChip(text: String(format: "%.0f s of speech", s), good: true)
                }
                FactChip(text: "recorded \(relative(e.updatedAt))")
            }
            enrolmentFooter
            HStack(spacing: Tok.s4) {
                Button("Re-record") { runEnrolment() }
                    .buttonStyle(.bordered).tint(Tok.brand)
                Text("Re-recording replaces the fingerprint you have now.")
                    .font(.caption2).foregroundStyle(Tok.textSecondary)
            }
            Button("See it under General") { selection = .general }
                .buttonStyle(.borderless).font(.caption)
        }
    }

    /// The privacy statement, in the place the thing is created — plainly, and
    /// without either softening it or dramatising it (PRD §9.1).
    private var enrolmentFooter: some View {
        Text("Minutes keeps a fingerprint of your voice on this Mac — a few hundred numbers, which cannot be played back. The recording itself is deleted as soon as the fingerprint is made. Neither ever leaves this Mac, and one click deletes it under General.")
            .font(.caption2).foregroundStyle(Tok.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var micMeter: some View {
        LevelMeter(label: "Microphone", level: enrolment.micLevel, status: nil)
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    // MARK: - How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "How it works")
            Card {
                VStack(alignment: .leading, spacing: Tok.s3) {
                    bullet("Click the menu bar icon to start and stop a recording. The icon turns red while recording.")
                    bullet("When Slack or Teams takes your microphone, Minutes offers to record. It never starts on its own.")
                    bullet("Your microphone and the other participants' audio are recorded separately, which is how “you” is never confused with “them”.")
                    bullet("Everything runs on this Mac. The only time Minutes uses the network is downloading a transcription model.")
                }
            }
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: Tok.s3) {
            Text("•").foregroundStyle(Tok.textSecondary)
            Text(s).font(.caption).foregroundStyle(Tok.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func runTest() {
        Task { await playground.run(); refresh() }
    }

    private func runEnrolment() {
        Task { await enrolment.run(); refresh() }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Where should Minutes write meeting notes?"
        if p.runModal() == .OK, let url = p.url {
            prefs.setNotesFolder(url)
            refresh()
        }
    }
}
