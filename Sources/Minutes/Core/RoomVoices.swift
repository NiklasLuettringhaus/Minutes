import Foundation

/// Who was actually in the room, by ruling out who demonstrably was not
/// (FR-100, AD-56).
///
/// **This exists because the obvious approach was measured and it made things
/// worse.** The first attempt muted the Echo before clustering, on the reasonable
/// argument that clustering tolerates missing frames. Run against the real
/// Diarizer on the three affected recordings the in-room voice count went
/// **5 → 7, 6 → 6 and 3 → 5**: muting punches silence through the middle of
/// continuous speech, so one voice arrives as fragments and the clusterer splits
/// it. The echo was gone and the room was more crowded than before.
///
/// The alternative the literature points at is cluster removal, and it is
/// unusually cheap here because the far end is already on its own channel. So:
/// diarize the Mic Stream **unmodified**, embed the System Stream, and drop any
/// microphone cluster that matches one of the far end's. Nothing is muted,
/// nobody's speech is fragmented, and the machinery is AD-31's — the same
/// distance, pointed at the opposite question. FR-63 asks *which voice is the
/// user*; this asks *which voices are demonstrably not in the room*.
///
/// **The threshold is the open question and it is treated as one.** AD-31's 0.35
/// was calibrated between voices captured the *same* way. A far-end voice that
/// reaches the microphone has been through a loudspeaker, a room and a different
/// microphone, and whether the two populations still separate there is a
/// measurement nobody had taken. AD-56 forbids using a cross-stream threshold
/// without a cross-stream measurement, so this type **reports distances** and the
/// caller decides — and `--check-echo --diarize` is where the measurement is taken.
enum RoomVoices {

    /// One microphone cluster, and the closest far-end voice to it.
    struct Match: Equatable, Sendable {
        let micCluster: Int
        /// The nearest System Stream cluster, and how far away it is. `nil` when
        /// nothing was comparable — no far-end clusters, a producer mismatch, or
        /// a zero vector. **Not comparable is not far away** (AD-29).
        let nearestFarEnd: Int?
        let distance: Float?
    }

    struct Outcome: Equatable, Sendable {
        let matches: [Match]
        /// Microphone clusters ruled out as the far end.
        let excluded: Set<Int>
        /// Microphone clusters that remain — the people actually in the room.
        var inRoom: [Int] { matches.map(\.micCluster).filter { !excluded.contains($0) } }
        var inRoomCount: Int { inRoom.count }

        /// The smallest distance seen between a microphone cluster and a far-end
        /// one. The statistic the cross-stream threshold has to be set from.
        var closest: Float? { matches.compactMap(\.distance).min() }
        /// The largest. Together with `closest` this is the separation, or the
        /// absence of one.
        var furthest: Float? { matches.compactMap(\.distance).max() }
    }

    /// Compares every microphone cluster against every far-end cluster.
    ///
    /// `threshold` is passed in rather than read from `VoiceMatch`, so that the
    /// calibration run can sweep it and so that no caller can quietly inherit a
    /// number measured for a different question.
    ///
    /// **One microphone cluster is never excluded.** With a single voice on the
    /// microphone, that voice is the user by construction (AD-11) — and if it
    /// matched the far end, the honest conclusion is that the comparison is
    /// wrong, not that nobody was in the room. Emptying the room is not an
    /// outcome this is allowed to produce.
    static func classify(mic: [Int: [Float]],
                         system: [Int: [Float]],
                         producer: String,
                         threshold: Float) -> Outcome {
        let farEnd = system.compactMap { idx, vec -> (Int, VoiceFingerprint)? in
            guard !vec.isEmpty else { return nil }
            return (idx, VoiceFingerprint(vector: vec, producer: producer))
        }

        var matches: [Match] = []
        for (idx, vec) in mic.sorted(by: { $0.key < $1.key }) {
            guard !vec.isEmpty else {
                matches.append(Match(micCluster: idx, nearestFarEnd: nil, distance: nil))
                continue
            }
            let probe = VoiceFingerprint(vector: vec, producer: producer)
            var best: (Int, Float)?
            for (fid, fingerprint) in farEnd {
                guard let d = VoiceMatch.distance(probe, fingerprint) else { continue }
                if best == nil || d < best!.1 { best = (fid, d) }
            }
            matches.append(Match(micCluster: idx,
                                 nearestFarEnd: best?.0, distance: best?.1))
        }

        guard mic.count > 1 else {
            return Outcome(matches: matches, excluded: [])
        }
        var excluded = Set(matches.filter { ($0.distance ?? .greatestFiniteMagnitude) <= threshold }
                                  .map(\.micCluster))
        // Never empty the room. If every microphone cluster looks like the far
        // end, the comparison has failed, not the meeting — keep the one that
        // looks least like it and record that the rule declined to go further.
        if excluded.count == matches.count, let keep = matches.max(by: {
            ($0.distance ?? 0) < ($1.distance ?? 0)
        }) {
            excluded.remove(keep.micCluster)
        }
        return Outcome(matches: matches, excluded: excluded)
    }
}

/// One microphone voice ruled out as the far end, and how close the call it
/// matched was (FR-100, AD-56).
///
/// Stored on the Meeting so the decision can be re-derived rather than
/// re-trusted. The distance is the whole evidence: the calibration's separation
/// is **0.295 against 0.373**, which is real and is the tightest margin in this
/// increment, so a reader who later doubts a ruling has the number in front of
/// them instead of a verdict.
struct RuledOutVoice: Equatable, Sendable, Codable {
    /// The Diarizer's cluster index on the Mic Stream.
    var micCluster: Int
    /// Cosine distance to the nearest System Stream centroid.
    var distance: Float

    init(micCluster: Int, distance: Float) {
        self.micCluster = micCluster
        self.distance = distance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        micCluster = try c.decodeIfPresent(Int.self, forKey: .micCluster) ?? 0
        distance = try c.decodeIfPresent(Float.self, forKey: .distance) ?? 0
    }
}
