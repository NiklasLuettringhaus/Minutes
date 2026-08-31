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
    static func image(for state: AppState.SessionState) -> NSImage {
        switch state {
        case .idle:
            return template("waveform")
        case .recording:
            return tinted("record.circle.fill", color: NSColor(Tok.recording))
        case .transcribing:
            return tinted("ellipsis.circle", color: NSColor(Tok.transcribing))
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
    static func accessibilityLabel(for state: AppState.SessionState, elapsed: TimeInterval) -> String {
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
            switch app.sessionState {
            case .idle:
                Button("Start Recording") { Task { await SessionCoordinator.shared.start() } }

            case .recording(let since, let degraded):
                // Disabled items, not headers, so VoiceOver reads them in order.
                Text("Recording — \(Fmt.duration(Date().timeIntervalSince(since)))")
                Text(degraded ? "Mic only ⚠" : "Mic + system audio")
                Divider()
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
