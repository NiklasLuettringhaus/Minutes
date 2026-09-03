import XCTest
import AVFoundation
@testable import Minutes

/// AD-47 / AD-48 / AD-49 / FR-89 to FR-92 — was the microphone hearing the call?
///
/// Written against the **measured** figures rather than invented ones: the three
/// affected recordings sit at 24%, 61% and 63% frame share with offsets of
/// 140 ms, 50 ms and 920 ms, and the five comparable clean recordings sit at
/// 0–1%. The synthetic cases below reproduce both populations.
final class EchoTests: XCTestCase {

    // MARK: - The floors of FR-91, which no threshold may override

    func testSystemSilentIsNeverExcluded() {
        // 40% of mic activity on the worst real recording falls here. Even at a
        // correlation of 1.0 — which cannot happen against silence, but the
        // point is that the floor is checked first — nothing is excluded.
        let frames = [
            EchoAnalysis.Frame(micActive: true, systemActive: false, correlation: 1.0),
            EchoAnalysis.Frame(micActive: true, systemActive: false, correlation: 0.99),
        ]
        XCTAssertEqual(EchoAnalysis.classify(frames), [false, false])
    }

    func testConcurrentButUncorrelatedIsRetainedAsDoubleTalk() {
        // The user talking over the far end: 13% of mic activity on the worst
        // real recording, and the case FR-91 exists to protect.
        let frames = [
            EchoAnalysis.Frame(micActive: true, systemActive: true, correlation: 0.05),
            EchoAnalysis.Frame(micActive: true, systemActive: true, correlation: 0.29),
        ]
        XCTAssertEqual(EchoAnalysis.classify(frames), [false, false])
    }

    func testEchoDominatedIsExcluded() {
        let frames = [
            EchoAnalysis.Frame(micActive: true, systemActive: true, correlation: 0.30),
            EchoAnalysis.Frame(micActive: true, systemActive: true, correlation: 0.94),
        ]
        XCTAssertEqual(EchoAnalysis.classify(frames), [true, true])
    }

    func testSilentMicIsNotExcludedAndDoesNotCountAsActive() {
        let frames = [EchoAnalysis.Frame(micActive: false, systemActive: true, correlation: 0.9)]
        XCTAssertEqual(EchoAnalysis.classify(frames), [false])
        let analysis = EchoAnalysis.make(frames: frames, delaySeconds: 0.04, peakCorrelation: 0.9)
        XCTAssertEqual(analysis.micActiveSeconds, 0)
        XCTAssertEqual(analysis.verdict, .clean)
    }

    // MARK: - Intervals

