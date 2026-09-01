import SwiftUI
import AppKit

/// FR-36 … FR-40. A utility view over the Notes, not a second home for the data —
/// the Meeting record is the source of truth and the Note is a projection (AD-9).
struct MeetingsPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    /// A Set, not an optional: FR-40's amendment is multi-select delete, and
    /// "manage" stops meaning anything if clearing five test recordings takes five
    /// confirmations.
    @State private var selected: Set<String> = []
    @State private var confirmingDelete = false
    @State private var deleteNoteToo = false
    @State private var refreshing = false

    /// The one selected Meeting, or nil when the selection is empty or plural.
    private var single: Meeting? {
        guard selected.count == 1, let id = selected.first else { return nil }
        return app.meeting(id: id)
    }

    /// Selection order is not meaningful, but confirmation copy is, so the list is
    /// resolved in display order.
    private var selectedMeetings: [Meeting] {
        app.meetings.filter { selected.contains($0.id) }
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 380)
            if let m = single {
                MeetingDetail(meeting: m)
            } else {
                VStack {
                    Spacer()
                    Text(detailPlaceholder)
                        .font(.body).foregroundStyle(Tok.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Tok.surfaceWindow)
            }
        }
        .onAppear { Task { await AppStateBridge.reloadMeetings() } }
        .alert(deleteTitle, isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { confirmingDelete = false }
            Button("Delete", role: .destructive) {
                let ids = selectedMeetings.map(\.id)
                let alsoNote = deleteNoteToo
                selected = []
                // Reset the destructive option rather than letting it persist into
                // the next selection: a sticky "also delete notes" would silently
                // widen a later deletion the user did not re-consider.
                deleteNoteToo = false
                Task { await SessionCoordinator.shared.delete(meetingIDs: ids, alsoNote: alsoNote) }
            }
        } message: {
            // Enumerates exactly what will be removed before removing it (FR-40).
            Text(deleteMessage)
        }
    }

    private var detailPlaceholder: String {
        if app.meetings.isEmpty { return "No meetings yet. Click the menu bar icon to record one." }
        if selected.count > 1 { return "\(selected.count) meetings selected." }
        return "Select a meeting."
    }

    private var deleteTitle: String {
        selected.count > 1 ? "Delete \(selected.count) meetings?" : "Delete this meeting?"
    }

    /// Names the count and the Note consequence explicitly. Discoverability does
    /// not weaken confirmation — a destructive action still says what it destroys.
    private var deleteMessage: String {
        let ms = selectedMeetings
        let notes = ms.compactMap(\.noteFilename)
        if ms.count == 1 {
            guard deleteNoteToo else {
                return "The recording and transcript will be permanently deleted. The Markdown note will be left in your notes folder."
            }
            let name = notes.first.map { "the Markdown note “\($0)”" } ?? "its Markdown note"
            return "The recording, the transcript and \(name) will be permanently deleted."
        }
        let base = "\(ms.count) recordings and their transcripts will be permanently deleted."
        return deleteNoteToo
            ? base + " \(notes.count) Markdown \(notes.count == 1 ? "note" : "notes") will be deleted with them."
            : base + " Their Markdown notes will be left in your notes folder."
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(app.meetings) { m in
                    row(m).tag(m.id)
                }
            }
            .listStyle(.inset)
            // FR-40 amended: the standard key for the standard action. Still
            // routed through the confirmation.
            .onDeleteCommand(perform: selected.isEmpty ? nil : { confirmingDelete = true })

            // FR-54: an unreadable record is surfaced, never silently omitted.
            if !app.unreadableMeetings.isEmpty {
                StateBanner(kind: .degraded,
                            text: "\(app.unreadableMeetings.count) meeting \(app.unreadableMeetings.count == 1 ? "record" : "records") could not be read. They are still on disk.")
                    .padding(.horizontal, Tok.s4)
                    .padding(.bottom, Tok.s3)
            }

            libraryToolbar
        }
        .background(Tok.surfaceWindow)
    }

    /// The visible home for management actions. Previously delete, retry and
    /// rename existed only in a context menu, which the user never found — so the
    /// capability was shipped and unreachable.
    private var libraryToolbar: some View {
        HStack(spacing: Tok.s3) {
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(selected.isEmpty)
            .help(selected.count > 1 ? "Delete \(selected.count) meetings" : "Delete the selected meeting")

            Toggle(isOn: $deleteNoteToo) {
                Text("also delete notes").font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(selected.isEmpty)
            .help("Include the Markdown note when deleting")

            Spacer()

            if !selected.isEmpty {
                Text("\(selected.count) selected").font(.caption)
                    .foregroundStyle(Tok.textSecondary).monospacedDigit()
            }

            // FR-54.
            Button {
                refreshing = true
                Task {
                    await SessionCoordinator.shared.refreshLibrary()
                    refreshing = false
                }
            } label: {
                if refreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.borderless)
            .disabled(refreshing)
            .help("Re-read meetings and notes from disk")
        }
        .padding(.horizontal, Tok.s4)
        .padding(.vertical, Tok.s3)
        .background(.bar)
    }

    private func row(_ m: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(m.metadata?.title ?? "Untitled meeting")
                .font(.body).lineLimit(1)
            HStack(spacing: Tok.s3) {
                Text(dateLabel(m)).font(.caption).monospacedDigit()
                    .foregroundStyle(Tok.textSecondary)
                Text(Fmt.duration(m.duration)).font(.caption).monospacedDigit()
                    .foregroundStyle(Tok.textSecondary)
            }
            // A row carries its own state (FR-36).
            if m.hasFailed {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text("Failed").font(.caption2)
                }.foregroundStyle(Tok.recording)
            } else if app.inFlight.contains(m.id) {
                // A spinner now means work is genuinely running, not merely that
                // the record stopped short of `written`.
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                    Text(m.stage.displayName).font(.caption2).foregroundStyle(Tok.transcribing)
                }
            } else if !m.isComplete {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle").font(.caption2)
                    Text("Interrupted").font(.caption2)
                }.foregroundStyle(Tok.textSecondary)
            } else if app.missingNotes.contains(m.id) {
                // FR-53: complete in the record is not complete on disk.
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.ellipsis").font(.caption2)
                    Text("Note missing").font(.caption2)
                }.foregroundStyle(Tok.recording)
            } else {
                HStack(spacing: Tok.s2) {
                    ForEach(m.speakers.prefix(4), id: \.raw) { s in
                        SpeakerChip(name: m.displayName(for: s), place: s.place,
                                    isInferred: m.isInferred(s))
                    }
                    if m.speakers.count > 4 {
                        Text("+\(m.speakers.count - 4)").font(.caption2)
                            .foregroundStyle(Tok.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            if let f = m.noteFilename, let folder = prefs.notesFolder() {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(folder.appendingPathComponent(f).path,
                                                  inFileViewerRootedAtPath: folder.path)
                }
                Button("Open in Editor") {
                    NSWorkspace.shared.open(folder.appendingPathComponent(f))
                }
            }
            if m.hasFailed || (!m.isComplete && !app.inFlight.contains(m.id)) {
                Button(m.hasFailed ? "Retry transcription" : "Finish transcription") {
                    Task { await SessionCoordinator.shared.retry(meetingID: m.id) }
                }
            }
            if app.missingNotes.contains(m.id) {
                Button("Rewrite note") {
                    Task { await SessionCoordinator.shared.rewriteNote(meetingID: m.id) }
                }
            }
            // The recordings live under ~/Library, which Finder hides, so without
            // this there is no route to them from anywhere in the app.
            Button("Reveal recording in Finder") {
                Task {
                    let dir = await MeetingStore.shared.directory(for: m.id)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
            }
            Divider()
            Button("Delete…", role: .destructive) {
                deleteNoteToo = false
                // Right-clicking a row outside the selection acts on that row.
                if !selected.contains(m.id) { selected = [m.id] }
                confirmingDelete = true
            }
        }
    }

    private func dateLabel(_ m: Meeting) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(m.startedAt) ? "'Today' HH:mm" : "d MMM HH:mm"
        return f.string(from: m.startedAt)
    }
}

