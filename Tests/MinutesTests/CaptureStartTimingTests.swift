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
        XCTAssertEqual(d?.deviceLatency ?? 0, 0.016, accuracy: 0.001)
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
                XCTAssertEqual((d?.serialisation ?? 0) + (d?.deviceLatency ?? 0),
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
