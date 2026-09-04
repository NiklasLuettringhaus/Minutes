import XCTest
@testable import Minutes

/// AD-51 / FR-94. The device's own account of what it delivered.
///
/// Every case here is three literals and no audio, which is the point of the
/// decision living in Core: the seven recordings this whole line of work exists
/// for are a rate of exactly 2 and exactly 3, and neither needs a sound card to
/// assert.
final class AudioClockTests: XCTestCase {

    /// Ticks for a device delivering `frames` per callback at `rate`, honestly.
    private func honest(rate: Double, frames: Double, count: Int) -> AudioClock {
        var c = AudioClock()
        for i in 0..<count {
            c.record(.init(sampleTime: Double(i) * frames,
                           hostSeconds: 1_000 + Double(i) * frames / rate,
                           frames: frames))
        }
        return c
    }

    func testRateIsTheDevicesOwnCounterOverItsOwnClock() {
        let c = honest(rate: 48_000, frames: 512, count: 200)
        XCTAssertEqual(c.observedRate, 48_000, accuracy: 1)
        XCTAssertTrue(c.isDecisive)
        XCTAssertEqual(c.framesMissing, 0)
        XCTAssertEqual(c.discontinuities, 0)
    }

    /// The defect the whole line of work exists for: a stream declaring 16 kHz
    /// while the device delivers 8 kHz. Five of the seven real recordings.
    func testAHalfRateDeviceReadsAsHalfRate() {
        let c = honest(rate: 8_000, frames: 512, count: 200)
        let f = RateFidelity(declaredRate: 16_000, framesObserved: c.sampleAdvance,
                             elapsedSeconds: c.elapsedSeconds, source: .audioClock,
                             callbackFrames: c.largestTick)
        XCTAssertEqual(f.ratio, 2, accuracy: 0.001)
        guard case .wrong = f.verdict else { return XCTFail("read \(f.verdict)") }
        XCTAssertEqual(f.correctionTarget, 8_000)
    }

    /// **Two callbacks are an answer with a useless tolerance, and it must not
    /// be mistaken for a verdict.** This is the case that would otherwise let a
    /// wildly wrong rate be confirmed as correct in the first millisecond.
    func testTwoCallbacksCannotDecideAnything() {
        let c = honest(rate: 48_000, frames: 512, count: 2)
        XCTAssertTrue(c.isUsable, "there is an answer")
        XCTAssertFalse(c.isDecisive, "and it cannot separate one real rate from another")
        XCTAssertGreaterThan(c.tolerance, 0.9)

        let f = RateFidelity(declaredRate: 96_000, framesObserved: c.sampleAdvance,
                             elapsedSeconds: c.elapsedSeconds, source: .audioClock,
                             callbackFrames: c.largestTick)
        XCTAssertEqual(f.verdict, .settling,
                       "a rate that is out by a factor of two must not read as correct")
    }

    /// The property a declared percentage cannot have.
    func testToleranceNarrowsAsTheMeasurementGrows() {
        let short = honest(rate: 48_000, frames: 512, count: 20)
        let long = honest(rate: 48_000, frames: 512, count: 2_000)
        XCTAssertLessThan(long.tolerance, short.tolerance)
        XCTAssertLessThan(long.tolerance, AudioClock.oscillatorDrift * 2,
                          "with a long enough window only the drift allowance is left")
        XCTAssertLessThan(short.tolerance, 0.06)
    }

    /// The decisive point is derived from the closest pair of real device rates,
    /// so it must actually separate them.
    func testTheDecisiveToleranceSeparatesTheClosestRealRates() {
        let gap = (24_000.0 - 22_050.0) / 22_050.0
        XCTAssertLessThan(AudioClock.decisiveTolerance, gap / 2,
                          "22050 and 24000 are \(gap * 100)% apart and must be distinguishable")
    }

    // MARK: - Continuity, which is a different question

