import Foundation
import Accelerate

/// Removes the far end from the Mic Stream, with the System Stream as the
/// reference (FR-99, AD-48 as amended, AD-55).
///
/// Two stages, and the second one is the reason this is permitted at all.
///
/// **1. A linear NLMS filter.** The textbook canceller, and measured on these
/// recordings it reaches about 7.5 dB against the 20 to 40 dB that matters. It is
/// here because it is nearly free once the reference is aligned and because
/// whatever it removes is removed cleanly.
///
/// **2. A non-linear residual suppressor, on power rather than on waveform.**
/// This is the stage that can work where the filter cannot, and the reason is the
/// same fact that defeats the filter: the loudspeaker path is not linear, so the
/// echo's *waveform* is not a filtered copy of the reference — but its *power
/// envelope* still is, closely. So the suppressor learns a per-bin power coupling
/// from the reference to the microphone during echo-only frames, predicts the
/// echo's power in each bin from the reference's, and applies a Wiener gain.
/// Nothing about that requires the path to be invertible.
///
/// It is deliberately **not** gated on a double-talk detector. The detector
/// freezes *learning* only. A Wiener gain already leaves a loud near-end voice
/// largely intact in the bins it occupies, and handing an 86%-accurate detector
/// the power to delete the user's own words is the mistake AD-47's calibration
/// found and corrected once already.
///
/// Streaming by construction, so the same object serves capture (FR-99) and the
/// offline measurement that has to come first (AD-55). It is **not** real-time
/// safe and must never run inside an IOProc — AD-1's rule stands, and this runs
/// on the writer's own thread.
final class EchoCanceller {

    private let p: EchoCancellation.Parameters
    private let hop: Int

    // Linear stage.
    private var weights: [Float]
    private var history: [Float]      // most recent `filterTaps` reference samples, newest last

    // Residual stage.
    private var window: [Float]
    private var coupling: [Float]     // per bin, residual power / reference power
    private var smoothedError: [Float]
    private var smoothedReference: [Float]
    private var micTail: [Float] = []
    private var refTail: [Float] = []
    private var errorTail: [Float] = []
    private var outputCarry: [Float]
    private var fft: vDSP.FFT<DSPSplitComplex>

    private(set) var report = EchoCancellation.Report()

    init(parameters: EchoCancellation.Parameters = .default) {
        self.p = parameters
        self.hop = parameters.fftSize / 2
        self.weights = [Float](repeating: 0, count: parameters.filterTaps)
        self.history = [Float](repeating: 0, count: parameters.filterTaps)
        self.window = vDSP.window(ofType: Float.self,
                                  usingSequence: .hanningDenormalized,
                                  count: parameters.fftSize, isHalfWindow: false)
        self.coupling = [Float](repeating: 0, count: parameters.fftSize / 2 + 1)
        self.smoothedError = [Float](repeating: 0, count: parameters.fftSize / 2 + 1)
        self.smoothedReference = [Float](repeating: 0, count: parameters.fftSize / 2 + 1)
        self.outputCarry = [Float](repeating: 0, count: parameters.fftSize)
        let log2n = vDSP_Length(round(log2(Double(parameters.fftSize))))
        // Force-unwrapped because a power-of-two size always has a setup, and
        // `fftSize` is a power of two by construction — a non-power-of-two here
        // is a programming error, not a runtime condition.
        self.fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
    }

    /// Processes one block. `mic` and `reference` must be the same length and
    /// already on a common clock; the filter absorbs the acoustic delay, not the
    /// capture offset (AD-53 measures that separately, and it can be a hundred
    /// times larger).
    func process(mic: [Float], reference: [Float]) -> [Float] {
        precondition(mic.count == reference.count, "the two blocks must be aligned")
        guard !mic.isEmpty else { return [] }

        // Chunked at the hop, so the double-talk decision the suppressor makes
        // reaches the adaptation within 16 ms rather than at the end of whatever
        // block a caller happened to hand over. **This is not a detail.** An
        // NLMS filter that keeps adapting while the near end is speaking chases
        // a signal its reference cannot explain, and it does not merely stop
        // helping — it diverges, and a diverged filter *adds* energy, because
        // `e = d - y` grows with `y` once `y` stops resembling the echo.
        var out: [Float] = []
        var i = 0
        while i < mic.count {
            let j = min(i + hop, mic.count)
            out += processChunk(mic: Array(mic[i..<j]), reference: Array(reference[i..<j]))
            i = j
        }
        return out
    }

