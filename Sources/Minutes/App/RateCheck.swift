import Foundation

/// `--check-rates [--repair]` — FR-88.
///
/// Assesses every recording on disk against its own sample count, and optionally
/// repairs the ones whose true rate is recoverable and re-runs them through the
/// pipeline.
///
/// It exists as a command and not only as a button because the seven recordings
/// that prompted it were repaired from a terminal, and the next person to hit
/// this — a colleague with a Bluetooth headset — needs the same route before any
/// UI exists to click. It prints counts and rates, never a title or a transcript
/// line (PRD §9.1).
enum RateCheck {

    static func run(repair: Bool) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go(repair: repair)
            sem.signal()
        }
        // The work hops to the main actor, so the main thread must keep pumping
        // rather than block on the semaphore. Blocking it deadlocks: the first
        // version of this did, and hung for two minutes before anyone noticed.
        // `Doctor.run()` has the same loop for the same reason.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

    @MainActor
    private static func go(repair: Bool) async {
        print("=== Minutes: recording rate check ===")
        print(String(format: "tolerance %.0f%%, settling %.0fs\n",
                     RateFidelity.tolerance * 100, RateFidelity.settlingSeconds))

        let audits = await SessionCoordinator.shared.auditRates()
        guard !audits.isEmpty else { return print("no recordings on disk") }

        var failing: [SessionCoordinator.RateAudit] = []
        for a in audits {
            let parts = [("mic", a.mic), ("system", a.system)].compactMap { name, f -> String? in
                guard let f, f.declaredRate > 0 else { return nil }
                let mark = f.isTrustworthy ? " " : "!"
                return String(format: "%@%@ %.0f/%.0f Hz x%.2f", mark, name,
                              f.declaredRate, f.observedRate, f.ratio)
            }
            let flag = a.failing.isEmpty ? "  ok  " : " FAIL "
            print("\(flag)\(a.meetingID)   \(parts.joined(separator: "   "))")
            if !a.failing.isEmpty { failing.append(a) }
        }

        print("\n\(audits.count) recording(s) checked, \(failing.count) failing")
        guard !failing.isEmpty else { return }

        let fixable = failing.filter(\.repairable)
        print("\(fixable.count) can have the declared rate repaired from their own sample count")
        for a in failing where !a.repairable {
            print("  \(a.meetingID): not a whole-number factor — repairing would be guessing")
        }

        guard repair else {
            return print("\nnothing written. Re-run with --repair to fix and re-transcribe.")
        }
        print("\nrepairing and re-running:")
        for a in fixable {
            print("  \(a.meetingID) …")
            await SessionCoordinator.shared.repairAndReprocess(meetingID: a.meetingID)
        }
        // Accuracy matters more than brevity. This command repairs headers and
        // marks the recordings unfinished; it does not transcribe, because doing
        // that from a second process would race the running app over one record.
        print("")
        print("Repaired. Those recordings are now marked unfinished, and nothing was")
        print("transcribed by this command \u{2014} doing that from a second process would")
        print("race the running app over the same meeting record.")
        print("")
        print("To re-transcribe them, either:")
        print("  - quit and reopen Minutes, which resumes unfinished recordings on launch, or")
        print("  - click Finish transcription on each row in Meetings.")
        print("")
        print("Then run --check-rates again to confirm.")
    }
}
