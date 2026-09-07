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
        } else if CommandLine.arguments.contains("--check-rates") {
            // FR-88. Assesses every recording on disk and, with --repair, fixes
            // the ones whose true rate is recoverable and re-runs them.
            //
            // A terminal command rather than only a button, because the seven
            // recordings this exists for were repaired from a terminal and the
            // person who hits this next may have to do the same before there is
            // any UI to click.
            RateCheck.run(repair: CommandLine.arguments.contains("--repair"))
        } else if CommandLine.arguments.contains("--reprocess") {
            // Re-derives named Meetings from the audio already on disk. Never
            // "all", refuses without --yes, and rewrites Notes — which is why it
            // is a decision the user makes and not one the app makes for them.
            Reprocess.run()
        } else if CommandLine.arguments.contains("--check-clock") {
            // FR-94, FR-97. Opens both streams for a few seconds and prints what
            // the devices themselves say — the rate from their own counters, the
            // tolerance that measurement earns, holes they counted and we never
            // received, and the offset between the two streams' first samples.
            // Creates no Meeting and keeps no audio.
            ClockCheck.run()
        } else if CommandLine.arguments.contains("--check-drain") {
            // Story 17.3. Reproduces the drain-starvation mechanism against the
            // real ring and writer with a synthetic producer, so no audio device
            // is opened and it is safe during a recording.
            DrainCheck.run()
        } else if CommandLine.arguments.contains("--check-aec") {
            // FR-99 / AD-55. The measurement that has to come before the
            // feature: run the canceller over the recordings on disk and print
            // the ERLE, what it costs where there is no echo, and — with
            // --transcribe — what it does to the duplicated-word count.
            AecCheck.run(transcribe: CommandLine.arguments.contains("--transcribe"))
        } else if CommandLine.arguments.contains("--check-echo") {
            // FR-89. Runs echo detection over every recording and prints the
            // verdict, which is also how the recording gate was calibrated.
            EchoCheck.run(diarize: CommandLine.arguments.contains("--diarize"))
        } else if CommandLine.arguments.contains("--asr") {
            // Transcribes one file and prints the segments, so accuracy can be
            // scored against a reference corpus instead of assumed.
            AsrEval.run()
        } else if CommandLine.arguments.contains("--uishot") {
            // Renders the panes to PNG with fixture data, so a layout defect is
            // findable from a terminal. Needs no screen-recording permission —
            // an app rendering its own view tree captures nobody's screen.
            MainActor.assumeIsolated { UIShot.run() }
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
            // FR-49: the elapsed time has to be readable with the menu closed, so
            // it lives in the label rather than only in the menu (FR-4 covers the
            // open menu, and both requirements hold). Text is shown only while
            // Recording, so the menu bar never implies a Session that is not running.
            HStack(spacing: 3) {
                Image(nsImage: MenuBarIcon.image(for: app.sessionState,
                                                 isAsking: app.pendingPrompt != nil))
                if app.sessionState.isRecording {
                    Text(Fmt.duration(app.elapsed)).monospacedDigit()
                }
            }
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

        Task {
            await AppStateBridge.reloadMeetings()
            // A meeting left mid-pipeline by a quit is picked up here rather than
            // stranded at its last completed stage (AD-8).
            await Pipeline.shared.resumeInterrupted()
        }

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
