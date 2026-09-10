import Foundation

/// Whether the far end can reach the microphone acoustically (FR-98, AD-54).
///
/// **Three values, not two, and that is the whole design.** The obvious shape is
/// a boolean — headphones or not — and it is wrong on this hardware. Core Audio
/// reports AirPods and a Bluetooth loudspeaker with the same transport type, so a
/// boolean has to guess one of them: read as headphones it disables Echo handling
/// on a loudspeaker, read as speakers it runs a canceller into a headset. Saying
/// *unknown* costs nothing, because unknown is exactly where FR-89's correlation
/// detector was already doing the work.
///
/// The research this comes from puts it plainly — "echo isn't a problem with
/// headphones", so an application "needs logic to detect the output device type"
/// rather than a threshold to tune. That is true, and it is true for the built-in
/// speakers and the headphone jack, which are the two cases the device *can*
/// distinguish. It is not true for the case the author actually records in.
enum OutputDeviceKind: String, Equatable, Sendable, Codable, CaseIterable {
    /// Sound leaves the machine into the room, so the microphone can hear it.
    case loudspeakers
    /// Sound goes into someone's ears. There is no acoustic path back.
    case headphones
    /// The device cannot say. Neither a yes nor a no — FR-89's measurement
    /// decides, exactly as it did before this existed.
    case unknown

    /// Whether Echo is physically possible. `nil` means unknown, and unknown is
    /// never read as either answer.
    var echoPossible: Bool? {
        switch self {
        case .loudspeakers: return true
        case .headphones: return false
        case .unknown: return nil
        }
    }

    /// The union over a Session, for a user who unplugs mid-meeting (FR-8, UJ-2).
    ///
    /// **Echo was possible if it was possible at any point.** Anything else would
    /// let thirty seconds on speakers at the start of a call be erased by fifty
    /// minutes on AirPods afterwards, and the thirty seconds are the part with
    /// the echo in it.
    static func union(_ kinds: [OutputDeviceKind]) -> OutputDeviceKind {
        if kinds.contains(.loudspeakers) { return .loudspeakers }
        if kinds.contains(.unknown) || kinds.isEmpty { return .unknown }
        return .headphones
    }
}

/// What the output device said about itself, and what Minutes made of it.
///
/// The raw four-character codes are kept beside the verdict rather than thrown
/// away. When a future reader finds a recording classified `unknown` that clearly
/// had an echo, the transport code is the thing that tells them which device to
/// teach this about — the verdict alone would not.
struct OutputDevice: Equatable, Sendable, Codable {
    /// The device's own name, e.g. "MacBook Pro Speakers". Diagnostic only; the
    /// verdict never depends on it, because a name is a string a vendor chose.
    var name: String?
    /// `kAudioDevicePropertyTransportType` as its four-character code.
    var transport: String
    /// `kAudioDevicePropertyDataSource` as its four-character code, where the
    /// device has one. This is what separates the built-in speakers ('ispk')
    /// from the headphone jack ('hdpn') — the same physical device, two states.
    var dataSource: String?
    var kind: OutputDeviceKind

    init(name: String?, transport: String, dataSource: String?) {
        self.name = name
        self.transport = transport
        self.dataSource = dataSource
        self.kind = OutputDevice.classify(transport: transport, dataSource: dataSource)
    }

    /// Hand-written per the spine's Decodable-evolution convention.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        transport = try c.decodeIfPresent(String.self, forKey: .transport) ?? ""
        dataSource = try c.decodeIfPresent(String.self, forKey: .dataSource)
        kind = try c.decodeIfPresent(OutputDeviceKind.self, forKey: .kind) ?? .unknown
    }

    /// The classification, as a pure function of two four-character codes.
    ///
    /// Every case is a decision about what the device can honestly tell us:
    ///
    ///  - **`bltn` + `hdpn`** — the headphone jack. Sound is in someone's ears.
    ///  - **`bltn` otherwise** — the built-in speakers. This is the case every
    ///    affected recording in the library was made on.
    ///  - **`hdmi`, `dprt`, `airp`** — a television, a monitor or an AirPlay
    ///    speaker. Sound is in the room, usually further away and louder.
    ///  - **everything else** — `blue`, `bles`, `usb `, `thun`, an aggregate, or
    ///    a transport the OS did not name. A Bluetooth headset and a Bluetooth
    ///    speaker are indistinguishable here, and so are a USB headset and a USB
    ///    monitor's speakers. Unknown.
    static func classify(transport: String, dataSource: String?) -> OutputDeviceKind {
        switch transport {
        case "bltn":
            return dataSource == "hdpn" ? .headphones : .loudspeakers
        case "hdmi", "dprt", "airp":
            return .loudspeakers
        default:
            return .unknown
        }
    }

    /// How to say it in the Note's provenance (FR-98). Absent where nothing is
    /// known, because "output device: unknown" is a line that tells a reader
    /// nothing and trains them to skip the ones that do.
    var provenance: String? {
        switch kind {
        case .loudspeakers:
            return "played through \(name ?? "loudspeakers"), so the microphone could hear the call"
        case .headphones:
            return "played through \(name ?? "headphones"), so the microphone could not hear the call"
        case .unknown:
            return nil
        }
    }
}
