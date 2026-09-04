import Foundation
import CryptoKit

/// AD-9: renders the Note as a *projection* of the Meeting record. Never parses
/// a Note back into state.
/// AD-18: the only component that computes a Note filename. It derives one once,
/// and thereafter the stored filename is authoritative — on a title change it
/// renames the existing file rather than writing a second one. **Amended in
/// increment 7 (AD-40):** that authority holds only while the name on disk is
/// still the name this type wrote. Once the user has renamed the file, their name
/// wins and nothing here renames it.
struct NoteWriter: NoteWriting {

    /// When the Meeting's record was last written, used only by AD-41's
    /// pre-digest migration signal.
    ///
    /// Injected rather than derived from a hardcoded path, because deriving it
    /// made the migration branch unreachable under a temp-rooted store — the test
    /// would have found no record, concluded "no evidence of an edit", and passed
    /// while proving nothing. The branch that never fires in the happy path is
    /// the one that ships broken, so it has to be testable.
    var recordModifiedAt: @Sendable (String) -> Date?

    init(recordModifiedAt: @escaping @Sendable (String) -> Date? = { id in
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = support.appendingPathComponent("Minutes/Meetings/\(id)/meeting.json")
        return (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
    }) {
        self.recordModifiedAt = recordModifiedAt
    }

    func write(meeting: Meeting, into folder: URL, at located: URL?) throws -> NoteWriteOutcome {
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw MinutesError.notesFolderNotWritable(folder.path)
        }
        let wanted = baseFilename(for: meeting)

        // The destination, in order of authority: the file the Note Link resolved
        // to; then the recorded name if it is actually there; then a fresh one.
        //
        // The middle case is the fix for FR-35's amendment. It used to be first
        // and unconditional, so a recorded name whose file had been renamed away
        // became the destination of a *new* file — one Meeting, two Notes, and the
        // user's renamed copy orphaned by the only button the app offered.
        let dest: URL
        if let located {
            dest = located
        } else if let existing = meeting.noteFilename,
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent(existing).path) {
            dest = folder.appendingPathComponent(existing)
        } else {
            dest = folder.appendingPathComponent(meeting.noteFilename ?? uniqueFilename(for: meeting, in: folder))
        }

        // AD-41: refuse to overwrite bytes this app did not write.
        if let refusal = refusalIfChangedOnDisk(at: dest, meeting: meeting) {
            return .refusedChangedOnDisk(refusal)
        }

        // A title change renames the file — unless the user owns the name (AD-40).
        //
        // Judged from the name of the destination, not from the record: the
        // destination may have been resolved from the folder a moment ago, and the
        // record's copy may be a reload behind. A test caught this exact ordering —
        // resolve to the user's renamed file, write, and the app renamed it back.
        var final = dest
        let onDisk = dest.lastPathComponent
        if meeting.appOwnsNoteName(onDisk), onDisk != wanted,
           FileManager.default.fileExists(atPath: dest.path) {
            let target = uniqueFilename(for: meeting, in: folder, excluding: onDisk)
            let to = folder.appendingPathComponent(target)
            try? FileManager.default.moveItem(at: dest, to: to)
            final = to
        }

