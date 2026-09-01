import Foundation

// AD-28: the identification MECHANISM lives here, in Core, and imports Foundation
// and nothing else. That is not a stylistic preference — it is the whole reason
// this file exists as its own type rather than as three methods on
// `SpeakerDirectory`.
//
// The user's constraint was that the way Minutes decides which voice is theirs
// must be plain arithmetic on numbers, portable to a system with no Apple
// frameworks in it. An adapter may be as Apple-specific as it likes: today
// `SpeakerKitVoiceEmbedder` uses pyannote embeddings through CoreML, and if it
// were replaced tomorrow nothing below would change. What must never happen is a
// framework type leaking into the comparison, because at that moment the feature
// stops being maths and starts being a platform.
//
// This is why the mic-isolation spike rejected Apple's Voice Isolation. It is
// free, already in macOS, and on AirPods aggressive at removing other voices —
// the cheapest effective thing available. It was rejected because adopting it as
// the mechanism would have made the answer macOS-only.

/// A fixed-length voice embedding, plus the identity of whatever produced it.
///
/// AD-29: the producer is not decoration. Two vectors from different embedders
/// are not "far apart" — they are **not comparable**, and a system that treats
/// the second as the first will hand back a confident number that means nothing.
/// That is the worst failure available to this feature: no error, no crash, no
/// log line, just the wrong name on someone's words.
struct VoiceFingerprint: Codable, Sendable, Equatable {
    /// The embedding. Never logged, never shown to the user, never transmitted
    /// (PRD §9.1).
    var vector: [Float]
    /// Which embedder produced `vector`. Compared before the vectors are.
    var producer: String

    var dimensions: Int { vector.count }
    var isUsable: Bool { !vector.isEmpty && !producer.isEmpty }

    init(vector: [Float], producer: String) {
        self.vector = vector
        self.producer = producer
    }
}

/// Comparison and resolution. Pure, synchronous, and testable with no audio
/// hardware, no model and no diarizer.
enum VoiceMatch {

    // MARK: - Calibrated constants (AD-31)

    /// Cosine distance below which two fingerprints are treated as one person.
    ///
    /// **0.35, measured on 2026-09-01** — not chosen. Calibrated against 24
    /// centroids from five real meetings recorded on this machine
    /// (`_bmad-output/planning-artifacts/spikes/calibration-speaker-threshold-2026-09-01.md`):
    ///
    /// - the same in-room voice measured **0.058 – 0.248** apart across four
    ///   independent recordings
    /// - two different in-room voices in one meeting measured **0.596 and above**
    ///
    /// 0.35 sits in that gap with 41% headroom above the observed same-voice
    /// maximum and a factor of 1.7 below the tightest genuine in-room impostor.
    /// The previous value, 0.45, had never been calibrated and was measurably
    /// loose: two genuinely different remote speakers measured 0.254 apart.
    ///
    /// **A limit the same measurement found, recorded rather than hidden:** for
    /// remote speakers the two populations touch — same speaker up to 0.248,
    /// different speakers from 0.254 — so no threshold separates them. 0.35
    /// therefore admits two known false matches among remote voices. That is
    /// accepted, not overlooked: FR-25 renders an auto-applied name as inferred
    /// and FR-51 makes it correctable, so the cost is one rename. A value tight
    /// enough to exclude them (0.25) leaves 0.002 of headroom above a genuine
    /// match, at which point enrolment stops working.
    ///
    /// Not a setting. Not in `Preferences`, not in `UserDefaults`, not reachable
    /// from any pane (FR-65). Changing it means re-running the calibration.
    static let sameSpeakerThreshold: Float = 0.35

    /// How much closer the best candidate must be than the runner-up before an
    /// identification is claimed (AD-30).
    ///
    /// 0.10, from the same measurement: genuine different in-room voices sit
    /// ≥ 0.596 apart, so a real user cluster clears this by a wide margin, and
    /// two candidates within 0.10 of each other almost certainly means the
    /// diarizer split one person in two — or that the app genuinely cannot tell.
    /// Either way it claims nothing, which is AD-11 applied to its own new path.
    static let ambiguityMargin: Float = 0.10

    // MARK: - Distance

    /// Cosine distance between two fingerprints, or `nil` when they cannot be
    /// compared at all.
    ///
    /// `nil` means **no information** and must never be read as "far apart"
    /// (AD-29). Collapsing those two is how a fingerprint written by one
    /// embedder becomes a silent permanent non-match under the next one.
    static func distance(_ a: VoiceFingerprint, _ b: VoiceFingerprint) -> Float? {
        guard a.isUsable, b.isUsable else { return nil }
        guard a.producer == b.producer else { return nil }
        return cosineDistance(a.vector, b.vector)
    }

