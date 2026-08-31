import Foundation
import WhisperKit

/// AD-13: the catalogue comes from the library at run time — the real identifiers
/// are `openai_whisper-`-prefixed and the published docs list bare names, so a
/// hardcoded list would offer models that do not exist.
///
/// But a *raw* run-time list is not a usable picker. WhisperKit offers 22
/// variants whose ids differ only by a size suffix, and shortening those names
/// for display collapsed them into 12 — with "large-v3 turbo" covering four
/// different models. So the list is curated into a handful of real choices with
/// plain-language names, and the full catalogue moved behind a disclosure.
@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    /// What a model is *for*, in the user's terms. This is the thing that was
    /// missing: "distil large-v3" tells you nothing about whether to pick it.
    enum Role: String {
        case recommended = "Recommended"
        case fastest     = "Fastest"
        case accurate    = "Most accurate"
        case english     = "English only"
        case compact     = "Smallest"
        case other       = "Other"

        var blurb: String {
            switch self {
            case .recommended: return "The best balance for meetings. Start here."
            case .fastest:     return "Noticeably quicker, and noticeably rougher."
            case .accurate:    return "Highest quality, and the slowest to run."
            case .english:     return "Faster and a little sharper, English speech only."
            case .compact:     return "Least disk space. Only for testing."
            case .other:       return ""
            }
        }
    }

    struct Entry: Identifiable, Hashable {
        let id: String              // the real WhisperKit identifier
        var name: String            // plain-language, and guaranteed unique
        var technical: String       // the identifier, shown as a subtitle
        var role: Role
        var bytes: Int64?
        /// 1 (slowest) … 5 (fastest). Relative, and labelled as an estimate
        /// until a real measurement exists for this Mac.
        var speed: Int
        var accuracy: Int
        var isDownloaded: Bool
        /// Seconds of processing per second of audio, measured on this machine.
        var measured: Double?
    }

    @Published var entries: [Entry] = []        // curated
    @Published var allEntries: [Entry] = []     // everything the library offers
    @Published var isRefreshing = false
    @Published var offlineOnly = false

    private init() {}

    // MARK: - Known characteristics
    //
    // Keyed on the real identifiers. Sizes are the CoreML on-disk figures; a
    // table beats regex-guessing, and it is the only way to give each variant a
    // name that actually distinguishes it.
    private struct Spec { let name: String; let role: Role; let mb: Int; let speed: Int; let acc: Int }

    private static let specs: [String: Spec] = [
        "openai_whisper-large-v3-v20240930_turbo_632MB":
            Spec(name: "Balanced", role: .recommended, mb: 632, speed: 4, acc: 5),
        "openai_whisper-base":
            Spec(name: "Quick", role: .fastest, mb: 147, speed: 5, acc: 2),
        "openai_whisper-large-v3_947MB":
            Spec(name: "Highest quality", role: .accurate, mb: 947, speed: 2, acc: 5),
        "openai_whisper-small.en":
            Spec(name: "English, balanced", role: .english, mb: 483, speed: 4, acc: 4),
        "openai_whisper-base.en":
            Spec(name: "English, quick", role: .english, mb: 147, speed: 5, acc: 3),
        "openai_whisper-tiny":
            Spec(name: "Tiny", role: .compact, mb: 78, speed: 5, acc: 1),
        // Sensible alternates, kept out of the curated list but named properly.
        "distil-whisper_distil-large-v3_turbo_600MB":
            Spec(name: "Distilled turbo", role: .other, mb: 600, speed: 4, acc: 4),
        "distil-whisper_distil-large-v3_594MB":
            Spec(name: "Distilled", role: .other, mb: 594, speed: 4, acc: 4),
        "openai_whisper-large-v3_turbo_954MB":
            Spec(name: "Turbo, full precision", role: .other, mb: 954, speed: 3, acc: 5),
        "openai_whisper-large-v3-v20240930_626MB":
            Spec(name: "Large v3, compact", role: .other, mb: 626, speed: 2, acc: 5),
        "openai_whisper-large-v2_949MB":
            Spec(name: "Large v2", role: .other, mb: 949, speed: 2, acc: 4),
        "openai_whisper-large-v2_turbo_955MB":
            Spec(name: "Large v2 turbo", role: .other, mb: 955, speed: 3, acc: 4),
        "openai_whisper-small":
            Spec(name: "Small", role: .other, mb: 483, speed: 4, acc: 3),
        "openai_whisper-tiny.en":
            Spec(name: "Tiny, English", role: .other, mb: 78, speed: 5, acc: 2),
    ]

    /// The curated picker, in this order.
    private static let curatedOrder = [
        "openai_whisper-large-v3-v20240930_turbo_632MB",
        "openai_whisper-base",
        "openai_whisper-large-v3_947MB",
        "openai_whisper-small.en",
        "openai_whisper-tiny",
    ]

    // MARK: - Loading

    func loadLocalRecommendations() {
        let support = WhisperKit.recommendedModels()
        rebuild(from: uniq([support.default] + support.supported))
        offlineOnly = true
    }

    func refreshFromNetwork() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            rebuild(from: uniq(try await WhisperKit.fetchAvailableModels()))
            offlineOnly = false
        } catch {
            Log.transcribe.error("model catalogue fetch failed: \(error.localizedDescription, privacy: .public)")
            if allEntries.isEmpty { loadLocalRecommendations() }
            offlineOnly = true
        }
    }

    private func uniq(_ xs: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for x in xs where !seen.contains(x) { seen.insert(x); out.append(x) }
        return out
    }

    private func rebuild(from ids: [String]) {
        let measurements = Self.loadMeasurements()
        var built: [Entry] = ids.map { id in
            let s = Self.specs[id]
            return Entry(
                id: id,
                name: s?.name ?? Self.derivedName(id),
                technical: id.replacingOccurrences(of: "openai_whisper-", with: ""),
                role: s?.role ?? .other,
                bytes: s.map { Int64($0.mb) * 1_000_000 } ?? Self.sizeFromSuffix(id),
                speed: s?.speed ?? Self.guessSpeed(id),
                accuracy: s?.acc ?? Self.guessAccuracy(id),
                isDownloaded: Self.isDownloaded(id),
                measured: measurements[id])
        }
        // Safety net: no two rows may ever render with the same name again.
        var used: [String: Int] = [:]
        for i in built.indices {
            let base = built[i].name
            used[base, default: 0] += 1
            if used[base]! > 1 {
                let mb = built[i].bytes.map { " (\(Int($0 / 1_000_000)) MB)" } ?? " (\(built[i].technical))"
                built[i].name = base + mb
            }
        }
        allEntries = built.sorted { ($0.role == .other ? 1 : 0, $0.name) < ($1.role == .other ? 1 : 0, $1.name) }

        let byID = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
        var curated = Self.curatedOrder.compactMap { byID[$0] }
        // Always offer the active model even if it is not in the curated set.
        let active = Preferences.shared.model
        if !curated.contains(where: { $0.id == active }), let e = byID[active] {
            curated.insert(e, at: 0)
        }
        entries = curated
    }

    func refreshDownloadStates() {
        func upd(_ xs: [Entry]) -> [Entry] {
            xs.map { var c = $0; c.isDownloaded = Self.isDownloaded($0.id); return c }
        }
        entries = upd(entries); allEntries = upd(allEntries)
    }

    // MARK: - Measurements

    /// Real seconds-per-second-of-audio on this Mac, keyed by model. Written by
    /// the Test Playground; nothing else is allowed to claim a measured figure.
    private static let measurementsKey = "modelMeasurements"

    static func loadMeasurements() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: measurementsKey) as? [String: Double] ?? [:]
    }

    static func record(ratio: Double, for model: String) {
        var m = loadMeasurements()
        m[model] = ratio
        UserDefaults.standard.set(m, forKey: measurementsKey)
    }

    /// How long this model would take on a meeting of the given length, when we
    /// have actually measured it. Estimates are never dressed up as measurements.
    static func projection(ratio: Double, minutes: Double) -> String {
        let secs = ratio * minutes * 60
        if secs < 90 { return "about \(Int(secs.rounded())) s for a \(Int(minutes))-min meeting" }
        return "about \(Int((secs / 60).rounded())) min for a \(Int(minutes))-min meeting"
    }

    // MARK: - Fallbacks for ids not in the table

    static func derivedName(_ id: String) -> String {
        var s = id
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "distil ")
            .replacingOccurrences(of: "-v20240930", with: "")
        // Deliberately keep the size suffix — stripping it is what collapsed
        // four distinct models into one name.
        s = s.replacingOccurrences(of: "_", with: " ")
        return s
    }

    static func sizeFromSuffix(_ id: String) -> Int64? {
        guard let m = id.range(of: "_([0-9]+)MB", options: .regularExpression) else { return nil }
        let digits = id[m].filter(\.isNumber)
        return Int64(digits).map { $0 * 1_000_000 }
    }

    static func guessSpeed(_ id: String) -> Int {
        if id.contains("tiny") || id.contains("base") { return 5 }
        if id.contains("small") || id.contains("turbo") || id.contains("distil") { return 4 }
        return 2
    }

    static func guessAccuracy(_ id: String) -> Int {
        if id.contains("tiny") { return 1 }
        if id.contains("base") { return 2 }
        if id.contains("small") { return 3 }
        if id.contains("large-v2") || id.contains("distil") { return 4 }
        return 5
    }

    /// Kept for the older call sites that only need a short label.
    static func friendlyName(_ id: String) -> String {
        specs[id]?.name ?? derivedName(id)
    }

    // MARK: - Download state

    static func modelFolder(_ id: String) -> URL? { ModelStorage.whisperFolder(id) }

    /// A model folder holding compiled CoreML packages is our download signal.
    static func isDownloaded(_ id: String) -> Bool {
        guard let f = modelFolder(id),
              let items = try? FileManager.default.contentsOfDirectory(atPath: f.path)
        else { return false }
        // A partial download must never read as valid (FR-18).
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
