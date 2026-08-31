import SwiftUI
import AppKit

/// FR-34 / FR-44 / FR-45 / FR-21 (local speaker name).
struct GeneralPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    /// Read on appearance, not once at init: the value can change outside the app
    /// (System Settings, or the plist being removed).
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var audioBytes: Int64 = 0
    @State private var voices: [SpeakerDirectory.Summary] = []
    @State private var renamingVoice: String?
    @State private var draftVoiceName = ""
    @State private var confirmForgetAll = false

    var body: some View {
        PaneScaffold(title: "General", subtitle: "Where notes go, what is kept, and how Minutes starts.") {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Notes folder")
                Card {
                    HStack(spacing: Tok.s4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(prefs.notesFolder()?.path ?? "Not set").font(.body).lineLimit(1)
                                .truncationMode(.middle)
                            Text("One Markdown file per meeting is written here.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                        }
                        Spacer()
                        Button("Choose…") { choose() }.buttonStyle(.bordered).controlSize(.small)
                        if let f = prefs.notesFolder() {
                            Button("Show") { NSWorkspace.shared.open(f) }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Your name in transcripts")
                Card {
                    HStack(spacing: Tok.s4) {
                        TextField("Me", text: Binding(
                            get: { prefs.localSpeakerName },
                            set: { prefs.localSpeakerName = $0.isEmpty ? "Me" : $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Text("Used for everything recorded from your microphone.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                        Spacer()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Recorded audio")
                Card {
                    VStack(alignment: .leading, spacing: Tok.s4) {
                        Picker(selection: Binding(
                            get: { prefs.keepAudio },
                            set: { prefs.keepAudio = $0 })) {
                            Text("Keep audio after the note is written").tag(true)
                            Text("Delete audio once the note is written").tag(false)
                        } label: { EmptyView() }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        // The trade-off is stated, not hidden (FR-44).
                        Text(prefs.keepAudio
                             ? "Keeping audio lets a failed transcription be retried later."
                             : "Deleting audio saves disk space, but a failed transcription cannot be retried.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)

                        Divider()
                        HStack(spacing: Tok.s4) {
                            Text("Audio on disk: \(Fmt.bytes(audioBytes))")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(Tok.textSecondary)
                            Spacer()
                            // The pane offered to *delete* this and no way to *look*
                            // at it. Recordings live under ~/Library, which Finder
                            // hides, so "where are my audio files" had no answer
                            // anywhere in the app.
                            Button("Show in Finder") { revealAudio() }
                                .buttonStyle(.borderless).font(.caption)
                            Button("Delete all recorded audio") { clearAudio() }
                                .buttonStyle(.borderless).font(.caption)
                                .disabled(audioBytes == 0)
                        }
                        Text("Recordings are kept per meeting under ~/Library/Application Support/Minutes/Meetings. Two files each: your microphone, and the far end.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Dock")
                Card {
                    Toggle(isOn: Binding(
                        get: { prefs.showInDock },
                        set: { prefs.showInDock = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Show Minutes in the Dock").font(.body)
                            Text(prefs.showInDock
                                 ? "Also appears in Command-Tab."
                                 : "Menu bar only — no Dock icon, and not in Command-Tab.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Startup")
                Card {
                    VStack(alignment: .leading, spacing: Tok.s3) {
                        Toggle(isOn: Binding(
                            get: { launchAtLogin },
                            set: { setLogin($0) })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Start Minutes at login").font(.body)
                                Text("A menu bar tool you have to launch by hand tends not to get used.")
                                    .font(.caption).foregroundStyle(Tok.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!LoginItem.isSupported)
                        if !LoginItem.isSupported {
                            Text("Available once Minutes is running from an app bundle.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                        } else if LoginItem.usesLaunchAgent {
                            // Says which mechanism and what to expect, rather than
                            // silently behaving differently from the modern one.
                            Text("Takes effect at your next login. This build is ad-hoc signed, so Minutes registers a login item in your own Library rather than appearing under Login Items in System Settings.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let loginError {
                            Text(loginError).font(.caption).foregroundStyle(Tok.recording)
                        }
                    }
                }
            }

            // FR-51. This section used to be one paragraph and a single
            // destructive "Forget all": the app remembered voices and gave the user
            // no way to see what it thought it knew, so a wrong match could only be
            // corrected by recording a meeting that happened to contain that voice.
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Remembered voices", trailing: AnyView(
                    Group {
                        if !voices.isEmpty {
                            Button("Forget all") { confirmForgetAll = true }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                ))
                Card {
                    VStack(alignment: .leading, spacing: Tok.s3) {
                        Text("When you rename a speaker, Minutes remembers that voice so it arrives named next time. This stays on this Mac and is never sent anywhere.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if voices.isEmpty {
                            Divider()
                            Text("No voices remembered yet. Rename a speaker in a meeting and it will appear here.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                        } else {
                            ForEach(voices) { v in
                                Divider()
                                voiceRow(v)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            Task { audioBytes = await MeetingStore.shared.audioBytes() }
            reloadVoices()
        }
        .alert("Forget every remembered voice?", isPresented: $confirmForgetAll) {
            Button("Cancel", role: .cancel) { }
            Button("Forget all", role: .destructive) {
                Task { await SpeakerDirectory.shared.forgetAll(); reloadVoices() }
            }
        } message: {
            Text("\(voices.count) \(voices.count == 1 ? "voice" : "voices") will be forgotten. Speakers in meetings already written keep their names; future meetings will start from anonymous labels again.")
        }
    }

    // MARK: - Remembered voices (FR-51)

    @ViewBuilder
    private func voiceRow(_ v: SpeakerDirectory.Summary) -> some View {
        HStack(spacing: Tok.s4) {
            Image(systemName: "waveform.circle")
                .foregroundStyle(Tok.brand).frame(width: 20)

            if renamingVoice == v.name {
                TextField("Name", text: $draftVoiceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { commitRename(from: v.name) }
                Button("Save") { commitRename(from: v.name) }
                    .buttonStyle(.borderless).font(.caption)
                Button("Cancel") { renamingVoice = nil }
                    .buttonStyle(.borderless).font(.caption)
                    .foregroundStyle(Tok.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.name).font(.body)
                    // Provenance, so a match is judgeable: a one-sample voice is a
                    // guess, a twelve-sample voice is established.
                    Text("\(v.samples) \(v.samples == 1 ? "meeting" : "meetings") · last heard \(relative(v.updatedAt))")
                        .font(.caption).foregroundStyle(Tok.textSecondary)
                }
                Spacer()
                Button("Rename") {
                    draftVoiceName = v.name
                    renamingVoice = v.name
                }
                .buttonStyle(.borderless).font(.caption)
                Button {
                    Task { await SpeakerDirectory.shared.forget(name: v.name); reloadVoices() }
                } label: {
                    Image(systemName: "minus.circle").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tok.textSecondary)
                .help("Forget \(v.name)")
            }
        }
        .padding(.vertical, 6)
    }

    private func commitRename(from old: String) {
        let new = draftVoiceName
        renamingVoice = nil
        Task {
            await SpeakerDirectory.shared.rename(from: old, to: new)
            reloadVoices()
        }
    }

    private func reloadVoices() {
        Task { voices = await SpeakerDirectory.shared.summaries() }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func revealAudio() {
        Task {
            let root = await MeetingStore.shared.meetingsRoot
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.path)
        }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.allowsMultipleSelection = false; p.prompt = "Choose"
        if p.runModal() == .OK, let url = p.url { prefs.setNotesFolder(url) }
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            launchAtLogin = LoginItem.isEnabled
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private func clearAudio() {
        Task {
            let all = await MeetingStore.shared.loadAll()
            for m in all { try? await MeetingStore.shared.deleteAudio(id: m.id) }
            audioBytes = await MeetingStore.shared.audioBytes()
            await AppStateBridge.reloadMeetings()
        }
    }
}
