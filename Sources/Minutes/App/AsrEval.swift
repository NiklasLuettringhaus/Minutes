import Foundation
import AVFoundation
import FluidAudio

/// NVIDIA Canary-1B-v2, reachable through the FluidAudio version already pinned.
///
/// **Measured here before it is offered anywhere.** It is deliberately not in
/// `ModelCatalog` and not selectable in the app: the point of this file is to
/// stop shipping accuracy claims that were never checked, so a new engine has to
/// earn its place with numbers first.
///
/// One structural difference decides whether it *can* be adopted: Canary returns
/// a bare `String`. Parakeet returns token timings and Whisper returns segments,
/// and Minutes needs timings — diarisation attributes a span, the note prints a
/// time, the detail pane seeks. So even a Canary that wins on accuracy cannot
/// simply replace them; it needs segment boundaries from somewhere else, which
/// is what a VAD would supply.
private struct CanaryEvalTranscriber: Transcribing {
    static let id = "canary-1b-v2"

    func transcribe(url: URL, model: String) async throws -> [TranscribedSegment] {
        let manager = try await CanaryManager.load()
        let text = try await manager.transcribe(audioURL: url)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // One span for the whole file: honest about what the engine returned.
        // Faking segment boundaries here would make a timing-less engine look
        // like it had timings.
        let seconds = (try? AVAudioFile(forReading: url))
            .map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        return [TranscribedSegment(start: 0, end: seconds, text: trimmed)]
    }
}

/// `Minutes --asr <file> [--model <id>] [--out <file.json>]`
///
/// Runs one audio file through the `Transcribing` port and prints the segments as
/// JSON. It exists so transcription quality can be **measured** instead of
/// asserted.
///
/// Every claim this project has made about transcription accuracy so far — that
/// the English-only Parakeet is "a little sharper", that one Whisper build is
/// more accurate than another — is an assumption written into `ModelCatalog`
/// specs and never checked against a reference. `--benchmark` already measures
/// speed, which is why speed claims are trustworthy and accuracy claims are not.
/// This is the missing half.
///
/// It prints only what the harness needs: timings and text of the file it was
/// pointed at. Pointed at a real meeting it will of course print that meeting's
/// words, so the harness writes those results outside the repository (PRD §9.1).
enum AsrEval {

    static func run() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--asr"), args.count > idx + 1 else {
            print("usage: Minutes --asr <file> [--model <id>] [--out <file.json>]")
            exit(2)
        }
        let url = URL(fileURLWithPath: args[idx + 1])
        let model = Self.flag("--model", args) ?? ParakeetModel.v3
        let out = Self.flag("--out", args).map { URL(fileURLWithPath: $0) }

        setbuf(stdout, nil)
        ModelStorage.adoptLegacyDownloads()

        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            code = await go(url: url, model: model, out: out)
            sem.signal()
        }
        // Same reason as RateCheck: the work hops to the main actor, so the main
        // thread pumps rather than blocks.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(code)
    }

    private static func flag(_ name: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), args.count > i + 1 else { return nil }
        return args[i + 1]
    }

    private static func go(url: URL, model: String, out: URL?) async -> Int32 {
        guard let file = try? AVAudioFile(forReading: url) else {
            FileHandle.standardError.write(Data("cannot read \(url.path)\n".utf8))
            return 1
        }
        let audioSeconds = Double(file.length) / file.fileFormat.sampleRate

        // Load the model before timing, so the figure is transcription and not a
        // cold CoreML compile (the lesson `--benchmark` already learned).
        do {
            if model == CanaryEvalTranscriber.id {
                _ = try await CanaryManager.load()
            } else if ParakeetModel.isParakeet(model) {
                _ = try await MLEngine.shared.parakeet(version: ParakeetModel.version(for: model))
            } else {
                _ = try await MLEngine.shared.whisperKit(model: model, download: true)
            }
        } catch {
            FileHandle.standardError.write(Data("model \(model): \(error.localizedDescription)\n".utf8))
            return 1
        }

        let engine: Transcribing
        if model == CanaryEvalTranscriber.id {
            engine = CanaryEvalTranscriber()
        } else if ParakeetModel.isParakeet(model) {
            engine = ParakeetTranscriber()
        } else {
            engine = WhisperKitTranscriber()
        }
        let started = Date()
        let segments: [TranscribedSegment]
        do {
            segments = try await engine.transcribe(url: url, model: model)
        } catch {
            FileHandle.standardError.write(Data("transcribe failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
        let wall = Date().timeIntervalSince(started)

        var json: [String: Any] = [
            "file": url.path,
            "model": model,
            "audioSeconds": audioSeconds,
            "wallSeconds": wall,
            "realtimeFactor": audioSeconds > 0 ? wall / audioSeconds : 0,
            "segmentCount": segments.count,
        ]
        json["segments"] = segments.map {
            ["start": $0.start, "end": $0.end, "text": $0.text]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            FileHandle.standardError.write(Data("could not encode result\n".utf8))
            return 1
        }
        if let out {
            do { try data.write(to: out) } catch {
                FileHandle.standardError.write(Data("could not write \(out.path)\n".utf8))
                return 1
            }
            print("\(segments.count) segments, \(String(format: "%.1f", wall))s "
                  + "(x\(String(format: "%.2f", audioSeconds > 0 ? wall / audioSeconds : 0)) realtime)"
                  + " -> \(out.lastPathComponent)")
        } else {
            FileHandle.standardOutput.write(data)
        }
        return 0
    }
}
