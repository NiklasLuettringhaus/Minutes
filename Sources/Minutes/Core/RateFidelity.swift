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

    /// How fast samples are really arriving, in Hz. Zero before anything arrives.
    var observedRate: Double {
        elapsedSeconds > 0 ? framesObserved / elapsedSeconds : 0
    }

    /// `declared / observed`. 1 is correct; the real failures measured exactly 2 and 3.
    var ratio: Double {
        observedRate > 0 ? declaredRate / observedRate : 0
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

    var verdict: Verdict {
        guard elapsedSeconds >= Self.settlingSeconds, framesObserved > 0, declaredRate > 0 else {
            return .settling
        }
        return abs(ratio - 1) <= Self.tolerance ? .correct : .wrong(ratio: ratio)
    }

    /// The verdict at stop, where a short capture has to be judged on what it has.
    ///
    /// A five-second Test Playground capture (FR-47) would otherwise always come
    /// back `.settling` and never be checkable at all.
    var finalVerdict: Verdict {
        guard framesObserved > 0, declaredRate > 0, elapsedSeconds > 0.5 else { return .settling }
        return abs(ratio - 1) <= Self.tolerance ? .correct : .wrong(ratio: ratio)
    }

    var isTrustworthy: Bool {
        if case .wrong = finalVerdict { return false }
        return true
    }

    /// What happened, in a sentence a person can act on.
    ///
    /// Names both rates, because the whole failure was the app believing one number
    /// while the device used another — and a reader who cannot see both numbers
    /// cannot tell this from any other audio problem.
    var explanation: String? {
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
        guard case .wrong(let r) = finalVerdict else { return nil }
        let nearest = r.rounded()
        guard nearest >= 2, nearest <= 8, abs(r - nearest) / nearest <= 0.05 else { return nil }
        return Int(nearest)
    }

    static let unknown = RateFidelity(declaredRate: 0, framesObserved: 0, elapsedSeconds: 0)
}
