import Foundation
import AVFoundation

/// FR-62. Records the user's own voice once, derives a fingerprint, and deletes
/// the recording.
///
/// Deliberately shaped like `TestPlayground`, because the Playground already
/// taught the user what a countdown plus a level meter plus a result made of
/// measured facts means: *the app is about to listen, and then it will tell you
/// what it actually heard.* Enrolment makes exactly that promise, so it makes it
/// in exactly that shape. Two things differ, and both because the underlying
/// thing differs — it reads one Stream rather than two, and its result reports
/// seconds of speech and voices found rather than a transcript.
///
/// **AD-32 is the rule that matters here and it is the one that is invisible when
/// broken.** Nothing is written to disk until a fingerprint exists, and the
/// sample audio is deleted on *every* exit path — success, refusal, thrown error,
/// and cancellation. That is why the cleanup is a `defer` and not a line at the
/// end of the happy path. The whole privacy argument for this feature is that
/// what persists is 256 numbers nobody can play back; a recording left beside
/// them would convert it into a stored voice recording of a named person, which
/// is a different thing entirely.
@MainActor
final class VoiceEnrolment: ObservableObject {
    static let shared = VoiceEnrolment()

    /// Inside the specified 20–30 s. Long enough for a stable fingerprint, short
    /// enough to do once without resenting it. The two shortest samples in the
    /// calibration data — 11 words and 1 word — produced visibly unreliable
    /// centroids, which is the measured reason this is not five seconds.
    static let captureSeconds: TimeInterval = 25

    /// Below this there is not enough speech to identify anyone, however long the
    /// file is. A 25-second recording of someone thinking is not a 25-second
    /// sample, so the check is on speech found and not on file duration.
    static let minimumSpeechSeconds: TimeInterval = 8

    /// A cough, a chair, or a "sorry, go on" from across the room reads as a
    /// second voice with a tiny share. Requiring the dominant speaker to hold
    /// most of the sample refuses genuine crosstalk without refusing a sample
    /// that merely has a noise in it.
    static let minimumDominantShare: Double = 0.85

    enum Phase: Equatable {
        case idle
        case recording(remaining: Int)
        case analysing
        case done(Result)
        case failed(String, recovery: String?)
    }

    /// What the card reports. Facts, not a verdict — no score and no adjective.
    struct Result: Equatable {
        var speechSeconds: Double
        var voicesFound: Int
        /// Kept so the card can say when, without re-reading the store.
        var recordedAt: Date
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var micLevel: Float = 0
    /// Mirrors the store so the checklist row and the card agree without either
    /// of them awaiting an actor mid-render.
    @Published private(set) var isEnrolled: Bool = false
    @Published private(set) var enrolled: SpeakerDirectory.Summary?

    private let embedder: VoiceEmbedding = SpeakerKitVoiceEmbedder()
    private var capture: MicCapture?
    private var levelTimer: Timer?
    private var cancelled = false
    /// Separate from `phase`, and not redundant with it. `phase` only becomes
    /// `.recording` inside the countdown loop, and there is an `await` before that
    /// — requesting microphone permission — so two taps in that window would both
    /// pass a phase-derived guard and start two captures on the same audio engine.
    /// The second would throw and report a failure for a recording that was
    /// actually running.
    private var inFlight = false

    var isRunning: Bool {
        if inFlight { return true }
        switch phase { case .idle, .done, .failed: return false; default: return true }
    }

    private init() {}

    /// Reads the store. Cheap, and called on pane appearance for the same reason
    /// the checklist recomputes permissions there: state is derived live, never
    /// from a stored completion flag (FR-46).
    func refresh() async {
        let summary = await SpeakerDirectory.shared.summaries().first { $0.isEnrolled }
        enrolled = summary
        isEnrolled = summary != nil
        // A previous run's result card should not outlive the thing it described.
        if summary == nil, case .done = phase { phase = .idle }
    }

    // MARK: - Recording

    func run() async {
        guard !inFlight, !isRunning else { return }
        inFlight = true
        defer { inFlight = false }
        cancelled = false
        micLevel = 0

        if Permissions.micState() == .notDetermined { _ = await Permissions.requestMic() }
        guard Permissions.micState().isAuthorized else {
            phase = .failed(MinutesError.microphonePermissionDenied.localizedDescription,
                            recovery: MinutesError.microphonePermissionDenied.recoverySuggestion)
            return
        }

        // Outside the Meetings root, so nothing here can ever be mistaken for a
        // Meeting or picked up by anything that scans that directory (AD-32).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-enrol-\(UUID().uuidString)", isDirectory: true)
        // AD-32: on every exit path, including a thrown error and a cancellation.
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            phase = .failed(MinutesError.audioFileWriteFailed(error.localizedDescription)
                .localizedDescription, recovery: nil)
            return
        }
        let url = dir.appendingPathComponent("voice.wav")

        // Mic only. The System Stream is never opened, so enrolment cannot trigger
        // the system-audio permission and cannot record the far end of a call —
        // which also means it can never become a way to sample a colleague's voice
        // without them being in the room (PRD §9.1).
        let mic = MicCapture()
        do {
            try mic.start(url: url)
        } catch let e as MinutesError {
            phase = .failed(e.localizedDescription, recovery: e.recoverySuggestion)
            return
        } catch {
            phase = .failed(error.localizedDescription, recovery: nil)
            return
        }
        capture = mic

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let c = self.capture else { return }
                self.micLevel = c.level
            }
        }

        for remaining in stride(from: Int(Self.captureSeconds), through: 1, by: -1) {
            guard !cancelled else { break }
            phase = .recording(remaining: remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        levelTimer?.invalidate(); levelTimer = nil
        _ = mic.stop()
        capture = nil
        micLevel = 0

        if cancelled {
            // Indistinguishable from never having started: the temp directory
            // goes in the `defer`, and nothing was stored (FR-62).
            phase = .idle
            return
        }

        phase = .analysing
        do {
            let r = try await embedder.embed(url: url)

            // Policy lives here, not in the embedder. The port reports what was
            // in the recording; this decides whether that is usable.
            guard r.voicesFound == 1, r.dominantShare >= Self.minimumDominantShare else {
                let e = MinutesError.voiceSampleMultipleVoices(count: max(r.voicesFound, 2))
                phase = .failed(e.localizedDescription, recovery: e.recoverySuggestion)
                return
            }
            guard r.speechSeconds >= Self.minimumSpeechSeconds else {
                let e = MinutesError.voiceSampleTooShort(seconds: r.speechSeconds)
                phase = .failed(e.localizedDescription, recovery: e.recoverySuggestion)
                return
            }

            await SpeakerDirectory.shared.enrol(name: Preferences.shared.localSpeakerName,
                                                fingerprint: r.fingerprint,
                                                speechSeconds: r.speechSeconds)
            await refresh()
            phase = .done(Result(speechSeconds: r.speechSeconds,
                                 voicesFound: r.voicesFound,
                                 recordedAt: Date()))
        } catch let e as MinutesError {
            phase = .failed(e.localizedDescription, recovery: e.recoverySuggestion)
        } catch {
            phase = .failed(error.localizedDescription, recovery: nil)
        }
    }

    /// Stops a running recording and stores nothing.
    func cancel() {
        guard isRunning else { return }
        cancelled = true
    }

    func reset() { if !isRunning { phase = .idle } }

    // MARK: - Deletion (FR-64)

    func delete() async {
        await SpeakerDirectory.shared.forgetEnrolled()
        phase = .idle
        await refresh()
    }
}
