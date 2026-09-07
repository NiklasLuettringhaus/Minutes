import XCTest
import AVFoundation
@testable import Minutes

/// Does AD-59's reordering make the microphone fail to start?
///
/// **The question that has to be answered before the reorder can ship.** AD-59
/// builds the whole tap chain — a process tap and a private aggregate device —
/// *between* `engine.prepare()` and `engine.start()`. Creating an aggregate
/// device forces a CoreAudio reconfiguration of the default output, and
/// `engine.prepare()` allocates render resources against the format it saw
/// before that. If the reconfiguration invalidates them, `engine.start()` fails
/// with `-10868` (`kAudioUnitErr_FormatNotSupported`) and the Session is lost —
/// which would be a far worse fault than the offset the reorder removes.
///
/// It is a real suspicion, not a theoretical one: `CaptureTeardownTests` hit
/// exactly that error while cycling three Sessions in a row, and a Session
/// recorded on this machine earlier the same day produced **0.13 s of
/// microphone against 57 s of system audio** — on the build that predates this
/// increment, so the fault is not new, but it is the same shape.
///
/// Gated because it opens the real audio devices dozens of times and takes
/// minutes. It reports a rate rather than asserting one, because the number is
/// what the decision needs:
///
/// ```
/// MINUTES_START_ORDER=1 swift test --filter StartOrderRegressionTests
/// ```
final class StartOrderRegressionTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MINUTES_START_ORDER"] == "1",
                          "set MINUTES_START_ORDER=1 — this opens the real devices many times")
        try XCTSkipUnless(MicCapture.authorizationStatus() == .authorized,
                          "needs microphone permission")
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-order-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // `if let`, because `setUpWithError` skips **before** assigning `tmp`
        // and an implicitly-unwrapped nil here does not fail this test — it
        // crashes the whole process with signal 5 and takes every remaining
        // test with it. That is the shape of the defect increment 10 found,
        // where a crash stopped 133 tests from running at all.
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    private static let cycles = 15

    /// AD-59's order: prepare the microphone, build the tap chain, then start
    /// both. The tap chain's construction sits between prepare and start.
    private func newOrder(_ i: Int) throws {
        let mic = MicCapture()
        let tap = SystemTapCapture()
        try mic.prepare(url: tmp.appendingPathComponent("n\(i)-mic.wav"))
        var prepared: SystemTapCapture?
        do {
            try tap.prepare(url: tmp.appendingPathComponent("n\(i)-sys.wav"))
            prepared = tap
        } catch { /* FR-7: the tap is never fatal */ }
        defer { _ = mic.stop(); prepared?.discard() }
        try mic.begin()
    }

    /// The order that shipped before: start the microphone completely, then
    /// build and start the tap chain.
    private func oldOrder(_ i: Int) throws {
        let mic = MicCapture()
        let tap = SystemTapCapture()
        try mic.start(url: tmp.appendingPathComponent("o\(i)-mic.wav"))
        defer { _ = mic.stop(); tap.discard() }
        do {
            try tap.prepare(url: tmp.appendingPathComponent("o\(i)-sys.wav"))
            try tap.begin()
        } catch { /* FR-7 */ }
    }

    func testTheReorderDoesNotMakeTheMicrophoneFailToStart() throws {
        var newFailures: [String] = []
        var oldFailures: [String] = []
        // Interleaved, so a device that degrades over the run degrades both.
        for i in 0..<Self.cycles {
            do { try newOrder(i) } catch { newFailures.append(error.localizedDescription) }
            do { try oldOrder(i) } catch { oldFailures.append(error.localizedDescription) }
        }
        print("""

        === start-order comparison, \(Self.cycles) cycles each, interleaved ===
          AD-59 order (prepare mic, build tap, start both): \
        \(newFailures.count)/\(Self.cycles) microphone failures
          previous order (start mic, then build+start tap): \
        \(oldFailures.count)/\(Self.cycles) microphone failures
        """)
        for f in Set(newFailures) { print("  new order: \(f)") }
        for f in Set(oldFailures) { print("  old order: \(f)") }

        // The assertion is comparative, and deliberately loose in the direction
        // that matters: the reorder may not be *worse*. A shared failure rate is
        // a pre-existing fault and is reported rather than blamed on this change.
        XCTAssertLessThanOrEqual(newFailures.count, oldFailures.count + 1,
                                 "AD-59's order failed to start the microphone "
                                 + "\(newFailures.count) times against "
                                 + "\(oldFailures.count) for the previous order — "
                                 + "the reorder is a regression and must be reverted")
    }
}
