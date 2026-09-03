import XCTest
@testable import Minutes

/// AD-39 / AD-43 / FR-78 — finding a Note that moved, and touching nothing while
/// doing it.
final class NoteLocatorTests: XCTestCase {

    private var folder: URL!
    private let locator = NoteLocator()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func meeting(_ id: String = "20260903-093038-zzzz",
                         at iso: String = "2026-09-03T07:30:38Z") -> Meeting {
        var m = Meeting(id: id, startedAt: ISO8601DateFormatter().date(from: iso)!)
        m.stage = .written
        return m
    }

    private func writeNote(_ name: String, id: String?, startedAt: String?, minutes: Bool = true,
                           into dir: URL? = nil) throws {
        var head = "---\ntitle: \"Anything\"\n"
        if let id { head += "minutes_id: \(id)\n" }
        if let startedAt { head += "started_at: \(startedAt)\n" }
        if minutes { head += "generated_by: Minutes (local, on-device)\n" }
        head += "---\n\n## Transcript\n\nWords.\n"
        try Data(head.utf8).write(to: (dir ?? folder).appendingPathComponent(name))
    }

    // MARK: - The three answers

    func testFindsARenamedFile() throws {
        try writeNote("whatever the user called it.md", id: "20260903-093038-zzzz",
                      startedAt: "2026-09-03T07:30:38Z")
        guard case .located(let url) = try locator.locate(meeting: meeting(), in: folder) else {
            return XCTFail("a renamed note must be found")
        }
        XCTAssertEqual(url.lastPathComponent, "whatever the user called it.md")
    }

    func testFindsAPreStampNoteByItsStartTime() throws {
        try writeNote("renamed legacy.md", id: nil, startedAt: "2026-09-03T07:30:38Z")
        guard case .located = try locator.locate(meeting: meeting(), in: folder) else {
            return XCTFail("the fifteen notes that predate the stamp must still be findable")
        }
    }

    /// Never guessed. Picking one means the next rewrite destroys the other.
    func testTwoClaimantsAreReportedNotChosen() throws {
        try writeNote("a.md", id: "20260903-093038-zzzz", startedAt: "2026-09-03T07:30:38Z")
        try writeNote("b.md", id: "20260903-093038-zzzz", startedAt: "2026-09-03T07:30:38Z")
        guard case .ambiguous(let urls) = try locator.locate(meeting: meeting(), in: folder) else {
            return XCTFail("two claimants is an ambiguity, not a choice")
        }
        XCTAssertEqual(urls.map(\.lastPathComponent), ["a.md", "b.md"], "stable order")
    }

    func testAnEmptyFolderIsNotFoundRatherThanAnError() throws {
        XCTAssertEqual(try locator.locate(meeting: meeting(), in: folder), .notFound)
    }

    // MARK: - AD-43: only our own files

    func testAMarkdownFileMinutesDidNotWriteIsInvisible() throws {
        let theirs = "---\ntitle: My shopping list\n---\n\n- milk\n"
        try Data(theirs.utf8).write(to: folder.appendingPathComponent("shopping.md"))
        try Data("# Not even frontmatter\n".utf8)
            .write(to: folder.appendingPathComponent("readme.md"))

        XCTAssertEqual(try locator.locate(meeting: meeting(), in: folder), .notFound)
        XCTAssertTrue(try locator.unclaimed(meetings: [], in: folder).isEmpty,
                      "the user's own documents are not the app's to enumerate")
    }

    // MARK: - Inertness (AD-39)

    /// The rule is that resolution creates, renames, moves and deletes nothing.
    /// This is the assertion that pins it: every name, size and modification date,
    /// either side of a resolution.
    func testResolvingChangesNothingOnDisk() throws {
        try writeNote("one.md", id: "20260903-093038-zzzz", startedAt: "2026-09-03T07:30:38Z")
        try writeNote("two.md", id: "20260901-000000-aaaa", startedAt: "2026-09-01T00:00:00Z")
        let theirs = "---\ntitle: mine\n---\n"
        try Data(theirs.utf8).write(to: folder.appendingPathComponent("theirs.md"))

        let before = try snapshot()
        _ = try locator.locate(meeting: meeting(), in: folder)
        _ = try locator.unclaimed(meetings: [meeting()], in: folder)
        let after = try snapshot()

        XCTAssertEqual(before, after, "a resolution must not touch the user's folder")
    }

    private func snapshot() throws -> [String] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(atPath: folder.path).sorted().map { name in
            let a = try fm.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            let size = (a[.size] as? Int) ?? -1
            let at = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            return "\(name)|\(size)|\(at)"
        }
    }

    // MARK: - Depth

    /// "I moved it" often means "I moved it into a folder". One level, because a
    /// bounded depth is the difference between a fix and a filesystem crawl.
    func testSearchesOneLevelOfSubdirectoryAndNoDeeper() throws {
        let one = folder.appendingPathComponent("Archive", isDirectory: true)
        let two = one.appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)

        try writeNote("moved.md", id: "20260903-093038-zzzz",
                      startedAt: "2026-09-03T07:30:38Z", into: one)
        guard case .located(let url) = try locator.locate(meeting: meeting(), in: folder) else {
            return XCTFail("a note moved into a subfolder must still be found")
        }
        XCTAssertEqual(url.lastPathComponent, "moved.md")

        try FileManager.default.removeItem(at: url)
        try writeNote("deeper.md", id: "20260903-093038-zzzz",
                      startedAt: "2026-09-03T07:30:38Z", into: two)
        XCTAssertEqual(try locator.locate(meeting: meeting(), in: folder), .notFound,
                       "two levels down is what the explicit chooser is for")
    }

    // MARK: - Unclaimed (FR-82)

    func testAFileWhoseMeetingIsGoneIsReportedAsUnclaimed() throws {
        try writeNote("survivor.md", id: "20260903-093038-zzzz",
                      startedAt: "2026-09-03T07:30:38Z")
        try writeNote("still-linked.md", id: "20260901-000000-aaaa",
                      startedAt: "2026-09-01T00:00:00Z")

        let alive = meeting("20260901-000000-aaaa", at: "2026-09-01T00:00:00Z")
        let orphans = try locator.unclaimed(meetings: [alive], in: folder)
        XCTAssertEqual(orphans.map(\.filename), ["survivor.md"])
        XCTAssertNotNil(orphans.first?.startedAt, "its own frontmatter is all there is left")
    }

    /// A bounded read, so a folder of large notes does not have to be read whole.
    /// One real note is 72 KB; four hundred of those is the cost this avoids.
    func testReadsOnlyTheHeadOfALargeFile() throws {
        var body = "---\nminutes_id: 20260903-093038-zzzz\ngenerated_by: Minutes\n---\n"
        body += String(repeating: "Long transcript line.\n", count: 20_000)
        let url = folder.appendingPathComponent("huge.md")
        try Data(body.utf8).write(to: url)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 400_000)

        guard case .located = try locator.locate(meeting: meeting(), in: folder) else {
            return XCTFail("a large note is still identifiable from its head")
        }
    }
}
