import Foundation
import WhisperKit

/// AD-14: a single serial actor owns all ML execution. Two CoreML models never
/// load concurrently, which is what keeps a 24 GB machine out of memory pressure
/// mid-meeting.
actor MLEngine {
    static let shared = MLEngine()

    private var whisper: WhisperKit?
    private var loadedModel: String?
    private var speaker: SpeakerKitBox?

    /// Loads (downloading if needed) and caches a Whisper model. Reloads only when
    /// the requested model differs from the loaded one.
    func whisperKit(model: String, download: Bool = true) async throws -> WhisperKit {
        if let w = whisper, loadedModel == model { return w }
        // Release the previous model before loading another (AD-14).
        whisper = nil
        loadedModel = nil
        do {
            let config = WhisperKitConfig(model: model,
                                          downloadBase: ModelStorage.base,
                                          verbose: false, logLevel: .error,
                                          prewarm: false, load: true, download: download)
            let w = try await WhisperKit(config)
            whisper = w
            loadedModel = model
            Log.transcribe.info("loaded whisper model \(model, privacy: .public)")
            return w
        } catch {
            throw MinutesError.modelLoadFailed(error.localizedDescription)
        }
    }

    func unloadWhisper() {
        whisper = nil
        loadedModel = nil
    }

    func speakerKit() async throws -> SpeakerKitBox {
        if let s = speaker { return s }
        let s = try await SpeakerKitBox()
        speaker = s
        return s
    }

    func unloadAll() async {
        whisper = nil; loadedModel = nil
        if let s = speaker { await s.unload() }
        speaker = nil
    }
}

/// Transcribes on-device via CoreML on the Neural Engine. No network at
/// transcription time (NFR-1); only a missing model triggers a download.
struct WhisperKitTranscriber: Transcribing {

    /// Whisper's well-known hallucinations over silence. It emits these with
    /// high confidence on an empty channel — a real run produced a phantom
    /// `Me: "Thank you."` from a microphone nobody spoke into, which invents a
    /// participant. Only ever matched against a segment's ENTIRE text, so real
    /// speech containing these words survives.
    static let hallucinations: Set<String> = [
        "thank you", "thanks", "thank you very much", "thanks for watching",
        "thank you for watching", "please subscribe", "subscribe",
        "bye", "goodbye", "bye bye", "you", "yeah", "okay", "ok", "mm", "mhm",
        "uh", "um", "hmm", "so", "and", "the", "amen", "music",
    ]

    /// Whisper's non-speech placeholders are not speech and must never reach a
    /// Note. Returns nil when nothing usable is left.
    static func clean(_ raw: String) -> String? {
        var s = raw
        // Special tokens, e.g. <|endoftext|>, <|0.00|>.
        while let r = s.range(of: "<\\|[^|]*\\|>", options: .regularExpression) {
            s.removeSubrange(r)
        }
        // Non-speech markers, e.g. [BLANK_AUDIO], [SILENCE], (music), [ Inaudible ].
        while let r = s.range(
            of: "[\\[(]\\s*(blank_?audio|silence|silent|music|inaudible|noise|laughter|applause|sound|beep|pause|no speech|foreign|sub[st]itles?[^\\])]*)\\s*[\\])]",
            options: [.regularExpression, .caseInsensitive]) {
            s.removeSubrange(r)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // A segment reduced to punctuation or a bare filler is not speech.
        let bare = s.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        if bare.isEmpty { return nil }
        // Whole-segment hallucination, not speech.
        if hallucinations.contains(bare) { return nil }
        return s
    }

    func transcribe(url: URL, model: String) async throws -> [TranscribedSegment] {
        let whisper = try await MLEngine.shared.whisperKit(model: model)

        // Load as 16 kHz mono float — the format both WhisperKit and SpeakerKit want.
        let samples: [Float]
        do {
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        } catch {
            throw MinutesError.transcriptionFailed("Could not read the recording: \(error.localizedDescription)")
        }
        guard samples.count > 1600 else { return [] }  // under ~0.1 s of audio

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            temperature: 0,
            skipSpecialTokens: true,
            withoutTimestamps: false)

        do {
            let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
            var out: [TranscribedSegment] = []
            for r in results {
                for s in r.segments {
                    guard let text = Self.clean(s.text) else { continue }
                    // Whisper emits confident-looking text over silence. Its own
                    // no-speech probability is the principled filter, and a real
                    // run showed "[BLANK_AUDIO]" and a trailing "you" without it.
                    if s.noSpeechProb > 0.6 && text.count < 25 { continue }
                    out.append(TranscribedSegment(start: TimeInterval(s.start),
                                                  end: TimeInterval(s.end),
                                                  text: text))
                }
            }
            return out.sorted { $0.start < $1.start }
        } catch {
            throw MinutesError.transcriptionFailed(error.localizedDescription)
        }
    }
}
