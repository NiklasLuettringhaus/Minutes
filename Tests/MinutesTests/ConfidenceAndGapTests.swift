import XCTest
@testable import Minutes

/// FR-95, FR-96 / AD-52. Confidence and gaps as part of the transcription
/// contract, and **absent meaning unknown** in both.
final class ConfidenceAndGapTests: XCTestCase {

    private func utterance(_ text: String, _ confidence: Double?,
                           start: TimeInterval = 0) -> Utterance {
        Utterance(start: start, end: start + 1, text: text,
                  speaker: .local, origin: .mic, confidence: confidence)
    }

    // MARK: - Confidence

    /// **The assertion that matters most.** An engine reporting nothing must not
    /// be indistinguishable from an engine reporting zero — one is "we do not
    /// know" and the other is "we are certain this is wrong".
    func testNoConfidenceReportedIsAbsentAndNotZero() {
        var m = Meeting(id: "20260904-000000-none", startedAt: Date())
        m.utterances = [utterance("a b c", nil), utterance("d e f", nil)]
        XCTAssertNil(m.transcriptConfidence, "nothing reported is not a low score")

        var zeros = Meeting(id: "20260904-000000-zero", startedAt: Date())
        zeros.utterances = [utterance("a b c", 0)]
        XCTAssertEqual(zeros.transcriptConfidence?.mean, 0,
                       "and zero, where an engine really says it, survives")
    }

    /// A doubtful Meeting is distinguishable from a confident one without
    /// re-running transcription (FR-95).
    func testTwoMeetingsAreComparableFromTheRecordAlone() {
        var good = Meeting(id: "20260904-000000-good", startedAt: Date())
        good.utterances = [utterance("a b c", 0.9), utterance("d e f", 0.85)]
        var bad = Meeting(id: "20260904-000000-bad", startedAt: Date())
        bad.utterances = [utterance("a b c", 0.2), utterance("d e f", 0.15)]
        XCTAssertGreaterThan(good.transcriptConfidence!.mean, bad.transcriptConfidence!.mean)
    }

    /// Weighted by words, because a two-word interjection and a long explanation
    /// are not equal evidence — the same error AD-50 forbids in the harness.
    func testTheMeanIsWeightedByWordsRatherThanByUtterance() {
        var m = Meeting(id: "20260904-000000-w", startedAt: Date())
        m.utterances = [utterance("yeah", 0.1),
                        utterance("one two three four five six seven eight nine", 0.9)]
        let c = m.transcriptConfidence!
        XCTAssertGreaterThan(c.mean, 0.8, "the long utterance dominates, as it should")
        XCTAssertEqual(c.coverage, 1.0, accuracy: 0.001)
    }

    /// A partly-scored transcript says how much of itself the figure covers.
    func testCoverageIsReportedSoTheFigureIsNotOverRead() {
        var m = Meeting(id: "20260904-000000-part", startedAt: Date())
        m.utterances = [utterance("a b", 0.9), utterance("c d e f g h", nil)]
        let c = m.transcriptConfidence!
        XCTAssertEqual(c.wordsScored, 2)
        XCTAssertEqual(c.wordsTotal, 8)
        XCTAssertEqual(c.coverage, 0.25, accuracy: 0.001)
    }

    /// A log-probability becomes a 0...1 figure, and an engine that gives none
    /// gives none.
    func testWhisperLogProbabilitiesBecomeConfidences() throws {
        XCTAssertEqual(try XCTUnwrap(WhisperKitTranscriber.confidence(0)), 1.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(WhisperKitTranscriber.confidence(-0.7)), 0.4966,
                       accuracy: 0.001)
        XCTAssertNil(WhisperKitTranscriber.confidence(.nan), "not a number is not a confidence")
        XCTAssertNil(WhisperKitTranscriber.confidence(1), "a positive log-probability is nonsense")
    }

