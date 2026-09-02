import Foundation
import AVFoundation
import AppKit

/// AD-7: the sole writer of `AppState`. Every start/stop intent goes through here.
@MainActor
final class SessionCoordinator: ObservableObject {
    static let shared = SessionCoordinator()

    private var capture: DualStreamCapture?
    private var currentMeetingID: String?
    private var startedAt: Date?
    /// Only a Session started from a Detection Prompt may be auto-stopped (FR-14).
    private(set) var autoStopBundleID: String?
    /// Whether this Session was started by hand rather than from a Prompt. Decides
    /// whether the meeting ending stops the recording or asks about it.
    private var wasManualStart = false
    private var tickTimer: Timer?

    private init() {}

    var isRecording: Bool { AppState.shared.sessionState.isRecording }

    // MARK: - Start

    /// `triggeredBy` non-nil means this Session came from a Detection Prompt and
    /// is therefore eligible for auto-stop (FR-13, FR-14).
    func start(triggeredBy app: DetectedMeeting? = nil) async {
        guard !isRecording else { return }

        // Mic permission is the one permission with a real API.
        let status = MicCapture.authorizationStatus()
        if status == .notDetermined {
            _ = await MicCapture.requestAccess()
        }
        guard MicCapture.authorizationStatus() == .authorized else {
            AppState.shared.setMicAuthorized(false)
            AppState.shared.lastError = .microphonePermissionDenied
            return
        }
        AppState.shared.setMicAuthorized(true)

        let id = Meeting.newID()
        let store = MeetingStore.shared
        do {
            _ = try await store.create(id: id, startedAt: Date())
        } catch {
            AppState.shared.lastError = .persistenceFailed(error.localizedDescription)
            return
        }

        let dir = await store.directory(for: id)
        let cap = DualStreamCapture()
        do {
            try cap.start(into: dir)
        } catch let e as MinutesError {
            AppState.shared.lastError = e
            try? await store.delete(id: id, alsoDeleteNote: nil)
            return
        } catch {
            AppState.shared.lastError = .microphoneUnavailable(error.localizedDescription)
            try? await store.delete(id: id, alsoDeleteNote: nil)
            return
        }

        capture = cap
        currentMeetingID = id
        startedAt = Date()

        // A manual start during a meeting is still a meeting.
        //
        // `autoStopBundleID` used to be set only from a Detection Prompt, so a
        // Session the user started by hand was permanently ineligible for
        // auto-stop. In the first real huddle the prompt's buttons never appeared,
        // the user started recording manually, the huddle ended — and nothing
        // noticed, because the Session had no associated app. Adopting whichever
        // watched app is holding the input right now fixes that without weakening
        // FR-14: the Session is genuinely tied to that meeting either way.
        let associated = app ?? DetectionService.appsUsingAudioInput().first
        autoStopBundleID = associated?.bundleID
        wasManualStart = (app == nil)

        // Provenance for the index at the top of the Note (FR-33). Captured at
        // start rather than derived later: the default input device can change
        // between recording and transcription.
        let micName = AVCaptureDevice.default(for: .audio)?.localizedName
        let sysName = cap.isDegraded ? nil
            : (associated.map { "system audio — \($0.appName)" } ?? "system audio")
        _ = try? await store.update(id: id) { m in
            if let associated { m.triggeringApp = associated.appName }
            m.micDevice = micName
            m.systemSource = sysName
        }

        // A previous failure is over: this attempt worked. A stale reason claiming
        // a present failure is its own defect (FR-66).
        AppState.shared.lastError = nil

        // The icon turns Recording only once audio is actually being captured (FR-3).
        AppState.shared.setSessionState(.recording(since: startedAt!, degraded: cap.isDegraded))
        startTicking()
        Log.session.info("session started \(id, privacy: .public) degraded=\(cap.isDegraded)")
    }

    // MARK: - Stop

