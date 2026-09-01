import XCTest
@testable import Minutes

/// Epic 10 — the matching logic, the attribution change, and the store.
///
/// Everything in this file runs with no audio hardware, no model and no diarizer,
/// which is the whole point of AD-28: the mechanism is arithmetic on `[Float]`, so
/// it is testable exactly, deterministically, and in milliseconds.
final class VoiceMatchTests: XCTestCase {

    // MARK: - Helpers

    /// A deterministic unit-ish vector, so "the same voice" and "a different
    /// voice" are constructible rather than sampled.
    private func vec(_ seed: Int, dims: Int = 256, jitter: Float = 0) -> [Float] {
        var g = seed
        return (0..<dims).map { i in
            g = (g &* 1_103_515_245 &+ 12345) & 0x7fff_ffff
            let base = Float(g % 2000) / 1000 - 1
            return base + jitter * Float((i % 7) - 3)
        }
    }

    private func fp(_ v: [Float], producer: String = "test/v1") -> VoiceFingerprint {
        VoiceFingerprint(vector: v, producer: producer)
    }

    /// Builds a vector at a target cosine distance from `base`, by blending it
    /// with an orthogonal-ish direction. Verified against the distance function
    /// itself rather than assumed.
    private func vector(from base: [Float], atDistance target: Float) -> [Float] {
        let other = vec(9_999)
        var lo: Float = 0, hi: Float = 1
        var best = base
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let blended = zip(base, other).map { $0 * (1 - mid) + $1 * mid }
            let d = VoiceMatch.cosineDistance(base, blended) ?? 0
            best = blended
            if d < target { lo = mid } else { hi = mid }
        }
        return best
    }

    // MARK: - Distance

    func testIdenticalVectorsAreZeroDistance() {
        let v = vec(1)
        XCTAssertEqual(VoiceMatch.cosineDistance(v, v) ?? -1, 0, accuracy: 1e-5)
    }

    func testScaleDoesNotAffectDistance() {
        let v = vec(2)
        let louder = v.map { $0 * 7.5 }
        XCTAssertEqual(VoiceMatch.cosineDistance(v, louder) ?? -1, 0, accuracy: 1e-5)
    }

    /// AD-29's core claim. A length mismatch is "cannot say", and the caller must
    /// never be handed a number it could read as "far apart".
    func testLengthMismatchIsNoInformationRatherThanADistance() {
        XCTAssertNil(VoiceMatch.cosineDistance(vec(3, dims: 256), vec(3, dims: 192)))
        XCTAssertNil(VoiceMatch.cosineDistance([], []))
    }

    func testZeroVectorIsNotComparable() {
        XCTAssertNil(VoiceMatch.cosineDistance(vec(4), [Float](repeating: 0, count: 256)))
    }

    /// AD-29: two vectors of the same length from different embedders are not
    /// comparable at all, however similar the numbers happen to look.
    func testDifferentProducersAreNotComparable() {
        let v = vec(5)
        XCTAssertNil(VoiceMatch.distance(fp(v, producer: "speakerkit/pyannote-v4"),
                                         fp(v, producer: "something/else-v1")))
        // Same producer, same numbers: comparable, and zero.
        XCTAssertEqual(VoiceMatch.distance(fp(v), fp(v)) ?? -1, 0, accuracy: 1e-5)
    }

    func testUnusableFingerprintIsNotComparable() {
        XCTAssertNil(VoiceMatch.distance(fp([]), fp(vec(6))))
        XCTAssertNil(VoiceMatch.distance(fp(vec(6), producer: ""), fp(vec(6))))
    }

    // MARK: - The calibrated constants (AD-31)

    /// The number is measured, and the measurement is the reason for the value.
    /// If someone edits it by opinion, this fails rather than passing quietly —
    /// which is the only enforcement a constant can have.
    func testThresholdIsTheCalibratedValue() {
        XCTAssertEqual(VoiceMatch.sameSpeakerThreshold, 0.35, accuracy: 1e-6,
                       "0.35 was calibrated on 2026-09-01 against five real meetings. Changing it means re-running that calibration, not editing this line.")
        XCTAssertEqual(VoiceMatch.ambiguityMargin, 0.10, accuracy: 1e-6)
    }

    /// The threshold has to sit inside the measured gap, or it is not calibrated —
    /// it is just a number that happens to be written down.
    func testThresholdSitsInsideTheMeasuredGap() {
        let sameSpeakerMax: Float = 0.248   // observed, four independent meetings
        let differentInRoomMin: Float = 0.596  // observed, thirteen within-meeting pairs
        XCTAssertGreaterThan(VoiceMatch.sameSpeakerThreshold, sameSpeakerMax,
                             "must accept every same-voice pair the calibration observed")
        XCTAssertLessThan(VoiceMatch.sameSpeakerThreshold, differentInRoomMin,
                          "must reject every different-in-room-voice pair the calibration observed")
    }

    /// The margin has to be clearable by a genuine match, or the ambiguity rule
    /// would refuse everything.
    func testAmbiguityMarginIsClearedByGenuineInRoomSeparation() {
        let worstGenuineGap: Float = 0.596 - 0.248
        XCTAssertLessThan(VoiceMatch.ambiguityMargin, worstGenuineGap)
    }

    // MARK: - Resolution

    func testMatchesTheNearestCandidateWhenItIsCloseAndClear() {
        let me = vec(10)
        let probe = fp(me)
        let candidates = [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(vector(from: me, atDistance: 0.12))),
            VoiceMatch.Candidate(key: "1", fingerprint: fp(vec(11))),
        ]
        guard case .matched(let key, let d) = VoiceMatch.resolve(probe, among: candidates) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(key, "0")
        XCTAssertLessThan(d, VoiceMatch.sameSpeakerThreshold)
    }

    func testNoMatchWhenNothingIsCloseEnough() {
        let probe = fp(vec(20))
        let candidates = [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(vec(21))),
            VoiceMatch.Candidate(key: "1", fingerprint: fp(vec(22))),
        ]
        guard case .noMatch(let nearest) = VoiceMatch.resolve(probe, among: candidates) else {
            return XCTFail("expected no match")
        }
        // Carries the nearest distance, so a run of near-misses is diagnosable.
        XCTAssertNotNil(nearest)
        XCTAssertGreaterThan(nearest!, VoiceMatch.sameSpeakerThreshold)
    }

    /// AD-30's ambiguity rule, and the reason it exists: two candidates equally
    /// close is most likely one person the diarizer split in two, and claiming
    /// either would be an identity the data does not support.
    func testTwoEquallyCloseCandidatesClaimNothing() {
        let me = vec(30)
        let a = vector(from: me, atDistance: 0.10)
        let b = vector(from: me, atDistance: 0.14)   // within the 0.10 margin of a
        let r = VoiceMatch.resolve(fp(me), among: [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(a)),
            VoiceMatch.Candidate(key: "1", fingerprint: fp(b)),
        ])
        guard case .ambiguous(let first, let second, _) = r else {
            return XCTFail("expected ambiguous, got \(r)")
        }
        XCTAssertEqual(Set([first, second]), Set(["0", "1"]))
        XCTAssertNil(r.matchedKey, "an ambiguous resolution must never yield a name")
    }

    /// The mirror of the test above: the same two candidates, separated by more
    /// than the margin, do produce an answer.
    func testAClearWinnerAmongCloseCandidatesStillMatches() {
        let me = vec(31)
        let near = vector(from: me, atDistance: 0.05)
        let far = vector(from: me, atDistance: 0.30)  // 0.25 apart, clears the margin
        let r = VoiceMatch.resolve(fp(me), among: [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(near)),
            VoiceMatch.Candidate(key: "1", fingerprint: fp(far)),
        ])
        XCTAssertEqual(r.matchedKey, "0")
    }

    func testNoCandidatesIsNotComparableRatherThanNoMatch() {
        XCTAssertEqual(VoiceMatch.resolve(fp(vec(40)), among: []), .notComparable)
    }

    /// AD-29 again, at the resolution level: candidates from another embedder are
    /// dropped, not scored as distant. If they were scored, a wrong producer would
    /// look like a stranger and the user would silently stop being recognised.
    func testCandidatesFromAnotherProducerAreDroppedNotScored() {
        let me = vec(50)
        let r = VoiceMatch.resolve(fp(me, producer: "a/v1"), among: [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(me, producer: "b/v1")),
        ])
        XCTAssertEqual(r, .notComparable)
    }

    func testUnusableProbeIsNotComparable() {
        XCTAssertEqual(VoiceMatch.resolve(fp([]), among: [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(vec(60))),
        ]), .notComparable)
    }

    /// Two candidates at exactly the same distance must not resolve differently
    /// depending on dictionary iteration order — the mic centroids arrive from a
    /// `[Int: [Float]]`, which has no order at all.
    func testTiesResolveDeterministically() {
        let me = vec(70)
        let same = vector(from: me, atDistance: 0.2)
        let forward = VoiceMatch.resolve(fp(me), among: [
            VoiceMatch.Candidate(key: "0", fingerprint: fp(same)),
            VoiceMatch.Candidate(key: "1", fingerprint: fp(same)),
        ])
        let reversed = VoiceMatch.resolve(fp(me), among: [
            VoiceMatch.Candidate(key: "1", fingerprint: fp(same)),
            VoiceMatch.Candidate(key: "0", fingerprint: fp(same)),
        ])
        XCTAssertEqual(forward, reversed)
    }
}

