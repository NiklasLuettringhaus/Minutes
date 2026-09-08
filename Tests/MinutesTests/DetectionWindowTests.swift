import XCTest
@testable import Minutes

/// FR-106. The two faults these cover both shipped, and both were found from a
/// user's recordings rather than from a test, because the logic they lived in
/// was inline in a method that enumerates CoreAudio process objects and could
/// not be called from a test at all.
final class DetectionWindowTests: XCTestCase {

    private let teams = "com.microsoft.teams2"
    private let slack = "com.tinyspeck.slackmacgap"

    private func window() -> DetectionWindow {
        DetectionWindow(debounce: 2.5, grace: 12.0)
    }

    /// Walks a window forward one second at a time, which is what the service
    /// does, and returns everything it said along the way.
    private func run(_ w: inout DetectionWindow,
                     from t: Date,
                     seconds: Int,
                     held: (Int) -> Set<String>) -> (candidates: [String], ended: [String]) {
        var candidates: [String] = []
        var ended: [String] = []
        for s in 0..<seconds {
            let v = w.update(held: held(s), now: t.addingTimeInterval(Double(s)))
            candidates += v.candidates
            ended += v.ended
            // The service announces whatever it actually asks about; mirroring
            // that here is what makes "asked twice" observable.
            for c in v.candidates { w.announce(c) }
        }
        return (candidates, ended)
    }

    // MARK: - The debounce (FR-12), unchanged behaviour

    func testAHolderIsNotAskedAboutBeforeTheDebounce() {
        var w = window()
        let t = Date()
        XCTAssertTrue(w.update(held: [teams], now: t).candidates.isEmpty)
        XCTAssertTrue(w.update(held: [teams], now: t.addingTimeInterval(1)).candidates.isEmpty)
        XCTAssertTrue(w.update(held: [teams], now: t.addingTimeInterval(2.4)).candidates.isEmpty)
        XCTAssertEqual(w.update(held: [teams], now: t.addingTimeInterval(2.5)).candidates, [teams])
    }

    func testTheUserIsAskedOnceNotEverySecond() {
        var w = window()
        let r = run(&w, from: Date(), seconds: 60) { _ in [self.teams] }
        XCTAssertEqual(r.candidates, [teams], "asked \(r.candidates.count) times for one meeting")
        XCTAssertTrue(r.ended.isEmpty)
    }

    // MARK: - The grace period (FR-106) — the recording that was lost

    /// The measured fault. One Teams call became three recordings on 8 Sep
    /// because a two-second gap between releasing one input device and taking
    /// the next was read as the meeting ending.
    func testASwitchBetweenAudioDevicesDoesNotEndTheMeeting() {
        var w = window()
        // Nine minutes of call, two seconds of switching hardware, then more call.
        let r = run(&w, from: Date(), seconds: 600) { s in
            (540...541).contains(s) ? [] : [self.teams]
        }
        XCTAssertTrue(r.ended.isEmpty, "a 2 s device switch ended the meeting")
        XCTAssertEqual(r.candidates, [teams], "the switch raised a second prompt")
    }

    /// Pins the fault itself, so the test above is known to be testing something.
    /// A window with no grace period is what shipped, and it has to fail here.
    func testWithNoGracePeriodTheSwitchDoesEndTheMeeting() {
        var w = DetectionWindow(debounce: 2.5, grace: 0)
        let r = run(&w, from: Date(), seconds: 600) { s in
            (540...541).contains(s) ? [] : [self.teams]
        }
        XCTAssertEqual(r.ended, [teams], "this is the shipped behaviour being fixed")
        XCTAssertEqual(r.candidates.count, 2, "and it asked a second time")
    }

    func testEvenARepeatedlyFlickeringDeviceDoesNotEndTheMeeting() {
        var w = window()
        // Absent every fifth second, for ten minutes. Never absent for 12.
        let r = run(&w, from: Date(), seconds: 600) { s in
            s % 5 == 0 && s > 0 ? [] : [self.teams]
        }
        XCTAssertTrue(r.ended.isEmpty)
        XCTAssertEqual(r.candidates, [teams])
    }

    /// The grace period must not become a way of never stopping. FR-14 still has
    /// to fire when the meeting is genuinely over.
    func testAMeetingThatActuallyEndsIsStillDetected() {
        var w = window()
        let r = run(&w, from: Date(), seconds: 120) { s in s < 60 ? [self.teams] : [] }
        XCTAssertEqual(r.ended, [teams])
        XCTAssertEqual(r.candidates, [teams])
    }

    func testTheEndIsReportedOnceNotOnEveryPollAfterwards() {
        var w = window()
        let r = run(&w, from: Date(), seconds: 300) { s in s < 60 ? [self.teams] : [] }
        XCTAssertEqual(r.ended, [teams], "reported the end \(r.ended.count) times")
    }

    func testTheEndArrivesWithinTheGracePeriodAndNotBefore() {
        var w = window()
        let t = Date()
        _ = w.update(held: [teams], now: t)
        // Absent from t+1 onward; last held at t.
        XCTAssertTrue(w.update(held: [], now: t.addingTimeInterval(11.9)).ended.isEmpty)
        XCTAssertEqual(w.update(held: [], now: t.addingTimeInterval(12.0)).ended, [teams])
    }

