import XCTest
import AVFoundation
@testable import Minutes

/// FR-104, FR-105, AD-59 — the start offset decomposed, and the two starts made
/// adjacent.
///
/// **The arithmetic is what is tested here, because the arithmetic is what the
/// increment relies on.** The offset FR-97 records had been one number for a
/// whole increment and nothing could be aimed at it: +1,006 ms on a real
/// 42.4-minute meeting against +16 to +62 ms on a five-second probe. Splitting
/// it into the part capture caused and the part the devices did is only worth
/// anything if the two terms provably sum to the whole — otherwise a change that
/// moved audio from one term to the other would look like an improvement.
final class CaptureStartTimingTests: XCTestCase {

    /// The old order, as it actually behaved: the microphone starts, the tap
    /// chain is then built while the microphone is already recording, and the tap
    /// starts afterwards. Every millisecond of the build lands in the offset.
    func testTheOldOrderChargedTheTapChainBuildToTheOffset() {
        let t = CaptureStartTiming(
            beganAt: 0,
            micPreparedAt: 0.200,
            micStartedAt: 0.200,
            tapChainBuiltAt: 1.150,     // 950 ms of chain building, while recording
            systemStartedAt: 1.150,
            micFirstSampleAt: 0.197,    // the engine had already begun
            systemFirstSampleAt: 1.163)
        XCTAssertEqual(t.streamOffsetSeconds ?? 0, 0.966, accuracy: 0.001)
        let d = t.decomposition
        XCTAssertEqual(d?.serialisation ?? 0, 0.950, accuracy: 0.001,
                       "almost all of it is the build, and none of it is the devices")
        XCTAssertEqual(d?.deviceLatencyGap ?? 0, 0.016, accuracy: 0.001)
    }

    /// AD-59's order: the chain is built before either device runs, so the two
    /// starts are adjacent and the residual is device latency alone.
    func testTheNewOrderLeavesOnlyDeviceLatencyInTheOffset() {
        let t = CaptureStartTiming(
            beganAt: 0,
            micPreparedAt: 0.200,
            micStartedAt: 1.150,
            tapChainBuiltAt: 1.150,     // the same 950 ms, now paid before anything records
            systemStartedAt: 1.1501,
            micFirstSampleAt: 1.147,
            systemFirstSampleAt: 1.163)
        XCTAssertEqual(t.tapChainBuildSeconds ?? 0, 0.950, accuracy: 0.001)
        XCTAssertEqual(t.startSerialisationSeconds ?? 0, 0.0001, accuracy: 0.0005,
                       "nothing may sit between the two starts")
        XCTAssertEqual(t.streamOffsetSeconds ?? 0, 0.016, accuracy: 0.001)
        XCTAssertLessThanOrEqual(abs(t.streamOffsetSeconds ?? 1), 0.100,
                                 "and FR-6's claim holds on this shape")
    }

    /// The two terms must sum to the offset exactly, or a change that moved cost
    /// from one to the other would read as an improvement.
    func testTheDecompositionSumsToTheOffsetByConstruction() {
        for serial in [-0.5, 0.0, 0.0001, 0.35, 1.2] {
            for latency in [-0.21, 0.0, 0.016, 0.4] {
                let t = CaptureStartTiming(
                    beganAt: 0, micPreparedAt: 0.1, micStartedAt: 0.5,
                    tapChainBuiltAt: 0.1, systemStartedAt: 0.5 + serial,
                    micFirstSampleAt: 0.5, systemFirstSampleAt: 0.5 + serial + latency)
                let d = try? XCTUnwrap(t.decomposition)
                XCTAssertEqual((d?.serialisation ?? 0) + (d?.deviceLatencyGap ?? 0),
                               t.streamOffsetSeconds ?? .nan, accuracy: 1e-9)
            }
        }
    }

    /// The first reading charged `engine.prepare()` to the tap chain and reported
    /// 350 ms of chain building that was mostly the microphone's. A stage
    /// measurement that charges one stage for another points a change at the
    /// wrong place, which is worse than having no stage measurement.
    func testThePreparationOfEachStreamIsChargedToThatStream() {
        let t = CaptureStartTiming(beganAt: 0, micPreparedAt: 0.300,
                                   micStartedAt: 0.345, tapChainBuiltAt: 0.345,
                                   systemStartedAt: 0.345)
        XCTAssertEqual(t.micPrepareSeconds ?? 0, 0.300, accuracy: 0.001)
        XCTAssertEqual(t.tapChainBuildSeconds ?? 0, 0.045, accuracy: 0.001)
    }

    /// AD-53's rule, applied to this type: absent is unknown, never zero.
    func testASessionThatStampedNothingReportsAbsentRatherThanZero() {
        let t = CaptureStartTiming.unknown
        XCTAssertFalse(t.isMeasured)
        XCTAssertNil(t.streamOffsetSeconds)
        XCTAssertNil(t.decomposition)
        XCTAssertNil(t.startSerialisationSeconds)
        XCTAssertNil(t.tapChainBuildSeconds)

        // A Mic-only Session stamps the microphone's side and nothing else. It
        // must not read as a zero offset.
        let micOnly = CaptureStartTiming(beganAt: 0, micPreparedAt: 0.1,
                                         micStartedAt: 0.1, micFirstSampleAt: 0.1)
        XCTAssertTrue(micOnly.isMeasured)
        XCTAssertNil(micOnly.streamOffsetSeconds, "there is no second Stream to offset from")
        XCTAssertNil(micOnly.decomposition)
    }

