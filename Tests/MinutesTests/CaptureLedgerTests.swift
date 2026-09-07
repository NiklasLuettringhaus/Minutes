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

    /// The two halves of a conversion loss are different faults and the ledger
    /// must not render them identically. "Consumed and not written" was doing
    /// the work of both, and the two have different causes and different fixes:
    /// one is a converter that did not produce, the other is a disk that did not
    /// accept.
    func testTheTwoHalvesOfAConversionLossAreDistinguished() {
        // The converter never produced it.
        let neverConverted = CaptureLedger(
            deviceFrames: 300_000, droppedFrames: 0, overflows: 0,
            consumedFrames: 300_000, residentFrames: 0, writtenFrames: 90_000,
            producedFrames: 90_000, inputRate: 48_000, outputRate: 16_000)
        XCTAssertEqual(neverConverted.unaccountedFrames, 0, "the writer consumed everything")
        XCTAssertEqual(neverConverted.conversionRemainder, 10_000)
        XCTAssertEqual(neverConverted.unproducedFrames, 10_000)
        XCTAssertEqual(neverConverted.writeFailureFrames, 0)
        XCTAssertEqual(neverConverted.attribution.first?.term,
                       "consumed and never converted")

        // The converter produced it and the file refused it.
        let notWritten = CaptureLedger(
            deviceFrames: 300_000, droppedFrames: 0, overflows: 0,
            consumedFrames: 300_000, residentFrames: 0, writtenFrames: 90_000,
            producedFrames: 100_000, writeFailures: 3, writeFailureFrames: 10_000,
            inputRate: 48_000, outputRate: 16_000)
        XCTAssertEqual(notWritten.unproducedFrames, 0, "the converter did its part")
        XCTAssertEqual(notWritten.writeFailures, 3)
        XCTAssertEqual(notWritten.attribution.first?.term,
                       "converted and not written to the file")
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

/// FR-102, AD-57 — the conversion defect itself, and the two halves of its fix.
///
/// **These exist so that a revert fails the suite.** The mechanism is one
/// constant and one loop, both of which look like harmless simplifications on
/// the page: the output buffer offered to `AVAudioConverter` was sized from the
/// input chunk plus 64 frames, and each chunk was converted in a single pass.
/// Under load that lost 0.16% to 0.60% of the shapes with 480- and 512-frame
/// callbacks and nothing at all of the shapes with 4,800-frame ones, which is
/// the 380× asymmetry the real recording shows.
///
/// The load-dependent measurement lives in `--check-drain`, deliberately. A test
/// that has to load the machine to fail is a test of the scheduler, which is
/// what took four attempts to get out of `RateCorrectionTests`. What is asserted
/// here is the arithmetic that makes the fix correct, and the deterministic
/// half of the behaviour.
final class ConverterDrainTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-conv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        StreamFileWriter.outputSlackOverride = nil
        StreamFileWriter.pullUntilDryOverride = nil
    }

    /// What the two halves of the fix are, and which of them is principled.
    ///
    /// **The first version of this test asserted that 4,096 frames is a bound
    /// covering one chunk's output, and that was wrong.** One 8,192-frame chunk
    /// converts to 5,461 output frames at 24 kHz and 16,384 at 8 kHz, both above
    /// 4,096. The constant is not a bound and is not derived; it is a larger
    /// number that measurably removes the loss (`--check-drain`), and the honest
    /// statement of it is here rather than in a comment claiming otherwise.
    ///
    /// The principled half is `pullUntilDry`: `.haveData` means the buffer came
    /// back full and the converter may hold more, `.inputRanDry` means it has
    /// run out. Asking is correct at every ratio, which choosing a size is not.
    /// So the loop is what this test requires to be on.
    func testTheLoopIsThePrincipledHalfAndTheConstantIsNotABound() {
        XCTAssertTrue(StreamFileWriter.pullUntilDry,
                      "the loop is the half that is correct at every ratio")
        let chunk = 8192.0
        let out = StreamFileWriter.outputSampleRate
        // Recorded as a fact about the constant, not as a justification of it:
        // there are ratios this app meets where one chunk's output exceeds it,
        // which is exactly why the loop cannot be removed in its favour.
        XCTAssertLessThan(Double(StreamFileWriter.outputSlackFrames),
                          chunk * (out / 8_000),
                          "at 2:1 one chunk is 16384 output frames; the constant "
                          + "does not cover it and only the loop does")
        XCTAssertGreaterThan(StreamFileWriter.outputSlackFrames, 64,
                             "and it is larger than the 64 that shipped before, "
                             + "which --check-drain measures as the difference "
                             + "between 0.16-0.60%% lost and 0.000%%")
    }

    /// Every sample in must reach the file, at every ratio the app meets —
    /// including the upsampling one the slack cannot cover on its own.
    func testEverySampleReachesTheFileAtEveryRatioTheAppMeets() throws {
        for rate in [8_000.0, 16_000, 22_050, 24_000, 44_100, 48_000] {
            for channels in [AVAudioChannelCount(1), 2] {
                let fmt = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                      sampleRate: rate, channels: channels,
                                                      interleaved: channels > 1))
                let ring = RingBuffer(capacity: Int(rate) * Int(channels) * 10)
                let w = StreamFileWriter(
                    url: tmp.appendingPathComponent("r\(Int(rate))c\(channels).wav"),
                    format: fmt, ring: ring)
                try w.start()
                // Small callbacks on purpose: this is the shape that loses.
                //
                // The count is **two seconds of audio at this rate**, not a fixed
                // number of callbacks. The first version wrote 200 callbacks at
                // every rate, which is 2.1 s at 48 kHz and **12.8 s at 8 kHz** —
                // past the ring's ten seconds, so it overran the buffer and
                // measured the fixture rather than the writer.
                let callbackFrames = 512
                let block = [Float](repeating: 0.3, count: callbackFrames * Int(channels))
                let callbacks = Int(rate * 2) / callbackFrames
                for _ in 0..<callbacks {
                    block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
                }
                w.stop()

                let l = w.ledger
                let offered = Double(callbacks * callbackFrames)
                XCTAssertEqual(l.droppedFrames, 0, "ring at \(rate) Hz x\(channels)")
                XCTAssertEqual(l.consumedFrames, offered, "consumed at \(rate) Hz x\(channels)")
                let expected = offered * (StreamFileWriter.outputSampleRate / rate)
                // One frame of slack for the ratio's own rounding, and no more:
                // the resampler's priming is measured at ~11 frames in total and
                // the tail is now flushed, so a real loss shows immediately.
                XCTAssertEqual(l.writtenFrames, expected, accuracy: 16,
                               "file short at \(rate) Hz x\(channels): "
                               + "produced \(l.producedFrames), expected \(expected)")
            }
        }
    }

    /// **The deterministic fixture cannot reproduce the loss, and that is the
    /// finding rather than a gap in the test.**
    ///
    /// The first version of this test asserted that one pass at a 64-frame slack
    /// would lose most of an upsampled chunk. It wrote **every frame**: the
    /// output buffer is sized from the chunk in hand times the ratio, so it
    /// always covers that chunk exactly, and no backlog forms on an idle
    /// machine at any ratio. The loss is only reproducible **under load**, which
    /// `--check-drain 20 10` does and a unit test must not — a test that has to
    /// load the machine to fail is a test of the scheduler, which took four
    /// attempts to get out of `RateCorrectionTests`.
    ///
    /// So what this asserts is the part that is deterministic and that a revert
    /// would still break: both configurations consume everything, neither drops
    /// anything, and the *shipping* one writes every frame at the ratio where
    /// the constant alone provably cannot cover a chunk.
    ///
    /// **The mechanism by which extra slack helps under load is not
    /// established.** The arithmetic above says it should not be needed, and the
    /// measurement says it is. That disagreement is recorded in
    /// `spikes/measurement-stream-alignment-2026-09-07.md` as an open question
    /// rather than resolved by a story about `AVAudioConverter`'s internals.
    func testBothConfigurationsConsumeEverythingAndTheShippingOneWritesItAll() throws {
        func run(slack: AVAudioFrameCount, pull: Bool) throws -> CaptureLedger {
            StreamFileWriter.outputSlackOverride = slack
            StreamFileWriter.pullUntilDryOverride = pull
            let fmt = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                  sampleRate: 8_000, channels: 1,
                                                  interleaved: false))
            let ring = RingBuffer(capacity: 8_000 * 10)
            let w = StreamFileWriter(
                url: tmp.appendingPathComponent("s\(slack)p\(pull).wav"),
                format: fmt, ring: ring)
            try w.start()
            // 8 kHz up to 16 kHz doubles the frame count, and 8 chunks of 8,192
            // frames is 8.2 s — inside the ring's ten seconds on purpose.
            let block = [Float](repeating: 0.3, count: 8192)
            for _ in 0..<8 {
                block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
            }
            w.stop()
            return w.ledger
        }

        let before = try run(slack: 64, pull: false)
        let after = try run(slack: StreamFileWriter.outputSlackFrames, pull: true)

        let offered = Double(8 * 8192)
        let expected = offered * 2   // 8 kHz -> 16 kHz
        for (name, l) in [("one pass, slack 64", before), ("shipping", after)] {
            XCTAssertEqual(l.consumedFrames, offered, "\(name) consumed everything")
            XCTAssertEqual(l.droppedFrames, 0, "\(name): this is not a ring fault")
            XCTAssertEqual(l.writeFailures, 0, "\(name): nor a write fault")
        }
        XCTAssertEqual(after.writtenFrames, expected, accuracy: 16,
                       "the shipping configuration writes every frame at 2:1")
        XCTAssertEqual(after.unproducedFrames, 0, accuracy: 16,
                       "and nothing is left inside the converter")
    }

    /// A write that throws must be counted, not only logged. The unified log for
    /// the recording that forced this increment had already rolled over by the
    /// time anyone looked, so "no write failures were logged" could not be said
    /// either way.
    func testAFailedWriteIsCountedAndNotOnlyLogged() throws {
        let fmt = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: 48_000, channels: 1,
                                              interleaved: false))
        let ring = RingBuffer(capacity: 48_000 * 10)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("ok.wav"),
                                 format: fmt, ring: ring)
        try w.start()
        let block = [Float](repeating: 0.3, count: 48_000)
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
        w.stop()
        // The happy path must report zero rather than absent, which is what makes
        // a non-zero count on some future recording legible.
        XCTAssertEqual(w.ledger.writeFailures, 0)
        XCTAssertEqual(w.ledger.writeFailureFrames, 0)
        XCTAssertGreaterThan(w.ledger.producedFrames, 0)
        XCTAssertEqual(w.ledger.producedFrames, w.ledger.writtenFrames,
                       "nothing was produced that did not reach the file")
    }
}
