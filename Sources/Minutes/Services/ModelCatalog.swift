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

    /// Who made the model. Asked for directly — "distil large-v3" says nothing
    /// about provenance, and the engine matters now that there are two.
    enum Provider: String {
        case openAI = "OpenAI"
        case nvidia = "NVIDIA"
        case distil = "Distil-Whisper"

        var glyph: String {
            switch self {
            case .openAI: return "circle.hexagongrid.fill"
            case .nvidia: return "bolt.fill"
            case .distil: return "circle.dashed"
            }
        }
    }

    /// Which inference engine runs it.
    enum Engine: String { case whisper = "WhisperKit", parakeet = "Parakeet" }

    struct Entry: Identifiable, Hashable {
        let id: String              // the real WhisperKit identifier
        var name: String            // plain-language, and guaranteed unique
        var technical: String       // the identifier, shown as a subtitle
        var role: Role
        var provider: Provider
        var engine: Engine
        var bytes: Int64?
        /// 1 (slowest) … 5 (fastest). Relative, and labelled as an estimate
        /// until a real measurement exists for this Mac.
        var speed: Int
        /// Word error rate on meeting speech, where it has been **measured**
        /// (FR-17 as amended, AD-50). `nil` means nobody has measured this model
        /// and the app therefore says nothing about its accuracy.
        var wordErrorRate: Double?
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
    private struct Spec {
        let name: String; let role: Role; let mb: Int; let speed: Int
        var provider: Provider = .openAI
        var engine: Engine = .whisper
        var note: String? = nil
    }

    private static let specs: [String: Spec] = [
        // --- NVIDIA Parakeet, via FluidAudio. Roughly an order of magnitude
        // faster than Whisper on Apple Silicon, which is the whole reason to
        // offer a second engine.
        ParakeetModel.v3:
            Spec(name: "Blazing fast", role: .recommended, mb: 461, speed: 5,
                 provider: .nvidia, engine: .parakeet,
                 note: "25 European languages. Much faster than Whisper."),
        ParakeetModel.v2:
            Spec(name: "Blazing fast, English", role: .english, mb: 461, speed: 5,
                 provider: .nvidia, engine: .parakeet,
                 note: "English only, and measured a little sharper for it on "
                     + "meeting speech."),
        // --- OpenAI Whisper, via WhisperKit ---
        "openai_whisper-large-v3-v20240930_turbo_632MB":
            Spec(name: "Balanced", role: .other, mb: 632, speed: 4,
                 note: "Measured on a par with the faster Parakeet models on a "
                     + "video call, and well behind them in a meeting room."),
        "openai_whisper-base":
            Spec(name: "Quick", role: .fastest, mb: 147, speed: 5),
        "openai_whisper-large-v3_947MB":
            // Not "Highest quality": nobody measured this model, and a superlative
            // the harness cannot back is the exact class of claim FR-93 removed
            // (investigation §2). Name it by what it verifiably is — the
            // full-precision, non-turbo large-v3.
            Spec(name: "Large v3, full precision", role: .other, mb: 947, speed: 2),
        "openai_whisper-small.en":
            Spec(name: "English, balanced", role: .english, mb: 483, speed: 4),
        "openai_whisper-base.en":
            Spec(name: "English, quick", role: .english, mb: 147, speed: 5),
        "openai_whisper-tiny":
            Spec(name: "Tiny", role: .compact, mb: 78, speed: 5),
        // Sensible alternates, kept out of the curated list but named properly.
        "distil-whisper_distil-large-v3_turbo_600MB":
            Spec(name: "Distilled turbo", role: .other, mb: 600, speed: 4, provider: .distil),
        "distil-whisper_distil-large-v3_594MB":
            Spec(name: "Distilled", role: .other, mb: 594, speed: 4, provider: .distil),
        "openai_whisper-large-v3_turbo_954MB":
            Spec(name: "Turbo, full precision", role: .other, mb: 954, speed: 3),
        "openai_whisper-large-v3-v20240930_626MB":
            Spec(name: "Large v3, compact", role: .other, mb: 626, speed: 2),
        "openai_whisper-large-v2_949MB":
            Spec(name: "Large v2", role: .other, mb: 949, speed: 2),
        "openai_whisper-large-v2_turbo_955MB":
            Spec(name: "Large v2 turbo", role: .other, mb: 955, speed: 3),
        "openai_whisper-small":
            Spec(name: "Small", role: .other, mb: 483, speed: 4),
        "openai_whisper-tiny.en":
            Spec(name: "Tiny, English", role: .other, mb: 78, speed: 5),
    ]

    /// The curated picker, in this order.
    private static let curatedOrder = [
        ParakeetModel.v3,
        ParakeetModel.v2,
        "openai_whisper-large-v3-v20240930_turbo_632MB",
        "openai_whisper-base",
        "openai_whisper-small.en",
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

    private func rebuild(from whisperIDs: [String]) {
        let measurements = Self.loadMeasurements()
        // Parakeet does not come from WhisperKit's catalogue, so it is added here.
        let ids = [ParakeetModel.v3, ParakeetModel.v2] + whisperIDs
        var built: [Entry] = ids.map { id in
            let s = Self.specs[id]
            return Entry(
                id: id,
                name: s?.name ?? Self.derivedName(id),
                technical: id.replacingOccurrences(of: "openai_whisper-", with: ""),
                role: s?.role ?? .other,
                provider: s?.provider ?? (id.contains("distil") ? .distil : .openAI),
                engine: s?.engine ?? .whisper,
                bytes: s.map { Int64($0.mb) * 1_000_000 } ?? Self.sizeFromSuffix(id),
                speed: s?.speed ?? Self.guessSpeed(id),
                wordErrorRate: Self.measuredWordErrorRate[id],
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

    /// Word error rate on meeting speech, for the models actually measured.
    ///
    /// **This replaced a five-point accuracy rating that fourteen models carried
    /// and none had earned.** `guessAccuracy` derived it from substrings of the
    /// model's name — "tiny" scored 1, "large" scored 5 — which reads as
    /// knowledge and was arithmetic on a filename.
    ///
    /// When the harness of FR-93 finally measured them, two of the three claims
    /// the product made turned out to be unsupported. `whisper-large-v3-turbo`
    /// was rated 5/5 and held the `.accurate` role against Parakeet v3 at 4/5;
    /// measured, it ties on close mics (22.8% against 22.6%) and is **11.4
    /// points worse** far-field, at eight times the cost.
    ///
    /// Figures are pooled over three AMI Meeting Corpus sessions (67 minutes,
    /// 7,374 reference words per condition), close-microphone condition, errors
    /// pooled over pooled words. A model absent from this table has not been
    /// measured, and the UI says nothing rather than guessing.
    ///
    /// A single session is **not** a measurement: the observed per-session swing
    /// is ±8 points, larger than any difference between the models here, which
    /// is why `whisper-base` — measured on one session only — is absent.
    static let measuredWordErrorRate: [String: Double] = [
        ParakeetModel.v2: 0.203,
        ParakeetModel.v3: 0.226,
        "openai_whisper-large-v3-v20240930_turbo_632MB": 0.228,
    ]

    /// Kept for the older call sites that only need a short label.
    static func friendlyName(_ id: String) -> String {
        specs[id]?.name ?? derivedName(id)
    }

    static func note(for id: String) -> String? { specs[id]?.note }
    static func engine(for id: String) -> Engine { specs[id]?.engine ?? .whisper }

    // MARK: - Download state

    static func modelFolder(_ id: String) -> URL? { ModelStorage.whisperFolder(id) }

    /// A model folder holding compiled CoreML packages is our download signal.
    static func isDownloaded(_ id: String) -> Bool {
        if ParakeetModel.isParakeet(id) { return ParakeetModel.isDownloaded(id) }
        guard let f = modelFolder(id),
              let items = try? FileManager.default.contentsOfDirectory(atPath: f.path)
        else { return false }
        // A partial download must never read as valid (FR-18).
        return items.contains { $0.hasSuffix(".mlmodelc") }
    }

    static func removeDownload(_ id: String) throws {
        if ParakeetModel.isParakeet(id) { try ParakeetModel.removeDownload(id); return }
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
