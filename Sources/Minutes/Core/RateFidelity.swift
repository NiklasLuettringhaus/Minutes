import Foundation

/// Whether a stream's samples are at the rate the stream claims (AD-44, AD-45).
///
/// The second half of capture evidence, and the half that was missing. `AudioEvidence`
/// answers *was anything captured*, from signal, and deliberately refuses to look
/// at duration. This answers a different question — *are these samples at the rate
/// they say* — and only the ratio of sample count to elapsed time can answer it.
/// Duration is not evidence of capture here either; it is the denominator of a rate.
///
/// **Measured, not hypothesised.** Seven of sixteen recordings on the author's
/// machine held a system stream declaring 16 kHz whose real rate was 8 kHz (ratio
/// exactly 2, five recordings) or 5333 Hz (ratio exactly 3, two recordings). Speech
/// at that speed is still speech-like, so transcription did not fail — it produced
/// fluent, confidently formatted, entirely invented dialogue for the remote
/// participant, and the title, tags and summary were then derived from the
/// fabrication. Every affected recording had a Bluetooth headset as the *input*
/// device; every microphone stream was correct.
///
/// Every one of those seven passed `AudioEvidence`, because a stream at three
/// times speed is full of signal.
///
/// This type is built on the **observable** rather than on the mechanism. A rate
/// misread, a dropped-buffer bug, a converter misconfiguration and a clock drift
/// all present identically — a sample count that disagrees with the time it took to
/// record — so one check catches the class, and it holds even if the diagnosis of
/// this particular defect turns out to be wrong.
struct RateFidelity: Equatable, Sendable, Codable {
    /// The rate the stream's format claims, in Hz.
    var declaredRate: Double
    /// Input frames the writer has consumed.
    var framesObserved: Double
    /// Wall-clock seconds the stream has been running.
    var elapsedSeconds: TimeInterval
    /// Which clock produced `framesObserved` and `elapsedSeconds` (AD-51).
    ///
    /// **Absent means the wall clock**, which is what every record written before
    /// increment 10 used and what a device supplying no timestamps still uses.
    /// It is not a quality rating: the wall-clock figures were what caught the
    /// original defect, and they remain the fallback rather than a downgrade.
    var source: Source = .wallClock

    /// The largest single callback seen, in frames. Zero when unknown.
    ///
    /// Only meaningful with `source == .audioClock`, where it is the
    /// quantisation term of `appliedTolerance`.
    var callbackFrames: Double = 0

    /// The rate the writer actually converted from, when it refused to believe
    /// `declaredRate` and used the observation instead (AD-44).
    ///
    /// Present means the disagreement was **corrected at capture time**, so the
    /// file on disk is right and the recording is trustworthy. The declared and
    /// observed rates are still recorded, because what happened is worth keeping:
    /// a record that hid its own correction would make this defect invisible
    /// again, just at a different layer.
    var correctedTo: Double?

    /// How fast samples are really arriving, in Hz. Zero before anything arrives.
    var observedRate: Double {
        elapsedSeconds > 0 ? framesObserved / elapsedSeconds : 0
    }

    /// `declared / observed`. 1 is correct; the real failures measured exactly 2 and 3.
    var ratio: Double {
        observedRate > 0 ? declaredRate / observedRate : 0
    }

    enum Source: String, Equatable, Sendable, Codable {
        /// `frames / (now - started)`. Carries scheduling jitter, and needs the
        /// wide window and settling period AD-44 declared.
        case wallClock
        /// The device's own sample-time advance over its own host-time elapsed
        /// (AD-51). No jitter, and a tolerance that narrows with the window.
        case audioClock
    }

    /// How far the two rates may disagree before the recording is not trustworthy.
    ///
    /// **12%.** The gap it has to live inside is wide and was measured on both
    /// sides: the nine correct recordings sit at ratios of **1.00 to 1.03**, and the
    /// closest failure is **2.00**. Anything from about 1.05 to 1.9 would separate
    /// them, so this is not a tuned number — it is the middle of a factor-of-two
    /// gap with nothing in it.
    ///
    /// It is set well above the observed 3% because the honest sources of drift are
    /// real: Bluetooth clock drift, a device switch mid-Session, and the fact that
    /// elapsed time is measured by the writer and not by the audio clock. A false
    /// positive here would refuse metadata on a sound recording, which is a worse
    /// trade than missing a hypothetical 10% error that no observed defect produces.
    ///
    /// **This is the wall clock's tolerance, and since increment 10 the wall clock
    /// is the fallback** (AD-51). Where the device supplies its own counters,
    /// `appliedTolerance` computes a much tighter figure from the measurement
    /// rather than declaring one — the last clause above is the admission that
    /// this number was absorbing a measurement problem rather than measuring.
    static let tolerance = 0.12

