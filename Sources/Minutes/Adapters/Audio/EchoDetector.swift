import Foundation
import AVFoundation
import Accelerate

/// Measures whether the Mic Stream was carrying the System Stream (FR-89).
///
/// The decision lives in `EchoAnalysis`; this is the measurement that feeds it.
/// Three steps, each chosen to be cheap enough to run on a 50-minute recording
/// inside the pipeline:
///
/// 1. **Delay**, from the two streams' energy envelopes rather than their
///    waveforms. Speech energy is what survives a loudspeaker and a room; phase
///    does not, which is why waveform-domain estimation on one real recording
///    returned 920 ms — a number no speaker-to-microphone path explains.
/// 2. **Per-frame correlation** at that delay, on the waveform, with a small
///    local lag search. This is the statistic the threshold was calibrated
///    against.
/// 3. **The gate**, from those same frames. Deriving it from a quantity already
///    computed avoids a second global statistic that could disagree with the
///    per-frame one.
enum EchoDetector {

    /// Envelope resolution for the delay estimate. 1 ms resolves an acoustic
    /// path of tens of milliseconds with room to spare.
    static let envelopeBinSeconds = 0.001

    /// Local lag search around the estimated delay, in seconds.
    ///
    /// ±10 ms, because the delay drifts: the two streams are captured on
    /// independent device clocks (the same fact behind AD-48) so a single global
    /// delay is only ever approximately right.
    static let localLagSeconds = 0.010

    /// Share of concurrent frames that must look like Echo before the whole
    /// recording is treated as affected.
    ///
    /// Calibrated in `EchoDetectorGateTests` against all twelve real dual-stream
    /// recordings: see `spikes/calibration-echo-threshold-2026-09-03.md`. The
    /// affected recordings put 46–49% of mic-active frames over the frame
    /// threshold; the clean ones are near zero. This sits far below the former
    /// and far above the latter.
    static let gateFrameShare = 0.10

    struct Streams {
        var mic: [Float]
        var system: [Float]
        var sampleRate: Double
    }

    enum DetectorError: LocalizedError {
        case unreadable(URL)
        case empty(URL)
        case rateMismatch(mic: Double, system: Double)
        var errorDescription: String? {
            switch self {
            case .unreadable(let u):
                return "Could not read \(u.lastPathComponent) as audio."
            case .empty(let u):
                return "\(u.lastPathComponent) holds no audio."
            case .rateMismatch(let m, let s):
                return "The two streams were recorded at different rates "
                     + "(\(Int(m)) Hz and \(Int(s)) Hz), so they cannot be compared."
            }
        }
    }

    // MARK: - Entry point

    /// Analyses a Meeting's two streams.
    ///
    /// Returns `.notApplicable` when either stream is missing (FR-7's mic-only
    /// Session is not a defect), and `.undetermined` — never `.clean` — when the
    /// comparison cannot be made (AD-49).
    static func analyse(micURL: URL?, systemURL: URL?) throws -> EchoAnalysis {
        guard let micURL, let systemURL,
              FileManager.default.fileExists(atPath: micURL.path),
              FileManager.default.fileExists(atPath: systemURL.path) else {
            return .notApplicable
        }
        let streams = try read(micURL: micURL, systemURL: systemURL)
        return analyse(streams)
    }

    static func analyse(_ s: Streams) -> EchoAnalysis {
        // A minute is the least that makes a delay estimate worth trusting.
        guard s.sampleRate > 0, min(s.mic.count, s.system.count) >= Int(s.sampleRate * 60) else {
            return .undetermined
        }
        // A System Stream with no signal in it cannot be echoed by anything.
        // That is a clean recording, not a failure to measure (FR-7 sessions
        // where system capture produced silence land here).
        guard peak(s.system) >= EchoAnalysis.activityFloor else {
            return .clean(delay: 0, frames: [])
        }
        guard let alignment = align(s) else { return .undetermined }

        // Below the gate the two streams share no structure at any offset, which
        // is itself the evidence that the microphone was not hearing the call.
        // Clean, not undetermined: we looked, and there was nothing.
        guard alignment.frameShare >= gateFrameShare else {
            Log.audio.info("""
                echo: no offset exceeds the gate (best \
                \(Int(alignment.frameShare * 100), privacy: .public)%) — clean
                """)
            return .clean(delay: alignment.offset, frames: [])
        }

        let delay = alignment.offset
        let frames = frameStatistics(s, delay: delay)
        let peak = frames.map(\.correlation).max() ?? 0
        let analysis = EchoAnalysis.make(frames: frames, delaySeconds: delay, peakCorrelation: peak)
        Log.audio.info("""
            echo: present, delay \(Int(delay * 1000), privacy: .public) ms, \
            \(Int(analysis.excludedProportion * 100), privacy: .public)% of mic activity excluded
            """)
        return analysis
    }

