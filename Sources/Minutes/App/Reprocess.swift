import Foundation

/// `--reprocess <meeting-id>… [--yes]`
///
/// Resets named Meetings to `captured` so the pipeline runs over them again with
/// the current code — a new transcript, new speakers, new metadata, and a
/// rewritten Note.
///
/// **It exists because the alternative was hand-editing `meeting.json`.** Three
/// recordings on the author's machine still hold the doubled transcripts and
/// phantom speakers that increment 9 and increment 10 fixed, and reprocessing
/// them is the user's decision and not the app's: it **rewrites those Notes**,
/// and a Note the user has edited by hand is theirs (FR-81, AD-40).
///
/// Three things make it safe to leave lying around:
///
///  - It never takes "all". Every Meeting is named explicitly, so there is no
///    invocation that reprocesses a library by accident.
///  - It refuses without `--yes`, and prints exactly what it would do first.
///  - It **does not enqueue the work**, for the reason `repairAndReprocess`
///    records: a short-lived process either exits before the pipeline runs — which
///    once left a meeting stuck at `captured` — or transcribes concurrently with
///    the running app, and two processes writing one `meeting.json` is worse than
///    a recording that needs one more click. `Pipeline.resumeInterrupted()` on
///    launch and the row's "Finish transcription" both already pick it up.
///
/// It does not touch audio. `WavRateRepair` is what repairs a file, and this is
/// only ever a decision to derive again from what is already there.
enum Reprocess {

    static func run() {
        let args = CommandLine.arguments
        let ids = args.dropFirst().filter { !$0.hasPrefix("--") && $0 != "--reprocess" }
        let confirmed = args.contains("--yes")
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go(ids: Array(ids), confirmed: confirmed)
            sem.signal()
        }
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

    private static func go(ids: [String], confirmed: Bool) async {
        print("=== Minutes: reprocess ===")
        guard !ids.isEmpty else {
            print("""
                Names one or more Meetings to derive again from the audio already
                on disk. Nothing is reprocessed unless you name it.

                  Minutes --reprocess <meeting-id> [<meeting-id>…] [--yes]

                Meeting ids are the directory names under
                ~/Library/Application Support/Minutes/Meetings, and --doctor
                lists them beside the Note each one wrote.
                """)
            return
        }

        let store = MeetingStore.shared
        var found: [Meeting] = []
        for id in ids {
            guard let m = try? await store.load(id: id) else {
                print("  not found: \(id)")
                continue
            }
            guard await store.hasAudio(id: id) else {
                print("  no audio on disk, cannot reprocess: \(id)")
                continue
            }
            found.append(m)
        }
        guard !found.isEmpty else { return }

        print("\nThis will re-derive \(found.count) meeting(s) and REWRITE their notes:")
        for m in found {
            let note = m.noteFilename ?? "no note yet"
            let owned = m.noteIsUserNamed ? "  ← you named this file" : ""
            print("  \(m.id)  \(Fmt.duration(m.duration))  \(note)\(owned)")
        }

        guard confirmed else {
            print("""

                Nothing was changed. Add --yes to do it.

                What you get back: a transcript with the far end counted once,
                in-room voices with the call ruled out of them, and utterances
                ordered by when they were said. What you lose: the notes above,
                as they are now, including anything you edited in them.
                """)
            return
        }

        for m in found {
            _ = try? await store.update(id: m.id) { rec in
                rec.stage = .captured
                rec.failure = nil
            }
            print("  reset: \(m.id)")
        }
        print("""

            Done. The work is deliberately not started here — a short-lived
            process would either exit before it ran or transcribe alongside the
            running app, and two processes writing one meeting.json is worse than
            a recording that needs one more click.

            Restart Minutes, or use "Finish transcription" on each row.
            """)
    }
}