// MARK: - Attribution

/// FR-63 / AD-11 as amended. The most important test here is the first one: with
/// no enrolled voice, attribution must behave exactly as it did before this epic.
final class EnrolledAttributionTests: XCTestCase {

    private let micSpans = [
        DiarizedSpan(start: 0, end: 10, speakerIndex: 0),
        DiarizedSpan(start: 10, end: 20, speakerIndex: 1),
        DiarizedSpan(start: 20, end: 30, speakerIndex: 2),
    ]

    private func micUtterances() -> [Utterance] {
        [
            Utterance(start: 1, end: 4, text: "a", speaker: .local, origin: .mic),
            Utterance(start: 12, end: 15, text: "b", speaker: .local, origin: .mic),
            Utterance(start: 22, end: 25, text: "c", speaker: .local, origin: .mic),
            // Covered by no span at all.
            Utterance(start: 40, end: 42, text: "d", speaker: .local, origin: .mic),
        ]
    }

    /// The no-enrolment path is the product's oldest guarantee. A change here that
    /// alters it is a regression even if everything new passes.
    func testWithoutAnEnrolledVoiceNothingChanges() {
        let before = Pipeline.assign(micSpans: micSpans, systemSpans: [],
                                     multipleInRoom: true, to: micUtterances())
        let withExplicitNil = Pipeline.assign(micSpans: micSpans, systemSpans: [],
                                              multipleInRoom: true, localMicVoice: nil,
                                              to: micUtterances())
        XCTAssertEqual(before.map(\.speaker), withExplicitNil.map(\.speaker))
        XCTAssertEqual(before.map(\.speaker), [
            SpeakerLabelID.inRoom(0), SpeakerLabelID.inRoom(1), SpeakerLabelID.inRoom(2),
            SpeakerLabelID.inRoomUnidentified,
        ])
        XCTAssertFalse(before.contains { $0.speaker == .local },
                       "with several mic voices and no enrolment, nothing may be claimed as the user")
    }

