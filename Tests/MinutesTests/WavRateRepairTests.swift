import XCTest
import Foundation
import AVFoundation
@testable import Minutes

/// FR-88 — assessing and repairing a recording already on disk.
///
/// The seven real recordings were repaired from a terminal before any of this
/// code existed. These tests are what make that repeatable for the next person.
final class WavRateRepairTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    /// `dir` is nil when `setUpWithError` skipped, and `URL!` force-unwraps on
    /// use — so this crashed the whole XCTest process on every plain `swift test`,
    /// taking every suite alphabetically after this one with it. 173 of 306 tests
    /// ran. The gate was doing its job and the teardown was not.
    override func tearDownWithError() throws {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a 16-bit mono WAV declaring `rate` and holding `frames` samples,
    /// through `AVAudioFile` — the same writer the app uses, so the header layout
    /// under test is the real one rather than one this test invented.
    private func writeWav(named name: String, rate: Double, frames: Int) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings,
                                commonFormat: .pcmFormatFloat32, interleaved: false)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                channels: 1, interleaved: false)!
        var remaining = frames
        while remaining > 0 {
            let n = min(remaining, 16_384)
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
            buf.frameLength = AVAudioFrameCount(n)
            let ch = buf.floatChannelData![0]
            for i in 0..<n { ch[i] = sinf(Float(remaining + i) * 0.05) * 0.4 }
            try f.write(from: buf)
            remaining -= n
        }
        return url
    }

    func testReadsAHeaderWithoutReadingTheAudio() throws {
        let url = try writeWav(named: "a.wav", rate: 16_000, frames: 16_000 * 5)
        let h = try WavRateRepair.header(of: url)
        XCTAssertEqual(h.declaredRate, 16_000)
        XCTAssertEqual(h.channels, 1)
        XCTAssertEqual(h.bitsPerSample, 16)
        XCTAssertEqual(h.frames, 16_000 * 5)
    }

    /// The real shape: a file declaring 16 kHz whose samples cover a 15-second
    /// session at one third the rate. This is `20260903-103103-y774` in miniature.
    func testDetectsAThreeTimesTooFastRecording() throws {
        let session: TimeInterval = 15
        let url = try writeWav(named: "fast.wav", rate: 16_000, frames: Int(16_000 / 3 * session))
        let f = try WavRateRepair.fidelity(of: url, sessionDuration: session)
        XCTAssertEqual(f.ratio, 3, accuracy: 0.02)
        XCTAssertFalse(f.isTrustworthy)
        XCTAssertEqual(f.integerRatio, 3)
    }

    func testACorrectRecordingIsLeftAlone() throws {
        let session: TimeInterval = 15
        let url = try writeWav(named: "ok.wav", rate: 16_000, frames: Int(16_000 * session))
        let f = try WavRateRepair.fidelity(of: url, sessionDuration: session)
        XCTAssertTrue(f.isTrustworthy)
        XCTAssertThrowsError(try WavRateRepair.repair(url, sessionDuration: session),
                             "a sound recording must not be 'repaired'")
    }

    /// The whole point of the header-only approach: the samples are untouched, so
    /// nothing is lost and the change is reversible.
    func testRepairChangesTheHeaderAndNotOneSample() throws {
        let session: TimeInterval = 15
        let url = try writeWav(named: "fix.wav", rate: 16_000, frames: Int(16_000 / 2 * session))

        let before = try Data(contentsOf: url)
        let h0 = try WavRateRepair.header(of: url)
        let audioBefore = before[h0.formatOffset...]     // includes the data chunk

        let change = try WavRateRepair.repair(url, sessionDuration: session)
        XCTAssertEqual(change.was, 16_000)
        XCTAssertEqual(change.now, 8_000)

        let after = try Data(contentsOf: url)
        XCTAssertEqual(before.count, after.count, "the file must not change size")

        let h1 = try WavRateRepair.header(of: url)
        XCTAssertEqual(h1.declaredRate, 8_000)
        XCTAssertEqual(h1.frames, h0.frames, "no sample was added or removed")

        // Byte-for-byte identical outside the two rate fields.
        //
        // The count is bounded rather than fixed at eight: 16000 -> 8000 and
        // 32000 -> 16000 happen to share their low bytes, so only four bytes
        // actually differ. *Where* they differ is the property worth asserting —
        // a repair that touched one sample would show up outside this range.
        var differing: [Int] = []
        for i in 0..<before.count where before[i] != after[i] { differing.append(i) }
        let rateFields = (h0.formatOffset + 4)..<(h0.formatOffset + 12)
        XCTAssertFalse(differing.isEmpty, "the header must actually change")
        XCTAssertLessThanOrEqual(differing.count, 8, "changed \(differing)")
        for i in differing {
            XCTAssertTrue(rateFields.contains(i),
                          "byte \(i) is outside the fmt chunk's rate fields — a sample was touched")
        }
        XCTAssertEqual(before[rateFields.upperBound...], after[rateFields.upperBound...],
                       "every byte after the rate fields, including all audio, must be identical")
        _ = audioBefore
    }

    /// After repair the file reads back at the right speed — the property that
    /// makes the transcript correct, asserted through `AVAudioFile` rather than
    /// through our own header parser.
    func testAfterRepairTheFileReportsTheRightDuration() throws {
        let session: TimeInterval = 15
        let url = try writeWav(named: "dur.wav", rate: 16_000, frames: Int(16_000 / 3 * session))

        let wrong = try AVAudioFile(forReading: url)
        let wrongSeconds = Double(wrong.length) / wrong.fileFormat.sampleRate
        XCTAssertEqual(wrongSeconds, session / 3, accuracy: 0.2, "before: three times too fast")

        try WavRateRepair.repair(url, sessionDuration: session)

        let right = try AVAudioFile(forReading: url)
        let rightSeconds = Double(right.length) / right.fileFormat.sampleRate
        XCTAssertEqual(rightSeconds, session, accuracy: 0.2, "after: real time")
    }

    /// Refusing to guess. A ratio that is not a whole number is a different
    /// defect, and repairing it would resample a recording on an assumption.
    func testRefusesToRepairANonIntegerRatio() throws {
        let session: TimeInterval = 15
        let url = try writeWav(named: "odd.wav", rate: 16_000, frames: Int(16_000 / 2.4 * session))
        XCTAssertThrowsError(try WavRateRepair.repair(url, sessionDuration: session)) { e in
            guard case WavRateRepair.RepairError.rateNotRecoverable = e else {
                return XCTFail("expected rateNotRecoverable, got \(e)")
            }
            XCTAssertTrue((e as? LocalizedError)?.errorDescription?.contains("guessing") ?? false)
        }
    }

    func testRejectsAFileThatIsNotAWave() throws {
        let url = dir.appendingPathComponent("not.wav")
        try Data("this is not a wave file at all, not even close".utf8).write(to: url)
        XCTAssertThrowsError(try WavRateRepair.header(of: url))
    }
}

