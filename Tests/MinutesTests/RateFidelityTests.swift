import XCTest
@testable import Minutes

/// AD-44 / AD-45 / FR-84 / FR-85 — are the samples at the rate they claim?
///
/// The check that was missing. Seven of sixteen recordings passed every existing
/// test and transcribed into fluent invented dialogue, so these tests are written
/// against the *real measured ratios* — exactly 2 and exactly 3 — rather than
/// against invented ones.
final class RateFidelityTests: XCTestCase {

    /// A stream behaving correctly: frames arrive at the rate the format declares.
    private func correct(rate: Double = 48_000, seconds: TimeInterval = 60) -> RateFidelity {
        RateFidelity(declaredRate: rate, framesObserved: rate * seconds, elapsedSeconds: seconds)
    }

    /// A stream declaring `rate` while the device delivers at `rate / factor`.
    /// This is the defect, parameterised.
    private func mislabelled(rate: Double = 48_000, factor: Double,
                             seconds: TimeInterval = 60) -> RateFidelity {
        RateFidelity(declaredRate: rate,
                     framesObserved: (rate / factor) * seconds,
                     elapsedSeconds: seconds)
    }

    // MARK: - The two ratios that actually occurred

    func testTheTwoRealFailuresAreCaught() {
        for factor in [2.0, 3.0] {
            let f = mislabelled(factor: factor)
            guard case .wrong(let ratio) = f.verdict else {
                return XCTFail("a stream at \(factor)x speed must be caught")
            }
            XCTAssertEqual(ratio, factor, accuracy: 0.01)
            XCTAssertFalse(f.isTrustworthy)
            XCTAssertEqual(f.integerRatio, Int(factor))
        }
    }

    /// The observed rates from the real recordings: 8000 Hz and 5333 Hz behind a
    /// 16 kHz declaration, which is what the *written file* looked like.
    func testTheRealObservedRatesReadBackCorrectly() {
        let twice = RateFidelity(declaredRate: 16_000, framesObserved: 8_000 * 60, elapsedSeconds: 60)
        XCTAssertEqual(twice.observedRate, 8_000, accuracy: 1)
        XCTAssertEqual(twice.integerRatio, 2)

        let thrice = RateFidelity(declaredRate: 16_000, framesObserved: 5_333 * 60, elapsedSeconds: 60)
        XCTAssertEqual(thrice.observedRate, 5_333, accuracy: 1)
        XCTAssertEqual(thrice.integerRatio, 3)
    }

    // MARK: - No false positives on real correct recordings

    /// The nine correct recordings on the author's machine measured 1.00–1.03.
    /// A check that fires on those is worse than no check, because it would refuse
    /// metadata on sound recordings and be switched off.
    func testTheRealCorrectRatiosAllPass() {
        for ratio in [1.00, 1.005, 1.01, 1.02, 1.03] {
            let f = RateFidelity(declaredRate: 48_000,
                                 framesObserved: (48_000 / ratio) * 60,
                                 elapsedSeconds: 60)
            XCTAssertEqual(f.verdict, .correct, "ratio \(ratio) is a correct recording")
            XCTAssertTrue(f.isTrustworthy)
            XCTAssertNil(f.explanation)
            XCTAssertNil(f.integerRatio)
        }
    }

    /// The tolerance sits in a factor-of-two gap with nothing in it. Asserted so
    /// that a future tightening has to confront the measurement.
    func testTheToleranceSitsInTheMeasuredGap() {
        XCTAssertGreaterThan(RateFidelity.tolerance, 0.03,
            "the correct recordings measured up to 1.03; the tolerance must clear them")
        XCTAssertLessThan(RateFidelity.tolerance, 1.0,
            "the closest failure measured 2.00; the tolerance must stay well under it")
    }

    // MARK: - Settling

    /// The first buffers arrive irregularly, so an early ratio is noise. A check
    /// that fires during startup is a check that fires on every recording.
    func testAStreamIsNeverJudgedWhileSettling() {
        let f = mislabelled(factor: 3, seconds: RateFidelity.settlingSeconds - 0.5)
        XCTAssertEqual(f.verdict, .settling, "too early to judge")
        // But at stop there is nothing left to settle, so it is judged.
        XCTAssertFalse(f.isTrustworthy)
    }

    /// A five-second Test Playground capture (FR-47) must still be checkable, or
    /// the Playground could never surface this class of failure at all.
    func testAShortCaptureIsStillJudgedAtStop() {
        let f = mislabelled(factor: 3, seconds: 5)
        guard case .wrong = f.finalVerdict else {
            return XCTFail("a five-second capture must still be judged at stop")
        }
    }

