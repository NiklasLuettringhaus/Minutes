import XCTest
@testable import Minutes

/// Story 10.1 — the calibration, checkable against the data that produced it.
///
/// These tests read the real Meetings on this machine and **skip cleanly when
/// they are not there**, which is deliberate and is the only honest option. The
/// centroids they read are biometric-adjacent data belonging to the user's
/// colleagues, and PRD §9.1 keeps that on the machine that recorded it — so there
/// is no fixture in this repository and there must never be one. Copying a
/// colleague's voice embedding into version control to make a test green would
/// breach the guarantee the whole product rests on.
///
/// The consequence is stated rather than hidden: on CI, or on any machine with no
/// meetings, this file proves nothing. `VoiceMatchTests` is what runs everywhere,
/// and it pins the constants and the logic. This file pins the constants to
/// *reality*, on the one machine where reality is available.
final class EnrolmentCalibrationTests: XCTestCase {

    // MARK: - Loading

    private struct Voice {
        let meeting: String
        let label: String
        let vector: [Float]
        var isInRoom: Bool { label == "local" || label.hasPrefix("room-") }
        var isRemote: Bool { label.hasPrefix("remote-") }
    }

    private static func loadVoices() -> [Voice] {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Minutes/Meetings", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var out: [Voice] = []
        for d in dirs.sorted() {
            let url = root.appendingPathComponent(d).appendingPathComponent("centroids.json")
            guard let data = try? Data(contentsOf: url),
                  let map = try? JSONDecoder().decode([String: [Float]].self, from: data)
            else { continue }
            for (label, vector) in map where !vector.isEmpty {
                out.append(Voice(meeting: d, label: label, vector: vector))
            }
        }
        return out
    }

    private func voicesOrSkip() throws -> [Voice] {
        let v = Self.loadVoices()
        // Two meetings is the minimum for anything cross-recording to mean
        // something, which is what enrolment actually depends on.
        try XCTSkipIf(Set(v.map(\.meeting)).count < 2,
                      "Needs at least two real Meetings with centroids.json on this machine. Nothing is fabricated to stand in for them.")
        return v
    }

    private func distance(_ a: Voice, _ b: Voice) -> Float? {
        VoiceMatch.cosineDistance(a.vector, b.vector)
    }

    // MARK: - The measured claims

    /// Every centroid the app has written must be the width the embedder produces.
    /// A mixed-width store would mean AD-29's "not comparable" path firing on real
    /// data, silently, forever.
    func testAllStoredCentroidsShareOneDimension() throws {
        let voices = try voicesOrSkip()
        let dims = Set(voices.map(\.vector.count))
        XCTAssertEqual(dims.count, 1, "mixed centroid widths on disk: \(dims.sorted())")
    }

    /// The claim FR-63 rests on: an in-room voice is reproducible across separate
    /// recordings. Measured as the tightest cross-meeting in-room pairs, which is
    /// what an enrolled fingerprint is compared against.
    ///
    /// This does not assert *which* voice is the user — that is unknowable from the
    /// files, and asserting it would be inventing a fact. It asserts that in-room
    /// voices form tight cross-meeting clusters at all, because if they did not,
    /// enrolment could not work regardless of threshold.
    func testAnInRoomVoiceIsReproducibleAcrossMeetings() throws {
        let voices = try voicesOrSkip()
        let inRoom = voices.filter(\.isInRoom)
        try XCTSkipIf(inRoom.count < 4, "not enough in-room voices to compare across meetings")

        var tightest: [Float] = []
        for a in inRoom {
            // The nearest in-room voice in a *different* meeting.
            let others = inRoom.filter { $0.meeting != a.meeting }
            guard !others.isEmpty else { continue }
            let best = others.compactMap { distance(a, $0) }.min()
            if let best { tightest.append(best) }
        }
        try XCTSkipIf(tightest.isEmpty, "no cross-meeting in-room pairs available")

        // At least some in-room voices must find a very close counterpart in
        // another recording, or "the same person sounds the same next week" is
        // false and the feature is built on nothing.
        let closest = tightest.min()!
        XCTAssertLessThanOrEqual(closest, VoiceMatch.sameSpeakerThreshold,
            "no in-room voice matched any in-room voice from another meeting within the calibrated threshold (closest \(closest)). Enrolment cannot work on this data.")
    }