/// AD-44 through the real writer: does a stream that receives samples at a rate
/// other than its declared one actually notice?
///
/// This is the test that would have caught the original defect. It drives
/// `StreamFileWriter` exactly as the IOProc does — floats into the ring — while
/// lying to it about the rate, which is precisely what CoreAudio did.
final class StreamFileWriterRateTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Feeds `seconds` of audio at `actualRate` into a writer told it is receiving
    /// `declaredRate`, and returns what the writer concluded.
    private func run(declaredRate: Double, actualRate: Double,
                     seconds: TimeInterval) throws -> RateFidelity {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: declaredRate,
                                channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: Int(declaredRate) * 4)
        let w = StreamFileWriter(url: dir.appendingPathComponent("s.wav"), format: fmt, ring: ring)

        // AD-51. These used to be paced by `usleep` and measured against
        // `Date()`, which passed in isolation and failed inside the full suite —
        // the same wall-clock sensitivity that put `RateCorrectionTests` behind
        // an environment variable, in the two tests that were hidden behind the
        // crash the gate caused. The device's own timestamps make it arithmetic:
        // the sleeps below now only pace the *ring*, and the measurement does
        // not depend on how well they held.
        let clock = AudioClockTap()
        w.clock = clock
        try w.start()

        let chunks = 40
        let framesPerChunk = Int(actualRate * seconds) / chunks
        var block = [Float](repeating: 0, count: framesPerChunk)
        for i in 0..<framesPerChunk { block[i] = sinf(Float(i) * 0.05) * 0.4 }
        for c in 0..<chunks {
            clock.record(sampleTime: Double(c * framesPerChunk),
                         hostTime: AudioClockTap.hostTime(
                            fromSeconds: 5_000 + Double(c) * seconds / Double(chunks)),
                         frames: framesPerChunk)
            block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: framesPerChunk) }
            var spun = 0
            while ring.count > 0, spun < 2000 { usleep(200); spun += 1 }
        }
        // Let the drain thread consume the tail before reading the counters.
        let deadline = Date().addingTimeInterval(2)
        while ring.count > 0, Date() < deadline { usleep(20_000) }
        usleep(50_000)
        let f = w.rateFidelity
        w.stop()
        return f
    }

    /// **The device is the authority on the rate and not on whether the recording
    /// gets written.** A device delivering very large buffers takes proportionally
    /// longer to narrow its tolerance; if it never narrows it, AD-44's "nothing
    /// reaches the file until the rate has settled" turns into "nothing reaches
    /// the file", and two hours of held audio is about four gigabytes that a
    /// crash loses entirely — which is what FR-9's incremental commit exists to
    /// prevent.
    func testAnUndecidableDeviceClockDoesNotHoldTheRecordingForEver() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 16_000 * 20)
        let url = dir.appendingPathComponent("patience.wav")
        let w = StreamFileWriter(url: url, format: fmt, ring: ring)
        let clock = AudioClockTap()
        w.clock = clock
        try w.start()

        // One enormous callback per second: two ticks make the clock *usable*
        // and its tolerance stays around 100%, so it can never decide.
        var block = [Float](repeating: 0, count: 16_000)
        for i in 0..<block.count { block[i] = sinf(Float(i) * 0.05) * 0.4 }
        for c in 0..<9 {
            clock.record(sampleTime: Double(c * 16_000),
                         hostTime: AudioClockTap.hostTime(fromSeconds: 9_000 + Double(c)),
                         frames: 16_000)
            block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
            var spun = 0
            while ring.count > 0, spun < 4000 { usleep(200); spun += 1 }
            // The wall clock has to actually pass for the patience bound to fire.
            usleep(900_000)
        }
        XCTAssertFalse(clock.snapshot.isDecisive, "the fixture must be undecidable")
        w.stop()

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertGreaterThan(seconds, 5,
                             "the held opening reached the file, \(seconds)s of it")
    }

    /// With no timestamps from the device, the wall clock is still there and
    /// still the thing that caught the original defect. Absent is a fallback,
    /// not a downgrade (AD-51).
    func testAWriterWithNoDeviceTimestampsFallsBackToTheWallClock() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 16_000 * 4)
        let w = StreamFileWriter(url: dir.appendingPathComponent("nodev.wav"),
                                 format: fmt, ring: ring)
        try w.start()
        var block = [Float](repeating: 0.2, count: 4_000)
        for i in 0..<block.count { block[i] = sinf(Float(i) * 0.05) * 0.4 }
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
        let deadline = Date().addingTimeInterval(2)
        while ring.count > 0, Date() < deadline { usleep(20_000) }
        let f = w.rateFidelity
        w.stop()
        XCTAssertEqual(f.source, .wallClock)
        XCTAssertEqual(f.appliedTolerance, RateFidelity.tolerance)
    }

    /// **The defect, reproduced through the real writer.** A stream told it is
    /// receiving 48 kHz while frames arrive at 16 kHz — the measured ratio-3 case.
    func testAWriterNoticesSamplesArrivingAtAThirdOfTheDeclaredRate() throws {
        let f = try run(declaredRate: 48_000, actualRate: 16_000, seconds: 4)
        XCTAssertEqual(f.declaredRate, 48_000)
        XCTAssertEqual(f.observedRate, 16_000, accuracy: 2_500,
                       "observed \(f.observedRate); the writer must see the real rate")
        XCTAssertEqual(f.ratio, 3, accuracy: 0.35)
        // Updated when the correction landed. This used to assert the stream was
        // untrustworthy and carried an explanation, which was the right contract
        // while the app could only *detect* the disagreement. Now that it
        // corrects the converter, a noticed stream is a fixed stream — so the
        // assertion moves to that, and the untrustworthy path is asserted where
        // it still applies: a rate no real device uses
        // (`testANonStandardObservedRateIsRefusedRatherThanGuessed`).
        XCTAssertEqual(f.correctedTo, 16_000, "noticing it means fixing it")
        XCTAssertTrue(f.isTrustworthy)
        XCTAssertNil(f.explanation, "nothing to warn about once the file is right")
    }

    /// And the same writer must not cry wolf when the rate is right. Run at the
    /// same duration and chunking, so the only difference is the rate itself.
    func testAWriterAtTheRightRateReportsNoProblem() throws {
        let f = try run(declaredRate: 16_000, actualRate: 16_000, seconds: 4)
        XCTAssertEqual(f.ratio, 1, accuracy: 0.12,
                       "observed \(f.observedRate) against declared \(f.declaredRate)")
        XCTAssertTrue(f.isTrustworthy)
        XCTAssertNil(f.explanation)
    }

    /// The callback fires once, not per drained chunk. A hundred identical errors
    /// is noise; one is information.
    func testTheDisagreementIsReportedExactlyOnce() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 48_000 * 4)
        let w = StreamFileWriter(url: dir.appendingPathComponent("once.wav"), format: fmt, ring: ring)
        let counter = Counter()
        w.onRateDisagreement = { _ in counter.bump() }
        let clock = AudioClockTap()
        w.clock = clock
        try w.start()

        // 8000 frames per callback delivered every 0.5 s is 16 kHz against a
        // declared 48 kHz — the ratio-3 case, stated in timestamps rather than
        // paced by sleeps.
        var block = [Float](repeating: 0.3, count: 8_000)
        for i in 0..<block.count { block[i] = sinf(Float(i) * 0.05) * 0.4 }
        for c in 0..<40 {
            clock.record(sampleTime: Double(c * 8_000),
                         hostTime: AudioClockTap.hostTime(fromSeconds: 7_000 + Double(c) * 0.5),
                         frames: 8_000)
            block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: block.count) }
            var spun = 0
            while ring.count > 0, spun < 2000 { usleep(200); spun += 1 }
        }
        let deadline = Date().addingTimeInterval(2)
        while ring.count > 0, Date() < deadline { usleep(20_000) }
        usleep(50_000)
        w.stop()

        XCTAssertEqual(counter.value, 1, "reported \(counter.value) times")
    }

    /// Thread-safe counter: the callback fires on the writer's drain thread.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
}

