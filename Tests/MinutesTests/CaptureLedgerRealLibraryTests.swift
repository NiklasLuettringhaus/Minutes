import XCTest
@testable import Minutes

/// FR-102, AD-57 against the author's real library, read-only.
///
/// **This exists because `--doctor` cannot answer it here.** The question is
/// whether adding five fields to `Meeting` broke the decoding of records written
/// before they existed — the failure mode increment 10's review found in
/// `EchoAnalysis`, which had shipped with the synthesised decoder and was one
/// field away from throwing `keyNotFound` on every meeting recorded since.
/// `--doctor` is the usual instrument for it and needs the installed app bundle,
/// and installing a new ad-hoc-signed build **revokes microphone and
/// system-audio consent** — which, on a day with back-to-back meetings, risks
/// losing one. So the check is taken here instead, where it costs nothing.
///
/// Gated behind an environment variable for the same reason as
/// `NoteIdentityRealNotesTests` and `EnrolmentCalibrationTests`: it depends on
/// data that exists on one machine and must never fail a clean checkout. It
/// **skips** rather than passing vacuously.
///
/// ```
/// MINUTES_REAL_NOTES=1 swift test --filter CaptureLedgerRealLibraryTests
/// ```
///
/// It asserts **properties, not counts.** There were twenty-six records on the
/// day this was written; pinning that would fail on the next meeting.
final class CaptureLedgerRealLibraryTests: XCTestCase {

    private var meetings: [Meeting] = []
    private var recordCount = 0

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MINUTES_REAL_NOTES"] == "1",
                          "set MINUTES_REAL_NOTES=1 to read the real library")
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Minutes/Meetings",
                                    isDirectory: true)
        try XCTSkipUnless(fm.fileExists(atPath: root.path), "no library on this machine")

        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        for name in try fm.contentsOfDirectory(atPath: root.path) where !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name).appendingPathComponent("meeting.json")
            guard fm.fileExists(atPath: url.path) else { continue }
            recordCount += 1
            // Not `try?`. A record that fails to decode is the whole point of
            // this test and must fail it, not be skipped past.
            meetings.append(try d.decode(Meeting.self, from: try Data(contentsOf: url)))
        }
        try XCTSkipUnless(recordCount > 0, "no records in the library")
    }

    /// Every record on disk still decodes, including every one written before
    /// the five fields this increment added existed.
    func testEveryRecordStillDecodes() {
        XCTAssertEqual(meetings.count, recordCount,
                       "\(recordCount - meetings.count) record(s) failed to decode")
    }

    /// **Absent, not zero.** A record from before increment 11 must have no
    /// ledger at all rather than a ledger reading zero, because a zero ledger
    /// would claim the recording lost nothing — which is exactly the claim the
    /// increment found to be false on a recording that looked clean by every
    /// other signal.
    func testARecordWithoutALedgerSaysNothingRatherThanZero() {
        let withoutLedger = meetings.filter { $0.systemLedger == nil && $0.micLedger == nil }
        XCTAssertFalse(withoutLedger.isEmpty,
                       "the library should still hold records written before this increment")
        for m in withoutLedger {
            XCTAssertTrue(m.lostAudioNotices.isEmpty,
                          "a record with no ledger must raise no notice")
        }
    }

    /// Where a ledger exists, its identity closes. A residual nobody can
    /// attribute is information about a mechanism nobody has named, and this is
    /// where a real recording would say so.
    func testWhereALedgerExistsTheIdentityCloses() {
        let ledgers = meetings.flatMap { [$0.micLedger, $0.systemLedger] }
            .compactMap { $0 }.filter { $0.isMeasured }
        for l in ledgers {
            // One callback of tolerance: `deviceFrames` stops at the last
            // callback's start by construction, and the largest callback seen on
            // this hardware is 4,800 frames.
            XCTAssertLessThan(abs(l.unaccountedFrames), 9_600,
                              "the identity does not close: device \(l.deviceFrames), "
                              + "dropped \(l.droppedFrames), consumed \(l.consumedFrames), "
                              + "resident \(l.residentFrames)")
        }
    }

    /// The Mic Stream is the control this increment cannot do without, and on
    /// the real library it must remain the *less* affected of the two. A change
    /// that helped the System Stream at the microphone's expense would have
    /// redistributed the fault rather than removed it.
    ///
    /// `throws`, and the skip is not swallowed. The first version wrote
    /// `try? XCTSkipIf(...)`, which discards the thrown skip and lets the test
    /// continue over an empty collection — a vacuous pass, which is worse than a
    /// skip because it reads as evidence.
    func testTheMicStreamRemainsTheLessAffectedStream() throws {
        let pairs = meetings.compactMap { m -> (Double, Double)? in
            guard let mic = m.micLedger, let sys = m.systemLedger,
                  mic.isMeasured, sys.isMeasured,
                  let mp = mic.lostProportion, let sp = sys.lostProportion else { return nil }
            return (mp, sp)
        }
        try XCTSkipIf(pairs.isEmpty, "no recording yet carries both ledgers — "
                      + "they are written only by the build this increment produced")
        for (mic, _) in pairs {
            // Stated as an absolute bound on the microphone rather than as a
            // comparison, so it still means something on a recording where both
            // Streams are clean.
            XCTAssertLessThan(mic, 0.001,
                              "the Mic Stream lost \(mic * 100)%, above its measured 0.027% worst case")
        }
    }
}
