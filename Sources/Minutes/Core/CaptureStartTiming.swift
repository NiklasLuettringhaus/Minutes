import Foundation

/// What each stage of capture start cost, on the clock the callbacks stamp
/// (AD-59, FR-104).
///
/// **One number was not actionable.** FR-97 measures the offset between the two
/// Streams' first samples and the merge applies it, which is correct and is a
/// symptom fix. The number itself said nothing about what to change: **+1,006 ms**
/// on a real 42.4-minute meeting against **+35 to +62 ms** on a five-second
/// `--check-clock` probe over six runs. A twentyfold understatement means the
/// cold probe does not exercise whatever costs the second, and a single figure
/// cannot say which stage spent it.
///
/// So the offset is decomposed into two terms that can be acted on separately:
///
///  - **Setup serialisation** — host time between the microphone being started
///    and the tap's device being started. This is the term AD-59 removes, by
///    building everything that can be built before either device runs.
///  - **First-callback latency** — for each Stream, host time between its device
///    being started and its first sample arriving. This is the device's own
///    warm-up and is not ours to remove; it is ours to stop confusing with the
///    term above.
///
/// Every stamp is a mach host time converted to seconds by the same function the
/// callbacks use, so the subtractions below are on one clock. Mixing a wall
/// clock into an audio measurement is what AD-51 exists to stop, and this is the
/// same rule applied to a different quantity.
///
/// Absent throughout for a Session that captured no host times, and absent is
/// never zero.
struct CaptureStartTiming: Equatable, Sendable, Codable {

    /// Host seconds at which `start(into:)` was entered.
    var beganAt: Double?
    /// Host seconds at which the microphone was prepared but not yet started.
    ///
    /// Separated from `tapChainBuiltAt` because the first reading of this
    /// conflated the two and attributed the microphone's own `engine.prepare()`
    /// to the tap chain. A stage measurement that charges one stage for another
    /// is worse than no stage measurement, because it points a change at the
    /// wrong place.
    var micPreparedAt: Double?
    /// Host seconds at which the microphone's engine was running.
    var micStartedAt: Double?
    /// Host seconds at which the process tap and its aggregate device existed,
    /// before either device was started.
    var tapChainBuiltAt: Double?
    /// Host seconds at which the tap's aggregate device was started.
    var systemStartedAt: Double?
    /// Host seconds of the first sample each Stream actually delivered.
    var micFirstSampleAt: Double?
    var systemFirstSampleAt: Double?

    static let unknown = CaptureStartTiming()

    init(beganAt: Double? = nil, micPreparedAt: Double? = nil,
         micStartedAt: Double? = nil,
         tapChainBuiltAt: Double? = nil, systemStartedAt: Double? = nil,
         micFirstSampleAt: Double? = nil, systemFirstSampleAt: Double? = nil) {
        self.beganAt = beganAt
        self.micPreparedAt = micPreparedAt
        self.micStartedAt = micStartedAt
        self.tapChainBuiltAt = tapChainBuiltAt
        self.systemStartedAt = systemStartedAt
        self.micFirstSampleAt = micFirstSampleAt
        self.systemFirstSampleAt = systemFirstSampleAt
    }

    var isMeasured: Bool { beganAt != nil && micStartedAt != nil }

    /// Host seconds spent building the tap chain, before anything was started.
    ///
    /// Under AD-59 this happens while nothing is recording, so it costs the
    /// offset nothing. Recorded anyway, because it is the term that *used* to be
    /// paid for out of the microphone's recording time and a reader comparing
    /// two builds needs to see that it moved rather than shrank.
    var tapChainBuildSeconds: TimeInterval? {
        guard let a = micPreparedAt, let b = tapChainBuiltAt else { return nil }
        return b - a
    }

    /// Host seconds spent preparing the microphone's engine, before anything was
    /// started. Charged to the microphone, where it belongs.
    var micPrepareSeconds: TimeInterval? {
        guard let a = beganAt, let b = micPreparedAt else { return nil }
        return b - a
    }

    /// Host seconds between the two device starts. **The term AD-59 owns.**
    ///
    /// Positive means the tap's device was started after the microphone's.
    var startSerialisationSeconds: TimeInterval? {
        guard let m = micStartedAt, let s = systemStartedAt else { return nil }
        return s - m
    }

    /// Host seconds each device took to deliver its first sample after being
    /// started. Not ours to remove; ours not to confuse with the above.
    var micFirstCallbackSeconds: TimeInterval? {
        guard let s = micStartedAt, let f = micFirstSampleAt else { return nil }
        return f - s
    }

    var systemFirstCallbackSeconds: TimeInterval? {
        guard let s = systemStartedAt, let f = systemFirstSampleAt else { return nil }
        return f - s
    }

    /// The offset FR-97 records, recomputed from these stamps.
    ///
    /// It must agree with the offset taken from the two clocks' origins — the
    /// two are the same subtraction reached two ways, and a disagreement between
    /// them is a defect in this type rather than a fact about the capture.
    var streamOffsetSeconds: TimeInterval? {
        guard let m = micFirstSampleAt, let s = systemFirstSampleAt else { return nil }
        return s - m
    }

    /// The offset, split into the part capture caused and the part the devices
    /// did. The two terms sum to `streamOffsetSeconds` by construction.
    var decomposition: (serialisation: TimeInterval, deviceLatency: TimeInterval)? {
        guard let total = streamOffsetSeconds,
              let serial = startSerialisationSeconds else { return nil }
        return (serialisation: serial, deviceLatency: total - serial)
    }

    /// Hand-written per the spine's Decodable-evolution convention. Every field
    /// is optional and absent decodes as absent, not as zero.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        beganAt = try c.decodeIfPresent(Double.self, forKey: .beganAt)
        micPreparedAt = try c.decodeIfPresent(Double.self, forKey: .micPreparedAt)
        micStartedAt = try c.decodeIfPresent(Double.self, forKey: .micStartedAt)
        tapChainBuiltAt = try c.decodeIfPresent(Double.self, forKey: .tapChainBuiltAt)
        systemStartedAt = try c.decodeIfPresent(Double.self, forKey: .systemStartedAt)
        micFirstSampleAt = try c.decodeIfPresent(Double.self, forKey: .micFirstSampleAt)
        systemFirstSampleAt = try c.decodeIfPresent(Double.self, forKey: .systemFirstSampleAt)
    }
}
