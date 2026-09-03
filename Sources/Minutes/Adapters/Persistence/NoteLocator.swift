import Foundation

/// AD-39: finds a Meeting's Note by identity rather than by path.
///
/// It is deliberately inert. It creates nothing, renames nothing, moves nothing
/// and deletes nothing — the only thing a resolution may change is which existing
/// file a record points at. `NoteLocatorTests` asserts that by capturing every
/// file's name, size and modification date either side of a resolution.
///
/// AD-43: only files carrying a Minutes identity marker are considered. A Markdown
/// file the user wrote themselves is not listed, not claimed and not touched.
struct NoteLocator: NoteLocating {

    private let fm = FileManager.default

    func locate(meeting: Meeting, in folder: URL) throws -> NoteLocation {
        let hits = try candidates(in: folder).filter { $0.identity.matches(meeting) }
        switch hits.count {
        case 0: return .notFound
        case 1: return .located(hits[0].url)
        default:
            // Sorted so the presented order is stable across calls; the user is
            // about to choose between these and a list that reshuffles is worse
            // than one that is arbitrary but fixed.
            return .ambiguous(hits.map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
    }

    func unclaimed(meetings: [Meeting], in folder: URL) throws -> [UnclaimedNote] {
        let all = try candidates(in: folder)
        return all
            .filter { c in !meetings.contains { c.identity.matches($0) } }
            .map { UnclaimedNote(url: $0.url, startedAt: $0.identity.startedAt) }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    // MARK: - Scanning

    private struct Candidate {
        let url: URL
        let identity: NoteIdentity
    }

    /// Every Markdown file in the folder that Minutes wrote, with its identity.
    ///
    /// One level of subdirectory, because "I moved it" often means "I moved it into
    /// a folder", and a bounded depth is the difference between a fix and a
    /// filesystem crawl. Deeper than that is what FR-79's explicit chooser is for.
    private func candidates(in folder: URL) throws -> [Candidate] {
        var out: [Candidate] = []
        for url in try markdownFiles(in: folder, depth: 1) {
            guard let head = try? head(of: url),
                  let identity = NoteIdentity.parse(frontmatterOf: head),
                  identity.isMinutesNote else { continue }
            out.append(Candidate(url: url, identity: identity))
        }
        return out
    }

    private func markdownFiles(in folder: URL, depth: Int) throws -> [URL] {
        let entries = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var out: [URL] = []
        for e in entries {
            let isDir = (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                guard depth > 0 else { continue }
                out += (try? markdownFiles(in: e, depth: depth - 1)) ?? []
            } else if e.pathExtension.lowercased() == "md" {
                out.append(e)
            }
        }
        return out
    }

    /// A bounded read. Reading four hundred whole files to find one is the cost
    /// this avoids, and one real Note is already 72 KB.
    private func head(of url: URL) throws -> String? {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        guard let data = try h.read(upToCount: NoteIdentity.headBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
