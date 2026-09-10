import Foundation

/// Whether the Mic Stream was carrying a delayed copy of the System Stream, and
/// which parts of it were (AD-47, FR-89).
///
/// **Measured, not hypothesised.** Of twelve recordings on the author's machine
/// holding both streams, three had the microphone recording the far end through
/// the loudspeakers: cross-correlation **0.771 at a 39 ms lag**, **0.574**, and
/// **0.349**, against **0.025 or below** for the other nine. The affected calls
/// were taken on speakers or in a room; the clean ones on headphones.
///
/// The damage was not the duplicated text, though there was plenty of it — 57.6%
/// of freshly transcribed mic words on the worst recording repeated a System
/// Stream Utterance. The damage was that the far end, arriving through the
/// microphone, was clustered by diarisation as **people in the room**: six
/// in-room labels on one real recording, and the user **never identified at
/// all**, because their own voice was one polluted cluster among six.
///
/// This type is the *decision*, kept free of audio so it can be tested without
/// any. `EchoDetector` measures the per-frame statistics; everything here is a
/// pure function of them.
struct EchoAnalysis: Equatable, Sendable, Codable {

    /// One contiguous run of excluded Mic Stream audio, in seconds from the
    /// Session start (AD-4's time base).
    ///
    /// Runs rather than a per-frame mask, because the mask is what makes the
    /// decision **recomputable** (AD-49) and it has to fit in the Meeting record
    /// next to everything else. On the worst real recording 2,754 excluded
    /// frames merge into a few hundred runs.
    struct Interval: Equatable, Sendable, Codable {
        var start: TimeInterval
        var end: TimeInterval
        var duration: TimeInterval { max(0, end - start) }
    }

    enum Verdict: String, Equatable, Sendable, Codable {
        /// Only one stream existed, so there is nothing to compare (FR-7).
        case notApplicable
        /// The comparison could not be made — too little audio, or a delay
        /// estimate no speaker-to-microphone path explains. **Never treated as
        /// clean** (AD-49): this is the honest answer, not a passing grade.
        case undetermined
        /// Both streams present, and the microphone was not hearing the call.
        case clean
        /// The microphone was hearing the call, and `excludedIntervals` says where.
        case present
    }

    var verdict: Verdict
    /// What the output device said about whether Echo was possible at all
    /// (FR-98, AD-54).
    ///
    /// Copied onto the analysis rather than only onto the Meeting, because AD-49
    /// requires the *inputs to the decision* to be recorded — and since increment
    /// 10 this is one of them. Absent on every analysis made before that, which
    /// reads as "the device was not consulted".
    ///
    /// It never overwrites `verdict`. The signal measurement and the device fact
    /// are two independent statements and both are kept; what the device decides
    /// is whether the *exclusion* runs, and a disagreement is reported rather
    /// than resolved (`deviceContradictsSignal`).
    var deviceKind: OutputDeviceKind?
    /// The measured speaker-to-microphone delay. 39 ms on the worst real recording.
    var delaySeconds: TimeInterval?
    /// Peak normalised cross-correlation between the streams, for the record.
    var peakCorrelation: Double?
    var excludedIntervals: [Interval]
    /// Mic Stream audio that carried any signal at all, as the denominator that
    /// makes `excludedProportion` mean something.
    var micActiveSeconds: TimeInterval
    var excludedSeconds: TimeInterval

    /// Share of *active* microphone audio excluded. 47% on the worst real
    /// recording, 6% on the mildest.
    var excludedProportion: Double {
        micActiveSeconds > 0 ? excludedSeconds / micActiveSeconds : 0
    }

    var excludedAnything: Bool { !excludedIntervals.isEmpty }

    /// Whether Echo exclusion may act on this recording (FR-98).
    ///
    /// **The device can veto; it cannot vote.** Where it says Echo was physically
    /// impossible — sound was going into someone's ears — nothing is excluded
    /// whatever the correlation says, because the correlation is then measuring
    /// something else and acting on it would remove speech for a reason that
    /// cannot be true. Where it says loudspeakers, or says nothing, the signal
    /// decides exactly as it did before this existed.
    var mayExclude: Bool {
        verdict == .present && deviceKind?.echoPossible != false
    }

    /// The signal found an echo on a device that cannot produce one.
    ///
    /// Neither answer is preferred silently: the exclusion follows the device,
    /// and this says so out loud. A disagreement is information — most likely
    /// about the detector, since there is no acoustic path out of a headphone
    /// jack — and discarding either half would destroy the only evidence of which
    /// one is wrong.
    var deviceContradictsSignal: Bool {
        verdict == .present && deviceKind?.echoPossible == false
    }

    static let notApplicable = EchoAnalysis(
        verdict: .notApplicable, delaySeconds: nil, peakCorrelation: nil,
        excludedIntervals: [], micActiveSeconds: 0, excludedSeconds: 0)

