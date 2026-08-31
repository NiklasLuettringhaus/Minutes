import Foundation
import AVFoundation

/// FR-47. The product's only reliable system-audio diagnostic.
///
/// macOS exposes no API to query system-audio permission, so "can this app
/// actually record a meeting?" is otherwise unanswerable. A short
/// record-and-transcribe converts it into an empirical question — and measures
/// real throughput on this machine as a side effect, which is what makes the
/// model picker's guidance honest rather than a generic claim.
@MainActor
final class TestPlayground: ObservableObject {
    static let shared = TestPlayground()

    /// Long enough to speak a sentence, short enough not to feel like a chore.
    static let captureSeconds: TimeInterval = 5

    enum Phase: Equatable {
        case idle
        case recording(remaining: Int)
        case transcribing
        case done(Result)
        case failed(String)
    }

    /// Failures are staged and named, never one generic error (FR-47).
    struct Result: Equatable {
        var transcript: String
        var micHadAudio: Bool
        var systemHadAudio: Bool
        var model: String
        var transcriptionSeconds: Double
        var audioSeconds: Double

        /// Linear extrapolation from the sample. Crude, but honest when labelled
        /// "roughly" — and far better than a static claim.
        var ratio: Double { audioSeconds > 0 ? transcriptionSeconds / audioSeconds : 0 }

        var extrapolation: String {
            guard ratio > 0 else { return "" }
            let thirtyMin = ratio * 30 * 60
            if thirtyMin < 90 { return "roughly \(Int(thirtyMin)) s for a 30-min meeting" }
            return "roughly \(Int((thirtyMin / 60).rounded())) min for a 30-min meeting"
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0

    private var capture: DualStreamCapture?
    private var levelTimer: Timer?

    var isRunning: Bool {
        switch phase { case .idle, .done, .failed: return false; default: return true }
    }

    func run() async {
        guard !isRunning else { return }
        micLevel = 0; systemLevel = 0

        if Permissions.micState() == .notDetermined { _ = await Permissions.requestMic() }
        guard Permissions.micState().isAuthorized else {
            phase = .failed("Microphone access has not been granted. Grant it above, then run the test again.")
            return
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-test-\(UUID().uuidString)", isDirectory: true)
        let cap = DualStreamCapture()
        do {
            try cap.start(into: dir)
        } catch let e as MinutesError {
            phase = .failed(e.localizedDescription)
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        capture = cap

        // Live per-Stream meters — a flat System meter is the diagnostic.
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let c = self.capture else { return }
                self.micLevel = c.level(for: .mic)
                self.systemLevel = c.level(for: .system)
            }
        }

        for remaining in stride(from: Int(Self.captureSeconds), through: 1, by: -1) {
            phase = .recording(remaining: remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        levelTimer?.invalidate(); levelTimer = nil
        let streams = cap.stop()
        capture = nil

        // The empirical answer about system-audio permission (FR-42).
        Preferences.shared.lastSystemCaptureOK = streams.systemCaptured

        phase = .transcribing
        let model = Preferences.shared.model
        guard ModelCatalog.isDownloaded(model) else {
            phase = .failed("The transcription model is not downloaded yet. Download it in Transcription, then run the test again.")
            try? FileManager.default.removeItem(at: dir)
            return
        }
        guard let micURL = streams.micURL else {
            phase = .failed("No microphone audio was captured. Check that the right input device is selected in System Settings > Sound.")
            try? FileManager.default.removeItem(at: dir)
            return
        }

        let started = Date()
        let transcriber: Transcribing = ParakeetModel.isParakeet(model) ? ParakeetTranscriber() : WhisperKitTranscriber()
        do {
            var segments = try await transcriber.transcribe(url: micURL, model: model)
            if let sys = streams.systemURL {
                segments += try await transcriber.transcribe(url: sys, model: model)
            }
            let elapsed = Date().timeIntervalSince(started)
            let text = segments.sorted { $0.start < $1.start }
                .map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let result = Result(
                transcript: text.isEmpty ? "(no speech detected — the capture worked, but nothing was said)" : text,
                micHadAudio: streams.micURL != nil,
                systemHadAudio: streams.systemCaptured,
                model: model,
                transcriptionSeconds: elapsed,
                audioSeconds: max(streams.duration, 0.1))
            // Feeds the model picker's speed guidance (PRD open question 1).
            Preferences.shared.lastThroughputRatio = result.ratio
            ModelCatalog.record(ratio: result.ratio, for: model)
            ModelCatalog.shared.loadLocalRecommendations()
            phase = .done(result)
        } catch let e as MinutesError {
            phase = .failed(e.localizedDescription)
        } catch {
            phase = .failed(error.localizedDescription)
        }
        // A test run produces no Meeting and writes no Note (FR-47).
        try? FileManager.default.removeItem(at: dir)
    }

    func reset() { phase = .idle; micLevel = 0; systemLevel = 0 }
}
