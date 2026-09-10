import XCTest
@testable import Minutes

/// Story 16.7 / FR-23 as amended. **The invariant over the merged output**, not
/// a property assumed from the stage upstream of it.
///
/// The distinction is the whole story. `EchoDeduplication.apply` runs once,
/// inside transcription, and the property it is supposed to guarantee is about
/// the Transcript that ends up on the record — and everything between them can
/// regress without the stage's own tests noticing. Increment 9 shipped the rule
/// and left this test unwritten, which is why the story stayed in progress.
final class MergedTranscriptInvariantTests: XCTestCase {

    private func meeting(mic: [(TimeInterval, String)],
                         system: [(TimeInterval, String)],
                         duration: TimeInterval = 120) -> Meeting {
        var m = Meeting(id: "20260904-150000-inv", startedAt: Date())
        m.duration = duration
        m.utterances =
            mic.map { Utterance(start: $0.0, end: $0.0 + 4, text: $0.1,
                                speaker: .local, origin: .mic) }
            + system.map { Utterance(start: $0.0, end: $0.0 + 4, text: $0.1,
                                     speaker: SpeakerLabelID.remote(0), origin: .system) }
        m.utterances.sort { $0.start < $1.start }
        return m
    }

    /// A merged Transcript with the rule applied holds no whole duplicated
    /// Utterance. This is the invariant, checked on the finished article.
    func testNoMicUtteranceRepeatsATimeOverlappingSystemOne() throws {
        let m = meeting(
            mic: [(0, "so what did we decide about the pricing"),
                  (10, "yes I agree with that entirely")],
            system: [(20, "let me check the numbers before we commit")])
        let residual = try XCTUnwrap(m.duplicateResidual)
        XCTAssertEqual(residual.duplicateWords, 0)
        XCTAssertGreaterThan(residual.micWords, 0, "the check must have looked at something")
    }

    /// The stage regressing is exactly what this catches: here the rule did not
    /// run, and the same sentence sits on both Streams at the same instant.
    func testItCatchesADuplicateTheStageShouldHaveRemoved() throws {
        let m = meeting(
            mic: [(0, "let me check the numbers before we commit"),
                  (10, "yes I agree with that entirely")],
            system: [(0, "let me check the numbers before we commit")])
        let residual = try XCTUnwrap(m.duplicateResidual)
        XCTAssertEqual(residual.duplicateWords, 8)
        XCTAssertGreaterThan(residual.proportion, 0.5)
    }

    /// **It is not asserted to reach zero**, and a test that demanded zero would
    /// be asserting something the design does not deliver. A partial overlap —
    /// echo and a room voice inside one Utterance — survives the Utterance-level
    /// rule by construction, and is counted rather than hidden. Measured on the
    /// three affected recordings: 695, 493 and 244 words.
    func testAPartialOverlapSurvivesAndIsCountedRatherThanHidden() throws {
        let m = meeting(
            // The far end's sentence with a room voice's words wrapped around it,
            // which is what a partial overlap is.
            mic: [(0, "hang on let me check the numbers before we commit yes fine")],
            system: [(0, "let me check the numbers before we commit")])
        let residual = try XCTUnwrap(m.duplicateResidual)
        XCTAssertGreaterThan(residual.duplicateWords, 0,
                             "the partial overlap is still there and must be reported")
        XCTAssertEqual(residual.micWords, 12)
    }

    /// The question does not arise on a Session with one Stream (FR-7), and the
    /// answer is absent rather than a reassuring zero.
    func testAMicOnlyMeetingHasNoResidualRatherThanAZeroOne() {
        let m = meeting(mic: [(0, "just me talking to myself")], system: [])
        XCTAssertNil(m.duplicateResidual)
    }

    /// The word-rate sanity signal, available without any reference to the audio.
    /// Measured on the library: 226 and 270 words per minute on the two severely
    /// affected recordings against a median of 148, and natural speech is
    /// 110–160.
    func testAnImpossibleWordRateIsVisibleFromTheTranscriptAlone() throws {
        // 60 words in 30 seconds is 120 wpm — ordinary.
        let ordinary = meeting(
            mic: [(0, Array(repeating: "word", count: 60).joined(separator: " "))],
            system: [], duration: 30)
        XCTAssertEqual(try XCTUnwrap(ordinary.wordsPerMinute), 120, accuracy: 1)

        // The same speech counted twice reads at twice the rate.
        let doubled = meeting(
            mic: [(0, Array(repeating: "word", count: 60).joined(separator: " "))],
            system: [(0, Array(repeating: "word", count: 60).joined(separator: " "))],
            duration: 30)
        XCTAssertEqual(try XCTUnwrap(doubled.wordsPerMinute), 240, accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(doubled.wordsPerMinute), 160,
                             "faster than anybody speaks, which is the signal")
    }

    /// The offset FR-97 measures is applied before the comparison, or the very
    /// recordings this exists for are compared at the wrong instants.
    func testTheComparisonHonoursTheMeasuredStreamOffset() {
        let mic = [EchoDeduplication.Span(start: 5, end: 9,
                                          text: "let me check the numbers first")]
        let system = [EchoDeduplication.Span(start: 0, end: 4,
                                             text: "let me check the numbers first")]
        // Unshifted, the two spans do not overlap and the duplicate is invisible.
        XCTAssertEqual(EchoDeduplication.residual(mic: mic, system: system).duplicateWords, 0)
        // Shifted by the measured five seconds, it is found.
        XCTAssertEqual(EchoDeduplication.residual(mic: mic, system: system,
                                                  offset: 5).duplicateWords, 6)
    }
}