    /// The arithmetic, on two plain arrays. `nil` on a length mismatch or a zero
    /// vector — both are "cannot say", not "no match".
    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return nil }
        return 1 - (dot / (na.squareRoot() * nb.squareRoot()))
    }

    // MARK: - Resolution

    /// One voice the probe might be.
    struct Candidate: Sendable, Equatable {
        /// Opaque to this type — a `SpeakerLabelID.raw`, a profile name, anything.
        let key: String
        let fingerprint: VoiceFingerprint

        init(key: String, fingerprint: VoiceFingerprint) {
            self.key = key
            self.fingerprint = fingerprint
        }
    }

    /// The four things that can happen, and they are deliberately four rather
    /// than a `String?`. Three of them mean "no name", and the UI and the logs
    /// need to tell them apart: nothing was close, two things were equally
    /// close, or nothing was comparable in the first place.
    enum Resolution: Sendable, Equatable {
        /// Close enough and unambiguous. The only case that produces a name.
        case matched(key: String, distance: Float)
        /// Nothing within the threshold. Carries the nearest distance seen, for
        /// diagnosis — a run of 0.36s means the threshold is the problem, and a
        /// run of 0.9s means the voice was not in the room.
        case noMatch(nearest: Float?)
        /// Two candidates within `ambiguityMargin` of each other. Most likely one
        /// person the diarizer split in two.
        case ambiguous(first: String, second: String, distance: Float)
        /// Nothing could be compared: no candidates, or none sharing the probe's
        /// producer and dimension. Distinct from `noMatch` on purpose (AD-29).
        case notComparable

        var matchedKey: String? {
            if case .matched(let key, _) = self { return key }
            return nil
        }
        var matchedDistance: Float? {
            if case .matched(_, let d) = self { return d }
            return nil
        }
    }

    // MARK: - Diarizer glue

    /// Turns a diarizer's per-cluster centroids into candidates.
    ///
    /// Extracted from the pipeline deliberately. The round trip — an `Int` cluster
    /// index becomes a `String` key, a `Resolution` names that key, and the key
    /// becomes an `Int` again — is three lines of glue that decide *which voice is
    /// the user*, and inside `diarizeStage` it was unreachable by any test that
    /// does not load a CoreML model and read a WAV file. If the round trip were
    /// wrong, the wrong colleague would be labelled as the user and every test
    /// would still pass.
    static func candidates(from centroids: [Int: [Float]], producer: String) -> [Candidate] {
        centroids
            .compactMap { idx, vec -> Candidate? in
                guard !vec.isEmpty else { return nil }
                return Candidate(key: String(idx),
                                 fingerprint: VoiceFingerprint(vector: vec, producer: producer))
            }
            // Sorted so the candidate list is stable: the input is a dictionary and
            // has no order, and `resolve` breaks ties by key.
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// The diarizer cluster index a resolution names, or `nil` for all three of the
    /// outcomes that claim nothing.
    static func micVoiceIndex(_ r: Resolution) -> Int? {
        guard let key = r.matchedKey else { return nil }
        return Int(key)
    }

    /// Picks the candidate the probe is, or declines to.
    ///
    /// Nothing here is stateful and nothing here is heuristic beyond the two
    /// calibrated constants. Given the same inputs it returns the same answer
    /// forever, which is what makes the identification reviewable.
    static func resolve(_ probe: VoiceFingerprint,
                        among candidates: [Candidate]) -> Resolution {
        guard probe.isUsable else { return .notComparable }

        // Only candidates the probe can actually be compared with. A candidate
        // from another embedder is dropped rather than scored as distant.
        var scored: [(key: String, distance: Float)] = []
        for c in candidates {
            guard let d = distance(probe, c.fingerprint) else { continue }
            scored.append((c.key, d))
        }
        guard !scored.isEmpty else { return .notComparable }

        // Sort by distance, then by key, so ties are resolved deterministically
        // rather than by whatever order the caller happened to build.
        scored.sort { $0.distance == $1.distance ? $0.key < $1.key : $0.distance < $1.distance }
        let best = scored[0]

        guard best.distance <= sameSpeakerThreshold else {
            return .noMatch(nearest: best.distance)
        }
        if scored.count > 1 {
            let runnerUp = scored[1]
            if runnerUp.distance - best.distance < ambiguityMargin {
                return .ambiguous(first: best.key, second: runnerUp.key,
                                  distance: best.distance)
            }
        }
        return .matched(key: best.key, distance: best.distance)
    }
}
