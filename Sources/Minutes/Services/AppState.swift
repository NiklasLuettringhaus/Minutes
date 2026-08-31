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
    /// Meetings whose Note is recorded but absent from the Notes Folder (FR-53).
    ///
    /// A display state derived on read, never written into the record: the folder
    /// can change, and a transient filesystem condition must not become a
    /// permanent claim in `meeting.json`.
    @Published private(set) var missingNotes: Set<String> = []
    /// Meeting records that could not be decoded, surfaced rather than skipped
    /// (FR-54). A listing that silently drops what it cannot parse is wrong
    /// without appearing wrong.
    @Published private(set) var unreadableMeetings: [String] = []
    /// Meetings actually in the pipeline right now — queued or running.
    ///
    /// The Meetings list used to infer "in progress" from `stage != .written`,
    /// which is a claim about the record, not about the work. A session interrupted
    /// by a quit therefore span a progress spinner forever with nothing behind it.
    @Published private(set) var inFlight: Set<String> = []
    /// Drives the FR-50 Recording pulse and, with it, the FR-49 menu bar timer.
    ///
    /// One published integer rather than an animation: the menu bar label is
    /// re-rendered by the system, so the cost has to be bounded and stoppable
    /// (NFR-3). It advances only while Recording and stops dead otherwise.
    @Published private(set) var pulsePhase: Int = 0
    @Published private(set) var micAuthorized: Bool = false
    @Published private(set) var audioBytes: Int64 = 0

    private init() {}

    // Only SessionCoordinator and Pipeline (via the bridge) call these.
    func setSessionState(_ s: SessionState) { sessionState = s }
    func setMeetings(_ m: [Meeting]) { meetings = m }
    func setMicAuthorized(_ b: Bool) { micAuthorized = b }
    func setInFlight(_ ids: Set<String>) { inFlight = ids }
    func setMissingNotes(_ ids: Set<String>) { missingNotes = ids }
    func advancePulse() { pulsePhase = (pulsePhase + 1) % 4 }
    func resetPulse() { pulsePhase = 0 }
    func setUnreadable(_ ids: [String]) { unreadableMeetings = ids }
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
    static func pinHeuristicBackend() async -> Bool {
        await MainActor.run { Preferences.shared.metadataBackend == .heuristic }
    }
    static func keepAudio() async -> Bool {
        await MainActor.run { Preferences.shared.keepAudio }
    }
    static func notesFolder() async -> URL? {
        await MainActor.run { Preferences.shared.notesFolder() }
    }

    static func setInFlight(_ ids: Set<String>) async {
        await MainActor.run { AppState.shared.setInFlight(ids) }
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
        let (meetings, bad) = await MeetingStore.shared.loadAllReportingFailures()
        let bytes = await MeetingStore.shared.audioBytes()
        let missing = await missingNoteIDs(in: meetings)
        await MainActor.run {
            AppState.shared.setMeetings(meetings)
            AppState.shared.setAudioBytes(bytes)
            AppState.shared.setMissingNotes(missing)
            AppState.shared.setUnreadable(bad.map(\.id))
        }
    }

    /// FR-53. Resolved against the folder *currently* in effect, so moving the
    /// Notes Folder does not mark every past Meeting broken. Only Meetings that
    /// claim a written Note are candidates — an unfinished one is not "missing" it.
    static func missingNoteIDs(in meetings: [Meeting]) async -> Set<String> {
        guard let folder = await notesFolder() else { return [] }
        let fm = FileManager.default
        var out: Set<String> = []
        for m in meetings {
            guard m.isComplete, let f = m.noteFilename else { continue }
            if !fm.fileExists(atPath: folder.appendingPathComponent(f).path) {
                out.insert(m.id)
            }
        }
        return out
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