    /// How long to let a stream settle before believing its rate.
    ///
    /// **3 seconds.** The first buffers arrive irregularly — the tap starts, the
    /// aggregate device spins up, the ring fills — so an early ratio is noise. Three
    /// seconds is long enough for that to wash out and short enough that a
    /// disagreement is caught while the user is still in the meeting, which is the
    /// point of checking during the Session rather than at the end.
    ///
    /// Below this, `verdict` is `.settling` and never `.wrong`. A capture shorter
    /// than this is judged at stop, where there is nothing left to settle.
    static let settlingSeconds: TimeInterval = 3

    enum Verdict: Equatable, Sendable {
        /// Not enough has arrived to judge. Never a failure.
        case settling
        case correct
        /// The samples are not at the declared rate. Carries the ratio, because
        /// "about twice as fast" is the fact a reader needs.
        case wrong(ratio: Double)
    }

    /// The tolerance actually applied to this measurement (AD-51).
    ///
    /// On the wall clock it is the declared 12% and nothing more can be said. On
    /// the audio clock it is **computed from the measurement itself**: one
    /// callback of frames over the frames measured, plus an allowance for two
    /// oscillators. That first term shrinks as the recording runs, so a
    /// two-hour meeting is judged far more tightly than its first second — which
    /// is the property a declared percentage cannot have, and the reason FR-94
    /// could ask for the 12% to "shrink or disappear" at all.
    var appliedTolerance: Double {
        switch source {
        case .wallClock:
            return Self.tolerance
        case .audioClock:
            guard framesObserved > 0 else { return Self.tolerance }
            let quantisation = callbackFrames > 0 ? callbackFrames / framesObserved : 0
            return quantisation + AudioClock.oscillatorDrift
        }
    }

    /// How long this source needs before it can say anything.
    ///
    /// The audio clock needs a *difference*, which two callbacks supply — there
    /// is no startup transient to wait out, because neither half of the quotient
    /// is measured from the moment the stream opened. The wall clock's three
    /// seconds exist entirely to let that transient wash out.
    var settlingRequirement: TimeInterval {
        source == .audioClock ? 0 : Self.settlingSeconds
    }

    var verdict: Verdict {
        guard elapsedSeconds >= settlingRequirement, elapsedSeconds > 0,
              framesObserved > 0, declaredRate > 0 else {
            return .settling
        }
        guard isDecisive else { return .settling }
        return abs(ratio - 1) <= appliedTolerance ? .correct : .wrong(ratio: ratio)
    }

    /// Whether the measurement is tight enough to say anything at all.
    ///
    /// **Only the audio clock can be indecisive.** Its tolerance is computed and
    /// starts near 100% — two callbacks are an answer with no resolving power,
    /// and without this guard a rate out by a factor of two would read as correct
    /// in the first millisecond. The wall clock's 12% is a *declared* figure that
    /// already accepted its trade (AD-44), and re-judging it here would turn
    /// every recording ever made into `settling`.
    var isDecisive: Bool {
        source == .wallClock || appliedTolerance <= AudioClock.decisiveTolerance
    }

    /// The verdict at stop, where a short capture has to be judged on what it has.
    ///
    /// A five-second Test Playground capture (FR-47) would otherwise always come
    /// back `.settling` and never be checkable at all.
    var finalVerdict: Verdict {
        let floor: TimeInterval = source == .audioClock ? 0 : 0.5
        guard framesObserved > 0, declaredRate > 0, elapsedSeconds > floor else { return .settling }
        guard isDecisive else { return .settling }
        return abs(ratio - 1) <= appliedTolerance ? .correct : .wrong(ratio: ratio)
    }

    var isTrustworthy: Bool {
        if correctedTo != nil { return true }
        if case .wrong = finalVerdict { return false }
        return true
    }

    /// The nearest rate a real audio device would actually use.
    ///
    /// Snapping is what makes correction safe. The observation carries noise — the
    /// wall clock includes the moments before the first sample arrived — so a true
    /// 16 kHz reads as 15935, and converting from 15935 would be very slightly
    /// wrong for ever. The standard rates are far enough apart that a 5% window
    /// around each cannot reach its neighbour.
    ///
    /// Returns nil when the observation is not near any of them, which is the
    /// case the app must *not* guess at: it keeps the declared rate, records the
    /// disagreement and refuses to derive anything (FR-85, FR-86).
    static func standardRate(nearest observed: Double) -> Double? {
        let standard: [Double] = [8_000, 11_025, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]
        return standard.first { abs(observed - $0) / $0 <= 0.05 }
    }

