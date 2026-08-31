import SwiftUI
import AppKit

/// FR-34 / FR-44 / FR-45 / FR-21 (local speaker name).
struct GeneralPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var audioBytes: Int64 = 0

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
                        HStack {
                            Text("Audio on disk: \(Fmt.bytes(audioBytes))")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(Tok.textSecondary)
                            Spacer()
                            Button("Delete all recorded audio") { clearAudio() }
                                .buttonStyle(.borderless).font(.caption)
                                .disabled(audioBytes == 0)
                        }
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
                        }
                        if let loginError {
                            Text(loginError).font(.caption).foregroundStyle(Tok.recording)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Remembered voices")
                Card {
                    VStack(alignment: .leading, spacing: Tok.s3) {
                        Text("When you rename a speaker, Minutes remembers that voice so it arrives named next time. This stays on this Mac and is never sent anywhere.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                        Button("Forget all remembered voices") {
                            Task { await SpeakerDirectory.shared.forgetAll() }
                        }
                        .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            Task { audioBytes = await MeetingStore.shared.audioBytes() }
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
