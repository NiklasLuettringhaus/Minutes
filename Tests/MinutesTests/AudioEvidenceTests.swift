import XCTest
@testable import Minutes

/// AD-36. The defect these pin is that the previous test could not fail:
/// `peak > 0.0001 || duration > 0.25` accepted a quarter second of silence, and
/// the peak it consulted was a decaying UI meter that had usually fallen back to
/// nothing by the time a meeting ended.
final class AudioEvidenceTests: XCTestCase {

    // MARK: - The defect itself

    func testSilenceOfAmpleDurationProducesNoAudio() {
        // The exact shape of the three real system streams that were reported as
        // captured: long, and every sample zero.
        let e = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 1894)
        XCTAssertFalse(e.producedAudio,
            "31 minutes of digital silence must not count as captured audio")
    }

    func testDurationAloneIsNeverEvidence() {
        for d in [0.26, 1, 60, 600, 3600] as [TimeInterval] {
            let e = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: d)
            XCTAssertFalse(e.producedAudio, "duration \(d) must not imply audio")
        }
    }

    func testPeakAloneIsNotEnoughEither() {
        // A click or a pop: real signal, no substance. Both halves are required
        // precisely so neither can carry the claim alone.
        let e = AudioEvidence(peak: 0.9, nonSilentSeconds: 0.01, duration: 30)
        XCTAssertFalse(e.producedAudio)
    }

    func testRealAudioProducesAudio() {
        let e = AudioEvidence(peak: 0.73, nonSilentSeconds: 505.9, duration: 506)
        XCTAssertTrue(e.producedAudio)
    }

    // MARK: - The boundary, stated

    func testExactlyAtTheFloorIsNotAudio() {
        let e = AudioEvidence(peak: AudioEvidence.silenceFloor,
                              nonSilentSeconds: 10, duration: 10)
        XCTAssertFalse(e.producedAudio, "the floor is exclusive")
    }

    func testExactlyAtTheMinimumSignalIsAudio() {
        let e = AudioEvidence(peak: 0.5,
                              nonSilentSeconds: AudioEvidence.minimumSignalSeconds,
                              duration: 5)
        XCTAssertTrue(e.producedAudio, "the signal minimum is inclusive")
    }

    /// The five-second Test Playground (FR-47) must be able to pass. A threshold
    /// tuned for meetings would make the test unpassable and nobody would notice
    /// until someone ran it.
    func testAFiveSecondTestCanPass() {
        let e = AudioEvidence(peak: 0.4, nonSilentSeconds: 3.0, duration: 5)
        XCTAssertTrue(e.producedAudio)
        XCTAssertLessThan(AudioEvidence.minimumSignalSeconds, 5.0)
    }

    /// If either constant drifts outside the range the calibration justified,
    /// this fails rather than passing quietly.
    func testConstantsStayWithinWhatWasMeasured() {
        XCTAssertGreaterThan(AudioEvidence.silenceFloor, 0,
            "a floor of zero would let a single stray sample count as audio")
        XCTAssertLessThan(AudioEvidence.silenceFloor, 0.01,
            "the quietest working stream measured 0.0237 peak; a higher floor would reject it")
        XCTAssertGreaterThan(AudioEvidence.minimumSignalSeconds, 0.05,
            "must exceed a click")
        XCTAssertLessThan(AudioEvidence.minimumSignalSeconds, 1.5,
            "the quietest genuinely-working stream held 1.5 s of signal")
    }

    // MARK: - Saying why

    func testFailureReasonNamesSilenceRatherThanShrugging() {
        let e = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 1894)
        let why = e.failureReason
        XCTAssertNotNil(why)
        XCTAssertTrue(why!.contains("silent"), "got: \(why!)")
        // How much was recorded, in a unit a person reads rather than converts.
        XCTAssertTrue(why!.contains("32 minutes"), "got: \(why!)")
    }

    func testDurationsAreSpelledForReadingNotForCounting() {
        XCTAssertEqual(AudioEvidence.spell(0.2), "0.20 seconds")
        XCTAssertEqual(AudioEvidence.spell(1), "1 second")
        XCTAssertEqual(AudioEvidence.spell(5), "5 seconds")
        XCTAssertEqual(AudioEvidence.spell(89), "89 seconds")
        XCTAssertEqual(AudioEvidence.spell(90), "2 minutes")
        XCTAssertEqual(AudioEvidence.spell(757), "13 minutes")
        XCTAssertEqual(AudioEvidence.spell(1893), "32 minutes")
    }

    func testFailureReasonDistinguishesNothingRecordedFromSilence() {
        let nothing = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 0)
        XCTAssertEqual(nothing.failureReason, "nothing was recorded")
    }

    func testFailureReasonNamesAMostlySilentStream() {
        let e = AudioEvidence(peak: 0.36, nonSilentSeconds: 0.2, duration: 1116)
        XCTAssertNotNil(e.failureReason)
        XCTAssertTrue(e.failureReason!.contains("0.20"), "got: \(e.failureReason!)")
    }

    func testSuccessHasNoFailureReason() {
        XCTAssertNil(AudioEvidence(peak: 0.5, nonSilentSeconds: 9, duration: 10).failureReason)
    }

    func testNoneIsNotAudio() {
        XCTAssertFalse(AudioEvidence.none.producedAudio)
    }
}

