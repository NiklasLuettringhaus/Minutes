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

        let micURL = await store.audioURL(id: id, stream: .mic)
        let systemURL = await store.audioURL(id: id, stream: .system)

        // FR-89. Measured before anything is transcribed, because the result
        // decides what the Transcript keeps and what Diarization clusters.
        //
        // **The detector runs even where the device says Echo was impossible**
        // (FR-98). It costs a fraction of a second against a transcription, and
        // it is the only way a disagreement between the two can exist to be
        // recorded — a measurement not taken cannot contradict anything. What
        // the device decides is whether the *exclusion* acts, not whether the
        // measurement happens.
        var echo = EchoAnalysis.notApplicable
        do {
            echo = try EchoDetector.analyse(micURL: micURL, systemURL: systemURL)
        } catch {
            // A failure to measure is `undetermined`, never `clean` (AD-49).
            echo = .undetermined
            Log.audio.info("echo: \(error.localizedDescription, privacy: .public) — undetermined")
        }
        echo.deviceKind = try await store.load(id: id).outputDevice?.kind
        if echo.deviceContradictsSignal {
            Log.audio.error("echo: the signal says present and the output device says headphones — nothing excluded, both recorded")
        }

        // The Mic Stream is the room; the System Stream is the far end. That
        // split is structural (AD-11) and holds only over Mic Stream audio the
        // far end did not arrive in (AD-47).
        var micSegments: [TranscribedSegment] = []
        if let micURL {
            micSegments = try await transcriber(for: model).transcribe(url: micURL, model: model).segments
        }
        var systemSegments: [TranscribedSegment] = []
        if let systemURL {
            systemSegments = try await transcriber(for: model).transcribe(url: systemURL, model: model).segments
        }

        // FR-90. A Mic Stream segment is dropped only where the audio *and* the
        // text agree it repeats the far end. Either signal alone is unsafe: the
        // audio test costs 13% of the user's own words at the recall it needs,
        // and the text test cannot tell an echo from two people agreeing.
        //
        // The System Stream spans are shifted onto the Mic Stream's timeline
        // first. The two files do not start at the same instant — measured
        // length differences across the real library run from -364 ms to
        // +3,278 ms — so comparing raw offsets would misalign the very
        // recordings this is for.
        //
        // **Two different shifts, and increment 10 separated them (FR-97, AD-53).**
        // The *capture* offset is when each file started, measured from the two
        // devices' host clocks; it applies to every Session that captured both
        // Streams and it is what puts the merged Transcript in the order things
        // were said. The *echo delay* is the acoustic path from the loudspeaker
        // back to the microphone; it applies only where there is an echo, and
        // only to the comparison that decides whether a mic Utterance repeats
        // one on the other Stream. Adding them is right for the echo comparison
        // and adding only the first is right for the merge.
        let captureOffset = try await store.load(id: id).streamStartOffset
        let echoDelay = echo.mayExclude ? (echo.delaySeconds ?? 0) : 0
        let shift = (captureOffset ?? 0) + echoDelay
        let outcome = EchoDeduplication.apply(
            mic: micSegments.map { .init(start: $0.start, end: $0.end, text: $0.text) },
            system: systemSegments.map {
                .init(start: $0.start + shift, end: $0.end + shift, text: $0.text)
            },
            echoFlagged: { span in
                echo.mayExclude && echo.isMostlyEcho(from: span.start, to: span.end)
            })
        let dropped = Set(outcome.droppedIndices)
        if !dropped.isEmpty {
            Log.audio.info("""
                echo: dropped \(dropped.count, privacy: .public) mic segments \
                (\(outcome.droppedWords, privacy: .public) words), \
                \(outcome.residualDuplicateWords, privacy: .public) residual
                """)
        }

        for (index, segment) in micSegments.enumerated() where !dropped.contains(index) {
            guard let text = clean(segment.text) else { continue }
            utterances.append(Utterance(start: segment.start, end: segment.end, text: text,
                                        speaker: .local, origin: .mic,
                                        confidence: segment.confidence))
        }
        // System Stream segments start unassigned; diarization names them next.
        //
        // FR-97: their times are positions in *their own file*, and the two files
        // did not start together. `captureOffset` puts them on the Mic Stream's
        // clock, which is the one AD-4 calls the session clock. Where it was
        // never measured it is zero, which is the behaviour every Meeting before
        // increment 10 had — an unknown offset is not applied, and a stored
        // Meeting is never re-ordered by a guess.
        for segment in systemSegments {
            guard let text = clean(segment.text) else { continue }
            utterances.append(Utterance(
                start: StreamAlignment.micTime(ofSystemTime: segment.start, offset: captureOffset),
                end: StreamAlignment.micTime(ofSystemTime: segment.end, offset: captureOffset),
                text: text, speaker: SpeakerLabelID.remote(0), origin: .system,
                confidence: segment.confidence))
        }
        guard !utterances.isEmpty else {
            throw MinutesError.transcriptionFailed("No speech was found in the recording.")
        }

        // FR-96. Speech the app had and produced nothing for.
        //
        // Measured against the audio rather than asked of the engine, because
        // everything an engine reports about an interval it produced nothing for
        // describes *silence*, which is the opposite question. Echo-excluded
        // audio is subtracted: it is speech Minutes has, once, on the other
        // Stream, and reporting it as unreadable would present a working feature
        // as a failure — on the worst real recording, as having lost 45% of the
        // microphone.
        var gaps: [TranscriptGap] = []
        for (stream, url) in [(StreamKind.mic, micURL), (StreamKind.system, systemURL)] {
            guard let url else { continue }
            do {
                let (active, frameSeconds) = try AudioActivity.mask(of: url)
                let covered = utterances.filter { $0.origin == stream }
                    .map { $0.start...max($0.start, $0.end) }
                let excluded = stream == .mic && echo.mayExclude
                    ? echo.excludedIntervals.map { $0.start...max($0.start, $0.end) }
                    : []
                gaps += TranscriptGaps.find(active: active, frameSeconds: frameSeconds,
                                            covered: covered, excluded: excluded,
                                            stream: stream)
            } catch {
                // A stream that cannot be scanned yields no gaps, which reads as
                // "not looked for" rather than "none" — the same rule as every
                // other absent measurement in this increment.
                Log.audio.info("gaps: could not scan \(stream.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !gaps.isEmpty {
            Log.pipeline.info("gaps: \(gaps.count, privacy: .public) interval(s), \(Int(TranscriptGaps.total(gaps)), privacy: .public)s unreadable")
        }

        let foundGaps = gaps
        _ = try await store.update(id: id) {
            $0.utterances = utterances.sorted { $0.start < $1.start }
            $0.transcriptionModel = model
            $0.echo = echo
            $0.gaps = foundGaps
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
        /// Which mic cluster the enrolled voice matched, when it matched one
        /// unambiguously. `nil` means the app claims nothing, which is what it did
        /// before enrolment existed and what it must keep doing.
        var localMicVoice: Int?
        var localMatchDistance: Float?

        // --- Microphone: the room ---
        //
        // **Diarization runs on the recording as it is, and the reason is a
        // measurement that refuted the design.** AD-47 first had clustering run
        // on Echo-muted audio, on the argument that clustering tolerates missing
        // frames while the Transcript does not. Checked against the real
        // Diarizer on the three affected recordings — once on the recording,
        // once on the muted copy — the voice count went **5 to 7, 6 to 6, and
        // 3 to 5**. Muting made it worse or made no difference, never better.
        //
        // In hindsight the mechanism is obvious: muting punches silence through
        // the middle of continuous speech, so one voice arrives as a handful of
        // fragments and the clusterer splits it. The Echo is gone and the room
        // is now more crowded than before.
        //
        // So the phantom-attendee half of AD-47 is **not implemented**, and
        // pretending otherwise by shipping a change that worsens the number
        // would be worse than leaving the defect visible. FR-90's Transcript
        // rule stands on its own measurement and is unaffected. The route that
        // remains untried is filtering the *clusters* after diarization rather
        // than the audio before it — a cluster whose spans are mostly Echo is
        // the far end — which never fragments anybody's speech.
        if let mic = await store.audioURL(id: id, stream: .mic) {

            do {
                let (spans, c) = try await diarizer.diarizeFull(url: mic)
                let voices = Set(spans.map(\.speakerIndex))
                if voices.count > 1 {
                    // Several people in the room. Which of them is the user is not
                    // assumed — it is either measured against an enrolled voice
                    // (FR-63) or left unclaimed, exactly as before.
                    multipleInRoom = true
                    micSpans = spans

                    // FR-63 / AD-30. The lookup happens here because this is the
                    // only stage holding the mic clusters' embeddings, and its
                    // result is handed to `assign` as a value — no stage is added
                    // to AD-8's list, and `assign` gains no dependency on the
                    // speaker store.
                    let candidates = VoiceMatch.candidates(from: c,
                                                           producer: SpeakerKitVoiceEmbedder.producerID)
                    let resolution = await SpeakerDirectory.shared.identifyLocal(among: candidates)
                    localMicVoice = VoiceMatch.micVoiceIndex(resolution)
                    localMatchDistance = resolution.matchedDistance

                    // The identified voice is keyed `local` so every consumer —
                    // the note, the detail pane, a future rename — sees the user
                    // where it expects them, and the rest stay in-room.
                    for (idx, vec) in c {
                        let label = (idx == localMicVoice)
                            ? SpeakerLabelID.local
                            : SpeakerLabelID.inRoom(idx)
                        centroids[label.raw] = vec
                    }
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
                // FR-97 / AD-53. These spans are positions in system.wav; the
                // Utterances they will be matched against were moved onto the Mic
                // Stream's clock at transcription. Both sides of the comparison
                // have to be on the same clock or `assign` matches an Utterance
                // against whoever was speaking seconds earlier — which on the
                // worst measured offset is 3.3 seconds of the wrong speaker.
                let offset = (try? await store.load(id: id).streamStartOffset) ?? 0
                systemSpans = offset == 0 ? spans : spans.map {
                    DiarizedSpan(start: $0.start + offset, end: $0.end + offset,
                                 speakerIndex: $0.speakerIndex)
                }
                for (idx, vec) in c { centroids[SpeakerLabelID.remote(idx).raw] = vec }
                if !spans.isEmpty { anySucceeded = true }
            } catch {
                Log.pipeline.error("system diarization failed, degrading to one speaker: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Name any voice we already know from a previous meeting (FR-25).
        //
        // The Local Speaker is deliberately not a candidate here. AD-30 gives the
        // user's identity exactly two sources — the structural fact of one voice on
        // the microphone, or an enrolment match — and their *display name* one owner,
        // the setting in General. Letting the rename-learned path name `local` as
        // well would add a third writer, and its visible symptom would be the
        // user's own chip rendering as `~Niklas`: marked inferred when it is the one
        // label that was either certain or measured.
        var names: [String: String] = [:]
        var inferred: [String] = []
        for (label, vec) in centroids where label != SpeakerLabelID.local.raw {
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
        let localVoice = localMicVoice, localDistance = localMatchDistance
        _ = try await store.update(id: id) { m in
            m.diarizationSucceeded = ok
            m.multipleInRoom = multi
            m.localIdentifiedByEnrolment = localVoice != nil
            m.localMatchDistance = localDistance
            for (k, v) in names { m.speakerNames[k] = v }
            m.inferredSpeakers = inferred
            m.utterances = Self.assign(micSpans: mic, systemSpans: sysSpans,
                                       multipleInRoom: multi,
                                       localMicVoice: localVoice, to: m.utterances)
        }
    }

    /// Assigns each Utterance to the diarized voice whose span overlaps it most,
    /// within its own stream. A mic Utterance can only become an in-room voice and
    /// a system Utterance can only become a remote one — the streams never mix,
    /// which is the part of the original design that survives.
    ///
    /// `localMicVoice`, when set, names the one mic cluster the user's enrolled
    /// voice matched (FR-63). It changes **which** in-room voice becomes the Local
    /// Speaker and nothing else: the stream rules above still hold, an unplaceable
    /// mic utterance is still unidentified in-room speech, and with the parameter
    /// absent this function behaves exactly as it did before enrolment existed —
    /// which is why it has a default, so the tests that assert the old behaviour
    /// assert it against unchanged call sites.
    static func assign(micSpans: [DiarizedSpan],
                       systemSpans: [DiarizedSpan],
                       multipleInRoom: Bool,
                       localMicVoice: Int? = nil,
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
                // One voice on the mic stays the user. With several, the enrolled
                // voice's match is the user and the rest are in-room voices; with
                // no match, none of them is claimed.
                if !multipleInRoom {
                    c.speaker = .local
                } else if let localMicVoice, b.idx == localMicVoice {
                    c.speaker = .local
                } else {
                    c.speaker = SpeakerLabelID.inRoom(b.idx)
                }
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
            // The naming rules are a pure function on the Meeting (Core), so they
            // are testable without a store — see `assignedSpeakerNames`.
            m.speakerNames = m.assignedSpeakerNames(localName: localName)
            // AD-4: sort by the shared session clock.
            m.utterances.sort { $0.start < $1.start }
        }
    }

    private func metadataStage(_ id: String) async throws {
        let store = MeetingStore.shared
        let meeting = try await store.load(id: id)

        // FR-86 / AD-46. Nothing is derived from a stream the app cannot vouch
        // for. This is the clause that addresses *why* the sample-rate defect
        // looked fine for three days: seven recordings arrived with confident
        // titles — "Die", "Sorry", "Put The Fashion" — generated from fabricated
        // text, and read as ordinary weak auto-titles.
        let usable = meeting.trustworthyUtterances
        if usable.count != meeting.utterances.count {
            let dropped = meeting.utterances.count - usable.count
            Log.pipeline.error("metadata: ignoring \(dropped, privacy: .public) utterances from a stream that failed its rate check")
        }
        guard !usable.isEmpty else {
            // No trustworthy speech at all: the Meeting still gets a name, and
            // the name is a date, which is honest (FR-26).
            let fallback = MeetingMetadata.fallback(date: meeting.startedAt, app: meeting.triggeringApp)
            _ = try await store.update(id: id) { $0.metadata = fallback }
            Log.pipeline.error("metadata: no trustworthy speech, using the date as the title")
            return
        }

        // AD-12: prefer the LLM, fall back to the deterministic backend. The
        // fallback is NOT an error here — it is the expected path on this machine.
        var result: MeetingMetadata
        // FR-52 amends FR-27: preferring the LLM is a default, and an explicit
        // user choice wins over availability.
        let pinHeuristic = await AppStateBridge.pinHeuristicBackend()
        if !pinHeuristic, await llm.isAvailable() {
            do {
                result = try await llm.derive(from: usable, names: meeting.speakerNames)
            } catch {
                Log.pipeline.info("LLM metadata failed, using heuristic: \(error.localizedDescription, privacy: .public)")
                result = try await heuristic.derive(from: usable, names: meeting.speakerNames)
            }
        } else {
            result = try await heuristic.derive(from: usable, names: meeting.speakerNames)
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
        // First write of a Meeting's Note: there is nothing on disk to locate and
        // nothing to conflict with, so a refusal here would mean the destination
        // is occupied by a file with someone else's bytes — which `uniqueFilename`
        // has already avoided.
        let outcome = try noteWriter.write(meeting: meeting, into: folder, at: nil)
        try await Self.persist(outcome, id: id, store: store)
    }

    /// AD-41: the filename and the digest are persisted in the same update, so a
    /// record can never hold one without the other.
    static func persist(_ outcome: NoteWriteOutcome, id: String, store: MeetingStore) async throws {
        switch outcome {
        case .wrote(let filename, let written, let digest):
            _ = try await store.update(id: id) {
                $0.noteFilename = filename
                $0.noteFilenameWritten = written
                $0.noteDigest = digest
            }
        case .refusedChangedOnDisk:
            break
        }
    }

    // MARK: - Note rewrite on edit (FR-35)

    /// Re-renders the Note after a title or speaker change, without re-running
    /// transcription or diarization (FR-24).
    /// Re-renders the Note after a title or speaker change (FR-24, FR-35).
    ///
    /// **Finds the file before it writes one.** Deriving the destination from the
    /// stored filename without checking it is how a Note the user had renamed in
    /// Finder became a second file, with the user's copy orphaned — reachable by
    /// clicking the one remedy the app offered for the break.
    ///
    /// Returns the outcome so the caller can surface a refusal (FR-81). It is
    /// discardable because most callers are fire-and-forget edits.
    @discardableResult
    func rewriteNote(meetingID id: String) async -> NoteWriteOutcome? {
        let store = MeetingStore.shared
        guard let meeting = try? await store.load(id: id),
              meeting.stage == .written,
              let folder = await AppStateBridge.notesFolder() else { return nil }
        let resolved = await NoteLinkService.resolvedNoteURL(for: meeting, in: folder)
        do {
            let outcome = try noteWriter.write(meeting: meeting, into: folder, at: resolved)
            try await Self.persist(outcome, id: id, store: store)
            return outcome
        } catch {
            Log.pipeline.error("note rewrite failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
