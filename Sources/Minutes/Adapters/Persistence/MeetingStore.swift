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
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var out: [Meeting] = []
        for n in names where !n.hasPrefix(".") {
            if let m = try? load(id: n) { out.append(m) }
        }
        return out.sorted { $0.startedAt > $1.startedAt }
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

    func delete(id: String, alsoDeleteNote noteURL: URL?) throws {
        if let noteURL { try? fm.removeItem(at: noteURL) }
        try fm.removeItem(at: directory(for: id))
        Log.store.info("deleted meeting \(id, privacy: .public)")
    }

    /// Deletes only the audio, leaving the record and Transcript (FR-44).
    func deleteAudio(id: String) throws {
        let dir = directory(for: id)
        for kind in StreamKind.allCases {
            try? fm.removeItem(at: dir.appendingPathComponent("\(kind.rawValue).wav"))
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
