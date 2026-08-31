import SwiftUI
import AppKit

/// The fallback ask, for when a notification cannot reach the user.
///
/// Detection had exactly one delivery channel — a `UNNotificationRequest` — and
/// when notification permission was denied the whole feature became a silent
/// no-op: the Teams call was matched correctly, the prompt was posted, and
/// nothing appeared. A convenience feature is allowed to be missed; it is not
/// allowed to be invisible.
///
/// Deliberately a **non-activating** floating panel: the user is mid-meeting, so
/// this must never pull focus, and it must be able to appear over a full-screen
/// Teams or Slack window — hence `.canJoinAllSpaces` and `.fullScreenAuxiliary`.
@MainActor
final class PromptPanel {
    static let shared = PromptPanel()
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    /// Ignoring the ask is a decline (FR-12), so an unanswered panel closes itself
    /// rather than sitting over the user's meeting for the rest of the call.
    private static let autoDismiss: TimeInterval = 90

    private init() {}

    func present(_ app: DetectedMeeting) {
        dismiss()

        let view = PromptPanelView(
            app: app,
            onRecord: { [weak self] in
                self?.dismiss()
                AppState.shared.pendingPrompt = nil
                Task { await SessionCoordinator.shared.start(triggeredBy: app) }
            },
            onNotNow: { [weak self] in
                self?.dismiss()
                AppState.shared.pendingPrompt = nil
            },
            onNever: { [weak self] in
                self?.dismiss()
                let prefix = DetectionService.watched
                    .first { app.bundleID.hasPrefix($0.bundleIDPrefix) }?.bundleIDPrefix ?? app.bundleID
                Preferences.shared.suppress(prefix)
                AppState.shared.pendingPrompt = nil
            })

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 148)

        let p = NSPanel(contentRect: hosting.frame,
                        styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                        backing: .buffered,
                        defer: false)
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

        // Top-right, tucked under the menu bar near the icon it belongs to.
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - hosting.frame.width - 16,
                                     y: v.maxY - hosting.frame.height - 8))
        }

        // orderFrontRegardless, not makeKeyAndOrderFront: the meeting keeps focus.
        p.orderFrontRegardless()
        panel = p

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismiss, repeats: false) { _ in
            Task { @MainActor in
                PromptPanel.shared.dismiss()
                AppState.shared.pendingPrompt = nil
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PromptPanelView: View {
    let app: DetectedMeeting
    let onRecord: () -> Void
    let onNotNow: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            HStack(spacing: Tok.s4) {
                if let icon = icon {
                    Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                } else {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(Tok.brand)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(app.appName) is using your microphone")
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Record this meeting?").font(.caption).foregroundStyle(Tok.textSecondary)
                }
            }
            HStack(spacing: Tok.s3) {
                Button("Record", action: onRecord)
                    .keyboardShortcut(.defaultAction)
                Button("Not now", action: onNotNow)
                Spacer()
                Button("Never for \(app.appName)", action: onNever)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Tok.textSecondary)
            }
        }
        .padding(Tok.s5)
        .frame(width: 340, alignment: .leading)
    }

    private var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
