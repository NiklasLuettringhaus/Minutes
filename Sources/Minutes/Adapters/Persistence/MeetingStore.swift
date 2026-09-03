import Foundation

/// AD-21: the **sole writer** of `meeting.json`.
///
/// Without this, Capture writing `systemStreamCaptured`, Diarize writing
/// `diarizationSucceeded` and Metadata writing `backend` each silently drop the
/// others' fields on a read-modify-write — which would present a Mic-only
/// recording as a full one. Adapters return values; only this type persists.
///
/// AD-10: every write is atomic (temp file in destination, then atomic replace).
actor MeetingStore {
    static let shared = MeetingStore()

    private let fm = FileManager.default
    private let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Minutes/Meetings", isDirectory: true)
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    var meetingsRoot: URL { root }

    func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    /// When the record was last written, for the one caller that needs its
    /// modification time rather than its contents (AD-41's pre-digest signal).
    func recordModified(id: String) -> Date? {
        let u = directory(for: id).appendingPathComponent("meeting.json")
        return (try? fm.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
    }

    /// Creates the Meeting directory and its initial record.
    func create(id: String, startedAt: Date) throws -> Meeting {
        let dir = directory(for: id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = Meeting(id: id, startedAt: startedAt)
        try persist(m)
        Log.store.info("created meeting \(id, privacy: .public)")
        return m
    }

    func load(id: String) throws -> Meeting {
        let url = directory(for: id).appendingPathComponent("meeting.json")
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(Meeting.self, from: data)
    }

    /// All meetings, newest first. Unreadable records are skipped rather than
    /// failing the whole listing.
    func loadAll() -> [Meeting] {
        loadAllReportingFailures().0
    }

    /// The same listing, plus what it could not read. A bare `try?` here once hid a
    /// schema-compatibility bug that removed five meetings from the UI while they
    /// sat intact on disk, so an unreadable record is now logged and surfaced to
    /// `--doctor` rather than merely skipped.
    func loadAllReportingFailures() -> ([Meeting], [(id: String, reason: String)]) {
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return ([], []) }
        var out: [Meeting] = []
        var bad: [(id: String, reason: String)] = []
        for n in names.sorted() where !n.hasPrefix(".") {
            do { out.append(try load(id: n)) }
            catch {
                bad.append((n, String(describing: error)))
                Log.store.error("unreadable meeting \(n, privacy: .public)")
            }
        }
        return (out.sorted { $0.startedAt > $1.startedAt }, bad)
    }

    /// Field-level update through one serial access point (AD-21).
    /// The mutation runs against the freshest record on disk, so concurrent
    /// stages cannot clobber each other.
    @discardableResult
    func update(id: String, _ mutate: (inout Meeting) -> Void) throws -> Meeting {
        var m = try load(id: id)
        mutate(&m)
        try persist(m)
        return m
    }

    /// AD-42: to the Trash, never unlinked.
    ///
    /// `removeItem` here destroyed a real recording — a Meeting whose Note the
    /// user had renamed in Finder, deleted on a confirmation that named a file it
    /// could not find, with an empty Trash afterwards and no route back. A
    /// confirmation dialog is not a substitute for that route.
    ///
    /// A Trash failure throws. There is deliberately **no** fallback to
    /// unlinking: a volume without a Trash means the delete does not happen,
    /// because an undoable delete is the whole point.
    /// Returns where the items landed in the Trash. Not decoration: it is the
    /// only exact way to assert this went to the Trash rather than into the void —
    /// macOS renames on collision, so looking for the name afterwards is a guess —
    /// and it is what an Undo would need.
    @discardableResult
    func delete(id: String, alsoDeleteNote noteURL: URL?) throws -> [URL] {
        var landed: [URL] = []
        if let noteURL, fm.fileExists(atPath: noteURL.path) {
            if let u = try Self.trash(noteURL, describedAs: noteURL.lastPathComponent) {
                landed.append(u)
            }
        }
        if let u = try Self.trash(directory(for: id), describedAs: "The meeting") {
            landed.append(u)
        }
        Log.store.info("trashed meeting \(id, privacy: .public)")
        return landed
    }

    /// Deletes only the audio, leaving the record and Transcript (FR-44).
    ///
    /// Also to the Trash: audio is the one input that cannot be regenerated, so
    /// it is the last thing that should be unlinked.
    @discardableResult
    func deleteAudio(id: String) throws -> [URL] {
        let dir = directory(for: id)
        var landed: [URL] = []
        for kind in StreamKind.allCases {
            let u = dir.appendingPathComponent("\(kind.rawValue).wav")
            guard fm.fileExists(atPath: u.path) else { continue }
            if let t = try Self.trash(u, describedAs: "The \(kind.rawValue) recording") {
                landed.append(t)
            }
        }
        return landed
    }

    /// The single place anything the user can lose is removed (AD-42).
    ///
    /// `nonisolated static` so `MeetingStore` is not the only caller — the Note
    /// the user asked to delete alongside a Meeting travels the same path.
    @discardableResult
    nonisolated static func trash(_ url: URL, describedAs what: String) throws -> URL? {
        do {
            var landed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            return landed as URL?
        } catch {
            throw MinutesError.deleteFailed(item: what, reason: error.localizedDescription)
        }
    }

    func hasAudio(id: String) -> Bool {
        let dir = directory(for: id)
        return StreamKind.allCases.contains { fm.fileExists(atPath: dir.appendingPathComponent("\($0.rawValue).wav").path) }
    }

    func audioURL(id: String, stream: StreamKind) -> URL? {
        let u = directory(for: id).appendingPathComponent("\(stream.rawValue).wav")
        return fm.fileExists(atPath: u.path) ? u : nil
    }

    /// Total bytes used by retained audio, for the disk figure in Settings (FR-44).
    func audioBytes() -> Int64 {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e where u.pathExtension == "wav" {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Atomic persistence (AD-10)

    private func persist(_ m: Meeting) throws {
        let dir = directory(for: m.id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("meeting.json")
        let data = try Self.encoder.encode(m)
        try Self.atomicWrite(data, to: dest)
    }

    /// Temp file in the *destination directory* (so replace is same-volume), fsync, atomic replace.
    static func atomicWrite(_ data: Data, to dest: URL) throws {
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tmp, options: .atomic)
            let h = try FileHandle(forWritingTo: tmp)
            try h.synchronize()
            try h.close()
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw MinutesError.persistenceFailed(error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