/// FR-66. `AppState.lastError` was written on four paths and read by one
/// command-line file; nothing in `UI/` read it. These pin the parts of that fix
/// that are not SwiftUI layout.
final class FailureRemedyTests: XCTestCase {

    func testEveryErrorHasADescription() {
        for e in Self.all {
            XCTAssertNotNil(e.errorDescription, "\(e) has no description")
            XCTAssertFalse(e.errorDescription!.isEmpty)
        }
    }

    /// Not every error has an action the app can take, but the ones a user hits
    /// while trying to record must — those are the ones that leave them stuck.
    func testTheErrorsThatBlockRecordingOfferARemedy() {
        let blocking: [MinutesError] = [
            .microphonePermissionDenied,
            .microphoneUnavailable("no usable format"),
            .systemAudioTapFailed(stage: "start", status: -10851),
            .systemAudioProducedSilence("every sample is silent"),
            .notesFolderUnavailable,
            .modelNotDownloaded("openai_whisper-base"),
        ]
        for e in blocking {
            XCTAssertNotNil(e.remedy, "\(e) leaves the user with nothing to press")
            XCTAssertNotNil(e.recoverySuggestion, "\(e) says what went wrong but not what to do")
        }
    }

    func testRemedyLabelsAreNotEmpty() {
        for r in [MinutesError.Remedy.openMicrophoneSettings, .openSystemAudioSettings,
                  .chooseTranscriptionModel, .chooseNotesFolder, .runAudioTest] {
            XCTAssertFalse(r.label.isEmpty)
        }
    }

    /// Deliberately *not* the settings pane. A tap that ran and heard nothing is
    /// either a revoked permission or a quiet meeting, and both deliver exact
    /// digital zeros — so the remedy is the thing that can tell them apart, not a
    /// fix for whichever one we guessed.
    func testSilentSystemAudioOffersTheTestRatherThanADiagnosis() {
        XCTAssertEqual(MinutesError.systemAudioProducedSilence("x").remedy, .runAudioTest)
    }

    func testSilentSystemAudioNamesBothPossibleCauses() {
        let s = MinutesError.systemAudioProducedSilence("x").recoverySuggestion!
        XCTAssertTrue(s.contains("nothing was playing"), "got: \(s)")
        XCTAssertTrue(s.contains("permission"), "got: \(s)")
    }

    /// A tap that failed to *establish* is diagnostic, so that one keeps the
    /// settings remedy.
    func testAFailedTapStillPointsAtTheSetting() {
        XCTAssertEqual(MinutesError.systemAudioTapFailed(stage: "start", status: -1).remedy,
                       .openSystemAudioSettings)
    }

    /// The reason a user sees must say what happened, and the silence case is the
    /// one the app previously could not report at all.
    func testSilentSystemAudioReadsAsAPartialRecording() {
        let d = MinutesError.systemAudioProducedSilence("2 seconds were recorded and every sample is silent").errorDescription!
        XCTAssertTrue(d.contains("Only your side"), "got: \(d)")
    }

    static let all: [MinutesError] = [
        .microphonePermissionDenied,
        .microphoneUnavailable("d"),
        .systemAudioTapFailed(stage: "s", status: -1),
        .systemAudioProducedSilence("d"),
        .noDefaultOutputDevice,
        .audioFileWriteFailed("d"),
        .modelNotDownloaded("m"),
        .modelLoadFailed("d"),
        .transcriptionFailed("d"),
        .diarizationFailed("d"),
        .voiceSampleUnreadable("d"),
        .voiceSampleTooShort(seconds: 1),
        .voiceSampleSilent,
        .voiceSampleMultipleVoices(count: 2),
        .voiceEmbeddingFailed("d"),
        .notesFolderUnavailable,
        .notesFolderNotWritable("p"),
        .persistenceFailed("d"),
        .stageFailed(stage: "s", reason: "r"),
    ]
}
