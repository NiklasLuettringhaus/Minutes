import XCTest
@testable import Minutes

/// The Heuristic backend is the unit-test target precisely because it is
/// deterministic (AD-12) — no model, no network, no assets.
final class HeuristicBackendTests: XCTestCase {

    private func utterances(_ pairs: [(Double, String, SpeakerLabelID)]) -> [Utterance] {
        pairs.map { Utterance(start: $0.0, end: $0.0 + 3, text: $0.1, speaker: $0.2,
                              origin: $0.2.isLocal ? .mic : .system) }
    }

    private var meetingTranscript: [Utterance] {
        utterances([
            (0,   "Okay so today we need to talk about the pricing page redesign.", .local),
            (4,   "The pricing page is confusing customers, that's the main problem.", .remote(0)),
            (9,   "Right, the pricing page conversion dropped twelve percent last quarter.", .local),
            (14,  "We decided to simplify the pricing page down to three tiers.", .remote(0)),
            (19,  "I'll take the copy review for the pricing page by Thursday.", .remote(1)),
            (24,  "Can you also check the mobile pricing page layout?", .local),
            (28,  "Sure. Let me handle the mobile layout as well.", .remote(1)),
        ])
    }

    func testAlwaysAvailable() async {
        let ok = await HeuristicBackend().isAvailable()
        XCTAssertTrue(ok, "The heuristic backend must work with no model and no network")
    }

    func testDeterministic() async throws {
        let b = HeuristicBackend()
        let names = [SpeakerLabelID.local.raw: "Me"]
        let a = try await b.derive(from: meetingTranscript, names: names)
        let c = try await b.derive(from: meetingTranscript, names: names)
        XCTAssertEqual(a.title, c.title)
        XCTAssertEqual(a.tags, c.tags)
        XCTAssertEqual(a.summary, c.summary)
    }

    func testTitleReflectsSubject() async throws {
        let md = try await HeuristicBackend().derive(from: meetingTranscript, names: [:])
        XCTAssertTrue(md.title.lowercased().contains("pricing"),
                      "Expected the dominant early phrase in the title, got: \(md.title)")
    }

    func testTagsAreLowercasedAndBounded() async throws {
        let md = try await HeuristicBackend().derive(from: meetingTranscript, names: [:])
        XCTAssertLessThanOrEqual(md.tags.count, 6)
        for t in md.tags {
            XCTAssertEqual(t, t.lowercased())
            XCTAssertFalse(t.contains(" "), "tags should be hyphenated, got \(t)")
        }
    }

    /// FR-55, and the point of story 9.1: this Backend no longer writes prose.
    ///
    /// The extract it used to call a summary was the four highest-weighted
    /// sentences of the transcript in transcript order — for a short meeting, most
    /// of the original text, and persuasive enough to be read as a real summary.
    func testDeriveProducesATitleAndTagsAndNoProse() async throws {
        let md = try await HeuristicBackend().derive(from: meetingTranscript, names: [:])
        XCTAssertFalse(md.title.isEmpty, "the title guarantee survives (FR-26)")
        XCTAssertFalse(md.tags.isEmpty, "tags survive — keyphrase salience is right for a label")
        XCTAssertTrue(md.summary.isEmpty, "no summary from a Backend that cannot write one")
        XCTAssertTrue(md.decisions.isEmpty, "no decisions")
        XCTAssertTrue(md.actionItems.isEmpty, "no action items")
        XCTAssertEqual(md.backend, .heuristic, "provenance is still recorded")
    }

    // The extraction functions are retained, unused by `derive`, and still covered:
    // they are pure, they are the only tested implementation of extractive
    // metadata, and re-enabling any of them is a one-line change. The action-item
    // extraction in particular was the best-performing of the three.

    func testFindsDecisionWithTimestamp() {
        let sentences = HeuristicBackend.sentences(from: meetingTranscript)
        let decisions = HeuristicBackend.decisions(in: sentences)
        XCTAssertFalse(decisions.isEmpty, "should find 'We decided to…'")
        XCTAssertNotNil(decisions.first?.at, "a decision must cite the timestamp it came from")
    }

