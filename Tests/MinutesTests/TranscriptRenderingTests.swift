import XCTest
@testable import Minutes

/// The transcript grouping, after it moved out of the view body.
///
/// Two properties matter and neither was testable while the grouping lived inside
/// `MeetingDetail`: that block identities are **stable across calls**, and that
/// the revision token changes exactly when the rendered output would.
final class TranscriptRenderingTests: XCTestCase {

    private func meeting(utterances: Int, speakers: Int = 3) -> Meeting {
        var m = Meeting(id: "t", startedAt: Date())
        m.multipleInRoom = speakers > 1
        var us: [Utterance] = []
        for i in 0..<utterances {
            let label: SpeakerLabelID = speakers == 1
                ? .local
                : (i % speakers == 0 ? .local : .inRoom(i % speakers))
            us.append(Utterance(start: Double(i) * 2, end: Double(i) * 2 + 1.5,
                                text: "line \(i)", speaker: label, origin: .mic))
        }
        m.utterances = us
        m.speakerNames = [SpeakerLabelID.local.raw: "Me"]
        return m
    }

    /// The defect that caused the lag: the old builder minted a fresh `UUID` per
    /// block per call, so `ForEach` saw a completely new identity set on every
    /// body evaluation and rebuilt every row instead of diffing.
    func testBlockIdentitiesAreStableAcrossCalls() {
        let m = meeting(utterances: 300)
        let a = m.transcriptBlocks()
        let b = m.transcriptBlocks()
        XCTAssertEqual(a.map(\.id), b.map(\.id),
                       "identities must not change between calls, or ForEach cannot diff")
        XCTAssertEqual(a, b, "and the whole block list must be equal")
        XCTAssertFalse(a.isEmpty)
    }

    /// Each block's id is its first utterance's id, so it survives a rename — the
    /// rows keep their identity when only the label text changes.
    func testIdentitiesSurviveARename() {
        var m = meeting(utterances: 60)
        // Named, as a completed Meeting always is after attribution.
        m.speakerNames[SpeakerLabelID.inRoom(1).raw] = "In-room 1"
        m.speakerNames[SpeakerLabelID.inRoom(2).raw] = "In-room 2"
        let before = m.transcriptBlocks()
        m.speakerNames[SpeakerLabelID.inRoom(1).raw] = "Mikkel"
        let after = m.transcriptBlocks()
        XCTAssertEqual(before.map(\.id), after.map(\.id),
                       "a rename changes labels, not block identities")
        XCTAssertNotEqual(before.map(\.name), after.map(\.name), "the label did change")
    }

