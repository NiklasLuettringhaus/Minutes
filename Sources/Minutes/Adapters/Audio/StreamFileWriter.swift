import Foundation
import AVFoundation

/// Drains a RingBuffer to a WAV file on a background thread, downsampling to
/// 16 kHz mono on the way.
///
/// Audio is committed to disk incrementally, never buffered in memory until stop,
/// so memory stays flat with respect to Session duration and a crash leaves the
/// captured audio recoverable (FR-9).
///
/// **Why 16 kHz mono 16-bit.** This used to write the capture format straight
/// through — 48 kHz float32, stereo for the system tap — which came to 532 KB/s
/// across the two streams, about 2 GB per hour, or 1.5 GB for a 45-minute meeting.
/// With retention on by default that grows without bound, and it bought nothing:
/// both transcription engines and the diarizer call
/// `AudioProcessor.loadAudioAsFloatArray`, which resamples to 16 kHz mono before
/// doing anything. Six times the resolution was being stored so that it could be
/// thrown away on every read. 16 kHz is also what Whisper and Parakeet were
/// trained on, and 16-bit PCM is the standard depth for speech, so this is a
/// 16-fold saving with no consumer of the extra data.
final class StreamFileWriter {
    /// The one place the storage format is decided.
    static let outputSampleRate: Double = 16_000
    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: outputSampleRate,
        channels: 1, interleaved: false)!

    private let url: URL
    private let format: AVAudioFormat
    private let ring: RingBuffer
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var thread: Thread?
    private var running = false
    /// Counts frames written to the file, i.e. output frames at 16 kHz — not
    /// captured frames. `duration` divides by the output rate accordingly.
    private(set) var framesWritten: AVAudioFramePosition = 0
    /// Counts frames *consumed from the ring*, i.e. captured frames at whatever
    /// rate the device is really delivering. The numerator of AD-44's rate check.
    private(set) var inputFramesConsumed: AVAudioFramePosition = 0
    /// When capture started, for the denominator. `Date` rather than the audio
    /// clock deliberately: the whole failure was the audio clock not being what
    /// the app believed, so the check has to come from outside it.
    private(set) var startedAt: Date?
    /// Set once when the rate check first fails, so the failure is reported once
    /// rather than on every drained chunk.
    private(set) var rateFailure: RateFidelity?
    /// Called on the drain thread the first time the observed rate disagrees with
    /// the declared one (AD-44). Never called for a settling or correct stream.
    var onRateDisagreement: (@Sendable (RateFidelity) -> Void)?
    /// The UI level meter. Decays on purpose so the meters fall when someone
    /// stops talking — which is exactly why it must never be used as evidence
    /// that a capture worked (AD-36). Use `evidence` for that.
    private(set) var peak: Float = 0
    /// Highest absolute sample over the whole capture. Never decays.
    private(set) var peakEver: Float = 0
    /// Captured frames belonging to a chunk whose peak cleared the silence floor.
    /// Counted at input rate, which is what `nonSilentSeconds` divides by.
    private(set) var nonSilentInputFrames: AVAudioFramePosition = 0

    /// When true, silence is written instead of the captured audio.
    ///
    /// Applied here, on the writer's own thread, rather than in the capture
    /// callback — the real-time audio thread is not the place for a flag it has to
    /// branch on. Silence rather than dropped frames, so the two streams stay on
    /// one clock and Utterance timestamps remain comparable across them (AD-4).
    /// This is a privacy convenience, not a security boundary: at the moment of
    /// muting, up to one buffer already in the ring may still reach disk.
    var isMuted = false

    init(url: URL, format: AVAudioFormat, ring: RingBuffer) {
        self.url = url
        self.format = format
        self.ring = ring
    }

    func start() throws {
        // 16-bit PCM on disk; the processing format stays float32 and AVAudioFile
        // converts depth on write. Sample-rate and channel conversion is ours to
        // do — AVAudioFile does not resample.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw MinutesError.audioFileWriteFailed(error.localizedDescription)
        }
        // Handles the sample-rate conversion and the multi-channel downmix in one
        // step, with proper filtering — the system tap is stereo at 48 kHz and the
        // mic may be any rate the device offers.
        guard let c = AVAudioConverter(from: format, to: Self.outputFormat) else {
            throw MinutesError.audioFileWriteFailed(
                "cannot convert \(format.sampleRate) Hz / \(format.channelCount) ch to 16 kHz mono")
        }
        c.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        converter = c
        startedAt = Date()
        running = true
        let t = Thread { [weak self] in self?.drainLoop() }
        t.name = "minutes.writer.\(url.lastPathComponent)"
        t.qualityOfService = .utility
        thread = t
        t.start()
    }

    func stop() {
        // Signal the drain thread and WAIT for it to finish before touching the
        // file. Draining from two threads at once is a data race on AVAudioFile,
        // and the old code did exactly that.
        running = false
        let deadline = Date().addingTimeInterval(3)
        while !(thread?.isFinished ?? true), Date() < deadline {
            usleep(5_000)
        }
        // Now sole owner: flush everything left, not just one chunk. The previous
        // single drainOnce() call truncated the tail of every recording.
        while ring.count > 0 {
            let before = ring.count
            drainOnce()
            if ring.count >= before { break }  // no progress; avoid spinning
        }
        file = nil
        thread = nil
    }

    var duration: TimeInterval {
        Double(framesWritten) / Self.outputSampleRate
    }

    var nonSilentSeconds: TimeInterval {
        Double(nonSilentInputFrames) / max(1, format.sampleRate)
    }

    /// What this capture can honestly claim about producing audio (AD-36).
    var evidence: AudioEvidence {
        AudioEvidence(peak: peakEver, nonSilentSeconds: nonSilentSeconds, duration: duration)
    }

    /// What this capture can honestly claim about its *rate* (AD-44, AD-45).
    ///
    /// The second, independent half of capture evidence. Both counters are ones
    /// this type already keeps: input frames consumed, and the wall time since
    /// `start()`. Nothing new is measured — which matters, because a check that
    /// costs something is a check somebody eventually makes optional.
    ///
    /// Wall time, not `duration`: `duration` is derived from frames *written* at
    /// the output rate, so it carries the same error it is meant to detect, and
    /// comparing it against input frames would always agree.
    var rateFidelity: RateFidelity {
        RateFidelity(declaredRate: format.sampleRate,
                     framesObserved: Double(inputFramesConsumed),
                     elapsedSeconds: startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// AD-44: the rate is checked *while recording*, because a two-hour meeting is
    /// too expensive to discover afterwards. Reported once — a disagreement does
    /// not improve, and one error is information while a hundred is noise.
    private func checkRate() {
        guard rateFailure == nil else { return }
        let f = rateFidelity
        guard case .wrong = f.verdict else { return }
        rateFailure = f
        Log.audio.error("rate disagreement: declared \(f.declaredRate, privacy: .public) Hz, observed \(f.observedRate, privacy: .public) Hz, ratio \(f.ratio, privacy: .public)")
        onRateDisagreement?(f)
    }

    private func drainLoop() {
        while running {
            if ring.count == 0 { usleep(20_000); continue }
            drainOnce()
        }
    }

    private func drainOnce() {
        guard let file, let converter else { return }
        let channels = Int(format.channelCount)
        let wanted = 8192 * channels
        let samples = ring.read(max: wanted)
        guard !samples.isEmpty else { return }
        let frames = samples.count / max(1, channels)
        guard frames > 0,
              let src = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        src.frameLength = AVAudioFrameCount(frames)
        guard let dst = src.floatChannelData?[0] else { return }

        // Peak is measured on the captured samples, before conversion, so the
        // level meters keep reading what the microphone actually heard.
        var localPeak: Float = 0
        samples.withUnsafeBufferPointer { p in
            dst.update(from: p.baseAddress!, count: frames * channels)
            for i in 0..<(frames * channels) { localPeak = max(localPeak, abs(p[i])) }
        }
        peak = isMuted ? 0 : max(peak * 0.85, localPeak)

        // Evidence, kept separately from the meter. Muted means silence really is
        // written to the file, so the evidence must agree with the file rather
        // than with what the microphone heard.
        if !isMuted {
            peakEver = max(peakEver, localPeak)
            if localPeak > AudioEvidence.silenceFloor {
                nonSilentInputFrames += AVAudioFramePosition(frames)
            }
        }

        // AD-44. Counted whether or not the stream is muted — a mute is about what
        // gets written, and the rate is about what arrives.
        inputFramesConsumed += AVAudioFramePosition(frames)
        checkRate()

        guard let out = convert(src, using: converter) else { return }
        if isMuted, let ch = out.floatChannelData?[0] {
            ch.update(repeating: 0, count: Int(out.frameLength))
        }
        guard out.frameLength > 0 else { return }
        do {
            try file.write(from: out)
            framesWritten += AVAudioFramePosition(out.frameLength)
        } catch {
            Log.audio.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One captured chunk to 16 kHz mono.
    ///
    /// The input-block form is required rather than optional: with a sample-rate
    /// change the output frame count differs from the input's, so the simple
    /// `convert(to:from:)` overload is not applicable. `inputRanDry` is the normal
    /// terminating status here — we hand over one buffer and the converter asks for
    /// more — and whatever it produced by then is real audio that must be written.
    private func convert(_ src: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = Self.outputSampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(src.frameLength) * ratio) + 64
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity)
        else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return src
        }

        switch status {
        case .haveData, .inputRanDry:
            return out
        case .endOfStream:
            return out.frameLength > 0 ? out : nil
        case .error:
            Log.audio.error("resample failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        @unknown default:
            return nil
        }
    }
}
