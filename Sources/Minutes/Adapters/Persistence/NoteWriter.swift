import Foundation

/// AD-9: renders the Note as a *projection* of the Meeting record. Never parses
/// a Note back into state.
/// AD-18: the only component that computes a Note filename. It derives one once,
/// and thereafter the stored filename is authoritative — on a title change it
/// renames the existing file rather than writing a second one.
struct NoteWriter: NoteWriting {

    func write(meeting: Meeting, into folder: URL) throws -> String {
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw MinutesError.notesFolderNotWritable(folder.path)
        }
        let filename = meeting.noteFilename ?? uniqueFilename(for: meeting, in: folder)
        let dest = folder.appendingPathComponent(filename)

        // A stored filename that no longer matches the title means the title changed:
        // rename in place so one Meeting never yields two Notes (AD-18).
        if let existing = meeting.noteFilename {
            let wanted = baseFilename(for: meeting)
            if existing != wanted, FileManager.default.fileExists(atPath: folder.appendingPathComponent(existing).path) {
                let target = uniqueFilename(for: meeting, in: folder, excluding: existing)
                let from = folder.appendingPathComponent(existing)
                let to = folder.appendingPathComponent(target)
                try? FileManager.default.moveItem(at: from, to: to)
                let data = Data(render(meeting: meeting).utf8)
                try MeetingStore.atomicWrite(data, to: to)
                return target
            }
        }

        let data = Data(render(meeting: meeting).utf8)
        try MeetingStore.atomicWrite(data, to: dest)
        return filename
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

        if !m.systemStreamCaptured {
            out += "> Only the microphone was captured for this meeting, so remote participants do not appear in the transcript.\n\n"
        }
        if m.multipleInRoom {
            out += "> More than one person was speaking in the room, so the in-room voices are labelled but not identified. Rename them once and Minutes will recognise them next time.\n\n"
        }

        out += "## Transcript\n\n"
        out += renderTranscript(m)
        return out
    }

    /// Groups consecutive Utterances from one Speaker under a single label, so a
    /// speaker's continuous speech is not fragmented line by line (FR-33).
    func renderTranscript(_ m: Meeting) -> String {
        guard !m.utterances.isEmpty else {
            return "*No speech was transcribed.*\n"
        }
        var out = ""
        var currentSpeaker: String? = nil
        var buffer: [String] = []
        var blockStart: TimeInterval = 0

        func flush() {
            guard let who = currentSpeaker, !buffer.isEmpty else { return }
            out += "**\(Fmt.timestamp(blockStart)) \(who)**\n\n\(buffer.joined(separator: " "))\n\n"
            buffer = []
        }

        for u in m.utterances.sorted(by: { $0.start < $1.start }) {
            var name = m.displayName(for: u.speaker)
            if m.isInferred(u.speaker) { name = "~\(name)" }
            if name != currentSpeaker {
                flush()
                currentSpeaker = name
                blockStart = u.start
            }
            buffer.append(u.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        flush()
        return out
    }

    private func frontmatter(_ m: Meeting) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"

        var lines = ["---"]
        lines.append("title: \(Self.yamlScalar(m.metadata?.title ?? "Meeting"))")
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
        lines.append("speakers_separated: \(m.diarizationSucceeded)")
        lines.append("multiple_people_in_room: \(m.multipleInRoom)")
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