        let bytes = Data(render(meeting: meeting).utf8)
        try MeetingStore.atomicWrite(bytes, to: final)
        return .wrote(filename: final.lastPathComponent, written: wanted, digest: Self.digest(bytes))
    }

    /// AD-41. Nil means writing is safe.
    ///
    /// Three cases, and the third is the migration. A record with a digest is
    /// compared against it. A record without one — every Note written before
    /// increment 7 — is judged by modification time instead: not later than the
    /// record's own last write means the app wrote it and the bytes are adopted as
    /// the baseline; later means something else touched it and the user is asked.
    /// That is a weaker signal than a digest and cannot see an edit that preserved
    /// the timestamp, which is recorded in AD-41 rather than hidden here. Measured
    /// on the fifteen real Notes: none is modified after its record, so all
    /// fifteen adopt cleanly.
    func refusalIfChangedOnDisk(at dest: URL, meeting: Meeting) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dest.path),
              let data = try? Data(contentsOf: dest) else { return nil }

        if let known = meeting.noteDigest {
            return Self.digest(data) == known ? nil : dest
        }
        return changedAfterItsRecord(dest, meeting: meeting) ? dest : nil
    }

    /// The pre-digest signal. Kept separate so it is testable on its own, and so
    /// the day it can be deleted is obvious: when no record lacks a digest.
    func changedAfterItsRecord(_ note: URL, meeting: Meeting) -> Bool {
        guard let noteAt = (try? FileManager.default
                .attributesOfItem(atPath: note.path)[.modificationDate]) as? Date,
              let recAt = recordModifiedAt(meeting.id)
        else { return false }   // No evidence of an edit is not evidence of one.
        return noteAt.timeIntervalSince(recAt) > 1
    }

    /// SHA-256 of the exact bytes written. In the adapter, not in Core, which
    /// `CorePurityTests` pins to Foundation alone.
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Filename

    private func baseFilename(for m: Meeting) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        let title = m.metadata?.title ?? "Meeting"
        return "\(f.string(from: m.startedAt)) \(Self.slug(title)).md"
    }

    private func uniqueFilename(for m: Meeting, in folder: URL, excluding: String? = nil) -> String {
        let base = baseFilename(for: m)
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path),
              candidate != excluding {
            let stem = base.replacingOccurrences(of: ".md", with: "")
            candidate = "\(stem) (\(n)).md"
            n += 1
            if n > 99 { break }
        }
        return candidate
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let cleaned = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let words = String(cleaned).split(separator: " ").map(String.init)
        let joined = words.joined(separator: "-")
        return joined.isEmpty ? "meeting" : String(joined.prefix(60))
    }

    // MARK: - Render

    func render(meeting m: Meeting) -> String {
        var out = frontmatter(m)
        out += "\n"

        if let md = m.metadata {
            if !md.summary.isEmpty {
                out += "## Summary\n\n\(md.summary)\n\n"
            }
            // Empty sections are omitted rather than left as empty headings (FR-33).
            if !md.decisions.isEmpty {
                out += "## Decisions\n\n"
                for d in md.decisions {
                    let ts = d.at.map { " *(\(Fmt.timestamp($0)))*" } ?? ""
                    out += "- \(d.text)\(ts)\n"
                }
                out += "\n"
            }
            if !md.actionItems.isEmpty {
                out += "## Action items\n\n"
                for a in md.actionItems {
                    let who = a.owner.map { "**\($0)** — " } ?? ""
                    let ts = a.at.map { " *(\(Fmt.timestamp($0)))*" } ?? ""
                    out += "- \(who)\(a.text)\(ts)\n"
                }
                out += "\n"
            }
        }

        // FR-87, first among the degradation notices because it is the only one
        // that makes the transcript below actively misleading rather than
        // incomplete.
        for (stream, why) in m.untrustworthyStreams {
            out += "> **The recording of \(stream) is not reliable.** \(why) "
            out += "The transcript below is what the transcription produced from it, kept because the audio is yours, but it does not reflect what was said. "
            out += "No summary, title or tags were generated from it.\n\n"
        }
        if !m.systemStreamCaptured {
            out += "> Only the microphone was captured for this meeting, so remote participants do not appear in the transcript.\n\n"
        }
        // FR-96. Before the echo notice, in the order EXPERIENCE.md fixes:
        // worst misleading first. A summary built on a transcript with holes in
        // it is incomplete, and a reader who is not told reads it as complete.
        if let why = TranscriptGaps.explanation(m.gaps) {
            out += "> \(why)\n\n"
        }
        // FR-92. The Note carries what the app knows, because a reader months
        // later has only this file — and a transcript with the far end counted
        // once reads differently from one where it was counted twice.
        if let why = m.echo?.explanation {
            out += "> \(why)\n\n"
        }
        if m.multipleInRoom {
            if m.localIdentifiedByEnrolment {
                // Says which voice was identified and how, so the Note carries the
                // same disclosure the app does (FR-65). A reader months later has
                // only this file.
                out += "> More than one person was speaking in the room. Your own voice was recognised from the sample you recorded; the other in-room voices are labelled but not identified. Rename them once and Minutes will recognise them next time.\n\n"
            } else {
                out += "> More than one person was speaking in the room, so the in-room voices are labelled but not identified. Rename them once and Minutes will recognise them next time.\n\n"
            }
        }

        out += speakerIndex(m)

        out += "## Transcript\n\n"
        out += renderTranscript(m)
        return out
    }

    /// The index at the top: who spoke, and what they were heard through.
    ///
    /// Worth its space because the two Streams are the product's core structural
    /// claim — microphone means the room, system audio means the far end — and until
    /// now that claim was implicit in labels like "In-room 1" without ever naming the
    /// hardware. On the first real meeting the input device turned out to be AirPods
    /// rather than the built-in mic, which changes how every other row should be
    /// read, and the Note recorded nothing about it.
    func speakerIndex(_ m: Meeting) -> String {
        let speakers = m.speakers
        guard !speakers.isEmpty else { return "" }

        var out = "## Speakers\n\n"
        out += "| Speaker | Lines | Heard through |\n| --- | --- | --- |\n"
        for s in speakers {
            var name = m.displayName(for: s)
            if m.isInferred(s) { name += " *(recognised)*" }
            if m.isExcluded(s) { name += " *(excluded below)*" }
            let lines = m.utterances.filter { $0.speaker == s }.count
            out += "| \(name) | \(lines) | \(m.heardThrough(s)) |\n"
        }
        out += "\n"

        let excluded = speakers.filter { m.isExcluded($0) }
        if !excluded.isEmpty {
            let names = excluded.map { m.displayName(for: $0) }
            let who = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
            // Stated rather than silently dropped: a Note that quietly omits speech
            // is less trustworthy than one that says what it left out.
            out += "> \(who) \(names.count == 1 ? "was" : "were") excluded from the transcript below. "
            out += "The speech is still in Minutes and can be restored.\n\n"
        }
        return out
    }

    /// Groups consecutive Utterances from one Speaker under a single label, so a
    /// speaker's continuous speech is not fragmented line by line (FR-33).
    func renderTranscript(_ m: Meeting) -> String {
        // One grouping rule for the app and the Note (`Meeting.transcriptBlocks`).
        // These were two implementations of the same paragraph-building logic, and
        // both had the same defect: they grouped on the *display name*, so two
        // different unnamed in-room voices — both falling back to "In-room
        // speaker" — were run together under one name. In the Note that is worse
        // than on screen, because the Note is what gets read in six months.
        let blocks = m.transcriptBlocks(honouringExclusions: true)
        guard !blocks.isEmpty else {
            return m.utterances.isEmpty
                ? "*No speech was transcribed.*\n"
                : "*Every speaker in this meeting has been excluded.*\n"
        }
        var out = ""
        for b in blocks {
            let who = b.isInferred ? "~\(b.name)" : b.name
            out += "**\(Fmt.timestamp(b.start)) \(who)**\n\n\(b.text)\n\n"
        }
        return out
    }
    private func frontmatter(_ m: Meeting) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"

        var lines = ["---"]
        lines.append("title: \(Self.yamlScalar(m.metadata?.title ?? "Meeting"))")
        // FR-77: the file says which Meeting it is, so a rename cannot sever the
        // link. Written first among the machine-readable fields because it is the
        // only one the app reads back (AD-39), and reading it is not reading the
        // Note's content (AD-9 as amended).
        lines.append("\(NoteIdentity.Key.meetingID): \(m.id)")
        lines.append("date: \(df.string(from: m.startedAt))")
        lines.append("start: \(tf.string(from: m.startedAt))")
        lines.append("duration: \(Self.yamlScalar(Fmt.duration(m.duration)))")
        lines.append("started_at: \(iso.string(from: m.startedAt))")

        func names(_ ids: [SpeakerLabelID]) -> [String] {
            ids.map { m.isInferred($0) ? "~\(m.displayName(for: $0))" : m.displayName(for: $0) }
        }
        let all = names(m.speakers)
        lines.append("participants: [\(all.map(Self.yamlScalar).joined(separator: ", "))]")
        // Where a voice was is structural; who it is may be an inference. Recording
        // the split lets a reader trust the first part even when unsure of the second.
        let room = names(m.inRoomSpeakers), remote = names(m.remoteSpeakers)
        if !room.isEmpty {
            lines.append("in_room: [\(room.map(Self.yamlScalar).joined(separator: ", "))]")
        }
        if !remote.isEmpty {
            lines.append("remote: [\(remote.map(Self.yamlScalar).joined(separator: ", "))]")
        }

        let tags = m.metadata?.tags ?? []
        lines.append("tags: [\(tags.map(Self.yamlScalar).joined(separator: ", "))]")

        lines.append("transcription_model: \(Self.yamlScalar(m.transcriptionModel ?? "unknown"))")
        // Provenance: a reader can always tell an LLM summary from keyphrase extraction (FR-30).
        lines.append("metadata_backend: \(Self.yamlScalar(m.metadata?.backend.rawValue ?? "none"))")
        lines.append("system_audio_captured: \(m.systemStreamCaptured)")
        // Emitted only when a check actually failed, so a Note never carries a
        // field implying a problem the recording did not have.
        if !m.untrustworthyStreams.isEmpty {
            let names = m.untrustworthyStreams.map { $0.stream }
            lines.append("unreliable_streams: [\(names.map(Self.yamlScalar).joined(separator: ", "))]")
            if let r = m.systemRate, !r.isTrustworthy {
                lines.append(String(format: "system_declared_hz: %.0f", r.declaredRate))
                lines.append(String(format: "system_observed_hz: %.0f", r.observedRate))
            }
            if let r = m.micRate, !r.isTrustworthy {
                lines.append(String(format: "mic_declared_hz: %.0f", r.declaredRate))
                lines.append(String(format: "mic_observed_hz: %.0f", r.observedRate))
            }
        }
        lines.append("speakers_separated: \(m.diarizationSucceeded)")
        lines.append("multiple_people_in_room: \(m.multipleInRoom)")
        // Provenance for the identity claim, not just for the summary (FR-30, FR-65).
        // Emitted only when the claim was made, so a Note never carries a field
        // implying a feature the recording did not use.
        if m.localIdentifiedByEnrolment {
            lines.append("you_identified_by: enrolled_voice")
            if let d = m.localMatchDistance {
                lines.append(String(format: "you_match_distance: %.3f", d))
            }
        }
        if let app = m.triggeringApp {
            lines.append("detected_from: \(Self.yamlScalar(app))")
        }
        lines.append("generated_by: Minutes (local, on-device)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quote and escape so a title containing a colon or a quote cannot break the
    /// YAML (FR-32).
    static func yamlScalar(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
