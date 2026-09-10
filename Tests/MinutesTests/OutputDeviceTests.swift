import XCTest
@testable import Minutes

/// FR-98 / AD-54. Whether Echo is possible is read from the device, and the
/// answer has three values.
final class OutputDeviceTests: XCTestCase {

    private func device(_ transport: String, _ source: String? = nil) -> OutputDevice {
        OutputDevice(name: nil, transport: transport, dataSource: source)
    }

    /// The two cases the device can actually distinguish, which are the same
    /// physical device in two states.
    func testTheBuiltInDeviceSeparatesSpeakersFromTheHeadphoneJack() {
        XCTAssertEqual(device("bltn", "ispk").kind, .loudspeakers)
        XCTAssertEqual(device("bltn", "hdpn").kind, .headphones)
        XCTAssertEqual(device("bltn", nil).kind, .loudspeakers,
                       "a built-in output with no data source is the speakers")
    }

    /// A television, a monitor and an AirPlay speaker all put sound in the room.
    func testExternalDisplaysAndAirPlayAreLoudspeakers() {
        for t in ["hdmi", "dprt", "airp"] {
            XCTAssertEqual(device(t).kind, .loudspeakers, t)
        }
    }

    /// **The case that matters most here, and the one the device cannot answer.**
    /// Every clean recording in the author's library was made on AirPods, which
    /// report the same transport as a Bluetooth loudspeaker.
    func testBluetoothAndUsbAreUnknownRatherThanGuessed() {
        for t in ["blue", "bles", "usb ", "thun", "grup", "virt", ""] {
            XCTAssertEqual(device(t).kind, .unknown, t)
            XCTAssertNil(device(t).kind.echoPossible, "unknown is neither answer")
        }
    }

    /// Echo was possible if it was possible at any point. Anything else lets
    /// thirty seconds on speakers be erased by fifty minutes on AirPods — and the
    /// thirty seconds are the part with the echo in it.
    func testTheUnionOverASessionKeepsTheWorstCase() {
        XCTAssertEqual(OutputDeviceKind.union([.headphones, .loudspeakers]), .loudspeakers)
        XCTAssertEqual(OutputDeviceKind.union([.headphones, .unknown]), .unknown)
        XCTAssertEqual(OutputDeviceKind.union([.headphones, .headphones]), .headphones)
        XCTAssertEqual(OutputDeviceKind.union([]), .unknown, "no reading is not a clean reading")
    }

    // MARK: - What the device does to the exclusion

    private func present(_ kind: OutputDeviceKind?) -> EchoAnalysis {
        EchoAnalysis(verdict: .present, delaySeconds: 0.039, peakCorrelation: 0.9,
                     excludedIntervals: [.init(start: 0, end: 10)],
                     micActiveSeconds: 20, excludedSeconds: 10, deviceKind: kind)
    }

    /// The device can veto, and it cannot vote.
    func testHeadphonesStopTheExclusionAndUnknownDoesNot() {
        XCTAssertFalse(present(.headphones).mayExclude)
        XCTAssertTrue(present(.loudspeakers).mayExclude)
        XCTAssertTrue(present(.unknown).mayExclude,
                      "unknown leaves FR-89's measurement in charge, as before")
        XCTAssertTrue(present(nil).mayExclude,
                      "a recording made before the device was read behaves exactly as it did")
    }

    /// Both readings survive, and the user is told which is which.
    func testADisagreementIsReportedRatherThanResolved() {
        let a = present(.headphones)
        XCTAssertTrue(a.deviceContradictsSignal)
        XCTAssertEqual(a.verdict, .present, "the measurement is not overwritten")
        let why = a.explanation ?? ""
        XCTAssertTrue(why.contains("headphones"), why)
        XCTAssertTrue(why.contains("Nothing was excluded"), why)
    }

    /// The record from before this existed must still load, and must not read as
    /// though the device had been consulted.
    func testAnEchoAnalysisFromBeforeTheDeviceWasReadStillDecodes() throws {
        let json = """
        {"verdict":"present","delaySeconds":0.039,"peakCorrelation":0.9,
         "excludedIntervals":[{"start":0,"end":10}],
         "micActiveSeconds":20,"excludedSeconds":10}
        """
        let a = try JSONDecoder().decode(EchoAnalysis.self, from: Data(json.utf8))
        XCTAssertEqual(a.verdict, .present)
        XCTAssertNil(a.deviceKind)
        XCTAssertTrue(a.mayExclude)
        XCTAssertFalse(a.deviceContradictsSignal)
    }

    /// A four-character code is four characters, and a zero is not "\\0\\0\\0\\0".
    func testFourCharacterCodesReadBackAsText() {
        XCTAssertEqual(OutputDeviceMonitor.text(0x626C_746E), "bltn")
        XCTAssertEqual(OutputDeviceMonitor.text(0x6864_706E), "hdpn")
        XCTAssertEqual(OutputDeviceMonitor.text(0), "", "an unset code is not a name")
    }
}
