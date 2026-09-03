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
    /// The files the confirmed delete will actually remove, resolved when the
    /// dialog is raised (FR-40 as amended).
    ///
    /// Held in state rather than computed in `deleteMessage`, because resolving a
    /// Note Link reads the folder and a SwiftUI body must not.
    @State private var deleteTargets: DeleteTargets = .init()
    @State private var showingUnclaimed = false

    struct DeleteTargets: Equatable {
        var meetings = 0
        /// Files that exist and will be trashed. Not names off the record.
        var noteFiles: [String] = []
        /// Meetings whose Note could not be found at all.
        var notesNotFound = 0
    }

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
    ///
    /// **It names the file that will actually be deleted** (FR-40 as amended).
    /// This used to read the filename off the record, so on a Note the user had
    /// renamed in Finder it named a file that was not there and would not be
    /// touched — a false statement at the exact moment the user was deciding
    /// whether to trust it. The same path would have deleted a *different* file if
    /// a name had been reused.
    private var deleteMessage: String {
        let t = deleteTargets
        let recordings = t.meetings == 1
            ? "The recording and transcript"
            : "\(t.meetings) recordings and their transcripts"
        let trash = " \(t.meetings == 1 ? "goes" : "go") to the Trash, so this can be undone."

        guard deleteNoteToo else {
            return recordings + trash + " The Markdown \(t.meetings == 1 ? "note" : "notes") will be left in your notes folder."
        }
        if t.noteFiles.isEmpty {
            // Says so rather than naming what the record remembers.
            return recordings + trash + " Minutes could not find "
                + (t.meetings == 1 ? "this meeting's note" : "any of their notes")
                + " in your notes folder, so nothing there will be touched."
        }
        var out = recordings
        if t.noteFiles.count == 1 {
            out += " and “\(t.noteFiles[0])”" + trash
        } else {
            out += " and \(t.noteFiles.count) notes — "
                + t.noteFiles.map { "“\($0)”" }.joined(separator: ", ") + " —" + trash
        }
        if t.notesNotFound > 0 {
            out += " \(t.notesNotFound) other \(t.notesNotFound == 1 ? "note was" : "notes were") not found, so nothing there will be touched."
        }
        return out
    }

    /// Resolves the links before the dialog is raised, so its sentence describes
    /// the filesystem rather than the record.
    private func askToDelete() {
        let ms = selectedMeetings
        deleteTargets = DeleteTargets(meetings: ms.count)
        confirmingDelete = true
        guard let folder = prefs.notesFolder() else { return }
        Task {
            var files: [String] = []
            var missing = 0
            for m in ms {
                if let u = await NoteLinkService.resolvedNoteURL(for: m, in: folder) {
                    files.append(u.lastPathComponent)
                } else {
                    missing += 1
                }
            }
            deleteTargets = DeleteTargets(meetings: ms.count, noteFiles: files, notesNotFound: missing)
        }
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
            .onDeleteCommand(perform: selected.isEmpty ? nil : { askToDelete() })

            // FR-54: an unreadable record is surfaced, never silently omitted.
            if !app.unreadableMeetings.isEmpty {
                StateBanner(kind: .degraded,
                            text: "\(app.unreadableMeetings.count) meeting \(app.unreadableMeetings.count == 1 ? "record" : "records") could not be read. They are still on disk.")
                    .padding(.horizontal, Tok.s4)
                    .padding(.bottom, Tok.s3)
            }

            unclaimedFooter

            libraryToolbar
        }
        .background(Tok.surfaceWindow)
    }

    /// FR-82. Files Minutes wrote that no Meeting claims.
    ///
    /// A footer rather than a section because it is almost always absent and never
    /// urgent — and it exists at all because a file the app wrote and then lost
    /// track of must not be invisible. That was the state the user reported, and
    /// the state in which a real meeting was lost: its note survived a rename, its
    /// record was deleted, and no surface in the product mentioned the file.
    ///
    /// They are not offered as an import. A Note cannot be parsed back into a
    /// Meeting (AD-9), and a half-Meeting with a transcript and no audio would be
    /// a second kind of record for every consumer of `Meeting` to special-case.
    @ViewBuilder
    private var unclaimedFooter: some View {
        if !app.unclaimedNotes.isEmpty {
            VStack(alignment: .leading, spacing: Tok.s3) {
                Button {
                    showingUnclaimed.toggle()
                } label: {
                    HStack(spacing: Tok.s2) {
                        Image(systemName: showingUnclaimed ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text(app.unclaimedNotes.count == 1
                             ? "1 note in your folder has no meeting"
                             : "\(app.unclaimedNotes.count) notes in your folder have no meeting")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tok.textSecondary)

                if showingUnclaimed {
                    ForEach(app.unclaimedNotes) { n in
                        UnclaimedNoteRow(note: n)
                    }
                }
            }
            .padding(.horizontal, Tok.s4)
            .padding(.bottom, Tok.s3)
        }
    }

    /// The visible home for management actions. Previously delete, retry and
    /// rename existed only in a context menu, which the user never found — so the
    /// capability was shipped and unreachable.
    private var libraryToolbar: some View {
        HStack(spacing: Tok.s3) {
            Button {
                askToDelete()
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
                   noteMissing: app.noteIsMissing(m.id))
        .padding(.vertical, 3)
        .contextMenu {
            ForEach(Self.rowActions(meeting: m,
                                    link: app.noteLink(m.id),
                                    isInFlight: app.inFlight.contains(m.id)), id: \.self) { a in
                menuItem(a, for: m)
            }
        }
    }

    /// What a row offers, as a value.
    ///
    /// A pure function, so the rule can be asserted without rendering a menu —
    /// and the rule is worth asserting, because the version of it that shipped
    /// offered `Open in Editor` whenever a *filename was recorded* rather than
    /// when a *file existed*, which handed the user macOS's own "the file does not
    /// exist" alert. The detail pane had the correct condition and a comment
    /// explaining it; this menu never got the fix. One rule, one place, one test.
    enum RowAction: Hashable {
        case reveal(URL)
        case openInEditor(URL)
        case retry
        case finish
        case locate
        case rewrite
        case useThisFile(URL)
        case revealRecording
        case divider
        case delete
    }

    static func rowActions(meeting m: Meeting,
                           link: NoteLinkState,
                           isInFlight: Bool) -> [RowAction] {
        var out: [RowAction] = []
        if let url = link.locatedURL {
            out += [.reveal(url), .openInEditor(url)]
        }
        if case .ambiguous(let urls) = link {
            out += urls.map { RowAction.useThisFile($0) }
        }
        if m.hasFailed { out.append(.retry) }
        else if !m.isComplete && !isInFlight { out.append(.finish) }
        if m.isComplete { out += [.locate, .rewrite] }
        out += [.revealRecording, .divider, .delete]
        return out
    }

    @ViewBuilder
    private func menuItem(_ a: RowAction, for m: Meeting) -> some View {
        switch a {
        case .reveal(let url):
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .openInEditor(let url):
            Button("Open in Editor") { NSWorkspace.shared.open(url) }
        case .useThisFile(let url):
            Button("Use “\(url.lastPathComponent)” as this note") {
                Task { await SessionCoordinator.shared.adoptNote(url, meetingID: m.id) }
            }
        case .retry:
            Button("Retry transcription") { Task { await SessionCoordinator.shared.retry(meetingID: m.id) } }
        case .finish:
            Button("Finish transcription") { Task { await SessionCoordinator.shared.retry(meetingID: m.id) } }
        case .locate:
            // Offered on a resolved link too: a user may want to point at a
            // different file (FR-79).
            Button("Locate note…") { Task { await SessionCoordinator.shared.locateNote(meetingID: m.id) } }
        case .rewrite:
            Button("Rewrite note") { Task { await SessionCoordinator.shared.rewriteNote(meetingID: m.id) } }
        case .revealRecording:
            // The recordings live under ~/Library, which Finder hides, so without
            // this there is no route to them from anywhere in the app.
            Button("Reveal recording in Finder") {
                Task {
                    let dir = await MeetingStore.shared.directory(for: m.id)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
            }
        case .divider:
            Divider()
        case .delete:
            Button("Delete…", role: .destructive) {
                deleteNoteToo = false
                // Right-clicking a row outside the selection acts on that row.
                if !selected.contains(m.id) { selected = [m.id] }
                askToDelete()
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
    /// Which **block** is being renamed from inside the transcript, if any.
    ///
    /// A block id, not a `SpeakerLabelID`, and that distinction was a real defect:
    /// keyed by speaker, clicking one chip presented every popover for that
    /// speaker at once — 9 of them for `In-room 4` in the user's own meeting, 173
    /// for `Speaker 2` — and SwiftUI drew the first in tree order, which is a row
    /// far above the one clicked. A block id is unique, so exactly one popover can
    /// ever be presented and it is the one you pointed at.
    ///
    /// The user asked for this directly: *"renaming should be possible within the
    /// script not just the speaker list at the top."* They are right, and the
    /// reason is that the transcript is where you *recognise* a voice — you read a
    /// line, know who said it, and the fix should be there rather than after
    /// scrolling back to a list that no longer says which one they were.
    @State private var renamingInTranscript: UUID?
    @State private var transcriptDraft = ""

    var body: some View {
        ShotScroll {
            VStack(alignment: .leading, spacing: Tok.cardGap) {
                titleBlock
                if meeting.hasFailed { failureBlock }
                // FR-87. Before the mic-only notice, because an unreliable
                // recording is worse than a missing one: its transcript reads
                // like a real conversation that never happened.
                ForEach(meeting.untrustworthyStreams, id: \.stream) { u in
                    StateBanner(kind: .degraded,
                                text: "The recording of \(u.stream) is not reliable. \(u.why) Minutes wrote no summary or title from it.")
                }
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
                // the user to an empty Finder window, so the cases are split.
                if let url = link.locatedURL {
                    Button("Reveal note") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
            // FR-80: the app shows the user's name for the file. Only when it is
            // theirs — a name the app derived carries no information the row above
            // does not already give.
            if case .linked(let url, true) = link {
                Text(url.lastPathComponent)
                    .font(Tok.monoInline).foregroundStyle(Tok.textSecondary)
                    // Middle, not tail: a filename's two informative ends are the
                    // name the user gave it and the extension. Tail truncation
                    // ate the `.md` at 320pt. Same treatment as the ambiguity
                    // list, so one filename never reads differently from another.
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .help("You named this file. Minutes will not rename it.")
            }
            noteLinkBanner
            noteConflictBanner
        }
    }

    private var link: NoteLinkState { app.noteLink(meeting.id) }

    /// FR-81. The app found something it will not decide.
    ///
    /// Here rather than at the window root because a conflict is about *this*
    /// meeting's file, and the edit that discovered it was made on this pane.
    @ViewBuilder
    private var noteConflictBanner: some View {
        if let c = app.noteConflict, c.meetingID == meeting.id {
            DecisionBanner(
                text: "“\(c.filename)” has been changed outside Minutes, so the note was not rewritten. Your edit to this meeting is saved either way.",
                safeLabel: "Keep My Version",
                safeAction: { Task { await SessionCoordinator.shared.keepNoteOnDisk() } },
                riskyLabel: "Replace With Minutes' Note",
                riskyAction: { Task { await SessionCoordinator.shared.replaceNoteWithFreshRender() } })
        }
    }

    /// The unresolved and ambiguous states. Both name what was looked for, and
    /// both distinguish the two remedies by what each does to the file on disk —
    /// offering only "Rewrite note" for a renamed Note is how a recoverable state
    /// became an unrecoverable one.
    @ViewBuilder
    private var noteLinkBanner: some View {
        switch link {
        case .notFound:
            VStack(alignment: .leading, spacing: Tok.s3) {
                StateBanner(kind: .degraded,
                            text: "Minutes looked in your notes folder and could not find this meeting's note.")
                Text("**Locate note…** points this meeting at a file that is already there — use it if you moved or renamed the note. **Rewrite note** creates a new file from the stored transcript; nothing is re-transcribed and your speaker names are kept.")
                    .font(.caption).foregroundStyle(Tok.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Tok.s3) {
                    Button("Locate note…") {
                        Task { await SessionCoordinator.shared.locateNote(meetingID: meeting.id) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("Rewrite note") {
                        Task { await SessionCoordinator.shared.rewriteNote(meetingID: meeting.id) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        case .ambiguous(let urls):
            VStack(alignment: .leading, spacing: Tok.s3) {
                StateBanner(kind: .degraded,
                            text: "\(urls.count) files in your notes folder say they belong to this meeting. Minutes will not choose between them.")
                ForEach(urls, id: \.path) { u in
                    HStack(spacing: Tok.s3) {
                        Text(u.lastPathComponent)
                            .font(Tok.monoInline)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Use this one") {
                            Task { await SessionCoordinator.shared.adoptNote(u, meetingID: meeting.id) }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        case .linked, .unknown:
            EmptyView()
        }
    }

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
                       renamingBlock: $renamingInTranscript,
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
    @Binding var renamingBlock: UUID?
    @Binding var draft: String
    let onCommit: (SpeakerLabelID, String) -> Void

    /// Compares only what is rendered. The closure is not comparable and the
    /// bindings change identity on every parent render, so both are excluded.
    ///
    /// `renamingBlock` is **also** excluded, deliberately. Including it meant one
    /// click invalidated the whole card and re-laid-out every row — 708 of them in
    /// the user's meeting, each with a `fixedSize` text forcing its own layout
    /// pass, which is why the popover was slow to appear. Exclusivity does not
    /// need the parent to re-render: each row compares its own `isRenaming`.
    static func == (a: TranscriptCard, b: TranscriptCard) -> Bool {
        a.blocks == b.blocks && a.emptyReason == b.emptyReason
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
                            TranscriptBlockRow(
                                block: b,
                                isRenaming: renamingBlock == b.id,
                                draft: $draft,
                                onBeginRename: {
                                    draft = b.name
                                    renamingBlock = b.id
                                },
                                onCancel: { renamingBlock = nil },
                                onCommit: { onCommit(b.speaker, draft) })
                        }
                    }
                }
            }
        }
    }
}

/// One paragraph of the transcript.
///
/// Its own `Equatable` view so that opening a rename popover re-renders **one**
/// row instead of every row. `isRenaming` is part of the comparison, so the two
/// rows whose state actually changed are the only two whose bodies re-run.
private struct TranscriptBlockRow: View, Equatable {
    let block: Meeting.TranscriptBlock
    let isRenaming: Bool
    @Binding var draft: String
    let onBeginRename: () -> Void
    let onCancel: () -> Void
    let onCommit: () -> Void

    static func == (a: TranscriptBlockRow, b: TranscriptBlockRow) -> Bool {
        a.block == b.block && a.isRenaming == b.isRenaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Tok.s3) {
                Text(Fmt.timestamp(block.start)).font(.caption).monospacedDigit()
                    .foregroundStyle(Tok.textSecondary)
                chip
                Spacer(minLength: 0)
            }
            // Transcript text is prose, not code — never monospaced.
            Text(block.text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The chip is the rename affordance: you recognise a voice by reading what it
    /// said, so the fix belongs on the line you recognised it from.
    ///
    /// The `.popover` modifier is attached **only while this row is the one being
    /// renamed**. Attaching it unconditionally put one popover modifier on every
    /// row — 708 of them — for a thing that can only ever be shown once.
    @ViewBuilder
    private var chip: some View {
        let button = Button(action: onBeginRename) {
            SpeakerChip(name: block.name, place: block.place,
                        isInferred: block.isInferred, basis: block.basis)
        }
        .buttonStyle(.plain)
        .help("Click to rename \(block.name) everywhere in this meeting")

        if isRenaming {
            button.popover(isPresented: Binding(get: { true },
                                                set: { if !$0 { onCancel() } }),
                           arrowEdge: .bottom) {
                renamePopover
            }
        } else {
            button
        }
    }

    /// Small, and says what the rename will do. "Every line" is the part worth
    /// stating: FR-24 renames the label, not the one line, and a user clicking a
    /// single line could reasonably expect otherwise.
    private var renamePopover: some View {
        VStack(alignment: .leading, spacing: Tok.s3) {
            Text("Rename this speaker").font(.body)
            Text("Applies to every line they spoke in this meeting, and Minutes will recognise the voice next time.")
                .font(.caption2).foregroundStyle(Tok.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(onCommit)
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button("Rename", action: onCommit)
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
        } else if !meeting.untrustworthyStreams.isEmpty {
            // FR-87, ahead of every other complete-state badge. This row's
            // transcript reads like a real conversation and is not one, so the
            // list must say so before the user opens it — the whole defect was
            // that seven of these looked exactly like the other nine.
            label("waveform.badge.exclamationmark", "Recording unreliable", stateTint(Tok.recording))
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

// MARK: - Unclaimed note row (FR-82)

/// `{components.voice-row}`'s anatomy, verbatim.
///
/// Deliberately not a new shape. It is the same kind of thing the Remembered
/// voices list holds — a short list of items the app is keeping on the user's
/// behalf, each with a name, a line of provenance and a way to remove it from the
/// list. The title is the filename the file **actually has**, because that is the
/// only name that helps the user find it in Finder.
struct UnclaimedNoteRow: View {
    let note: UnclaimedNote

    var body: some View {
        HStack(spacing: Tok.s3) {
            Image(systemName: "doc.text").foregroundStyle(Tok.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.filename)
                    .font(Tok.monoInline)
                    .lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption2).foregroundStyle(Tok.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                .buttonStyle(.bordered).controlSize(.small)
            Button {
                // Changes the listing only. Never the file — its meeting is gone,
                // and writing to an orphan to record that the app should stop
                // mentioning it would be worse than remembering it locally.
                Preferences.shared.dismissedUnclaimedNotes.append(note.filename)
                Task { await SessionCoordinator.shared.refreshLibrary() }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop listing this file. The file is not touched.")
        }
        .padding(.vertical, Tok.s2)
    }

    private var subtitle: String {
        guard let d = note.startedAt else { return "Written by Minutes; its meeting is no longer in your library." }
        return "\(d.formatted(date: .abbreviated, time: .shortened)) — its meeting is no longer in your library."
    }
}