    /// Found by the test above failing. Grouping on the display name alone ran two
    /// different unnamed in-room voices together into one paragraph under one
    /// label, presenting two people's alternating speech as one person's.
    func testTwoUnnamedSpeakersAreNotMergedByTheirFallbackLabel() {
        var m = Meeting(id: "u", startedAt: Date())
        m.multipleInRoom = true
        m.speakerNames = [:]
        m.utterances = [
            Utterance(start: 0, end: 1, text: "mine", speaker: .inRoom(0), origin: .mic),
            Utterance(start: 1, end: 2, text: "theirs", speaker: .inRoom(1), origin: .mic),
        ]
        // Both fall back to the same generic label…
        XCTAssertEqual(m.displayName(for: .inRoom(0)), m.displayName(for: .inRoom(1)))
        // …and must still be two paragraphs.
        let b = m.transcriptBlocks()
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b.map(\.text), ["mine", "theirs"])
    }

    /// The case that *should* merge: FR-24's fix for one person split in two.
    func testTwoLabelsRenamedToTheSameNameAreMerged() {
        var m = Meeting(id: "m", startedAt: Date())
        m.multipleInRoom = true
        m.speakerNames = [SpeakerLabelID.inRoom(0).raw: "Mikkel",
                          SpeakerLabelID.inRoom(1).raw: "Mikkel"]
        m.utterances = [
            Utterance(start: 0, end: 1, text: "first half", speaker: .inRoom(0), origin: .mic),
            Utterance(start: 1, end: 2, text: "second half", speaker: .inRoom(1), origin: .mic),
        ]
        let b = m.transcriptBlocks()
        XCTAssertEqual(b.count, 1, "renaming two labels to one name merges them (FR-24)")
        XCTAssertEqual(b[0].text, "first half second half")
    }

    func testConsecutiveUtterancesFromOneSpeakerAreGrouped() {
        var m = Meeting(id: "g", startedAt: Date())
        m.utterances = [
            Utterance(start: 0, end: 1, text: "one", speaker: .local, origin: .mic),
            Utterance(start: 1, end: 2, text: "two", speaker: .local, origin: .mic),
            Utterance(start: 2, end: 3, text: "three", speaker: .remote(0), origin: .system),
        ]
        m.speakerNames = [SpeakerLabelID.local.raw: "Me",
                          SpeakerLabelID.remote(0).raw: "Speaker 1"]
        let b = m.transcriptBlocks()
        XCTAssertEqual(b.count, 2, "FR-33: one speaker's continuous speech is not fragmented")
        XCTAssertEqual(b[0].text, "one two")
        XCTAssertEqual(b[0].id, m.utterances[0].id, "the block keeps its first utterance's id")
        XCTAssertEqual(b[1].text, "three")
    }

    func testBlocksAreOrderedByTheSessionClockRegardlessOfInputOrder() {
        var m = Meeting(id: "o", startedAt: Date())
        m.utterances = [
            Utterance(start: 10, end: 11, text: "later", speaker: .remote(0), origin: .system),
            Utterance(start: 1, end: 2, text: "earlier", speaker: .local, origin: .mic),
        ]
        let b = m.transcriptBlocks()
        XCTAssertEqual(b.map(\.text), ["earlier", "later"])
    }

    func testEmptyTranscriptProducesNoBlocks() {
        XCTAssertTrue(Meeting(id: "e", startedAt: Date()).transcriptBlocks().isEmpty)
    }

    // MARK: - The revision token

    /// The token is what decides whether the view regroups. Too eager and the lag
    /// comes back; too lazy and a rename does not show.
    func testRevisionChangesOnARename() {
        var m = meeting(utterances: 20)
        let before = m.transcriptRevision
        m.speakerNames[SpeakerLabelID.inRoom(1).raw] = "Mikkel"
        XCTAssertNotEqual(m.transcriptRevision, before)
    }

    func testRevisionChangesWhenAnUtteranceArrives() {
        var m = meeting(utterances: 20)
        let before = m.transcriptRevision
        m.utterances.append(Utterance(start: 999, end: 1000, text: "new",
                                      speaker: .local, origin: .mic))
        XCTAssertNotEqual(m.transcriptRevision, before)
    }

    func testRevisionChangesWhenTheIdentificationChanges() {
        var m = meeting(utterances: 20)
        let before = m.transcriptRevision
        m.localIdentifiedByEnrolment = true
        m.localMatchDistance = 0.14
        XCTAssertNotEqual(m.transcriptRevision, before,
                          "the basis line under a speaker chip would change")
    }

    /// The whole point: editing the title must NOT invalidate the transcript.
    func testRevisionIsUnchangedByATitleEdit() {
        var m = meeting(utterances: 20)
        m.metadata = MeetingMetadata(title: "before", tags: [], summary: "",
                                     decisions: [], actionItems: [], backend: .heuristic)
        let before = m.transcriptRevision
        m.metadata?.title = "after"
        XCTAssertEqual(m.transcriptRevision, before,
                       "a title change must not trigger a regroup — that was the lag")
    }

    func testRevisionIsUnchangedByAnExclusion() {
        var m = meeting(utterances: 20)
        let before = m.transcriptRevision
        m.excludedSpeakers = [SpeakerLabelID.inRoom(1).raw]
        XCTAssertEqual(m.transcriptRevision, before,
                       "exclusion changes the Note, not the in-app transcript")
    }

    // MARK: - Cost

    /// Not a threshold to defend, a figure to record. It measures what one keystroke
    /// used to cost, since the old code did this work on every body evaluation.
    func testGroupingCostIsRecorded() {
        let m = meeting(utterances: 600, speakers: 5)
        let started = Date()
        var blocks = 0
        for _ in 0..<20 { blocks = m.transcriptBlocks().count }
        let per = Date().timeIntervalSince(started) / 20
        print(String(format: "[transcript] %d utterances -> %d blocks, %.2f ms per grouping",
                     m.utterances.count, blocks, per * 1000))
        XCTAssertGreaterThan(blocks, 0)
    }
}

