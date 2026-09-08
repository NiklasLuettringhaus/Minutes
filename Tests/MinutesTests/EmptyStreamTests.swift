import XCTest
import AVFoundation
@testable import Minutes

/// FR-108. A Stream that recorded nothing is absent, not a failure.
///
/// FR-7 says a Session whose system tap failed still produces a Note from the
/// microphone alone. The mirror — a microphone that recorded nothing beside a
/// System Stream holding real speech — had no rule, and two Meetings were
/// discarded whole because of it.
final class EmptyStreamTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

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
        guard seconds > 0 else { return }
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

    /// The header-only file the two real Meetings had: 4,096 bytes, no audio.
    func testAStreamThatRecordedNothingIsRecognisedAsEmpty() throws {
        let url = tmp.appendingPathComponent("mic.wav")
        try write(seconds: 0, to: url)
        let a = try WavTailRepair.assess(url)
        let seconds = Double(a.actualDataBytes) / (a.sampleRate * Double(a.bytesPerFrame))
        XCTAssertEqual(seconds, 0, accuracy: 0.001)
        XCTAssertLessThan(seconds, 0.3, "must read as absent, not be handed to the transcriber")
    }

    /// The transcriber's floor is 300 ms and refusing below it is where
    /// "Invalid audio data provided. Must be at least 300ms of 16kHz audio"
    /// came from. The pipeline's own threshold has to agree with it.
    func testTheThresholdAgreesWithTheTranscribersOwnFloor() throws {
        for (seconds, usable) in [(0.0, false), (0.1, false), (0.29, false),
                                  (0.31, true), (1.0, true), (57.3, true)] {
            let url = tmp.appendingPathComponent("s-\(seconds).wav")
            try write(seconds: seconds, to: url)
            let a = try WavTailRepair.assess(url)
            let got = Double(a.actualDataBytes) / (a.sampleRate * Double(a.bytesPerFrame))
            XCTAssertEqual(got >= 0.3, usable,
                           "\(seconds)s read as \(got)s and was judged \(got >= 0.3 ? "usable" : "absent")")
        }
    }

    /// A real Stream is never mistaken for an empty one, which is the failure
    /// that would silently drop a whole meeting.
    func testARealStreamIsNeverMistakenForAnEmptyOne() throws {
        let url = tmp.appendingPathComponent("system.wav")
        try write(seconds: 57.3, to: url)
        let a = try WavTailRepair.assess(url)
        let seconds = Double(a.actualDataBytes) / (a.sampleRate * Double(a.bytesPerFrame))
        XCTAssertEqual(seconds, 57.3, accuracy: 0.01)
        XCTAssertFalse(a.needsRepair, "a properly closed file must need no repair")
    }
}