// MARK: - Detail

struct MeetingDetail: View {
    let meeting: Meeting
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var editingSpeaker: SpeakerLabelID?
    @State private var draftName = ""
    @State private var editingTitle = false
    @State private var draftTitle = ""
    /// Cached, not computed in the body. Regrouping the transcript on every body
    /// evaluation meant every keystroke in the title or a speaker name walked all
    /// of the meeting's utterances — 598 in the longest real one.
    @State private var blocks: [Meeting.TranscriptBlock] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.cardGap) {
                titleBlock
                if meeting.hasFailed { failureBlock }
                if !meeting.systemStreamCaptured && meeting.isComplete {
                    StateBanner(kind: .degraded,
                                text: "Only your microphone was captured, so remote participants are not in this transcript.")
                }
                speakerBlock
                if let md = meeting.metadata { metadataBlock(md) }
                transcriptBlock
                provenanceBlock
            }
            .padding(Tok.paneMargin)
        }
        .background(Tok.surfaceWindow)
        .onAppear { blocks = meeting.transcriptBlocks() }
        // Rebuilt only when the rendered transcript would actually differ — a
        // rename, a new utterance, a changed identification. Not on a keystroke.
        .onChange(of: meeting.transcriptRevision) { _, _ in
            blocks = meeting.transcriptBlocks()
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editingTitle {
                HStack {
                    TextField("Title", text: $draftTitle)
                        .textFieldStyle(.roundedBorder).font(.title2)
                        .onSubmit { commitTitle() }
                    Button("Save") { commitTitle() }.controlSize(.small)
                    Button("Cancel") { editingTitle = false }.controlSize(.small)
                }
            } else {
                Text(meeting.metadata?.title ?? "Untitled meeting")
                    .font(.largeTitle)
                    .onTapGesture(count: 2) {
                        draftTitle = meeting.metadata?.title ?? ""
                        editingTitle = true
                    }
                    .help("Double-click to rename")
            }
            HStack(spacing: Tok.s4) {
                Text(fullDate).font(.caption).foregroundStyle(Tok.textSecondary)
                Text(Fmt.duration(meeting.duration)).font(.caption).monospacedDigit()
                    .foregroundStyle(Tok.textSecondary)
                // FR-53: offering "Reveal note" for a file that is not there sends
                // the user to an empty Finder window, so the two cases are split.
                if noteIsMissing {
                    Button("Rewrite note") {
                        Task { await SessionCoordinator.shared.rewriteNote(meetingID: meeting.id) }
                    }
                    .buttonStyle(.borderless).font(.caption)
                } else if let f = meeting.noteFilename, let folder = prefs.notesFolder() {
                    Button("Reveal note") {
                        NSWorkspace.shared.selectFile(folder.appendingPathComponent(f).path,
                                                      inFileViewerRootedAtPath: folder.path)
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
            }
            if noteIsMissing {
                StateBanner(kind: .degraded,
                            text: "This meeting's note is not in your notes folder. Rewriting recreates it from the recording's stored transcript — nothing is re-transcribed, and your speaker names are kept.")
            }
        }
    }

    private var noteIsMissing: Bool { app.missingNotes.contains(meeting.id) }

    private func openSummaries() {
        app.paneRequest = MainWindow.Pane.summaries.rawValue
    }

    private var failureBlock: some View {
        VStack(alignment: .leading, spacing: Tok.s3) {
            StateBanner(kind: .degraded, text: meeting.failure ?? "Processing failed.")
            HStack {
                Button("Retry") { Task { await SessionCoordinator.shared.retry(meetingID: meeting.id) } }
                    .buttonStyle(.borderedProminent).tint(Tok.brand).controlSize(.small)
                Text("Stopped after: \(meeting.stage.displayName)")
                    .font(.caption).foregroundStyle(Tok.textSecondary)
            }
        }
    }

    /// Inline rename on the chip — a frequent action, so it is not buried in a
    /// sheet (FR-24).
    private var speakerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Speakers")
            Card {
                VStack(alignment: .leading, spacing: Tok.s3) {
                    ForEach(meeting.speakers, id: \.raw) { s in
                        HStack(spacing: Tok.s4) {
                            if editingSpeaker == s {
                                TextField("Name", text: $draftName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 180)
                                    .onSubmit { commitSpeaker(s) }
                                Button("Save") { commitSpeaker(s) }.controlSize(.small)
                                Button("Cancel") { editingSpeaker = nil }.controlSize(.small)
                            } else {
                                SpeakerChip(name: meeting.displayName(for: s),
                                            place: s.place,
                                            isInferred: meeting.isInferred(s),
                                            basis: meeting.basis(for: s))
                                if true {
                                    Button("Rename") {
                                        draftName = meeting.displayName(for: s)
                                        editingSpeaker = s
                                    }
                                    .buttonStyle(.borderless).font(.caption)
                                }
                                if meeting.isInferred(s) {
                                    Text("recognised automatically — check it is right")
                                        .font(.caption2).foregroundStyle(Tok.textSecondary)
                                }
                                // FR-65: a claim states its basis. The two ways a
                                // voice becomes "you" render identically in the
                                // transcript and must not render identically here —
                                // one cannot be wrong, the other is a measurement.
                                if let note = basisNote(for: s) {
                                    Text(note)
                                        .font(.caption2).foregroundStyle(Tok.textSecondary)
                                }
                                Spacer()
                                // Per-speaker, per-meeting, and never automatic. A
                                // room usually holds participants, so the app cannot
                                // tell a colleague beside you from a stranger beside
                                // you — but you can, instantly.
                                Button(meeting.isExcluded(s) ? "Include" : "Exclude") {
                                    Task {
                                        await SessionCoordinator.shared
                                            .setSpeakerExcluded(!meeting.isExcluded(s),
                                                                speaker: s, meetingID: meeting.id)
                                    }
                                }
                                .buttonStyle(.borderless).font(.caption)
                                .help(meeting.isExcluded(s)
                                      ? "Put this speaker back in the note"
                                      : "Leave this speaker out of the note — the speech is kept here")
                                Text("\(count(of: s)) lines").font(.caption).monospacedDigit()
                                    .foregroundStyle(meeting.isExcluded(s) ? Tok.textSecondary.opacity(0.6)
                                                                           : Tok.textSecondary)
                                Text(meeting.heardThrough(s)).font(.caption2)
                                    .foregroundStyle(Tok.textSecondary).lineLimit(1)
                            }
                        }
                    }
                    Text("Renaming two speakers to the same name merges them — the fix when one person was split in two.")
                        .font(.caption2).foregroundStyle(Tok.textSecondary)
                }
            }
        }
    }

    private func metadataBlock(_ md: MeetingMetadata) -> some View {
        VStack(alignment: .leading, spacing: Tok.cardGap) {
            // FR-55: say why the derived sections are absent, rather than leaving
            // the reader to wonder whether the meeting was too short or the app
            // silently failed.
            if md.summary.isEmpty && md.decisions.isEmpty && md.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "No summary")
                    Card {
                        VStack(alignment: .leading, spacing: Tok.s3) {
                            Text("This meeting has a transcript and a title, and no summary — nothing capable of writing one was available.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Set up summaries…") { openSummaries() }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                }
            }

            if !md.summary.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "Summary")
                    Card { Text(md.summary).font(.body).fixedSize(horizontal: false, vertical: true) }
                }
            }
            if !md.tags.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "Tags")
                    Card {
                        HStack(spacing: Tok.s3) {
                            ForEach(md.tags, id: \.self) { FactChip(text: $0) }
                            Spacer()
                        }
                    }
                }
            }
            // Empty sections are omitted rather than shown empty (FR-33).
            if !md.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "Decisions")
                    Card {
                        VStack(alignment: .leading, spacing: Tok.s3) {
                            ForEach(Array(md.decisions.enumerated()), id: \.offset) { _, d in
                                itemRow(d.text, at: d.at, owner: nil)
                            }
                        }
                    }
                }
            }
            if !md.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "Action items")
                    Card {
                        VStack(alignment: .leading, spacing: Tok.s3) {
                            ForEach(Array(md.actionItems.enumerated()), id: \.offset) { _, a in
                                itemRow(a.text, at: a.at, owner: a.owner)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Timestamp references so a reader can check derived content against the
    /// record (FR-29).
    private func itemRow(_ text: String, at: TimeInterval?, owner: String?) -> some View {
        HStack(alignment: .top, spacing: Tok.s3) {
            Text("•").foregroundStyle(Tok.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Tok.s3) {
                    if let owner { Text(owner).font(.caption).foregroundStyle(Tok.brand) }
                    if let at {
                        Text(Fmt.timestamp(at)).font(.caption).monospacedDigit()
                            .foregroundStyle(Tok.textSecondary)
                    }
                }
            }
        }
    }

    /// Handed to an `Equatable` child so a keystroke in the title or a speaker name
    /// does no transcript work at all. Stable block ids alone would let SwiftUI
    /// *diff* the rows instead of rebuilding them, which was the bulk of the fix;
    /// this stops it walking 600 of them to discover nothing changed.
    private var transcriptBlock: some View {
        TranscriptCard(blocks: blocks,
                       emptyReason: meeting.utterances.isEmpty
                           ? (meeting.stage < .transcribed
                              ? "Not transcribed yet — this recording was interrupted before it finished."
                              : "No speech was transcribed.")
                           : nil)
            .equatable()
    }

    private var provenanceBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: Tok.s2) {
                // Provenance is never ambiguous (FR-30).
                HStack(spacing: Tok.s3) {
                    FactChip(text: ModelCatalog.friendlyName(meeting.transcriptionModel ?? "unknown"))
                    if let b = meeting.metadata?.backend {
                        FactChip(text: b.displayName)
                    }
                    FactChip(text: meeting.systemStreamCaptured ? "System audio ✓" : "Mic only",
                             good: meeting.systemStreamCaptured)
                    FactChip(text: meeting.diarizationSucceeded ? "Speakers separated" : "Speakers not separated",
                             good: meeting.diarizationSucceeded)
                    if meeting.multipleInRoom {
                        FactChip(text: "Several people in the room")
                    }
                    if meeting.localIdentifiedByEnrolment {
                        FactChip(text: "You identified by voice", good: true)
                    }
                }
                Text("Everything above was produced on this Mac.")
                    .font(.caption2).foregroundStyle(Tok.textSecondary)
            }
        }
    }

    // MARK: - Helpers

    /// What the app's claim about this speaker rests on, in one line.
    ///
    /// Three of the five cases are refusals to claim an identity, and they render
    /// as ordinary text with no warning glyph — the app declining to guess is the
    /// product working, and dressing it as a failure would push a reader toward
    /// wanting the guess back. Only the two claims are annotated, because only a
    /// claim can be wrong.
    private func basisNote(for s: SpeakerLabelID) -> String? {
        switch meeting.basis(for: s) {
        case .structural:
            return "your microphone held a single voice, so this is certain"
        case .enrolmentMatch(let d):
            if let d {
                return String(format: "recognised from your recorded voice (distance %.2f — lower is closer)", d)
            }
            return "recognised from your recorded voice"
        case .inRoomUnplaceable:
            return "in the room, and no voice could be matched to it"
        case .inRoomAnonymous, .remote:
            return nil
        }
    }

    private func count(of s: SpeakerLabelID) -> Int {
        meeting.utterances.filter { $0.speaker == s }.count
    }

    private var fullDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM, HH:mm"
        return f.string(from: meeting.startedAt)
    }

    private func commitSpeaker(_ s: SpeakerLabelID) {
        let name = draftName
        editingSpeaker = nil
        Task { await SessionCoordinator.shared.renameSpeaker(meetingID: meeting.id, label: s, to: name) }
    }

    private func commitTitle() {
        let t = draftTitle
        editingTitle = false
        Task { await SessionCoordinator.shared.renameMeeting(meetingID: meeting.id, to: t) }
    }
}

/// The Transcript, as its own `Equatable` view.
///
/// Its only inputs are the already-grouped blocks and the reason the transcript is
/// empty, both value types — so SwiftUI can compare them and skip the body
/// entirely when a sibling's `@State` changed. Editing a title used to re-create
/// every row in here, each with a `fixedSize` text that forces its own layout
/// pass; on a 598-utterance meeting that is what "super slow and laggy" was.
private struct TranscriptCard: View, Equatable {
    let blocks: [Meeting.TranscriptBlock]
    let emptyReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Transcript")
            Card {
                if let emptyReason {
                    // An empty transcript has two very different causes, and saying
                    // "no speech" for the second one is simply wrong.
                    Text(emptyReason)
                        .font(.caption)
                        .foregroundStyle(Tok.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: Tok.s4) {
                        ForEach(blocks) { b in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Tok.s3) {
                                    Text(Fmt.timestamp(b.start)).font(.caption).monospacedDigit()
                                        .foregroundStyle(Tok.textSecondary)
                                    SpeakerChip(name: b.name, place: b.place,
                                                isInferred: b.isInferred, basis: b.basis)
                                }
                                // Transcript text is prose, not code — never monospaced.
                                Text(b.text).font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
