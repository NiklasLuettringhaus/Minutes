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
        // The watched prefix, not the helper process that happened to hold the
        // device when the Session started. Teams swaps between `.modulehost` and
        // `.helper` across an audio-hardware change, and a Session pinned to the
        // one that has gone away can never be matched again.
        autoStopBundleID = associated?.watchedPrefix
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
            // AD-45: a fact about a recording that happened, stored per stream.
            m.micRate = streams.micRate
            m.systemRate = streams.systemRate
            // AD-51: holes the device counted and the app never received. A
            // different fact from the rate, kept separately so it cannot be
            // read as one.
            m.micContinuity = streams.micContinuity
            m.systemContinuity = streams.systemContinuity
            // AD-57: what became of every sample the devices delivered. The term
            // continuity cannot reach — it answers what the device handed over,
            // and this answers what reached the file.
            m.micLedger = streams.micLedger
            m.systemLedger = streams.systemLedger
            // AD-58: how close each Stream came to outrunning its writer, so a
            // drop count has a cause attached and a near-miss is visible at all.
            m.micPressure = streams.micPressure
            m.systemPressure = streams.systemPressure
            // AD-59: the offset below, decomposed into the part capture caused
            // and the part the devices did.
            m.startTiming = streams.startTiming
            // AD-53: measured, not estimated, and absent when it could not be.
            m.streamStartOffset = streams.streamStartOffset
            // AD-54: a fact about the capture, read rather than inferred.
            m.outputDevice = streams.outputDevice
            m.outputDeviceChanged = streams.outputDeviceChanged
        }

        // The only evidence available about system-audio permission (FR-42),
        // and now derived from the samples rather than from elapsed time (AD-36).
        Preferences.shared.lastSystemCaptureOK = streams.systemCaptured

        // A degraded recording is a thing the user can act on, so say so rather
        // than only logging it. Gated on the tap having been established, not on
        // duration: a tap that started and delivered no callbacks at all has zero
        // duration, and suppressing that case would reproduce exactly the silence
        // FR-66 exists to remove. A tap that never started already reported
        // itself at start.
        if streams.systemTapEstablished, !streams.systemCaptured,
           let why = streams.systemEvidence.failureReason {
            AppState.shared.lastError = .systemAudioProducedSilence(why)
        }

        // AD-44 / FR-84. A rate disagreement is louder than a silent stream,
        // because the recording *looks* fine and its transcript will read fine.
        // Reported after the silence check so the more specific failure wins.
        for (stream, why) in [("your microphone", streams.micRate.explanation),
                              ("the far end of the call", streams.systemRate.explanation)] {
            if let why {
                AppState.shared.lastError = .captureRateMismatch(stream: stream, detail: why)
            }
        }

        // FR-106. The loudest of the three, so it is reported last and wins: a
        // microphone that stopped part-way through means part of the meeting is
        // not in the recording at all, which is worse than a wrong rate and
        // worse than a silent System Stream.
        if let why = streams.micEndedEarly {
            AppState.shared.lastError = .microphoneUnavailable(
                "The recording continued but your microphone stopped part-way through — \(why).")
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
    /// `watchedPrefix` is the watched app's identity, not a process bundle ID —
    /// both sides of this comparison are prefixes now, so it is an equality.
    func autoStopIfTriggered(by watchedPrefix: String) async {
        guard isRecording, let trigger = autoStopBundleID, watchedPrefix == trigger else { return }
        let bundleID = watchedPrefix
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
        surface(await Pipeline.shared.rewriteNote(meetingID: meetingID), meetingID: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    func renameMeeting(meetingID: String, to newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? await MeetingStore.shared.update(id: meetingID) { $0.metadata?.title = trimmed }
        surface(await Pipeline.shared.rewriteNote(meetingID: meetingID), meetingID: meetingID)
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
        await delete(meetingIDs: [meetingID], alsoNote: alsoNote)
    }

    /// FR-40 (amended): one confirmed action over a selection, one reload at the
    /// end rather than a reload per Meeting.
    func delete(meetingIDs: [String], alsoNote: Bool) async {
        let store = MeetingStore.shared
        let folder = Preferences.shared.notesFolder()
        var failure: MinutesError?
        for id in meetingIDs {
            var noteURL: URL? = nil
            // FR-40 as amended: the file is *resolved*, not read off the record.
            // Building this path from the stored filename is how the app deleted
            // nothing while its dialog said it had.
            if alsoNote, let m = try? await store.load(id: id), let folder {
                noteURL = await NoteLinkService.resolvedNoteURL(for: m, in: folder)
            }
            do {
                try await store.delete(id: id, alsoDeleteNote: noteURL)
            } catch let e as MinutesError {
                // AD-42: nothing was removed. A swallowed `try?` here is how a
                // delete that did not happen looked exactly like one that did.
                failure = failure ?? e
            } catch {
                failure = failure ?? .deleteFailed(item: "The meeting", reason: error.localizedDescription)
            }
        }
        if let failure { AppState.shared.lastError = failure }
        await AppStateBridge.reloadMeetings()
    }

    /// FR-53: re-render a Note from the stored record.
    ///
    /// No transcription, no diarization, and nothing parsed out of any file — the
    /// record is the source of truth and the Note is a projection (AD-9). The
    /// Pipeline resolves the link first, so this can only ever *create* a file
    /// when no file claims the Meeting (FR-35 as amended).
    func rewriteNote(meetingID: String) async {
        let outcome = await Pipeline.shared.rewriteNote(meetingID: meetingID)
        surface(outcome, meetingID: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    /// FR-81: a refusal becomes a choice the user makes, not a silent no-op.
    private func surface(_ outcome: NoteWriteOutcome?, meetingID: String) {
        if case .refusedChangedOnDisk(let url) = outcome {
            AppState.shared.noteConflict = .init(meetingID: meetingID, url: url)
        }
    }

    // MARK: - Rate fidelity of recordings already on disk (FR-88)

    /// What a stored recording's own samples say about their rate.
    struct RateAudit: Sendable {
        var meetingID: String
        var title: String
        var mic: RateFidelity?
        var system: RateFidelity?
        var failing: [String] {
            var out: [String] = []
            if let m = mic, !m.isTrustworthy { out.append("mic") }
            if let s = system, !s.isTrustworthy { out.append("system") }
            return out
        }
        var repairable: Bool {
            (mic.map { !$0.isTrustworthy && $0.integerRatio != nil } ?? false)
            || (system.map { !$0.isTrustworthy && $0.integerRatio != nil } ?? false)
        }
    }

    /// Assesses every recording on disk, including those made before the live
    /// check existed. Reads headers only — no audio, no writes.
    func auditRates() async -> [RateAudit] {
        let store = MeetingStore.shared
        var out: [RateAudit] = []
        for m in await store.loadAll() where m.duration > 0 {
            let dir = await store.directory(for: m.id)
            func check(_ stream: StreamKind) -> RateFidelity? {
                let u = dir.appendingPathComponent("\(stream.rawValue).wav")
                guard FileManager.default.fileExists(atPath: u.path) else { return nil }
                return try? WavRateRepair.fidelity(of: u, sessionDuration: m.duration)
            }
            out.append(RateAudit(meetingID: m.id,
                                 title: m.metadata?.title ?? "Untitled",
                                 mic: check(.mic), system: check(.system)))
        }
        return out
    }

    /// Repairs a recording's declared rate and re-runs the pipeline over the
    /// retained audio (FR-88).
    ///
    /// Nothing here is automatic. The samples are the user's and a repair is a
    /// change to their file, so it happens when they ask and not on a launch.
    /// Re-running uses the existing pipeline — there is deliberately no second
    /// transcription path for recovered recordings.
    func repairAndReprocess(meetingID id: String) async {
        let store = MeetingStore.shared
        guard let m = try? await store.load(id: id), m.duration > 0 else { return }
        let dir = await store.directory(for: id)
        var repaired: [String] = []
        for stream in StreamKind.allCases {
            let u = dir.appendingPathComponent("\(stream.rawValue).wav")
            guard FileManager.default.fileExists(atPath: u.path),
                  let f = try? WavRateRepair.fidelity(of: u, sessionDuration: m.duration),
                  !f.isTrustworthy, f.integerRatio != nil else { continue }
            do {
                let change = try WavRateRepair.repair(u, sessionDuration: m.duration)
                repaired.append("\(stream.rawValue) \(Int(change.was))->\(Int(change.now)) Hz")
            } catch let e as MinutesError {
                AppState.shared.lastError = e
                return
            } catch {
                AppState.shared.lastError = .audioFileWriteFailed(error.localizedDescription)
                return
            }
        }
        guard !repaired.isEmpty else { return }
        Log.session.info("repaired \(id, privacy: .public): \(repaired.joined(separator: ", "), privacy: .public)")

        // The rate check has to be cleared as well as the audio fixed: the record
        // still carries the failure that was true before the repair, and leaving
        // it would mark a now-sound recording unreliable for ever.
        _ = try? await store.update(id: id) { rec in
            rec.micRate = nil
            rec.systemRate = nil
            rec.stage = .captured          // re-transcribe, re-diarize, re-derive
            rec.failure = nil
        }
        // Deliberately *not* enqueued here.
        //
        // The stage is reset and the re-run is left to whichever process owns the
        // library. Enqueueing from a short-lived `--check-rates --repair` process
        // either exits before the work runs — which it did, leaving a meeting
        // stuck at `captured` — or transcribes concurrently with a running app,
        // and two processes writing one `meeting.json` is worse than a recording
        // that needs one more click.
        //
        // `Pipeline.resumeInterrupted()` on launch and the row's "Finish
        // transcription" both already pick this up, so recovery uses a path that
        // existed and was tested rather than a new one.
        await AppStateBridge.reloadMeetings()
    }

    /// Repairs and re-runs immediately, for a caller that owns the library — the
    /// running app, from a button.
    func repairAndReprocessNow(meetingID id: String) async {
        await repairAndReprocess(meetingID: id)
        await Pipeline.shared.enqueue(meetingID: id)
    }

    // MARK: - Note links (FR-79, FR-81)

    /// FR-79. The user points a Meeting at a file.
    ///
    /// Three cases, and the middle one is why this is not a bare file picker: a
    /// file whose frontmatter names a *different* Meeting is allowed but stated,
    /// because linking one file to two Meetings means the next rewrite destroys
    /// one of them. A file Minutes did not write is also allowed and also stated —
    /// the next rewrite would replace its contents, and the user hears that before
    /// the link is made rather than after.
    func locateNote(meetingID: String) async {
        guard let folder = Preferences.shared.notesFolder() else {
            AppState.shared.lastError = .notesFolderUnavailable
            return
        }
        guard let url = NotePicker.chooseMarkdownFile(startingIn: folder) else { return }

        let identity = (try? String(contentsOf: url, encoding: .utf8))
            .flatMap { NoteIdentity.parse(frontmatterOf: String($0.prefix(NoteIdentity.headBytes))) }
        let meetings = AppState.shared.meetings

        if let identity, identity.isMinutesNote,
           let other = meetings.first(where: { identity.matches($0) }),
           other.id != meetingID {
            let name = other.metadata?.title ?? "the meeting that started \(other.startedAt.formatted(date: .abbreviated, time: .shortened))"
            guard NotePicker.confirm(
                title: "That note belongs to another meeting",
                message: "“\(url.lastPathComponent)” says it is the note for “\(name)”. Linking it here means both meetings point at one file, and the next time either is rewritten the other's note is replaced.",
                confirm: "Link it anyway") else { return }
        } else if identity?.isMinutesNote != true {
            guard NotePicker.confirm(
                title: "Minutes did not write that file",
                message: "“\(url.lastPathComponent)” has no Minutes frontmatter. Linking it is fine, but the next time this meeting is rewritten — after a rename, a retitle or an exclusion — its contents will be replaced with the meeting's note.",
                confirm: "Link it anyway") else { return }
        }
        await adoptNote(url, meetingID: meetingID)
    }

    /// Links a specific file, from FR-79's chooser or from the ambiguity list.
    func adoptNote(_ url: URL, meetingID: String) async {
        await NoteLinkService.adopt(url, for: meetingID)
        await AppStateBridge.reloadMeetings()
    }

    /// FR-81, the outcome that changes nothing on disk. The record keeps its edit;
    /// the file keeps the user's version, and the app stops reporting a conflict by
    /// adopting the file's current bytes as its new baseline.
    func keepNoteOnDisk() async {
        guard let c = AppState.shared.noteConflict else { return }
        AppState.shared.noteConflict = nil
        await NoteLinkService.adopt(c.url, for: c.meetingID)
    }

    /// FR-81, the destructive outcome, taken deliberately because the user said so.
    ///
    /// Adopting the file's current bytes as the baseline first is what lets the
    /// rewrite through: the digest check then passes and the write proceeds. The
    /// alternative — a `force` flag on `NoteWriting.write` — would put a way to
    /// skip AD-41 into the port itself, where a later caller could reach it by
    /// accident. Here it takes two deliberate calls in one method that says what
    /// it is for.
    func replaceNoteWithFreshRender() async {
        guard let c = AppState.shared.noteConflict else { return }
        AppState.shared.noteConflict = nil
        await NoteLinkService.adopt(c.url, for: c.meetingID)
        _ = await Pipeline.shared.rewriteNote(meetingID: c.meetingID)
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
        surface(await Pipeline.shared.rewriteNote(meetingID: meetingID), meetingID: meetingID)
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
