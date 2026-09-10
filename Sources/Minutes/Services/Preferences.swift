import Foundation
import AppKit

/// Scalars in UserDefaults; the Notes Folder as a security-scoped bookmark rather
/// than a path string. Owns the single balanced start/stopAccessingSecurityScopedResource
/// pair — no other component starts or stops access (architecture convention).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let d = UserDefaults.standard
    private enum K {
        static let model = "transcriptionModel"
        static let notesBookmark = "notesFolderBookmark"
        static let localSpeakerName = "localSpeakerName"
        static let detectionEnabled = "detectionEnabled"
        static let suppressedApps = "suppressedApps"
        static let keepAudio = "keepAudio"
        static let launchAtLogin = "launchAtLogin"
        static let lastPane = "lastPane"
        static let promptDelivery = "promptDelivery"
        static let didCompleteFirstRun = "didCompleteFirstRun"
        static let lastSystemCaptureOK = "lastSystemCaptureOK"
        static let lastThroughput = "lastThroughputRatio"
        static let removeFiller = "removeFillerWords"
        static let fillerWords = "fillerWords"
        static let customWatchedApps = "customWatchedApps"
        static let showInDock = "showInDock"
        static let metadataBackend = "metadataBackend"
        static let dismissedUnclaimed = "dismissedUnclaimedNotes"
    }

    /// The measured-best engine for meetings, and the one `ModelCatalog` already
    /// marks `.recommended` — so the default finally agrees with the picker
    /// instead of contradicting it.
    ///
    /// `spikes/investigation-transcription-quality-2026-09-03` measured both
    /// Parakeet variants at or ahead of Whisper large-v3-turbo *everywhere*, at
    /// ~8× the speed: a tie on close mics (22.6% vs 22.8% WER) and an **11.4-point**
    /// lead far-field (29.4% vs 40.8%, proper-noun recall 77% vs 60%) — and the
    /// meeting room, where echo also lives, is exactly the far-field case. The old
    /// default here *was* that Whisper turbo: the measured-worse, 8×-slower engine.
    /// That mismatch is the whole of "FluidVoice's transcription is far superior" —
    /// FluidVoice is this same Parakeet, which we shipped but did not default to.
    ///
    /// v3 over v2-en on purpose. v3 is multilingual (25 European languages, Danish
    /// among them) and trails v2-en by only 0.4 pts far-field; v2-en's single
    /// measured edge is English close mics (+2.3 pts), inside a ±8-pt per-session
    /// swing. A recorder that must not mangle a non-English call defaults to the
    /// multilingual model; v2-en stays one click away for an English-only user.
    ///
    /// Migration is intentional and safe: `init` reads `d.string(forKey:) ?? this`,
    /// and `model`'s `didSet` never fires for that initial read (Swift does not run
    /// observers during initialization). So a user who only ever took the default
    /// never had a value written and moves to v3 on upgrade; a user who *picked* a
    /// model persisted it through the observer and keeps that exact choice.
    static let defaultModel = ParakeetModel.v3

    @Published var model: String {
        didSet { d.set(model, forKey: K.model) }
    }
    @Published var localSpeakerName: String {
        didSet { d.set(localSpeakerName, forKey: K.localSpeakerName) }
    }
    @Published var detectionEnabled: Bool {
        didSet { d.set(detectionEnabled, forKey: K.detectionEnabled) }
    }
    @Published var suppressedApps: [String] {
        didSet { d.set(suppressedApps, forKey: K.suppressedApps) }
    }
    @Published var keepAudio: Bool {
        didSet { d.set(keepAudio, forKey: K.keepAudio) }
    }
    /// Off by default: FR-1 makes this a menu bar tool, and `LSUIElement` in
    /// Info.plist starts it that way. The toggle overrides the activation policy at
    /// runtime rather than the plist, so it takes effect without a relaunch.
    /// FR-52. `auto` means AD-12's original behaviour: use the on-device LLM when
    /// it is available, otherwise the deterministic backend. `heuristic` pins the
    /// deterministic one even when the LLM is available, because a reproducible
    /// summary is sometimes the one you want.
    enum MetadataBackendChoice: String, CaseIterable {
        case auto, heuristic
    }
    @Published var metadataBackend: MetadataBackendChoice {
        didSet { d.set(metadataBackend.rawValue, forKey: K.metadataBackend) }
    }

    /// How the Detection Prompt reaches the user (FR-12).
    ///
    /// **A choice because both surfaces are defensible and they were shipped
    /// together, which is neither.** The notification came first and failed in
    /// the first real huddle: macOS shows a notification's actions only when the
    /// banner is hovered or expanded, and under Banner style it auto-dismisses
    /// before most people get there, so the one channel carrying the Record
    /// button was the one that might never show it. The panel was added with
    /// real buttons — and the notification was kept beside it as a durable
    /// record, reachable in Notification Centre after the panel's 90 seconds.
    ///
    /// Two prompts for one question is its own defect: the user gets a slide-in
    /// *and* a panel, has to work out which one carries the buttons, and
    /// answering one does not visibly resolve the other. So the app stops
    /// deciding for everybody. The default is the panel alone, because it is the
    /// surface that always shows its buttons.
    enum PromptDelivery: String, CaseIterable {
        /// The floating panel only. Always shows its buttons; closes after 90 s.
        case panel
        /// The notification only. Survives in Notification Centre; its buttons
        /// may be hidden until the banner is hovered.
        case notification
        /// Both, which is what shipped before this was a choice.
        case both

        var title: String {
            switch self {
            case .panel: return "A floating panel"
            case .notification: return "A notification"
            case .both: return "Both"
            }
        }

        var detail: String {
            switch self {
            case .panel:
                return "A small panel in the corner with Record, Not now and Never for this app. "
                    + "It never takes focus from your meeting and closes itself after 90 seconds."
            case .notification:
                return "A notification that stays in Notification Centre until you answer it. "
                    + "macOS may hide its buttons until you hover the banner."
            case .both:
                return "The panel to answer, and a notification as a record you can come back to. "
                    + "Two prompts for one meeting."
            }
        }

        /// Whether this choice needs notification permission to work at all.
        var needsNotifications: Bool { self != .panel }

        var showsPanel: Bool { self != .notification }
        var showsNotification: Bool { self != .panel }
    }

    @Published var promptDelivery: PromptDelivery {
        didSet { d.set(promptDelivery.rawValue, forKey: K.promptDelivery) }
    }
    @Published var showInDock: Bool {
        didSet {
            d.set(showInDock, forKey: K.showInDock)
            DockVisibility.apply(showInDock)
        }
    }
    /// On by default: a long meeting transcript is genuinely hard to read with
    /// every clause opening "um, uh, so".
    @Published var removeFillerWords: Bool {
        didSet { d.set(removeFillerWords, forKey: K.removeFiller) }
    }
    @Published var fillerWords: [String] {
        didSet { d.set(fillerWords, forKey: K.fillerWords) }
    }
    /// Apps the user added themselves, as `bundleID|Display Name` pairs.
    /// Slack and Teams ship built in; anything else is opt-in, because a
    /// wider watch list means more spurious prompts (SM-C1).
    @Published var customWatchedApps: [String] {
        didSet { d.set(customWatchedApps, forKey: K.customWatchedApps) }
    }
    @Published var didCompleteFirstRun: Bool {
        didSet { d.set(didCompleteFirstRun, forKey: K.didCompleteFirstRun) }
    }
    /// Filenames of Unclaimed Notes the user has dismissed from the Library
    /// footer (FR-82).
    ///
    /// A list of names here rather than a marker in the file, because the file's
    /// Meeting no longer exists and writing to an orphan to record that the app
    /// should stop mentioning it is worse than remembering it locally. Dismissing
    /// changes the listing and never touches the file.
    @Published var dismissedUnclaimedNotes: [String] {
        didSet { d.set(dismissedUnclaimedNotes, forKey: K.dismissedUnclaimed) }
    }
    /// The only evidence we can have about system-audio permission: whether the
    /// last capture actually produced audio. macOS exposes no query API (FR-42).
    @Published var lastSystemCaptureOK: Bool? {
        didSet {
            if let v = lastSystemCaptureOK { d.set(v, forKey: K.lastSystemCaptureOK) }
            else { d.removeObject(forKey: K.lastSystemCaptureOK) }
        }
    }
    /// Seconds of wall-clock transcription per second of audio, measured on this
    /// machine by the Test Playground. Drives honest guidance in the model picker.
    @Published var lastThroughputRatio: Double? {
        didSet {
            if let v = lastThroughputRatio { d.set(v, forKey: K.lastThroughput) }
            else { d.removeObject(forKey: K.lastThroughput) }
        }
    }

    private var accessedURL: URL?

    private init() {
        model = d.string(forKey: K.model) ?? Self.defaultModel
        localSpeakerName = d.string(forKey: K.localSpeakerName) ?? "Me"
        detectionEnabled = d.object(forKey: K.detectionEnabled) as? Bool ?? true
        suppressedApps = d.stringArray(forKey: K.suppressedApps) ?? []
        keepAudio = d.object(forKey: K.keepAudio) as? Bool ?? true
        showInDock = d.object(forKey: K.showInDock) as? Bool ?? false
        metadataBackend = (d.string(forKey: K.metadataBackend)
            .flatMap(MetadataBackendChoice.init(rawValue:))) ?? .auto
        // Defaults to the panel rather than to `both`, which is what existing
        // installs were doing. That is a deliberate change of behaviour on
        // upgrade: `both` is the configuration the user asked to be rid of, and
        // silently keeping it for everyone who already had it would make the
        // setting look broken to exactly the people who want it.
        promptDelivery = (d.string(forKey: K.promptDelivery)
            .flatMap(PromptDelivery.init(rawValue:))) ?? .panel
        removeFillerWords = d.object(forKey: K.removeFiller) as? Bool ?? true
        fillerWords = d.stringArray(forKey: K.fillerWords) ?? FillerWords.defaults
        customWatchedApps = d.stringArray(forKey: K.customWatchedApps) ?? []
        didCompleteFirstRun = d.bool(forKey: K.didCompleteFirstRun)
        dismissedUnclaimedNotes = d.stringArray(forKey: K.dismissedUnclaimed) ?? []
        lastSystemCaptureOK = d.object(forKey: K.lastSystemCaptureOK) as? Bool
        lastThroughputRatio = d.object(forKey: K.lastThroughput) as? Double
    }

    // MARK: - Notes Folder (security-scoped bookmark)

    /// Resolves the bookmark and begins access. Falls back to a sensible default
    /// so the app works before it is configured (FR-34).
    func notesFolder() -> URL? {
        if let u = accessedURL { return u }
        if let data = d.data(forKey: K.notesBookmark) {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: data,
                                options: [.withSecurityScope],
                                relativeTo: nil,
                                bookmarkDataIsStale: &stale) {
                if u.startAccessingSecurityScopedResource() {
                    accessedURL = u
                    if stale { setNotesFolder(u) }
                    return u
                }
            }
        }
        return defaultNotesFolder()
    }

    func defaultNotesFolder() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let base = docs else { return nil }
        let u = base.appendingPathComponent("Minutes", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func setNotesFolder(_ url: URL) {
        releaseAccess()
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            d.set(data, forKey: K.notesBookmark)
        }
        if url.startAccessingSecurityScopedResource() { accessedURL = url }
        objectWillChange.send()
    }

    func hasExplicitNotesFolder() -> Bool { d.data(forKey: K.notesBookmark) != nil }

    private func releaseAccess() {
        if let u = accessedURL { u.stopAccessingSecurityScopedResource() }
        accessedURL = nil
    }

    // MARK: - Detection suppression

    func isSuppressed(_ bundleID: String) -> Bool {
        suppressedApps.contains { bundleID.hasPrefix($0) }
    }
    func suppress(_ bundleID: String) {
        guard !suppressedApps.contains(bundleID) else { return }
        suppressedApps.append(bundleID)
    }
    func unsuppress(_ bundleID: String) {
        suppressedApps.removeAll { $0 == bundleID }
    }

    // MARK: - Custom watched apps

    func addWatchedApp(bundleID: String, name: String) {
        let id = bundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        // Never shadow a built-in, and never add the same app twice.
        guard !DetectionService.builtIn.contains(where: { id.hasPrefix($0.bundleIDPrefix) }) else { return }
        guard !customWatchedApps.contains(where: { $0.hasPrefix(id + "|") }) else { return }
        customWatchedApps.append("\(id)|\(name)")
    }

    func removeWatchedApp(bundleID: String) {
        customWatchedApps.removeAll { $0.hasPrefix(bundleID + "|") }
    }

    func resetFillerWords() { fillerWords = FillerWords.defaults }

    func addFillerWord(_ w: String) {
        let x = w.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !x.isEmpty, !fillerWords.contains(x) else { return }
        fillerWords.append(x)
    }

    func removeFillerWord(_ w: String) { fillerWords.removeAll { $0 == w } }

    // MARK: - Sidebar restoration

    var lastPane: String? {
        get { d.string(forKey: K.lastPane) }
        set { d.set(newValue, forKey: K.lastPane) }
    }
}
