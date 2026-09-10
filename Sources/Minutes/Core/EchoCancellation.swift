import Foundation

/// The contract for cancelling the far end out of the Mic Stream (FR-99, AD-48,
/// AD-55).
///
/// **Three conditions gate this, and each one is a thing the first measurement
/// got wrong rather than a preference** (AD-48 as amended):
///
///  1. It runs **at capture**, where the reference is aligned by construction and
///     the filter adapts continuously. Post hoc on two independently-clocked
///     files is the hardest version of the problem and is why the measured
///     offsets ran to 920 ms.
///  2. It includes a **non-linear residual** stage. A linear filter alone is
///     measured insufficient here — 8.7 to 10.6 dB against the 20 to 40 dB a
///     canceller needs — and that bound is what closed the *linear post-hoc*
///     route, not cancellation as such.
///  3. Its benefit is **measured on our own recordings before it is relied on**,
///     and until then it may be built and exercised offline and may not be wired
///     into the path that writes the user's audio (AD-55).
///
/// This type holds the parameters and the report. The signal processing is in
/// `EchoCanceller`, which needs Accelerate; keeping the numbers and the verdict
/// here means every one of them can be read, cited and changed without opening a
/// file full of FFTs.
struct EchoCancellation {

    /// Everything the canceller is tuned by, in one place, with its reasoning.
    struct Parameters: Equatable, Sendable {
        /// Length of the linear adaptive filter, in samples at 16 kHz.
        ///
        /// **1600 — 100 ms.** The acoustic path from a laptop speaker to its own
        /// microphone is tens of milliseconds (39 ms measured on the worst real
        /// recording), and early reflections in a small room add a few tens more.
        /// The reverberation tail is longer than this and deliberately not
        /// covered: the coherence measurement says a linear filter cannot use it
        /// anyway, so paying 16× the arithmetic to reach it would buy nothing.
        var filterTaps = 1_600

        /// NLMS step size.
        ///
        /// 0.3 — the conventional compromise. Faster converges but rings on
        /// double-talk; slower never catches a drifting delay, and these two
        /// streams are on independent clocks so the delay does drift.
        var stepSize: Float = 0.3

        /// STFT size for the residual stage, in samples. 512 at 16 kHz is 32 ms,
        /// which is long enough to resolve speech formants and short enough not
        /// to smear a syllable.
        var fftSize = 512

        /// How much the predicted residual echo power is over-estimated before
        /// it is subtracted.
        ///
        /// **2.0.** The prediction comes from a power coupling learnt on
        /// echo-only frames, and it is an under-estimate by construction: the
        /// loudspeaker path is not linear, so some of the echo's power lands in
        /// harmonics the coupling for that bin never saw. Over-estimating is the
        /// standard answer and the cost is over-suppression during double-talk,
        /// which `minimumGain` floors.
        var overSuppression: Float = 2.0

        /// The floor on any bin's gain.
        ///
        /// **0.05, about −26 dB.** Not zero: a gain that reaches zero produces
        /// musical noise, and a transcription model asked to interpret musical
        /// noise invents words — which is the failure this whole increment
        /// started from. Twenty-six decibels is already past the point where a
        /// recogniser finds anything.
        var minimumGain: Float = 0.05

        /// Smoothing on the learnt power coupling, per frame.
        ///
        /// 0.9 over 16 ms hops is a time constant of about 150 ms — long enough
        /// to average out one phoneme, short enough to follow someone moving.
        var couplingSmoothing: Float = 0.9

        /// Below this share of a frame's power being explained by the reference,
        /// the frame is treated as containing near-end speech and the coupling is
        /// **not** updated from it.
        ///
        /// This is the double-talk detector, and it is deliberately used only to
        /// freeze *learning*. It never gates the suppression itself: a Wiener
        /// gain already leaves a loud near-end voice largely intact, and gating
        /// on a detector that is 86% accurate at best would hand it the power to
        /// delete the user's own words — which is the mistake AD-47's calibration
        /// found and corrected once already.
        var doubleTalkCoupling: Float = 0.5

        static let `default` = Parameters()
    }

    /// What one run actually achieved. Every field is a count or an energy, so
    /// nothing here is an opinion.
    struct Report: Equatable, Sendable {
        /// Energy of the microphone signal over frames where the reference was
        /// active — the only frames where cancellation can do anything.
        var micEnergy: Double = 0
        /// Energy left after cancellation over the same frames.
        var outputEnergy: Double = 0
        /// Microphone energy where the reference was **silent**. This must come
        /// out unchanged: it cannot be echo (FR-91's floor).
        var quietMicEnergy: Double = 0
        var quietOutputEnergy: Double = 0

        var frames = 0
        var framesReferenceActive = 0
        var framesDoubleTalk = 0
        /// Mean gain the residual stage applied, over bins and over frames where
        /// the reference was active.
        ///
        /// **A diagnostic, and the one that tells a poor result from a broken
        /// one.** A mean gain near 1 means the suppressor decided there was
        /// almost no echo power to remove, which is a statement about the
        /// coupling estimate rather than about the recording; a mean gain well
        /// below 1 with little ERLE means it suppressed and the echo was not
        /// where it thought.
        var gainSum: Double = 0
        var gainCount: Int = 0

        var meanGain: Double { gainCount > 0 ? gainSum / Double(gainCount) : 1 }

        /// Echo return loss enhancement, in dB, over the frames where the
        /// reference was active. **The number FR-99 is judged on**: a useful
        /// canceller needs 20 to 40 dB and a linear filter here is bounded at
        /// 8.7 to 10.6.
        var erleDB: Double {
            guard micEnergy > 0, outputEnergy > 0 else { return 0 }
            return 10 * log10(micEnergy / outputEnergy)
        }

        /// How much of the user's own speech was attenuated where there was no
        /// echo to remove. **Must be ~0 dB.** Anything else is the canceller
        /// eating the room, and it is a release criterion rather than a
        /// footnote — the same status FR-91 gives the cost of exclusion.
        var quietLossDB: Double {
            guard quietMicEnergy > 0, quietOutputEnergy > 0 else { return 0 }
            return 10 * log10(quietMicEnergy / quietOutputEnergy)
        }
    }

    /// Whether a report clears the bar the research sets for a useful canceller.
    ///
    /// Stated as a function rather than left to a reader's judgement, because the
    /// whole point of FR-99's third condition is that the decision is made on a
    /// number. 20 dB is the bottom of the range the field quotes.
    static let usefulERLE = 20.0

    /// The most a canceller may attenuate audio the far end was silent for.
    ///
    /// **1 dB.** Not zero, because a filter that is adapting has a transient; but
    /// FR-91's floor says microphone audio recorded while the System Stream is
    /// silent is never Echo, and a canceller that quietly took 3 dB out of it
    /// would be violating that floor in a place no test was looking.
    static let permittedQuietLoss = 1.0

    static func clears(_ report: Report) -> Bool {
        report.erleDB >= usefulERLE && report.quietLossDB <= permittedQuietLoss
    }
}