    // MARK: - Reading

    static func read(micURL: URL, systemURL: URL) throws -> Streams {
        let mic = try samples(of: micURL)
        let system = try samples(of: systemURL)
        // Both streams share one session clock (AD-4), so a common index is a
        // common instant and no resampling is needed to compare them.
        guard mic.rate == system.rate else {
            throw DetectorError.rateMismatch(mic: mic.rate, system: system.rate)
        }
        return Streams(mic: mic.data, system: system.data, sampleRate: mic.rate)
    }

    /// Reads a whole file as mono `Float`.
    ///
    /// Reads in chunks using the file's **own** `processingFormat`. Handing
    /// `AVAudioFile.read(into:)` a buffer in any other format raises an
    /// Objective-C exception rather than throwing, which takes the process with
    /// it — the first version of this did exactly that.
    private static func samples(of url: URL) throws -> (data: [Float], rate: Double) {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw DetectorError.unreadable(url)
        }
        guard file.length > 0 else { throw DetectorError.empty(url) }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard format.commonFormat == .pcmFormatFloat32, channels > 0 else {
            throw DetectorError.unreadable(url)
        }

        let chunk: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw DetectorError.unreadable(url)
        }
        var out = [Float]()
        out.reserveCapacity(Int(file.length))

        while file.framePosition < file.length {
            buffer.frameLength = 0
            do { try file.read(into: buffer, frameCount: chunk) } catch { break }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            if channels == 1 {
                out.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
            } else {
                // Average the channels, matching what capture writes and what the
                // transcription path sees.
                let scale = 1.0 / Float(channels)
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels { sum += data[channel][frame] }
                    out.append(sum * scale)
                }
            }
        }
        guard !out.isEmpty else { throw DetectorError.empty(url) }
        return (out, format.sampleRate)
    }

    // MARK: - Retained audio, for Diarization

    /// Writes a copy of the Mic Stream with the Echo muted, for clustering.
    ///
    /// **Diarization gets audio; the Transcript does not.** This is where the
    /// frame test's ~13% false-positive rate is affordable: clustering needs
    /// enough audio per speaker rather than all of it, and a frame lost here can
    /// never delete a word from the Transcript (AD-47).
    ///
    /// The original recording is untouched (AD-49) — this is a derived file, and
    /// callers are expected to delete it when the stage is done. Muting uses
    /// short ramps rather than hard cuts, so no click is introduced into audio a
    /// model then has to interpret.
    static func writeRetained(micURL: URL, analysis: EchoAnalysis, to destination: URL) throws {
        guard analysis.verdict == .present, analysis.excludedAnything else {
            // Nothing to do. Copying rather than muting keeps the no-echo path
            // provably identical.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: micURL, to: destination)
            return
        }
        var (samples, rate) = try samples(of: micURL)
        let ramp = max(1, Int(0.010 * rate))
        for interval in analysis.excludedIntervals {
            let start = max(0, Int(interval.start * rate))
            let end = min(samples.count, Int(interval.end * rate))
            guard start < end else { continue }
            for i in start..<end { samples[i] = 0 }
            for i in 0..<ramp where start - ramp + i >= 0 {
                samples[start - ramp + i] *= Float(ramp - i) / Float(ramp)
            }
            for i in 0..<ramp where end + i < samples.count {
                samples[end + i] *= Float(i) / Float(ramp)
            }
        }
        try write(samples, rate: rate, to: destination)
    }

    private static func write(_ samples: [Float], rate: Double, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: rate, channels: 1, interleaved: true) else {
            throw DetectorError.unreadable(url)
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let float = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: rate, channels: 1, interleaved: false) else {
            throw DetectorError.unreadable(url)
        }
        let chunk = 1 << 16
        var offset = 0
        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: float,
                                                frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else {
                throw DetectorError.unreadable(url)
            }
            for i in 0..<count { channel[i] = samples[offset + i] }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            offset += count
        }
    }

    // MARK: - Alignment

    /// What the offset search found.
    struct Alignment: Equatable, Sendable {
        /// Seconds to shift the System Stream by to line it up with the Mic
        /// Stream. Positive means the microphone heard it later.
        var offset: TimeInterval
        /// Share of sampled concurrent frames that look like Echo at that offset.
        var frameShare: Double
    }

    /// Finds the offset by the statistic that actually discriminates.
    ///
    /// **Two earlier methods were built and discarded, both because they were
    /// measured.** Correlating the two energy envelopes and taking the argmax
    /// found the two severe recordings (envelope peak 0.549 and 0.684 against
    /// 0.063–0.140 for clean ones) and was blind to the mild one (0.071, and it
    /// has 12% duplicated words). Judging that curve by peak prominence was
    /// worse than useless: a genuinely clean recording scored 6.82 and an
    /// affected one 1.18.
    ///
    /// What separates the populations is the thing the exclusion itself depends
    /// on — the **share of concurrent frames that correlate** at a given offset.
    /// Measured across all eight comparable real recordings: **0% for every
    /// clean recording** and **21%, 71%, 73%** for the three affected ones, at
    /// offsets of 129 ms, 920 ms and 39 ms respectively. None of those offsets
    /// equals the file-length difference, so that shortcut does not work either.
    ///
    /// So the search maximises frame share over a coarse grid on sampled frames,
    /// then refines. It costs more than an envelope correlation and it is the
    /// only one of the three that works.
    static func align(_ s: Streams) -> Alignment? {
        let frameLength = max(1, Int(s.sampleRate * EchoAnalysis.frameSeconds))
        let frames = min(s.mic.count, s.system.count) / frameLength
        guard frames > 8 else { return nil }

        // Sample evenly across the recording, mic-active frames only. A fixed
        // count keeps the cost independent of how long the meeting was.
        let active = (0..<frames).filter { i in
            peak(Array(s.mic[(i * frameLength)..<((i + 1) * frameLength)]))
                >= EchoAnalysis.activityFloor
        }
        guard active.count >= 8 else { return nil }
        let wanted = min(active.count, 150)
        let sample = (0..<wanted).map { active[$0 * active.count / wanted] }

        func share(at offset: TimeInterval, localLags: [Int]) -> Double {
            let shift = Int(offset * s.sampleRate)
            var concurrent = 0, over = 0
            for i in sample {
                let micStart = i * frameLength
                let micFrame = Array(s.mic[micStart..<(micStart + frameLength)])
                var isConcurrent = false
                var best = 0.0
                for lag in localLags {
                    let start = micStart - shift + lag
                    guard start >= 0, start + frameLength <= s.system.count else { continue }
                    let sysFrame = Array(s.system[start..<(start + frameLength)])
                    if peak(sysFrame) >= EchoAnalysis.activityFloor { isConcurrent = true }
                    best = max(best, abs(correlation(micFrame, sysFrame)))
                }
                if isConcurrent {
                    concurrent += 1
                    if best >= EchoAnalysis.frameCorrelationThreshold { over += 1 }
                }
            }
            return concurrent > 0 ? Double(over) / Double(concurrent) : 0
        }

        // Coarse pass: one lag per offset, because the grid step and the local
        // search are sized to cover each other.
        let step = EchoAnalysis.offsetSearchStep
        var best = Alignment(offset: 0, frameShare: -1)
        var offset = EchoAnalysis.offsetSearch.lowerBound
        while offset <= EchoAnalysis.offsetSearch.upperBound {
            let value = share(at: offset, localLags: [0])
            if value > best.frameShare { best = Alignment(offset: offset, frameShare: value) }
            offset += step
        }
        guard best.frameShare > 0 else { return Alignment(offset: 0, frameShare: 0) }

        // Fine pass around the winner, now with the local search.
        var refined = best
        for delta in stride(from: -step, through: step, by: step / 4) {
            let candidate = best.offset + delta
            let localLag = max(1, Int(localLagSeconds * s.sampleRate))
            let value = share(at: candidate, localLags: [-localLag, 0, localLag])
            if value > refined.frameShare {
                refined = Alignment(offset: candidate, frameShare: value)
            }
        }
        return refined
    }

    /// Root-mean-square energy per bin. Kept for diagnostics.
    static func envelope(_ x: [Float], sampleRate: Double,
                         binSeconds: Double = envelopeBinSeconds) -> [Float] {
        let bin = max(1, Int(sampleRate * binSeconds))
        var out = [Float](repeating: 0, count: x.count / bin)
        x.withUnsafeBufferPointer { p in
            for i in 0..<out.count {
                var mean: Float = 0
                vDSP_measqv(p.baseAddress! + i * bin, 1, &mean, vDSP_Length(bin))
                out[i] = sqrt(mean)
            }
        }
        return out
    }

    // MARK: - Frames

    static func frameStatistics(_ s: Streams, delay: TimeInterval) -> [EchoAnalysis.Frame] {
        let frameLength = max(1, Int(s.sampleRate * EchoAnalysis.frameSeconds))
        let shift = Int(delay * s.sampleRate)
        let localLag = max(1, Int(localLagSeconds * s.sampleRate))
        let lags = [-localLag, -localLag / 2, 0, localLag / 2, localLag]
        let count = min(s.mic.count, s.system.count) / frameLength
        guard count > 0 else { return [] }

        var out: [EchoAnalysis.Frame] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let micStart = i * frameLength
            let micFrame = Array(s.mic[micStart..<(micStart + frameLength)])
            let micActive = peak(micFrame) >= EchoAnalysis.activityFloor
            guard micActive else {
                out.append(.init(micActive: false, systemActive: false, correlation: 0))
                continue
            }
            // The aligned System Stream position, plus the local search.
            //
            // The microphone hears the loudspeaker *later*, so the mic frame at
            // t lines up with the System Stream at t - delay. Getting this sign
            // backwards is not a small error: it compares each mic frame with
            // audio the far end had not played yet, correlation collapses, and
            // the gate reports a badly affected recording as clean. It did.
            var systemActive = false
            var bestCorrelation = 0.0
            for lag in lags {
                let start = micStart - shift + lag
                guard start >= 0, start + frameLength <= s.system.count else { continue }
                let sysFrame = Array(s.system[start..<(start + frameLength)])
                if peak(sysFrame) >= EchoAnalysis.activityFloor { systemActive = true }
                bestCorrelation = max(bestCorrelation, abs(correlation(micFrame, sysFrame)))
            }
            out.append(.init(micActive: true,
                             systemActive: systemActive,
                             correlation: systemActive ? bestCorrelation : 0))
        }
        return out
    }

    static func rounded(_ v: Double) -> String {
        String(((v * 100).rounded() / 100))
    }

    // MARK: - Small numerics

    private static func mean(_ x: [Float]) -> Float {
        var m: Float = 0
        vDSP_meanv(x, 1, &m, vDSP_Length(x.count))
        return m
    }

    private static func energy(_ x: [Float]) -> Double {
        var e: Float = 0
        vDSP_svesq(x, 1, &e, vDSP_Length(x.count))
        return Double(e)
    }

    private static func peak(_ x: [Float]) -> Float {
        var p: Float = 0
        vDSP_maxmgv(x, 1, &p, vDSP_Length(x.count))
        return p
    }

    /// Pearson correlation, the statistic the threshold was calibrated against.
    static func correlation(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let am = mean(a), bm = mean(b)
        var ac = [Float](repeating: 0, count: a.count)
        var bc = [Float](repeating: 0, count: b.count)
        var negA = -am, negB = -bm
        vDSP_vsadd(a, 1, &negA, &ac, 1, vDSP_Length(a.count))
        vDSP_vsadd(b, 1, &negB, &bc, 1, vDSP_Length(b.count))
        let denom = sqrt(energy(ac) * energy(bc))
        guard denom > 0 else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(ac, 1, bc, 1, &dot, vDSP_Length(ac.count))
        return Double(dot) / denom
    }
}

private extension EchoAnalysis {
    /// A clean verdict that still records what was measured, because "we looked
    /// and found nothing" is a different statement from "we did not look".
    static func clean(delay: TimeInterval,
                      frames: [EchoAnalysis.Frame],
                      peak: Double? = nil) -> EchoAnalysis {
        EchoAnalysis(verdict: .clean,
                     delaySeconds: delay,
                     peakCorrelation: peak ?? frames.map(\.correlation).max(),
                     excludedIntervals: [],
                     micActiveSeconds: Double(frames.filter(\.micActive).count) * frameSeconds,
                     excludedSeconds: 0)
    }
}
