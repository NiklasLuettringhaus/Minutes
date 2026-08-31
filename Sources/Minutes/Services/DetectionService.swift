import Foundation
import CoreAudio
import AppKit

/// A meeting Minutes believes is underway.
struct DetectedMeeting: Identifiable, Equatable {
    var id: String { bundleID }
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
    private static let debounce: TimeInterval = 4.0
    private static let pollInterval: TimeInterval = 2.0

    @Published private(set) var activeApps: [DetectedMeeting] = []

    private var timer: Timer?
    private var firstSeen: [String: Date] = [:]
    /// One prompt per detected meeting; a declined meeting is not re-prompted
    /// while the same input session continues (FR-12).
    private var promptedThisSession: Set<String> = []

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
        firstSeen = [:]
        promptedThisSession = []
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
        let heldIDs = Set(holders.map(\.bundleID))

        // Released: clear debounce state, and auto-stop if this Session came from
        // a Detection Prompt for that app (FR-14).
        // Snapshot before mutating: iterating `firstSeen.keys` while removing from
        // `firstSeen` is undefined behaviour and can crash.
        let released = firstSeen.keys.filter { !heldIDs.contains($0) }
        for id in released {
            firstSeen.removeValue(forKey: id)
            promptedThisSession.remove(id)
            Task { await SessionCoordinator.shared.autoStopIfTriggered(by: id) }
        }

        for h in holders {
            if firstSeen[h.bundleID] == nil { firstSeen[h.bundleID] = now }
            guard let since = firstSeen[h.bundleID],
                  now.timeIntervalSince(since) >= Self.debounce else { continue }
            guard !promptedThisSession.contains(h.bundleID) else { continue }
            guard !Preferences.shared.isSuppressed(h.bundleID) else { continue }
            guard !SessionCoordinator.shared.isRecording else { continue }
            guard AppState.shared.sessionState == .idle else { continue }

            promptedThisSession.insert(h.bundleID)
            Log.detection.info("prompting for \(h.bundleID, privacy: .public)")
            AppState.shared.pendingPrompt = h
            Notifier.shared.askToRecord(h)
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
            out.append(DetectedMeeting(bundleID: bundle, appName: w.displayName))
        }
        return out
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
