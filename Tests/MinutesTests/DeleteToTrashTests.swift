import XCTest
@testable import Minutes

/// AD-42 / FR-40 as amended — deleting a Meeting is recoverable.
///
/// Not a precaution. `removeItem` on a Meeting directory destroyed a real
/// recording on 3 September 2026: a note the user had renamed in Finder, a
/// confirmation that named a file it could not find, and an empty Trash
/// afterwards with no route back.
final class DeleteToTrashTests: XCTestCase {

    private var root: URL!
    private var store: MeetingStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-\(UUID().uuidString)", isDirectory: true)
        store = MeetingStore(root: root)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testDeletingAMeetingPutsItInTheTrashIntact() async throws {
        _ = try await store.create(id: "m1", startedAt: Date())
        let dir = await store.directory(for: "m1")
        try Data(repeating: 7, count: 2048).write(to: dir.appendingPathComponent("mic.wav"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        // `trashItem` reports where it put things, which is what makes this an
        // assertion rather than a guess — macOS renames on collision, so looking
        // the name up in the Trash afterwards proves nothing.
        let landed = try await store.delete(id: "m1", alsoDeleteNote: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "the meeting must leave the library")
        let trashed = try XCTUnwrap(landed.first, "it must be in the Trash, not unlinked")
        addTeardownBlock { try? FileManager.default.removeItem(at: trashed) }

        XCTAssertEqual(try Data(contentsOf: trashed.appendingPathComponent("mic.wav")).count, 2048,
                       "the audio must come back byte-for-byte")
        XCTAssertNoThrow(try Data(contentsOf: trashed.appendingPathComponent("meeting.json")),
                         "and so must the record")
    }

    func testDeletingTheNoteAlongsideItAlsoGoesToTheTrash() async throws {
        _ = try await store.create(id: "m2", startedAt: Date())
        let folder = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appendingPathComponent("a note the user wrote in.md")
        try Data("# a note\n".utf8).write(to: note)

        let landed = try await store.delete(id: "m2", alsoDeleteNote: note)
        for u in landed { addTeardownBlock { try? FileManager.default.removeItem(at: u) } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
        XCTAssertEqual(landed.count, 2, "the note and the meeting both go to the Trash")
        let trashedNote = try XCTUnwrap(landed.first { $0.pathExtension == "md" })
        XCTAssertEqual(try String(contentsOf: trashedNote, encoding: .utf8), "# a note\n",
                       "the user's note must come back intact")
    }

    /// Deleting only the audio (FR-44) is the same rule: audio is the one input
    /// that cannot be regenerated, so it is the last thing to unlink.
    func testDeletingAudioGoesToTheTrashAndKeepsTheTranscript() async throws {
        _ = try await store.create(id: "m3", startedAt: Date())
        let dir = await store.directory(for: "m3")
        try Data(repeating: 3, count: 512).write(to: dir.appendingPathComponent("mic.wav"))

        let landed = try await store.deleteAudio(id: "m3")
        for u in landed { addTeardownBlock { try? FileManager.default.removeItem(at: u) } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mic.wav").path))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(landed.first)).count, 512)
        XCTAssertNoThrow(try Data(contentsOf: dir.appendingPathComponent("meeting.json")),
                         "FR-44 removes audio, not the transcript")
    }

    /// A missing note is not an error, and must not stop the Meeting being deleted.
    func testAnAbsentNoteDoesNotBlockTheDelete() async throws {
        _ = try await store.create(id: "m4", startedAt: Date())
        let ghost = root.appendingPathComponent("not-there.md")
        let dir = await store.directory(for: "m4")

        let landed = try await store.delete(id: "m4", alsoDeleteNote: ghost)
        for u in landed { addTeardownBlock { try? FileManager.default.removeItem(at: u) } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "an absent note must not stop the meeting being deleted")
        XCTAssertEqual(landed.count, 1, "only the meeting; there was no note to trash")
    }

}

/// The allowlist. AD-42 is one line of code away from being undone by a tidy-up,
/// so the call sites are enumerated with their reasons and a new one fails here.
///
/// Same shape and same purpose as `CorePurityTests`: a rule that only lives in a
/// comment is a rule the next person removes in good faith.
final class UnlinkAllowlistTests: XCTestCase {

    /// Every file permitted to call `removeItem`, and why. Two of these are
    /// **required** to use it rather than merely permitted — trashing a recording
    /// of the user's voice would leave that recording on disk, which is exactly
    /// what AD-32 destroys it to prevent.
    private let allowed: [String: String] = [
        "MeetingStore.swift": "the staged temp file inside atomicWrite (AD-10)",
        "VoiceEnrolment.swift": "REQUIRED: AD-32 destroys the enrolment sample. The Trash would keep it.",
        "TestPlayground.swift": "REQUIRED: the same, for the Playground's throwaway recordings.",
        "ParakeetTranscriber.swift": "a downloaded model directory — re-downloadable, and trashing 1.5 GB doubles the disk the user was reclaiming",
        "ModelCatalog.swift": "the same, for a model file",
        "ModelStorage.swift": "one-time cleanup of a legacy migration path",
        "LoginItem.swift": "the launch agent plist — app configuration, not user data",
        "EchoDetector.swift": "the derived Echo-muted copy of the Mic Stream, in Caches. The recording itself is never touched (AD-49) and this copy is recomputable from it plus the stored intervals.",
        "Pipeline.swift": "the same derived copy, deleted when Diarization is done. Trashing it would put a near-100 MB duplicate of a meeting in the user's Trash for no reason.",
    ]

    func testNoNewUnlinkOfAnythingTheUserCanLose() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Minutes", isDirectory: true)

        var offenders: [String] = []
        let e = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in e where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            let calls = src.split(separator: "\n").filter { line in
                line.contains("removeItem") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("///")
                    && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            }
            guard !calls.isEmpty else { continue }
            let name = url.lastPathComponent
            if allowed[name] == nil {
                offenders.append("\(name): \(calls.count) call(s)")
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            removeItem appeared in a file that is not on AD-42's allowlist: \(offenders).
            Anything the user can lose goes to the Trash — `MeetingStore.trash`. If this
            call really is a temporary or staged file, add it to the allowlist above
            with the reason, so the next reader knows it was considered.
            """)
    }

    /// The other direction: the allowlist must not rot into a list of files that no
    /// longer call it, which would hide a real regression behind a stale entry.
    func testTheAllowlistHasNoStaleEntries() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Minutes", isDirectory: true)

        var present: Set<String> = []
        let e = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in e where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            if src.split(separator: "\n").contains(where: {
                $0.contains("removeItem") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            }) {
                present.insert(url.lastPathComponent)
            }
        }
        let stale = Set(allowed.keys).subtracting(present)
        XCTAssertTrue(stale.isEmpty, "allowlist entries with no such call any more: \(stale)")
    }
}
