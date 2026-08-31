import Foundation

// MARK: - Streams

/// Exactly two audio sources per Capture (PRD Glossary).
enum StreamKind: String, Codable, Sendable, CaseIterable {
    /// The local microphone. Attributed to the Local Speaker structurally (AD-11).
    case mic
    /// All other applications' output. Contains Remote Speakers; diarized.
    case system
}

// MARK: - Speakers

/// AD-19: Utterances reference a stable ID, never a display name.
/// This makes rename O(1) and makes "rename two labels to the same name" a
/// well-defined merge rather than an ambiguous pair of edits.
struct SpeakerLabelID: Hashable, Codable, Sendable, CustomStringConvertible {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    /// The one guaranteed-correct label in the product.
    static let local = SpeakerLabelID("local")
    static func remote(_ index: Int) -> SpeakerLabelID { SpeakerLabelID("remote-\(index)") }

    var isLocal: Bool { self == .local }
    var description: String { raw }
}

// MARK: - Utterance

/// One contiguous span of speech. Times are offsets from the session clock (AD-4).
struct Utterance: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var speaker: SpeakerLabelID
    /// Which Stream this came from — keeps the structural/inferred distinction in the data (AD-11).
    var origin: StreamKind

    var duration: TimeInterval { max(0, end - start) }
}

// MARK: - Metadata

enum MetadataBackendKind: String, Codable, Sendable {
    case heuristic
    case foundationModels

    var displayName: String {
        switch self {
        case .heuristic: return "Local keyphrase extraction"
        case .foundationModels: return "Apple on-device model"
        }
    }
}

struct ActionItem: Codable, Sendable, Hashable {
    var text: String
    var owner: String?
    /// Offset into the Transcript this was drawn from, so a reader can check it.
    var at: TimeInterval?
}

struct Decision: Codable, Sendable, Hashable {
    var text: String
    var at: TimeInterval?
}

struct MeetingMetadata: Codable, Sendable {
    var title: String
    var tags: [String]
    var summary: String
    var decisions: [Decision]
    var actionItems: [ActionItem]
    var backend: MetadataBackendKind

    static func fallback(date: Date, app: String?) -> MeetingMetadata {
        let f = DateFormatter()
        f.dateFormat = "d MMMM, HH:mm"
        let who = app.map { " — \($0)" } ?? ""
        return MeetingMetadata(
            title: "Meeting \(f.string(from: date))\(who)",
            tags: [], summary: "", decisions: [], actionItems: [],
            backend: .heuristic)
    }
}

// MARK: - Pipeline stage

/// AD-8: ordered, persisted, resumable. Only the Pipeline advances this (AD-20).
enum Stage: String, Codable, Sendable, CaseIterable, Comparable {
    case captured
    case transcribed
    case diarized
    case attributed
    case metadata
    case written

    var order: Int { Stage.allCases.firstIndex(of: self)! }
    static func < (a: Stage, b: Stage) -> Bool { a.order < b.order }

    var next: Stage? {
        let i = order + 1
        return i < Stage.allCases.count ? Stage.allCases[i] : nil
    }

    var displayName: String {
        switch self {
        case .captured:   return "Recorded"
        case .transcribed: return "Transcribed"
        case .diarized:   return "Speakers separated"
        case .attributed: return "Attributed"
        case .metadata:   return "Summarised"
        case .written:    return "Complete"
        }
    }
}

// MARK: - Meeting

/// The persisted record. **The source of truth** — the Note is a projection of
/// this and is never parsed back (AD-9). Written only by `MeetingStore` (AD-21).
struct Meeting: Codable, Sendable, Identifiable {
    /// Sortable, stable, and the directory name. Never changes, including on rename.
    var id: String
    var startedAt: Date
    var duration: TimeInterval
    var stage: Stage
    /// Set when a stage failed; `stage` stays at the last completed value (AD-20).
    var failure: String?

    // --- Degradation flags. Recorded even when degradation is the expected path (AD-17). ---
    /// False when the System Stream could not be captured — so a transcript with no
    /// Remote Speakers is never mistaken for a monologue (FR-7).
    var systemStreamCaptured: Bool
    var diarizationSucceeded: Bool

    /// Which app triggered a detected Session, if any.
    var triggeringApp: String?
    var transcriptionModel: String?

    var utterances: [Utterance]
    /// AD-19: display names live here, keyed by stable ID.
    var speakerNames: [String: String]
    /// Names applied automatically from a Speaker Profile, so the UI can mark them inferred (FR-25).
    var inferredSpeakers: [String]
    var metadata: MeetingMetadata?
    /// AD-18: computed once by NoteWriter and authoritative thereafter.
    var noteFilename: String?

    init(id: String, startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.duration = 0
        self.stage = .captured
        self.failure = nil
        self.systemStreamCaptured = false
        self.diarizationSucceeded = false
        self.triggeringApp = nil
        self.transcriptionModel = nil
        self.utterances = []
        self.speakerNames = [SpeakerLabelID.local.raw: "Me"]
        self.inferredSpeakers = []
        self.metadata = nil
        self.noteFilename = nil
    }

    // Unknown-key tolerant by virtue of Codable synthesis + optionals; defaults fill gaps
    // so an older record still loads (architecture convention).

    func displayName(for id: SpeakerLabelID) -> String {
        speakerNames[id.raw] ?? (id.isLocal ? "Me" : "Speaker")
    }

    func isInferred(_ id: SpeakerLabelID) -> Bool { inferredSpeakers.contains(id.raw) }

    /// Distinct speakers in transcript order of first appearance.
    var speakers: [SpeakerLabelID] {
        var seen = Set<String>(); var out: [SpeakerLabelID] = []
        for u in utterances where !seen.contains(u.speaker.raw) {
            seen.insert(u.speaker.raw); out.append(u.speaker)
        }
        return out
    }

    var isComplete: Bool { stage == .written }
    var hasFailed: Bool { failure != nil }

    static func newID(at date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let suffix = String((0..<4).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return "\(f.string(from: date))-\(suffix)"
    }
}

// MARK: - Formatting helpers

enum Fmt {
    /// mm:ss under an hour, h:mm:ss over (architecture convention).
    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded()), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }
    static func timestamp(_ t: TimeInterval) -> String { duration(t) }

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }
}
