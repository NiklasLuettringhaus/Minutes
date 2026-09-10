import Foundation
import CoreAudio
import AppKit

/// A meeting Minutes believes is underway.
struct DetectedMeeting: Identifiable, Equatable {
    /// **The watched app, not the process that happens to hold the device.**
    ///
    /// Identity used to be `bundleID`, and `bundleID` is whichever helper
    /// process was found holding the input device — `com.microsoft.teams2` ships
    /// no bare audio process object, only `.modulehost`, `.helper` and
    /// `.notificationcenter` (AD-5). Two of those can hold the device across one
    /// call, the enumeration order that picks between them is not guaranteed to
    /// be stable, and the app swaps between them when audio moves to different
    /// hardware. So the identity of a meeting changed while the meeting did not,
    /// and a meeting whose identity changes looks exactly like one meeting
    /// ending and another beginning.
    ///
    /// The prefix is the thing that is actually stable, and AD-5 already made it
    /// the unit of *matching*. This makes it the unit of identity too.
    var id: String { watchedPrefix }
    /// The watched-app prefix this holder matched.
    let watchedPrefix: String
    /// The specific process holding the device. Kept for the log and for
    /// provenance on the Meeting record — never for identity.
    let bundleID: String
    let appName: String
}

/// AD-5 / AD-6: watches which applications hold the audio *input* device.
///
/// Two rules here were established by measurement, and both matter:
///
///  - **Prefix matching is mandatory.** Teams exposes no bare
///    `com.microsoft.teams2` audio process object — only `.modulehost`,
///    `.helper` and `.notificationcenter`. Exact matching detects Teams *never*.
///  - **Polling is the source of truth.** `kAudioProcessPropertyIsRunningInput`
///    listeners are documented as not always firing, so a timer poll decides and
///    listeners only shorten latency.
///
/// AD-6: reads process/device *properties* only. It never reads audio content —
/// that is a privacy invariant, not an optimisation.
@MainActor
final class DetectionService: ObservableObject {
    static let shared = DetectionService()

    struct WatchedApp: Identifiable, Hashable {
        var id: String { bundleIDPrefix }
        let bundleIDPrefix: String
        let displayName: String
        var isBuiltIn: Bool = false
    }

    /// Slack and Teams ship built in — the two that were asked for. Anything
    /// else the user adds themselves, because every extra watched app is another
    /// source of spurious prompts, and SM-C1 prefers a missed huddle to a nag.
    static let builtIn: [WatchedApp] = [
        WatchedApp(bundleIDPrefix: "com.tinyspeck.slackmacgap", displayName: "Slack", isBuiltIn: true),
        WatchedApp(bundleIDPrefix: "com.microsoft.teams2", displayName: "Microsoft Teams", isBuiltIn: true),
    ]

    /// Built-ins plus whatever the user has added.
    @MainActor
    static var watched: [WatchedApp] {
        builtIn + Preferences.shared.customWatchedApps.compactMap { entry in
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            guard let id = parts.first, !id.isEmpty else { return nil }
            return WatchedApp(bundleIDPrefix: id,
                              displayName: parts.count > 1 ? parts[1] : id,
                              isBuiltIn: false)
        }
    }

    /// Seconds the input device must stay held before we prompt, so notification
    /// sounds and device probes do not trigger it (FR-12).
    ///
    /// Tuned down from 4.0s debounce / 2.0s poll after the first real huddle, where
    /// the prompt took up to 6s and the user described it as slow. The risk a long
    /// debounce guards against is a spurious prompt from a brief device probe — but
    /// the watch list is only Slack and Teams, and neither acquires the *input*
    /// device to play a notification sound. 3.5s worst case is the trade.
    private static let debounce: TimeInterval = 2.5
    private static let pollInterval: TimeInterval = 1.0

    /// Seconds a watched app may hold no input device at all before the meeting
    /// is believed to be over (FR-106).
    ///
    /// Switching audio hardware mid-call makes the app release one input device
    /// and take another, and between the two it holds neither. That gap used to
    /// end the recording, because absence was acted on the moment it was seen.
    ///
    /// FR-14's own testable consequence allows thirty seconds to notice a
    /// meeting has ended, so this spends a portion of a budget that was already
    /// granted and never used. Twelve seconds is the trade: comfortably longer
    /// than any device switch measured on this machine, comfortably inside
    /// FR-14's deadline, and it costs up to twelve seconds of recorded silence
    /// after a real meeting ends — which the transcript drops anyway, and which
    /// is cheap next to losing the second half of a call.
    static let releaseGrace: TimeInterval = 12.0

    @Published private(set) var activeApps: [DetectedMeeting] = []

    private var timer: Timer?
    private var window = DetectionWindow(debounce: DetectionService.debounce,
                                         grace: DetectionService.releaseGrace)

    private init() {}

    func start() {
        guard timer == nil else { return }
        guard Preferences.shared.detectionEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.5
        Log.detection.info("detection started")
    }

