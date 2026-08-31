import XCTest
@testable import Minutes

/// Regression cover for the bug that lost five real recordings from the UI.
///
/// `Meeting` relied on synthesised `Codable` and a comment asserting that
/// "defaults fill gaps so an older record still loads". Swift does not work that
/// way: a missing key throws `keyNotFound` regardless of the property's default.
/// Adding `multipleInRoom` therefore made every earlier `meeting.json` undecodable,
/// and `MeetingStore.loadAll`'s `try?` dropped them silently — the meetings stayed
/// on disk and vanished from the list.
final class MeetingCodableTests: XCTestCase {

    private func decode(_ json: String) throws -> Meeting {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(Meeting.self, from: Data(json.utf8))
    }

    /// The exact shape written before `multipleInRoom` existed.
    func testRecordWrittenBeforeMultipleInRoomStillLoads() throws {
        let m = try decode("""
        {
          "id": "20260831-134017-anb2",
          "startedAt": "2026-08-31T11:40:17Z",
          "duration": 31.4,
          "stage": "written",
          "systemStreamCaptured": true,
          "diarizationSucceeded": true,
          "speakerNames": {"local": "Me", "remote-0": "Speaker 2"},
          "inferredSpeakers": [],
          "utterances": [],
          "noteFilename": "2026-08-31 1340 Pricing-Page.md",
          "transcriptionModel": "openai_whisper-base"
        }
        """)
        XCTAssertEqual(m.id, "20260831-134017-anb2")
        XCTAssertEqual(m.stage, .written)
        XCTAssertFalse(m.multipleInRoom)
        XCTAssertEqual(m.noteFilename, "2026-08-31 1340 Pricing-Page.md")
        XCTAssertEqual(m.speakerNames["remote-0"], "Speaker 2")
    }

    /// Only identity is load-bearing; every other field must fall back rather than
    /// take the whole record down with it.
    func testMinimalRecordLoadsWithDefaults() throws {
        let m = try decode("""
        {"id": "x", "startedAt": "2026-08-31T11:40:17Z"}
        """)
        XCTAssertEqual(m.stage, .captured)
        XCTAssertEqual(m.duration, 0)
        XCTAssertFalse(m.systemStreamCaptured)
        XCTAssertFalse(m.diarizationSucceeded)
        XCTAssertFalse(m.multipleInRoom)
        XCTAssertEqual(m.speakerNames[SpeakerLabelID.local.raw], "Me")
        XCTAssertTrue(m.utterances.isEmpty)
        XCTAssertNil(m.metadata)
    }

    /// A field this build has never heard of must not be fatal either — the next
    /// schema change has to be survivable in both directions.
    func testUnknownFieldIsIgnored() throws {
        let m = try decode("""
        {"id": "x", "startedAt": "2026-08-31T11:40:17Z", "somethingFromTheFuture": 42}
        """)
        XCTAssertEqual(m.id, "x")
    }

    /// A record still missing identity is a genuinely broken file and must fail
    /// loudly rather than decode into a meeting with no id.
    func testMissingIdentityStillFails() {
        XCTAssertThrowsError(try decode(#"{"duration": 5}"#))
    }

    func testRoundTripPreservesEveryField() throws {
        var m = Meeting(id: "rt", startedAt: Date(timeIntervalSince1970: 1_770_000_000))
        m.stage = .metadata
        m.duration = 92.5
        m.multipleInRoom = true
        m.systemStreamCaptured = true
        m.diarizationSucceeded = true
        m.triggeringApp = "Microsoft Teams"
        m.transcriptionModel = "parakeet-tdt-0.6b-v3"
        m.speakerNames = ["local": "Me", "room-1": "In-room 1"]
        m.inferredSpeakers = ["local"]
        m.noteFilename = "note.md"

        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let back = try decode(String(decoding: try e.encode(m), as: UTF8.self))

        XCTAssertEqual(back.stage, .metadata)
        XCTAssertEqual(back.duration, 92.5)
        XCTAssertTrue(back.multipleInRoom)
        XCTAssertEqual(back.triggeringApp, "Microsoft Teams")
        XCTAssertEqual(back.transcriptionModel, "parakeet-tdt-0.6b-v3")
        XCTAssertEqual(back.speakerNames["room-1"], "In-room 1")
        XCTAssertEqual(back.inferredSpeakers, ["local"])
        XCTAssertEqual(back.noteFilename, "note.md")
    }
}
