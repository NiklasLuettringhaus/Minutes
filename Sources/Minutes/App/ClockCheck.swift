import Foundation

/// `--check-clock [seconds]` — FR-94, FR-97.
///
/// Opens both Streams for a few seconds and prints what the *devices* say about
/// what they delivered: the rate from their own sample counters, the tolerance
/// that measurement earns, any frames they counted and this process never
/// received, and the offset between the two Streams' first samples.
///
/// It exists for the same reason `--check-rates` and `--check-echo` do. Two
/// numbers in this increment are claimed to be derived rather than tuned — the
/// tolerance and the settling point — and a claim like that is only worth
/// anything if the command that produced it is in the repository.
///
/// **It creates no Meeting and keeps no audio.** The capture writes to a
/// temporary directory which is removed on the way out, so running this costs
/// the library nothing. It prints rates, counts and milliseconds, never a title
/// and never a transcript line (PRD §9.1).
enum ClockCheck {

    static func run() {
        let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 6
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go(seconds: max(2, min(60, seconds)))
            sem.signal()
        }
        // The main thread pumps rather than blocks: AVAudioEngine needs a live
        // run loop, and `Doctor` and `RateCheck` have the same loop for the same
        // reason.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

    private static func go(seconds: Double) async {
        print("=== Minutes: audio clock check ===")
        print("decisive tolerance \(AudioClock.decisiveTolerance) "
              + "(half the 8.8% gap between 22050 and 24000 Hz), "
              + "drift allowance \(AudioClock.oscillatorDrift)\n")

        guard MicCapture.authorizationStatus() == .authorized else {
            print("microphone not authorised — grant it and re-run")
            return
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-clock-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let capture = DualStreamCapture()
        do {
            try capture.start(into: dir)
        } catch {
            print("could not start capture: \(error.localizedDescription)")
            return
        }
        print("recording \(Int(seconds))s — play some audio to exercise the system stream")
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let streams = capture.stop()

        print("")
        report("microphone", streams.micRate, streams.micContinuity)
        report("system tap", streams.systemRate, streams.systemContinuity)

        print("")
        if let offset = streams.streamStartOffset {
            print(String(format: "stream start offset: %+.0f ms "
                         + "(system stream begins that much after the microphone)",
                         offset * 1000))
            // FR-6 claims the two Streams agree to within 100 ms. It is a test
            // now rather than an assertion, and this is where it is taken.
            let ok = abs(offset) <= 0.100
            print("  FR-6's +/-100 ms claim: \(ok ? "holds" : "FAILS") on this capture")
            if !ok {
                print("  the merge applies the measured offset, so the transcript is")
                print("  ordered correctly regardless — but the capture itself is not aligned")
            }
        } else {
            print("stream start offset: unknown — one of the devices supplied no host time")
        }
    }

    private static func report(_ name: String, _ rate: RateFidelity, _ cont: StreamContinuity) {
        print("\(name):")
        print("  clock:      \(rate.source.rawValue)")
        guard rate.framesObserved > 0 else {
            print("  nothing measured")
            return
        }
        print(String(format: "  declared:   %.0f Hz", rate.declaredRate))
        print(String(format: "  observed:   %.1f Hz  (x%.4f)", rate.observedRate, rate.ratio))
        print(String(format: "  tolerance:  %.4f  (%@)", rate.appliedTolerance,
                     rate.source == .audioClock ? "derived from this measurement"
                                                : "the declared wall-clock window"))
        print(String(format: "  window:     %.2f s, %.0f frames, callbacks of %.0f",
                     rate.elapsedSeconds, rate.framesObserved, rate.callbackFrames))
        let verdict: String
        switch rate.finalVerdict {
        case .settling: verdict = "settling — not enough to say"
        case .correct: verdict = "correct"
        case .wrong(let r): verdict = String(format: "WRONG by x%.3f", r)
        }
        print("  verdict:    \(verdict)")
        if cont.isMeasured {
            print(String(format: "  continuity: %.0f frames missing of %.0f (%.4f%%), %d hole(s), %d rebase(s)",
                         cont.missingFrames, cont.expectedFrames,
                         (cont.missingProportion ?? 0) * 100,
                         cont.discontinuities, cont.rebases))
        } else {
            print("  continuity: unknown")
        }
    }
}
