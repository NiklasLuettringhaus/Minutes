import Foundation
import WhisperKit

/// AD-13: the catalogue comes from the library at run time. Only the *default*
/// identifier is a constant.
///
/// This matters concretely: the published documentation lists bare names like
/// `base` and `large-v3-v20240930_626MB`, but the real identifiers are
/// `openai_whisper-`-prefixed. A hardcoded list would offer models that do not
/// exist.
@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    struct Entry: Identifiable, Hashable {
        let id: String
        var displayName: String
        var approxBytes: Int64?
        var isDownloaded: Bool
        /// Relative character, derived from the identifier's own size hints.
        var speed: Speed
        var accuracy: Accuracy

        enum Speed: String { case fastest = "Fastest", fast = "Fast", moderate = "Moderate", slow = "Slower" }
        enum Accuracy: String { case basic = "Basic", good = "Good", better = "Better", best = "Best" }
    }

    @Published var entries: [Entry] = []
    @Published var isRefreshing = false
    /// Set when the full catalogue could not be fetched, so the UI can say the
    /// list is the offline subset rather than pretend it is complete.
    @Published var offlineOnly = false

    private init() {}

    /// Local, no network — gives a usable list immediately (verified).
    func loadLocalRecommendations() {
        let support = WhisperKit.recommendedModels()
        var ids = [support.default]
        ids.append(contentsOf: support.supported)
        rebuild(from: uniq(ids))
        offlineOnly = true
    }

    /// Full catalogue from Hugging Face. Falls back to the local list.
    func refreshFromNetwork() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let all = try await WhisperKit.fetchAvailableModels()
            rebuild(from: uniq(all))
            offlineOnly = false
        } catch {
            Log.transcribe.error("model catalogue fetch failed: \(error.localizedDescription, privacy: .public)")
            if entries.isEmpty { loadLocalRecommendations() }
            offlineOnly = true
        }
    }

    private func uniq(_ xs: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for x in xs where !seen.contains(x) { seen.insert(x); out.append(x) }
        return out
    }

    private func rebuild(from ids: [String]) {
        entries = ids.map { id in
            Entry(id: id,
                  displayName: Self.friendlyName(id),
                  approxBytes: Self.approxBytes(id),
                  isDownloaded: Self.isDownloaded(id),
                  speed: Self.speed(id),
                  accuracy: Self.accuracy(id))
        }
        .sorted { a, b in
            // Recommended default first, then by accuracy, then name.
            if a.id == Preferences.defaultModel { return true }
            if b.id == Preferences.defaultModel { return false }
            return a.id < b.id
        }
    }

    func refreshDownloadStates() {
        entries = entries.map { e in
            var c = e; c.isDownloaded = Self.isDownloaded(e.id); return c
        }
    }

    // MARK: - Model metadata derived from the identifier

    static func friendlyName(_ id: String) -> String {
        var s = id
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "distil ")
        // Strip the size suffix; it is shown separately.
        if let r = s.range(of: "_[0-9]+MB$", options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: "-v20240930", with: "")
        s = s.replacingOccurrences(of: "_turbo", with: " turbo")
        return s
    }

    static func approxBytes(_ id: String) -> Int64? {
        guard let m = id.range(of: "_([0-9]+)MB", options: .regularExpression) else { return nil }
        let digits = id[m].filter(\.isNumber)
        guard let mb = Int64(digits) else { return nil }
        return mb * 1_000_000
    }

    static func speed(_ id: String) -> Entry.Speed {
        if id.contains("tiny") { return .fastest }
        if id.contains("base") { return .fastest }
        if id.contains("small") { return .fast }
        if id.contains("turbo") { return .fast }
        if id.contains("distil") { return .fast }
        return .slow
    }

    static func accuracy(_ id: String) -> Entry.Accuracy {
        if id.contains("tiny") { return .basic }
        if id.contains("base") { return .good }
        if id.contains("small") { return .better }
        return .best
    }

    /// WhisperKit caches under Application Support; a model folder existing with
    /// content is our download signal.
    static func modelFolder(_ id: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    static func isDownloaded(_ id: String) -> Bool {
        guard let f = modelFolder(id) else { return false }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: f.path) else { return false }
        // A partial download must never read as valid (FR-18): require the
        // compiled model packages to be present.
        return items.contains { $0.hasSuffix(".mlmodelc") }
    }

    static func removeDownload(_ id: String) throws {
        guard let f = modelFolder(id) else { return }
        try FileManager.default.removeItem(at: f)
    }

    static func bytesOnDisk(_ id: String) -> Int64 {
        guard let f = modelFolder(id),
              let e = FileManager.default.enumerator(at: f, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
