import Foundation

/// How close a Stream came to outrunning the thread that writes it (AD-58, FR-103).
///
/// **A drop count with no cause attached is not a diagnosis.** Where samples go
/// missing between the callback and the file, the reason is a consumer that did
/// not keep up, and the two numbers that establish it are free to take on the
/// thread that fell behind. Both rings hold **ten seconds**, and that figure is
/// what makes these numbers interpretable: a fault that needs the writer to be
/// ten seconds late is a different fault from one that needs it to be fifty
/// milliseconds late, and nothing else separates them.
///
/// It also covers the case a drop count cannot reach at all. A recording that
/// dropped nothing and peaked at 96% of its ring is a fault waiting for a busier
/// day, and it is indistinguishable from a healthy one until this is recorded.
///
/// Diagnostics only. Nothing here refuses, delays, degrades or alters a capture,
/// and none of it is gated on a preference (AD-45's rule, and its reason).
struct DrainPressure: Equatable, Sendable, Codable {

    /// The largest backlog the writer ever found waiting, in input frames.
    var highWaterFrames: Double
    /// The ring's capacity in input frames, so the share is derivable rather
    /// than stored twice.
    var capacityFrames: Double
    /// The longest interval between two successive drains, in seconds.
    ///
    /// **On its own this says nothing**, which is why it never travels alone.
    /// The drain loop sleeps 20 ms whenever the ring is empty, so an idle
    /// recording produces gaps of 20 ms by design. What distinguishes a stall
    /// from an idle wait is the backlog that had piled up by the time the gap
    /// ended — `backlogAtLongestGap` — and the two are recorded as a pair for
    /// exactly that reason.
    var longestGapSeconds: TimeInterval
    /// The backlog the writer found at the end of that longest gap, in input
    /// frames. Small means the writer was idle; large means it was starved.
    var backlogAtLongestGap: Double
    /// The rate those frames arrive at, so a frame count can be read as time.
    var inputRate: Double

    static let unknown = DrainPressure(highWaterFrames: 0, capacityFrames: 0,
                                       longestGapSeconds: 0, backlogAtLongestGap: 0,
                                       inputRate: 0)

    var isMeasured: Bool { capacityFrames > 0 && inputRate > 0 }

    /// The closest the recording came to filling its ring, as a share.
    var highWaterProportion: Double? {
        guard capacityFrames > 0 else { return nil }
        return highWaterFrames / capacityFrames
    }

    /// How much audio the ring holds when full.
    var capacitySeconds: TimeInterval {
        guard inputRate > 0 else { return 0 }
        return capacityFrames / inputRate
    }

    /// The largest backlog, as time rather than frames.
    var highWaterSeconds: TimeInterval {
        guard inputRate > 0 else { return 0 }
        return highWaterFrames / inputRate
    }

    /// The backlog at the longest gap, as time rather than frames.
    ///
    /// **There is deliberately no `wasStarved` flag here.** The first version had
    /// one, thresholded at what a single read can take, and on a perfectly
    /// healthy microphone capture it said `STARVED` — because the microphone's
    /// callback is 4,800 frames and two of them exceed one 8,192-frame read. A
    /// Bool over a number nobody had looked at yet is the same mistake as
    /// `RingBuffer.didOverflow`, which is what this increment exists to correct.
    ///
    /// The fact is `CaptureLedger.droppedFrames`: it is zero or it is not. These
    /// numbers are the context that explains it, and they are reported rather
    /// than judged.
    var backlogAtLongestGapSeconds: TimeInterval {
        guard inputRate > 0 else { return 0 }
        return backlogAtLongestGap / inputRate
    }

    init(highWaterFrames: Double, capacityFrames: Double,
         longestGapSeconds: TimeInterval, backlogAtLongestGap: Double,
         inputRate: Double) {
        self.highWaterFrames = highWaterFrames
        self.capacityFrames = capacityFrames
        self.longestGapSeconds = longestGapSeconds
        self.backlogAtLongestGap = backlogAtLongestGap
        self.inputRate = inputRate
    }

    /// Hand-written per the spine's Decodable-evolution convention.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        highWaterFrames = try c.decodeIfPresent(Double.self, forKey: .highWaterFrames) ?? 0
        capacityFrames = try c.decodeIfPresent(Double.self, forKey: .capacityFrames) ?? 0
        longestGapSeconds = try c.decodeIfPresent(Double.self, forKey: .longestGapSeconds) ?? 0
        backlogAtLongestGap = try c.decodeIfPresent(Double.self, forKey: .backlogAtLongestGap) ?? 0
        inputRate = try c.decodeIfPresent(Double.self, forKey: .inputRate) ?? 0
    }
}

/// The two numbers that decide how far behind a writer may fall before audio is
/// lost, in one place because they are read from three.
///
/// They were literals in two adapters and one method, and `DrainPressure` cannot
/// be interpreted without them: a high-water mark is a share of a capacity, and
/// a gap is a stall only relative to how much a single read can take.
enum StreamRingSizing {
    /// Seconds of audio each Stream's ring holds.
    ///
    /// **Ten, unchanged.** It is not raised here on purpose: a bigger buffer
    /// moves the load at which the fault appears without removing it, which is
    /// the tolerance-widening AD-51 exists to stop.
    static let seconds = 10
    /// Input frames one `drainOnce` may take. The unit a backlog is compared to.
    static let readFrames: Double = 8192
}
