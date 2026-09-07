import Foundation

/// What became of every sample the audio device said it delivered (AD-57, FR-102).
///
/// **The type exists because a subtraction was being left to a reader.** AD-51
/// made the device's own counters the authority on the rate, and its continuity
/// term answers one question exactly: did this process receive everything the
/// device counted? On the recording that forced this increment the answer was
/// yes — zero missing frames, zero discontinuities, on both Streams — and the
/// System Stream's file was still **8.37 seconds short of 42 minutes**. Nothing
/// between the callback and the file reported to anyone, so the loss was only
/// findable by subtracting two file lengths weeks later, by which time it had
/// already happened in eight recordings.
///
/// So the terms below are one identity rather than a set of statistics:
///
/// ```
/// deviceFrames  ==  droppedFrames + consumedFrames + residentFrames + unaccountedFrames
/// consumedFrames * (outputRate / inputRate)  ==  writtenFrames + conversionRemainder
/// ```
///
/// `unaccountedFrames` and `conversionRemainder` are the *point*, not slack. A
/// remainder nobody can attribute is information about a mechanism nobody has
/// named yet, and rounding it into a tolerance is exactly how this defect
/// survived fourteen recordings. They are recorded as remainders and named as
/// remainders.
///
/// Pure and Foundation-only by construction: everything here is arithmetic on
/// counts the adapters already keep, so every case below is testable with a
/// handful of literals and no audio device.
struct CaptureLedger: Equatable, Sendable, Codable {

    /// Frames the device's own sample counter accounted for (AD-51's
    /// `sampleAdvance`, plus the final callback it excludes by construction).
    var deviceFrames: Double
    /// Input frames the producer had to drop because the ring was full.
    ///
    /// **This is the number `RingBuffer.didOverflow` could not carry.** It was a
    /// `Bool`, set on the line where samples are dropped and read by nobody, and
    /// a Bool cannot distinguish the Mic Stream's loss from the System Stream's
    /// on the same recording — which is a factor of 380 and the only real clue
    /// the measurement has.
    var droppedFrames: Double
    /// Separate occasions on which the producer had to drop anything.
    ///
    /// One overflow of eight seconds and eight hundred overflows of ten
    /// milliseconds are different faults with the same total, and only this
    /// separates them.
    var overflows: Int
    /// Input frames the writer took out of the ring.
    var consumedFrames: Double
    /// Input frames still in the ring when the count was taken. Normally zero —
    /// `stop()` flushes — and recorded because a non-zero value would mean the
    /// flush did not finish rather than that audio was lost.
    var residentFrames: Double
    /// Frames actually written to the file, at the output rate.
    var writtenFrames: Double
    /// The rate the writer converted *from*, which may be the corrected one
    /// rather than the declared one (AD-44).
    var inputRate: Double
    /// The rate the file is written at.
    var outputRate: Double

    static let unknown = CaptureLedger(
        deviceFrames: 0, droppedFrames: 0, overflows: 0, consumedFrames: 0,
        residentFrames: 0, writtenFrames: 0, inputRate: 0, outputRate: 0)

    /// Whether the device supplied enough for the identity to mean anything.
    ///
    /// **Absent is not zero**, and the distinction is the whole reason this is a
    /// computed property rather than a stored flag: a device that reports no
    /// sample times leaves `deviceFrames` at zero, and reading that as "nothing
    /// was lost" would be the same mistake AD-52 forbids for confidence and
    /// AD-54 forbids for the Echo verdict.
    var isMeasured: Bool { deviceFrames > 0 && outputRate > 0 }

    /// Input frames the device counted that this process cannot place anywhere.
    ///
    /// Zero when the identity closes. Non-zero means a mechanism nobody has
    /// named, and it is reported rather than absorbed.
    var unaccountedFrames: Double {
        guard isMeasured else { return 0 }
        return deviceFrames - droppedFrames - consumedFrames - residentFrames
    }

    /// Output frames the conversion should have produced from what it consumed.
    var expectedWrittenFrames: Double {
        guard inputRate > 0 else { return 0 }
        return consumedFrames * (outputRate / inputRate)
    }

    /// Output frames the writer consumed input for and did not write.
    ///
    /// **Measured, so that it is not guessed.** Driven exactly as
    /// `StreamFileWriter` drives it, `AVAudioConverter` retains a constant ~11
    /// frames of priming latency in total, across runs of 1,500 to 20,000 calls
    /// — 0.0003%, and *not* per call. So a remainder here of more than a few
    /// hundred frames is not the resampler, whatever it looks like on the page.
    var conversionRemainder: Double {
        guard isMeasured else { return 0 }
        return expectedWrittenFrames - writtenFrames
    }

    /// Total output frames the device's audio should have become, had nothing
    /// been lost anywhere.
    var expectedFromDevice: Double {
        guard inputRate > 0 else { return 0 }
        return deviceFrames * (outputRate / inputRate)
    }

    /// Everything missing from the file, in output frames, however it went.
    var lostFrames: Double {
        guard isMeasured else { return 0 }
        return expectedFromDevice - writtenFrames
    }

