import SwiftUI
import AppKit

/// FR-46 / FR-47 / FR-48 — the setup surface, following the pattern the user
/// asked for: rows that each explain themselves and carry their own state, with
/// satisfied rows fading back.
struct GettingStartedPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var playground = TestPlayground.shared
    @ObservedObject var catalog = ModelCatalog.shared
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
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.cardGap) {
                header
                quickSetup
                testPlayground
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
                    if modelReady { DonePill() }
                    else { RowActionButton(title: "Choose Model") { selection = .transcription } }
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
                    if micState.isAuthorized { DonePill() }
                    else if micState == .denied {
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
                    if sysState == .observedWorking { DonePill() }
                    else { RowActionButton(title: "Run Test") { runTest() } }
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
                    if folderReady && prefs.hasExplicitNotesFolder() { DonePill() }
                    else {
                        RowActionButton(title: "Choose Folder…", showsChevron: false) { chooseFolder() }
                    }
                }
                RowDivider()

                // 5 — Test
                ChecklistRow(
                    ordinal: 5,
                    title: "Test your setup",
                    subtitle: testPassed
                        ? "Passed. Minutes can record, transcribe and attribute speech."
                        : "Record five seconds and confirm the whole chain works before a real meeting.",
                    isSatisfied: testPassed,
                    isOptional: true
                ) {
                    if testPassed { DonePill() }
                    else { RowActionButton(title: "Run Test") { runTest() } }
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