    func stop() async {
        guard let cap = capture, let id = currentMeetingID else { return }
        stopTicking()
        let streams = cap.stop()
        capture = nil
        currentMeetingID = nil
        autoStopBundleID = nil
        wasManualStart = false
        AppState.shared.setMicMuted(false)
        StopPanel.shared.dismiss()

        let store = MeetingStore.shared
        _ = try? await store.update(id: id) { m in
            m.duration = streams.duration
            m.systemStreamCaptured = streams.systemCaptured
        }

        // The only evidence available about system-audio permission (FR-42),
        // and now derived from the samples rather than from elapsed time (AD-36).
        Preferences.shared.lastSystemCaptureOK = streams.systemCaptured

        // A degraded recording is a thing the user can fix, so say so rather than
        // only logging it. Not raised when the tap was never established — that
        // path already reported itself at start.
        if !streams.systemCaptured, let why = streams.systemEvidence.failureReason,
           streams.systemEvidence.duration > 0 {
            AppState.shared.lastError = .systemAudioProducedSilence(why)
        }

        AppState.shared.setSessionState(.transcribing(meetingID: id, title: nil))
        Log.session.info("session stopped \(id, privacy: .public) duration=\(streams.duration) system=\(streams.systemCaptured)")

        // Discard a recording too short to be a meeting rather than clutter the library.
        if streams.duration < 2.0 {
            try? await store.delete(id: id, alsoDeleteNote: nil)
            AppState.shared.setSessionState(.idle)
            await AppStateBridge.reloadMeetings()
            return
        }

        await Pipeline.shared.enqueue(meetingID: id)
        await AppStateBridge.reloadMeetings()
    }

    /// Called by detection when the triggering app releases the input device (FR-14).
    /// FR-14. A Session the *app* started stops itself; a Session the *user*
    /// started asks first, because stopping something someone chose to start is
    /// their call. What must not happen — and did — is neither.
    func autoStopIfTriggered(by bundleID: String) async {
        guard isRecording, let trigger = autoStopBundleID, bundleID.hasPrefix(trigger) else { return }
        let name = AppState.shared.meeting(id: currentMeetingID ?? "")?.triggeringApp
            ?? DetectionService.watched.first { trigger.hasPrefix($0.bundleIDPrefix) }?.displayName
            ?? "The meeting"

        if wasManualStart {
            Log.session.info("meeting ended, asking whether to stop \(bundleID, privacy: .public)")
            StopPanel.shared.present(appName: name)
        } else {
            Log.session.info("auto-stopping session for \(bundleID, privacy: .public)")
            await stop()
        }
    }

    // MARK: - Editing (FR-24, FR-35, FR-38)