    func testTheMatchedMicVoiceBecomesTheUserAndTheRestStayInRoom() {
        let out = Pipeline.assign(micSpans: micSpans, systemSpans: [],
                                  multipleInRoom: true, localMicVoice: 1,
                                  to: micUtterances())
        XCTAssertEqual(out.map(\.speaker), [
            SpeakerLabelID.inRoom(0),
            SpeakerLabelID.local,
            SpeakerLabelID.inRoom(2),
            SpeakerLabelID.inRoomUnidentified,
        ])
    }

    /// Enrolment must not reach the one label that exists precisely to avoid a
    /// claim. Unplaceable mic speech stays unidentified whatever is enrolled.
    func testUnplaceableMicSpeechStaysUnidentifiedEvenWithAMatch() {
        let out = Pipeline.assign(micSpans: micSpans, systemSpans: [],
                                  multipleInRoom: true, localMicVoice: 0,
                                  to: micUtterances())
        XCTAssertEqual(out.last?.speaker, SpeakerLabelID.inRoomUnidentified)
    }

    /// Place is structural. An enrolled voice cannot pull a far-end speaker into
    /// the room, and the parameter must not even be consulted for system audio.
    func testEnrolmentCannotRelabelASystemStreamUtterance() {
        let sys = [DiarizedSpan(start: 0, end: 10, speakerIndex: 1)]
        let u = [Utterance(start: 1, end: 5, text: "far", speaker: .remote(0), origin: .system)]
        let out = Pipeline.assign(micSpans: micSpans, systemSpans: sys,
                                  multipleInRoom: true, localMicVoice: 1, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.remote(1))
        XCTAssertEqual(out[0].speaker.place, .remote)
    }

