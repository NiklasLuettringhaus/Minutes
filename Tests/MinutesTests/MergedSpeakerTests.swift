import XCTest
@testable import Minutes

/// FR-24's merge, in the Speakers card as well as in the transcript.
///
/// **Reported by the user**, who renamed two speakers to the same name and
/// watched the transcript merge them while the card directly above it kept
/// listing both — under a sentence saying that renaming two speakers to the
/// same name merges them.
final class MergedSpeakerTests: XCTestCase {

    private func meeting(_ utterances: [(SpeakerLabelID, String)],
                         names: [String: String]) -> Meeting {
        var m = Meeting(id: "20260904-120000-merge", startedAt: Date())
        m.utterances = utterances.enumerated().map { i, u in
            Utterance(start: Double(i), end: Double(i) + 0.9, text: u.1,
                      speaker: u.0, origin: u.0.isRemote ? .system : .mic)
        }
        m.speakerNames = names
        return m
    }

    /// The exact shape reported: `local` and `room-unidentified`, both renamed to
    /// the same thing, plus one genuinely separate voice.
    func testTwoLabelsRenamedToOneNameAreOnePerson() {
        let m = meeting([(.local, "one two"), (.inRoom(1), "three"),
                         (.inRoomUnidentified, "four")],
                        names: ["local": "Me", "room-1": "Olivier",
                                "room-unidentified": "Me"])
        XCTAssertEqual(m.speakers.count, 3, "three Speaker Labels")
        let people = m.mergedSpeakers
        XCTAssertEqual(people.count, 2, "two people")
        XCTAssertEqual(people[0].name, "Me")
        XCTAssertEqual(people[0].labels.map(\.raw), ["local", "room-unidentified"])
        XCTAssertTrue(people[0].isMerged)
        XCTAssertEqual(people[1].name, "Olivier")
        XCTAssertFalse(people[1].isMerged)
    }

    /// The card and the transcript must agree, because they are the same
    /// question asked twice — and the reason the transcript was already right is
    /// that it used this rule.
    func testTheCardAndTheTranscriptUseTheSameRule() {
        let m = meeting([(.local, "one"), (.inRoomUnidentified, "two")],
                        names: ["local": "Me", "room-unidentified": "Me"])
        XCTAssertTrue(m.groups(.local, with: .inRoomUnidentified))
        XCTAssertEqual(m.mergedSpeakers.count, 1)
        // One paragraph in the transcript, one row in the card.
        XCTAssertEqual(m.transcriptBlocks().count, 1)
    }

    /// **What must not merge**, and it is the reason the rule is not "same
    /// display name". Two unnamed in-room voices both fall back to a generic
    /// label before attribution names them; running them together would present
    /// two people's alternating speech as one person's.
    func testTwoVoicesFallingBackToTheSameGenericLabelStaySeparate() {
        let m = meeting([(.inRoom(0), "one"), (.inRoom(1), "two")], names: [:])
        XCTAssertEqual(m.displayName(for: .inRoom(0)), m.displayName(for: .inRoom(1)),
                       "the fallback labels really are identical")
        XCTAssertEqual(m.mergedSpeakers.count, 2, "and they must still be two people")
    }

    /// The line count is the person's, not the primary label's.
    func testTheLineCountSumsOverEveryMergedLabel() {
        let m = meeting([(.local, "a"), (.local, "b"), (.inRoomUnidentified, "c")],
                        names: ["local": "Me", "room-unidentified": "Me"])
        let person = m.mergedSpeakers[0]
        let lines = person.labels.reduce(0) { total, label in
            total + m.utterances.filter { $0.speaker == label }.count
        }
        XCTAssertEqual(lines, 3)
    }

    /// Merging changes no Utterance, so it stays reversible by renaming one label
    /// back — which is what AD-19's stable IDs are for.
    func testAMergeIsReversibleBecauseNothingIsRewritten() {
        var m = meeting([(.local, "a"), (.inRoomUnidentified, "b")],
                        names: ["local": "Me", "room-unidentified": "Me"])
        XCTAssertEqual(m.mergedSpeakers.count, 1)
        XCTAssertEqual(m.utterances.map(\.speaker.raw), ["local", "room-unidentified"],
                       "the Utterances still point at their own labels")
        m.speakerNames["room-unidentified"] = "Someone else"
        XCTAssertEqual(m.mergedSpeakers.count, 2, "and renaming one back splits them")
    }
}
