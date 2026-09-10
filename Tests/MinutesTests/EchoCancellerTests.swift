import XCTest
import Accelerate
@testable import Minutes

/// FR-99 / AD-48 as amended / AD-55. The canceller, on fixtures whose ground
/// truth is known by construction.
///
/// **A synthetic fixture can invent the effect you are testing for**, and this
/// project has already been caught by exactly that: two "unrelated" speech
/// streams built on one burst schedule correlated strongly on their shared
/// silences and the echo detector called them an echo — correctly. So the
/// controls here matter more than the positive cases, and every signal below is
/// built from independent pseudo-random phases rather than a shared schedule.
final class EchoCancellerTests: XCTestCase {

    private let rate = 16_000

    /// A deterministic voice-like signal: a few formant-ish tones with slow
    /// amplitude modulation, seeded so two calls with different seeds share
    /// nothing — no common envelope, no common burst schedule.
    private func voice(seconds: Double, seed: UInt64, active: Bool = true) -> [Float] {
        var rng = SplitMix(seed: seed)
        let count = Int(Double(rate) * seconds)
        let tones = (0..<4).map { _ in 90.0 + rng.next01() * 2_600 }
        let phases = (0..<4).map { _ in rng.next01() * 2 * .pi }
        // An envelope with its own random period, so two voices do not fall
        // silent together.
        let envPeriod = 0.25 + rng.next01() * 0.6
        let envPhase = rng.next01() * 2 * .pi
        var out = [Float](repeating: 0, count: count)
        guard active else { return out }
        for n in 0..<count {
            let t = Double(n) / Double(rate)
            let env = max(0, sin(2 * .pi * t / envPeriod + envPhase))
            var v = 0.0
            for (i, f) in tones.enumerated() {
                v += sin(2 * .pi * f * t + phases[i]) / Double(tones.count)
            }
            out[n] = Float(v * env * 0.35)
        }
        return out
    }

    /// The echo path: a delay, an attenuation, a short reverb tail, and — the
    /// part that matters — a **soft clipper**, which is what a laptop
    /// loudspeaker does and what makes the path non-linear. A purely linear
    /// fixture would let the NLMS stage alone pass, which would prove nothing
    /// about the claim under test.
    private func echoPath(_ x: [Float], delay: Int = 620, gain: Float = 0.5) -> [Float] {
        var out = [Float](repeating: 0, count: x.count)
        let taps: [(Int, Float)] = [(0, 1.0), (140, 0.45), (330, 0.28), (700, 0.16), (1_450, 0.08)]
        for (offset, a) in taps {
            let shift = delay + offset
            guard shift < x.count else { continue }
            for n in shift..<x.count { out[n] += a * gain * x[n - shift] }
        }
        // Soft clipping. tanh is the standard model and it puts energy into
        // harmonics that no linear filter of the reference can reach.
        for n in 0..<out.count { out[n] = tanhf(out[n] * 3.2) / 3.2 }
        return out
    }

    private func energy(_ x: [Float]) -> Double {
        var e: Float = 0
        vDSP_svesq(x, 1, &e, vDSP_Length(x.count))
        return Double(e)
    }

    private func run(mic: [Float], reference: [Float],
                     parameters: EchoCancellation.Parameters = .default)
        -> (out: [Float], report: EchoCancellation.Report) {
        let canceller = EchoCanceller(parameters: parameters)
        var out: [Float] = []
        let block = 1_600
        var i = 0
        while i < mic.count {
            let j = min(i + block, mic.count)
            out += canceller.process(mic: Array(mic[i..<j]), reference: Array(reference[i..<j]))
            i = j
        }
        out += canceller.finish()
        return (out, canceller.report)
    }

    // MARK: - The positive case

    /// Echo only, through a non-linear path. This is where ERLE has to come from.
    func testItRemovesANonLinearEchoOfTheReference() {
        let reference = voice(seconds: 20, seed: 1)
        let mic = echoPath(reference)
        let (out, report) = run(mic: mic, reference: reference)

        XCTAssertGreaterThan(report.framesReferenceActive, 100, "the fixture must exercise it")
        XCTAssertGreaterThan(report.erleDB, 6.0,
                             "ERLE was \(report.erleDB) dB")
        // And independently of the report's own bookkeeping: the output must
        // hold less energy than the microphone did.
        XCTAssertLessThan(energy(out), energy(mic) * 0.6,
                          "the output must actually be quieter than the input")
    }

