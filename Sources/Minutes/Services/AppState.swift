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
    /// Where each complete Meeting's Note actually is (FR-78).
    ///
    /// A display state derived on read, never written into the record: the folder
    /// can change, and a transient filesystem condition must not become a
    /// permanent claim in `meeting.json`. A *positive* identification is persisted
    /// — see `NoteLinkService` — because that one is durable.
    ///
    /// Replaced `missingNotes: Set<String>` in increment 7. A set of "missing" ids
    /// could only express one of the four answers, and it expressed the wrong one
    /// for a renamed file: the app had not looked.
    @Published private(set) var noteLinks: [String: NoteLinkState] = [:]
    /// Files in the Notes Folder that Minutes wrote and no Meeting claims (FR-82).
    @Published private(set) var unclaimedNotes: [UnclaimedNote] = []
    /// A Note the app declined to overwrite because it is not the bytes the app
    /// wrote (FR-81). One at a time: the choice is per Note and is made now.
    @Published var noteConflict: NoteConflict?

    /// A Note changed outside Minutes, and the edit that discovered it.
    struct NoteConflict: Equatable, Identifiable {
        let meetingID: String
        let url: URL
        var id: String { meetingID }
        var filename: String { url.lastPathComponent }
    }

    /// FR-53's badge, in terms of the new state. Not simply "no file": a Meeting
    /// whose folder is unset has not been looked for, and saying its Note is gone
    /// would be a claim about the user's folder that the app cannot support.
    func noteIsMissing(_ id: String) -> Bool {
        switch noteLinks[id] {
        case .notFound, .ambiguous: return true
        default: return false
        }
    }
    func noteLink(_ id: String) -> NoteLinkState { noteLinks[id] ?? .unknown }
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
    /// A pane another surface wants brought forward. `MainWindow` owns the actual
    /// selection, so a deep link sets this and clears it rather than reaching into
    /// someone else's `@State` (AD-7: views call intents, they do not mutate).
    @Published var paneRequest: String?
    /// Whether the Mic Stream is muted for the running Session. Reset on stop —
    /// a mute is a decision about one meeting, not a persisted preference.
    @Published private(set) var micMuted: Bool = false
    @Published private(set) var micAuthorized: Bool = false
    @Published private(set) var audioBytes: Int64 = 0

    private init() {}

    // Only SessionCoordinator and Pipeline (via the bridge) call these.
    func setSessionState(_ s: SessionState) { sessionState = s }
    func setMeetings(_ m: [Meeting]) { meetings = m }
    func setMicAuthorized(_ b: Bool) { micAuthorized = b }
    func setMicMuted(_ b: Bool) { micMuted = b }
    func setInFlight(_ ids: Set<String>) { inFlight = ids }
    func setNoteLinks(_ l: [String: NoteLinkState]) { noteLinks = l }
    func setUnclaimedNotes(_ n: [UnclaimedNote]) { unclaimedNotes = n }
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
        let folder = await notesFolder()
        // FR-78 / FR-54: both directions — records against files, and files
        // against records. Resolved against the folder *currently* in effect, so
        // moving the Notes Folder still does not mark every past Meeting broken.
        let links = await NoteLinkService.reconcile(meetings, in: folder)
        let orphans = await NoteLinkService.unclaimed(meetings, in: folder)
        await MainActor.run {
            AppState.shared.setMeetings(meetings)
            AppState.shared.setAudioBytes(bytes)
            AppState.shared.setNoteLinks(links)
            AppState.shared.setUnclaimedNotes(orphans)
            AppState.shared.setUnreadable(bad.map(\.id))
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