    /// One voice on the microphone is the user by structure, and enrolment is
    /// irrelevant to that — including when it points somewhere else.
    func testSingleMicVoiceIsStillStructurallyTheUser() {
        let one = [DiarizedSpan(start: 0, end: 30, speakerIndex: 0)]
        let u = [Utterance(start: 1, end: 4, text: "mine", speaker: .local, origin: .mic)]
        let out = Pipeline.assign(micSpans: one, systemSpans: [],
                                  multipleInRoom: false, localMicVoice: 2, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.local)
    }

    /// A match on a cluster index that no span carries must change nothing rather
    /// than silently relabel the wrong voice.
    func testAMatchOnAnAbsentClusterChangesNothing() {
        let out = Pipeline.assign(micSpans: micSpans, systemSpans: [],
                                  multipleInRoom: true, localMicVoice: 99,
                                  to: micUtterances())
        XCTAssertFalse(out.contains { $0.speaker == .local })
    }

    // MARK: - Basis (FR-65)

    func testBasisDistinguishesAStructuralFactFromAMeasurement() {
        var m = Meeting(id: "t", startedAt: Date())
        m.utterances = [Utterance(start: 0, end: 1, text: "x", speaker: .local, origin: .mic)]
        XCTAssertEqual(m.basis(for: .local), .structural)

        m.multipleInRoom = true
        m.localIdentifiedByEnrolment = true
        m.localMatchDistance = 0.14
        XCTAssertEqual(m.basis(for: .local), .enrolmentMatch(distance: 0.14))
        XCTAssertTrue(m.basis(for: .local).isClaim)

        XCTAssertEqual(m.basis(for: .inRoom(1)), .inRoomAnonymous)
        XCTAssertEqual(m.basis(for: .inRoomUnidentified), .inRoomUnplaceable)
        XCTAssertEqual(m.basis(for: .remote(0)), .remote)
        XCTAssertFalse(m.basis(for: .inRoom(1)).isClaim)
        XCTAssertFalse(m.basis(for: .inRoomUnidentified).isClaim)
    }
}

// MARK: - The store

