import SwiftUI

/// FR-43 / FR-15. Detection is a convenience over a fundamentally unreliable
/// signal, so this pane is honest about that and makes being left alone easy —
/// SM-C1 prefers a missed huddle to a spurious prompt.
struct DetectionPane: View {
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var detection = DetectionService.shared
    @State private var live: [String] = []

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

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Watched apps")
                Card {
                    ForEach(Array(DetectionService.watched.enumerated()), id: \.element.id) { idx, w in
                        HStack(spacing: Tok.s4) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.displayName).font(.body)
                                Text(isActive(w) ? "Using your microphone now."
                                                 : "Not using your microphone.")
                                    .font(.caption).foregroundStyle(Tok.textSecondary)
                            }
                            Spacer()
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
                        if idx < DetectionService.watched.count - 1 { RowDivider() }
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
        .onAppear { refreshLive() }
        .task {
            // Cheap diagnostic refresh while the pane is open.
            while !Task.isCancelled {
                refreshLive()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
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
