import XCTest
@testable import Minutes

/// Closes one of the three verification gaps the increment-4 code review recorded:
/// **`SpeakerKitVoiceEmbedder.embed()` had never executed.**
///
/// It loads real CoreML models and reads real audio, so it is guarded twice — by
/// `MINUTES_ML_TESTS=1` so the default `swift test` stays in the tens of
/// milliseconds, and by the presence of real Meetings on this machine. It reads
/// the same `mic.wav` files the app recorded; nothing is copied into the
/// repository, because those are recordings of the user's colleagues (PRD §9.1).
///
/// Run it with:
///
///     MINUTES_ML_TESTS=1 swift test --filter VoiceEmbedderIntegrationTests
final class VoiceEmbedderIntegrationTests: XCTestCase {

    private struct Recording {
        let id: String
        let micURL: URL
        let inRoomVoices: Int
        let seconds: Double
    }

    /// Every real Meeting on this machine, with how many in-room voices its
    /// `centroids.json` says the mic stream held. That count is the ground truth
    /// this test checks the embedder against — it was produced by the same models,
    /// through the diarizer, when the meeting was processed.
    private static func recordings() -> [Recording] {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Minutes/Meetings", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var out: [Recording] = []
        for d in dirs.sorted() {
            let dir = root.appendingPathComponent(d)
            let mic = dir.appendingPathComponent("mic.wav")
            guard FileManager.default.fileExists(atPath: mic.path),
                  let cdata = try? Data(contentsOf: dir.appendingPathComponent("centroids.json")),
                  let centroids = try? JSONDecoder().decode([String: [Float]].self, from: cdata)
            else { continue }
            let inRoom = centroids.keys.filter { $0 == "local" || $0.hasPrefix("room-") }.count
            let bytes = (try? FileManager.default.attributesOfItem(atPath: mic.path)[.size] as? Int) ?? 0
            // 16 kHz mono 16-bit, per the storage budget in PRD §11.
            out.append(Recording(id: d, micURL: mic, inRoomVoices: inRoom,
                                 seconds: Double(bytes ?? 0) / 32_000))
        }
        return out
    }