    func testIntervalsMergeContiguousFrames() {
        let mask = [false, true, true, true, false, true, false]
        let runs = EchoAnalysis.intervals(from: mask, frameSeconds: 0.5)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].start, 0.5)
        XCTAssertEqual(runs[0].end, 2.0)
        XCTAssertEqual(runs[1].start, 2.5)
        XCTAssertEqual(runs[1].end, 3.0)
    }

    func testIntervalsCloseARunThatReachesTheEnd() {
        let runs = EchoAnalysis.intervals(from: [false, true, true], frameSeconds: 0.5)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].end, 1.5, "a run ending at the last frame must still be closed")
    }

    func testExcludedProportionUsesActiveAudioAsItsDenominator() {
        // Half the frames are silent; the proportion must be of *active* audio,
        // or a long silence would make any recording look clean.
        let frames = (0..<10).map { i in
            EchoAnalysis.Frame(micActive: i < 4, systemActive: i < 4,
                               correlation: i < 2 ? 0.9 : 0.0)
        }
        let analysis = EchoAnalysis.make(frames: frames, delaySeconds: 0.05, peakCorrelation: 0.9)
        XCTAssertEqual(analysis.micActiveSeconds, 2.0)
        XCTAssertEqual(analysis.excludedSeconds, 1.0)
        XCTAssertEqual(analysis.excludedProportion, 0.5, accuracy: 0.0001)
    }

    // MARK: - Verdicts stay honest

    func testUndeterminedIsNeverReadableAsClean() {
        XCTAssertEqual(EchoAnalysis.undetermined.verdict, .undetermined)
        XCTAssertFalse(EchoAnalysis.undetermined.excludedAnything)
        XCTAssertNotNil(EchoAnalysis.undetermined.explanation,
                        "undetermined must say so; silence would read as clean")
        XCTAssertNil(EchoAnalysis.clean(peak: 0.02).explanation,
                     "a clean recording has nothing to explain")
    }

    func testExplanationNamesTheProportionAndTheRemedy() {
        let frames = (0..<10).map { i in
            EchoAnalysis.Frame(micActive: true, systemActive: true,
                               correlation: i < 5 ? 0.9 : 0.0)
        }
        let analysis = EchoAnalysis.make(frames: frames, delaySeconds: 0.04, peakCorrelation: 0.9)
        let text = analysis.explanation ?? ""
        XCTAssertTrue(text.contains("50%"), "the user needs the size of it: \(text)")
        XCTAssertTrue(text.lowercased().contains("headphones"),
                      "an explanation the user cannot act on is half an explanation")
    }

    // MARK: - The Transcript rule needs both signals

    private func span(_ start: TimeInterval, _ end: TimeInterval, _ text: String)
        -> EchoDeduplication.Span {
        .init(start: start, end: end, text: text)
    }

    func testTextAloneNeverDropsAnything() {
        // The whole safety property. A verbatim duplicate that the audio test
        // did not flag must survive.
        let mic = [span(0, 2, "the invoice goes out on Friday")]
        let system = [span(0, 2, "the invoice goes out on Friday")]
        let outcome = EchoDeduplication.apply(mic: mic, system: system,
                                              echoFlagged: { _ in false })
        XCTAssertTrue(outcome.droppedIndices.isEmpty)
        XCTAssertEqual(outcome.residualDuplicateWords, 6,
                       "an unflagged duplicate is residual, not silently dropped")
    }

    func testEchoFlagAloneNeverDropsAnything() {
        // The other half. This is the 13%-cost case: the audio says echo, the
        // user actually spoke, and the text proves it was not a repeat.
        let mic = [span(0, 2, "can we push that to next week")]
        let system = [span(0, 2, "the invoice goes out on Friday")]
        let outcome = EchoDeduplication.apply(mic: mic, system: system,
                                              echoFlagged: { _ in true })
        XCTAssertTrue(outcome.droppedIndices.isEmpty)
        XCTAssertEqual(outcome.retainedWords, 7)
    }

    func testBothSignalsTogetherDrop() {
        let mic = [span(0, 2, "the invoice goes out on Friday")]
        let system = [span(0, 2, "The invoice goes out on Friday.")]
        let outcome = EchoDeduplication.apply(mic: mic, system: system,
                                              echoFlagged: { _ in true })
        XCTAssertEqual(outcome.droppedIndices, [0])
        XCTAssertEqual(outcome.droppedWords, 6)
        XCTAssertEqual(outcome.residualDuplicateWords, 0)
    }

    func testANonOverlappingRepeatIsNotADuplicate() {
        // Somebody in the room genuinely repeating what was said a minute ago.
        let mic = [span(100, 102, "the invoice goes out on Friday")]
        let system = [span(0, 2, "the invoice goes out on Friday")]
        let outcome = EchoDeduplication.apply(mic: mic, system: system,
                                              echoFlagged: { _ in true })
        XCTAssertTrue(outcome.droppedIndices.isEmpty)
    }

    func testSimilarityIsAMultisetSoRepetitionDoesNotScoreAsIdentity() {
        XCTAssertEqual(EchoDeduplication.similarity(["yeah", "yeah", "yeah"], ["yeah"]),
                       0.5, accuracy: 0.001)
        XCTAssertEqual(EchoDeduplication.similarity(["a", "b"], ["a", "b"]), 1.0)
        XCTAssertEqual(EchoDeduplication.similarity(["a"], ["b"]), 0.0)
    }

    func testTokensStripPunctuationAndCase() {
        XCTAssertEqual(EchoDeduplication.tokens("Well, that's — fine."),
                       ["well", "that", "s", "fine"])
    }

    // MARK: - Detection on synthetic audio

    /// Speech-like noise: bursts of energy separated by quiet.
    ///
    /// **The burst schedule is randomised per seed, and that matters.** The
    /// first version of this used a fixed 0.6 s burst and 0.3 s gap for every
    /// seed, so two "unrelated" streams fell silent at exactly the same
    /// instants. Centre such a pair frame by frame and the shared silences
    /// correlate strongly all on their own — the detector called them an echo,
    /// correctly, because the fixture had given them a common envelope. Two
    /// unrelated speakers do not take turns in lockstep, and neither do these
    /// now.
    private func speechLike(seconds: Double, rate: Double, seed: UInt64) -> [Float] {
        var state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bits = UInt32(truncatingIfNeeded: state >> 32)
            return Float(Int32(bitPattern: bits)) / Float(Int32.max)
        }
        let count = Int(seconds * rate)
        var out = [Float](repeating: 0, count: count)
        var i = 0
        while i < count {
            let burst = Int(rate * (0.25 + Double(abs(next())) * 0.9))
            let gap = Int(rate * (0.15 + Double(abs(next())) * 0.6))
            for j in i..<min(i + burst, count) { out[j] = next() * 0.4 }
            i += burst + gap
        }
        return out
    }

    func testDetectsADelayedAttenuatedCopy() {
        let rate = 16_000.0
        let system = speechLike(seconds: 90, rate: rate, seed: 7)
        let delaySamples = Int(0.040 * rate)     // 40 ms, as measured on the worst recording
        var mic = [Float](repeating: 0, count: system.count)
        for i in delaySamples..<system.count {
            mic[i] = system[i - delaySamples] * 0.5
        }
        let analysis = EchoDetector.analyse(
            .init(mic: mic, system: system, sampleRate: rate))
        XCTAssertEqual(analysis.verdict, .present)
        XCTAssertEqual(analysis.delaySeconds ?? -1, 0.040, accuracy: 0.025,
                       "the offset must be recovered to within the search grid")
        XCTAssertGreaterThan(analysis.excludedProportion, 0.5)
    }

    func testDoesNotFlagTwoUnrelatedStreams() {
        let rate = 16_000.0
        let analysis = EchoDetector.analyse(.init(
            mic: speechLike(seconds: 90, rate: rate, seed: 11),
            system: speechLike(seconds: 90, rate: rate, seed: 99),
            sampleRate: rate))
        XCTAssertEqual(analysis.verdict, .clean,
                       "two unrelated speakers are not an echo; the five clean "
                       + "real recordings measured 0-1% frame share")
        XCTAssertFalse(analysis.excludedAnything)
    }

    func testASilentSystemStreamCannotEcho() {
        let rate = 16_000.0
        let analysis = EchoDetector.analyse(.init(
            mic: speechLike(seconds: 90, rate: rate, seed: 3),
            system: [Float](repeating: 0, count: Int(90 * rate)),
            sampleRate: rate))
        XCTAssertEqual(analysis.verdict, .clean,
                       "nothing can be an echo of silence — and this is clean, "
                       + "not undetermined, because we looked")
    }

    func testTooShortToJudgeIsUndetermined() {
        let rate = 16_000.0
        let analysis = EchoDetector.analyse(.init(
            mic: speechLike(seconds: 10, rate: rate, seed: 5),
            system: speechLike(seconds: 10, rate: rate, seed: 5),
            sampleRate: rate))
        XCTAssertEqual(analysis.verdict, .undetermined)
    }

    func testMissingStreamIsNotApplicableRatherThanAFailure() throws {
        // FR-7's mic-only Session is a degradation, not a defect.
        let analysis = try EchoDetector.analyse(micURL: nil, systemURL: nil)
        XCTAssertEqual(analysis.verdict, .notApplicable)
        XCTAssertNil(analysis.explanation)
    }

    /// The offset the real library forced this design to accept.
    ///
    /// A 920 ms offset was twice dismissed as physically impossible before the
    /// streams turned out to start at different instants — measured length
    /// differences run from −364 ms to +3,278 ms. A search bounded by acoustics
    /// would have excluded the affected recording it was meant to protect.
    func testRecoversAnOffsetFarLargerThanAnyAcousticPath() {
        let rate = 16_000.0
        let system = speechLike(seconds: 120, rate: rate, seed: 13)
        let offset = Int(0.920 * rate)
        var mic = [Float](repeating: 0, count: system.count)
        for i in offset..<system.count { mic[i] = system[i - offset] * 0.6 }
        let analysis = EchoDetector.analyse(
            .init(mic: mic, system: system, sampleRate: rate))
        XCTAssertEqual(analysis.verdict, .present)
        XCTAssertEqual(analysis.delaySeconds ?? -1, 0.920, accuracy: 0.025)
    }

    // MARK: - The record

    func testAnalysisSurvivesACodableRoundTrip() throws {
        let frames = (0..<12).map { i in
            EchoAnalysis.Frame(micActive: true, systemActive: true,
                               correlation: i % 3 == 0 ? 0.8 : 0.1)
        }
        let original = EchoAnalysis.make(frames: frames, delaySeconds: 0.92,
                                         peakCorrelation: 0.8)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(EchoAnalysis.self, from: data), original)
    }

    func testAMeetingRecordedBeforeThisExistedReadsAsUnknown() throws {
        // AD-49. The same rule the rate work settled on: absent is "never
        // checked", never "passed".
        let json = """
        {"id":"abc","startedAt":\(Date().timeIntervalSinceReferenceDate)}
        """
        let meeting = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
        XCTAssertNil(meeting.echo, "absent must stay absent rather than defaulting to clean")
    }
}

private extension EchoAnalysis {
    static func clean(peak: Double) -> EchoAnalysis {
        EchoAnalysis(verdict: .clean, delaySeconds: 0, peakCorrelation: peak,
                     excludedIntervals: [], micActiveSeconds: 10, excludedSeconds: 0)
    }
}