    /// FR-14 promises the Session stops within thirty seconds of the release.
    /// The grace period is spent out of that budget, so it has to leave room for
    /// the poll interval and the stop itself.
    func testTheGracePeriodStaysInsideTheRequirementItSpends() {
        XCTAssertLessThan(DetectionService.releaseGrace, 30.0,
                          "FR-14 allows 30 s from release to stopped")
        XCTAssertLessThanOrEqual(DetectionService.releaseGrace + 1.0 + 2.0, 30.0,
                                 "grace + one poll + the stop must fit in FR-14's 30 s")
        XCTAssertGreaterThan(DetectionService.releaseGrace, 4.0,
                             "shorter than a device switch defeats the point")
    }

    // MARK: - What the grace period must not soften

    func testABriefGapDoesNotRestartTheDebounceAndSoDoesNotAskAgain() {
        var w = window()
        let t = Date()
        // Held long enough to be asked about.
        _ = w.update(held: [teams], now: t)
        let first = w.update(held: [teams], now: t.addingTimeInterval(3))
        XCTAssertEqual(first.candidates, [teams])
        w.announce(teams)
        // A switch, then back. The same episode continues.
        XCTAssertTrue(w.update(held: [], now: t.addingTimeInterval(4)).candidates.isEmpty)
        let back = w.update(held: [teams], now: t.addingTimeInterval(5))
        XCTAssertTrue(back.candidates.isEmpty, "asked a second time about one meeting")
        XCTAssertTrue(back.ended.isEmpty)
    }

    func testANewMeetingAfterARealEndingIsAskedAboutAgain() {
        var w = window()
        let t = Date()
        _ = w.update(held: [teams], now: t)
        _ = w.update(held: [teams], now: t.addingTimeInterval(3))
        w.announce(teams)
        XCTAssertEqual(w.update(held: [], now: t.addingTimeInterval(20)).ended, [teams])
        // A genuinely new call an hour later.
        let t2 = t.addingTimeInterval(3600)
        _ = w.update(held: [teams], now: t2)
        XCTAssertEqual(w.update(held: [teams], now: t2.addingTimeInterval(3)).candidates, [teams],
                       "a new meeting after a real ending must still be offered")
    }

    func testOneAppEndingDoesNotDisturbAnother() {
        var w = window()
        let t = Date()
        _ = w.update(held: [teams, slack], now: t)
        _ = w.update(held: [teams, slack], now: t.addingTimeInterval(3))
        w.announce(teams); w.announce(slack)
        let v = w.update(held: [slack], now: t.addingTimeInterval(20))
        XCTAssertEqual(v.ended, [teams])
        XCTAssertTrue(v.candidates.isEmpty)
        XCTAssertEqual(w.tracked, [slack])
    }

    func testResetForgetsEverything() {
        var w = window()
        let t = Date()
        _ = w.update(held: [teams], now: t)
        w.announce(teams)
        w.reset()
        XCTAssertTrue(w.tracked.isEmpty)
        // A fresh episode, so the debounce runs again from here.
        XCTAssertTrue(w.update(held: [teams], now: t.addingTimeInterval(1)).candidates.isEmpty)
    }

    func testAbsenceIsVisibleWhileInsideTheGracePeriod() {
        var w = window()
        let t = Date()
        _ = w.update(held: [teams], now: t)
        XCTAssertNil(w.absence(of: teams, now: t), "a held device is not absent")
        _ = w.update(held: [], now: t.addingTimeInterval(3))
        XCTAssertEqual(w.absence(of: teams, now: t.addingTimeInterval(3)) ?? 0, 3.0, accuracy: 0.01)
        XCTAssertNil(w.absence(of: "com.example.other", now: t))
    }

    // MARK: - Identity (AD-5): the app, not the process holding the device

    /// Teams exposes no bare audio process object — only helper processes — and
    /// it swaps between them when audio moves to different hardware. Identity
    /// was the helper's bundle ID, so the swap looked like one meeting ending
    /// and another starting even when the device was never released.
    func testTwoHelperProcessesOfOneAppAreOneMeeting() {
        let a = DetectedMeeting(watchedPrefix: teams,
                                bundleID: "com.microsoft.teams2.modulehost",
                                appName: "Microsoft Teams")
        let b = DetectedMeeting(watchedPrefix: teams,
                                bundleID: "com.microsoft.teams2.helper",
                                appName: "Microsoft Teams")
        XCTAssertEqual(a.id, b.id, "a helper swap must not look like a new meeting")
        XCTAssertEqual(a.id, teams, "identity is the watched app")
        XCTAssertNotEqual(a.bundleID, b.bundleID, "the holder is still recorded")
    }

    func testAHelperSwapMidMeetingRaisesNoSecondPrompt() {
        var w = window()
        let t = Date()
        // Same identity throughout, even though the holder changed.
        let modulehost = DetectedMeeting(watchedPrefix: teams,
                                         bundleID: "com.microsoft.teams2.modulehost",
                                         appName: "Microsoft Teams")
        let helper = DetectedMeeting(watchedPrefix: teams,
                                     bundleID: "com.microsoft.teams2.helper",
                                     appName: "Microsoft Teams")
        _ = w.update(held: [modulehost.id], now: t)
        XCTAssertEqual(w.update(held: [modulehost.id], now: t.addingTimeInterval(3)).candidates, [teams])
        w.announce(teams)
        let v = w.update(held: [helper.id], now: t.addingTimeInterval(4))
        XCTAssertTrue(v.ended.isEmpty, "a helper swap ended the meeting")
        XCTAssertTrue(v.candidates.isEmpty, "a helper swap raised a second prompt")
    }
}