// MARK: - The Note uses the same grouping

/// The app and the Note had two implementations of the same paragraph-building
/// logic, and both had the same defect. They now share one, so a fix or a
/// regression lands in both at once.
final class NoteTranscriptGroupingTests: XCTestCase {

    private let writer = NoteWriter()

    func testTheNoteDoesNotMergeTwoUnnamedInRoomVoices() {
        var m = Meeting(id: "n", startedAt: Date())
        m.multipleInRoom = true
        m.speakerNames = [:]
        m.utterances = [
            Utterance(start: 0, end: 1, text: "mine", speaker: .inRoom(0), origin: .mic),
            Utterance(start: 1, end: 2, text: "theirs", speaker: .inRoom(1), origin: .mic),
        ]
        let out = writer.renderTranscript(m)
        // Two paragraphs, not one run-together block under a single name.
        XCTAssertEqual(out.components(separatedBy: "**00:0").count - 1, 2, out)
        XCTAssertFalse(out.contains("mine theirs"),
                       "two different people's speech must not share a paragraph")
    }

    func testTheNoteStillMergesTwoLabelsRenamedToOneName() {
        var m = Meeting(id: "n2", startedAt: Date())
        m.multipleInRoom = true
        m.speakerNames = [SpeakerLabelID.inRoom(0).raw: "Mikkel",
                          SpeakerLabelID.inRoom(1).raw: "Mikkel"]
        m.utterances = [
            Utterance(start: 0, end: 1, text: "first half", speaker: .inRoom(0), origin: .mic),
            Utterance(start: 1, end: 2, text: "second half", speaker: .inRoom(1), origin: .mic),
        ]
        XCTAssertTrue(writer.renderTranscript(m).contains("first half second half"))
    }

    /// Exclusions belong to the Note and not to the app (FR-40), so the shared
    /// grouping has to be able to honour them without the app inheriting it.
    func testExclusionsApplyToTheNoteOnly() {
        var m = Meeting(id: "n3", startedAt: Date())
        m.multipleInRoom = true
        m.speakerNames = [SpeakerLabelID.inRoom(0).raw: "In-room 1",
                          SpeakerLabelID.inRoom(1).raw: "In-room 2"]
        m.utterances = [
            Utterance(start: 0, end: 1, text: "kept", speaker: .inRoom(0), origin: .mic),
            Utterance(start: 1, end: 2, text: "dropped", speaker: .inRoom(1), origin: .mic),
        ]
        m.excludedSpeakers = [SpeakerLabelID.inRoom(1).raw]

        let note = writer.renderTranscript(m)
        XCTAssertTrue(note.contains("kept"))
        XCTAssertFalse(note.contains("dropped"), "the Note omits an excluded speaker")

        let onScreen = m.transcriptBlocks()
        XCTAssertEqual(onScreen.count, 2, "the app still shows it — the speech is not lost")
        XCTAssertTrue(onScreen.contains { $0.text == "dropped" })
    }

    func testEveryExcludedSpeakerStillProducesAnHonestNote() {
        var m = Meeting(id: "n4", startedAt: Date())
        m.utterances = [Utterance(start: 0, end: 1, text: "x", speaker: .inRoom(0), origin: .mic)]
        m.excludedSpeakers = [SpeakerLabelID.inRoom(0).raw]
        XCTAssertTrue(writer.renderTranscript(m).contains("Every speaker in this meeting has been excluded"))
    }
}

// MARK: - The popover keying defect