    /// The other half of the gap: two different people in the same room, in the
    /// same recording, must not look like one person. The diarizer separated them,
    /// so they are known to be different — this is the cleanest impostor set the
    /// data offers.
    ///
    /// Room-versus-room only, on purpose. A room voice and a *remote* voice can be
    /// the same physical person — a colleague sitting in the room who is also
    /// joined to the call reaches both Streams — and the calibration proved exactly
    /// that for two pairs, at 0.128 and 0.373 with 83–93% temporal overlap and
    /// identical text. Treating those as impostors is what would make 0.35 look
    /// wrong when it is not.
    func testTwoDifferentInRoomVoicesAreNeverConfusedAtTheCalibratedThreshold() throws {
        let voices = try voicesOrSkip()
        var pairs = 0
        var violations: [String] = []
        let byMeeting = Dictionary(grouping: voices.filter(\.isInRoom), by: \.meeting)

        for (meeting, group) in byMeeting where group.count > 1 {
            for i in 0..<group.count {
                for j in (i + 1)..<group.count {
                    guard let d = distance(group[i], group[j]) else { continue }
                    pairs += 1
                    if d <= VoiceMatch.sameSpeakerThreshold {
                        violations.append("\(meeting) \(group[i].label) vs \(group[j].label) = \(d)")
                    }
                }
            }
        }
        try XCTSkipIf(pairs == 0, "no meeting on this machine has two in-room voices")
        XCTAssertTrue(violations.isEmpty,
            "the calibrated threshold would merge \(violations.count) of \(pairs) known-different in-room voices: \(violations.joined(separator: "; "))")
    }

    /// The end-to-end claim, on real audio, without inventing an identity.
    ///
    /// Takes one meeting's in-room centroid, treats it as an enrolled fingerprint,
    /// and asks `VoiceMatch.resolve` — the exact function the pipeline calls — to
    /// find that voice among a *different* meeting's in-room voices. When it
    /// answers, the answer must be the nearest voice, and the identification must
    /// be reachable at all: if no pair in the whole corpus resolves to `.matched`,
    /// the mechanism does not work on this data and the test says so.
    func testResolveFindsAKnownVoiceInAnotherMeeting() throws {
        let voices = try voicesOrSkip()
        let producer = "calibration/test"
        let byMeeting = Dictionary(grouping: voices.filter(\.isInRoom), by: \.meeting)
        let meetings = byMeeting.keys.sorted()
        try XCTSkipIf(meetings.count < 2, "need two meetings with in-room voices")

        var matches = 0
        var ambiguous = 0
        var noMatch = 0

        for probeMeeting in meetings {
            for probe in byMeeting[probeMeeting] ?? [] {
                for targetMeeting in meetings where targetMeeting != probeMeeting {
                    let candidates = (byMeeting[targetMeeting] ?? []).map {
                        VoiceMatch.Candidate(
                            key: "\($0.label)",
                            fingerprint: VoiceFingerprint(vector: $0.vector, producer: producer))
                    }
                    guard candidates.count > 1 else { continue }
                    let r = VoiceMatch.resolve(
                        VoiceFingerprint(vector: probe.vector, producer: producer),
                        among: candidates)
                    switch r {
                    case .matched(let key, let d):
                        matches += 1
                        // Whatever it picks, it must be the nearest — the resolution
                        // is "nearest, if close and clear", never "first found".
                        let nearest = candidates
                            .compactMap { c -> (String, Float)? in
                                guard let dd = VoiceMatch.cosineDistance(probe.vector, c.fingerprint.vector)
                                else { return nil }
                                return (c.key, dd)
                            }
                            .min { $0.1 < $1.1 }
                        XCTAssertEqual(key, nearest?.0,
                                       "resolved \(key) but \(nearest?.0 ?? "?") was nearer")
                        XCTAssertEqual(d, nearest?.1 ?? -1, accuracy: 1e-5)
                    case .ambiguous: ambiguous += 1
                    case .noMatch: noMatch += 1
                    case .notComparable:
                        XCTFail("real centroids from one embedder must always be comparable")
                    }
                }
            }
        }

        // Recorded rather than asserted as a ratio: the corpus is whatever this
        // machine happens to hold, and a hard-coded hit rate would be a fixture
        // pretending to be a measurement.
        print("[calibration] cross-meeting in-room resolutions: \(matches) matched, \(ambiguous) ambiguous, \(noMatch) no-match")
        XCTAssertGreaterThan(matches, 0,
            "no in-room voice was identifiable in any other meeting. Enrolment's central mechanism does not work on this data.")
    }

    /// A guard against the specific way this could regress silently: if the
    /// embedder changed and old centroids stayed on disk, every comparison would
    /// return nil and enrolment would fail with no error anywhere. AD-29 makes
    /// that a recognisable "cannot say" rather than a false "far apart", and this
    /// checks the recognisable half is what actually happens.
    func testACentroidFromAnotherProducerIsNeverSilentlyCompared() throws {
        let voices = try voicesOrSkip()
        guard let real = voices.first else { return }
        let mine = VoiceFingerprint(vector: real.vector, producer: "speakerkit/pyannote-v4-community-1")
        let theirs = VoiceFingerprint(vector: real.vector, producer: "future/embedder-v2")
        XCTAssertNil(VoiceMatch.distance(mine, theirs))
        XCTAssertEqual(VoiceMatch.resolve(mine, among: [.init(key: "0", fingerprint: theirs)]),
                       .notComparable)
    }
}
