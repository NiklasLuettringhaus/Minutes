import SwiftUI
import AppKit

/// Entry point. Branches to a headless self-test before the GUI starts, so the
/// whole pipeline can be exercised from a terminal — which is also the only way
/// to verify it without clicking a menu bar item.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--benchmark") {
            Benchmark.run()
        } else if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
        } else if CommandLine.arguments.contains("--doctor") {
            Doctor.run()
        } else {
            MinutesApp.main()
        }
    }
}

struct MinutesApp: App {
    @StateObject private var app = AppState.shared
    @StateObject private var prefs = Preferences.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // FR-1: menu-bar-only. LSUIElement in Info.plist keeps it out of the Dock.
        MenuBarExtra {
            MenuBarContent(openWindow: { pane in
                Preferences.shared.lastPane = pane.rawValue
                AppDelegate.shared?.showWindow()
            })
            .environmentObject(app)
            .environmentObject(prefs)
        } label: {
            // SwiftUI renders this as a template unless we hand it a non-template
            // NSImage, and Recording's colour is load-bearing.
            Image(nsImage: MenuBarIcon.image(for: app.sessionState,
                                             isAsking: app.pendingPrompt != nil))
                .accessibilityLabel(MenuBarIcon.accessibilityLabel(
                    for: app.sessionState, elapsed: app.elapsed,
                    asking: app.pendingPrompt?.appName))
        }
    }
}

/// Owns the single window (FR-5) and the app lifecycle wiring.
///
/// A plain `Window` scene is avoided deliberately: `MenuBarExtra` plus a scene
/// gives SwiftUI license to restore or duplicate windows, and "exactly one
/// window ever exists" is a requirement rather than a preference.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Log.app.info("Minutes launched")

        // Reuse anything the library already downloaded to its own default
        // location rather than costing the user a second 600 MB fetch.
        ModelStorage.adoptLegacyDownloads()

        DockVisibility.apply(Preferences.shared.showInDock)
        Notifier.shared.configure()
        Task { await Notifier.shared.refreshAuthorization() }
        SessionCoordinator.shared.refreshMicAuthorization()
        ModelCatalog.shared.loadLocalRecommendations()
        ModelCatalog.shared.refreshDownloadStates()
        DetectionService.shared.start()

        Task { await AppStateBridge.reloadMeetings() }

        // First run opens the window so the user is guided to a working state
        // (FR-41). Afterwards it stays out of the way.
        if !Preferences.shared.didCompleteFirstRun {
            Preferences.shared.didCompleteFirstRun = true
            Preferences.shared.lastPane = MainWindow.Pane.gettingStarted.rawValue
            DispatchQueue.main.async { [weak self] in self?.showWindow() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave a Session half-recorded on quit.
        if SessionCoordinator.shared.isRecording {
            let sem = DispatchSemaphore(value: 0)
            Task { await SessionCoordinator.shared.stop(); sem.signal() }
            _ = sem.wait(timeout: .now() + 5)
        }
        DetectionService.shared.stop()
    }

    /// Closing the window does not quit the app; it is menu-bar-resident.
    func showWindow() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = MainWindow()
            .environmentObject(AppState.shared)
            .environmentObject(Preferences.shared)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = "Minutes"
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: root)
        w.delegate = self
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Keep the instance so reopening restores the last pane rather than
        // rebuilding from scratch.
    }
}
