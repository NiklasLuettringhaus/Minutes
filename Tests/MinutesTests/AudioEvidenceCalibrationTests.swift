import XCTest
import AVFoundation
@testable import Minutes

/// AD-36, measured against the real recordings on this machine rather than
/// against fixtures.
///
/// Skips cleanly when there are no Meetings, so it is meaningful on the author's
/// machine and silent everywhere else — the same contract as
/// `EnrolmentCalibrationTests`. It reads the audio and never copies any of it
/// into the repository: these are other people's voices (PRD §9.1).
final class AudioEvidenceCalibrationTests: XCTestCase {

    /// Off by default. It reads every stream of every Meeting — about a gigabyte
    /// on the author's machine, 56 seconds — which is far too slow to sit in the
    /// loop a developer runs on every change. Same contract as
    /// `MINUTES_ML_TESTS`:
    ///
    ///     MINUTES_AUDIO_CALIBRATION=1 swift test --filter AudioEvidenceCalibration
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["MINUTES_AUDIO_CALIBRATION"] == "1"
    }

    private static var meetingsRoot: URL? {
        let u = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Minutes/Meetings", isDirectory: true)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Peak and non-silent seconds, computed the way `StreamFileWriter` computes
    /// them live: chunked, comparing each chunk's peak against the floor.
    private func evidence(of url: URL) throws -> AudioEvidence {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let chunk: AVAudioFrameCount = 8192
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk) else {
            return .none
        }
        var peakEver: Float = 0
        var nonSilentFrames: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            // Bound the read: AVAudioFile throws rather than short-reading when
            // fewer frames remain than requested.
            let remaining = file.length - file.framePosition
            let want = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
            if want == 0 { break }
            try file.read(into: buf, frameCount: want)
            let n = Int(buf.frameLength)
            if n == 0 { break }
            var localPeak: Float = 0
            if let ch = buf.floatChannelData {
                for c in 0..<Int(fmt.channelCount) {
                    let p = ch[c]
                    for i in 0..<n { localPeak = max(localPeak, abs(p[i])) }
                }
            }
            peakEver = max(peakEver, localPeak)
            if localPeak > AudioEvidence.silenceFloor {
                nonSilentFrames += AVAudioFramePosition(n)
            }
        }
        let dur = Double(file.length) / fmt.sampleRate
        return AudioEvidence(peak: peakEver,
                             nonSilentSeconds: Double(nonSilentFrames) / fmt.sampleRate,
                             duration: dur)
    }

    func testTheNewRuleRejectsSilentStreamsTheOldOneAccepted() throws {
        try XCTSkipUnless(Self.enabled, "set MINUTES_AUDIO_CALIBRATION=1 to read real audio")
        guard let root = Self.meetingsRoot else {
            throw XCTSkip("no Meetings on this machine")
        }
        let ids = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { !$0.hasPrefix(".") }.sorted()
        guard !ids.isEmpty else { throw XCTSkip("no Meetings on this machine") }

        var examined = 0
        var newAccepts = 0
        var oldAccepts = 0
        var silentButLong: [String] = []

        for id in ids {
            for kind in ["mic", "system"] {
                let u = root.appendingPathComponent(id).appendingPathComponent("\(kind).wav")
                guard FileManager.default.fileExists(atPath: u.path) else { continue }
                let e = try evidence(of: u)
                examined += 1
                if e.producedAudio { newAccepts += 1 }
                // The rule as it shipped: a decaying meter OR a quarter second.
                let oldRule = e.peak > 0.0001 || e.duration > 0.25
                if oldRule { oldAccepts += 1 }

                // The defect, stated as an assertion rather than a comment: a
                // stream of digital silence is never captured audio, however long.
                if e.peak == 0 {
                    XCTAssertFalse(e.producedAudio,
                        "\(id)/\(kind): peak is exactly 0 over \(Int(e.duration))s and it was accepted")
                    if e.duration > 60 { silentButLong.append("\(id)/\(kind) \(Int(e.duration))s") }
                }
                // And a stream the new rule accepts must have real signal in it.
                if e.producedAudio {
                    XCTAssertGreaterThan(e.peak, AudioEvidence.silenceFloor)
                    XCTAssertGreaterThanOrEqual(e.nonSilentSeconds, AudioEvidence.minimumSignalSeconds)
                }
            }
        }

        print("[audio-evidence] \(examined) real streams examined")
        print("[audio-evidence] the shipped rule accepted \(oldAccepts); this rule accepts \(newAccepts)")
        print("[audio-evidence] long streams of pure digital silence: \(silentButLong.isEmpty ? "none" : silentButLong.joined(separator: ", "))")

        XCTAssertGreaterThan(examined, 0)
        XCTAssertLessThanOrEqual(newAccepts, oldAccepts,
            "this rule must be no more permissive than the one it replaces")
    }

    /// The claim that motivated the change, held as a regression: at least one
    /// real stream is long, silent, and was previously reported as working.
    func testAtLeastOneRealFalsePositiveExistedOnThisMachine() throws {
        try XCTSkipUnless(Self.enabled, "set MINUTES_AUDIO_CALIBRATION=1 to read real audio")
        guard let root = Self.meetingsRoot else {
            throw XCTSkip("no Meetings on this machine")
        }
        let ids = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { !$0.hasPrefix(".") }
        var falsePositives = 0
        for id in ids {
            let u = root.appendingPathComponent(id).appendingPathComponent("system.wav")
            guard FileManager.default.fileExists(atPath: u.path) else { continue }
            let e = try evidence(of: u)
            let oldRule = e.peak > 0.0001 || e.duration > 0.25
            if oldRule && !e.producedAudio { falsePositives += 1 }
        }
        print("[audio-evidence] system streams the old rule got wrong: \(falsePositives)")
        guard falsePositives > 0 else {
            throw XCTSkip("no false positives in this Meeting set — nothing to demonstrate")
        }
        XCTAssertGreaterThan(falsePositives, 0)
    }
}
