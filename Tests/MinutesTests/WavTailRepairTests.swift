import XCTest
import AVFoundation
@testable import Minutes

/// FR-9, FR-107. A WAV's length is written on close, so a Session that ended
/// because the process died leaves every sample on disk under a header claiming
/// zero bytes. Five Meetings were stuck at `captured` for exactly this reason.
final class WavTailRepairTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    /// A correctly closed 16 kHz mono recording of a given length.
    private func write(seconds: Double, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings,
                                commonFormat: .pcmFormatFloat32, interleaved: false)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 16_000, channels: 1, interleaved: false)!
        let n = AVAudioFrameCount(16_000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
        buf.frameLength = n
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(n) {
            let t: Double = Double(i) / 16_000.0
            let v: Double = 0.4 * sin(2.0 * Double.pi * 440.0 * t)
            ch[i] = Float(v)
        }
        try f.write(from: buf)
    }

    /// Zeroes the two size fields, which is exactly what a process death leaves
    /// behind: samples present, header claiming none.
    private func breakHeader(_ url: URL) throws {
        let h = try FileHandle(forUpdating: url)
        defer { try? h.close() }
        let head = try h.read(upToCount: 8192)!
        // Walk to the data chunk rather than assuming offset 40 — AVAudioFile
        // does not always write a 44-byte canonical header.
        var pos = 12
        var dataSizeOffset: Int?
        while pos + 8 <= head.count {
            let id = head[pos..<(pos + 4)]
            var size = 0
            for b in (0..<4).reversed() { size = size << 8 | Int(head[pos + 4 + b]) }
            if id == Data("data".utf8) { dataSizeOffset = pos + 4; break }
            guard size > 0 else { break }
            pos += 8 + size + (size & 1)
        }
        let off = try XCTUnwrap(dataSizeOffset, "no data chunk in the fixture")
        try h.seek(toOffset: UInt64(off))
        try h.write(contentsOf: Data([0, 0, 0, 0]))
        try h.seek(toOffset: 4)
        try h.write(contentsOf: Data([0, 0, 0, 0]))
    }

    private func readableSeconds(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.fileFormat.sampleRate
    }

    // MARK: - The fault, and the repair

    func testAnUnclosedRecordingIsUnreadableBeforeTheRepair() throws {
        let url = tmp.appendingPathComponent("a.wav")
        try write(seconds: 5, to: url)
        XCTAssertEqual(try readableSeconds(url), 5.0, accuracy: 0.01)

        try breakHeader(url)
        // `AVAudioFile` refuses to open it at all rather than reporting zero
        // length — which is exactly the "Invalid audio data provided" the five
        // real Meetings carried, arriving one layer further in.
        XCTAssertThrowsError(try readableSeconds(url),
                             "this is the state five real Meetings were in")
    }

    func testTheRepairMakesEverySampleReadableAgain() throws {
        let url = tmp.appendingPathComponent("b.wav")
        try write(seconds: 5, to: url)
        let before = try Data(contentsOf: url)
        try breakHeader(url)

        let a = try XCTUnwrap(WavTailRepair.repair(url))
        XCTAssertEqual(a.declaredDataBytes, 0)
        XCTAssertEqual(a.recoverableSeconds, 5.0, accuracy: 0.01)
        XCTAssertEqual(try readableSeconds(url), 5.0, accuracy: 0.01)

        // And it restored the file byte for byte, which is the strongest form of
        // "no sample was touched".
        XCTAssertEqual(try Data(contentsOf: url), before,
                       "the repair changed something other than the two size fields")
    }

    func testTheRepairChangesEightBytesAndNoSample() throws {
        let url = tmp.appendingPathComponent("c.wav")
        try write(seconds: 3, to: url)
        let good = try Data(contentsOf: url)
        try breakHeader(url)
        let broken = try Data(contentsOf: url)
        try WavTailRepair.repair(url)
        let fixed = try Data(contentsOf: url)

        XCTAssertEqual(fixed.count, broken.count, "the file changed length")
        let differences = zip(broken, fixed).filter { $0 != $1 }.count
        XCTAssertLessThanOrEqual(differences, 8, "more than the two size fields moved")
        XCTAssertEqual(fixed, good)
    }

    func testACorrectRecordingIsLeftCompletelyAlone() throws {
        let url = tmp.appendingPathComponent("d.wav")
        try write(seconds: 2, to: url)
        let before = try Data(contentsOf: url)
        XCTAssertNil(try WavTailRepair.repair(url), "nothing to repair must report nothing")
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testARepairIsIdempotent() throws {
        let url = tmp.appendingPathComponent("e.wav")
        try write(seconds: 2, to: url)
        try breakHeader(url)
        XCTAssertNotNil(try WavTailRepair.repair(url))
        XCTAssertNil(try WavTailRepair.repair(url),
                     "a second pass must find nothing — this is what stops resume looping")
    }

    // MARK: - What it must refuse

    /// A header claiming *more* than the file holds is a truncated file, which is
    /// a different fault. Raising its claim would feed whatever follows the audio
    /// to the transcriber as speech.
    func testAHeaderClaimingMoreThanThefileHoldsIsNotTouched() throws {
        let url = tmp.appendingPathComponent("f.wav")
        try write(seconds: 4, to: url)
        // Truncate the audio, leaving the header claiming the original length.
        let d = try Data(contentsOf: url)
        try d.prefix(d.count - 32_000).write(to: url)
        let before = try Data(contentsOf: url)

        let a = try WavTailRepair.assess(url)
        XCTAssertFalse(a.needsRepair, "an over-claiming header must not be 'repaired'")
        XCTAssertNil(try WavTailRepair.repair(url))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testAPartialFrameIsRoundedDownRatherThanRecovered() throws {
        let url = tmp.appendingPathComponent("g.wav")
        try write(seconds: 1, to: url)
        try breakHeader(url)
        // One stray byte, as a process killed mid-write would leave.
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data([0x7F]))
        try h.close()

        let a = try XCTUnwrap(WavTailRepair.repair(url))
        XCTAssertEqual(a.actualDataBytes % a.bytesPerFrame, 0,
                       "half a sample is not audio")
        XCTAssertEqual(try readableSeconds(url), 1.0, accuracy: 0.01)
    }

    func testSomethingThatIsNotAWaveFileIsRejectedNotGuessedAt() throws {
        let url = tmp.appendingPathComponent("h.wav")
        try Data(repeating: 0x41, count: 4096).write(to: url)
        XCTAssertThrowsError(try WavTailRepair.assess(url))
        XCTAssertThrowsError(try WavTailRepair.repair(url))
    }

    func testAnEmptyRecordingHasNothingToRecover() throws {
        let url = tmp.appendingPathComponent("i.wav")
        try write(seconds: 0.001, to: url)
        try breakHeader(url)
        // The header-only case: two of the five real Meetings were 4,096 bytes
        // with no audio at all, and the repair must not invent any.
        let a = try WavTailRepair.assess(url)
        XCTAssertLessThan(a.recoverableSeconds, 0.05)
    }

    // MARK: - The live stamp, which is what stops this happening again

    /// The writer stamps the length as it goes, so a killed process leaves a file
    /// readable by *anything*, not only by a Minutes that knows to repair it.
    ///
    /// Driven with an audio clock and **realistic callback sizes**, because both
    /// matter and neither is obvious. Nothing reaches the file until the rate
    /// settles (AD-44), and the clock only becomes decisive once the span is
    /// about 26 callbacks long — `tolerance` is one callback's host time over the
    /// span measured. A first version of this test used 16,000-frame callbacks,
    /// which put the tolerance at 0.125 against a `decisiveTolerance` of 0.044,
    /// so the rate never settled, nothing was ever written, and the test read
    /// 0 s for a reason that had nothing to do with the header.
    func testAWriterKilledMidRecordingLeavesAReadableFile() throws {
        let url = tmp.appendingPathComponent("live.wav")
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 16_000, channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: url, format: fmt, ring: ring)
        let clock = AudioClockTap()
        w.clock = clock
        try w.start()

        let callback: Int = 1024                    // 64 ms, as a real device delivers
        var tone = [Float](repeating: 0, count: callback)
        for i in 0..<callback {
            let t: Double = Double(i) / 16_000.0
            let v: Double = 0.4 * sin(2.0 * Double.pi * 440.0 * t)
            tone[i] = Float(v)
        }

        let callbacks: Int = 200                    // 12.8 s of audio
        var sampleTime: Double = 0
        for n in 0..<callbacks {
            tone.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: callback) }
            sampleTime += Double(callback)
            let hostSeconds: Double = Double(n + 1) * Double(callback) / 16_000.0
            clock.record(sampleTime: sampleTime,
                         hostTime: AudioClockTap.hostTime(fromSeconds: hostSeconds),
                         frames: callback)
            let d = Date().addingTimeInterval(5)
            while ring.count > (1 << 19), Date() < d { usleep(5_000) }
        }
        // The audio must actually be reaching the file, or this measures nothing.
        let drained = Date().addingTimeInterval(10)
        while w.framesWritten == 0, Date() < drained { usleep(20_000) }
        XCTAssertGreaterThan(w.framesWritten, 0,
                             "the rate never settled, so this test proves nothing")

        // Now wait out the stamp interval, polling rather than sleeping blind.
        let deadline = Date().addingTimeInterval(20)
        var readable: Double = 0
        while Date() < deadline {
            readable = (try? readableSeconds(url)) ?? 0
            if readable > 1 { break }
            usleep(100_000)
        }

        // Read the file *without* stopping the writer: this is the crash case.
        XCTAssertGreaterThan(readable, 1.0,
            "a recording in progress reads as \(readable)s; a crash now would leave a file nothing can open")
        let stamped = readable
        w.stop()
        XCTAssertGreaterThanOrEqual(try readableSeconds(url), stamped,
                                    "the proper close lost what the stamp had already claimed")
    }
}