    /// What happened, in a sentence a person can act on.
    ///
    /// Names both rates, because the whole failure was the app believing one number
    /// while the device used another — and a reader who cannot see both numbers
    /// cannot tell this from any other audio problem.
    var explanation: String? {
        // A corrected stream has nothing to explain to the user: the file is
        // right. What happened is in the log and in the record.
        guard correctedTo == nil else { return nil }
        guard case .wrong(let r) = finalVerdict else { return nil }
        let speed = r > 1 ? "faster" : "slower"
        return String(format:
            "Audio arrived at about %.0f Hz while Minutes was told to expect %.0f Hz, "
            + "so the recording plays about %.1f times %@ than real time and its transcript "
            + "cannot be trusted.",
            observedRate, declaredRate, r > 1 ? r : 1 / r, speed)
    }

    /// The integer factor the rates are out by, when it is one.
    ///
    /// Used by repair (FR-88): the true rate is the declared rate divided by this,
    /// which is more accurate than the raw observation. The empirical figure reads a
    /// few per mil low because the wall clock includes the moments before the first
    /// sample arrived and after the last — that is how a true 8000 Hz measured as
    /// 7919 to 7996 across five recordings.
    ///
    /// Returns nil unless the observation is within 5% of a small integer, because
    /// a non-integer ratio is a different defect and must not be silently rounded
    /// into this one.
    var integerRatio: Int? {
        // `finalVerdict` rather than `verdict`, so this answers "what is the
        // ratio" for any stream that has produced enough to judge, including
        // mid-Session where the live correction needs it.
        guard case .wrong(let r) = finalVerdict else { return nil }
        let nearest = r.rounded()
        guard nearest >= 2, nearest <= 8, abs(r - nearest) / nearest <= 0.05 else { return nil }
        return Int(nearest)
    }

    /// The rate to convert from, when the samples are not at the declared rate.
    ///
    /// **Prefers `declared / integerRatio` over the raw observation**, and that
    /// order matters. The declared rate is exact and the ratio is a small
    /// integer, so their quotient is exact; the observation carries the noise of
    /// whatever clock measured it. `WavRateRepair` has documented this since
    /// increment 8 — "the true rate is `declared / integerRatio`, **not** the
    /// raw observation" — but the live correction path snapped the observation
    /// anyway, and that inconsistency was a real defect.
    ///
    /// It showed up as a **flaky test**. 22050 Hz and 24000 Hz are 8.8% apart
    /// and `standardRate(nearest:)` accepts a 5% window, so a true 24000 Hz
    /// measured 4% low under CPU load snapped to 22050 and the recording came
    /// out wrong. Under the ratio rule the same measurement gives
    /// `48000 / 2 = 24000` exactly, and load cannot move it.
    ///
    /// Falls back to snapping when there is no integer ratio, and returns nil
    /// when neither applies — the case the app must refuse rather than guess.
    var correctionTarget: Double? {
        if let ratio = integerRatio { return (declaredRate / Double(ratio)).rounded() }
        return Self.standardRate(nearest: observedRate)
    }

    static let unknown = RateFidelity(declaredRate: 0, framesObserved: 0, elapsedSeconds: 0)

    /// Hand-written for the reason the spine's Decodable-evolution convention
    /// gives: Swift ignores a property's default when the key is absent and
    /// throws `keyNotFound` instead, which is how one added field once orphaned
    /// five real recordings. `source` and `callbackFrames` are new in
    /// increment 10 and every record written before it has neither.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        declaredRate = try c.decodeIfPresent(Double.self, forKey: .declaredRate) ?? 0
        framesObserved = try c.decodeIfPresent(Double.self, forKey: .framesObserved) ?? 0
        elapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
        correctedTo = try c.decodeIfPresent(Double.self, forKey: .correctedTo)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .wallClock
        callbackFrames = try c.decodeIfPresent(Double.self, forKey: .callbackFrames) ?? 0
    }

    init(declaredRate: Double, framesObserved: Double, elapsedSeconds: TimeInterval,
         correctedTo: Double? = nil, source: Source = .wallClock,
         callbackFrames: Double = 0) {
        self.declaredRate = declaredRate
        self.framesObserved = framesObserved
        self.elapsedSeconds = elapsedSeconds
        self.correctedTo = correctedTo
        self.source = source
        self.callbackFrames = callbackFrames
    }
}
