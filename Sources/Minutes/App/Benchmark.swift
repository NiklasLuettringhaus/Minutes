import Foundation
import AVFoundation

/// `Minutes --benchmark <file.wav> [model ...]`
///
/// Reports **warm** throughput: the model is loaded, a throwaway pass runs, and
/// only then is the timed pass measured. The self-test's figure includes a cold
/// CoreML load, which on a 5-second clip dominates completely and makes the
/// model look far slower than it is in use.
enum Benchmark {
    static func run() {
        let args = CommandLine.arguments
        guard let fileIdx = args.firstIndex(of: "--benchmark"), args.count > fileIdx + 1 else {
            print("usage: Minutes --benchmark <file.wav> [model ...]"); exit(2)
        }
        let url = URL(fileURLWithPath: args[fileIdx + 1])
        var models = Array(args.dropFirst(fileIdx + 2)).filter { !$0.hasPrefix("-") }
        if models.isEmpty { models = ["openai_whisper-large-v3-v20240930_turbo_632MB"] }

        setbuf(stdout, nil)
        ModelStorage.adoptLegacyDownloads()

        var finished = false
        Task { @MainActor in
            guard let f = try? AVAudioFile(forReading: url) else {
                print("cannot read \(url.path)"); finished = true; return
            }
            let seconds = Double(f.length) / f.fileFormat.sampleRate
            print("file:  \(url.lastPathComponent)  \(String(format: "%.1f", seconds))s audio")
            print("")
            print(pad("model", 46) + pad("cold", 11) + pad("warm", 11) + "warm ×realtime   30-min meeting")
            print(String(repeating: "-", count: 104))

            
            for m in models {
                guard ModelCatalog.isDownloaded(m) else {
                    print(pad(m, 46) + "not downloaded"); continue
                }
                await MLEngine.shared.unloadWhisper()   // force a genuine cold load
                let c0 = Date()
                guard let _ = try? await (ParakeetModel.isParakeet(m) ? ParakeetTranscriber() as Transcribing : WhisperKitTranscriber()).transcribe(url: url, model: m) else {
                    print(pad(m, 46) + "failed"); continue
                }
                let cold = Date().timeIntervalSince(c0)

                let w0 = Date()
                _ = try? await (ParakeetModel.isParakeet(m) ? ParakeetTranscriber() as Transcribing : WhisperKitTranscriber()).transcribe(url: url, model: m)
                let warm = Date().timeIntervalSince(w0)

                let ratio = warm / seconds
                ModelCatalog.record(ratio: ratio, for: m)
                print(pad(m, 46)
                      + pad(String(format: "%.1fs", cold), 11)
                      + pad(String(format: "%.1fs", warm), 11)
                      + pad(String(format: "%.2fx", ratio), 17)
                      + ModelCatalog.projection(ratio: ratio, minutes: 30))
            }
            print("")
            print("Cold includes loading the model onto the Neural Engine; warm is what")
            print("you actually experience once Minutes has been used once.")
            finished = true
        }
        while !finished {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        exit(0)
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? String(s.prefix(n - 1)) + " " : s + String(repeating: " ", count: n - s.count)
    }
}
