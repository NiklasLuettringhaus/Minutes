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
    /// When capture started. Kept for `duration`-adjacent diagnostics only.
    private(set) var startedAt: Date?
    /// The baseline the rate is measured from: the moment the *second* chunk of
    /// input was seen, and the frame count at that moment.
    ///
    /// Not `start()`. The first buffer arrives almost immediately after the
    /// stream opens, so measuring from `start()` divides a full chunk of frames by
    /// a near-zero elapsed and reads absurdly high — 76 kHz on the first drain of
    /// a 16 kHz stream — then converges downward over seconds. A check that fires
    /// on that transient is a check that fires on every recording; worse, one that
    /// *snaps a rate* from it picks the wrong rate. Measured: at 3.4 s the biased
    /// figure was 17716 Hz, which is 10.7% from 16 kHz and therefore too far from
    /// any real device rate to be trusted, so the correction refused to act.
    ///
    /// Measuring between two later points removes the transient entirely.
    private var measureBaseline: (frames: AVAudioFramePosition, at: Date)?
    /// When the most recently counted chunk was seen.
    ///
    /// The rate is `(frames since baseline) / (lastDrainAt - baselineAt)`, so both
    /// halves refer to the *same instant*. Dividing frames counted at the last
    /// chunk by elapsed measured *now* is biased low by up to half a chunk period
    /// — about 6% for 375 ms chunks over a 3 s window, which was enough to report
    /// a perfectly correct 16 kHz stream as 13% out. Sampling both at the same
    /// point removes the bias entirely rather than hiding it under a wider
    /// tolerance.
    private var lastDrainAt: Date?
    /// `Date` rather than the audio clock, deliberately: the whole failure was the
    /// audio clock not being what the app believed, so the check must come from
    /// outside it.
    /// Set once when the rate check first fails, so the failure is reported once
    /// rather than on every drained chunk.
    private(set) var rateFailure: RateFidelity?
    /// The rate this writer is actually converting *from*.
    ///
    /// Starts as the declared rate and becomes the observed one if the device
    /// turns out to disagree (AD-44). Every conversion uses this, never `format`.
    private var effectiveRate: Double
    /// The rate the writer settled on, when it differed from the declared one.
    private(set) var correctedRate: Double?
    /// Raw input samples held back until the rate is settled.
    ///
    /// **Nothing is written to the file until the rate is confirmed.** Deciding
    /// after some audio is already on disk would leave the first seconds of every
    /// corrected recording compressed — a small permanent defect at the start of
    /// the file, which is exactly the kind of thing nobody notices until it
    /// matters. Three seconds of stereo float at 48 kHz is about 1.1 MB, so
    /// holding it costs nothing worth counting.
    private var pending: [Float] = []
    private var rateSettled = false
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
        self.effectiveRate = format.sampleRate
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
        guard let c = makeConverter(inputRate: effectiveRate) else {
            throw MinutesError.audioFileWriteFailed(
                "cannot convert \(format.sampleRate) Hz / \(format.channelCount) ch to 16 kHz mono")
        }
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
        // A capture shorter than the settling period has nothing left to settle,
        // so the decision is forced here and the held opening is written. Without
        // this a five-second Test Playground recording (FR-47) would produce an
        // empty file.
        settleRateIfPossible(final: true)
        file = nil
        thread = nil
    }

    var duration: TimeInterval {
        Double(framesWritten) / Self.outputSampleRate
    }

    var nonSilentSeconds: TimeInterval {
        Double(nonSilentInputFrames) / max(1, effectiveRate)
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
        guard let b = measureBaseline, let last = lastDrainAt else {
            return RateFidelity(declaredRate: format.sampleRate, framesObserved: 0,
                                elapsedSeconds: 0, correctedTo: correctedRate)
        }
        return RateFidelity(declaredRate: format.sampleRate,
                            framesObserved: Double(inputFramesConsumed - b.frames),
                            elapsedSeconds: last.timeIntervalSince(b.at),
                            correctedTo: correctedRate)
    }

    /// The input format conversions actually use, which may not be the one the
    /// device claimed.
    private func makeConverter(inputRate: Double) -> AVAudioConverter? {
        guard let input = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: inputRate,
                                        channels: format.channelCount,
                                        interleaved: format.isInterleaved),
              let c = AVAudioConverter(from: input, to: Self.outputFormat) else { return nil }
        c.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        return c
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
        let channels = Int(format.channelCount)
        let wanted = 8192 * channels
        let samples = ring.read(max: wanted)
        guard !samples.isEmpty else { return }
        let frames = samples.count / max(1, channels)
        guard frames > 0 else { return }

        // Peak is measured on the captured samples, before conversion, so the
        // level meters keep reading what the microphone actually heard.
        var localPeak: Float = 0
        for v in samples { localPeak = max(localPeak, abs(v)) }
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
        // The baseline is taken *after* the first chunk, so the startup transient
        // is outside the measurement window rather than dominating it.
        let now = Date()
        if measureBaseline == nil {
            measureBaseline = (frames: inputFramesConsumed, at: now)
        }
        lastDrainAt = now

        // Nothing reaches the file until the rate is settled (AD-44). Held rather
        // than written-then-corrected, so a corrected recording has no compressed
        // opening seconds.
        if !rateSettled {
            pending += samples
            settleRateIfPossible(final: false)
            return
        }
        checkRate()
        write(samples: samples, channels: channels)
    }

    /// Decides, once, what rate this stream is really delivering — and rebuilds
    /// the converter if it is not the one the device claimed (AD-44).
    ///
    /// This is the prevention, as distinct from the detection. Reporting a
    /// disagreement leaves the recording ruined and merely honest about it; the
    /// point of measuring the rate is to be able to use the right one.
    private func settleRateIfPossible(final: Bool) {
        guard !rateSettled else { return }
        let f = rateFidelity
        let verdict = final ? f.finalVerdict : f.verdict
        switch verdict {
        case .settling:
            // Only a stop forces a decision. Mid-stream, keep holding.
            guard final else { return }
            rateSettled = true
        case .correct:
            rateSettled = true
        case .wrong(let ratio):
            rateSettled = true
            guard let snapped = RateFidelity.standardRate(nearest: f.observedRate) else {
                // Not near any rate a real device uses. Keep the declared rate,
                // let the file come out wrong, and let AD-45 refuse to build
                // anything on it — guessing here is how a different defect would
                // get silently resampled into this one.
                Log.audio.error("rate disagreement x\(ratio, privacy: .public) but observed \(f.observedRate, privacy: .public) Hz is not a standard rate; keeping the declared rate and marking the stream untrustworthy")
                checkRate()
                break
            }
            if let c = makeConverter(inputRate: snapped) {
                effectiveRate = snapped
                correctedRate = snapped
                converter = c
                Log.audio.error("corrected input rate: declared \(self.format.sampleRate, privacy: .public) Hz, observed \(f.observedRate, privacy: .public) Hz, converting from \(snapped, privacy: .public) Hz")
                onRateDisagreement?(rateFidelity)
            } else {
                Log.audio.error("could not build a converter at \(snapped, privacy: .public) Hz; keeping the declared rate")
                checkRate()
            }
        }
        guard rateSettled, !pending.isEmpty else { return }
        let held = pending
        pending = []
        write(samples: held, channels: Int(format.channelCount))
    }

    /// Converts and appends. Chunked, because the held opening can be far larger
    /// than one drain and `convert` hands the converter a single buffer.
    private func write(samples: [Float], channels: Int) {
        guard let file, let converter else { return }
        let maxFrames = 8192
        var offset = 0
        let totalFrames = samples.count / max(1, channels)
        while offset < totalFrames {
            let n = min(maxFrames, totalFrames - offset)
            guard let src = AVAudioPCMBuffer(pcmFormat: converter.inputFormat,
                                             frameCapacity: AVAudioFrameCount(n)),
                  let dst = src.floatChannelData?[0] else { return }
            src.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { p in
                dst.update(from: p.baseAddress! + offset * channels, count: n * channels)
            }
            offset += n
            guard let out = convert(src, using: converter) else { continue }
            if isMuted, let ch = out.floatChannelData?[0] {
                ch.update(repeating: 0, count: Int(out.frameLength))
            }
            guard out.frameLength > 0 else { continue }
            do {
                try file.write(from: out)
                framesWritten += AVAudioFramePosition(out.frameLength)
            } catch {
                Log.audio.error("write failed: \(error.localizedDescription, privacy: .public)")
            }
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
        let ratio = Self.outputSampleRate / effectiveRate
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