    private func processChunk(mic: [Float], reference: [Float]) -> [Float] {
        // --- Stage one: linear NLMS, sample by sample ---
        var error = [Float](repeating: 0, count: mic.count)
        var estimate = [Float](repeating: 0, count: mic.count)
        let taps = p.filterTaps

        for n in 0..<mic.count {
            // Newest reference sample at the end, so the dot product lines up
            // with the weight vector without reversing either.
            history.removeFirst()
            history.append(reference[n])

            var y: Float = 0
            vDSP_dotpr(history, 1, weights, 1, &y, vDSP_Length(taps))
            estimate[n] = y
            let e = mic[n] - y
            error[n] = e

            // **No double-talk freeze here, and the reason is a measurement.**
            // The first version froze adaptation whenever the frame did not look
            // echo-dominated, where "echo-dominated" meant the filter already
            // explained half the frame's energy. That is circular: a filter
            // starting from zero explains nothing, so it froze on the first
            // frame and never adapted again — ERLE came out at 1.4e-08 dB.
            //
            // Properly regularised NLMS does not need the freeze. Double-talk
            // costs it *misadjustment*, which is a few decibels; what produced
            // the −30 dB divergence was the regularisation below, not the
            // absence of a detector.
            //
            // NLMS. Normalising by the reference energy is what makes the step
            // size independent of how loud the far end is — a fixed-step LMS
            // diverges on a loud passage and stalls on a quiet one.
            var energy: Float = 0
            vDSP_svesq(history, 1, &energy, vDSP_Length(taps))
            // **The regularisation is not an epsilon.** With `+ 1e-6` a near-
            // silent reference divides the update by almost nothing and the
            // weights explode; when the far end came back the filter produced a
            // large output that resembled nothing, and the measurement showed
            // **negative** ERLE — up to −30 dB, the canceller adding a thousand
            // times the energy it removed. The floor has to be a real fraction
            // of a plausible signal energy, and 0.01 over 1600 taps is about
            // −45 dBFS RMS: below any speech and above any silence.
            guard energy > Self.referenceEnergyFloor else { continue }
            var s = p.stepSize * e / (energy + Self.regularisation)
            vDSP_vsma(history, 1, &s, weights, 1, &weights, 1, vDSP_Length(taps))
        }

        // --- Stage two: residual suppression on power ---
        return suppress(mic: mic, reference: reference, error: error, estimate: estimate)
    }

    /// Below this the reference is silence and there is nothing to learn from.
    /// 1600 taps at −45 dBFS RMS.
    static let referenceEnergyFloor: Float = 0.005
    /// The NLMS denominator's floor. See `processChunk` — this was `1e-6` and
    /// that single number made the whole canceller diverge.
    static let regularisation: Float = 0.01