    /// Disabling detection stops all polling — verifiable by the absence of
    /// periodic audio-process enumeration (FR-43).
    func stop() {
        timer?.invalidate(); timer = nil
        window.reset()
        activeApps = []
        Log.detection.info("detection stopped")
    }

    func restart() {
        stop()
        if Preferences.shared.detectionEnabled { start() }
    }

    // MARK: - Poll

    private func poll() {
        let holders = Self.appsUsingAudioInput()
        activeApps = holders

        let now = Date()
        let verdict = window.update(held: Set(holders.map(\.id)), now: now)

        // Ended: the app has held no input device for longer than the grace
        // period. Auto-stop if this Session came from a Detection Prompt for
        // that app (FR-14).
        for id in verdict.ended {
            Log.detection.info("\(id, privacy: .public) released the input device for \(Int(Self.releaseGrace), privacy: .public)s — treating the meeting as over")
            Task { await SessionCoordinator.shared.autoStopIfTriggered(by: id) }
        }

        for h in holders where verdict.candidates.contains(h.id) {
            guard !Preferences.shared.isSuppressed(h.watchedPrefix) else { continue }
            guard !SessionCoordinator.shared.isRecording else { continue }
            guard AppState.shared.sessionState == .idle else { continue }

            window.announce(h.id)
            Log.detection.info("prompting for \(h.bundleID, privacy: .public)")
            AppState.shared.pendingPrompt = h
            // The panel is the prompt, and the notification is a record of it.
            //
            // This was the other way round until the first real huddle, where the
            // notification arrived with no visible buttons and the user had to go
            // and start recording by hand. macOS shows notification actions only
            // when the banner is hovered or expanded, and under Banner style it
            // auto-dismisses before most people get there — so the one channel
            // carrying the Record button was the one channel that might never show
            // it. The panel has real buttons, is non-activating exactly like the
            // notification, and does not depend on a System Settings alert style.
            // FR-12, and the surface is the user's choice (`PromptDelivery`).
            //
            // **The panel is the fallback and it is not optional.** If the user
            // chose the notification and notification permission is absent, the
            // ask still has to arrive somewhere: a preference that silently
            // results in no prompt at all is how a real Teams call went
            // unprompted with nothing to show for it. So `notification` degrades
            // to the panel rather than to silence — the same rule FR-7 applies
            // to the System Stream.
            let choice = Preferences.shared.promptDelivery
            let canNotify = Notifier.shared.canDeliver
            if choice.showsPanel || !canNotify {
                PromptPanel.shared.present(h)
            }
            if choice.showsNotification, canNotify {
                Notifier.shared.askToRecord(h)
            }
        }
    }

    // MARK: - CoreAudio enumeration

    /// Watched apps currently holding the audio input device, matched by
    /// bundle-ID **prefix** (AD-5).
    @MainActor
    static func appsUsingAudioInput() -> [DetectedMeeting] {
        let list = watched
        var out: [DetectedMeeting] = []
        var seen = Set<String>()
        for obj in processObjects() {
            guard let bundle = bundleID(obj), isRunningInput(obj) else { continue }
            guard let w = list.first(where: { bundle.hasPrefix($0.bundleIDPrefix) }) else { continue }
            guard !seen.contains(w.bundleIDPrefix) else { continue }
            seen.insert(w.bundleIDPrefix)
            out.append(DetectedMeeting(watchedPrefix: w.bundleIDPrefix,
                                       bundleID: bundle,
                                       appName: w.displayName))
        }
        return out
    }

    /// The watched-app prefix a bundle ID belongs to, or nil when it belongs to
    /// none. The one place a full bundle ID is turned back into an identity —
    /// needed because a notification carries the bundle ID it was posted with,
    /// and that notification may have been posted by an earlier build.
    @MainActor
    static func watchedPrefix(for bundleID: String) -> String? {
        watched.first { bundleID.hasPrefix($0.bundleIDPrefix) }?.bundleIDPrefix
    }

    /// Any app holding the input device, for diagnostics in the Detection pane.
    static func allAppsUsingAudioInput() -> [String] {
        var out: [String] = []
        for obj in processObjects() {
            guard isRunningInput(obj) else { continue }
            if let b = bundleID(obj) { out.append(b) }
            else if let p = pid(obj), let app = NSRunningApplication(processIdentifier: p) {
                out.append(app.localizedName ?? "pid \(p)")
            }
        }
        return out
    }

    static func processObjects() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                            &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                        &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func isRunningInput(_ obj: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr else { return false }
        return v != 0
    }

    static func bundleID(_ obj: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: Unmanaged<CFString>?
        let st = withUnsafeMutablePointer(to: &out) { p in
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, p)
        }
        guard st == noErr else { return nil }
        let s = out?.takeUnretainedValue() as String?
        return (s?.isEmpty ?? true) ? nil : s
    }

    static func pid(_ obj: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var v: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }
}
