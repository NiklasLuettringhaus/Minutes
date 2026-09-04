import Foundation

/// `--check-echo` — FR-89, FR-92.
///
/// Runs echo detection over every recording on disk and prints the verdict. It
/// exists for the same reason `--check-rates` does: the defect it looks for was
/// found from a terminal against a real library, and the numbers that calibrated
/// it have to stay reproducible by anyone who changes a threshold.
///
/// It is also how the gate was set. The frame threshold was calibrated against
/// text-duplicate labels in a spike; the *recording* gate needs the opposite
/// evidence — that the twelve real recordings separate into two populations with
/// a wide gap — and that is what this prints.
///
/// It prints counts, correlations and proportions. Never a title, never a
/// transcript line (PRD §9.1).
enum EchoCheck {

    static func run(diarize: Bool = false) {
        Self.alsoDiarize = diarize
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go()
            sem.signal()
        }
        // The work hops to the main actor, so the main thread pumps rather than
        // blocks. `RateCheck` and `Doctor` have the same loop for the same reason.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

    /// `--diarize` also re-clusters the affected recordings, which is the only
    /// way to check the claim that mattered most: that excluding the Echo stops
    /// the far end being counted as people in the room. Slow, so it is opt-in.
    private nonisolated(unsafe) static var alsoDiarize = false

    /// Fixed-width columns without `String(format:)`.
    ///
    /// `String(format:)` is avoided here deliberately: the first version of this
    /// used `%7s` with a Swift `String`, and `%s` wants a C string, so it
    /// dereferenced a bridged `NSString` as a `char *` and took the process down
    /// with a segfault inside `strlen`.
    private static func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
        guard s.count < width else { return s }
        let fill = String(repeating: " ", count: width - s.count)
        return right ? fill + s : s + fill
    }

    private static func rounded(_ value: Double, places: Int) -> String {
        let factor = pow(10.0, Double(places))
        let v = (value * factor).rounded() / factor
        var text = "\(v)"
        // "16.0" rather than "16.000000000000002", and never exponent notation.
        if let dot = text.firstIndex(of: "."),
           text.distance(from: dot, to: text.endIndex) > places + 1 {
            text = String(text[text.startIndex...text.index(dot, offsetBy: places)])
        }
        return text
    }

    private static func go() async {
        print("=== Minutes: echo check ===")
        let gate = Int((EchoDetector.gateFrameShare * 100).rounded())
        let search = EchoAnalysis.offsetSearch.upperBound
        let step = Int(EchoAnalysis.offsetSearchStep * 1000)
        print("frame threshold \(EchoAnalysis.frameCorrelationThreshold), "
              + "gate \(gate)% of concurrent frames, "
              + "offset searched +/-\(search) s in \(step) ms steps\n")

        let store = MeetingStore.shared
        let meetings = await store.loadAll()
        guard !meetings.isEmpty else { return print("no recordings on disk") }

        var affected = 0, clean = 0, undetermined = 0, skipped = 0
        print("  minutes  verdict        offset   peak   excluded   best-share")
        print("  " + String(repeating: "-", count: 66))

        for meeting in meetings.sorted(by: { $0.startedAt < $1.startedAt }) {
            let mic = await store.audioURL(id: meeting.id, stream: .mic)
            let system = await store.audioURL(id: meeting.id, stream: .system)
            let analysis: EchoAnalysis
            var alignment: EchoDetector.Alignment?
            do {
                // The alignment is reported separately from the verdict, because
                // the prominence threshold that judges it has to be set from
                // these numbers rather than from taste.
                if let mic, let system,
                   let streams = try? EchoDetector.read(micURL: mic, systemURL: system) {
                    alignment = EchoDetector.align(streams)
                }
                analysis = try EchoDetector.analyse(micURL: mic, systemURL: system)
            } catch {
                print("        ?  failed: \(error.localizedDescription)")
                skipped += 1
                continue
            }
            let minutes = meeting.duration / 60
            switch analysis.verdict {
            case .notApplicable:
                skipped += 1
                continue
            case .clean: clean += 1
            case .undetermined: undetermined += 1
            case .present: affected += 1
            }
            let delay = analysis.delaySeconds
                .map { "\(Int(($0 * 1000).rounded())) ms" } ?? "-"
            let peak = analysis.peakCorrelation
                .map { Self.rounded($0, places: 3) } ?? "-"
            let excluded = analysis.verdict == .present
                ? "\(Int((analysis.excludedProportion * 100).rounded()))%"
                : "-"
            let bestShare = alignment
                .map { "\(Int(($0.frameShare * 100).rounded()))%" } ?? "-"
            print("  " + Self.pad(Self.rounded(minutes, places: 1), 7, right: true)
                  + "  " + Self.pad(analysis.verdict.rawValue, 14)
                  + Self.pad(delay, 8, right: true)
                  + Self.pad(peak, 7, right: true)
                  + Self.pad(excluded, 11, right: true)
                  + Self.pad(bestShare, 13, right: true))

            // The phantom-attendee claim, checked rather than asserted. Runs the
            // real Diarizer twice — once on the recording as it is, once on the
            // Echo-muted copy — and counts the voices each time.
            if Self.alsoDiarize, analysis.verdict == .present, let mic {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("echo-check-\(meeting.id).wav")
                defer { try? FileManager.default.removeItem(at: temp) }
                do {
                    let diarizer = SpeakerKitDiarizerAdapter()
                    let before = try await diarizer.diarizeFull(url: mic)
                    try EchoDetector.writeRetained(micURL: mic, analysis: analysis, to: temp)
                    let after = try await diarizer.diarizeFull(url: temp)
                    let b = Set(before.spans.map(\.speakerIndex)).count
                    let a = Set(after.spans.map(\.speakerIndex)).count
                    print("           voices in the room: \(b) before, \(a) after")
                } catch {
                    print("           could not re-cluster: \(error.localizedDescription)")
                }
            }

            // What the Transcript rule would do to what is already on disk.
            // Read-only: this reports, it never rewrites a Meeting.
            if analysis.verdict == .present, !meeting.utterances.isEmpty {
                let shift = analysis.delaySeconds ?? 0
                let mic = meeting.utterances.filter { $0.origin == .mic }
                let system = meeting.utterances.filter { $0.origin == .system }
                let outcome = EchoDeduplication.apply(
                    mic: mic.map { .init(start: $0.start, end: $0.end, text: $0.text) },
                    system: system.map {
                        .init(start: $0.start + shift, end: $0.end + shift, text: $0.text)
                    },
                    echoFlagged: { analysis.isMostlyEcho(from: $0.start, to: $0.end) })
                let share = Int((outcome.droppedProportion * 100).rounded())
                print("           would drop \(outcome.droppedWords) of "
                      + "\(outcome.droppedWords + outcome.retainedWords) mic words "
                      + "(\(share)%), leaving \(outcome.residualDuplicateWords) "
                      + "still repeating the far end")
            }
        }

        print("")
        print("\(affected) affected, \(clean) clean, \(undetermined) undetermined, "
              + "\(skipped) with only one stream")
        if affected > 0 {
            print("")
            print("An affected recording had the microphone picking up the call through")
            print("the speakers. Minutes counts that audio once, from the call itself.")
            print("Headphones prevent it.")
        }
    }
}