    /// Frames the device counted past and never handed over. The wall clock
    /// cannot see this at all: the loss lowers the frame count *and* leaves the
    /// elapsed time it is divided by running, so the two errors partly cancel.
    func testFramesTheDeviceCountedAndNeverDeliveredAreAHole() {
        var c = AudioClock()
        c.record(.init(sampleTime: 0, hostSeconds: 1_000, frames: 512))
        // The next buffer starts 4096 frames on, not 512: 3584 never arrived.
        c.record(.init(sampleTime: 4_096, hostSeconds: 1_000 + 4_096 / 48_000, frames: 512))
        c.record(.init(sampleTime: 4_608, hostSeconds: 1_000 + 4_608 / 48_000, frames: 512))
        XCTAssertEqual(c.framesMissing, 3_584)
        XCTAssertEqual(c.discontinuities, 1)
        XCTAssertEqual(c.rebases, 0)
    }

    func testAContinuousStreamReportsNoHoles() {
        let c = honest(rate: 48_000, frames: 512, count: 500)
        let cont = StreamContinuity(missingFrames: c.framesMissing,
                                    expectedFrames: c.sampleAdvance,
                                    discontinuities: c.discontinuities, rebases: c.rebases)
        XCTAssertEqual(cont.missingProportion, 0)
        XCTAssertNil(cont.explanation, "nothing happened, so nothing is said")
    }

    /// A device change renumbers the counter. FR-8 supports that, so it is a new
    /// baseline and not lost audio — and reporting it as a hole would invent a
    /// defect out of a working feature.
    func testACounterThatRestartsIsARebaseNotAHole() {
        var c = AudioClock()
        c.record(.init(sampleTime: 100_000, hostSeconds: 1_000, frames: 512))
        c.record(.init(sampleTime: 100_512, hostSeconds: 1_000 + 512 / 48_000, frames: 512))
        c.record(.init(sampleTime: 0, hostSeconds: 1_002, frames: 512))
        c.record(.init(sampleTime: 512, hostSeconds: 1_002 + 512 / 48_000, frames: 512))
        XCTAssertEqual(c.rebases, 1)
        XCTAssertEqual(c.discontinuities, 0)
        XCTAssertEqual(c.framesMissing, 0)
    }

    /// FR-97 / AD-53. The origin survives a rebase, because a device change moves
    /// the device's numbering and not the beginning of the file.
    func testTheOriginSurvivesARebase() {
        var c = AudioClock()
        c.record(.init(sampleTime: 100_000, hostSeconds: 1_234.5, frames: 512))
        c.record(.init(sampleTime: 0, hostSeconds: 1_240.0, frames: 512))
        XCTAssertEqual(c.originHostSeconds, 1_234.5)
    }

    // MARK: - Absent means unknown

    func testAnEmptyClockSaysNothing() {
        let c = AudioClock()
        XCTAssertFalse(c.isUsable)
        XCTAssertFalse(c.isDecisive)
        XCTAssertNil(c.originHostSeconds)
        XCTAssertNil(c.missingProportion)
        XCTAssertEqual(StreamContinuity.unknown.missingProportion, nil,
                       "unknown continuity is not zero continuity")
        XCTAssertNil(StreamContinuity.unknown.explanation)
    }

    /// A record written before increment 10 has no clock source and must decode
    /// as the wall clock rather than throwing — the convention that stopped one
    /// added field orphaning five real recordings.
    func testAnOlderRateRecordStillDecodes() throws {
        let json = #"{"declaredRate":16000,"framesObserved":48000,"elapsedSeconds":3}"#
        let f = try JSONDecoder().decode(RateFidelity.self, from: Data(json.utf8))
        XCTAssertEqual(f.source, .wallClock)
        XCTAssertEqual(f.appliedTolerance, RateFidelity.tolerance)
        XCTAssertEqual(f.observedRate, 16_000)
    }
}
