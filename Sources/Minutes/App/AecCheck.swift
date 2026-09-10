import Foundation
import AVFoundation

/// `--check-aec` — FR-99, AD-48, AD-55.
///
/// **The measurement that has to come before the feature.** AD-48 permits
/// cancellation only once its benefit is measured on our own recordings with the
/// FR-93 harness, and AD-55 forbids wiring it into the path that writes the
/// user's audio until then. This is that measurement, and it is deliberately a
/// command rather than a test: the numbers have to be reproducible by whoever
/// next changes a parameter.
///
/// It reports two things, and both are release criteria:
///
///  - **ERLE**, over the frames where the far end was actually playing. The field
///    quotes 20 to 40 dB for a useful canceller, and a linear filter on these
///    recordings is bounded at 8.7 to 10.6.
///  - **What it costs where there is no echo to remove.** Microphone audio
///    recorded while the System Stream is silent can never be Echo (FR-91), and a
///    canceller that quietly takes decibels out of it is violating that floor
///    somewhere no test was looking.
///
/// With `--transcribe` it also re-transcribes the cancelled microphone and counts
/// duplicated and unique words against the stored System Stream transcript —
/// the same before/after measurement the original investigation used, which is
/// the only one that says whether the *transcript* improved.
///
/// **This is the hardest version of the problem, and that asymmetry has to be
/// stated.** Running post hoc on two independently-clocked files is precisely
/// what AD-48 says cancellation must not do; a good result here would be strong
/// evidence, and a poor one is weaker evidence against, because capture-time
/// cancellation has an aligned reference and a continuously adapting filter that
/// this does not.
enum AecCheck {

    static func run(transcribe: Bool = false) {
        // A sweepable parameter, so "the residual stage does not pay here" is a
        // measurement over a range rather than a claim about one setting.
        var p = EchoCancellation.Parameters.default
        if let i = CommandLine.arguments.firstIndex(of: "--suppression"),
           i + 1 < CommandLine.arguments.count,
           let v = Float(CommandLine.arguments[i + 1]) {
            p.overSuppression = v
        }
        if let i = CommandLine.arguments.firstIndex(of: "--taps"),
           i + 1 < CommandLine.arguments.count,
           let v = Int(CommandLine.arguments[i + 1]) {
            p.filterTaps = v
        }
        let parameters = p
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go(transcribe: transcribe, p: parameters)
            sem.signal()
        }
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

    private static func rounded(_ v: Double, _ places: Int) -> String {
        let f = pow(10.0, Double(places))
        return "\(((v * f).rounded()) / f)"
    }

    private static func go(transcribe: Bool, p: EchoCancellation.Parameters) async {
        print("=== Minutes: echo cancellation check ===")
        print("filter \(p.filterTaps) taps (\(p.filterTaps * 1000 / 16000) ms), "
              + "step \(p.stepSize), FFT \(p.fftSize), "
              + "over-suppression \(p.overSuppression), floor \(p.minimumGain)")
        print("bar: ERLE >= \(EchoCancellation.usefulERLE) dB "
              + "and <= \(EchoCancellation.permittedQuietLoss) dB lost where the far end was silent\n")

        let store = MeetingStore.shared
        let meetings = await store.loadAll()
        var cleared = 0, measured = 0

        for meeting in meetings.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let micURL = await store.audioURL(id: meeting.id, stream: .mic),
                  let sysURL = await store.audioURL(id: meeting.id, stream: .system) else { continue }
            guard let streams = try? EchoDetector.read(micURL: micURL, systemURL: sysURL) else {
                continue
            }
            let analysis = (try? EchoDetector.analyse(streams)) ?? .undetermined
            let minutes = rounded(meeting.duration / 60, 1)
            let label = analysis.verdict == .present ? "affected" : analysis.verdict.rawValue

            // Align the reference the way capture would have it: the acoustic
            // path is what the filter absorbs, and the *capture offset* — up to
            // 3.3 seconds, a hundred times larger — is not something a 100 ms
            // filter can reach. AD-53 measures it separately for exactly this.
            let offset = analysis.delaySeconds ?? 0
            let reference = shift(streams.system, by: offset, rate: streams.sampleRate,
                                  toMatch: streams.mic.count)

            let canceller = EchoCanceller(parameters: p)
            var out: [Float] = []
            out.reserveCapacity(streams.mic.count)
            var i = 0
            let block = 16_000
            while i < streams.mic.count {
                let j = min(i + block, streams.mic.count)
                out += canceller.process(mic: Array(streams.mic[i..<j]),
                                         reference: Array(reference[i..<j]))
                i = j
            }
            out += canceller.finish()
            let r = canceller.report
            measured += 1
            if EchoCancellation.clears(r) { cleared += 1 }

            print("  \(minutes) min  [\(label)]  offset \(Int(offset * 1000)) ms")
            print("    ERLE          \(rounded(r.erleDB, 2)) dB over "
                  + "\(r.framesReferenceActive) frames with the far end playing")
            print("    quiet loss    \(rounded(r.quietLossDB, 2)) dB over "
                  + "\(r.frames - r.framesReferenceActive) frames with it silent")
            print("    mean gain     \(rounded(r.meanGain, 3)) "
                  + "(1.0 means the residual stage found nothing to remove)")
            print("    double-talk   \(r.framesDoubleTalk) frames "
                  + "(\(r.framesReferenceActive > 0 ? r.framesDoubleTalk * 100 / r.framesReferenceActive : 0)% of active)")
            print("    verdict       \(EchoCancellation.clears(r) ? "CLEARS THE BAR" : "does not clear the bar")")

            if transcribe, analysis.verdict == .present {
                await transcribeAndCompare(meeting: meeting, micURL: micURL,
                                           cancelled: out, rate: streams.sampleRate)
            }
        }