/// AD-44's *prevention*, as opposed to its detection.
///
/// Detecting a wrong rate leaves the recording ruined and merely honest about it.
/// These assert the thing that actually matters: with the device delivering at a
/// rate other than the one it declared, the **file on disk comes out right**.
///
/// **These were opt-in behind `MINUTES_RATE_TIMING=1`, and increment 10 took the
/// gate off.** The reason they were gated is worth keeping, because it is the
/// argument for Story 16.9 in miniature. The writer measured its rate against
/// `Date()`, so the measurement was only ever as good as the machine's pacing:
/// eight runs out of eight passed in isolation, about one in three failed inside
/// the full suite, and a later isolated run failed too. Four attempts at a
/// deterministic harness are recorded in `capture` below; the best passed
/// reliably and took three minutes, and the rest failed *deterministically* for
/// arithmetic reasons that only hold when one drain equals one chunk —
/// `drainOnce` reads up to 8192 samples per wake, so the writer's baseline can
/// land mid-chunk and frames-consumed is not predictable from the chunk index.
///
/// None of that was a flaw in what they assert. It was the wall clock, and
/// AD-51 replaced it: the device supplies its own sample-time and host-time
/// counters, so `capture` now hands the writer an exact pair per callback and
/// the measurement has no pacing in it at all. The `now` seam is still here for
/// the wall-clock fallback, and is no longer load-bearing.
///
/// The gate had one honest property worth restating: it did not loosen an
/// assertion until it could not fail, and it did not leave a suite that cries
/// wolf one run in three. It cost a hidden crash instead — `tearDownWithError`
/// force-unwrapped the directory a skipped `setUp` never created, which took the
/// whole XCTest process down on every plain `swift test` and stopped 133 of the
/// 306 tests from running at all. A gate is a liability that has to be
/// maintained; removing the need for it is the fix.
final class RateCorrectionTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Feeds `seconds` of audio at `actualRate` into a writer told `declaredRate`,
    /// and returns the duration of the file that resulted plus what the writer
    /// concluded about the rate.
    private func capture(declaredRate: Double, actualRate: Double,
                         seconds: TimeInterval, name: String)
        throws -> (fileSeconds: Double, fidelity: RateFidelity) {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: declaredRate,
                                channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: Int(max(declaredRate, actualRate)) * 12)
        let url = dir.appendingPathComponent(name)
        let w = StreamFileWriter(url: url, format: fmt, ring: ring)

        // The wall-clock seam is still installed, because the writer still uses
        // it wherever a device supplies no timestamps. It is no longer what this
        // test measures.
        let origin = Date()
        let elapsed = ElapsedClock()
        w.now = { origin.addingTimeInterval(elapsed.value) }

        // AD-51: the device's own account, driven by hand. Every tick is an
        // exact pair — the sample counter at that buffer, and the host clock at
        // the same instant — so the ratio the writer computes is arithmetic on
        // two numbers this test chose. There is no pacing in it and no `usleep`
        // it can be wrong about, which is what took the gate off.
        let clock = AudioClockTap()
        w.clock = clock

        try w.start()

        // A realistic cadence. A real tap delivers roughly every 170 ms at 48 kHz,
        // and it still matters here: `largestTick` is one callback's frames and
        // it sets how quickly the measurement's own tolerance narrows past
        // `AudioClock.decisiveTolerance`. A producer that dumps a second at a
        // time would take far longer to become decisive, which is a real
        // property of the mechanism rather than an artefact.
        let chunks = max(12, Int(seconds / 0.15))
        let framesPerChunk = Int(actualRate * seconds) / chunks
        var block = [Float](repeating: 0, count: framesPerChunk)
        for i in 0..<framesPerChunk { block[i] = sinf(Float(i) * 0.05) * 0.4 }

        let tick = seconds / Double(chunks)
        for c in 0..<chunks {
            // The device reports where its own counter stands *before* handing
            // the samples over, which is the order a real callback arrives in.
            clock.record(sampleTime: Double(c * framesPerChunk),
                         hostTime: AudioClockTap.hostTime(
                            fromSeconds: 1_000 + Double(c) * tick),
                         frames: framesPerChunk)
            block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: framesPerChunk) }
            var spun = 0
            while ring.count > 0, spun < 2000 { usleep(200); spun += 1 }
            elapsed.advance(by: tick)
        }
        // The writer's own settle happens on a drain; give it one more.
        usleep(50_000)
        let f = w.rateFidelity
        w.stop()

        let file = try AVAudioFile(forReading: url)
        return (Double(file.length) / file.fileFormat.sampleRate, f)
    }

    /// **The defect, prevented.** A device delivering 16 kHz while declaring
    /// 48 kHz used to produce a file three times too fast. The file must now hold
    /// the real elapsed time.
    func testAThreeTimesWrongDeclaredRateStillProducesACorrectFile() throws {
        let seconds: TimeInterval = 5
        let r = try capture(declaredRate: 48_000, actualRate: 16_000,
                            seconds: seconds, name: "corrected.wav")
        XCTAssertEqual(r.fileSeconds, seconds, accuracy: 1.0,
                       "the file is \(r.fileSeconds)s for \(seconds)s of audio")
        XCTAssertEqual(r.fidelity.correctedTo, 16_000, "and it says it corrected itself")
        XCTAssertTrue(r.fidelity.isTrustworthy, "a corrected recording is trustworthy")
        XCTAssertNil(r.fidelity.explanation, "so there is nothing to warn the user about")
    }

    /// The ratio-2 case, which is five of the seven real recordings.
    func testATwiceWrongDeclaredRateStillProducesACorrectFile() throws {
        let seconds: TimeInterval = 5
        let r = try capture(declaredRate: 48_000, actualRate: 24_000,
                            seconds: seconds, name: "corrected2.wav")
        XCTAssertEqual(r.fileSeconds, seconds, accuracy: 1.0)
        XCTAssertEqual(r.fidelity.correctedTo, 24_000)
    }

    /// And a device behaving correctly must be left entirely alone — no
    /// correction, no warning, and the same duration as before.
    func testACorrectDeviceIsNotTouched() throws {
        let seconds: TimeInterval = 5
        let r = try capture(declaredRate: 16_000, actualRate: 16_000,
                            seconds: seconds, name: "untouched.wav")
        XCTAssertEqual(r.fileSeconds, seconds, accuracy: 1.0)
        XCTAssertNil(r.fidelity.correctedTo, "nothing to correct")
        XCTAssertTrue(r.fidelity.isTrustworthy)
    }

    /// A rate no real device uses is the case the app must not guess at: it keeps
    /// the declared rate, so the file is wrong, and AD-45 refuses to build on it.
    func testANonStandardObservedRateIsRefusedRatherThanGuessed() throws {
        let seconds: TimeInterval = 5
        // 48000 / 3.5 = 13714 Hz. Deliberately *mid-way* between whole-number
        // factors: 3.5 is 12.5% from both 3 and 4, and 13714 Hz is more than
        // 14% from every standard rate. The first version used 3.7, which sits
        // inside a hair of the 5% window around 4 — so a 3% measurement wobble
        // flipped it to "correctable" and the test blamed the code.
        let r = try capture(declaredRate: 48_000, actualRate: 13_714,
                            seconds: seconds, name: "weird.wav")
        XCTAssertNil(r.fidelity.correctedTo, "guessing here would hide a different defect")
        XCTAssertFalse(r.fidelity.isTrustworthy)
        XCTAssertNotNil(r.fidelity.explanation, "and the user is told")
    }

    /// A capture shorter than the settling period must still produce a file. The
    /// held opening is written when stop forces the decision — without that, a
    /// five-second Test Playground recording would come out empty.
    func testAShortCaptureStillWritesItsAudio() throws {
        let seconds: TimeInterval = 1.5
        let r = try capture(declaredRate: 16_000, actualRate: 16_000,
                            seconds: seconds, name: "short.wav")
        XCTAssertGreaterThan(r.fileSeconds, 0.5, "the held opening must reach the file")
    }
}


/// A clock the test advances by hand.
///
/// Locked because the writer reads it from its drain thread while the test
/// advances it, and a data race here would be a flaky test about flaky tests.
private final class ElapsedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double = 0

    var value: Double {
        lock.lock(); defer { lock.unlock() }
        return seconds
    }

    func advance(by delta: Double) {
        lock.lock(); defer { lock.unlock() }
        seconds += delta
    }
}
