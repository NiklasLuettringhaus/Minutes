import XCTest
import AVFoundation
@testable import Minutes

/// FR-102, FR-103, AD-57, AD-58 — the accounting identity and what it says when
/// samples are lost.
///
/// **The suite exists because of what the defect looked like from outside.** On
/// a 42.4-minute recording both devices ran at 48 kHz within 0.84 s of each
/// other, both reported zero missing frames and zero discontinuities on the
/// audio clock, and the System Stream's file was 8.37 seconds short. Every
/// signal the app had said the capture was clean. So the tests below assert
/// exactly that combination — a clean clock and a short file — and require the
/// ledger to name where the samples went, because that is the reading the
/// increment needs and it is the reading nothing previously produced.
///
/// No audio device is involved anywhere here. The ring and the writer are the
/// real ones; only the producer is a fixture, which is what lets the drop count
/// be *known* rather than observed.
final class CaptureLedgerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - The identity, as arithmetic

    func testTheIdentityClosesWhenNothingIsLost() {
        // 48 kHz in, 16 kHz out: 30,000 input frames become 10,000 output frames.
        let l = CaptureLedger(deviceFrames: 30_000, droppedFrames: 0, overflows: 0,
                              consumedFrames: 30_000, residentFrames: 0,
                              writtenFrames: 10_000, inputRate: 48_000, outputRate: 16_000)
        XCTAssertTrue(l.isMeasured)
        XCTAssertEqual(l.unaccountedFrames, 0)
        XCTAssertEqual(l.conversionRemainder, 0)
        XCTAssertEqual(l.lostFrames, 0)
        XCTAssertNil(l.explanation(streamIsSystem: true))
        XCTAssertTrue(l.attribution.isEmpty, "nothing was lost, so nothing is attributed")
    }

    /// The measured shape of the real defect: the device counted everything, the
    /// ring dropped a third of a per cent, and the file is short by exactly that.
    func testDroppedSamplesAreAttributedToTheRingAndNotToTheResampler() {
        let device: Double = 121_947_648            // as the device counted it
        let dropped: Double = 401_832               // 8.37 s at 48 kHz
        let l = CaptureLedger(deviceFrames: device, droppedFrames: dropped, overflows: 3,
                              consumedFrames: device - dropped, residentFrames: 0,
                              writtenFrames: (device - dropped) / 3,
                              inputRate: 48_000, outputRate: 16_000)
        XCTAssertEqual(l.unaccountedFrames, 0, "the identity closes: the ring has it all")
        XCTAssertEqual(l.conversionRemainder, 0, accuracy: 1,
                       "nothing is charged to the resampler, which is measured at ~11 frames total")
        XCTAssertEqual(l.lostSeconds, 8.37, accuracy: 0.01)
        XCTAssertEqual(l.lostProportion ?? 0, 0.0033, accuracy: 0.0002)
        XCTAssertEqual(l.attribution.first?.term, "dropped before the writer could read them")
    }

    /// The case the instrument exists for above all: a loss that is **not** the
    /// ring's. If a real recording ever reports this, the mechanism is not the
    /// one this increment found and the number says so rather than hiding.
    func testALossTheRingCannotExplainIsReportedAsUnaccountedFor() {
        let l = CaptureLedger(deviceFrames: 300_000, droppedFrames: 0, overflows: 0,
                              consumedFrames: 240_000, residentFrames: 0,
                              writtenFrames: 80_000, inputRate: 48_000, outputRate: 16_000)
        XCTAssertEqual(l.unaccountedFrames, 60_000,
                       "the writer never saw 60,000 frames the device counted")
        XCTAssertEqual(l.conversionRemainder, 0, "and the conversion is not at fault")
        XCTAssertEqual(l.attribution.first?.term, "unaccounted for")
    }

    func testALossBetweenTheRingAndTheFileIsReportedAsAConversionRemainder() {
        let l = CaptureLedger(deviceFrames: 300_000, droppedFrames: 0, overflows: 0,
                              consumedFrames: 300_000, residentFrames: 0,
                              writtenFrames: 90_000, inputRate: 48_000, outputRate: 16_000)
        XCTAssertEqual(l.unaccountedFrames, 0, "the writer consumed everything")
        XCTAssertEqual(l.conversionRemainder, 10_000, "and wrote 10,000 output frames fewer")
        XCTAssertEqual(l.attribution.first?.term, "consumed and not written")
    }

    /// AD-57: **zero is a measurement and absent is not.** The Mic Stream is this
    /// increment's control, and a control that cannot be distinguished from "not
    /// measured" is not a control.
    func testAbsentIsNotZero() {
        XCTAssertFalse(CaptureLedger.unknown.isMeasured)
        XCTAssertNil(CaptureLedger.unknown.lostProportion)
        XCTAssertNil(CaptureLedger.unknown.explanation(streamIsSystem: true))

        let clean = CaptureLedger(deviceFrames: 30_000, droppedFrames: 0, overflows: 0,
                                  consumedFrames: 30_000, residentFrames: 0,
                                  writtenFrames: 10_000, inputRate: 48_000, outputRate: 16_000)
        XCTAssertTrue(clean.isMeasured, "a clean capture is measured, not absent")
        XCTAssertEqual(clean.lostProportion, 0, "and its loss is zero, which is a number")
    }

    /// A Meeting recorded before this existed must decode, and must decode as
    /// absent — the spine's Decodable-evolution convention.
    func testAMeetingFromBeforeThisExistedDecodesAsAbsent() throws {
        let led = try JSONDecoder().decode(CaptureLedger.self,
                                           from: Data("{}".utf8))
        XCTAssertFalse(led.isMeasured)
        XCTAssertEqual(led.droppedFrames, 0)
        let press = try JSONDecoder().decode(DrainPressure.self, from: Data("{}".utf8))
        XCTAssertFalse(press.isMeasured)
        let timing = try JSONDecoder().decode(CaptureStartTiming.self, from: Data("{}".utf8))
        XCTAssertFalse(timing.isMeasured)
        XCTAssertNil(timing.streamOffsetSeconds, "absent, not zero")
    }

    // MARK: - The disclosure floor (UX spine, increment 11)

    /// The floor separates the two cases measured on one real recording: 22 ms on
    /// the Mic Stream and 8.37 s on the System Stream. It must not be reachable
    /// by the first and must not be escapable by the second.
    func testTheDisclosureFloorSeparatesTheTwoMeasuredCases() {
        func ledger(lostOutputFrames: Double) -> CaptureLedger {
            let device: Double = 121_947_648
            let droppedInput = lostOutputFrames * 3
            return CaptureLedger(deviceFrames: device, droppedFrames: droppedInput,
                                 overflows: 1, consumedFrames: device - droppedInput,
                                 residentFrames: 0,
                                 writtenFrames: (device - droppedInput) / 3,
                                 inputRate: 48_000, outputRate: 16_000)
        }
        let mic = ledger(lostOutputFrames: 353)        // 22 ms
        let system = ledger(lostOutputFrames: 133_944) // 8.37 s
        XCTAssertFalse(mic.isWorthDisclosing, "22 ms cannot have lost a whole word")
        XCTAssertTrue(system.isWorthDisclosing, "8.37 s certainly has")
        XCTAssertNotNil(system.explanation(streamIsSystem: true))
        XCTAssertNil(mic.explanation(streamIsSystem: false))
    }

    /// The floor withholds a sentence and never a number. This is the assertion
    /// that stops it from becoming the tolerance AD-51 exists to prevent.
    func testTheFloorHidesTheSentenceAndNeverTheCount() {
        let l = CaptureLedger(deviceFrames: 4_800_000, droppedFrames: 300, overflows: 2,
                              consumedFrames: 4_799_700, residentFrames: 0,
                              writtenFrames: 1_599_900, inputRate: 48_000, outputRate: 16_000)
        XCTAssertFalse(l.isWorthDisclosing, "under the floor")
        XCTAssertEqual(l.droppedFrames, 300, "and the count is still exactly on the record")
        XCTAssertEqual(l.overflows, 2)
        XCTAssertFalse(l.attribution.isEmpty, "and still attributed")
    }

    /// The far end and the user's own voice are not interchangeable, and a reader
    /// deciding whether to trust an attributed decision needs to know which.
    func testTheSentenceNamesWhichStreamLostTheAudio() throws {
        let device: Double = 100_000_000
        let dropped: Double = 480_000    // 10 s at 48 kHz
        let l = CaptureLedger(deviceFrames: device, droppedFrames: dropped, overflows: 4,
                              consumedFrames: device - dropped, residentFrames: 0,
                              writtenFrames: (device - dropped) / 3,
                              inputRate: 48_000, outputRate: 16_000)
        let system = try XCTUnwrap(l.explanation(streamIsSystem: true))
        let mic = try XCTUnwrap(l.explanation(streamIsSystem: false))
        XCTAssertTrue(system.contains("the call's own audio"), system)
        XCTAssertTrue(mic.contains("your microphone's audio"), mic)
        XCTAssertTrue(system.contains("4 separate stretches"), system)
        XCTAssertTrue(system.contains("10 seconds"), system)
        // It must not claim a position it does not have.
        XCTAssertFalse(system.lowercased().contains("at "), system)
    }

    // MARK: - The ring, counting rather than flagging

    /// AD-58. The Bool this replaces could not distinguish these two, and the
    /// difference between them is the whole diagnosis.
    func testTheRingCountsWhatItDropsAndHowOftenRatherThanSettingAFlag() {
        let ring = RingBuffer(capacity: 1024)
        let block = [Float](repeating: 0.5, count: 400)

        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 400) }
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 400) }
        XCTAssertEqual(ring.droppedSamples, 0, "1023 usable, 800 written")
        XCTAssertEqual(ring.overflowEvents, 0)

        // 400 more into 223 of remaining space: 177 dropped, one occasion.
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 400) }
        XCTAssertEqual(ring.droppedSamples, 177)
        XCTAssertEqual(ring.overflowEvents, 1)

        // A second attempt against a full ring drops everything, and is a
        // *second* occasion. One 177-sample loss and two are different faults.
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 400) }
        XCTAssertEqual(ring.droppedSamples, 577)
        XCTAssertEqual(ring.overflowEvents, 2)
    }

    func testTheRingRecordsTheLargestBacklogAReaderEverFound() {
        let ring = RingBuffer(capacity: 4096)
        let block = [Float](repeating: 0.5, count: 1000)
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 1000) }
        _ = ring.read(max: 10)
        XCTAssertEqual(ring.highWaterFill, 1000)
        // Draining it down must not lower the high-water mark: it is a record of
        // the worst moment, not a gauge of the current one.
        _ = ring.read(max: 4096)
        XCTAssertEqual(ring.highWaterFill, 1000)
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 1000) }
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 1000) }
        _ = ring.read(max: 1)
        XCTAssertEqual(ring.highWaterFill, 2000)
    }

    func testResetClearsTheCountsSoTheNextRecordingStartsClean() {
        let ring = RingBuffer(capacity: 512)
        let block = [Float](repeating: 0.5, count: 1000)
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 1000) }
        XCTAssertGreaterThan(ring.droppedSamples, 0)
        ring.reset()
        XCTAssertEqual(ring.droppedSamples, 0)
        XCTAssertEqual(ring.overflowEvents, 0)
        XCTAssertEqual(ring.highWaterFill, 0)
    }

    /// A full ring must drop the whole block rather than copy a negative count.
    /// `available` is `capacity - fill - 1`, which is zero when full — and the
    /// copy loop below it used to run regardless.
    func testAFullRingDropsCleanly() {
        let ring = RingBuffer(capacity: 128)
        let block = [Float](repeating: 1, count: 200)
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 200) }
        XCTAssertEqual(ring.count, 127)
        XCTAssertEqual(ring.droppedSamples, 73)
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 200) }
        XCTAssertEqual(ring.count, 127, "still full, and nothing was corrupted")
        XCTAssertEqual(ring.droppedSamples, 273)
    }

    // MARK: - The writer, through the real ring, with no device

    /// **The reproduction.** The writer is starved deliberately, so the number of
    /// dropped frames is known rather than observed — and the ledger must
    /// attribute every one of them to the ring.
    ///
    /// This is the signature to compare a real recording against: the producer
    /// delivered everything, the consumer could not take it, and the file is
    /// short by exactly what the ring refused.
    func testAStarvedWriterLosesExactlyWhatTheRingRefusedAndTheLedgerSaysSo() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 48_000, channels: 1, interleaved: false)!
        // Two callbacks' worth of capacity, so the fixture can overrun it without
        // needing to be enormous or to depend on a real 10-second ring.
        let ring = RingBuffer(capacity: 8192)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("starved.wav"),
                                 format: fmt, ring: ring)
        // Never started, so no drain thread exists and the consumer is starved by
        // construction rather than by a sleep. A timing-based starvation test is
        // a test of the scheduler, which is the mistake `RateCorrectionTests`
        // made four times.
        let callback = [Float](repeating: 0.4, count: 512)
        var offered = 0
        for _ in 0..<100 {
            callback.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 512) }
            offered += 512
        }
        XCTAssertEqual(offered, 51_200)
        XCTAssertEqual(ring.count, 8191, "the ring is full")
        XCTAssertEqual(ring.droppedSamples, 51_200 - 8_191)
        XCTAssertGreaterThan(ring.overflowEvents, 1)

        // The writer never ran, so nothing was consumed and nothing written. The
        // ledger must place every offered frame in exactly one term.
        let l = w.ledger
        XCTAssertEqual(l.droppedFrames, Double(ring.droppedSamples))
        XCTAssertEqual(l.consumedFrames, 0)
        XCTAssertEqual(l.residentFrames, 8_191)
        XCTAssertEqual(l.droppedFrames + l.consumedFrames + l.residentFrames,
                       Double(offered), "every offered frame is accounted for")
        _ = w
    }

    /// The same fixture, run through a live writer, must close the identity with
    /// **zero** dropped — the control for the test above.
    func testAWriterThatKeepsUpDropsNothingAndTheIdentityCloses() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 48_000, channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("kept-up.wav"),
                                 format: fmt, ring: ring)
        try w.start()
        let callback = [Float](repeating: 0.4, count: 4800)
        for _ in 0..<50 {
            callback.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 4800) }
        }
        w.stop()

        let l = w.ledger
        XCTAssertEqual(l.droppedFrames, 0)
        XCTAssertEqual(l.overflows, 0)
        XCTAssertEqual(l.consumedFrames, 240_000, "everything offered was consumed")
        XCTAssertEqual(l.residentFrames, 0, "and the flush left nothing behind")
        // 240,000 input frames at 48 kHz become 80,000 at 16 kHz. The resampler's
        // one-time priming is measured at about eleven frames in total, so the
        // allowance below is that measurement and not a tolerance.
        XCTAssertEqual(l.writtenFrames, 80_000, accuracy: 64)
        XCTAssertEqual(l.expectedWrittenFrames, 80_000)
        XCTAssertLessThan(abs(l.conversionRemainder), 64,
                          "measured at ~11 frames total across 1,500-20,000 calls")
    }

    /// The counters must survive the ring being reset, because one of the two
    /// adapters resets it before reading the result — which made the System
    /// Stream report a clean ledger on every capture.
    func testTheLedgerSurvivesTheRingBeingResetAfterStop() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 48_000, channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 1 << 16)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("frozen.wav"),
                                 format: fmt, ring: ring)
        try w.start()
        let block = [Float](repeating: 0.4, count: 1 << 17)  // twice the ring
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
        w.stop()
        let before = w.ledger
        XCTAssertGreaterThan(before.droppedFrames, 0, "the fixture overran the ring on purpose")
        let highWaterBefore = w.drainPressure.highWaterFrames

        ring.reset()
        XCTAssertEqual(w.ledger.droppedFrames, before.droppedFrames,
                       "the drop count is frozen at stop, not read live from the ring")
        XCTAssertEqual(w.ledger.overflows, before.overflows)
        XCTAssertEqual(w.drainPressure.highWaterFrames, highWaterBefore)
    }

    // MARK: - FR-103

    func testPressureIsInterpretableOnlyBecauseTheCapacityTravelsWithIt() {
        let p = DrainPressure(highWaterFrames: 24_000, capacityFrames: 480_000,
                              longestGapSeconds: 0.19, backlogAtLongestGap: 9_600,
                              inputRate: 48_000)
        XCTAssertEqual(p.capacitySeconds, 10, accuracy: 0.001, "AD-58's ten seconds")
        XCTAssertEqual(p.highWaterProportion ?? 0, 0.05, accuracy: 0.0001)
        XCTAssertEqual(p.highWaterSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(p.backlogAtLongestGapSeconds, 0.2, accuracy: 0.001)
    }

    /// The case a drop count cannot reach: nothing was lost and the ring nearly
    /// filled. Recorded because it is a fault waiting for a busier day, and it is
    /// indistinguishable from a healthy capture without this.
    func testANearMissIsVisibleEvenThoughNothingWasDropped() {
        let p = DrainPressure(highWaterFrames: 460_800, capacityFrames: 480_000,
                              longestGapSeconds: 9.4, backlogAtLongestGap: 460_800,
                              inputRate: 48_000)
        XCTAssertEqual(p.highWaterProportion ?? 0, 0.96, accuracy: 0.001)
        XCTAssertEqual(p.highWaterSeconds, 9.6, accuracy: 0.01)
        XCTAssertTrue(p.isMeasured)
    }
}
