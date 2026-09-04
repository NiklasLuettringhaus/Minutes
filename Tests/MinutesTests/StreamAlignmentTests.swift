import XCTest
@testable import Minutes

/// FR-97 / AD-53. The two Streams did not start at the same instant, and FR-6
/// had been claiming for nine increments that they did.
final class StreamAlignmentTests: XCTestCase {

    /// The real measured spread across the author's library, in seconds. These
    /// are file-length differences, which is the only evidence available for
    /// recordings made before capture recorded the offset — the point they make
    /// is the size of the error, not the exact value the new measurement gives.
    private let measuredSpread: [TimeInterval] = [-0.364, -0.078, -0.069, 0.868, 2.372, 3.278]

    /// The requirement as a test rather than an assertion. It fails, and that is
    /// the finding.
    func testFR6sHundredMillisecondClaimFailsOnRealRecordings() {
        let failures = measuredSpread.filter {
            StreamAlignment.capturesAreAligned(offset: $0) == false
        }
        XCTAssertEqual(failures.count, 4,
                       "four of the six measured offsets exceed the ±100 ms FR-6 claims — "
                       + "and the fourth is the −364 ms one, which the first draft of this "
                       + "test forgot because it read the spread as three large positives")
        XCTAssertEqual(StreamAlignment.capturesAreAligned(offset: 3.278), false)
        XCTAssertEqual(StreamAlignment.capturesAreAligned(offset: 0.069), true)
    }

    /// The whole reason the offset is measured: an Utterance's position must
    /// reflect when it was said.
    func testASystemUtteranceIsPlacedOnTheMicClock() {
        // The far end said something 10 s into system.wav; the system capture
        // started 3.278 s after the microphone's, so it happened 13.278 s into
        // the Session.
        XCTAssertEqual(StreamAlignment.micTime(ofSystemTime: 10, offset: 3.278),
                       13.278, accuracy: 0.0001)
    }

    /// **A Meeting recorded before this existed is not re-ordered by a guess.**
    /// Unknown is not zero on the record, and yet unknown changes nothing here —
    /// those are the same decision, not two.
    func testAnUnknownOffsetLeavesEveryTimeAlone() {
        for t in [0.0, 1.5, 3_600.0] {
            XCTAssertEqual(StreamAlignment.micTime(ofSystemTime: t, offset: nil), t)
        }
        XCTAssertNil(StreamAlignment.capturesAreAligned(offset: nil),
                     "never measured is not the same answer as aligned")
        XCTAssertNil(StreamAlignment.explanation(offset: nil))
    }

    /// An offset inside the claim is not worth a sentence.
    func testAnAlignedCaptureSaysNothing() {
        XCTAssertNil(StreamAlignment.explanation(offset: 0.05))
        XCTAssertNotNil(StreamAlignment.explanation(offset: 0.868))
    }

    /// A Meeting round-trips the offset, and one written before it existed reads
    /// as unknown rather than as zero.
    func testTheOffsetSurvivesTheRecordAndAbsenceMeansUnknown() throws {
        var m = Meeting(id: "20260904-120000-test", startedAt: Date())
        m.streamStartOffset = 0.868
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(Meeting.self, from: data)
        XCTAssertEqual(back.streamStartOffset, 0.868)

        let old = #"{"id":"20260101-000000-old","startedAt":0}"#
        let older = try JSONDecoder().decode(Meeting.self, from: Data(old.utf8))
        XCTAssertNil(older.streamStartOffset)
        XCTAssertNil(older.micContinuity)
    }
}