    /// A record from before increment 10 loads, and its Utterances read as
    /// unknown rather than as zero.
    func testAnOlderUtteranceDecodesWithoutAConfidence() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","start":0,"end":1,"text":"hello there","speaker":{"raw":"local"},"origin":"mic"}"#
        let u = try JSONDecoder().decode(Utterance.self, from: Data(json.utf8))
        XCTAssertNil(u.confidence)
        XCTAssertEqual(u.text, "hello there")
    }

    // MARK: - Gaps

    /// Signal with nothing transcribed over it is speech the app failed on.
    func testActiveAudioWithNoUtteranceIsAGap() {
        // 20 frames of 0.5 s: 10 s. Active throughout, covered only for the first 4 s.
        let active = [Bool](repeating: true, count: 20)
        let gaps = TranscriptGaps.find(active: active, frameSeconds: 0.5,
                                       covered: [0...4], stream: .mic)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].start, 4.5, accuracy: 0.001)
        XCTAssertEqual(gaps[0].end, 10, accuracy: 0.001)
        XCTAssertEqual(gaps[0].stream, .mic)
    }

    /// **A gap is not silence.** Nothing was said, so nothing was missed.
    func testSilenceIsNotAGap() {
        let active = [Bool](repeating: false, count: 20)
        XCTAssertTrue(TranscriptGaps.find(active: active, frameSeconds: 0.5,
                                          covered: [], stream: .mic).isEmpty)
    }

    /// **Echo-excluded audio is not a gap** (FR-96). It is speech Minutes has,
    /// once, on the other Stream. Reporting it as unreadable would present a
    /// working feature as a failure — 45% of the microphone on the worst real
    /// recording.
    func testEchoExclusionProducesNoGaps() {
        let active = [Bool](repeating: true, count: 40)
        let withoutExclusion = TranscriptGaps.find(active: active, frameSeconds: 0.5,
                                                   covered: [0...4], stream: .mic)
        XCTAssertFalse(withoutExclusion.isEmpty, "the control: this would be a gap")

        let withExclusion = TranscriptGaps.find(active: active, frameSeconds: 0.5,
                                                covered: [0...4], excluded: [4...20],
                                                stream: .mic)
        XCTAssertTrue(withExclusion.isEmpty,
                      "excluded echo must not be reported as speech the app lost")
    }

    /// Short uncovered tails are not worth a mark. An Utterance boundary
    /// routinely leaves one, and dozens of meaningless marks teach a reader to
    /// ignore the one that matters.
    func testAShortUncoveredTailIsNotWorthReporting() {
        let active = [Bool](repeating: true, count: 10)   // 5 s
        let gaps = TranscriptGaps.find(active: active, frameSeconds: 0.5,
                                       covered: [0...4], stream: .mic)
        XCTAssertTrue(gaps.isEmpty, "1 s uncovered is below the 2 s floor")
    }

    /// A mostly-silent stretch is a pause with noise in it, not a failure.
    func testAMostlySilentIntervalIsNotAGap() {
        var active = [Bool](repeating: false, count: 20)
        active[3] = true; active[9] = true
        XCTAssertTrue(TranscriptGaps.find(active: active, frameSeconds: 0.5,
                                          covered: [], stream: .mic).isEmpty)
    }

    /// The sentence a reader gets, and the silence where there is nothing to say.
    func testTheExplanationNamesTheAmountAndThePlaces() throws {
        XCTAssertNil(TranscriptGaps.explanation([]))
        let gaps = [TranscriptGap(start: 10, end: 40, stream: .mic),
                    TranscriptGap(start: 100, end: 130, stream: .system)]
        let why = try XCTUnwrap(TranscriptGaps.explanation(gaps))
        XCTAssertTrue(why.contains("60 seconds"), why)
        XCTAssertTrue(why.contains("2 places"), why)
        XCTAssertTrue(why.contains("missing from the transcript"), why)
    }

    /// Gaps survive the record, and a Meeting from before has none because nobody
    /// looked — not because there were none.
    func testGapsRoundTripAndAreAbsentOnOlderRecords() throws {
        var m = Meeting(id: "20260904-000000-gap", startedAt: Date())
        m.gaps = [TranscriptGap(start: 5, end: 12, stream: .system)]
        let back = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.gaps, m.gaps)

        let old = #"{"id":"20260101-000000-old","startedAt":0}"#
        let older = try JSONDecoder().decode(Meeting.self, from: Data(old.utf8))
        XCTAssertTrue(older.gaps.isEmpty)
        XCTAssertNil(older.transcriptConfidence)
    }
}
