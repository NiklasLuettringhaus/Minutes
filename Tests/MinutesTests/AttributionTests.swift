import XCTest
@testable import Minutes

/// AD-11 / AD-19 / AD-4 — the structural claims the product rests on.
final class AttributionTests: XCTestCase {

    func testSystemSpansAssignedByGreatestOverlap() {
        let sys = [
            DiarizedSpan(start: 0, end: 10, speakerIndex: 0),
            DiarizedSpan(start: 10, end: 20, speakerIndex: 1),
        ]
        let utterances = [
            Utterance(start: 1, end: 4, text: "a", speaker: .remote(0), origin: .system),
            Utterance(start: 12, end: 15, text: "b", speaker: .remote(0), origin: .system),
            // Straddles the boundary but sits mostly in speaker 1's span.
            Utterance(start: 9, end: 14, text: "c", speaker: .remote(0), origin: .system),
        ]
        let out = Pipeline.assign(micSpans: [], systemSpans: sys, multipleInRoom: false, to: utterances)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.remote(0))
        XCTAssertEqual(out[1].speaker, SpeakerLabelID.remote(1))
        XCTAssertEqual(out[2].speaker, SpeakerLabelID.remote(1))
    }

    /// A single voice on the microphone IS the user, and that inference is safe.
    func testSingleMicVoiceStaysTheUser() {
        let mic = [DiarizedSpan(start: 0, end: 30, speakerIndex: 0)]
        let u = [Utterance(start: 1, end: 4, text: "mine", speaker: .local, origin: .mic)]
        let out = Pipeline.assign(micSpans: mic, systemSpans: [], multipleInRoom: false, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.local)
        XCTAssertEqual(out[0].speaker.place, .you)
    }

    /// The correction that matters: in a meeting room the microphone holds several
    /// people, and none of them may be assumed to be the user.
    func testMultipleMicVoicesBecomeInRoomAndNoneIsAssumedToBeTheUser() {
        let mic = [
            DiarizedSpan(start: 0, end: 5, speakerIndex: 0),
            DiarizedSpan(start: 5, end: 10, speakerIndex: 1),
        ]
        let u = [
            Utterance(start: 1, end: 4, text: "me?", speaker: .local, origin: .mic),
            Utterance(start: 6, end: 9, text: "colleague", speaker: .local, origin: .mic),
        ]
        let out = Pipeline.assign(micSpans: mic, systemSpans: [], multipleInRoom: true, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.inRoom(0))
        XCTAssertEqual(out[1].speaker, SpeakerLabelID.inRoom(1))
        for o in out {
            XCTAssertFalse(o.speaker.isLocal, "no in-room voice may be claimed as the user")
            XCTAssertTrue(o.speaker.isInRoom, "but it is still structurally in the room")
            XCTAssertEqual(o.speaker.place, .room)
        }
    }

    /// The part of the original design that survives: a mic voice can never
    /// become a remote one, or vice versa. Where a voice was is never a guess.
    func testStreamsNeverCross() {
        let mic = [DiarizedSpan(start: 0, end: 100, speakerIndex: 7)]
        let sys = [DiarizedSpan(start: 0, end: 100, speakerIndex: 3)]
        let u = [
            Utterance(start: 1, end: 4, text: "room", speaker: .local, origin: .mic),
            Utterance(start: 1, end: 4, text: "far end", speaker: .remote(0), origin: .system),
        ]
        let out = Pipeline.assign(micSpans: mic, systemSpans: sys, multipleInRoom: true, to: u)
        XCTAssertTrue(out[0].speaker.isInRoom)
        XCTAssertFalse(out[0].speaker.isRemote)
        XCTAssertTrue(out[1].speaker.isRemote)
        XCTAssertFalse(out[1].speaker.isInRoom)
    }

    func testUnmatchedSystemUtteranceKeepsItsLabel() {
        let spans = [DiarizedSpan(start: 50, end: 60, speakerIndex: 1)]
        let u = [Utterance(start: 1, end: 4, text: "x", speaker: .remote(0), origin: .system)]
        let out = Pipeline.assign(micSpans: [], systemSpans: spans, multipleInRoom: false, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.remote(0))
    }

    func testPlaceClassification() {
        XCTAssertEqual(SpeakerLabelID.local.place, .you)
        XCTAssertEqual(SpeakerLabelID.inRoom(2).place, .room)
        XCTAssertEqual(SpeakerLabelID.remote(2).place, .remote)
        XCTAssertTrue(SpeakerLabelID.local.isInRoom, "the user is, trivially, in the room")
        XCTAssertFalse(SpeakerLabelID.inRoom(1).isLocal)
    }

    /// AD-19: rename edits the name map only. Renaming two IDs to one name is
    /// what "merge" means, and it requires no Utterance mutation.
    func testRenameIsAMapEditAndMergeIsWellDefined() {
        var m = Meeting(id: "t", startedAt: Date())
        m.utterances = [
            Utterance(start: 0, end: 1, text: "a", speaker: .remote(0), origin: .system),
            Utterance(start: 1, end: 2, text: "b", speaker: .remote(1), origin: .system),
        ]
        m.speakerNames[SpeakerLabelID.remote(0).raw] = "Speaker 1"
        m.speakerNames[SpeakerLabelID.remote(1).raw] = "Speaker 2"

        // Merge: both labels named the same person.
        m.speakerNames[SpeakerLabelID.remote(0).raw] = "Mikkel"
        m.speakerNames[SpeakerLabelID.remote(1).raw] = "Mikkel"

        XCTAssertEqual(m.displayName(for: .remote(0)), "Mikkel")
        XCTAssertEqual(m.displayName(for: .remote(1)), "Mikkel")
        // Utterances still carry their distinct stable IDs — the merge is display-level.
        XCTAssertEqual(m.utterances[0].speaker, SpeakerLabelID.remote(0))
        XCTAssertEqual(m.utterances[1].speaker, SpeakerLabelID.remote(1))
    }

    func testStageOrderingIsTotalAndAdvances() {
        XCTAssertLessThan(Stage.captured, Stage.transcribed)
        XCTAssertLessThan(Stage.transcribed, Stage.diarized)
        XCTAssertLessThan(Stage.diarized, Stage.attributed)
        XCTAssertLessThan(Stage.attributed, Stage.metadata)
        XCTAssertLessThan(Stage.metadata, Stage.written)
        XCTAssertNil(Stage.written.next, "written is terminal")
        XCTAssertEqual(Stage.captured.next, .transcribed)
    }

    func testCosineDistanceIdentityAndOrthogonality() {
        let a: [Float] = [1, 0, 0]
        XCTAssertEqual(SpeakerDirectory.cosineDistance(a, a) ?? 1, 0, accuracy: 1e-5)
        XCTAssertEqual(SpeakerDirectory.cosineDistance(a, [0, 1, 0]) ?? 0, 1, accuracy: 1e-5)
        XCTAssertNil(SpeakerDirectory.cosineDistance([1, 0], [1, 0, 0]), "length mismatch must not match")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Fmt.duration(0), "00:00")
        XCTAssertEqual(Fmt.duration(65), "01:05")
        XCTAssertEqual(Fmt.duration(3725), "1:02:05")
    }
}