/// Renaming from the transcript keyed its popover by `SpeakerLabelID`, so clicking
/// one chip presented every popover for that speaker at once and SwiftUI drew the
/// first in tree order — a row far above the one clicked.
///
/// Measured on the user's own meeting when they reported it: 708 blocks, with
/// `In-room 4` appearing 9 times and `Speaker 2` 173 times. The fix is to key by
/// block id, and what makes that correct is that block ids are unique per block
/// even when the speaker repeats. These tests pin exactly that.
final class TranscriptRenameKeyingTests: XCTestCase {

    /// A speaker who talks, is interrupted, and talks again — the ordinary case,
    /// and the one that broke.
    private func interleaved(blocksPerSpeaker: Int) -> Meeting {
        var m = Meeting(id: "k", startedAt: Date())
        m.multipleInRoom = true
        m.speakerNames = [SpeakerLabelID.inRoom(0).raw: "In-room 1",
                          SpeakerLabelID.inRoom(1).raw: "In-room 2"]
        var t = 0.0
        for _ in 0..<blocksPerSpeaker {
            for who in [SpeakerLabelID.inRoom(0), .inRoom(1)] {
                m.utterances.append(Utterance(start: t, end: t + 2, text: "line at \(t)",
                                              speaker: who, origin: .mic))
                t += 2
            }
        }
        return m
    }

    func testOneSpeakerProducesManyBlocksWithUniqueIDs() {
        let m = interleaved(blocksPerSpeaker: 12)
        let blocks = m.transcriptBlocks()
        XCTAssertEqual(blocks.count, 24, "each turn is its own paragraph")

        // The condition that made keying by speaker wrong.
        let forOneSpeaker = blocks.filter { $0.speaker == .inRoom(0) }
        XCTAssertEqual(forOneSpeaker.count, 12,
                       "one speaker legitimately owns many blocks — this is why a speaker key cannot identify a row")

        // The condition that makes keying by block id right.
        XCTAssertEqual(Set(blocks.map(\.id)).count, blocks.count,
                       "block ids must be unique, or the popover would still be ambiguous")
    }

    /// The keying itself: exactly one block matches a block id, and many match a
    /// speaker id. Expressed as the predicate the view uses.
    func testABlockIDSelectsExactlyOneBlockWhereASpeakerIDSelectsMany() {
        let blocks = interleaved(blocksPerSpeaker: 9).transcriptBlocks()
        guard let target = blocks.first(where: { $0.speaker == .inRoom(1) }) else {
            return XCTFail("no block for that speaker")
        }
        XCTAssertEqual(blocks.filter { $0.id == target.id }.count, 1,
                       "`renamingBlock == b.id` presents exactly one popover")
        XCTAssertGreaterThan(blocks.filter { $0.speaker == target.speaker }.count, 1,
                             "`renaming == b.speaker` presented one per block — 9 in the reported meeting")
    }

    /// Block ids come from the first utterance in the block, so they survive the
    /// rename that follows — the row keeps its identity while its label changes.
    func testABlockIDSurvivesTheRenameItTriggers() {
        var m = interleaved(blocksPerSpeaker: 4)
        let before = m.transcriptBlocks()
        m.speakerNames[SpeakerLabelID.inRoom(1).raw] = "Mikkel"
        let after = m.transcriptBlocks()
        XCTAssertEqual(before.map(\.id), after.map(\.id))
        XCTAssertNotEqual(before.map(\.name), after.map(\.name))
    }

    /// Two labels renamed to one name merge into one block, so the id set shrinks —
    /// worth pinning because it is the one case where ids legitimately change.
    func testMergingTwoSpeakersCollapsesBlocksAndTheirIDs() {
        var m = interleaved(blocksPerSpeaker: 5)
        XCTAssertEqual(m.transcriptBlocks().count, 10)
        m.speakerNames[SpeakerLabelID.inRoom(1).raw] = "In-room 1"
        XCTAssertEqual(m.transcriptBlocks().count, 1,
                       "renaming both to one name merges every turn into one paragraph (FR-24)")
    }
}