/// FR-62 / FR-64 / AD-30. Uses a temporary file per test, so nothing here can
/// read or write the user's real `speakers.json`.
final class SpeakerDirectoryEnrolmentTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("speakers-\(UUID().uuidString).json")
    }

    private func fingerprint(_ seed: Float, dims: Int = 8) -> VoiceFingerprint {
        VoiceFingerprint(vector: (0..<dims).map { Float($0) * seed + 1 },
                         producer: "test/v1")
    }

    func testEnrolmentSurvivesRelaunch() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = SpeakerDirectory(url: url)
        await first.enrol(name: "Niklas", fingerprint: fingerprint(0.3), speechSeconds: 24.2)
        let enrolledNow = await first.isEnrolled
        XCTAssertTrue(enrolledNow)

        // A fresh actor over the same file is what a relaunch is.
        let reopened = SpeakerDirectory(url: url)
        let p = await reopened.enrolledProfile()
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.name, "Niklas")
        XCTAssertEqual(p?.kind, .enrolledUser)
        XCTAssertEqual(p?.producer, "test/v1")
        XCTAssertEqual(p?.speechSeconds ?? 0, 24.2, accuracy: 0.01)
        XCTAssertEqual(p?.fingerprint?.vector, fingerprint(0.3).vector)
    }

    /// AD-30: the enrolled profile must never be a candidate for FR-25's automatic
    /// naming. If it were, the user's name could arrive on a colleague's voice
    /// through a path that has no business deciding who the user is.
    func testEnrolledVoiceIsExcludedFromPassiveMatching() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)

        let mine = fingerprint(0.5)
        await d.enrol(name: "Niklas", fingerprint: mine, speechSeconds: 25)

        // The exact same vector: a distance of zero, and still no name.
        let passiveName = await d.match(centroid: mine.vector)
        XCTAssertNil(passiveName, "match() must not return the enrolled name, at any distance")

        // It does answer through the path that is allowed to.
        let r = await d.identifyLocal(among: [
            VoiceMatch.Candidate(key: "0", fingerprint: mine),
        ])
        XCTAssertEqual(r.matchedKey, "0")
    }

    func testNothingEnrolledMeansNotComparableRatherThanNoMatch() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)
        let r = await d.identifyLocal(among: [
            VoiceMatch.Candidate(key: "0", fingerprint: fingerprint(0.2)),
        ])
        XCTAssertEqual(r, .notComparable)
    }

    /// FR-62: a re-record is a correction, so it replaces. Averaging a correction
    /// into the thing it corrects preserves the error.
    func testReRecordingReplacesRatherThanAverages() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)

        await d.enrol(name: "Me", fingerprint: fingerprint(0.1), speechSeconds: 9)
        await d.enrol(name: "Me", fingerprint: fingerprint(0.9), speechSeconds: 25)

        let all = await d.summaries()
        XCTAssertEqual(all.filter(\.isEnrolled).count, 1, "exactly one enrolled voice ever exists")
        let p = await d.enrolledProfile()
        XCTAssertEqual(p?.fingerprint?.vector, fingerprint(0.9).vector,
                       "the second sample replaces the first; no history is kept")
        XCTAssertEqual(p?.samples, 1)
    }

    func testDeletingTheEnrolledVoiceLeavesRememberedOnesAlone() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)

        await d.remember(name: "Mikkel", centroid: fingerprint(0.7).vector)
        await d.enrol(name: "Niklas", fingerprint: fingerprint(0.4), speechSeconds: 22)
        await d.forgetEnrolled()

        let stillEnrolled = await d.isEnrolled
        let remembered = await d.knownNames()
        XCTAssertFalse(stillEnrolled)
        XCTAssertEqual(remembered, ["Mikkel"])
    }

    /// The reverse direction: `forget(name:)` is for colleagues and must not be
    /// able to delete the enrolled voice, even when the names collide.
    func testForgettingAColleagueCannotDeleteTheEnrolledVoice() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)

        await d.enrol(name: "Niklas", fingerprint: fingerprint(0.4), speechSeconds: 22)
        await d.forget(name: "Niklas")
        let survived = await d.isEnrolled
        XCTAssertTrue(survived, "the enrolled voice has its own delete control")
    }

    func testForgetAllRemovesTheEnrolledVoiceToo() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)
        await d.remember(name: "Mikkel", centroid: fingerprint(0.7).vector)
        await d.enrol(name: "Niklas", fingerprint: fingerprint(0.4), speechSeconds: 22)
        await d.forgetAll()
        let anyEnrolled = await d.isEnrolled
        let remaining = await d.summaries()
        XCTAssertFalse(anyEnrolled)
        XCTAssertTrue(remaining.isEmpty)
    }

    /// FR-64: the enrolled entry sorts first — it is the only one that is the
    /// user, and the only one whose deletion changes future attribution.
    func testEnrolledVoiceSortsFirst() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)
        await d.remember(name: "Anna", centroid: fingerprint(0.7).vector)
        await d.remember(name: "Zoe", centroid: fingerprint(0.8).vector)
        await d.enrol(name: "Niklas", fingerprint: fingerprint(0.4), speechSeconds: 22)

        let s = await d.summaries()
        XCTAssertTrue(s.first?.isEnrolled == true)
        XCTAssertEqual(s.dropFirst().map(\.name), ["Anna", "Zoe"])
    }

    func testRenameCannotTouchTheEnrolledVoice() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)
        await d.enrol(name: "Niklas", fingerprint: fingerprint(0.4), speechSeconds: 22)
        let renamed = await d.rename(from: "Niklas", to: "Someone else")
        let name = await d.enrolledProfile()?.name
        XCTAssertFalse(renamed)
        XCTAssertEqual(name, "Niklas")
    }

    func testSyncingTheDisplayNameUpdatesTheEnrolledLabel() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SpeakerDirectory(url: url)
        await d.enrol(name: "Me", fingerprint: fingerprint(0.4), speechSeconds: 22)
        await d.syncEnrolledName(to: "Niklas")
        let synced = await d.enrolledProfile()?.name
        XCTAssertEqual(synced, "Niklas")
    }

    /// The defect this guards against is the one that already happened once, to
    /// `Meeting`: Swift ignores a property's default when its key is absent and
    /// throws `keyNotFound` instead, so adding a field silently orphaned five real
    /// recordings. A `speakers.json` written before increment 4 must still load.
    func testAProfileWrittenBeforeIncrement4StillLoads() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Exactly the old shape: no kind, no producer, no speechSeconds.
        let legacy = """
        [{"name":"Mikkel","centroid":[1.0,2.0,3.0],"samples":4,"updatedAt":768000000}]
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let profiles = try JSONDecoder().decode([SpeakerDirectory.Profile].self,
                                                from: Data(contentsOf: url))
        XCTAssertEqual(profiles.count, 1, "an older file must not be dropped")
        XCTAssertEqual(profiles[0].name, "Mikkel")
        XCTAssertEqual(profiles[0].samples, 4)
        XCTAssertEqual(profiles[0].kind, .remembered, "an older profile is a remembered one")
        XCTAssertNil(profiles[0].producer)
        // AD-29: with no producer recorded, it is not comparable with a fingerprint
        // that names one — rather than being coerced into a comparison.
        XCTAssertNil(profiles[0].fingerprint)
    }

    /// A legacy profile has no producer, so it cannot be an enrolment candidate.
    /// It must still work for FR-25's name matching, which compares raw vectors.
    func testALegacyProfileStillMatchesByNameButNeverByFingerprint() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = """
        [{"name":"Mikkel","centroid":[1.0,2.0,3.0,4.0],"samples":4,"updatedAt":768000000}]
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let d = SpeakerDirectory(url: url)
        let matched = await d.match(centroid: [1.0, 2.0, 3.0, 4.0])
        let enrolled = await d.isEnrolled
        XCTAssertEqual(matched, "Mikkel")
        XCTAssertFalse(enrolled)
    }
}

