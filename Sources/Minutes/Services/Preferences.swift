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
        static let didCompleteFirstRun = "didCompleteFirstRun"
        static let lastSystemCaptureOK = "lastSystemCaptureOK"
        static let lastThroughput = "lastThroughputRatio"
        static let removeFiller = "removeFillerWords"
        static let fillerWords = "fillerWords"
    }

    /// Verified present in the live catalogue. Deliberately not the library's
    /// recommended `openai_whisper-base`, which is too weak for multi-speaker
    /// meeting audio; also deliberately not the largest (SM-C3).
    static let defaultModel = "openai_whisper-large-v3-v20240930_turbo_632MB"

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
    /// On by default: a long meeting transcript is genuinely hard to read with
    /// every clause opening "um, uh, so".
    @Published var removeFillerWords: Bool {
        didSet { d.set(removeFillerWords, forKey: K.removeFiller) }
    }
    @Published var fillerWords: [String] {
        didSet { d.set(fillerWords, forKey: K.fillerWords) }
    }
    @Published var didCompleteFirstRun: Bool {
        didSet { d.set(didCompleteFirstRun, forKey: K.didCompleteFirstRun) }
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
        removeFillerWords = d.object(forKey: K.removeFiller) as? Bool ?? true
        fillerWords = d.stringArray(forKey: K.fillerWords) ?? FillerWords.defaults
        didCompleteFirstRun = d.bool(forKey: K.didCompleteFirstRun)
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
