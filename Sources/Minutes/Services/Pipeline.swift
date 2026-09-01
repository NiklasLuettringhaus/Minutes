import Foundation

/// AD-8 / AD-20: the staged, resumable pipeline.
///
/// `captured -> transcribed -> diarized -> attributed -> metadata -> written`
///
/// Stages are functions from inputs to an output value. They never write the
/// Meeting record and never touch `stage` — only this type advances it, and only
/// after a stage has returned successfully (AD-20). A failure therefore leaves
/// the Meeting at its last completed stage with a reason, and can be resumed
/// from exactly there.
actor Pipeline {
    static let shared = Pipeline()

    /// Chosen per model: the two engines share one port (AD-12's pattern).
    private func transcriber(for model: String) -> Transcribing {
        ParakeetModel.isParakeet(model) ? ParakeetTranscriber() : WhisperKitTranscriber()
    }
    private let diarizer = SpeakerKitDiarizerAdapter()
    private let noteWriter: NoteWriting = NoteWriter()
    private let heuristic = HeuristicBackend()
    private let llm = FoundationModelsBackend()

    private var queue: [String] = []
    private var current: String?
    private var isProcessing = false

    /// Queued serially: a Session may be recorded while another Meeting processes,
    /// but two model inferences never run concurrently (AD-14).
    func enqueue(meetingID: String) {
        guard !queue.contains(meetingID), current != meetingID else { return }
        queue.append(meetingID)
        Task { await publishInFlight() }
        Task { await drain() }
    }

    /// Restarts anything a quit or crash left mid-pipeline (AD-8).
    ///
    /// Without this the staged design was only *theoretically* resumable: an
    /// interrupted meeting sat at its last completed stage with no failure recorded
    /// and nothing to advance it, so it read as permanently in-progress. A record
    /// whose audio is already gone cannot be resumed, so it is failed explicitly
    /// rather than left looking live.
    func resumeInterrupted() async {
        let store = MeetingStore.shared
        for m in await store.loadAll() where !m.isComplete && !m.hasFailed {
            if await store.hasAudio(id: m.id) {
                Log.pipeline.info("resuming interrupted meeting \(m.id, privacy: .public)")
                enqueue(meetingID: m.id)
            } else {
                _ = try? await store.update(id: m.id) {
                    $0.failure = "Interrupted before the note was written, and the audio is no longer on disk."
                }
            }
        }
        await AppStateBridge.reloadMeetings()
    }

    private func publishInFlight() async {
        var ids = Set(queue)
        if let current { ids.insert(current) }
        await AppStateBridge.setInFlight(ids)
    }

    var pending: Int { queue.count }

    private func drain() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            current = id
            await publishInFlight()
            await AppStateBridge.setProcessing(id)
            await run(meetingID: id)
            current = nil
            await publishInFlight()
        }
        await AppStateBridge.setProcessing(nil)
        // Release models once the queue drains (AD-14).
        await MLEngine.shared.unloadWhisper()
    }

    // MARK: - Run / resume

    /// Advances a Meeting from wherever it is to `written`.
    func run(meetingID id: String) async {
        let store = MeetingStore.shared
        guard var meeting = try? await store.load(id: id) else {
            Log.pipeline.error("cannot load meeting \(id, privacy: .public)")
            return
        }

        // Clear a prior failure before retrying (FR-39).
        if meeting.failure != nil {
            meeting = (try? await store.update(id: id) { $0.failure = nil }) ?? meeting
        }

        while let next = meeting.stage.next {
            do {
                try await perform(next, on: id)
                // Only the Pipeline advances `stage`, and only after success (AD-20).
                meeting = try await store.update(id: id) { $0.stage = next }
                Log.pipeline.info("meeting \(id, privacy: .public) -> \(next.rawValue, privacy: .public)")
            } catch {
                let reason = (error as? MinutesError)?.localizedDescription ?? error.localizedDescription
                _ = try? await store.update(id: id) { $0.failure = reason }
                Log.pipeline.error("stage \(next.rawValue, privacy: .public) failed: \(reason, privacy: .public)")
                await AppStateBridge.reloadMeetings()
                return
            }
            await AppStateBridge.reloadMeetings()
        }

        // Audio retention is the user's call (FR-44).
        let keep = await AppStateBridge.keepAudio()
        if !keep { try? await store.deleteAudio(id: id) }
        await AppStateBridge.finished(meetingID: id)
    }

    private func perform(_ stage: Stage, on id: String) async throws {
        switch stage {
        case .captured:
            return  // produced by capture, never by the pipeline
        case .transcribed:
            try await transcribeStage(id)
        case .diarized:
            try await diarizeStage(id)
        case .attributed:
            try await attributeStage(id)
        case .metadata:
            try await metadataStage(id)
        case .written:
            try await writeStage(id)
        }
    }

    // MARK: - Stages

    private func transcribeStage(_ id: String) async throws {
        let store = MeetingStore.shared
        let model = await AppStateBridge.model()
        let (stripFiller, fillers) = await AppStateBridge.fillerSettings()
        var utterances: [Utterance] = []

        /// Drops disfluencies, and drops the Utterance entirely when it was
        /// nothing but them.
        func clean(_ s: String) -> String? {
            guard stripFiller else { return s }
            let out = FillerWords.strip(s, words: fillers)
            return out.isEmpty ? nil : out
        }

        // The Mic Stream is the Local Speaker, structurally and without inference (AD-11).
        if let mic = await store.audioURL(id: id, stream: .mic) {
            for s in try await transcriber(for: model).transcribe(url: mic, model: model) {
                guard let text = clean(s.text) else { continue }
                utterances.append(Utterance(start: s.start, end: s.end, text: text,
                                            speaker: .local, origin: .mic))
            }
        }
        // System Stream segments start unassigned; diarization names them next.
        if let sys = await store.audioURL(id: id, stream: .system) {
            for s in try await transcriber(for: model).transcribe(url: sys, model: model) {
                guard let text = clean(s.text) else { continue }
                utterances.append(Utterance(start: s.start, end: s.end, text: text,
                                            speaker: SpeakerLabelID.remote(0), origin: .system))
            }
        }
        guard !utterances.isEmpty else {
            throw MinutesError.transcriptionFailed("No speech was found in the recording.")
        }
        _ = try await store.update(id: id) {
            $0.utterances = utterances.sorted { $0.start < $1.start }
            $0.transcriptionModel = model
        }
    }

    /// Diarizes BOTH streams.
    ///
    /// Revised after a user correction: the microphone is not necessarily the
    /// user. In a meeting room it captures the user *and* whoever is sitting
    /// next to them, so attributing all of it to the Local Speaker would put
    /// colleagues' words in the user's mouth — strictly worse than an anonymous
    /// label.
    ///
    /// What is still structural is *where* a voice was: the mic stream is the
    /// room, the system stream is the far end. That split is never a guess.
    private func diarizeStage(_ id: String) async throws {
        let store = MeetingStore.shared
        var centroids: [String: [Float]] = [:]
        var anySucceeded = false
        var multipleInRoom = false
        var micSpans: [DiarizedSpan] = []
        var systemSpans: [DiarizedSpan] = []

        // --- Microphone: the room ---
        if let mic = await store.audioURL(id: id, stream: .mic) {
            do {
                let (spans, c) = try await diarizer.diarizeFull(url: mic)
                let voices = Set(spans.map(\.speakerIndex))
                if voices.count > 1 {
                    // Several people in the room. Do not claim any of them is the
                    // user; the rename + profile machinery names them once.
                    multipleInRoom = true
                    micSpans = spans
                    for (idx, vec) in c { centroids[SpeakerLabelID.inRoom(idx).raw] = vec }
                } else {
                    // A single voice on the microphone is the user, and that
                    // inference is safe.
                    for (_, vec) in c { centroids[SpeakerLabelID.local.raw] = vec }
                }
                anySucceeded = true
            } catch {
                // Degrade to the old assumption rather than fail: one voice, the user.
                Log.pipeline.error("mic diarization failed, treating the mic as a single speaker: \(error.localizedDescription, privacy: .public)")
            }
        }

        // --- System: the far end ---
        if let sys = await store.audioURL(id: id, stream: .system) {
            do {
                let (spans, c) = try await diarizer.diarizeFull(url: sys)
                systemSpans = spans
                for (idx, vec) in c { centroids[SpeakerLabelID.remote(idx).raw] = vec }
                if !spans.isEmpty { anySucceeded = true }
            } catch {
                Log.pipeline.error("system diarization failed, degrading to one speaker: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Name any voice we already know from a previous meeting (FR-25).
        var names: [String: String] = [:]
        var inferred: [String] = []
        for (label, vec) in centroids {
            if let known = await SpeakerDirectory.shared.match(centroid: vec) {
                names[label] = known
                inferred.append(label)
            }
        }

        if !centroids.isEmpty {
            let json = try JSONEncoder().encode(centroids)
            try MeetingStore.atomicWrite(json, to: await store.directory(for: id)
                .appendingPathComponent("centroids.json"))
        }

        let mic = micSpans, sysSpans = systemSpans, multi = multipleInRoom
        let ok = anySucceeded
        _ = try await store.update(id: id) { m in
            m.diarizationSucceeded = ok
            m.multipleInRoom = multi
            for (k, v) in names { m.speakerNames[k] = v }
            m.inferredSpeakers = inferred
            m.utterances = Self.assign(micSpans: mic, systemSpans: sysSpans,
                                       multipleInRoom: multi, to: m.utterances)
        }
    }

    /// Assigns each Utterance to the diarized voice whose span overlaps it most,
    /// within its own stream. A mic Utterance can only become an in-room voice and
    /// a system Utterance can only become a remote one — the streams never mix,
    /// which is the part of the original design that survives.
    static func assign(micSpans: [DiarizedSpan],
                       systemSpans: [DiarizedSpan],
                       multipleInRoom: Bool,
                       to utterances: [Utterance]) -> [Utterance] {
        utterances.map { u in
            let spans = u.origin == .mic ? micSpans : systemSpans
            guard !spans.isEmpty else { return u }
            var best: (idx: Int, overlap: TimeInterval)? = nil
            for s in spans {
                let o = min(u.end, s.end) - max(u.start, s.start)
                guard o > 0 else { continue }
                if best == nil || o > best!.overlap { best = (s.speakerIndex, o) }
            }
            guard let b = best else {
                // No overlapping span. With one voice on the mic that is still the
                // user; with several it is in-room speech nobody can attribute, and
                // calling it the user would be an identity claim the data does not
                // support (AD-11). The default used to be `.local` either way, which
                // put 14 unplaceable utterances under "Me" in the first real meeting.
                if u.origin == .mic, multipleInRoom {
                    var c = u
                    c.speaker = .inRoomUnidentified
                    return c
                }
                return u
            }
            var c = u
            switch u.origin {
            case .mic:
                // One voice on the mic stays the user; several become in-room voices.
                c.speaker = multipleInRoom ? SpeakerLabelID.inRoom(b.idx) : .local
            case .system:
                c.speaker = SpeakerLabelID.remote(b.idx)
            }
            return c
        }
    }

    private func attributeStage(_ id: String) async throws {
        let store = MeetingStore.shared
        let localName = await AppStateBridge.localSpeakerName()
        _ = try await store.update(id: id) { m in
            if !m.multipleInRoom {
                m.speakerNames[SpeakerLabelID.local.raw] = localName
            }
            // Number each group independently so "In-room 2" and "Speaker 2" are
            // never confused for one another.
            var roomN = 1, remoteN = 1
            for s in m.speakers {
                guard m.speakerNames[s.raw] == nil else {
                    if s.isInRoom { roomN += 1 } else if s.isRemote { remoteN += 1 }
                    continue
                }
                switch s.place {
                case .you:
                    m.speakerNames[s.raw] = localName
                case .room:
                    m.speakerNames[s.raw] = "In-room \(roomN)"; roomN += 1
                case .remote:
                    m.speakerNames[s.raw] = "Speaker \(remoteN)"; remoteN += 1
                }
            }
            // AD-4: sort by the shared session clock.
            m.utterances.sort { $0.start < $1.start }
        }
    }

    private func metadataStage(_ id: String) async throws {
        let store = MeetingStore.shared
        let meeting = try await store.load(id: id)

        // AD-12: prefer the LLM, fall back to the deterministic backend. The
        // fallback is NOT an error here — it is the expected path on this machine.
        var result: MeetingMetadata
        // FR-52 amends FR-27: preferring the LLM is a default, and an explicit
        // user choice wins over availability.
        let pinHeuristic = await AppStateBridge.pinHeuristicBackend()
        if !pinHeuristic, await llm.isAvailable() {
            do {
                result = try await llm.derive(from: meeting.utterances, names: meeting.speakerNames)
            } catch {
                Log.pipeline.info("LLM metadata failed, using heuristic: \(error.localizedDescription, privacy: .public)")
                result = try await heuristic.derive(from: meeting.utterances, names: meeting.speakerNames)
            }
        } else {
            result = try await heuristic.derive(from: meeting.utterances, names: meeting.speakerNames)
        }

        // No Meeting is ever left untitled (FR-26).
        if result.title.trimmingCharacters(in: .whitespaces).isEmpty {
            result.title = MeetingMetadata.fallback(date: meeting.startedAt, app: meeting.triggeringApp).title
        }
        _ = try await store.update(id: id) { $0.metadata = result }
    }

    private func writeStage(_ id: String) async throws {
        let store = MeetingStore.shared
        let meeting = try await store.load(id: id)
        guard let folder = await AppStateBridge.notesFolder() else {
            throw MinutesError.notesFolderUnavailable
        }
        let filename = try noteWriter.write(meeting: meeting, into: folder)
        _ = try await store.update(id: id) { $0.noteFilename = filename }
    }

    // MARK: - Note rewrite on edit (FR-35)

    /// Re-renders the Note after a title or speaker change, without re-running
    /// transcription or diarization (FR-24).
    func rewriteNote(meetingID id: String) async {
        let store = MeetingStore.shared
        guard let meeting = try? await store.load(id: id),
              meeting.stage == .written,
              let folder = await AppStateBridge.notesFolder() else { return }
        do {
            let filename = try noteWriter.write(meeting: meeting, into: folder)
            _ = try? await store.update(id: id) { $0.noteFilename = filename }
        } catch {
            Log.pipeline.error("note rewrite failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