    static let undetermined = EchoAnalysis(
        verdict: .undetermined, delaySeconds: nil, peakCorrelation: nil,
        excludedIntervals: [], micActiveSeconds: 0, excludedSeconds: 0)

    // MARK: - Tuning, and where each number comes from

    /// Frame length for the per-frame decision.
    ///
    /// **0.5 s.** Long enough for a correlation estimate to mean something at
    /// speech frequencies, short enough that muting a frame does not take a
    /// syllable of the user's own speech with it.
    static let frameSeconds: TimeInterval = 0.5

    /// Below this peak amplitude a frame holds no speech worth judging.
    ///
    /// 300 of 32,767, about −40 dBFS. Chosen from the real recordings, where the
    /// gap between room noise and speech is wide; the figure only has to be
    /// below speech and above a quiet room.
    static let activityFloor: Float = 300.0 / 32_767.0

    /// The **whole recording** is only considered affected above this peak
    /// correlation.
    ///
    /// **0.10.** The nine clean recordings measured **0.025 or below** and the
    /// three affected ones **0.349 and up** — a factor of fourteen between the
    /// populations with nothing in it. This is a gate, not a fine judgement: it
    /// keeps a headphones recording from being frame-tested at all.
    static let recordingCorrelationGate = 0.10

    /// How far apart the two Streams may be aligned, in seconds.
    ///
    /// **±2 s, and it is not an acoustic bound.** The reasoning here was wrong
    /// twice before it was measured. A speaker-to-microphone path is tens of
    /// milliseconds, so the first version searched ±250 ms, got **920 ms** on
    /// one real recording, and called it an estimator failure.
    ///
    /// It was not. The offset between the two files is the acoustic delay
    /// **plus the instant each capture started**, and those instants differ:
    /// measured across the real library, `mic.wav` and `system.wav` differ in
    /// length by **−364 ms to +3,278 ms**. The recording whose "impossible"
    /// 920 ms lag prompted the plausibility check has a **+868 ms** length
    /// difference, which accounts for nearly all of it.
    ///
    /// The three real offsets measured are 39 ms, 129 ms and 920 ms, so ±2 s
    /// covers them with room to spare while keeping the search affordable.
    static let offsetSearch: ClosedRange<TimeInterval> = -2.0...2.0

    /// Coarse step for the offset search.
    ///
    /// 20 ms, paired with the ±10 ms local search inside the frame test, so the
    /// grid has no blind spots between its points.
    static let offsetSearchStep: TimeInterval = 0.020

    /// How strongly a frame must correlate with the aligned System Stream
    /// before it is called Echo.
    ///
    /// **0.30**, and it is the *cheapest* threshold reaching 80% recall rather
    /// than a good one. Calibrated against the independent text-duplicate
    /// labels it gives **86% recall for 13% of the user's own words** on the
    /// worst recording, and only **18% recall** on the moderate one.
    ///
    /// An earlier design required *energy dominance* instead — exclude only
    /// where the aligned System Stream explains the frame's energy, so a frame
    /// carrying the user's voice as well as an echo would survive. Measured,
    /// that bought **1.1 points** over plain correlation: ERLE collapses to
    /// nothing above 4.5 dB because the echo path is not linear, which is the
    /// same fact that ruled out cancellation (AD-48).
    ///
    /// A threshold this weak is only tolerable because of where its mistakes
    /// can land. This frame test feeds **Diarization only**, which is robust to
    /// missing frames; the Transcript uses `EchoDeduplication`, which requires
    /// the text to agree and therefore cannot delete a word the user said.
    /// See `spikes/calibration-echo-threshold-2026-09-03.md`.
    static let frameCorrelationThreshold = 0.30

    /// Fraction of a candidate Utterance's frames that must be Echo before the
    /// span counts as Echo-flagged.
    ///
    /// A single Echo frame inside speech is not grounds for calling the speech
    /// around it an echo; a majority is.
    static let frameShareThreshold = 0.5

    // MARK: - The decision, as a pure function of measurements

    /// One frame's measurements, as `EchoDetector` produces them.
    struct Frame: Equatable, Sendable {
        /// The microphone carried signal here.
        var micActive: Bool
        /// The System Stream carried signal here at the aligned position.
        var systemActive: Bool
        /// How strongly the microphone frame correlates with the aligned
        /// System Stream, 0...1. Higher means more echo-like.
        var correlation: Double
    }

    /// Classifies frames, honouring the two floors of FR-91 absolutely.
    ///
    /// The floors are checked **before** the threshold and cannot be overridden
    /// by it, which is the whole point of them being floors:
    ///
    ///  - **The System Stream was silent.** Then nothing the microphone heard
    ///    can be an echo of it. 40% of mic activity on the worst real recording
    ///    falls here, and no threshold may touch it.
    ///  - **Concurrent but not dominated.** The far end was speaking and the
    ///    microphone frame's energy is *not* explained by it, so somebody in the
    ///    room was speaking too. That is Double-talk, and it is the case this
    ///    function exists to protect.
    static func classify(_ frames: [Frame],
                         threshold: Double = Self.frameCorrelationThreshold) -> [Bool] {
        frames.map { f in
            guard f.micActive else { return false }     // nothing to exclude
            guard f.systemActive else { return false }  // FR-91 floor one
            return f.correlation >= threshold           // FR-91 floor two
        }
    }

