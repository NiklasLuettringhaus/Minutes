import XCTest
@testable import Minutes

/// FR-77 / AD-39 / AD-9 as amended — a Note says which Meeting it is, and that is
/// the *only* thing the app reads out of it.
final class NoteIdentityTests: XCTestCase {

    private func meeting(id: String = "20260903-093038-zzzz",
                         at iso: String = "2026-09-03T07:30:38Z") -> Meeting {
        Meeting(id: id, startedAt: ISO8601DateFormatter().date(from: iso)!)
    }

    private let stamped = """
    ---
    title: "Anything"
    minutes_id: 20260903-093038-zzzz
    date: 2026-09-03
    started_at: 2026-09-03T07:30:38Z
    generated_by: Minutes (local, on-device)
    ---

    ## Transcript

    **00:10 Me**

    Words that must never be read by anything.
    """

    func testReadsTheIdentityAndMatchesItsMeeting() throws {
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: stamped))
        XCTAssertEqual(i.meetingID, "20260903-093038-zzzz")
        XCTAssertTrue(i.writtenByMinutes)
        XCTAssertTrue(i.isMinutesNote)
        XCTAssertTrue(i.matches(meeting()))
    }

    /// The ID decides on its own. A Note whose start time matches but whose ID does
    /// not is *not* that Meeting's Note — otherwise a copied file would be claimed.
    func testTheIDDecidesAndTheTimestampDoesNotOverrideIt() throws {
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: stamped))
        let sameTimeDifferentMeeting = meeting(id: "20260903-093038-aaaa")
        XCTAssertFalse(i.matches(sameTimeDifferentMeeting))
    }

    /// The fallback for every Note written before increment 7. Measured on the real
    /// folder: all fifteen carry `started_at`, and none carries an ID.
    func testFallsBackToTheStartTimeWhenThereIsNoID() throws {
        let legacy = """
        ---
        title: "Anything"
        started_at: 2026-09-03T07:30:38Z
        generated_by: Minutes (local, on-device)
        ---
        """
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: legacy))
        XCTAssertNil(i.meetingID)
        XCTAssertTrue(i.isMinutesNote)
        XCTAssertTrue(i.matches(meeting()))
    }

    /// The frontmatter's ISO string is second-precision; `Meeting.startedAt` is not.
    /// Without the tolerance every pre-stamp Note fails to match its own Meeting.
    func testTheStartTimeToleranceIsOneSecond() throws {
        let legacy = """
        ---
        started_at: 2026-09-03T07:30:38Z
        generated_by: Minutes
        ---
        """
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: legacy))
        let base = ISO8601DateFormatter().date(from: "2026-09-03T07:30:38Z")!

        var withinTolerance = Meeting(id: "x", startedAt: base.addingTimeInterval(0.812))
        XCTAssertTrue(i.matches(withinTolerance), "sub-second precision must still match")

        withinTolerance = Meeting(id: "x", startedAt: base.addingTimeInterval(4))
        XCTAssertFalse(i.matches(withinTolerance), "four seconds apart is a different meeting")
    }

    /// AD-43. A Markdown file the user wrote is not the app's to claim.
    func testAFileMinutesDidNotWriteIsNeverClaimed() throws {
        let theirs = """
        ---
        title: My own notes
        tags: [personal]
        ---

        started_at: 2026-09-03T07:30:38Z
        """
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: theirs))
        XCTAssertFalse(i.isMinutesNote, "no ID and no generated_by means not ours")
        XCTAssertFalse(i.matches(meeting()))
        XCTAssertNil(i.startedAt, "a key below the closing --- is not frontmatter")
    }

    func testRejectsAFileThatDoesNotOpenWithFrontmatter() {
        XCTAssertNil(NoteIdentity.parse(frontmatterOf: "# Just a heading\n\nminutes_id: x\n"))
        XCTAssertNil(NoteIdentity.parse(frontmatterOf: ""))
    }

    /// Without this a long prose file whose first line happens to be `---` would be
    /// read as a header, and any `minutes_id:` line anywhere in it would be
    /// believed.
    func testRejectsAnUnterminatedBlock() {
        let unterminated = "---\nminutes_id: 20260903-093038-zzzz\ntitle: no closing rule\n"
        XCTAssertNil(NoteIdentity.parse(frontmatterOf: unterminated))
    }

    func testUnquotesAndSurvivesAwkwardScalars() throws {
        let s = """
        ---
        title: "A title: with a colon and a \\"quote\\""
        minutes_id: 20260903-093038-zzzz
        generated_by: Minutes (local, on-device)
        started_at: 2026-09-03T07:30:38Z
        ---
        """
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: s))
        XCTAssertEqual(i.meetingID, "20260903-093038-zzzz")
        XCTAssertNotNil(i.startedAt)
    }

    /// The head budget is a measured figure, not a guess. If a future frontmatter
    /// field pushes a real Note past it, identity reads stop working silently — so
    /// the margin is asserted rather than trusted.
    func testTheHeadBudgetHasRoomOverTheLongestRealFrontmatter() {
        XCTAssertGreaterThan(NoteIdentity.headBytes, 753 * 4,
            "753 bytes is the longest of the fifteen real notes; keep multiples of headroom")
    }

    /// AD-9 as amended, enforced by the type. This does not compile if someone adds
    /// a content field, which is the point — the identity reader must stay unable
    /// to carry a title, a summary or an utterance.
    func testTheTypeCannotCarryContent() throws {
        let i = try XCTUnwrap(NoteIdentity.parse(frontmatterOf: stamped))
        let mirror = Mirror(reflecting: i)
        XCTAssertEqual(Set(mirror.children.compactMap(\.label)),
                       ["meetingID", "startedAt", "writtenByMinutes"],
                       "NoteIdentity gained a field. If it holds note *content*, AD-9 is broken.")
    }
}

/// The stamp itself, and the promise that no existing file is touched to add it.
final class NoteStampTests: XCTestCase {

    func testTheRenderedNoteCarriesItsMeetingID() {
        var m = Meeting(id: "20260903-093038-zzzz",
                        startedAt: ISO8601DateFormatter().date(from: "2026-09-03T07:30:38Z")!)
        m.stage = .written
        m.metadata = MeetingMetadata(title: "Anything", tags: [], summary: "",
                                     decisions: [], actionItems: [], backend: .heuristic)
        let out = NoteWriter().render(meeting: m)
        XCTAssertTrue(out.contains("minutes_id: 20260903-093038-zzzz"))

        // And the round trip: what the writer wrote, the reader identifies.
        let identity = NoteIdentity.parse(frontmatterOf: out)
        XCTAssertEqual(identity?.meetingID, m.id)
        XCTAssertTrue(identity?.matches(m) ?? false)
    }
}
