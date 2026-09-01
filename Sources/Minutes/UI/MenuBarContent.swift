import SwiftUI
import AppKit

/// FR-2 — the product's most-seen element.
///
/// The three states differ in **silhouette as well as tint**, so the icon stays
/// readable in a greyscale menu bar and for a colour-blind user (NFR-7). Idle is
/// a template image so macOS tints it to match the menu bar; Recording and
/// Transcribing are rendered with their own colour, because that colour carries
/// meaning the system must not override.
enum MenuBarIcon {
    /// `isAsking` wins over Idle: a detected meeting the user has not answered is
    /// the one thing the icon must not stay silent about, since the prompt itself
    /// can be suppressed by the system.
    ///
    /// `pulsePhase` implements FR-50 by varying the Recording tint's alpha over a
    /// four-phase cycle. It is deliberately a *variation on an already-legible
    /// state*, never the carrier of it: FR-2's silhouette-and-tint rule still
    /// distinguishes Recording, so the pulse survives a greyscale menu bar and a
    /// colour-blind reader losing nothing (NFR-7).
    static func image(for state: AppState.SessionState, isAsking: Bool = false,
                      pulsePhase: Int = 0) -> NSImage {
        if isAsking, case .idle = state {
            return tinted("waveform.badge.exclamationmark", color: NSColor(Tok.brand))
        }
        switch state {
        case .idle:
            return template("waveform")
        case .recording:
            return tinted("record.circle.fill",
                          color: NSColor(Tok.recording).withAlphaComponent(pulseAlpha(pulsePhase)))
        case .transcribing:
            return tinted("ellipsis.circle", color: NSColor(Tok.transcribing))
        }
    }

    /// Never dips far enough to read as "off" — a status light that blinks out
    /// looks like a fault, and the ask was to animate it *slightly*.
    static func pulseAlpha(_ phase: Int) -> CGFloat {
        switch phase % 4 {
        case 0:  return 1.0
        case 1:  return 0.72
        case 2:  return 0.5
        default: return 0.72
        }
    }

    private static func template(_ name: String) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(cfg) ?? NSImage()
        img.isTemplate = true
        return img
    }

    private static func tinted(_ name: String, color: NSColor) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(cfg) ?? NSImage()
        img.isTemplate = false
        return img
    }

    /// VoiceOver states meaning, not appearance (NFR-7).
    static func accessibilityLabel(for state: AppState.SessionState, elapsed: TimeInterval,
                                   asking: String? = nil) -> String {
        if let asking, case .idle = state {
            return "Minutes, asking whether to record \(asking)"
        }
        switch state {
        case .idle: return "Minutes, idle"
        case .recording(_, let degraded):
            let base = "Minutes, recording, \(Fmt.duration(elapsed))"
            return degraded ? base + ", microphone only" : base
        case .transcribing: return "Minutes, transcribing"
        }
    }
}

/// The menu. At most 8 items in any state, and Start/Stop are never both
/// present (FR-3, FR-5).
struct MenuBarContent: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    let openWindow: (MainWindow.Pane) -> Void

    var body: some View {
        Group {
            // A pending ask sits above everything else. It is repeated here because
            // the notification that normally carries it can be denied, dismissed or
            // missed, and then this is the only place it survives.
            if let p = app.pendingPrompt, app.sessionState == .idle {
                Text("\(p.appName) is using your microphone")
                Button("Record \(p.appName) Meeting") {
                    AppState.shared.pendingPrompt = nil
                    PromptPanel.shared.dismiss()
                    Task { await SessionCoordinator.shared.start(triggeredBy: p) }
                }
                Button("Not Now") {
                    AppState.shared.pendingPrompt = nil
                    PromptPanel.shared.dismiss()
                }
                Divider()
            }

            switch app.sessionState {
            case .idle:
                Button("Start Recording") { Task { await SessionCoordinator.shared.start() } }

            case .recording(let since, let degraded):
                // Disabled items, not headers, so VoiceOver reads them in order.
                Text("Recording — \(Fmt.duration(Date().timeIntervalSince(since)))")
                Text(app.micMuted ? "Your mic is muted — far end only"
                                  : (degraded ? "Mic only ⚠" : "Mic + system audio"))
                Divider()
                // Muting in Slack or Teams stops their outgoing stream, not the
                // macOS input device, so this is the only switch that stops Minutes
                // recording the room around you.
                Button(app.micMuted ? "Unmute My Microphone" : "Mute My Microphone") {
                    SessionCoordinator.shared.setMicMuted(!app.micMuted)
                }
                Button("Stop Recording") { Task { await SessionCoordinator.shared.stop() } }

            case .transcribing(_, let title):
                Text("Transcribing \(title.map { "“\($0)”" } ?? "meeting")…")
                Divider()
                // Transcribing does not block a new Session — it queues (FR-20).
                Button("Start Recording") { Task { await SessionCoordinator.shared.start() } }
            }

            Divider()
            Button("Meetings…") { openWindow(.meetings) }
            Button("Settings…") { openWindow(.gettingStarted) }
            Divider()
            Button("Quit Minutes") { NSApplication.shared.terminate(nil) }
        }
    }
}
