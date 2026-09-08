import XCTest
import AVFoundation
@testable import Minutes

/// FR-106 / AD-60. The writer's side of surviving an audio-hardware change,
/// driven through the real ring and the real converter with no audio device.
///
/// The rates are the ones this machine actually reports: the built-in
/// microphone declares 48 kHz and AirPods declare 24 kHz, so putting AirPods in
/// during a call halves the input rate mid-file. That is the case these cover.
final class MicDeviceChangeTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-devchange-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    private func format(_ rate: Double, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                      channels: channels, interleaved: false)!
    }

    /// A tone, so the samples are real audio rather than zeros — silence would
    /// let a resampling error pass unnoticed.
    private func tone(_ rate: Double, seconds: Double, hz: Double = 440) -> [Float] {
        let n = Int(rate * seconds)
        return (0..<n).map { Float(0.5 * sin(2 * .pi * hz * Double($0) / rate)) }
    }

    private func feed(_ ring: RingBuffer, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: samples.count) }
    }

    /// Waits for the drain thread to catch up rather than sleeping a fixed time.
    private func drain(_ ring: RingBuffer, seconds: Double = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while ring.count > 0, Date() < deadline { usleep(10_000) }
    }

    // MARK: - The rate change itself

    /// **The measurement.** Two seconds at 48 kHz then two seconds at 24 kHz
    /// must produce four seconds of file. Converting the second half with the
    /// first half's converter produces three — which is what a handler that only
    /// restarted the engine would have written.
    func testAudioCapturedAfterTheRateChangeLandsAtItsOwnRate() throws {
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("s.wav"),
                                 format: format(48_000), ring: ring)
        try w.start()

        feed(ring, tone(48_000, seconds: 2))
        drain(ring)

        XCTAssertTrue(w.retune(inputRate: 24_000), "the retune failed")
        XCTAssertEqual(w.converterInputRate, 24_000)
        // Read *after* the retune rather than before it, because until the rate
        // settles the opening is held in memory by design (AD-44) and the file
        // is legitimately still empty. The retune forces that decision, so this
        // is also the assertion that the old device's audio reached the file
        // before its converter was retired.
        XCTAssertEqual(w.duration, 2.0, accuracy: 0.05, "the first device's audio")

        feed(ring, tone(24_000, seconds: 2))
        drain(ring)
        w.stop()

        XCTAssertEqual(w.duration, 4.0, accuracy: 0.05,
                       "two seconds each side of the change must be four seconds of file")
        // What the un-retuned converter would have produced, named so a
        // regression cannot be mistaken for noise.
        XCTAssertGreaterThan(w.duration, 3.5,
                             "the second half was converted at the first half's rate")
    }

    /// The file itself, not the writer's own counter — the counter could agree
    /// with a wrong file.
    func testTheFileOnDiskHoldsBothHalvesAtTheOutputRate() throws {
        let url = tmp.appendingPathComponent("f.wav")
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: url, format: format(48_000), ring: ring)
        try w.start()
        feed(ring, tone(48_000, seconds: 1))
        drain(ring)
        XCTAssertTrue(w.retune(inputRate: 24_000))
        feed(ring, tone(24_000, seconds: 1))
        drain(ring)
        w.stop()

        let f = try AVAudioFile(forReading: url)
        XCTAssertEqual(f.fileFormat.sampleRate, 16_000, "the output rate must not change")
        let seconds = Double(f.length) / f.fileFormat.sampleRate
        XCTAssertEqual(seconds, 2.0, accuracy: 0.05)
    }

    func testRetuningToTheRateAlreadyInUseChangesNothing() throws {
        let ring = RingBuffer(capacity: 1 << 20)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("n.wav"),
                                 format: format(48_000), ring: ring)
        try w.start()
        XCTAssertTrue(w.retune(inputRate: 48_000), "a no-op retune must succeed")
        XCTAssertEqual(w.converterInputRate, 48_000)
        feed(ring, tone(48_000, seconds: 0.5))
        drain(ring)
        w.stop()
        XCTAssertEqual(w.duration, 0.5, accuracy: 0.05)
        XCTAssertNil(w.ledger.expectedOutputFrames,
                     "nothing changed, so the derived identity must still be used")
    }

    func testAnImpossibleRateIsRefusedRatherThanGuessed() throws {
        let ring = RingBuffer(capacity: 1 << 20)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("z.wav"),
                                 format: format(48_000), ring: ring)
        try w.start()
        XCTAssertFalse(w.retune(inputRate: 0))
        XCTAssertFalse(w.retune(inputRate: -48_000))
        XCTAssertEqual(w.converterInputRate, 48_000, "a refused retune must not disturb the converter")
        w.stop()
    }

    /// The samples already in the ring when the device changed were captured at
    /// the **old** rate, and must be converted at it. Retuning without draining
    /// first would resample them wrongly.
    func testSamplesStillInTheRingAtTheChangeAreConvertedAtTheOldRate() throws {
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("r.wav"),
                                 format: format(48_000), ring: ring)
        try w.start()
        // Fed and retuned immediately, with no drain in between, so the ring is
        // still holding 48 kHz audio at the moment of the change.
        feed(ring, tone(48_000, seconds: 2))
        XCTAssertTrue(w.retune(inputRate: 24_000))
        XCTAssertEqual(ring.count, 0, "retune must drain what the old device left")
        XCTAssertEqual(w.duration, 2.0, accuracy: 0.05,
                       "the old device's audio was converted at the new rate")
        w.stop()
    }

    // MARK: - What the change costs, stated rather than hidden

    /// A device that legitimately changed its rate is not a device lying about
    /// its rate. Reporting AD-44's verdict here would raise "recorded at the
    /// wrong rate" on a recording that is correct.
    func testTheRateVerdictBecomesUnavailableRatherThanWrong() throws {
        let ring = RingBuffer(capacity: 1 << 20)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("v.wav"),
                                 format: format(48_000), ring: ring)
        try w.start()
        feed(ring, tone(48_000, seconds: 0.5))
        drain(ring)
        XCTAssertTrue(w.retune(inputRate: 24_000))
        feed(ring, tone(24_000, seconds: 0.5))
        drain(ring)
        w.stop()

        let r = w.rateFidelity
        XCTAssertEqual(r, .unknown, "a changed rate must read unavailable")
        XCTAssertNil(r.explanation, "and must not report a failure to the user")
    }

    /// The identity has to keep closing across two rates, which is the whole
    /// reason the expected term is counted rather than derived.
    func testTheAccountingIdentityStillClosesAcrossTheChange() throws {
        let ring = RingBuffer(capacity: 1 << 21)
        let w = StreamFileWriter(url: tmp.appendingPathComponent("l.wav"),
                                 format: format(48_000), ring: ring)
        try w.start()
        feed(ring, tone(48_000, seconds: 2))
        drain(ring)
        XCTAssertTrue(w.retune(inputRate: 24_000))
        feed(ring, tone(24_000, seconds: 2))
        drain(ring)
        w.stop()

        let l = w.ledger
        XCTAssertNotNil(l.expectedOutputFrames, "the counted term must be supplied after a change")
        XCTAssertEqual(l.droppedFrames, 0)
        XCTAssertEqual(l.writeFailures, 0)
        XCTAssertEqual(l.residentFrames, 0)
        // 2 s at 48 kHz + 2 s at 24 kHz = 144,000 input frames consumed.
        XCTAssertEqual(l.consumedFrames, 144_000, accuracy: 1)
        // And four seconds of 16 kHz output expected from them. The derived form
        // would have said 144,000 * (16/24) = 96,000 — one second too many.
        XCTAssertEqual(l.expectedWrittenFrames, 64_000, accuracy: 8)
        XCTAssertEqual(l.writtenFrames, 64_000, accuracy: 64)
        XCTAssertEqual(l.unproducedFrames, 0, accuracy: 64,
                       "frames consumed and never converted: \(l.unproducedFrames)")
    }

    /// Pins that the derived form really would be wrong here, so the test above
    /// is known to be testing something.
    func testTheDerivedIdentityWouldHaveBeenWrongAcrossTwoRates() {
        // The same counts, with the counted term absent — which is every
        // Meeting recorded before this existed, and the arithmetic that made
        // the change necessary.
        let derived = CaptureLedger(
            deviceFrames: 144_000, droppedFrames: 0, overflows: 0,
            consumedFrames: 144_000, residentFrames: 0, writtenFrames: 64_000,
            producedFrames: 64_000, inputRate: 24_000, outputRate: 16_000)
        XCTAssertNil(derived.expectedOutputFrames)
        XCTAssertEqual(derived.expectedWrittenFrames, 96_000,
                       "the derived form applies the last rate to the whole file")
        XCTAssertEqual(derived.unproducedFrames, 32_000,
                       "and so invents two seconds of loss that never happened")

        var counted = derived
        counted.expectedOutputFrames = 64_000
        XCTAssertEqual(counted.expectedWrittenFrames, 64_000)
        XCTAssertEqual(counted.unproducedFrames, 0)
    }

    // MARK: - The stored form

    func testAMeetingRecordedBeforeThisTermExistedStillReadsCorrectly() throws {
        // No `expectedOutputFrames` key at all: the shape every stored Meeting
        // has. It must decode as absent and derive, not as zero expected frames.
        let json = """
        {"deviceFrames":48000,"droppedFrames":0,"overflows":0,"consumedFrames":48000,
         "residentFrames":0,"writtenFrames":16000,"producedFrames":16000,
         "writeFailures":0,"writeFailureFrames":0,"heldFrames":0,
         "inputRate":48000,"outputRate":16000}
        """.data(using: .utf8)!
        let l = try JSONDecoder().decode(CaptureLedger.self, from: json)
        XCTAssertNil(l.expectedOutputFrames)
        XCTAssertEqual(l.expectedWrittenFrames, 16_000, "must derive, not read as zero")
        XCTAssertEqual(l.unproducedFrames, 0)
    }

    func testTheCountedTermSurvivesARoundTrip() throws {
        var l = CaptureLedger(
            deviceFrames: 144_000, droppedFrames: 0, overflows: 0,
            consumedFrames: 144_000, residentFrames: 0, writtenFrames: 64_000,
            producedFrames: 64_000, inputRate: 24_000, outputRate: 16_000)
        l.expectedOutputFrames = 64_000
        let back = try JSONDecoder().decode(
            CaptureLedger.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(back.expectedOutputFrames, 64_000)
        XCTAssertEqual(back, l)
    }
}
