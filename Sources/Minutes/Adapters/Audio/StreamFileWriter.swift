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

    /// Output frames offered to `AVAudioConverter` beyond what the current input
    /// chunk needs — **and the fix for the drift this increment was written
    /// for** (AD-57, FR-102).
    ///
    /// **It was 64, and 64 was the whole defect.** The output buffer is sized
    /// from the input chunk in hand, so the slack is all the room the converter
    /// has to hand back anything it is holding beyond that chunk. Sixty-four
    /// frames is four milliseconds. Under load the converter holds more than
    /// that, cannot shed it at four milliseconds per call, and the audio does not
    /// reach the file.
    ///
    /// Measured with `--check-drain 20 10` — twenty seconds per shape against ten
    /// competing `userInteractive` threads on a ten-core machine, three runs each:
    ///
    /// | producer shape | slack 64 | slack 4096 |
    /// |---|---|---|
    /// | 512 frames / 10.7 ms, stereo 48 kHz | 0.27–0.75% lost | **0%** |
    /// | 480 frames / 20 ms, stereo 24 kHz | 0.50–0.60% | **0%** |
    /// | 512 frames / 10.7 ms, mono 48 kHz | 0.80–0.91% | **0%** |
    /// | 4800 frames / 100 ms, mono 48 kHz | 0% | **0%** |
    /// | 4800 frames / 100 ms, stereo 48 kHz | 0% | **0%** |
    ///
    /// The two shapes that never lost anything are the ones whose callbacks are
    /// **4,800 frames**, and the microphone's callbacks are 4,800 frames while the
    /// system tap's are 512. That is the 380× asymmetry the real recording shows,
    /// reproduced from the callback size alone with no audio device involved.
    ///
    /// **4096, and it is a bound rather than a tuned figure.** It is half of one
    /// output chunk, so a conversion can always return a whole chunk's worth more
    /// than the input it was just handed — which is strictly more than the
    /// converter can be holding, because it is only ever handed one chunk at a
    /// time. It costs 16 KB per conversion buffer and the buffer is transient.
    /// This is not a widened tolerance: nothing is being allowed through that was
    /// previously rejected, and the number it moves is a loss to **zero** rather
    /// than to inside a window.
    static let outputSlackFrames: AVAudioFrameCount = 4096

    /// The slack actually used, so `--check-drain` can sweep it and show the
    /// difference the shipping value makes. Production never sets it.
    static var outputSlackOverride: AVAudioFrameCount?

    /// Whether a conversion keeps pulling until the converter stops filling the
    /// buffer — **the half of the fix that needs no constant** (AD-57).
    ///
    /// `outputSlackFrames` above makes the buffer big enough for the backlog at
    /// the ratios this app actually meets, and "big enough" is a claim about the
    /// ratio: at 3:1 one input chunk converts to at most 2,731 output frames, so
    /// 4,096 covers it. At **2:1 upward** — an 8 kHz device, and this library
    /// holds five recordings whose System Stream ran at 8000 Hz — one 8,192-frame
    /// chunk converts to 16,384 output frames and 4,096 does not cover it at all.
    ///
    /// So the size is not the mechanism's cure, it is a symptom of not asking the
    /// converter whether it has more. `.haveData` means the buffer was filled and
    /// there may be more behind it; `.inputRanDry` means it has run out. Looping
    /// on the former drains the backlog at any ratio and needs no figure to be
    /// right.
    ///
    /// Sweepable so the two halves can be measured apart rather than shipped as
    /// one change nobody can attribute. Production never sets it.
    static var pullUntilDryOverride: Bool?
    static let pullUntilDry = true
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
    /// Output frames the converter actually produced (AD-57).
    ///
    /// Splits `CaptureLedger.conversionRemainder` into its two halves, which are
    /// different faults: frames the converter never produced from input it was
    /// given, and frames it produced that did not reach the file. The first
    /// reading of the identity could not tell them apart, and "consumed and not
    /// written" was doing the work of both.
    private(set) var convertProducedFrames: AVAudioFramePosition = 0
    /// Times `AVAudioFile.write` threw.
    ///
    /// It was logged and never counted. A recording that lost audio because the
    /// disk stalled and one that lost it because the ring overflowed are
    /// different faults, and a log line that has rolled out of the unified log —
    /// as the log for the 42.4-minute recording had by the time it was looked at
    /// — is not a record.
    private(set) var writeFailures = 0
    /// Output frames lost to those failures.
    private(set) var writeFailureFrames: AVAudioFramePosition = 0

    /// The ring's counters, frozen at `stop()` (AD-57).
    ///
    /// **The ledger must not depend on being read before the ring is reset.**
    /// The first version read them live, and `SystemTapCapture.stop` calls
    /// `teardown()` — which calls `ring.reset()` — before it reads the result. So
    /// the System Stream reported zero drops and a zero high-water mark on every
    /// capture, which is the *exact* reading the increment is trying to obtain
    /// and would have looked like good news. Freezing them here makes the
    /// measurement independent of the order two adapters happen to do their
    /// teardown in.
    private var frozen: (dropped: Int, overflows: Int, highWater: Int, resident: Int)?

    /// The longest interval between two successive drains (FR-103, AD-58).
    ///
    /// Measured here rather than in the IOProc because this is the thread that
    /// falls behind, and because AD-1 forbids adding anything to that one. It is
    /// a subtraction of two values `lastDrainAt` already holds, so nothing new is
    /// sampled — the same argument AD-45 makes for the rate check being free.
    private(set) var longestDrainGap: TimeInterval = 0
    /// The backlog waiting at the end of that longest gap, in input frames.
    ///
    /// **It never travels without the gap, and the gap never travels without
    /// it.** The drain loop sleeps 20 ms whenever the ring is empty, so an idle
    /// recording produces 20 ms gaps by design; what separates that from
    /// starvation is whether work had piled up by the time the gap ended.
    private(set) var backlogAtLongestGap: Double = 0

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

    /// The clock the rate measurement reads.
    ///
    /// Injected so a test can drive it deterministically, and because a test
    /// that sleeps to pace a synthetic producer is measuring the scheduler
    /// rather than this code. `RateCorrectionTests` did exactly that and was
    /// **flaky under load**: a true 24 kHz stream measured a few per cent low
    /// and snapped to 22050 Hz.
    ///
    /// It is also the seam FR-94 needs. The device supplies its own sample-time
    /// and host-time counters in every IOProc callback, and the honest fix is to
    /// measure the rate against those rather than against any wall clock. This
    /// is where that will attach.
    var now: () -> Date = { Date() }
    /// `Date` rather than the audio clock, deliberately: the whole failure was the
    /// audio clock not being what the app believed, so the check must come from
    /// outside it.
    ///
    /// *Qualified in increment 10.* The sentence above conflated two clocks that
    /// live in the same device and are not the same thing. What the app believed
    /// wrongly was the **format's declared rate** — a static number read from a
    /// property. `mSampleTime` is a running counter of frames the device actually
    /// produced, and on the seven affected recordings it advanced at 8000 or 5333
    /// per host second exactly as the wall clock said. So the audio clock is not
    /// the thing that lied; it is a second, independent witness that agrees, and
    /// it agrees without the scheduling jitter this one carries (AD-51).

    /// The device's own account of what it delivered (AD-51, FR-94).
    ///
    /// Absent for a device that supplies no valid timestamps, in which case
    /// everything falls back to `now()` above. Absent is not a downgrade: the
    /// wall-clock figures are what caught the original defect.
    var clock: AudioClockTap?
    /// Set once when the rate check first fails, so the failure is reported once
    /// rather than on every drained chunk.
    private(set) var rateFailure: RateFidelity?
    /// Whether `onRateDisagreement` has already fired.
    ///
    /// Separate from `rateFailure` because a *corrected* stream is not a failure
    /// and must not be recorded as one — but it is still a disagreement, and it
    /// is still reported exactly once. Without this the correction path fired the
    /// callback and then left `checkRate` free to fire it again on the next
    /// drain, which is a duplicate the wall clock's slower settling used to hide
    /// by settling too late for a second drain to happen.
    private var didReportDisagreement = false
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

    /// The drain thread's scheduling class.
    ///
    /// **A seam, so that the question can be measured rather than argued.** This
    /// thread was `.utility` from the day it was written, which is the lowest
    /// non-background class: on Apple Silicon it is scheduled on the efficiency
    /// cores and is subject to CPU throttling. If it is late, the ring overflows
    /// and the user's audio is gone — which is not the profile of background
    /// work, and 8.37 seconds went missing from one recording somewhere between
    /// the callback and this thread.
    ///
    /// Exposed rather than simply changed because `--check-drain` has to be able
    /// to sweep it and report the difference. A change that cannot be shown to
    /// improve a measured number does not ship.
    var qualityOfService: QualityOfService = .utility

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
        t.qualityOfService = qualityOfService
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
        flushConverter()
        // After the flush, so `resident` is what the flush could not move rather
        // than what it had not moved yet, and before any caller resets the ring.
        frozen = (dropped: ring.droppedSamples, overflows: ring.overflowEvents,
                  highWater: ring.highWaterFill, resident: ring.count)
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
        // The device's own account first (AD-51). It needs two callbacks rather
        // than three seconds, carries no scheduling jitter, and its tolerance is
        // computed from the measurement rather than declared.
        let audio = clock?.snapshot
        // **Where the device speaks at all, it is the only authority** (AD-51).
        // Two ticks is the threshold, not `isDecisive`: between the second
        // callback and the point the tolerance narrows enough to decide, the
        // honest answer is `settling`, and falling back to the wall clock for
        // that window puts its jitter back in exactly where the measurement is
        // still forming. It cost a test — under full-suite load the wall clock
        // read a 16 kHz stream as ~48 kHz for one drain, settled `correct`, and
        // the file came out three times too fast.
        //
        // A device that supplies no valid timestamp records no tick, and there
        // the wall clock is not a fallback but the whole check.
        if let audio, audio.ticks >= 2 {
            return RateFidelity(declaredRate: format.sampleRate,
                                framesObserved: audio.sampleAdvance,
                                elapsedSeconds: audio.elapsedSeconds,
                                correctedTo: correctedRate,
                                source: .audioClock,
                                callbackFrames: audio.largestTick)
        }
        return wallClockFidelity
    }

    /// The wall-clock measurement, always available and always the fallback.
    var wallClockFidelity: RateFidelity {
        guard let b = measureBaseline, let last = lastDrainAt else {
            return RateFidelity(declaredRate: format.sampleRate, framesObserved: 0,
                                elapsedSeconds: 0, correctedTo: correctedRate)
        }
        return RateFidelity(declaredRate: format.sampleRate,
                            framesObserved: Double(inputFramesConsumed - b.frames),
                            elapsedSeconds: last.timeIntervalSince(b.at),
                            correctedTo: correctedRate)
    }

    /// How long the opening may be held waiting for the device's own clock to
    /// become decisive before the wall clock is asked instead.
    ///
    /// **Six seconds, and it is a safety bound rather than a measurement.**
    /// AD-44's rule is that nothing reaches the file until the rate has settled,
    /// and AD-51 made the device the authority on when that is. Together those
    /// two have a failure mode neither has alone: a device delivering very large
    /// buffers takes proportionally longer to narrow its tolerance, and if it
    /// never narrows it, `pending` grows for the whole meeting and the file stays
    /// empty until stop. Two hours of held audio is about four gigabytes, and a
    /// crash loses all of it — which is exactly what FR-9's incremental commit
    /// exists to prevent.
    ///
    /// Twice the wall clock's own settling period, so a device that supplies no
    /// timestamps at all is unaffected and one that supplies slow ones is
    /// judged by the check that caught the original defect.
    static let audioClockPatience: TimeInterval = RateFidelity.settlingSeconds * 2

    /// What the device says about holes in what it handed over (AD-51, FR-94).
    ///
    /// Separate from the rate on purpose. A dropped buffer and a wrong rate are
    /// different defects that the wall clock renders as one blurred number — the
    /// missing frames lower the count and the elapsed time it is divided by
    /// keeps running, so the two errors partly cancel and neither is visible.
    var continuity: StreamContinuity {
        guard let audio = clock?.snapshot, audio.isUsable else { return .unknown }
        return StreamContinuity(missingFrames: audio.framesMissing,
                                expectedFrames: audio.sampleAdvance,
                                discontinuities: audio.discontinuities,
                                rebases: audio.rebases)
    }

    /// Host time, in seconds, of the very first sample this stream delivered.
    ///
    /// FR-97's offset between the two Streams is the difference of two of these.
    /// Absent where the device supplied no timestamps.
    var originHostSeconds: Double? { clock?.snapshot.originHostSeconds }

    /// What became of every sample the device delivered (AD-57, FR-102).
    ///
    /// **Every term is a counter this type or the ring already kept.** Nothing
    /// new is measured; the change is that the counts now leave the adapter.
    /// `inputFramesConsumed` in particular has existed since AD-44 and was
    /// discarded at this boundary, and it is the single term that separates
    /// "never got out of the ring" from "lost between the ring and the file" —
    /// which is the difference between naming this defect's mechanism and
    /// guessing it.
    var ledger: CaptureLedger {
        let channels = Double(max(1, format.channelCount))
        let r = frozen ?? (dropped: ring.droppedSamples, overflows: ring.overflowEvents,
                           highWater: ring.highWaterFill, resident: ring.count)
        return CaptureLedger(
            deviceFrames: clock?.snapshot.framesProduced ?? 0,
            droppedFrames: Double(r.dropped) / channels,
            overflows: r.overflows,
            consumedFrames: Double(inputFramesConsumed),
            residentFrames: Double(r.resident) / channels + Double(pending.count) / channels,
            writtenFrames: Double(framesWritten),
            producedFrames: Double(convertProducedFrames),
            writeFailures: writeFailures,
            writeFailureFrames: Double(writeFailureFrames),
            inputRate: effectiveRate,
            outputRate: Self.outputSampleRate)
    }

    /// The rate the converter is actually configured to read, for diagnostics
    /// that need to distinguish a rebuilt converter from a settled one.
    var converterInputRate: Double { converter?.inputFormat.sampleRate ?? 0 }

    /// How close this Stream came to outrunning this thread (AD-58, FR-103).
    var drainPressure: DrainPressure {
        let channels = Double(max(1, format.channelCount))
        let r = frozen ?? (dropped: ring.droppedSamples, overflows: ring.overflowEvents,
                           highWater: ring.highWaterFill, resident: ring.count)
        return DrainPressure(
            highWaterFrames: Double(r.highWater) / channels,
            capacityFrames: Double(ring.capacity) / channels,
            longestGapSeconds: longestDrainGap,
            backlogAtLongestGap: backlogAtLongestGap,
            inputRate: effectiveRate)
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
        Log.audio.error("rate disagreement: declared \(f.declaredRate, privacy: .public) Hz, observed \(f.observedRate, privacy: .public) Hz, ratio \(f.ratio, privacy: .public), clock \(f.source.rawValue, privacy: .public)")
        report(f)
    }

    /// One disagreement, one report.
    private func report(_ f: RateFidelity) {
        guard !didReportDisagreement else { return }
        didReportDisagreement = true
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
        let instant = now()
        if measureBaseline == nil {
            measureBaseline = (frames: inputFramesConsumed, at: instant)
        }
        // FR-103. The gap and the backlog that ended it, as a pair — see
        // `longestDrainGap`. `backlog` is what was still in the ring after this
        // read took its share, plus the share it took: the whole queue the
        // writer arrived to find.
        if let previous = lastDrainAt {
            let gap = instant.timeIntervalSince(previous)
            if gap > longestDrainGap {
                longestDrainGap = gap
                backlogAtLongestGap = Double(frames) + Double(ring.count) / Double(max(1, channels))
            }
        }
        lastDrainAt = instant

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
        var f = rateFidelity
        // The device is the authority on the rate (AD-51) and it is not allowed
        // to be the authority on *whether the recording gets written*. If its
        // own clock has not narrowed enough to decide within `audioClockPatience`,
        // the wall clock decides and the held opening reaches the file.
        if f.source == .audioClock, !f.isDecisive,
           wallClockFidelity.elapsedSeconds > Self.audioClockPatience {
            Log.audio.info("rate: the device's clock has not become decisive in \(Int(Self.audioClockPatience), privacy: .public)s; using the wall clock")
            f = wallClockFidelity
        }
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
            guard let snapped = f.correctionTarget else {
                // Not near any rate a real device uses. Keep the declared rate,
                // let the file come out wrong, and let AD-45 refuse to build
                // anything on it — guessing here is how a different defect would
                // get silently resampled into this one.
                Log.audio.error("rate disagreement x\(ratio, privacy: .public) but observed \(f.observedRate, privacy: .public) Hz is neither a whole-number factor of the declared rate nor a standard rate; keeping the declared rate and marking the stream untrustworthy")
                checkRate()
                break
            }
            if let c = makeConverter(inputRate: snapped) {
                effectiveRate = snapped
                correctedRate = snapped
                converter = c
                Log.audio.error("corrected input rate: declared \(self.format.sampleRate, privacy: .public) Hz, observed \(f.observedRate, privacy: .public) Hz, converting from \(snapped, privacy: .public) Hz")
                report(rateFidelity)
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
            convertAndAppend(src, using: converter, into: file)
        }
    }

    /// Empties the resampler's filter tail into the file (AD-57).
    ///
    /// **Found by the accounting identity, which is the point of having one.**
    /// Every capture reported a non-zero `conversionRemainder` — 20 to 400
    /// output frames, under 25 ms, noisy and not proportional to duration. The
    /// cause is that nothing ever told `AVAudioConverter` the stream had ended,
    /// so the samples inside its delay line were converted from input this
    /// process had consumed and were never emitted.
    ///
    /// The loss is small. Fixing it is not about the milliseconds: a remainder
    /// that is *always* non-zero is a remainder a reader learns to ignore, and
    /// this increment exists because a quantity nobody looked at hid a defect
    /// three orders of magnitude larger. A term that reads zero when nothing is
    /// wrong is the only kind worth reporting.
    private func flushConverter() {
        guard let file, let converter, rateSettled else { return }
        // Looped for the same reason `convertAndAppend` is: one call returns at
        // most one buffer's worth and the converter may be holding more. 64
        // passes is a bound against a converter that never reports itself dry,
        // not an expectation — a filter tail is a few hundred frames.
        for _ in 0..<64 {
            guard let out = AVAudioPCMBuffer(pcmFormat: Self.outputFormat,
                                             frameCapacity: 8192) else { return }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            switch status {
            case .haveData, .inputRanDry, .endOfStream:
                let produced = out.frameLength
                append(out, to: file)
                // Nothing left to give, or the converter has said it is finished.
                guard produced > 0, status == .haveData else { return }
            case .error:
                Log.audio.error("tail resample failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                return
            @unknown default:
                return
            }
        }
        Log.audio.error("tail flush did not run dry in 64 passes; the remainder is abandoned")
    }

    /// Hands one chunk to the converter and writes everything it yields.
    ///
    /// **Looped, and the loop is the fix.** The output buffer is sized from the
    /// chunk in hand, so it is the converter's only opportunity to return
    /// anything it is still holding from earlier chunks. A single call could shed
    /// only `outputSlackFrames` of that per chunk; under load the converter holds
    /// more than that and the audio never reaches the file. Measured with
    /// `--check-drain 20 10`, three runs each: **0.16% to 0.60% lost** on the
    /// shapes with 480- and 512-frame callbacks, **0.000%** on the shapes with
    /// 4,800-frame callbacks — which is the microphone's callback size and the
    /// System Stream's, and therefore the 380× asymmetry the real recording
    /// shows, reproduced with no audio device involved.
    ///
    /// `.haveData` means the buffer came back full and there may be more behind
    /// it. `.inputRanDry` means the converter has consumed everything it was
    /// given. Looping on the first is correct at every ratio, which sizing the
    /// buffer is not.
    private func convertAndAppend(_ src: AVAudioPCMBuffer,
                                  using converter: AVAudioConverter,
                                  into file: AVAudioFile) {
        var supplied = false
        // A bound, not an expectation: one chunk cannot need more passes than
        // its own output size divided by the buffer, and this is far above that.
        // It exists so a converter that never reports itself dry cannot spin.
        var passes = 0
        while passes < 64 {
            passes += 1
            guard let out = makeOutputBuffer(forInputFrames: src.frameLength) else { return }
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
            case .haveData, .inputRanDry, .endOfStream:
                append(out, to: file)
                guard Self.pullUntilDryOverride ?? Self.pullUntilDry else { return }
                // Anything but `.haveData` means the converter has run out, and a
                // zero-length buffer means it had nothing left to give.
                guard status == .haveData, out.frameLength > 0 else { return }
            case .error:
                Log.audio.error("resample failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                return
            @unknown default:
                return
            }
        }
        Log.audio.error("conversion did not run dry in 64 passes; the chunk is abandoned")
    }

    private func makeOutputBuffer(forInputFrames frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let ratio = Self.outputSampleRate / effectiveRate
        let slack = Self.outputSlackOverride ?? Self.outputSlackFrames
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + slack
        guard capacity > 0 else { return nil }
        return AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity)
    }

    /// Writes one converted buffer, honouring the mute and counting both halves
    /// of what can go wrong with it.
    private func append(_ out: AVAudioPCMBuffer, to file: AVAudioFile) {
        if isMuted, let ch = out.floatChannelData?[0] {
            ch.update(repeating: 0, count: Int(out.frameLength))
        }
        guard out.frameLength > 0 else { return }
        convertProducedFrames += AVAudioFramePosition(out.frameLength)
        do {
            try file.write(from: out)
            framesWritten += AVAudioFramePosition(out.frameLength)
        } catch {
            writeFailures += 1
            writeFailureFrames += AVAudioFramePosition(out.frameLength)
            Log.audio.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}
