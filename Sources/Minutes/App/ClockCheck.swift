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
        // The cap is 3600 rather than 60 because the fault this command now
        // measures is **not exercised by a short capture**. A five-second probe
        // reads +35 to +62 ms of start offset where a real 42-minute meeting read
        // +1,006 ms, and the sample loss FR-102 counts appeared on two recordings
        // of 31 and 42 minutes and on neither of six shorter ones. A diagnostic
        // that cannot run for as long as the fault takes to appear is a
        // diagnostic that reports the fault absent.
        let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 6
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go(seconds: max(2, min(3600, seconds)))
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

        // FR-98 / AD-54. What the device says about itself, before anything is
        // recorded — the classification has to be checkable against a machine
        // rather than only against a unit test's literals.
        if let device = OutputDeviceMonitor.current() {
            print("output device: \(device.name ?? "unnamed") "
                  + "transport '\(device.transport)' "
                  + "dataSource '\(device.dataSource ?? "-")' -> \(device.kind.rawValue)")
            switch device.kind.echoPossible {
            case true?: print("  echo is possible here; exclusion and cancellation may act")
            case false?: print("  echo is impossible here; nothing is excluded whatever the signal says")
            case nil: print("  the device cannot say; FR-89's measurement decides, as before")
            }
        } else {
            print("output device: none reported")
        }
        print("")

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
        report("microphone", streams.micRate, streams.micContinuity,
               streams.micLedger, streams.micPressure)
        report("system tap", streams.systemRate, streams.systemContinuity,
               streams.systemLedger, streams.systemPressure)

        print("")
        reportStart(streams.startTiming)

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

    /// FR-104. Where the offset was actually spent.
    ///
    /// Printed as a decomposition rather than a total because a total is not
    /// something a change can be aimed at. The two terms sum to the offset by
    /// construction, so a reader can check the arithmetic rather than trust it.
    private static func reportStart(_ t: CaptureStartTiming) {
        guard t.isMeasured else {
            print("start timing: unknown — no host times were stamped")
            return
        }
        print("start timing (AD-59, all on the callbacks' own clock):")
        if let m = t.micPrepareSeconds {
            print(String(format: "  mic prepared in              %+7.1f ms, before either device was started", m * 1000))
        }
        if let b = t.tapChainBuildSeconds {
            print(String(format: "  tap chain built in           %+7.1f ms, before either device was started", b * 1000))
            print("    (under the previous order this was paid out of the microphone's recording time)")
        }
        if let ser = t.startSerialisationSeconds {
            print(String(format: "  between the two starts       %+7.1f ms  <- the term AD-59 owns", ser * 1000))
        }
        if let m = t.micFirstCallbackSeconds {
            print(String(format: "  mic first callback after     %+7.1f ms", m * 1000))
        }
        if let sy = t.systemFirstCallbackSeconds {
            print(String(format: "  system first callback after  %+7.1f ms", sy * 1000))
        }
        if let d = t.decomposition, let total = t.streamOffsetSeconds {
            print(String(format: "  offset %+.1f ms = %+.1f ms serialisation %+.1f ms device latency",
                         total * 1000, d.serialisation * 1000, d.deviceLatency * 1000))
        }
    }

    /// FR-102 and FR-103. The accounting identity, and how close the writer came
    /// to losing the race.
    private static func reportLedger(_ led: CaptureLedger, _ press: DrainPressure) {
        guard led.isMeasured else {
            print("  ledger:     unknown — the device supplied no counters")
            return
        }
        print(String(format: "  ledger:     device %.0f in -> dropped %.0f in %d overflow(s), consumed %.0f, written %.0f out",
                     led.deviceFrames, led.droppedFrames, led.overflows,
                     led.consumedFrames, led.writtenFrames))
        print(String(format: "              unaccounted %.0f in; converter produced %.0f, never converted %.0f, not written %.0f in %d failure(s)",
                     led.unaccountedFrames, led.producedFrames,
                     led.unproducedFrames, led.writeFailureFrames, led.writeFailures))
        if led.lostFrames >= 1 {
            print(String(format: "              LOST %.0f out (%.3f s, %.4f%%)",
                         led.lostFrames, led.lostSeconds, (led.lostProportion ?? 0) * 100))
            for a in led.attribution {
                print(String(format: "                %-45@ %.0f out", a.term as NSString, a.frames))
            }
            print("              disclosed to the reader: \(led.isWorthDisclosing ? "yes" : "no, under the 0.4 s floor")")
        } else {
            print("              every sample the device reported reached the file")
        }
        guard press.isMeasured else { return }
        print(String(format: "  pressure:   ring holds %.1f s; high water %.0f frames (%.2f%% / %.3f s)",
                     press.capacitySeconds, press.highWaterFrames,
                     (press.highWaterProportion ?? 0) * 100, press.highWaterSeconds))
        print(String(format: "              longest gap between drains %.1f ms, backlog then %.0f frames (%.3f s)",
                     press.longestGapSeconds * 1000, press.backlogAtLongestGap,
                     press.backlogAtLongestGapSeconds))
    }

    private static func report(_ name: String, _ rate: RateFidelity, _ cont: StreamContinuity,
                               _ led: CaptureLedger, _ press: DrainPressure) {
        print("\(name):")
        print("  clock:      \(rate.source.rawValue)")
        guard rate.framesObserved > 0 else {
            print("  nothing measured")
            reportLedger(led, press)
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
        reportLedger(led, press)
    }
}