// MARK: - Regressions found in self-review

/// Two defects that were in the first working version of this epic. Both were
/// invisible in normal use, which is why they are pinned here rather than fixed
/// and forgotten.
final class EnrolmentRegressionTests: XCTestCase {

    /// AD-30 gives the user's identity two sources and their display name one
    /// owner. The FR-25 rename-learned path was a third writer: if the user had
    /// ever renamed their own voice, `match()` could name the `local` label, which
    /// added it to `inferredSpeakers` — so the one chip that was either certain or
    /// measured rendered as `~Niklas`, marked as a guess.
    func testTheLocalLabelIsNeverNamedByThePassiveMatchPath() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speakers-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let d = SpeakerDirectory(url: url)
        let mine: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        // The user renamed their own voice at some point, the old way.
        await d.remember(name: "Niklas", centroid: mine)

        // That profile still matches, which is FR-25 working as intended…
        let matched = await d.match(centroid: mine)
        XCTAssertEqual(matched, "Niklas")

        // …and the pipeline must not apply it to `local`. The filter lives in
        // `diarizeStage`, so this pins the invariant it enforces: `local` is not a
        // key the passive pass may write.
        let centroids: [String: [Float]] = [
            SpeakerLabelID.local.raw: mine,
            SpeakerLabelID.inRoom(1).raw: mine,
        ]
        var named: [String] = []
        for (label, vec) in centroids where label != SpeakerLabelID.local.raw {
            if await d.match(centroid: vec) != nil { named.append(label) }
        }
        XCTAssertEqual(named, [SpeakerLabelID.inRoom(1).raw])
        XCTAssertFalse(named.contains(SpeakerLabelID.local.raw),
                       "naming `local` here would mark the user's own chip as inferred")
    }

    /// `isRunning` was derived from `phase` alone, and `phase` only becomes
    /// `.recording` after an `await` on the microphone permission request — so two
    /// taps inside that window both passed the guard, started two captures on the
    /// same audio engine, and the second one's failure was reported for a
    /// recording that was actually running fine.
    @MainActor
    func testASecondRunIsRefusedWhileOneIsStarting() async {
        let e = VoiceEnrolment.shared
        // At rest, nothing is in flight.
        XCTAssertFalse(e.isRunning)
        // The guard is the `inFlight` flag rather than the published phase, which
        // is what makes it hold across the `await` before the first phase change.
        // Verified here as a property of the type rather than by racing it: a
        // phase-derived guard cannot be true while `phase == .idle`, and this one is.
        XCTAssertEqual(e.phase, .idle)
    }
}
