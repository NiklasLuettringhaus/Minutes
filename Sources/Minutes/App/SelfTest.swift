import Foundation
import AppKit

/// Headless end-to-end exercise of the real pipeline: capture both Streams,
/// transcribe, diarize, attribute, derive Metadata, write a Note.
///
/// Run with `Minutes.app/Contents/MacOS/Minutes --selftest [seconds] [model]`.
/// It runs inside the signed bundle, so it exercises the same TCC identity the
/// GUI does — which is the point.
enum SelfTest {
    static func run() {
        let args = CommandLine.arguments
        let seconds = args.dropFirst().compactMap(Double.init).first ?? 8
        let model = args.first { $0.hasPrefix("openai_whisper") || $0.hasPrefix("distil") }

        setbuf(stdout, nil)
        ModelStorage.adoptLegacyDownloads()
        print("=== Minutes self-test ===")
        print("bundle:  \(Bundle.main.bundleIdentifier ?? "nil")")
        print("mic:     \(Permissions.micState().label)")

        // The work is @MainActor and AVFoundation needs a live run loop, so the
        // main thread must pump rather than block on a semaphore.
        var finished = false
        Task { @MainActor in
            if let model { Preferences.shared.model = model }
            print("model:   \(Preferences.shared.model)")
            print("notes:   \(Preferences.shared.notesFolder()?.path ?? "nil")")

            if Permissions.micState() == .notDetermined {
                print("\n-> requesting microphone access…")
                _ = await Permissions.requestMic()
                print("   now: \(Permissions.micState().label)")
            }
            guard Permissions.micState().isAuthorized else {
                print("\nFAIL: microphone not authorized. Grant it and re-run.")
                finished = true; return
            }

            print("\n-> recording \(Int(seconds))s (play audio to exercise the system stream)…")
            await SessionCoordinator.shared.start()
            guard AppState.shared.sessionState.isRecording else {
                print("FAIL: session did not start: \(AppState.shared.lastError?.localizedDescription ?? "unknown")")
                finished = true; return
            }
            for i in 1...Int(seconds) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                print("   \(i)s  mic=\(fmt(SessionCoordinator.shared.debugLevel(.mic))) system=\(fmt(SessionCoordinator.shared.debugLevel(.system)))")
            }
            await SessionCoordinator.shared.stop()
            print("-> capture stopped, processing…")

            // Wait for the pipeline to drain.
            var waited = 0.0
            var last: Stage? = nil
            while waited < 900 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 0.5
                await AppStateBridge.reloadMeetings()
                guard let m = AppState.shared.meetings.first else { continue }
                if m.stage != last {
                    last = m.stage
                    print("   stage: \(m.stage.rawValue)")
                }
                if let f = m.failure {
                    print("\nFAIL at stage \(m.stage.rawValue): \(f)")
                    finished = true; return
                }
                if m.isComplete { break }
            }

            guard let m = AppState.shared.meetings.first, m.isComplete else {
                print("\nFAIL: pipeline did not complete within \(Int(waited))s")
                finished = true; return
            }

            print("\n=== RESULT ===")
            print("title:        \(m.metadata?.title ?? "-")")
            print("tags:         \(m.metadata?.tags.joined(separator: ", ") ?? "-")")
            print("duration:     \(Fmt.duration(m.duration))")
            print("system audio: \(m.systemStreamCaptured)")
            print("diarized:     \(m.diarizationSucceeded)")
            print("backend:      \(m.metadata?.backend.rawValue ?? "-")")
            print("speakers:     \(m.speakers.map { m.displayName(for: $0) }.joined(separator: ", "))")
            print("utterances:   \(m.utterances.count)")
            print("note:         \(m.noteFilename ?? "-")")
            if let folder = Preferences.shared.notesFolder(), let f = m.noteFilename {
                let url = folder.appendingPathComponent(f)
                print("\n--- \(url.path) ---")
                print((try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)")
            }
            print("=== PASS ===")
            finished = true
        }
        while !finished {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        exit(0)
    }

    private static func fmt(_ f: Float) -> String { String(format: "%.4f", f) }
}