    /// Spectral residual suppression, with overlap-add.
    private func suppress(mic: [Float], reference: [Float],
                          error: [Float], estimate: [Float]) -> [Float] {
        micTail += mic
        refTail += reference
        errorTail += error

        let n = p.fftSize
        var out = [Float](repeating: 0, count: 0)

        while errorTail.count >= n {
            var errFrame = Array(errorTail[0..<n])
            var refFrame = Array(refTail[0..<n])
            let micFrame = Array(micTail[0..<n])

            vDSP.multiply(errFrame, window, result: &errFrame)
            vDSP.multiply(refFrame, window, result: &refFrame)

            let errSpectrum = magnitudeSquared(errFrame)
            let refSpectrum = magnitudeSquared(refFrame)

            let refPower = refSpectrum.reduce(0, +)
            let errPower = errSpectrum.reduce(0, +)
            var micWindowed = micFrame
            vDSP.multiply(micWindowed, window, result: &micWindowed)
            let micPower = magnitudeSquared(micWindowed).reduce(0, +)

            report.frames += 1
            let referenceActive = refPower > 1e-8
            if referenceActive { report.framesReferenceActive += 1 }

            // How much of this frame's microphone power the reference explains,
            // reported so double-talk is a number rather than an assumption.
            let explained = micPower > 0 ? min(1, (micPower - errPower) / micPower) : 0
            if referenceActive && explained < p.doubleTalkCoupling {
                report.framesDoubleTalk += 1
            }

            // **The power coupling, as a ratio of two smoothed powers.**
            //
            // The second attempt at this. The first took a per-bin *minimum* of
            // the observed ratio, on the argument that minimum statistics ignore
            // double-talk by construction — which is true, and it is also how a
            // noise estimator avoids tracking speech. It does not transfer: noise
            // is stationary and an echo is not, so the minimum over a recording
            // lands on the frames where the echo had not arrived yet or the
            // loudspeaker does not radiate. Measured, the coupling came out near
            // zero and the mean applied gain was **0.997 even at thirty-two times
            // over-suppression** — the stage was doing nothing at all, and a
            // negative result from it would have been a measurement of a bug.
            //
            // Averaging the two powers separately and dividing is the standard
            // formulation and is biased *upward* by double-talk rather than
            // downward, which `overSuppression` and `minimumGain` already bound.
            if referenceActive {
                let a = p.couplingSmoothing
                for k in 0..<coupling.count {
                    smoothedError[k] = a * smoothedError[k] + (1 - a) * errSpectrum[k]
                    smoothedReference[k] = a * smoothedReference[k] + (1 - a) * refSpectrum[k]
                    coupling[k] = smoothedReference[k] > 1e-12
                        ? smoothedError[k] / smoothedReference[k] : 0
                }
            }

            // Predict the residual echo's power from the reference's, and apply
            // a Wiener gain. Where the reference is silent the prediction is
            // zero, the gain is one, and FR-91's floor holds by arithmetic rather
            // than by a branch.
            var gains = [Float](repeating: 1, count: coupling.count)
            for k in 0..<coupling.count {
                let predicted = p.overSuppression * coupling[k] * refSpectrum[k]
                let observed = errSpectrum[k]
                guard observed > 1e-12 else { continue }
                let g = observed / (observed + predicted)
                gains[k] = max(p.minimumGain, g)
            }

            if referenceActive {
                report.gainSum += Double(gains.reduce(0, +)) / Double(gains.count)
                report.gainCount += 1
            }

            let filtered = applyGains(errFrame, gains: gains)

            // **Both energies in the time domain, over the same windowed frame.**
            // The first version of this compared a spectral sum against a
            // time-domain sum, which are different units by a factor of the
            // frame length — so it reported 25.8 dB of loss on a *silent*
            // reference, where the arithmetic guarantees the output equals the
            // input. Two of the four controls failed and both failures were this
            // one bug. Measuring the frame rather than the emitted hop also keeps
            // the overlap-add's first half-formed frame out of the figure.
            var micE: Float = 0, outE: Float = 0
            vDSP_svesq(micWindowed, 1, &micE, vDSP_Length(n))
            vDSP_svesq(filtered, 1, &outE, vDSP_Length(n))
            if referenceActive {
                report.micEnergy += Double(micE)
                report.outputEnergy += Double(outE)
            } else {
                report.quietMicEnergy += Double(micE)
                report.quietOutputEnergy += Double(outE)
            }

            // Overlap-add. The Hann window at 50% overlap sums to a constant, so
            // no normalisation is needed beyond the window itself.
            for i in 0..<n { outputCarry[i] += filtered[i] }
            out += Array(outputCarry[0..<hop])
            for i in 0..<(n - hop) { outputCarry[i] = outputCarry[i + hop] }
            for i in (n - hop)..<n { outputCarry[i] = 0 }

            micTail.removeFirst(hop)
            refTail.removeFirst(hop)
            errorTail.removeFirst(hop)
        }
        return out
    }

    /// Flushes whatever is held in the overlap buffer at the end of a stream.
    func finish() -> [Float] {
        let remaining = Array(outputCarry[0..<hop])
        outputCarry = [Float](repeating: 0, count: p.fftSize)
        micTail = []; refTail = []; errorTail = []
        return remaining
    }

    // MARK: - Small spectral helpers

    private func magnitudeSquared(_ frame: [Float]) -> [Float] {
        let n = p.fftSize
        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var out = [Float](repeating: 0, count: half + 1)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
                        vDSP_ctoz(c, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                // vDSP packs bin 0 in realp[0] and the Nyquist bin in imagp[0].
                out[0] = r[0] * r[0]
                out[half] = i[0] * i[0]
                for k in 1..<half { out[k] = r[k] * r[k] + i[k] * i[k] }
            }
        }
        // vDSP's real FFT is scaled by 2; squaring makes that 4. Constant, and it
        // cancels in every ratio below — kept unscaled deliberately rather than
        // divided out and reintroduced.
        return out
    }

    private func applyGains(_ frame: [Float], gains: [Float]) -> [Float] {
        let n = p.fftSize
        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var out = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
                        vDSP_ctoz(c, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                r[0] *= gains[0]
                i[0] *= gains[half]
                for k in 1..<half { r[k] *= gains[k]; i[k] *= gains[k] }
                fft.inverse(input: split, output: &split)
                out.withUnsafeMutableBufferPointer { o in
                    o.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
                        vDSP_ztoc(&split, 1, c, 2, vDSP_Length(half))
                    }
                }
            }
        }
        // The forward/inverse pair scales by 2n; undo it here so the output is on
        // the input's scale and the overlap-add sums to unity.
        var scale = Float(1) / Float(2 * n)
        vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(n))
        return out
    }
}
