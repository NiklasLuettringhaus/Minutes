import Foundation
import SwiftUI

/// AD-7: the single owner of observable application state.
///
/// Views never mutate this — they call intents on `SessionCoordinator`, which is
/// the sole writer. Adapters never touch it at all; they return values or publish
/// upward. Without this rule the menu bar, the window and the pipeline each end
/// up with their own idea of whether a Session is running.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum SessionState: Equatable {
        case idle
        case recording(since: Date, degraded: Bool)
        case transcribing(meetingID: String, title: String?)

        var isRecording: Bool { if case .recording = self { return true }; return false }
        var isTranscribing: Bool { if case .transcribing = self { return true }; return false }
    }

    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var meetings: [Meeting] = []
    @Published var lastError: MinutesError?
    /// A meeting the user has been offered but not yet answered (FR-12).
    @Published var pendingPrompt: DetectedMeeting?
    @Published private(set) var micAuthorized: Bool = false
    @Published private(set) var audioBytes: Int64 = 0

    private init() {}

    // Only SessionCoordinator and Pipeline (via the bridge) call these.
    func setSessionState(_ s: SessionState) { sessionState = s }
    func setMeetings(_ m: [Meeting]) { meetings = m }
    func setMicAuthorized(_ b: Bool) { micAuthorized = b }
    func setAudioBytes(_ n: Int64) { audioBytes = n }

    var elapsed: TimeInterval {
        if case .recording(let since, _) = sessionState { return Date().timeIntervalSince(since) }
        return 0
    }

    func meeting(id: String) -> Meeting? { meetings.first { $0.id == id } }
}

/// Lets the `Pipeline` actor read preferences and push updates without holding a
/// MainActor reference across suspension points.
enum AppStateBridge {
    static func model() async -> String {
        await MainActor.run { Preferences.shared.model }
    }
    static func localSpeakerName() async -> String {
        await MainActor.run { Preferences.shared.localSpeakerName }
    }
    static func fillerSettings() async -> (Bool, [String]) {
        await MainActor.run { (Preferences.shared.removeFillerWords, Preferences.shared.fillerWords) }
    }
    static func keepAudio() async -> Bool {
        await MainActor.run { Preferences.shared.keepAudio }
    }
    static func notesFolder() async -> URL? {
        await MainActor.run { Preferences.shared.notesFolder() }
    }

    static func setProcessing(_ id: String?) async {
        let meetings = await MeetingStore.shared.loadAll()
        await MainActor.run {
            AppState.shared.setMeetings(meetings)
            if let id {
                let title = meetings.first { $0.id == id }?.metadata?.title
                AppState.shared.setSessionState(.transcribing(meetingID: id, title: title))
            } else if AppState.shared.sessionState.isTranscribing {
                AppState.shared.setSessionState(.idle)
            }
        }
    }

    static func reloadMeetings() async {
        let meetings = await MeetingStore.shared.loadAll()
        let bytes = await MeetingStore.shared.audioBytes()
        await MainActor.run {
            AppState.shared.setMeetings(meetings)
            AppState.shared.setAudioBytes(bytes)
        }
    }

    static func finished(meetingID id: String) async {
        let meetings = await MeetingStore.shared.loadAll()
        await MainActor.run {
            AppState.shared.setMeetings(meetings)
            if let m = meetings.first(where: { $0.id == id }), m.isComplete {
                Notifier.shared.meetingReady(m)
            }
        }
    }
}