    private func recordingsOrSkip() throws -> [Recording] {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MINUTES_ML_TESTS"] == "1",
                          "Loads CoreML models. Set MINUTES_ML_TESTS=1 to run.")
        let r = Self.recordings()
        try XCTSkipIf(r.isEmpty, "No real Meetings with audio on this machine.")
        return r
    }

    /// The embedder runs, on real audio, and produces a usable fingerprint.
    func testEmbedProducesAUsableFingerprintFromRealAudio() async throws {
        let recordings = try recordingsOrSkip()
        // The longest recording with speech: the most representative sample, and the
        // one that exercises the dominant-speaker selection hardest.
        guard let r = recordings.filter({ $0.seconds > 60 }).max(by: { $0.seconds < $1.seconds })
        else { throw XCTSkip("no recording over a minute long") }

        let started = Date()
        let result = try await SpeakerKitVoiceEmbedder().embed(url: r.micURL)
        let elapsed = Date().timeIntervalSince(started)

        print(String(format: """
            [embedder] %@ · %.0f s of audio · %.1f s to embed
            [embedder]   voices=%d  speech=%.1f s  dominantShare=%.2f  dims=%d
            """, r.id, r.seconds, elapsed,
            result.voicesFound, result.speechSeconds, result.dominantShare,
            result.fingerprint.dimensions))

        XCTAssertTrue(result.fingerprint.isUsable)
        XCTAssertEqual(result.fingerprint.producer, SpeakerKitVoiceEmbedder.producerID)
        XCTAssertEqual(result.fingerprint.dimensions, 256,
                       "the width every stored centroid on this machine already has")
        XCTAssertGreaterThan(result.speechSeconds, 0)
        XCTAssertGreaterThan(result.voicesFound, 0)
        XCTAssertGreaterThan(result.dominantShare, 0)
        XCTAssertLessThanOrEqual(result.dominantShare, 1.0)
    }

    /// **The check the multi-voice refusal depends on.** A recording of a room with
    /// several people in it must report more than one voice — otherwise
    /// `VoiceEnrolment` would accept a two-person sample and store a fingerprint
    /// that puts a colleague's name on the user's words for months.
    func testARoomWithSeveralVoicesIsReportedAsSeveralVoices() async throws {
        let recordings = try recordingsOrSkip()
        guard let r = recordings.filter({ $0.inRoomVoices > 1 && $0.seconds > 60 })
            .max(by: { $0.inRoomVoices < $1.inRoomVoices })
        else { throw XCTSkip("no multi-voice room recording available") }

        let result = try await SpeakerKitVoiceEmbedder().embed(url: r.micURL)
        print("[embedder] \(r.id): diarizer recorded \(r.inRoomVoices) in-room voices, embed() reports \(result.voicesFound)")

        XCTAssertGreaterThan(result.voicesFound, 1,
            "this mic stream held \(r.inRoomVoices) voices; a sample like it must be refused, not fingerprinted")
        // And the refusal `VoiceEnrolment` applies would actually fire.
        let wouldRefuse = result.voicesFound != 1
            || result.dominantShare < VoiceEnrolment.minimumDominantShare
        XCTAssertTrue(wouldRefuse, "the enrolment policy must reject this sample")
    }

    /// A recording too short to identify anyone is refused with the reason, rather
    /// than fingerprinted from a second of audio.
    func testATooShortRecordingIsRefusedWithItsReason() async throws {
        let recordings = try recordingsOrSkip()
        guard let r = recordings.filter({ $0.seconds < 10 }).min(by: { $0.seconds < $1.seconds })
        else { throw XCTSkip("no short recording available") }

        // Under 1 s the embedder throws; above it, the policy in VoiceEnrolment
        // rejects on speech found. Either is a named refusal — assert whichever
        // applies to this file rather than assuming which.
        do {
            let result = try await SpeakerKitVoiceEmbedder().embed(url: r.micURL)
            print(String(format: "[embedder] %@: %.1f s of audio -> %.1f s of speech, %d voice(s)",
                         r.id, r.seconds, result.speechSeconds, result.voicesFound))
            XCTAssertLessThan(result.speechSeconds, VoiceEnrolment.minimumSpeechSeconds,
                "an %.0f-second recording must not pass the enrolment minimum")
        } catch let e as MinutesError {
            print("[embedder] \(r.id): refused — \(e.localizedDescription)")
            switch e {
            case .voiceSampleTooShort, .voiceSampleSilent:
                break  // the expected refusals
            default:
                XCTFail("refused for the wrong reason: \(e)")
            }
        }
    }

    /// The whole round trip, on real audio and a real store: embed, enrol, then ask
    /// the identification question the pipeline asks. This is the closest thing to
    /// an end-to-end run that does not need a human voice — the "enrolled" voice
    /// here is a real in-room voice from a real meeting, which is what an enrolment
    /// sample is a cleaner version of.
    func testEmbedThenEnrolThenIdentifyAgainstTheSameMeeting() async throws {
        let recordings = try recordingsOrSkip()
        guard let r = recordings.filter({ $0.inRoomVoices >= 1 && $0.seconds > 60 })
            .max(by: { $0.seconds < $1.seconds })
        else { throw XCTSkip("no suitable recording") }

        let result = try await SpeakerKitVoiceEmbedder().embed(url: r.micURL)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speakers-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SpeakerDirectory(url: url)
        await store.enrol(name: "Test", fingerprint: result.fingerprint,
                          speechSeconds: result.speechSeconds)

        // The dominant voice of that recording, offered back as a candidate, must
        // be the one identified — and at a distance the calibration would accept.
        let candidates = [VoiceMatch.Candidate(key: "0", fingerprint: result.fingerprint)]
        let resolution = await store.identifyLocal(among: candidates)
        XCTAssertEqual(resolution.matchedKey, "0")
        XCTAssertEqual(resolution.matchedDistance ?? 1, 0, accuracy: 1e-4)

        // And it survives a relaunch, with its producer intact (AD-29).
        let reopened = SpeakerDirectory(url: url)
        let p = await reopened.enrolledProfile()
        XCTAssertEqual(p?.producer, SpeakerKitVoiceEmbedder.producerID)
        XCTAssertEqual(p?.centroid.count, 256)
    }
}