    /// FR-7 takes precedence over AD-59, and this is the assertion that keeps it
    /// that way. The tap chain is now built *before* the microphone is started,
    /// so a failure in it happens earlier than it used to — and it must still
    /// leave a running microphone and a degraded Session rather than no Session.
    ///
    /// Driven through the real `DualStreamCapture` against a directory it cannot
    /// write to for the tap, which is the closest a test can get to a failing
    /// chain without a device. Skipped where the microphone is not authorised,
    /// because there is then nothing to assert about degradation.
    func testAFailingTapChainStillLeavesTheMicrophoneRunning() throws {
        try XCTSkipUnless(MicCapture.authorizationStatus() == .authorized,
                          "needs microphone permission; the assertion is about degradation")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-degrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let capture = DualStreamCapture()
        try capture.start(into: dir)
        XCTAssertTrue(capture.isRunning, "the Session runs whatever the tap did")
        // Whether the tap succeeded here depends on the machine, and the
        // assertion deliberately does not depend on that: what must hold is that
        // the microphone is capturing and the degradation is reported honestly.
        let degraded = capture.isDegraded
        let streams = capture.stop()
        XCTAssertNotNil(streams.micURL, "the microphone's file exists on both paths")
        if degraded {
            XCTAssertFalse(streams.systemCaptured)
            XCTAssertNil(streams.streamStartOffset,
                         "with one Stream there is no offset, and absent is not zero")
        }
        XCTAssertTrue(streams.startTiming.isMeasured,
                      "the stamps are taken whether or not the tap survived")
        XCTAssertNotNil(streams.startTiming.micPrepareSeconds)
    }

    /// AD-59's actual claim, on this machine: nothing sits between the two device
    /// starts. This is the one assertion that a future reordering would break.
    func testNothingSitsBetweenTheTwoDeviceStarts() throws {
        try XCTSkipUnless(MicCapture.authorizationStatus() == .authorized,
                          "needs microphone permission")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-adjacent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let capture = DualStreamCapture()
        try capture.start(into: dir)
        let streams = capture.stop()
        let t = streams.startTiming
        guard let serial = t.startSerialisationSeconds else {
            throw XCTSkip("no system tap on this machine, so there is no gap to measure")
        }
        // Two CoreAudio calls back to back. Measured at 0.1-0.2 ms across six
        // runs; the bound is two orders of magnitude above that, so it fails on
        // a reordering and not on a busy machine.
        XCTAssertLessThan(serial, 0.020,
                          "the tap chain must be built before either device is started")
        XCTAssertGreaterThan(t.tapChainBuildSeconds ?? -1, 0,
                             "and the build must have happened before the starts")
    }
}

/// AD-2 under AD-59 — the teardown paths the prepare/begin split created.
///
/// **Found by review, not by a test, and this is the test that was missing.**
/// `SystemTapCapture.createIOProc` does `Unmanaged.passRetained(self)`, so a
/// prepared tap holds a reference to itself and `deinit` can never fire.
/// Dropping one without tearing it down leaks the private aggregate device and
/// the global process tap for the life of the process — AD-2 names that harm
/// exactly, "a leaked aggregate device is visible system-wide" — and leaves the
/// writer's drain thread spinning on a file it never closes.
///
/// Before AD-59 the path did not exist: the chain was built *after* the
/// microphone had started, so a microphone failure happened before there was
/// anything to leak. Moving the build earlier created it.
final class CaptureTeardownTests: XCTestCase {

    /// A prepared-but-never-begun tap must be releasable, and releasing it must
    /// leave nothing behind that a second Session would collide with.
    ///
    /// The assertion is that two full prepare/discard cycles both succeed. A
    /// leaked aggregate device is not directly observable from inside the
    /// process, but a leak of the *tap* makes the next `prepare` fail or the
    /// device count grow without bound — so a loop that keeps succeeding is the
    /// available evidence, and it fails if `discard` stops tearing down.
    func testAPreparedTapCanBeDiscardedWithoutLeaking() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-discard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0..<3 {
            let tap = SystemTapCapture()
            do {
                try tap.prepare(url: dir.appendingPathComponent("s\(i).wav"))
            } catch {
                throw XCTSkip("no system tap on this machine: \(error.localizedDescription)")
            }
            XCTAssertFalse(tap.isRunning, "prepared is not running")
            tap.discard()
            XCTAssertFalse(tap.isRunning)
        }
    }

    /// A Session starts and stops cleanly, leaving nothing running.
    ///
    /// **One cycle, not three, and the reason is a measurement.** The first
    /// version cycled three Sessions in a rapid loop to make an accumulated leak
    /// visible, and it failed inside the full suite with
    /// `-10868` (`kAudioUnitErr_FormatNotSupported`) while passing in
    /// isolation — because several tests in the suite open the input device in
    /// quick succession and it will not always reopen. That is test isolation,
    /// not the product: `StartOrderRegressionTests` runs **fifteen** full cycles
    /// of each start order with the devices to itself and measures **0/15**
    /// microphone failures for both.
    ///
    /// Loosening the assertion would have been the wrong fix — the resolution is
    /// that the cycling belonged in a gated measurement rather than in the
    /// suite, which is the same conclusion four attempts at a rate harness
    /// reached in `WavRateRepairTests`.
    func testASessionStartsAndStopsLeavingNothingRunning() throws {
        try XCTSkipUnless(MicCapture.authorizationStatus() == .authorized,
                          "needs microphone permission")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-failstart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let capture = DualStreamCapture()
        try capture.start(into: dir)
        XCTAssertTrue(capture.isRunning)
        _ = capture.stop()
        XCTAssertFalse(capture.isRunning, "stop leaves nothing running")
    }
}
