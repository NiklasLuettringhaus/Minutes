import SwiftUI
import AppKit

/// The ask when a meeting ends under a Session the user started by hand.
///
/// FR-14 auto-stops a Session that came from a Detection Prompt, and deliberately
/// does not auto-stop one the user started — stopping something somebody chose to
/// start is their decision. What the first real huddle exposed is that "does not
/// auto-stop" had been implemented as "does nothing at all": the meeting ended, the
/// recording ran on, and there was no signal of either.
///
/// Same construction as `PromptPanel` and for the same reason: non-activating, so
/// it cannot steal focus, and `fullScreenAuxiliary` so it is visible over a
/// full-screen Slack or Teams window.
@MainActor
final class StopPanel {
    static let shared = StopPanel()
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    /// Longer than the record prompt's window. Ignoring "shall I stop?" means
    /// keep going, which is the safe outcome — but the panel should not sit there
    /// for the rest of the day either.
    private static let autoDismiss: TimeInterval = 120

    private init() {}

    func present(appName: String) {
        dismiss()

        let view = StopPanelView(
            appName: appName,
            onStop: { [weak self] in
                self?.dismiss()
                Task { await SessionCoordinator.shared.stop() }
            },
            onKeepGoing: { [weak self] in self?.dismiss() })

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 142)

        let p = NSPanel(contentRect: hosting.frame,
                        styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.contentView = hosting
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.standardWindowButton(.closeButton)?.isHidden = true

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - hosting.frame.width - 16,
                                     y: v.maxY - hosting.frame.height - 8))
        }
        p.orderFrontRegardless()
        panel = p

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismiss, repeats: false) { _ in
            Task { @MainActor in StopPanel.shared.dismiss() }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct StopPanelView: View {
    let appName: String
    let onStop: () -> Void
    let onKeepGoing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            HStack(spacing: Tok.s4) {
                Image(systemName: "stop.circle")
                    .font(.title2).foregroundStyle(Tok.recording)
                VStack(alignment: .leading, spacing: 1) {
                    Text("The \(appName) meeting ended")
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Minutes is still recording.")
                        .font(.caption).foregroundStyle(Tok.textSecondary)
                }
            }
            HStack(spacing: Tok.s3) {
                Button("Stop and transcribe", action: onStop)
                    .keyboardShortcut(.defaultAction)
                Button("Keep recording", action: onKeepGoing)
                Spacer()
            }
        }
        .padding(Tok.s5)
        .frame(width: 340, alignment: .leading)
    }
}