    func testNothingIsJudgedWithNoFramesOrNoRate() {
        XCTAssertEqual(RateFidelity.unknown.verdict, .settling)
        XCTAssertEqual(RateFidelity.unknown.finalVerdict, .settling)
        XCTAssertTrue(RateFidelity.unknown.isTrustworthy,
                      "never having checked is not evidence of a problem")
        let noFrames = RateFidelity(declaredRate: 48_000, framesObserved: 0, elapsedSeconds: 60)
        XCTAssertEqual(noFrames.verdict, .settling)
    }

    // MARK: - Repair refuses to guess

    /// A non-integer ratio is a different defect. Rounding it into this one would
    /// silently resample a recording on a guess.
    func testANonIntegerRatioIsNotRepairable() {
        let f = RateFidelity(declaredRate: 48_000,
                             framesObserved: (48_000 / 2.4) * 60, elapsedSeconds: 60)
        XCTAssertFalse(f.isTrustworthy, "2.4x is still wrong")
        XCTAssertNil(f.integerRatio, "but its true rate cannot be worked out")
    }

    /// The empirical figure reads low because the wall clock includes the moments
    /// before the first sample arrived. A true 8000 Hz measured as 7919 across a
    /// real 63-second recording, and the repair still has to land on 8000.
    func testTheWorstRealMeasurementStillSnapsToTheRightFactor() {
        let f = RateFidelity(declaredRate: 16_000, framesObserved: 499_754, elapsedSeconds: 63.1)
        XCTAssertEqual(f.observedRate, 7919, accuracy: 2)
        XCTAssertEqual(f.integerRatio, 2, "1.02% off a clean factor of 2 must still snap")
    }

    // MARK: - The sentence a person reads

    func testTheExplanationNamesBothRates() throws {
        let f = RateFidelity(declaredRate: 16_000, framesObserved: 5_333 * 60, elapsedSeconds: 60)
        let why = try XCTUnwrap(f.explanation)
        XCTAssertTrue(why.contains("5333"), why)
        XCTAssertTrue(why.contains("16000"), why)
        XCTAssertTrue(why.contains("faster"), why)
        XCTAssertFalse(why.lowercased().contains("error occurred"), "no generic wording")
    }

    func testACorrectStreamExplainsNothing() {
        XCTAssertNil(correct().explanation)
    }
}

/// AD-36 as amended — the two halves of capture evidence are independent, and a
/// stream can fail either one alone.
final class CaptureEvidenceCompletenessTests: XCTestCase {

    func testAStreamCanBeFullOfSignalAtTheWrongRate() {
        // Exactly the seven real recordings: plenty of signal, wrong rate.
        let signal = AudioEvidence(peak: 0.42, nonSilentSeconds: 500, duration: 520)
        let rate = RateFidelity(declaredRate: 16_000,
                                framesObserved: 5_333 * 520, elapsedSeconds: 520)
        XCTAssertTrue(signal.producedAudio, "this is why AD-36 alone passed all seven")
        XCTAssertFalse(rate.isTrustworthy, "and this is what catches them")
    }

    func testAStreamCanBeSilentAtTheRightRate() {
        // The increment-6 failure: a tap that ran and delivered digital silence.
        let signal = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 1920)
        let rate = RateFidelity(declaredRate: 48_000,
                                framesObserved: 48_000 * 1920, elapsedSeconds: 1920)
        XCTAssertFalse(signal.producedAudio)
        XCTAssertTrue(rate.isTrustworthy, "the rate was fine; there was simply nothing there")
    }

    /// Neither check subsumes the other, so a recording must pass both. Asserted
    /// as a matrix so a future simplification that drops one has to fail here.
    func testBothChecksAreRequired() {
        let good = AudioEvidence(peak: 0.4, nonSilentSeconds: 30, duration: 60)
        let bad = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 60)
        let rateOK = RateFidelity(declaredRate: 48_000, framesObserved: 48_000 * 60, elapsedSeconds: 60)
        let rateBad = RateFidelity(declaredRate: 48_000, framesObserved: 16_000 * 60, elapsedSeconds: 60)

        XCTAssertTrue(good.producedAudio && rateOK.isTrustworthy, "the only usable combination")
        XCTAssertFalse(good.producedAudio && rateBad.isTrustworthy)
        XCTAssertFalse(bad.producedAudio && rateOK.isTrustworthy)
        XCTAssertFalse(bad.producedAudio && rateBad.isTrustworthy)
    }
}

/// FR-85 / FR-86 — what the record says, and what the app refuses to derive.
final class UntrustworthyStreamTests: XCTestCase {

