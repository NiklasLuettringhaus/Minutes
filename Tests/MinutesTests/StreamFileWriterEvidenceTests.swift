import XCTest
import AVFoundation
@testable import Minutes

/// The wiring behind AD-36, which `AudioEvidenceTests` does not reach.
///
/// This suite exists because of a specific gap found in review: every test of
/// the *rule* passed while `StreamFileWriter` still reported the decaying UI
/// meter as its evidence. Reverting one line — `peak: peakEver` back to
/// `peak: peak` — reintroduced the original defect and the whole suite stayed
/// green. These tests fail on that revert, which is the only reason they are
/// worth having.
final class StreamFileWriterEvidenceTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Feeds a writer real samples through the real ring buffer, then stops it —
    /// no audio device involved.
    private func run(_ blocks: [[Float]], sampleRate: Double = 48_000) throws -> AudioEvidence {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: sampleRate, channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("s.wav"), format: fmt, ring: ring)
        try w.start()
        for b in blocks {
            b.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: b.count) }
        }
        // No sleeps: stop() joins the drain thread and then flushes the whole
        // ring itself, so this is deterministic rather than a race with a timer.
        w.stop()
        XCTAssertEqual(ring.droppedSamples, 0, "the ring overflowed; the fixture is too large")
        return w.evidence
    }

    /// Polls a live value to a deadline. Fixed sleeps against a background drain
    /// thread are how a test becomes flaky on a loaded machine.
    private static func waitFor(_ what: String, until: () -> Bool, read: () -> Float,
                                seconds: Double = 5) -> Float {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if until() { return read() }
            usleep(10_000)
        }
        return read()
    }

    private func tone(_ amplitude: Float, seconds: Double, sampleRate: Double = 48_000) -> [Float] {
        let n = Int(seconds * sampleRate)
        return (0..<n).map { amplitude * sin(Float($0) * 0.05) }
    }
    private func silence(seconds: Double, sampleRate: Double = 48_000) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    // MARK: - The defect, pinned

    /// **The regression test.** Loud audio, then a long quiet tail — the shape of
    /// essentially every real meeting. The UI meter decays to nothing across the
    /// tail; the evidence must not.
    func testEvidenceSurvivesASilentTail() throws {
        let e = try run([tone(0.8, seconds: 1.2), silence(seconds: 3.0)])
        XCTAssertGreaterThan(e.peak, 0.5,
            "the reported peak decayed with the level meter — this is the original defect")
        XCTAssertTrue(e.producedAudio)
        XCTAssertGreaterThan(e.nonSilentSeconds, 1.0)
    }

    /// And the meter itself must still decay, because that is what it is for.
    /// If this fails, the fix went too far and the level bars will stick.
    func testTheLevelMeterStillDecays() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 48_000, channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("m.wav"), format: fmt, ring: ring)
        try w.start()
        let loud = tone(0.9, seconds: 0.5)
        loud.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: loud.count) }
        let afterLoud = Self.waitFor("the meter to rise", until: { w.peak > 0.5 }, read: { w.peak })
        let quiet = silence(seconds: 4.0)
        quiet.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: quiet.count) }
        let afterQuiet = Self.waitFor("the meter to fall",
                                      until: { w.peak < afterLoud * 0.5 }, read: { w.peak })
        let evidence = w.evidence
        w.stop()

        XCTAssertGreaterThan(afterLoud, 0.5, "the meter should have risen")
        XCTAssertLessThan(afterQuiet, afterLoud, "the meter must decay; it drives the level bars")
        XCTAssertGreaterThan(evidence.peak, 0.5, "the evidence must not decay with it")
    }

    // MARK: - Silence really is silence

    func testPureSilenceProducesNoEvidence() throws {
        let e = try run([silence(seconds: 2.0)])
        XCTAssertEqual(e.peak, 0)
        XCTAssertEqual(e.nonSilentSeconds, 0)
        XCTAssertFalse(e.producedAudio, "2 s of digital silence must not count as captured audio")
        XCTAssertGreaterThan(e.duration, 0, "it was still recorded — duration is a fact, just not evidence")
    }

    /// The exact false positive found on real data: long, and entirely silent.
    func testALongSilentCaptureIsStillNotAudio() throws {
        let e = try run([silence(seconds: 3.0)])
        XCTAssertFalse(e.producedAudio)
        XCTAssertGreaterThan(e.duration, 2.0,
            "the old rule accepted anything past 0.25 s; the length is real, the audio is not")
    }

    // MARK: - Units

    /// `nonSilentSeconds` divides by the input rate while `duration` divides by
    /// the 16 kHz output rate. If those ever diverge the comparison in
    /// `producedAudio` becomes nonsense, so pin them against each other at a
    /// non-16 kHz input rate where a mistake would show.
    func testSecondsAgreeAcrossTheResampleBoundary() throws {
        let e = try run([tone(0.7, seconds: 1.0)], sampleRate: 44_100)
        XCTAssertEqual(e.nonSilentSeconds, 1.0, accuracy: 0.15,
            "non-silent seconds must be real seconds, not input frames over the output rate")
        XCTAssertEqual(e.duration, 1.0, accuracy: 0.15)
    }

    func testMutedCaptureReportsNoAudioBecauseTheFileHoldsNone() throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 48_000, channels: 1, interleaved: false)!
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("mu.wav"), format: fmt, ring: ring)
        w.isMuted = true
        try w.start()
        let loud = tone(0.9, seconds: 1.0)
        loud.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: loud.count) }
        usleep(200_000)
        w.stop()
        XCTAssertFalse(w.evidence.producedAudio,
            "a muted writer writes silence, so the evidence must agree with the file")
    }
}

/// AD-28 generalised: `Core/` is pure. The existing rule was prose in a comment,
/// which is not a test.
final class CorePurityTests: XCTestCase {
    func testCoreImportsNothingButFoundation() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Minutes/Core", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: core.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "did not find Core/ at \(core.path)")

        let allowed: Set<String> = ["Foundation", "os", "os.log"]
        for f in files {
            let src = try String(contentsOf: core.appendingPathComponent(f), encoding: .utf8)
            for line in src.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                guard s.hasPrefix("import ") else { continue }
                let module = String(s.dropFirst("import ".count))
                    .trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(allowed.contains(module),
                    "Core/\(f) imports \(module). Core is plain maths and plain data — an "
                    + "Apple framework here is what AD-28 exists to prevent.")
            }
        }
    }
}
