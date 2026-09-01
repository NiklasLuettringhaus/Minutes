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

    /// The user, and only used when the mic stream contained exactly ONE voice —
    /// then it is certain. With several people in the room it is not, so the
    /// in-room voices get `inRoom` labels and the app asserts nothing about which
    /// one is the user until told.
    static let local = SpeakerLabelID("local")
    /// One of several people physically in the room with the user.
    static func inRoom(_ index: Int) -> SpeakerLabelID { SpeakerLabelID("room-\(index)") }
    /// Mic speech the Diarizer could not place, when more than one voice shares the
    /// microphone. Previously such an Utterance fell through to `.local` and was
    /// rendered as the user's own words — an identity claim the data does not
    /// support, which is exactly what AD-11 forbids.
    static let inRoomUnidentified = SpeakerLabelID("room-unidentified")
    /// A participant on the other end of the call.
    static func remote(_ index: Int) -> SpeakerLabelID { SpeakerLabelID("remote-\(index)") }

    /// Certainly the user.
    var isLocal: Bool { self == .local }
    /// In the room — the user, or someone sitting next to them.
    var isInRoom: Bool { self == .local || raw.hasPrefix("room-") }
    var isRemote: Bool { raw.hasPrefix("remote-") }

    /// Where this voice was, which is the part that IS structural.
    enum Place { case you, room, remote }
    var place: Place { isLocal ? .you : (isRemote ? .remote : .room) }

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
    /// True when the mic stream held more than one voice, i.e. the user was in a
    /// room with other people. When true, no voice is assumed to be the user.
    var multipleInRoom: Bool = false

    /// Which app triggered a detected Session, if any.
    var triggeringApp: String?
    var transcriptionModel: String?
    /// What the two Streams were actually heard through. Recorded because the same
    /// room behaves completely differently on a headset and on a built-in mic, and
    /// diagnosing the first real meeting required probing the machine from outside
    /// the app to discover it had been AirPods.
    var micDevice: String?
    var systemSource: String?
    /// True when the Local Speaker was identified by matching the user's enrolled
    /// voice against the in-room voices, rather than by the structural certainty
    /// of a single voice on the microphone (FR-63).
    ///
    /// The distinction is recorded because the two are not equally reliable and
    /// the transcript renders them identically. One cannot be wrong; the other is
    /// a measurement. AD-11 exists to stop the second being presented as the
    /// first, so the detail pane says which it was (FR-65).
    var localIdentifiedByEnrolment: Bool = false
    /// How close that match was, when there was one. Shown as a fact and never
    /// settable — no control anywhere in the app writes a distance (FR-65).
    var localMatchDistance: Float?

    /// Speaker Labels the user has excluded from the Note for this Meeting.
    ///
    /// Deliberately per-Meeting and never automatic. In-room voices are usually
    /// *participants* — a conference room is the normal case, not the exception —
    /// so the app cannot know which non-user voice belongs to the meeting and which
    /// was a conversation happening beside it. The user knows instantly. Excluded
    /// speech stays in the record and stays visible in the app; only the Note omits
    /// it, and the Note says so.
    var excludedSpeakers: [String] = []

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
        self.multipleInRoom = false
        self.triggeringApp = nil
        self.transcriptionModel = nil
        self.micDevice = nil
        self.systemSource = nil
        self.localIdentifiedByEnrolment = false
        self.localMatchDistance = nil
        self.excludedSpeakers = []
        self.utterances = []
        self.speakerNames = [SpeakerLabelID.local.raw: "Me"]
        self.inferredSpeakers = []
        self.metadata = nil
        self.noteFilename = nil
    }

    /// Hand-written because the synthesised `Codable` was **not** tolerant of an
    /// older record, contrary to what a comment here used to claim: Swift ignores a
    /// property's default value when the key is absent and throws `keyNotFound`
    /// instead. Adding `multipleInRoom` therefore made every meeting recorded
    /// before it silently unreadable, and `MeetingStore.loadAll`'s `try?` dropped
    /// them from the list — five real recordings vanished from the UI while still
    /// sitting on disk. Only `id` and `startedAt` are required; everything else
    /// falls back, so a future field can never orphan history again.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        stage = try c.decodeIfPresent(Stage.self, forKey: .stage) ?? .captured
        failure = try c.decodeIfPresent(String.self, forKey: .failure)
        systemStreamCaptured = try c.decodeIfPresent(Bool.self, forKey: .systemStreamCaptured) ?? false
        diarizationSucceeded = try c.decodeIfPresent(Bool.self, forKey: .diarizationSucceeded) ?? false
        multipleInRoom = try c.decodeIfPresent(Bool.self, forKey: .multipleInRoom) ?? false
        triggeringApp = try c.decodeIfPresent(String.self, forKey: .triggeringApp)
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel)
        micDevice = try c.decodeIfPresent(String.self, forKey: .micDevice)
        systemSource = try c.decodeIfPresent(String.self, forKey: .systemSource)
        localIdentifiedByEnrolment = try c.decodeIfPresent(Bool.self, forKey: .localIdentifiedByEnrolment) ?? false
        localMatchDistance = try c.decodeIfPresent(Float.self, forKey: .localMatchDistance)
        excludedSpeakers = try c.decodeIfPresent([String].self, forKey: .excludedSpeakers) ?? []
        utterances = try c.decodeIfPresent([Utterance].self, forKey: .utterances) ?? []
        speakerNames = try c.decodeIfPresent([String: String].self, forKey: .speakerNames)
            ?? [SpeakerLabelID.local.raw: "Me"]
        inferredSpeakers = try c.decodeIfPresent([String].self, forKey: .inferredSpeakers) ?? []
        metadata = try c.decodeIfPresent(MeetingMetadata.self, forKey: .metadata)
        noteFilename = try c.decodeIfPresent(String.self, forKey: .noteFilename)
    }

    func displayName(for id: SpeakerLabelID) -> String {
        if let n = speakerNames[id.raw] { return n }
        if id == .inRoomUnidentified { return "In-room, unidentified" }
        switch id.place {
        case .you:    return "Me"
        case .room:   return "In-room speaker"
        case .remote: return "Speaker"
        }
    }

    /// Voices captured by the microphone: the user and anyone in the room.
    var inRoomSpeakers: [SpeakerLabelID] { speakers.filter(\.isInRoom) }
    /// Voices from the other end of the call.
    var remoteSpeakers: [SpeakerLabelID] { speakers.filter(\.isRemote) }

    func isExcluded(_ id: SpeakerLabelID) -> Bool { excludedSpeakers.contains(id.raw) }

    /// How a given Speaker reached the recording. Structural, not guessed: mic
    /// means the room, system means the far end (AD-11).
    func heardThrough(_ id: SpeakerLabelID) -> String {
        switch id.place {
        case .you, .room:
            return micDevice ?? "microphone"
        case .remote:
            if let s = systemSource { return s }
            return "system audio"
        }
    }

    func isInferred(_ id: SpeakerLabelID) -> Bool { inferredSpeakers.contains(id.raw) }

    /// What the app's claim about this voice actually rests on (FR-65).
    ///
    /// Three of the four cases mean "no identity was claimed", and they are kept
    /// apart because they are not the same statement: a structural fact, a
    /// measurement, an honest anonymous label, and speech nothing could place.
    enum Basis: Equatable {
        /// The microphone held one voice. Cannot be wrong.
        case structural
        /// Matched against the user's enrolled voice, at this distance.
        case enrolmentMatch(distance: Float?)
        /// In the room, and the app does not claim to know who.
        case inRoomAnonymous
        /// Mic speech no diarized span covered, with several voices present.
        case inRoomUnplaceable
        /// The far end of the call, split by diarization.
        case remote

        var isClaim: Bool {
            switch self {
            case .structural, .enrolmentMatch: return true
            case .inRoomAnonymous, .inRoomUnplaceable, .remote: return false
            }
        }
    }

    func basis(for id: SpeakerLabelID) -> Basis {
        if id == .inRoomUnidentified { return .inRoomUnplaceable }
        switch id.place {
        case .you:
            return localIdentifiedByEnrolment
                ? .enrolmentMatch(distance: localMatchDistance)
                : .structural
        case .room:   return .inRoomAnonymous
        case .remote: return .remote
        }
    }

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