    private func meeting(mic: RateFidelity? = nil, system: RateFidelity? = nil) -> Meeting {
        var m = Meeting(id: "20260903-103103-y774", startedAt: Date())
        m.stage = .written
        m.duration = 1565
        m.micRate = mic
        m.systemRate = system
        m.utterances = [
            Utterance(start: 0, end: 4, text: "Mine.", speaker: .local, origin: .mic),
            Utterance(start: 4, end: 8, text: "Theirs.", speaker: .remote(0), origin: .system),
            Utterance(start: 8, end: 12, text: "Mine again.", speaker: .local, origin: .mic),
        ]
        return m
    }

    private var wrong: RateFidelity {
        RateFidelity(declaredRate: 16_000, framesObserved: 5_333 * 1565, elapsedSeconds: 1565)
    }
    private var right: RateFidelity {
        RateFidelity(declaredRate: 16_000, framesObserved: 16_000 * 1565, elapsedSeconds: 1565)
    }

    /// A record from before this check existed must not read as broken. Otherwise
    /// every meeting in the library — including the seven now repaired — would be
    /// flagged for ever.
    func testAnUncheckedRecordIsNotFlagged() {
        let m = meeting()
        XCTAssertTrue(m.untrustworthyStreams.isEmpty)
        XCTAssertTrue(m.mayDeriveMetadata)
        XCTAssertEqual(m.trustworthyUtterances.count, 3)
    }

    func testAFailedSystemStreamIsNamedAndItsSpeechIsExcludedFromMetadata() {
        let m = meeting(mic: right, system: wrong)
        XCTAssertEqual(m.untrustworthyStreams.map(\.stream), ["the far end of the call"])
        XCTAssertFalse(m.mayDeriveMetadata)
        // FR-86: the microphone's speech is still perfectly good input.
        XCTAssertEqual(m.trustworthyUtterances.map(\.text), ["Mine.", "Mine again."])
    }

    /// Per stream, because in all seven observed cases the microphone was correct.
    func testTrustIsPerStreamAndTheMicrophoneIsJudgedSeparately() {
        let m = meeting(mic: wrong, system: right)
        XCTAssertEqual(m.untrustworthyStreams.map(\.stream), ["your microphone"])
        XCTAssertEqual(m.trustworthyUtterances.map(\.text), ["Theirs."])
    }

    func testBothStreamsFailingLeavesNothingToDeriveFrom() {
        let m = meeting(mic: wrong, system: wrong)
        XCTAssertEqual(m.untrustworthyStreams.count, 2)
        XCTAssertTrue(m.trustworthyUtterances.isEmpty,
                      "and the pipeline then titles it by date, which is honest")
    }

    /// The Decodable-evolution convention: adding one field to `Meeting` once made
    /// every earlier record unreadable and dropped five real recordings from the UI.
    func testARecordWithoutTheNewFieldsStillDecodes() throws {
        let json = """
        {"id":"20260901-093248-evi3","startedAt":"2026-09-01T07:32:48Z","stage":"written"}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let m = try d.decode(Meeting.self, from: Data(json.utf8))
        XCTAssertNil(m.micRate)
        XCTAssertNil(m.systemRate)
        XCTAssertTrue(m.untrustworthyStreams.isEmpty)
    }

    /// FR-87: the Note carries it, because in six months the Note is all there is.
    func testTheNoteStatesTheProblemAndTheFrontmatterCarriesBothRates() {
        var m = meeting(mic: right, system: wrong)
        m.metadata = MeetingMetadata(title: "Anything", tags: [], summary: "",
                                     decisions: [], actionItems: [], backend: .heuristic)
        let out = NoteWriter().render(meeting: m)
        XCTAssertTrue(out.contains("not reliable"), out.prefix(600).description)
        XCTAssertTrue(out.contains("unreliable_streams:"))
        XCTAssertTrue(out.contains("system_declared_hz: 16000"))
        XCTAssertTrue(out.contains("system_observed_hz: 5333"))
        XCTAssertTrue(out.contains("No summary, title or tags were generated from it"))
    }

    /// And a sound recording's Note says nothing about rates at all — a field
    /// implying a problem the recording did not have is its own defect.
    func testASoundRecordingsNoteSaysNothingAboutRates() {
        var m = meeting(mic: right, system: right)
        m.metadata = MeetingMetadata(title: "Anything", tags: [], summary: "",
                                     decisions: [], actionItems: [], backend: .heuristic)
        let out = NoteWriter().render(meeting: m)
        XCTAssertFalse(out.contains("unreliable_streams"))
        XCTAssertFalse(out.contains("not reliable"))
    }
}
