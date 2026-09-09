import XCTest
@testable import Minutes

/// FR-109. The Summaries pane told a user *"Apple Intelligence is switched off on
/// this Mac"* while their Mac had it switched **on** and downloading. The reason
/// was known, logged, and thrown away by a `Bool`.
final class LanguageModelAvailabilityTests: XCTestCase {

    private let all: [LanguageModelAvailability] = [
        .available, .notEnabled, .downloading, .deviceNotEligible,
        .unsupportedSystem, .unrecognised("something new"),
    ]

    // MARK: - The fault

    /// The sentence that was shown, against the state that was real.
    func testTheDownloadingStateIsNotDescribedAsSwitchedOff() {
        let text = LanguageModelAvailability.downloading.reasonForUser
        XCTAssertFalse(text.contains("switched off"),
                       "this is the sentence the user was shown, and it was false")
        XCTAssertTrue(text.lowercased().contains("download"),
                      "the reason must name what is actually happening")
        XCTAssertNotEqual(LanguageModelAvailability.downloading.reasonForUser,
                          LanguageModelAvailability.notEnabled.reasonForUser,
                          "two different causes must not read identically")
    }

    /// Only one state may claim Apple Intelligence is off, and it is the one
    /// named after that.
    func testOnlyOneStateClaimsAppleIntelligenceIsOff() {
        let claiming = all.filter { $0.reasonForUser.contains("switched off") }
        XCTAssertEqual(claiming, [.notEnabled])
    }

    func testEveryStateSaysSomethingDifferent() {
        let texts = all.map(\.reasonForUser)
        XCTAssertEqual(Set(texts).count, texts.count,
                       "two states share a sentence, so one of them is wrong")
        let summaries = all.map(\.summary)
        XCTAssertEqual(Set(summaries).count, summaries.count)
    }

    func testNoStateIsSilent() {
        for a in all {
            XCTAssertFalse(a.reasonForUser.isEmpty, "\(a) tells the user nothing")
            XCTAssertFalse(a.summary.isEmpty, "\(a) tells --doctor nothing")
        }
    }

    // MARK: - What the buttons may claim

    /// A button that cannot change the answer is worse than no button: it makes
    /// the user do something twice and conclude the app is lying.
    func testSettingsIsOfferedOnlyWhereItCouldHelp() {
        XCTAssertTrue(LanguageModelAvailability.notEnabled.settingsCanHelp)
        // Offered while downloading because that pane is where macOS itself
        // reports the download's progress and any restriction on it.
        XCTAssertTrue(LanguageModelAvailability.downloading.settingsCanHelp)
        XCTAssertTrue(LanguageModelAvailability.unrecognised("x").settingsCanHelp)

        XCTAssertFalse(LanguageModelAvailability.deviceNotEligible.settingsCanHelp,
                       "no setting makes an ineligible Mac eligible")
        XCTAssertFalse(LanguageModelAvailability.unsupportedSystem.settingsCanHelp)
        XCTAssertFalse(LanguageModelAvailability.available.settingsCanHelp,
                       "nothing to fix")
    }

    func testCheckAgainIsOfferedOnlyWhereTheAnswerCanChangeByItself() {
        XCTAssertTrue(LanguageModelAvailability.downloading.mayResolveItself,
                      "a download finishes without the app restarting")
        XCTAssertTrue(LanguageModelAvailability.notEnabled.mayResolveItself,
                      "the user can switch it on and come straight back")
        XCTAssertFalse(LanguageModelAvailability.deviceNotEligible.mayResolveItself)
        XCTAssertFalse(LanguageModelAvailability.unsupportedSystem.mayResolveItself)
        XCTAssertFalse(LanguageModelAvailability.available.mayResolveItself)
    }

    func testOnlyAvailableIsUsable() {
        for a in all {
            XCTAssertEqual(a.isUsable, a == .available, "\(a) reported the wrong usability")
        }
    }

    // MARK: - The composed message

    /// The reason and the description of what runs instead are separate, so a
    /// corrected reason cannot leave a stale second half behind it.
    func testTheFallbackDescriptionIsNotBakedIntoAnyReason() {
        for a in all {
            XCTAssertFalse(a.reasonForUser.contains("most salient sentences"),
                           "\(a) has the fallback description baked into its reason")
        }
        XCTAssertTrue(LanguageModelAvailability.fallbackDescription
            .contains("most salient sentences"))
    }

    func testAnUnrecognisedStateRepeatsWhatTheSystemSaidRatherThanGuessing() {
        let a = LanguageModelAvailability.unrecognised("someFutureReason")
        XCTAssertTrue(a.reasonForUser.contains("someFutureReason"),
                      "a reason this build does not know must be quoted, not replaced")
        XCTAssertTrue(a.summary.contains("someFutureReason"))
        XCTAssertFalse(a.reasonForUser.contains("switched off"),
                       "an unknown reason must not be reported as a known one")
    }

    /// A managed Mac can restrict Apple Intelligence, and the app has no API for
    /// that — so it points at the place that does rather than guessing.
    func testTheUnrecognisedStatePointsAtWhereTheRealAnswerIs() {
        XCTAssertTrue(LanguageModelAvailability.unrecognised("x")
            .reasonForUser.contains("managed Mac"))
    }
}
