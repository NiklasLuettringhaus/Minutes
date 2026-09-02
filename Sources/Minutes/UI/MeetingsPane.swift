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
        rowContent(m, isSelected: selected.contains(m.id))
    }

    /// `isSelected` is a parameter rather than read from `selected`, so `--uishot`
    /// can render both states without driving a `List`'s selection — and because
    /// the selected state is where the colour defects live, it is the state most
    /// worth being able to render.
    @ViewBuilder
    func rowContent(_ m: Meeting, isSelected: Bool) -> some View {
        MeetingRow(meeting: m, isSelected: isSelected,
                   isInFlight: app.inFlight.contains(m.id),
                   noteMissing: app.missingNotes.contains(m.id))
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
    /// Which speaker is being renamed from inside the transcript, if any.
    ///
    /// The user asked for this directly: *"renaming should be possible within the
    /// script not just the speaker list at the top."* They are right, and the
    /// reason is that the transcript is where you *recognise* a voice — you read a
    /// line, know who said it, and the fix should be there rather than after
    /// scrolling back to a list that no longer says which one they were.
    @State private var renamingInTranscript: SpeakerLabelID?
    @State private var transcriptDraft = ""

    var body: some View {
        ShotScroll {
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
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) {
                        draftTitle = meeting.metadata?.title ?? ""
                        editingTitle = true
                    }
                    .help("Double-click to rename")
            }
            // `fixedSize` on each item, so a narrow detail column wraps the row
            // rather than hyphenating "Tuesday 1 September" down the middle of a
            // word — which is what it was doing.
            HStack(spacing: Tok.s4) {
                Text(fullDate).font(.caption).foregroundStyle(Tok.textSecondary)
                    .fixedSize()
                Text(Fmt.duration(meeting.duration)).font(.caption).monospacedDigit()
                    .foregroundStyle(Tok.textSecondary)
                    .fixedSize()
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
                    .fixedSize()
                }
                Spacer(minLength: 0)
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

    /// Who spoke, grouped by where they were.
    ///
    /// **Rebuilt after the user photographed it.** The previous version was a flat
    /// list of one row per speaker, each two lines tall, each carrying its own copy
    /// of "heard through MacBook Pro Microphone". On a real fourteen-speaker
    /// meeting that is a 1100pt wall of near-identical text before the transcript,
    /// with 28 borderless text buttons in it — and the user's words were "stuff is
    /// squeezed together and I am not sure what buttons to click". Both halves of
    /// that were fair.
    ///
    /// Three changes, each removing repetition rather than shrinking it:
    ///
    /// - **Grouped by place**, with the device named once per group instead of once
    ///   per speaker. Place is the structural fact (AD-11), so it is also the
    ///   honest way to group, and eight identical device lines collapse to one.
    /// - **One line per speaker.** The provenance sentence stays only where it is a
    ///   *claim* — the two rows where the app says who someone is — rather than on
    ///   every row, where it was mostly restating the group heading.
    /// - **Bordered buttons.** `.borderless` renders a button as plain text, which
    ///   is precisely why the user could not tell what was clickable.
    private var speakerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Speakers", trailing: AnyView(
                Text(meeting.speakers.count == 1 ? "1 voice"
                                                 : "\(meeting.speakers.count) voices")
                    .font(.caption).foregroundStyle(Tok.textSecondary)
            ))
            Card {
                VStack(alignment: .leading, spacing: Tok.s5) {
                    ForEach(speakerGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: Tok.s3) {
                            // The device, once per group rather than once per row.
                            HStack(spacing: Tok.s2) {
                                Text(group.title).font(.caption).fontWeight(.medium)
                                Text("·").foregroundStyle(Tok.separator)
                                Text(group.heardThrough).font(.caption)
                                    .foregroundStyle(Tok.textSecondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            ForEach(group.speakers, id: \.raw) { s in
                                speakerRow(s)
                            }
                        }
                    }
                    Text("Renaming two speakers to the same name merges them — the fix when one person was split in two. You can also rename from any line in the transcript below.")
                        .font(.caption2).foregroundStyle(Tok.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// In-room voices, then remote ones. Each group names the device once.
    private var speakerGroups: [SpeakerGroup] {
        let inRoom = meeting.speakers.filter { !$0.isRemote }
        let remote = meeting.speakers.filter(\.isRemote)
        var out: [SpeakerGroup] = []
        if let first = inRoom.first {
            out.append(SpeakerGroup(title: inRoom.count == 1 ? "In the room" : "In the room with you",
                                    heardThrough: meeting.heardThrough(first),
                                    speakers: inRoom))
        }
        if let first = remote.first {
            out.append(SpeakerGroup(title: "On the call",
                                    heardThrough: meeting.heardThrough(first),
                                    speakers: remote))
        }
        return out
    }

    struct SpeakerGroup {
        let title: String
        let heardThrough: String
        let speakers: [SpeakerLabelID]
    }

    @ViewBuilder
    private func speakerRow(_ s: SpeakerLabelID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if editingSpeaker == s {
                HStack(spacing: Tok.s3) {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { commitSpeaker(s) }
                    Button("Save") { commitSpeaker(s) }
                        .buttonStyle(.borderedProminent).tint(Tok.brand).controlSize(.small)
                    Button("Cancel") { editingSpeaker = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                    Spacer(minLength: 0)
                }
            } else {
                // One line when it fits, two when it does not. The detail column
                // has a 560pt minimum so one line is the real case — but the tool
                // rendered this at 320pt and the row overflowed its container
                // instead of adapting, which is the same class of bug as the
                // collapse it just replaced. `ViewThatFits` makes the narrow case
                // degrade rather than break.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tok.s3) {
                        identity(s)
                        Spacer(minLength: Tok.s3)
                        controls(s)
                    }
                    VStack(alignment: .leading, spacing: Tok.s2) {
                        HStack(spacing: Tok.s3) { identity(s); Spacer(minLength: 0) }
                        HStack(spacing: Tok.s3) { controls(s); Spacer(minLength: 0) }
                    }
                }
                // Only where the app is making a claim about identity (FR-65), not
                // on every row. On the others this line said what the group heading
                // above it already says.
                if let note = claimNote(for: s) {
                    Text(note)
                        .font(.caption2).foregroundStyle(Tok.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Who, and how much they said.
    @ViewBuilder
    private func identity(_ s: SpeakerLabelID) -> some View {
        SpeakerChip(name: meeting.displayName(for: s),
                    place: s.place,
                    isInferred: meeting.isInferred(s),
                    basis: meeting.basis(for: s))
        Text(lineCount(s)).font(.caption).monospacedDigit()
            .foregroundStyle(meeting.isExcluded(s) ? Tok.textSecondary.opacity(0.6)
                                                   : Tok.textSecondary)
            .fixedSize()
    }

    /// Bordered, so they read as controls. The previous borderless pair rendered as
    /// two more words of grey text among four others, which is why the user could
    /// not tell what was clickable.
    @ViewBuilder
    private func controls(_ s: SpeakerLabelID) -> some View {
        Button("Rename") {
            draftName = meeting.displayName(for: s)
            editingSpeaker = s
        }
        .buttonStyle(.bordered).controlSize(.small).fixedSize()
        // Per-speaker, per-meeting, and never automatic. A room usually holds
        // participants, so the app cannot tell a colleague beside you from a
        // stranger beside you — but you can, instantly.
        Button(meeting.isExcluded(s) ? "Include" : "Exclude") {
            Task {
                await SessionCoordinator.shared
                    .setSpeakerExcluded(!meeting.isExcluded(s),
                                        speaker: s, meetingID: meeting.id)
            }
        }
        .buttonStyle(.bordered).controlSize(.small).fixedSize()
        .help(meeting.isExcluded(s)
              ? "Put this speaker back in the note"
              : "Leave this speaker out of the note — the speech is kept here")
    }

    private func lineCount(_ s: SpeakerLabelID) -> String {
        let n = count(of: s)
        return n == 1 ? "1 line" : "\(n) lines"
    }

    /// The basis, but only when it is an identity *claim* or an explicit refusal —
    /// the two cases a reader cannot infer from the group heading.
    private func claimNote(for s: SpeakerLabelID) -> String? {
        var parts: [String] = []
        switch meeting.basis(for: s) {
        case .structural:
            parts.append("your microphone held a single voice, so this is certain")
        case .enrolmentMatch(let d):
            if let d {
                parts.append(String(format: "recognised from your recorded voice (distance %.2f — lower is closer)", d))
            } else {
                parts.append("recognised from your recorded voice")
            }
        case .inRoomUnplaceable:
            parts.append("speech from the room that could not be matched to any voice")
        case .inRoomAnonymous, .remote:
            break
        }
        if meeting.isInferred(s) { parts.append("recognised automatically — check it is right") }
        if meeting.isExcluded(s) { parts.append("left out of the note") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
                           : nil,
                       renaming: $renamingInTranscript,
                       draft: $transcriptDraft,
                       onCommit: { label, name in
                           renamingInTranscript = nil
                           let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                           guard !trimmed.isEmpty else { return }
                           Task {
                               await SessionCoordinator.shared.renameSpeaker(
                                   meetingID: meeting.id, label: label, to: trimmed)
                           }
                       })
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
    @Binding var renaming: SpeakerLabelID?
    @Binding var draft: String
    let onCommit: (SpeakerLabelID, String) -> Void

    /// Compares only what is rendered. The closure is not comparable and the
    /// bindings change identity on every parent render, so both are excluded
    /// deliberately — `renaming` is included because it *is* rendered.
    static func == (a: TranscriptCard, b: TranscriptCard) -> Bool {
        a.blocks == b.blocks && a.emptyReason == b.emptyReason && a.renaming == b.renaming
    }

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
                                    // The chip is the rename affordance here. You
                                    // recognise a voice by reading what it said, so
                                    // the fix belongs on the line you recognised it
                                    // from — not in a list you have to scroll back
                                    // to, where the speaker is a label again.
                                    Button {
                                        draft = b.name
                                        renaming = b.speaker
                                    } label: {
                                        SpeakerChip(name: b.name, place: b.place,
                                                    isInferred: b.isInferred, basis: b.basis)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Click to rename \(b.name) everywhere in this meeting")
                                    .popover(isPresented: Binding(
                                        get: { renaming == b.speaker },
                                        set: { if !$0 && renaming == b.speaker { renaming = nil } }
                                    ), arrowEdge: .bottom) {
                                        renamePopover(b)
                                    }
                                    Spacer(minLength: 0)
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

    /// Small, and says what the rename will do. "Everywhere in this meeting" is
    /// the part worth stating: FR-24 renames the label, not the one line, and a
    /// user clicking a single line could reasonably expect otherwise.
    @ViewBuilder
    private func renamePopover(_ b: Meeting.TranscriptBlock) -> some View {
        VStack(alignment: .leading, spacing: Tok.s3) {
            Text("Rename this speaker").font(.body)
            Text("Applies to every line they spoke in this meeting, and Minutes will recognise the voice next time.")
                .font(.caption2).foregroundStyle(Tok.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { onCommit(b.speaker, draft) }
            HStack {
                Button("Cancel") { renaming = nil }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button("Rename") { onCommit(b.speaker, draft) }
                    .buttonStyle(.borderedProminent).tint(Tok.brand).controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Tok.s5)
    }
}

/// One row in the Meetings list.
///
/// Its own view, with explicit inputs and no `@EnvironmentObject`, for two
/// reasons. It can be rendered standalone by `--uishot` — which matters because
/// every layout defect this row has shipped was a *narrow-column* defect that the
/// default window width hid. And a row that declares what it depends on cannot
/// silently start depending on more, which is how it grew to eight children in
/// the first place.
struct MeetingRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let isInFlight: Bool
    let noteMissing: Bool

    var body: some View {
        // The system fills a selected row with the user's accent and owns the
        // foreground of everything inside it. Anything here that paints its own
        // colour has to know that, or it paints itself invisible — which is
        // exactly what the speaker chips were doing.
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.metadata?.title ?? "Untitled meeting")
                .font(.body).lineLimit(1)
            HStack(spacing: Tok.s3) {
                Text(dateLabel).font(.caption).monospacedDigit()
                    .foregroundStyle(secondary)
                Text(Fmt.duration(meeting.duration)).font(.caption).monospacedDigit()
                    .foregroundStyle(secondary)
                Spacer(minLength: 0)
            }
            // A row carries its own state (FR-36). Every branch paints its own
            // colour, so every branch yields it to a selection fill.
            state
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var state: some View {
        if meeting.hasFailed {
            label("exclamationmark.triangle.fill", "Failed", stateTint(Tok.recording))
        } else if isInFlight {
            // A spinner means work is genuinely running, not merely that the
            // record stopped short of `written`.
            HStack(spacing: 4) {
                ProgressView().controlSize(.small).scaleEffect(0.6)
                Text(meeting.stage.displayName).font(.caption2)
                    .foregroundStyle(stateTint(Tok.transcribing))
            }
        } else if !meeting.isComplete {
            label("pause.circle", "Interrupted", secondary)
        } else if noteMissing {
            // FR-53: complete in the record is not complete on disk.
            label("doc.badge.ellipsis", "Note missing", stateTint(Tok.recording))
        } else {
            speakers
        }
    }

    /// Chips wrap rather than compress.
    ///
    /// This is the defect the user photographed: chips in a `HStack` at a narrow
    /// width were squeezed into tall vertical ovals with one letter per line,
    /// because an `HStack` distributes a shortfall across its children and a
    /// `Text` with no line limit accepts it. `FlowLayout` moves the overflow to a
    /// second line instead, and `lineLimit(1)` inside the chip refuses to be
    /// narrowed at all. Two speakers per row at 320pt is legible; "In-ro om 1"
    /// stacked vertically is not.
    private var speakers: some View {
        FlowLayout(spacing: Tok.s2) {
            ForEach(meeting.speakers.prefix(4), id: \.raw) { s in
                SpeakerChip(name: meeting.displayName(for: s), place: s.place,
                            isInferred: meeting.isInferred(s),
                            inSelectedRow: isSelected)
            }
            if meeting.speakers.count > 4 {
                Text("+\(meeting.speakers.count - 4)").font(.caption2)
                    .foregroundStyle(isSelected
                                     ? Color(nsColor: .alternateSelectedControlTextColor)
                                     : Tok.textSecondary)
            }
        }
    }

    private func label(_ glyph: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: glyph).font(.caption2)
            Text(text).font(.caption2)
        }.foregroundStyle(tint)
    }

    /// Secondary text inside a row: the selection's own secondary colour when the
    /// row is filled, `{colors.text-secondary}` otherwise.
    private var secondary: Color {
        isSelected ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.75)
                   : Tok.textSecondary
    }

    /// A state tint — recording red, transcribing amber — inside a row that may be
    /// filled. On a filled row the tint is surrendered: the glyph beside it already
    /// carries the state, and a warm tint on the user's accent is unreadable at any
    /// contrast. DESIGN.md's rule that colour is never the only signal, arriving
    /// where it was needed rather than where it was written.
    private func stateTint(_ tint: Color) -> Color {
        isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : tint
    }

    private var dateLabel: String {
        let f = DateFormatter()
        let cal = Calendar.current
        f.dateFormat = cal.isDateInToday(meeting.startedAt) ? "'Today' HH:mm" : "d MMM HH:mm"
        return f.string(from: meeting.startedAt)
    }
}
