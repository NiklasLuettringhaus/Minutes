import SwiftUI
import AppKit

/// FR-36 … FR-40. A utility view over the Notes, not a second home for the data —
/// the Meeting record is the source of truth and the Note is a projection (AD-9).
struct MeetingsPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var selected: String?
    @State private var deleting: Meeting?
    @State private var deleteNoteToo = false

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 380)
            if let id = selected, let m = app.meeting(id: id) {
                MeetingDetail(meeting: m)
            } else {
                VStack {
                    Spacer()
                    Text(app.meetings.isEmpty
                         ? "No meetings yet. Click the menu bar icon to record one."
                         : "Select a meeting.")
                        .font(.body).foregroundStyle(Tok.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Tok.surfaceWindow)
            }
        }
        .onAppear { Task { await AppStateBridge.reloadMeetings() } }
        .alert("Delete this meeting?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let m = deleting {
                    Task { await SessionCoordinator.shared.delete(meetingID: m.id, alsoNote: deleteNoteToo) }
                }
                deleting = nil
            }
        } message: {
            // Enumerates exactly what will be removed before removing it (FR-40).
            if let m = deleting {
                Text(deleteNoteToo
                     ? "The recording, the transcript and the Markdown note “\(m.noteFilename ?? "")” will be permanently deleted."
                     : "The recording and transcript will be permanently deleted. The Markdown note will be left in your notes folder.")
            }
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
        }
        .background(Tok.surfaceWindow)
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
            } else if !m.isComplete {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                    Text(m.stage.displayName).font(.caption2).foregroundStyle(Tok.transcribing)
                }
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
            if m.hasFailed {
                Button("Retry transcription") {
                    Task { await SessionCoordinator.shared.retry(meetingID: m.id) }
                }
            }
            Divider()
            Button("Delete…", role: .destructive) { deleteNoteToo = false; deleting = m }
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
    @EnvironmentObject var prefs: Preferences
    @State private var editingSpeaker: SpeakerLabelID?
    @State private var draftName = ""
    @State private var editingTitle = false
    @State private var draftTitle = ""

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
                if let f = meeting.noteFilename, let folder = prefs.notesFolder() {
                    Button("Reveal note") {
                        NSWorkspace.shared.selectFile(folder.appendingPathComponent(f).path,
                                                      inFileViewerRootedAtPath: folder.path)
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
            }
        }
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
                                            isInferred: meeting.isInferred(s))
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
                                Spacer()
                                Text("\(count(of: s)) lines").font(.caption).monospacedDigit()
                                    .foregroundStyle(Tok.textSecondary)
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

    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Transcript")
            Card {
                if meeting.utterances.isEmpty {
                    Text("No speech was transcribed.").font(.caption)
                        .foregroundStyle(Tok.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: Tok.s4) {
                        ForEach(blocks(), id: \.id) { b in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Tok.s3) {
                                    Text(Fmt.timestamp(b.start)).font(.caption).monospacedDigit()
                                        .foregroundStyle(Tok.textSecondary)
                                    SpeakerChip(name: b.name, place: b.place, isInferred: b.isInferred)
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
                }
                Text("Everything above was produced on this Mac.")
                    .font(.caption2).foregroundStyle(Tok.textSecondary)
            }
        }
    }

    // MARK: - Helpers

    struct Block: Identifiable {
        let id = UUID()
        var start: TimeInterval
        var name: String
        var place: SpeakerLabelID.Place
        var isInferred: Bool
        var text: String
    }

    /// Groups consecutive Utterances from one Speaker under a single label (FR-33).
    private func blocks() -> [Block] {
        var out: [Block] = []
        for u in meeting.utterances.sorted(by: { $0.start < $1.start }) {
            let name = meeting.displayName(for: u.speaker)
            if var last = out.last, last.name == name {
                last.text += " " + u.text.trimmingCharacters(in: .whitespaces)
                out[out.count - 1] = last
            } else {
                out.append(Block(start: u.start, name: name, place: u.speaker.place,
                                 isInferred: meeting.isInferred(u.speaker),
                                 text: u.text.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
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
