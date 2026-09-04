import XCTest
@testable import Minutes

/// FR-100 / AD-56. Ruling a voice out of the room by comparison, never by
/// removing audio.
final class RoomVoicesTests: XCTestCase {

    private let producer = "test-embedder"

    /// A deterministic 8-dimensional vector, `angle` radians away from the first
    /// axis. Cosine distance between two of these is a known quantity, so a
    /// threshold can be asserted rather than eyeballed.
    private func voice(_ angle: Float) -> [Float] {
        [cos(angle), sin(angle), 0, 0, 0, 0, 0, 0]
    }

    func testAMicClusterMatchingTheFarEndIsRuledOut() {
        let outcome = RoomVoices.classify(
            mic: [0: voice(0), 1: voice(1.2)],
            system: [0: voice(0.01)],
            producer: producer, threshold: 0.35)
        XCTAssertEqual(outcome.excluded, [0])
        XCTAssertEqual(outcome.inRoom, [1])
        XCTAssertEqual(outcome.inRoomCount, 1)
    }

    /// **The direction of the change is the assertion.** Assuming it is exactly
    /// what went wrong with the previous approach, which was built, committed and
    /// described before anyone counted the speakers — and had made them worse.
    func testTheCountFallsRatherThanRises() {
        let mic = [0: voice(0), 1: voice(0.02), 2: voice(1.5), 3: voice(2.2)]
        let outcome = RoomVoices.classify(
            mic: mic, system: [0: voice(0.01), 1: voice(0.03)],
            producer: producer, threshold: 0.35)
        XCTAssertLessThan(outcome.inRoomCount, mic.count,
                          "ruling voices out must reduce the room, never enlarge it")
        XCTAssertLessThanOrEqual(outcome.inRoomCount, mic.count)
    }

    /// No far end, nothing to rule out. This is every mic-only Session (FR-7).
    func testWithNoFarEndNothingIsExcluded() {
        let outcome = RoomVoices.classify(
            mic: [0: voice(0), 1: voice(1.0)], system: [:],
            producer: producer, threshold: 0.35)
        XCTAssertTrue(outcome.excluded.isEmpty)
        XCTAssertEqual(outcome.inRoomCount, 2)
        XCTAssertNil(outcome.closest, "no comparison was possible, so there is no distance")
    }

    /// One voice on the microphone is the user by construction (AD-11). Even a
    /// perfect match to the far end cannot empty the room — if it matched, the
    /// comparison is what is wrong.
    func testASingleMicVoiceIsNeverRuledOut() throws {
        let outcome = RoomVoices.classify(
            mic: [0: voice(0)], system: [0: voice(0)],
            producer: producer, threshold: 0.35)
        XCTAssertTrue(outcome.excluded.isEmpty)
        XCTAssertEqual(outcome.inRoomCount, 1)
        XCTAssertEqual(try XCTUnwrap(outcome.closest), 0, accuracy: 0.001,
                       "and the distance is still reported")
    }

    /// The room is never emptied. If every cluster looks like the far end the
    /// comparison has failed, not the meeting.
    func testTheRoomIsNeverEmptied() {
        let outcome = RoomVoices.classify(
            mic: [0: voice(0), 1: voice(0.02), 2: voice(0.04)],
            system: [0: voice(0.01)],
            producer: producer, threshold: 0.9)
        XCTAssertEqual(outcome.inRoomCount, 1,
                       "the cluster least like the far end stays")
        XCTAssertEqual(outcome.excluded.count, 2)
    }

    /// AD-29: a fingerprint from another embedder is **not comparable**, which is
    /// not the same as far away. Treating it as far away would silently stop the
    /// rule ever firing; treating it as near would empty the room.
    func testAnIncomparableFingerprintIsNotAMatch() {
        let outcome = RoomVoices.classify(
            mic: [0: voice(0), 1: voice(1.0)],
            system: [0: voice(0)],
            producer: producer, threshold: 0.35)
        XCTAssertEqual(outcome.excluded, [0])

        // Same vectors, different producers on each side is impossible through
        // this API by construction — one producer is passed for both — which is
        // itself the guard. What can still happen is an empty vector.
        let empty = RoomVoices.classify(
            mic: [0: [], 1: voice(1.0)], system: [0: voice(0)],
            producer: producer, threshold: 0.35)
        XCTAssertTrue(empty.excluded.isEmpty, "an unusable vector is not a match")
        XCTAssertNil(empty.matches.first { $0.micCluster == 0 }?.distance)
    }

    /// The reporting shape AD-56 requires: distances come out even when nothing
    /// is excluded, because that is what a threshold has to be set from.
    func testDistancesAreReportedWhateverTheThreshold() {
        let outcome = RoomVoices.classify(
            mic: [0: voice(0), 1: voice(1.4)], system: [0: voice(0.01)],
            producer: producer, threshold: 0.0)
        XCTAssertTrue(outcome.excluded.isEmpty, "nothing clears a zero threshold")
        XCTAssertNotNil(outcome.closest)
        XCTAssertNotNil(outcome.furthest)
        XCTAssertLessThan(outcome.closest!, outcome.furthest!)
    }
}
