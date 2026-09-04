import Foundation

/// Whether the app received everything the device produced (AD-51, FR-94).
///
/// A **different question** from `RateFidelity`, and separating them is the point.
/// A rate error means the samples are at the wrong speed; a continuity error
/// means some of them are not here at all. The wall-clock check cannot tell them
/// apart, and in fact tends to hide the second: dropped frames lower the
/// numerator while the elapsed time in the denominator keeps running, so the
/// ratio moves less than the loss did.
///
/// `unknown` is the honest answer for every device that supplies no timestamps
/// and for every recording made before this existed. It is not `clean` — the
/// same rule the echo verdict and the rate check already settled on.
struct StreamContinuity: Equatable, Sendable, Codable {

    /// Frames the device counted past that never arrived here.
    var missingFrames: Double
    /// Frames the device counted over the measured span.
    var expectedFrames: Double
    /// How many separate holes those frames fell into.
    var discontinuities: Int
    /// How many times the device's counter restarted. **Not** a defect: FR-8
    /// rebuilds the tap chain on an output-device change and the replacement
    /// numbers its own samples. Recorded so a reader can tell a supported event
    /// from a lost one.
    var rebases: Int

    static let unknown = StreamContinuity(missingFrames: 0, expectedFrames: 0,
                                          discontinuities: 0, rebases: 0)

    var isMeasured: Bool { expectedFrames > 0 }

    /// Share of the stream the app never received, or nil when nothing was measured.
    var missingProportion: Double? {
        guard expectedFrames > 0 else { return nil }
        return missingFrames / expectedFrames
    }

    /// What happened, in a sentence, or nil when nothing did.
    ///
    /// Deliberately silent below a frame: a device is entitled to report a
    /// fractional sample time, and a sentence about a rounding error is noise
    /// that trains a reader to ignore the ones that matter.
    var explanation: String? {
        guard isMeasured, missingFrames >= 1, let share = missingProportion else { return nil }
        let places = discontinuities == 1 ? "one place" : "\(discontinuities) places"
        return String(format:
            "The audio device produced about %.1f%% more sound than Minutes received, "
            + "in %@ — that audio is missing from the recording.", share * 100, places)
    }

    init(missingFrames: Double, expectedFrames: Double,
         discontinuities: Int, rebases: Int) {
        self.missingFrames = missingFrames
        self.expectedFrames = expectedFrames
        self.discontinuities = discontinuities
        self.rebases = rebases
    }

    /// Hand-written per the spine's Decodable-evolution convention.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        missingFrames = try c.decodeIfPresent(Double.self, forKey: .missingFrames) ?? 0
        expectedFrames = try c.decodeIfPresent(Double.self, forKey: .expectedFrames) ?? 0
        discontinuities = try c.decodeIfPresent(Int.self, forKey: .discontinuities) ?? 0
        rebases = try c.decodeIfPresent(Int.self, forKey: .rebases) ?? 0
    }
}
