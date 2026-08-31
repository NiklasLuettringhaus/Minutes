import XCTest
@testable import Minutes

/// AD-11 / AD-19 / AD-4 — the structural claims the product rests on.
final class AttributionTests: XCTestCase {

    func testDiarizedSpansAssignedByGreatestOverlap() {
        let spans = [
            DiarizedSpan(start: 0, end: 10, speakerIndex: 0),
            DiarizedSpan(start: 10, end: 20, speakerIndex: 1),
        ]
        let utterances = [
            Utterance(start: 1, end: 4, text: "a", speaker: .remote(0), origin: .system),
            Utterance(start: 12, end: 15, text: "b", speaker: .remote(0), origin: .system),
            // Straddles the boundary but sits mostly in speaker 1's span.
            Utterance(start: 9, end: 14, text: "c", speaker: .remote(0), origin: .system),
        ]
        let out = Pipeline.assign(spans: spans, to: utterances)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.remote(0))
        XCTAssertEqual(out[1].speaker, SpeakerLabelID.remote(1))
        XCTAssertEqual(out[2].speaker, SpeakerLabelID.remote(1))
    }

    /// The core structural guarantee: a Mic Stream Utterance is never reassigned
    /// to a Remote Speaker, whatever diarization says.
    func testMicStreamNeverReassigned() {
        let spans = [DiarizedSpan(start: 0, end: 100, speakerIndex: 3)]
        let utterances = [
            Utterance(start: 1, end: 4, text: "mine", speaker: .local, origin: .mic),
        ]
        let out = Pipeline.assign(spans: spans, to: utterances)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.local,
                       "AD-11: the Local Speaker is structural and cannot be overridden")
    }

    func testUnmatchedSystemUtteranceKeepsItsLabel() {
        let spans = [DiarizedSpan(start: 50, end: 60, speakerIndex: 1)]
        let u = [Utterance(start: 1, end: 4, text: "x", speaker: .remote(0), origin: .system)]
        let out = Pipeline.assign(spans: spans, to: u)
        XCTAssertEqual(out[0].speaker, SpeakerLabelID.remote(0))
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
