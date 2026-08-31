import Foundation

/// FR-25: remembers a named voice so the same person arrives pre-named next time.
///
/// This was the PRD's highest-uncertainty requirement. It is feasible because
/// SpeakerKit exposes per-speaker centroid embeddings specifically for "linking
/// the same speaker across independent diarize() calls".
///
/// The library deliberately defines no universal same-speaker threshold, so the
/// threshold here is ours to calibrate — and it is set conservatively, because a
/// wrong automatic name is worse than an anonymous one. Auto-applied names are
/// always marked inferred so a mistake is visible and correctable.
actor SpeakerDirectory {
    static let shared = SpeakerDirectory()

    struct Profile: Codable {
        var name: String
        /// Mean of the centroids seen for this person, so repeated confirmations
        /// improve the profile rather than overwrite it.
        var centroid: [Float]
        var samples: Int
        var updatedAt: Date
    }

    /// Cosine distance below which two centroids are treated as the same person.
    /// Conservative on purpose: missing a match costs one rename, a false match
    /// puts the wrong name on someone's words.
    static let matchThreshold: Float = 0.45

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

    // MARK: - Matching

    /// Best-matching known name for a centroid, or nil when nothing is close enough.
    func match(centroid: [Float]) -> String? {
        var best: (name: String, distance: Float)? = nil
        for p in profiles {
            guard let d = Self.cosineDistance(p.centroid, centroid) else { continue }
            if best == nil || d < best!.distance { best = (p.name, d) }
        }
        guard let b = best, b.distance <= Self.matchThreshold else { return nil }
        Log.pipeline.info("speaker matched profile distance=\(b.distance)")
        return b.name
    }

    /// Records a user-supplied name against a voice. Called on rename, which is
    /// the only way a profile is ever created — the app never tries to identify
    /// someone it was not told about (PRD §5).
    func remember(name: String, centroid: [Float]) {
        guard !name.isEmpty, !centroid.isEmpty else { return }
        if let i = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
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
            profiles[i] = Profile(name: p.name, centroid: merged, samples: p.samples + 1, updatedAt: Date())
        } else {
            profiles.append(Profile(name: name, centroid: centroid, samples: 1, updatedAt: Date()))
        }
        persist()
    }

    /// Biometric-adjacent data: deletable, local, never transmitted (PRD §9.1).
    func forget(name: String) {
        profiles.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        persist()
    }

    func forgetAll() {
        profiles = []
        persist()
    }

    func knownNames() -> [String] { profiles.map(\.name).sorted() }

    // MARK: - FR-51: seeing and curating what is remembered

    /// What the voices list shows. Deliberately excludes the centroid: it is the
    /// one field that is biometric-adjacent and it means nothing to a reader.
    struct Summary: Identifiable, Equatable, Sendable {
        var id: String { name }
        let name: String
        /// How many Meetings contributed, so a one-sample guess is distinguishable
        /// from a well-established voice.
        let samples: Int
        let updatedAt: Date
    }

    func summaries() -> [Summary] {
        profiles
            .map { Summary(name: $0.name, samples: $0.samples, updatedAt: $0.updatedAt) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    @discardableResult
    func rename(from old: String, to new: String) -> Bool {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame })
        else { return false }

        if let j = profiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
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
                                  samples: a.samples + b.samples, updatedAt: Date())
            profiles.remove(at: i)
        } else {
            let p = profiles[i]
            profiles[i] = Profile(name: trimmed, centroid: p.centroid,
                                  samples: p.samples, updatedAt: Date())
        }
        persist()
        return true
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

    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return nil }
        return 1 - (dot / (na.squareRoot() * nb.squareRoot()))
    }
}
