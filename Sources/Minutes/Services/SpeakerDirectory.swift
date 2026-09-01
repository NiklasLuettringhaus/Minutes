import Foundation

/// FR-25 / FR-62 / FR-64: remembers voices, so a person arrives pre-named next
/// time — and, for exactly one person, answers *which voice on the microphone is
/// the user*.
///
/// Those two jobs are related but they are not the same job, and the difference
/// is the whole reason increment 4 exists. Remembering works by learning from a
/// rename: the user types a name, and the voice that was carrying that label
/// becomes a Profile. That needs a *correct label to start from*, and when
/// several people share one microphone there is none — nothing in the transcript
/// is known to be the user, so there is nothing to rename that would teach the
/// app anything true. PRD §6.2 deferred voiceprint enrolment on the grounds that
/// FR-25 learns passively; that reasoning holds for other people and fails for
/// the user, and increment 4 reverses it for the user alone.
///
/// So there are two kinds of Profile in one store, on purpose (AD-30):
///
/// - `.remembered` — learned from a rename, matched by `match(centroid:)`, may
///   name any voice, and is always marked inferred so a mistake is visible.
/// - `.enrolledUser` — recorded deliberately by the user, at most one, and
///   **excluded from `match`** so it can never put a name on a voice. It answers
///   one question, through `identifyLocal`, and the user's display name keeps its
///   existing single owner in Preferences.
///
/// The store is deliberately shared rather than duplicated. A separate
/// `enrolled.json` would have meant a second persistence path, a second atomic
/// write, a second thing to delete, and a "Remembered voices" list that lied by
/// omission about the most sensitive thing on disk.
actor SpeakerDirectory {
    static let shared = SpeakerDirectory()

    /// What kind of thing a Profile is. Decoded with a default so a
    /// `speakers.json` written before increment 4 loads as `.remembered`, which
    /// is what every profile in it is.
    enum Kind: String, Codable, Sendable {
        case remembered
        case enrolledUser
    }

    struct Profile: Codable {
        var name: String
        /// Mean of the centroids seen for this person, so repeated confirmations
        /// improve the profile rather than overwrite it. For an enrolled voice
        /// this is the single recorded fingerprint — see `enrol`.
        var centroid: [Float]
        var samples: Int
        var updatedAt: Date
        var kind: Kind = .remembered
        /// Which embedder produced `centroid` (AD-29). `nil` on a profile written
        /// before increment 4, which is treated as "unknown, therefore not
        /// comparable with a fingerprint that names its producer".
        var producer: String?
        /// Seconds of speech the fingerprint came from, when known. Set by
        /// enrolment; `nil` for a voice learned from a rename, where the figure
        /// is meaningless because it accumulates across meetings.
        var speechSeconds: Double?

        init(name: String, centroid: [Float], samples: Int, updatedAt: Date,
             kind: Kind = .remembered, producer: String? = nil,
             speechSeconds: Double? = nil) {
            self.name = name
            self.centroid = centroid
            self.samples = samples
            self.updatedAt = updatedAt
            self.kind = kind
            self.producer = producer
            self.speechSeconds = speechSeconds
        }

        /// Hand-written for the reason `Meeting.init(from:)` is hand-written, and
        /// it is worth restating because the failure is invisible: **Swift
        /// ignores a property's default value when its key is absent** and throws
        /// `keyNotFound` instead. Adding one field to `Meeting` therefore made
        /// every record written before it undecodable, and `loadAll`'s `try?`
        /// turned that into five real meetings vanishing from the UI while still
        /// sitting on disk.
        ///
        /// `Profile` gains three fields here. Without this initialiser, every
        /// remembered voice the user has ever named would silently disappear the
        /// first time the new build ran, and the only symptom would be speakers
        /// arriving anonymous again.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            centroid = try c.decodeIfPresent([Float].self, forKey: .centroid) ?? []
            samples = try c.decodeIfPresent(Int.self, forKey: .samples) ?? 1
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .remembered
            producer = try c.decodeIfPresent(String.self, forKey: .producer)
            speechSeconds = try c.decodeIfPresent(Double.self, forKey: .speechSeconds)
        }

        var fingerprint: VoiceFingerprint? {
            guard let producer, !centroid.isEmpty else { return nil }
            return VoiceFingerprint(vector: centroid, producer: producer)
        }
    }

    private var profiles: [Profile] = []
    private let url: URL

    init(url: URL? = nil) {
        if let url { self.url = url } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = support.appendingPathComponent("Minutes", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("speakers.json")
        }
        profiles = Self.loadProfiles(from: self.url)
    }

    // MARK: - Matching (FR-25)

    /// Best-matching known name for a centroid, or nil when nothing is close
    /// enough.
    ///
    /// **The enrolled voice is excluded from the candidate set** (AD-30). It is
    /// not a name this function may apply: the user's identity is resolved by
    /// place or by `identifyLocal`, and letting a third path put the user's name
    /// on a voice would mean two components deciding who the user is.
    func match(centroid: [Float]) -> String? {
        var best: (name: String, distance: Float)? = nil
        for p in profiles where p.kind == .remembered {
            guard let d = VoiceMatch.cosineDistance(p.centroid, centroid) else { continue }
            if best == nil || d < best!.distance { best = (p.name, d) }
        }
        guard let b = best, b.distance <= VoiceMatch.sameSpeakerThreshold else { return nil }
        Log.pipeline.info("speaker matched profile distance=\(b.distance)")
        return b.name
    }

    /// Records a user-supplied name against a voice. Called on rename, which is
    /// the only way a `.remembered` profile is ever created — the app never tries
    /// to identify someone it was not told about (PRD §5).
    func remember(name: String, centroid: [Float]) {
        guard !name.isEmpty, !centroid.isEmpty else { return }
        if let i = profiles.firstIndex(where: {
            $0.kind == .remembered && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            // Running mean, so correcting a wrong match improves the profile
            // rather than replacing it wholesale.
            let p = profiles[i]
            let n = Float(p.samples)
            var merged = p.centroid
            if merged.count == centroid.count {
                for k in 0..<merged.count {
                    merged[k] = (merged[k] * n + centroid[k]) / (n + 1)
                }
            } else {
                merged = centroid
            }
            profiles[i] = Profile(name: p.name, centroid: merged, samples: p.samples + 1,
                                  updatedAt: Date(), kind: .remembered, producer: p.producer)
        } else {
            profiles.append(Profile(name: name, centroid: centroid, samples: 1,
                                    updatedAt: Date(), kind: .remembered))
        }
        persist()
    }

    // MARK: - Voice enrolment (FR-62, FR-63, FR-64)

    /// Stores the user's own fingerprint, replacing any previous one.
    ///
    /// **Replaces rather than averages**, unlike `remember`. A re-record is a
    /// correction — most plausibly of a first sample that had a colleague in it
    /// or too little speech — and averaging a correction into the thing it
    /// corrects preserves the error. It also means no history of samples exists,
    /// which matters because each one identifies a person (PRD §9.1).
    func enrol(name: String, fingerprint: VoiceFingerprint, speechSeconds: Double) {
        guard fingerprint.isUsable else { return }
        profiles.removeAll { $0.kind == .enrolledUser }
        profiles.append(Profile(name: name.isEmpty ? "Me" : name,
                                centroid: fingerprint.vector,
                                samples: 1,
                                updatedAt: Date(),
                                kind: .enrolledUser,
                                producer: fingerprint.producer,
                                speechSeconds: speechSeconds))
        persist()
        Log.pipeline.info("voice enrolled dims=\(fingerprint.vector.count) speech=\(speechSeconds, format: .fixed(precision: 1))s")
    }

    func enrolledProfile() -> Profile? { profiles.first { $0.kind == .enrolledUser } }

    var isEnrolled: Bool { profiles.contains { $0.kind == .enrolledUser } }

    /// Biometric-adjacent data: deletable in one click, local, never transmitted
    /// (PRD §9.1, FR-64).
    func forgetEnrolled() {
        let had = isEnrolled
        profiles.removeAll { $0.kind == .enrolledUser }
        if had { persist(); Log.pipeline.info("enrolled voice deleted") }
    }

    /// Which of several in-room voices is the user (FR-63).
    ///
    /// The decision itself is `VoiceMatch.resolve` — pure, in Core, and unaware
    /// that any of this is about speakers on a microphone. All this method does is
    /// look up the enrolled fingerprint and hand it over, which is deliberate:
    /// the identification rule must be readable and testable in one place with no
    /// actor, no store, and no audio anywhere near it.
    ///
    /// Returns `.notComparable` when nothing is enrolled, which the caller must
    /// treat exactly as it treated the world before enrolment existed.
    func identifyLocal(among candidates: [VoiceMatch.Candidate]) -> VoiceMatch.Resolution {
        guard let probe = enrolledProfile()?.fingerprint else { return .notComparable }
        let r = VoiceMatch.resolve(probe, among: candidates)
        switch r {
        case .matched(let key, let d):
            Log.pipeline.info("local speaker identified from enrolled voice label=\(key, privacy: .public) distance=\(d)")
        case .ambiguous(let a, let b, let d):
            // Logged at info, not error: refusing is the correct outcome, and the
            // pair is what makes a diarizer split diagnosable afterwards.
            Log.pipeline.info("enrolled voice ambiguous between \(a, privacy: .public) and \(b, privacy: .public) at \(d) — claiming nothing")
        case .noMatch(let nearest):
            Log.pipeline.info("enrolled voice matched nothing in the room, nearest=\(nearest ?? -1)")
        case .notComparable:
            Log.pipeline.info("enrolled voice not comparable with this meeting's voices")
        }
        return r
    }

    // MARK: - Forgetting

    /// Forgets a remembered voice by name. Deliberately cannot reach the enrolled
    /// voice — that has its own control, so that a colleague who happens to share
    /// the user's display name cannot delete it by accident.
    func forget(name: String) {
        profiles.removeAll {
            $0.kind == .remembered && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        persist()
    }

    /// Everything, including the enrolled voice. The confirmation that calls this
    /// must name the enrolled voice separately (FR-64) — "3 voices will be
    /// forgotten" hides the one that matters.
    func forgetAll() {
        profiles = []
        persist()
    }

    func knownNames() -> [String] { profiles.filter { $0.kind == .remembered }.map(\.name).sorted() }

    // MARK: - FR-51 / FR-64: seeing and curating what is remembered

    /// What the voices list shows. Deliberately excludes the centroid: it is the
    /// one field that is biometric-adjacent and it means nothing to a reader.
    struct Summary: Identifiable, Equatable, Sendable {
        var id: String { kind == .enrolledUser ? "enrolled" : name }
        let name: String
        /// How many Meetings contributed, so a one-sample guess is distinguishable
        /// from a well-established voice.
        let samples: Int
        let updatedAt: Date
        let kind: Kind
        /// Set for an enrolled voice: how much audio produced it. This is the
        /// provenance that makes an enrolled fingerprint judgeable, in the way
        /// meeting count makes a remembered one judgeable.
        let speechSeconds: Double?

        var isEnrolled: Bool { kind == .enrolledUser }
    }

    /// The enrolled voice sorts first. It is the only entry that is the user, and
    /// the only one whose deletion changes how future meetings are attributed.
    func summaries() -> [Summary] {
        profiles
            .map { Summary(name: $0.name, samples: $0.samples, updatedAt: $0.updatedAt,
                           kind: $0.kind, speechSeconds: $0.speechSeconds) }
            .sorted {
                if $0.isEnrolled != $1.isEnrolled { return $0.isEnrolled }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Renames a Profile in place, keeping its learned centroid and sample count —
    /// the point of a correction is that what was learned about the *voice* stays.
    ///
    /// Renaming onto an existing name merges the two, which is the fix when one
    /// person was recorded as two. Merging averages the centroids weighted by
    /// sample count, matching how `remember` accumulates.
    ///
    /// Does not relabel Meetings already written: that was not asked for, and it
    /// would rewrite Notes the user may have edited by hand.
    ///
    /// The enrolled voice cannot be renamed here (FR-64). Its label is the user's
    /// own name, which is owned by Preferences and edited in one place — two
    /// places to change one name is the defect this avoids.
    @discardableResult
    func rename(from old: String, to new: String) -> Bool {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = profiles.firstIndex(where: {
                  $0.kind == .remembered && $0.name.caseInsensitiveCompare(old) == .orderedSame
              })
        else { return false }

        if let j = profiles.firstIndex(where: {
            $0.kind == .remembered && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }), j != i {
            let a = profiles[i], b = profiles[j]
            var merged = b.centroid
            if a.centroid.count == b.centroid.count, !merged.isEmpty {
                let wa = Float(a.samples), wb = Float(b.samples)
                for k in 0..<merged.count {
                    merged[k] = (a.centroid[k] * wa + b.centroid[k] * wb) / (wa + wb)
                }
            }
            profiles[j] = Profile(name: trimmed, centroid: merged,
                                  samples: a.samples + b.samples, updatedAt: Date(),
                                  kind: .remembered, producer: b.producer ?? a.producer)
            profiles.remove(at: i)
        } else {
            let p = profiles[i]
            profiles[i] = Profile(name: trimmed, centroid: p.centroid,
                                  samples: p.samples, updatedAt: Date(),
                                  kind: .remembered, producer: p.producer)
        }
        persist()
        return true
    }

    /// Keeps the enrolled voice's label in step with the user's display name.
    /// Called when that setting changes, so the voices list never shows a stale
    /// name for the one entry whose name it does not own.
    func syncEnrolledName(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = profiles.firstIndex(where: { $0.kind == .enrolledUser }),
              profiles[i].name != trimmed else { return }
        profiles[i].name = trimmed
        persist()
    }

    // MARK: - Persistence (atomic, AD-10)

    private static func loadProfiles(from url: URL) -> [Profile] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Profile].self, from: d)) ?? []
    }

    private func persist() {
        guard let d = try? JSONEncoder().encode(profiles) else { return }
        try? MeetingStore.atomicWrite(d, to: url)
    }

    // MARK: - Math

    /// Retained so existing call sites keep working; the arithmetic itself now
    /// lives in `VoiceMatch` in Core, which is what AD-28 requires — the
    /// comparison must not depend on this actor, on Services, or on anything that
    /// imports a framework.
    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float? {
        VoiceMatch.cosineDistance(a, b)
    }
}