        print("")
        print("\(cleared) of \(measured) recording(s) clear the bar.")
        if cleared == 0 && measured > 0 {
            print("")
            print("FR-99 is therefore not implemented at capture, and AD-55 is what")
            print("says so: the component may be built and exercised offline and may")
            print("not be wired into the path that writes the user's audio until a")
            print("measurement supports it. FR-90's post-hoc rule stands.")
        }
    }

    /// Shifts the reference so sample `n` of it lines up with sample `n` of the
    /// microphone. Positive `seconds` means the microphone heard it later.
    private static func shift(_ x: [Float], by seconds: TimeInterval,
                              rate: Double, toMatch count: Int) -> [Float] {
        let samples = Int((seconds * rate).rounded())
        var out = [Float](repeating: 0, count: count)
        for n in 0..<count {
            let k = n - samples
            if k >= 0 && k < x.count { out[n] = x[k] }
        }
        return out
    }

    /// Re-transcribes the cancelled microphone and counts what changed, against
    /// the System Stream transcript already on the record.
    ///
    /// The metric is the investigation's: a mic word that duplicates a
    /// time-overlapping System Stream Utterance is pure loss, and a mic word that
    /// does not is what must survive. No ground truth is needed for that question
    /// — the far end is already recorded perfectly on the other Stream.
    private static func transcribeAndCompare(meeting: Meeting, micURL: URL,
                                             cancelled: [Float], rate: Double) async {
        let model = await MainActor.run { Preferences.shared.model }
        let engine: Transcribing = ParakeetModel.isParakeet(model)
            ? ParakeetTranscriber() : WhisperKitTranscriber()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aec-\(meeting.id).wav")
        defer { try? FileManager.default.removeItem(at: temp) }

        do {
            try write(cancelled, rate: rate, to: temp)
            let before = try await engine.transcribe(url: micURL, model: model).segments
            let after = try await engine.transcribe(url: temp, model: model).segments
            let system = meeting.utterances.filter { $0.origin == .system }
                .map { EchoDeduplication.Span(start: $0.start, end: $0.end, text: $0.text) }

            for (name, segments) in [("before", before), ("after", after)] {
                let mic = segments.map {
                    EchoDeduplication.Span(start: $0.start, end: $0.end, text: $0.text)
                }
                var duplicated = 0, unique = 0
                for span in mic {
                    let words = EchoDeduplication.tokens(span.text)
                    guard !words.isEmpty else { continue }
                    let repeats = system.contains {
                        span.overlaps($0)
                            && EchoDeduplication.similarity(words, EchoDeduplication.tokens($0.text))
                               >= EchoDeduplication.textSimilarityThreshold
                    }
                    if repeats { duplicated += words.count } else { unique += words.count }
                }
                let total = duplicated + unique
                let share = total > 0 ? duplicated * 100 / total : 0
                print("    \(name):  \(total) mic words, \(duplicated) duplicating "
                      + "the far end (\(share)%), \(unique) unique")
            }
        } catch {
            print("    could not re-transcribe: \(error.localizedDescription)")
        }
    }

    private static func write(_ samples: [Float], rate: Double, to url: URL) throws {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate,
                                      channels: 1, interleaved: true),
              let float = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                        channels: 1, interleaved: false) else {
            throw MinutesError.audioFileWriteFailed("cannot build a \(rate) Hz format")
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: out.settings)
        var offset = 0
        let chunk = 1 << 16
        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: float,
                                                frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else { break }
            for i in 0..<count { channel[i] = samples[offset + i] }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            offset += count
        }
    }
}