    func testActionItemOwnerFromFirstPerson() {
        let names = [SpeakerLabelID.local.raw: "Me", SpeakerLabelID.remote(1).raw: "Mikkel"]
        let sentences = HeuristicBackend.sentences(from: meetingTranscript)
        let items = HeuristicBackend.actionItems(in: sentences, names: names)
        XCTAssertFalse(items.isEmpty)
        let mikkels = items.filter { $0.owner == "Mikkel" }
        XCTAssertFalse(mikkels.isEmpty, "\"I'll take…\" said by Mikkel should be owned by Mikkel")
    }

    /// Absence is represented honestly — never invented content (FR-29).
    func testNoInventedContentWhenNothingIsThere() async throws {
        let small = utterances([(0, "Hello. Hi. Yeah. Okay. Sure.", .local)])
        let md = try await HeuristicBackend().derive(from: small, names: [:])
        XCTAssertTrue(md.decisions.isEmpty, "must not invent decisions")
        XCTAssertTrue(md.actionItems.isEmpty, "must not invent action items")
    }

    func testEmptyTranscriptDoesNotCrash() async throws {
        let md = try await HeuristicBackend().derive(from: [], names: [:])
        XCTAssertTrue(md.tags.isEmpty)
        XCTAssertTrue(md.summary.isEmpty)
    }

    /// FR-28: under 2 seconds for a 2-hour transcript.
    func testPerformanceOnLongTranscript() async throws {
        var long: [Utterance] = []
        let sentences = [
            "We should review the quarterly roadmap for the platform team.",
            "The migration timeline slipped because of the database work.",
            "I'll follow up with the vendor about the licence renewal.",
            "We decided to postpone the launch until the audit completes.",
        ]
        // ~2 hours at one utterance every 4 seconds.
        for i in 0..<1800 {
            long.append(Utterance(start: Double(i) * 4, end: Double(i) * 4 + 3.5,
                                  text: sentences[i % sentences.count],
                                  speaker: i % 3 == 0 ? .local : .remote(i % 2),
                                  origin: i % 3 == 0 ? .mic : .system))
        }
        let start = Date()
        let md = try await HeuristicBackend().derive(from: long, names: [:])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "FR-28 requires under 2s for a 2-hour transcript; took \(elapsed)s")
        XCTAssertFalse(md.title.isEmpty)
    }
}

/// Filler-word stripping. The dangerous failure is substring matching, so that
/// is tested first.
final class FillerWordTests: XCTestCase {
    private let w = FillerWords.defaults

    func testStripsStandaloneFillers() {
        XCTAssertEqual(FillerWords.strip("So um we decided to ship it", words: w),
                       "So we decided to ship it")
        XCTAssertEqual(FillerWords.strip("Uh, I think that works", words: w),
                       "I think that works")
    }

    /// "um" must never be cut out of "number".
    func testNeverMatchesInsideAnotherWord() {
        XCTAssertEqual(FillerWords.strip("The number is umbrella shaped", words: w),
                       "The number is umbrella shaped")
        XCTAssertEqual(FillerWords.strip("Her manner was ahead of ours", words: w),
                       "Her manner was ahead of ours")
    }

    func testRepairsPunctuationLeftBehind() {
        // Without repair this becomes "So, , we decided" — worse than the filler.
        XCTAssertEqual(FillerWords.strip("So, um, we decided", words: w), "So, we decided")
        XCTAssertEqual(FillerWords.strip("Right , uh . Next item", words: w), "Right. Next item")
    }

    func testDropsUtterancesThatWereOnlyFiller() {
        XCTAssertEqual(FillerWords.strip("Um.", words: w), "")
        XCTAssertEqual(FillerWords.strip("uh, um, er", words: w), "")
    }

    func testRecapitalisesAfterStrippingAnOpener() {
        XCTAssertEqual(FillerWords.strip("Um, the pricing page is confusing", words: w),
                       "The pricing page is confusing")
    }

    func testLongestMatchWinsSoRemnantsAreNotLeft() {
        XCTAssertEqual(FillerWords.strip("Ummm okay then", words: w), "Okay then")
    }

    func testDisabledListIsANoOp() {
        XCTAssertEqual(FillerWords.strip("So um we decided", words: []), "So um we decided")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(FillerWords.strip("UH, right", words: w), "Right")
    }
}