    /// Merges a per-frame mask into contiguous runs.
    static func intervals(from mask: [Bool],
                          frameSeconds: TimeInterval = Self.frameSeconds) -> [Interval] {
        var out: [Interval] = []
        var runStart: Int?
        for (i, excluded) in mask.enumerated() {
            if excluded, runStart == nil { runStart = i }
            if !excluded, let s = runStart {
                out.append(Interval(start: Double(s) * frameSeconds,
                                    end: Double(i) * frameSeconds))
                runStart = nil
            }
        }
        if let s = runStart {
            out.append(Interval(start: Double(s) * frameSeconds,
                                end: Double(mask.count) * frameSeconds))
        }
        return out
    }

    /// Builds the finished analysis from classified frames.
    static func make(frames: [Frame],
                     delaySeconds: TimeInterval,
                     peakCorrelation: Double,
                     frameSeconds: TimeInterval = Self.frameSeconds,
                     threshold: Double = Self.frameCorrelationThreshold) -> EchoAnalysis {
        let mask = classify(frames, threshold: threshold)
        let runs = intervals(from: mask, frameSeconds: frameSeconds)
        let active = Double(frames.filter(\.micActive).count) * frameSeconds
        let excluded = Double(mask.filter { $0 }.count) * frameSeconds
        return EchoAnalysis(
            verdict: runs.isEmpty ? .clean : .present,
            delaySeconds: delaySeconds,
            peakCorrelation: peakCorrelation,
            excludedIntervals: runs,
            micActiveSeconds: active,
            excludedSeconds: excluded)
    }

    /// Whether a span of the Mic Stream is mostly Echo.
    ///
    /// One half of the Transcript rule (`EchoDeduplication`), never the whole
    /// of it: on its own this is the 13%-cost test, and the Transcript requires
    /// the text to agree before anything is dropped.
    func isMostlyEcho(from start: TimeInterval, to end: TimeInterval) -> Bool {
        guard end > start else { return false }
        let overlap = excludedIntervals.reduce(0.0) { total, i in
            total + max(0, min(end, i.end) - max(start, i.start))
        }
        return overlap / (end - start) >= Self.frameShareThreshold
    }

    /// What happened, in a sentence a person can act on (FR-92).
    ///
    /// Names the cause and the remedy, because "echo detected" tells the user
    /// nothing they can do. Headphones are why the nine clean recordings are clean.
    var explanation: String? {
        switch verdict {
        case .notApplicable, .clean:
            return nil
        case .undetermined:
            return "Minutes could not tell whether your microphone also picked up "
                 + "the other side of this call, so nothing was excluded."
        case .present:
            guard mayExclude else {
                return "Minutes measured something in your microphone that looks like "
                     + "the other side of this call, but the audio was playing through "
                     + "headphones, where that cannot happen. Nothing was excluded, and "
                     + "both readings are on the record."
            }
            return String(format:
                "Your microphone also picked up the other side of this call, so about "
                + "%.0f%% of it was the call coming back through your speakers. That "
                + "audio is counted once, from the call itself, not twice. Headphones "
                + "prevent it.", excludedProportion * 100)
        }
    }

    /// Hand-written per the spine's Decodable-evolution convention.
    ///
    /// `EchoAnalysis` shipped in increment 9 with the synthesised `Codable`,
    /// which was already one added field away from throwing `keyNotFound` on
    /// every Meeting recorded since. `deviceKind` is that field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try c.decodeIfPresent(Verdict.self, forKey: .verdict) ?? .undetermined
        deviceKind = try c.decodeIfPresent(OutputDeviceKind.self, forKey: .deviceKind)
        delaySeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .delaySeconds)
        peakCorrelation = try c.decodeIfPresent(Double.self, forKey: .peakCorrelation)
        excludedIntervals = try c.decodeIfPresent([Interval].self, forKey: .excludedIntervals) ?? []
        micActiveSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .micActiveSeconds) ?? 0
        excludedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .excludedSeconds) ?? 0
    }

    init(verdict: Verdict, delaySeconds: TimeInterval?, peakCorrelation: Double?,
         excludedIntervals: [Interval], micActiveSeconds: TimeInterval,
         excludedSeconds: TimeInterval, deviceKind: OutputDeviceKind? = nil) {
        self.verdict = verdict
        self.delaySeconds = delaySeconds
        self.peakCorrelation = peakCorrelation
        self.excludedIntervals = excludedIntervals
        self.micActiveSeconds = micActiveSeconds
        self.excludedSeconds = excludedSeconds
        self.deviceKind = deviceKind
    }
}
