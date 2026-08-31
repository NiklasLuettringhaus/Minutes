import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// FR-43 / FR-15. Detection is a convenience over a fundamentally unreliable
/// signal, so this pane is honest about that and makes being left alone easy —
/// SM-C1 prefers a missed huddle to a spurious prompt.
struct DetectionPane: View {
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var detection = DetectionService.shared
    @ObservedObject var notifier = Notifier.shared
    @State private var live: [String] = []
    @State private var addError: String?

    var body: some View {
        PaneScaffold(title: "Detection",
                     subtitle: "Offers to record when a meeting app starts using your microphone.") {
            Card {
                Toggle(isOn: Binding(
                    get: { prefs.detectionEnabled },
                    set: { prefs.detectionEnabled = $0; detection.restart() }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Offer to record detected meetings").font(.body)
                        Text("Minutes never starts recording on its own — it only asks.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }

            // How the ask reaches you. This exists because it silently did not:
            // notification permission was denied, the prompt was posted anyway, and
            // a real Teams call produced nothing at all.
            if prefs.detectionEnabled {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "How Minutes asks")
                    Card {
                        HStack(alignment: .top, spacing: Tok.s4) {
                            Image(systemName: notifier.canDeliver ? "bell.badge" : "macwindow.on.rectangle")
                                .foregroundStyle(notifier.canDeliver ? Tok.brand : Tok.textSecondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notifier.canDeliver ? "With a notification" : "With a floating panel")
                                    .font(.body)
                                Text(deliveryExplanation)
                                    .font(.caption).foregroundStyle(Tok.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Tok.s4)
                            if !notifier.canDeliver {
                                Button("Open Settings") { Notifier.openSettings() }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Watched apps", trailing: AnyView(
                    Button {
                        pickApp()
                    } label: { Label("Add app…", systemImage: "plus").font(.caption) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tok.brand)
                ))
                Card {
                    let list = DetectionService.watched
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, w in
                        HStack(spacing: Tok.s4) {
                            if let icon = appIcon(for: w.bundleIDPrefix) {
                                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                            } else {
                                Image(systemName: "app.dashed")
                                    .foregroundStyle(Tok.textSecondary).frame(width: 22)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: Tok.s3) {
                                    Text(w.displayName).font(.body)
                                    if !w.isBuiltIn {
                                        Text("added by you").font(.caption2)
                                            .foregroundStyle(Tok.textSecondary)
                                    }
                                }
                                Text(isActive(w) ? "Using your microphone now."
                                                 : "Not using your microphone.")
                                    .font(.caption).foregroundStyle(Tok.textSecondary)
                            }
                            Spacer()
                            if !w.isBuiltIn {
                                Button {
                                    prefs.removeWatchedApp(bundleID: w.bundleIDPrefix)
                                    DetectionService.shared.restart()
                                } label: { Image(systemName: "minus.circle").font(.caption) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Tok.textSecondary)
                                .help("Stop watching \(w.displayName)")
                            }
                            Toggle("", isOn: Binding(
                                get: { !prefs.isSuppressed(w.bundleIDPrefix) },
                                set: { on in
                                    if on { prefs.unsuppress(w.bundleIDPrefix) }
                                    else { prefs.suppress(w.bundleIDPrefix) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!prefs.detectionEnabled)
                        }
                        .padding(.vertical, 8)
                        if idx < list.count - 1 { RowDivider() }
                    }
                    if let addError {
                        Text(addError).font(.caption).foregroundStyle(Tok.recording)
                            .padding(.top, Tok.s3)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "What Minutes can see")
                Card {
                    VStack(alignment: .leading, spacing: Tok.s3) {
                        // AD-6: this is a privacy invariant, stated plainly because
                        // it is the kind of claim a user should be able to check.
                        Text("Minutes only reads which apps hold the microphone. It never listens to audio unless you are recording.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                        Divider()
                        if live.isEmpty {
                            Text("No app is using the microphone right now.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                        } else {
                            ForEach(live, id: \.self) { id in
                                HStack(spacing: Tok.s3) {
                                    Circle().fill(Tok.recording).frame(width: 6, height: 6)
                                    Text(id).font(.caption).monospaced()
                                        .foregroundStyle(Tok.textSecondary)
                                }
                            }
                        }
                    }
                }
            }

            if !prefs.suppressedApps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "Silenced")
                    Card {
                        ForEach(prefs.suppressedApps, id: \.self) { id in
                            HStack {
                                Text(name(for: id)).font(.body)
                                Spacer()
                                Button("Ask again") { prefs.unsuppress(id) }
                                    .buttonStyle(.borderless).font(.caption)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .onAppear { refreshLive(); Task { await Notifier.shared.refreshAuthorization() } }
        .task {
            // Cheap diagnostic refresh while the pane is open.
            while !Task.isCancelled {
                refreshLive()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// A real application picker rather than asking for a bundle identifier.
    /// The bundle ID is read from whatever the user chose.
    private func pickApp() {
        addError = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Watch"
        panel.message = "Choose an app that should offer to record when it uses your microphone."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            addError = "That does not look like an application bundle."
            return
        }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        if DetectionService.builtIn.contains(where: { id.hasPrefix($0.bundleIDPrefix) }) {
            addError = "\(name) is already watched."
            return
        }
        if prefs.customWatchedApps.contains(where: { $0.hasPrefix(id + "|") }) {
            addError = "\(name) is already in the list."
            return
        }
        prefs.addWatchedApp(bundleID: id, name: name)
        DetectionService.shared.restart()
    }

    /// Shown so a row is recognisable at a glance.
    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 22, height: 22)
        return icon
    }

    private var deliveryExplanation: String {
        switch notifier.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "A notification with Record, Not now, and Never for this app."
        case .denied:
            return "Notifications are turned off for Minutes, so the ask appears as a small panel in the corner instead. It never takes focus from your meeting."
        default:
            return "Notifications have not been allowed yet, so the ask appears as a small panel in the corner. It never takes focus from your meeting."
        }
    }

    private func refreshLive() {
        live = DetectionService.allAppsUsingAudioInput().sorted()
    }

    private func isActive(_ w: DetectionService.WatchedApp) -> Bool {
        live.contains { $0.hasPrefix(w.bundleIDPrefix) }
    }

    private func name(for prefix: String) -> String {
        DetectionService.watched.first { prefix.hasPrefix($0.bundleIDPrefix) }?.displayName ?? prefix
    }
}