    /// Everything missing from the file, in seconds.
    var lostSeconds: TimeInterval {
        guard outputRate > 0 else { return 0 }
        return lostFrames / outputRate
    }

    /// Share of the recording that never reached the file.
    var lostProportion: Double? {
        guard isMeasured, expectedFromDevice > 0 else { return nil }
        return lostFrames / expectedFromDevice
    }

    /// Where the loss went, worst term first, for a reader who needs the
    /// mechanism and not just the total.
    ///
    /// Only terms that are actually non-trivial appear. A term of under a frame
    /// is arithmetic on `Double`s, not a fault.
    var attribution: [(term: String, frames: Double)] {
        guard isMeasured else { return [] }
        let terms = [
            ("dropped before the writer could read them", droppedFrames * (outputRate / max(1, inputRate))),
            ("still in the ring when capture stopped", residentFrames * (outputRate / max(1, inputRate))),
            ("consumed and not written", conversionRemainder),
            ("unaccounted for", unaccountedFrames * (outputRate / max(1, inputRate))),
        ]
        return terms.filter { $0.1 >= 1 }.sorted { $0.1 > $1.1 }
            .map { (term: $0.0, frames: $0.1) }
    }

    /// The floor above which a lost stretch is worth telling a reader about.
    ///
    /// **0.4 seconds, and it is one word at a conversational 150 words a
    /// minute.** Below it no word can have been lost whole, so the worst
    /// available outcome is a clipped one; above it, a word the reader will never
    /// see is gone from a transcript that does not look interrupted.
    ///
    /// It is a **disclosure** floor and never a detection tolerance. The counts
    /// above are recorded whatever their size — zero included — so nothing is
    /// absorbed by this number: what it withholds from a banner is still on the
    /// record, still printable, and still what a regression is caught by. The
    /// two cases it separates were measured on one recording: **22 ms on the Mic
    /// Stream against 8.37 s on the System Stream.**
    static let disclosureFloorSeconds: TimeInterval = 0.4

    /// Whether the loss is large enough that a reader should be told.
    var isWorthDisclosing: Bool {
        isMeasured && lostSeconds >= Self.disclosureFloorSeconds
    }

    /// What happened, in a sentence, or nil when nothing worth saying did.
    ///
    /// Says *how much* and *in how many stretches*, and deliberately claims no
    /// position: the app knows how many samples were dropped and not where in
    /// the file they would have been. Claiming a position would be the more
    /// useful answer and the app does not have it.
    func explanation(streamIsSystem: Bool) -> String? {
        guard isWorthDisclosing else { return nil }
        let whose = streamIsSystem ? "the call's own audio" : "your microphone's audio"
        let stretches: String
        switch overflows {
        case 0: stretches = ""
        case 1: stretches = ", in one stretch"
        default: stretches = ", in \(overflows) separate stretches"
        }
        return String(format:
            "About %@ of %@ was lost while this was being recorded%@. "
            + "The transcript below runs straight across those joins, so a "
            + "sentence there may be two halves of different ones.",
            Self.phrase(seconds: lostSeconds), whose, stretches)
    }

    /// Seconds as a reader would say them, not as a float.
    static func phrase(seconds: TimeInterval) -> String {
        if seconds < 1 { return "\(Int((seconds * 1000).rounded())) milliseconds" }
        if seconds < 90 { return "\(Int(seconds.rounded())) seconds" }
        return "\(Int((seconds / 60).rounded())) minutes"
    }

    init(deviceFrames: Double, droppedFrames: Double, overflows: Int,
         consumedFrames: Double, residentFrames: Double, writtenFrames: Double,
         inputRate: Double, outputRate: Double) {
        self.deviceFrames = deviceFrames
        self.droppedFrames = droppedFrames
        self.overflows = overflows
        self.consumedFrames = consumedFrames
        self.residentFrames = residentFrames
        self.writtenFrames = writtenFrames
        self.inputRate = inputRate
        self.outputRate = outputRate
    }

    /// Hand-written per the spine's Decodable-evolution convention: a Meeting
    /// recorded before this existed must decode, and must decode as *absent*
    /// rather than as a clean ledger.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceFrames = try c.decodeIfPresent(Double.self, forKey: .deviceFrames) ?? 0
        droppedFrames = try c.decodeIfPresent(Double.self, forKey: .droppedFrames) ?? 0
        overflows = try c.decodeIfPresent(Int.self, forKey: .overflows) ?? 0
        consumedFrames = try c.decodeIfPresent(Double.self, forKey: .consumedFrames) ?? 0
        residentFrames = try c.decodeIfPresent(Double.self, forKey: .residentFrames) ?? 0
        writtenFrames = try c.decodeIfPresent(Double.self, forKey: .writtenFrames) ?? 0
        inputRate = try c.decodeIfPresent(Double.self, forKey: .inputRate) ?? 0
        outputRate = try c.decodeIfPresent(Double.self, forKey: .outputRate) ?? 0
    }
}