    /// Renames a Speaker Label. Edits the per-Meeting name map only — no Utterance
    /// is mutated (AD-19) — then rewrites the Note in place.
    ///
    /// Renaming two labels to the same name merges them, which is the correct fix
    /// for one person split across two labels (FR-24).
    func renameSpeaker(meetingID: String, label: SpeakerLabelID, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let store = MeetingStore.shared
        _ = try? await store.update(id: meetingID) { m in
            m.speakerNames[label.raw] = trimmed
            // A user-supplied name is a fact, not an inference.
            m.inferredSpeakers.removeAll { $0 == label.raw }
        }
        // Teach the directory this voice, so it arrives named next time (FR-25).
        // This now includes naming YOURSELF among several people in a room — the
        // one time you do it, and thereafter your voice is recognised.
        if let centroid = await loadCentroid(meetingID: meetingID, label: label) {
            await SpeakerDirectory.shared.remember(name: trimmed, centroid: centroid)
        }
        await Pipeline.shared.rewriteNote(meetingID: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    func renameMeeting(meetingID: String, to newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? await MeetingStore.shared.update(id: meetingID) { $0.metadata?.title = trimmed }
        await Pipeline.shared.rewriteNote(meetingID: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    private func loadCentroid(meetingID: String, label: SpeakerLabelID) async -> [Float]? {
        let dir = await MeetingStore.shared.directory(for: meetingID)
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("centroids.json")),
              let map = try? JSONDecoder().decode([String: [Float]].self, from: d) else { return nil }
        return map[label.raw]
    }

    // MARK: - Retry / delete

    func retry(meetingID: String) async {
        await Pipeline.shared.enqueue(meetingID: meetingID)
    }

    func delete(meetingID: String, alsoNote: Bool) async {
        let store = MeetingStore.shared
        var noteURL: URL? = nil
        if alsoNote,
           let m = try? await store.load(id: meetingID),
           let f = m.noteFilename,
           let folder = Preferences.shared.notesFolder() {
            noteURL = folder.appendingPathComponent(f)
        }
        try? await store.delete(id: meetingID, alsoDeleteNote: noteURL)
        await AppStateBridge.reloadMeetings()
    }

    /// FR-40 (amended): one confirmed action over a selection, one reload at the
    /// end rather than a reload per Meeting.
    func delete(meetingIDs: [String], alsoNote: Bool) async {
        let store = MeetingStore.shared
        let folder = Preferences.shared.notesFolder()
        for id in meetingIDs {
            var noteURL: URL? = nil
            if alsoNote, let m = try? await store.load(id: id), let f = m.noteFilename, let folder {
                noteURL = folder.appendingPathComponent(f)
            }
            try? await store.delete(id: id, alsoDeleteNote: noteURL)
        }
        await AppStateBridge.reloadMeetings()
    }

    /// FR-53: re-render a Note that is recorded but absent, from the stored record.
    /// No transcription, no diarization, and nothing parsed out of any file — the
    /// record is the source of truth and the Note is a projection (AD-9).
    func rewriteNote(meetingID: String) async {
        await Pipeline.shared.rewriteNote(meetingID: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    /// FR-54: an explicit resynchronisation with what is on disk. Changes what is
    /// displayed, never what is stored.
    func refreshLibrary() async {
        await AppStateBridge.reloadMeetings()
    }

    // MARK: - Elapsed-time ticking

    private func startTicking() {
        tickTimer?.invalidate()
        // One timer drives the menu's elapsed time (FR-4) and the menu bar's
        // elapsed time (FR-49). It used to drive the FR-50 pulse too, which is why
        // it ran at 0.5s; the pulse is withdrawn and the interval stays at 0.5s
        // because "at least once per second" has to hold under timer tolerance,
        // and a 1.0s timer with 0.1 tolerance can land at 1.1s.
        //
        // The tick is much cheaper than it was: the icon image is now built once
        // rather than per tick, so a tick republishes the session state and
        // nothing redraws except the timer text.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let cap = self.capture, let started = self.startedAt else { return }
                AppState.shared.setSessionState(.recording(since: started, degraded: cap.isDegraded))
            }
        }
        tickTimer?.tolerance = 0.1
    }

    private func stopTicking() {
        tickTimer?.invalidate(); tickTimer = nil
    }

    /// Excluding a Speaker changes the Note, never the record. The speech stays in
    /// `meeting.json`, stays visible in the app, and the Note states that something
    /// was left out — a Note that quietly omits speech is less trustworthy than one
    /// that says so.
    func setSpeakerExcluded(_ excluded: Bool, speaker: SpeakerLabelID, meetingID: String) async {
        let store = MeetingStore.shared
        _ = try? await store.update(id: meetingID) { m in
            var set = Set(m.excludedSpeakers)
            if excluded { set.insert(speaker.raw) } else { set.remove(speaker.raw) }
            m.excludedSpeakers = Array(set).sorted()
        }
        await Pipeline.shared.rewriteNote(meetingID: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    /// FR-10-adjacent. Published through AppState so the menu can show the state
    /// rather than only set it.
    func setMicMuted(_ muted: Bool) {
        capture?.isMicMuted = muted
        AppState.shared.setMicMuted(muted)
    }

    /// Live capture level, for the self-test and the Test Playground meters.
    func debugLevel(_ s: StreamKind) -> Float { capture?.level(for: s) ?? 0 }

    func refreshMicAuthorization() {
        AppState.shared.setMicAuthorized(MicCapture.authorizationStatus() == .authorized)
    }
}
