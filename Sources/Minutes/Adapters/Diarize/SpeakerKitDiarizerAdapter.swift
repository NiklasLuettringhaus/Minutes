import Foundation
import WhisperKit
import SpeakerKit

/// Wraps the library's `SpeakerKit` so `MLEngine` can hold it as a cached,
/// serially-accessed resource. (Named `Box` because the library already exports
/// a `SpeakerKitDiarizer` type.)
final class SpeakerKitBox {
    let kit: SpeakerKit

    init() async throws {
        do {
            // Defaults: Pyannote v4 community-1, models fetched lazily on first diarize.
            kit = try await SpeakerKit()
        } catch {
            throw MinutesError.diarizationFailed(error.localizedDescription)
        }
    }

    func unload() async { await kit.unloadModels() }
}

/// AD-11: runs on the **System Stream only**. Never a mixed stream — that is what
/// keeps the Local Speaker a fact rather than a prediction.
struct SpeakerKitDiarizerAdapter: Diarizing {

    func diarize(url: URL) async throws -> [DiarizedSpan] {
        let result = try await diarizeFull(url: url)
        return result.spans
    }

    /// Also returns the per-speaker centroid embeddings, which are what make
    /// Speaker Profiles possible across separate recordings (FR-25).
    func diarizeFull(url: URL) async throws -> (spans: [DiarizedSpan], centroids: [Int: [Float]]) {
        let box = try await MLEngine.shared.speakerKit()

        let samples: [Float]
        do {
            // 16 kHz mono, as diarize() requires.
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        } catch {
            throw MinutesError.diarizationFailed("Could not read the recording: \(error.localizedDescription)")
        }
        guard samples.count > 16000 else { return ([], [:]) }  // under ~1 s

        do {
            // options: nil => defaults, which determine the speaker count from the
            // audio rather than requiring the user to state it (FR-22).
            let r = try await box.kit.diarize(audioArray: samples, options: nil)
            var spans: [DiarizedSpan] = []
            for seg in r.segments {
                guard let id = seg.speaker.speakerId else { continue }
                spans.append(DiarizedSpan(start: TimeInterval(seg.startTime),
                                          end: TimeInterval(seg.endTime),
                                          speakerIndex: id))
            }
            spans.sort { $0.start < $1.start }
            Log.transcribe.info("diarized speakers=\(r.speakerCount) spans=\(spans.count)")
            return (spans, r.speakerCentroidEmbeddings)
        } catch {
            throw MinutesError.diarizationFailed(error.localizedDescription)
        }
    }
}