/// Regression tests for the transcript-quality bugs a real run surfaced.
final class TranscriptCleaningTests: XCTestCase {

    func testStripsWhisperNonSpeechMarkers() {
        XCTAssertNil(WhisperKitTranscriber.clean("[BLANK_AUDIO]"))
        XCTAssertNil(WhisperKitTranscriber.clean(" [ SILENCE ] "))
        XCTAssertNil(WhisperKitTranscriber.clean("(music)"))
        XCTAssertNil(WhisperKitTranscriber.clean("[Inaudible]"))
        XCTAssertNil(WhisperKitTranscriber.clean("<|endoftext|>"))
        XCTAssertNil(WhisperKitTranscriber.clean("."))
        XCTAssertNil(WhisperKitTranscriber.clean("   "))
    }

    func testKeepsRealSpeechIntact() {
        XCTAssertEqual(WhisperKitTranscriber.clean("Let's talk about the pricing page."),
                       "Let's talk about the pricing page.")
    }

    func testStripsMarkerButKeepsSurroundingSpeech() {
        let out = WhisperKitTranscriber.clean("[BLANK_AUDIO] Okay, let's begin.")
        XCTAssertEqual(out, "Okay, let's begin.")
    }

    /// A real run produced a phantom `Me: "Thank you."` from a silent microphone,
    /// which invents a participant who never spoke.
    func testDropsWholeSegmentHallucinations() {
        XCTAssertNil(WhisperKitTranscriber.clean("Thank you."))
        XCTAssertNil(WhisperKitTranscriber.clean("  thanks for watching  "))
        XCTAssertNil(WhisperKitTranscriber.clean("you"))
        XCTAssertNil(WhisperKitTranscriber.clean("Okay."))
    }

    func testKeepsHallucinationWordsInsideRealSpeech() {
        XCTAssertEqual(WhisperKitTranscriber.clean("Thank you for taking the pricing page on."),
                       "Thank you for taking the pricing page on.")
        XCTAssertEqual(WhisperKitTranscriber.clean("Okay, so what about Thursday?"),
                       "Okay, so what about Thursday?")
    }

    func testDoesNotEatBracketedRealContent() {
        // Square brackets are not automatically non-speech.
        XCTAssertEqual(WhisperKitTranscriber.clean("The [Q3] number is twelve."),
                       "The [Q3] number is twelve.")
    }
}