    // MARK: - The controls, which matter more

    /// **Trap 3, as a test — and it is the test that decided the story.**
    ///
    /// Given a reference it has no relationship to, the canceller should remove
    /// almost nothing. It removes about **3 dB**, and that is not an artefact of
    /// the fixture: on the real library the same thing shows up far worse, where
    /// a headphones recording that can contain no echo at all reports **6.49 dB
    /// of "ERLE"** — more than two of the three genuinely affected recordings
    /// (`spikes/measurement-echo-cancellation-2026-09-04.md`). What the residual
    /// stage produces is attenuation, not cancellation.
    ///
    /// The bound below is the measured behaviour, pinned so a change to the
    /// suppressor cannot make it quietly worse. It is deliberately **not** the
    /// bar: the bar is `EchoCancellation.clears`, this fails it, and FR-99 is
    /// therefore not wired into capture (AD-55).
    func testItAttenuatesSpeechItHasNoReferenceFor() {
        let room = voice(seconds: 20, seed: 7)
        let unrelated = voice(seconds: 20, seed: 99)
        let (_, report) = run(mic: room, reference: unrelated)
        XCTAssertLessThan(report.erleDB, 4.0,
                          "removed \(report.erleDB) dB of speech it had no reference for")
        XCTAssertGreaterThan(report.erleDB, 1.0,
                             "and it does remove some — which is the whole problem, "
                             + "so a version that removed none would need re-measuring "
                             + "rather than quietly passing this")
    }

    /// **FR-91's floor, by arithmetic rather than by a branch.** Microphone audio
    /// recorded while the System Stream is silent can never be Echo, and the
    /// canceller must not touch it. This is the clause a canceller violates
    /// silently — three decibels off the user's own voice looks like nothing and
    /// is a permanent loss.
    func testItLeavesAudioAloneWhereTheFarEndWasSilent() {
        let count = rate * 12
        let room = voice(seconds: 12, seed: 3)
        let reference = [Float](repeating: 0, count: count)
        let (_, report) = run(mic: room, reference: reference)
        XCTAssertEqual(report.framesReferenceActive, 0, "the reference really is silent")
        XCTAssertLessThanOrEqual(report.quietLossDB, EchoCancellation.permittedQuietLoss,
                                 "took \(report.quietLossDB) dB out of the room")
    }

    /// Double-talk: the user speaking over the far end. Their voice must survive.
    func testTheUsersOwnVoiceSurvivesDoubleTalk() {
        let reference = voice(seconds: 20, seed: 11)
        let echo = echoPath(reference)
        let near = voice(seconds: 20, seed: 23)
        var mic = [Float](repeating: 0, count: echo.count)
        for n in 0..<mic.count { mic[n] = echo[n] + near[n] }

        let (out, report) = run(mic: mic, reference: reference)
        XCTAssertGreaterThan(report.framesDoubleTalk, 0, "the fixture must contain some")
        // The near-end voice is louder than the echo, so most of the remaining
        // energy must be the near end rather than nothing at all.
        XCTAssertGreaterThan(energy(out), energy(near) * 0.15,
                             "the user's own speech was largely deleted")
    }

    /// The bar, stated as code so nobody has to remember it.
    func testTheBarIsTwentyDecibelsAndNoQuietLoss() {
        var good = EchoCancellation.Report()
        good.micEnergy = 100; good.outputEnergy = 0.5          // 23 dB
        good.quietMicEnergy = 10; good.quietOutputEnergy = 10  // 0 dB
        XCTAssertTrue(EchoCancellation.clears(good))

        var weak = good
        weak.outputEnergy = 10                                  // 10 dB
        XCTAssertFalse(EchoCancellation.clears(weak),
                       "10 dB is the linear bound this was supposed to beat")

        var lossy = good
        lossy.quietOutputEnergy = 1                             // 10 dB of the room gone
        XCTAssertFalse(EchoCancellation.clears(lossy),
                       "no ERLE buys the right to eat the room")
    }
}

/// A small deterministic generator, so a fixture is the same on every machine
/// and on every run. `SystemRandomNumberGenerator` is neither.
private struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next01() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}
