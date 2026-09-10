import Foundation

/// Placing the two Streams on one clock (FR-97, AD-53, AD-4).
///
/// FR-6 has always claimed that "a sound occurring at a known wall-clock moment
/// appears at the same offset (±100 ms) in both" Streams. It was an assertion,
/// and measured across the author's real library it **fails by up to 3,278 ms**:
/// the two files differ in length by −364 ms to +3,278 ms, because the microphone
/// opens first and the tap chain takes as long as it takes.
///
/// Nothing here estimates. The offset is measured at capture as the difference
/// between the two Streams' first-sample host times (AD-53) and handed in; this
/// type only decides what to do with it, including the case where there is none.
enum StreamAlignment {

    /// The tolerance FR-6 claims. Kept here so the claim has one home and the
    /// test that checks it and the code that reports it cannot drift apart.
    static let claimedTolerance: TimeInterval = 0.100

    /// Places a System Stream time on the Mic Stream's clock.
    ///
    /// **An unknown offset is not a zero offset, and yet both leave the time
    /// alone.** That is deliberate and it is not a contradiction: with no
    /// measurement the honest action is to change nothing, because the
    /// alternative is re-ordering a stored Transcript by a guess. What must not
    /// happen is `nil` being *recorded* as 0, which would make an unmeasured
    /// Meeting indistinguishable from a perfectly aligned one — so the offset is
    /// optional all the way to the record.
    static func micTime(ofSystemTime t: TimeInterval, offset: TimeInterval?) -> TimeInterval {
        t + (offset ?? 0)
    }

    /// Whether FR-6's ±100 ms claim holds for this Session, or `nil` where it was
    /// never measured.
    ///
    /// This is the requirement turned into a check. It is expected to be `false`
    /// on this hardware — the point is that the merge applies the measured offset
    /// regardless, so a failing capture still produces a correctly ordered
    /// Transcript, and the failure is visible rather than assumed away.
    static func capturesAreAligned(offset: TimeInterval?) -> Bool? {
        guard let offset else { return nil }
        return abs(offset) <= claimedTolerance
    }

    /// What to say about it, or nil when there is nothing to say.
    static func explanation(offset: TimeInterval?) -> String? {
        guard let offset, abs(offset) > claimedTolerance else { return nil }
        return String(format:
            "The two recordings did not start at the same instant — the call's audio "
            + "began %.0f ms %@ the microphone's. Minutes measured that and lined them "
            + "up, so the transcript is in the order things were said.",
            abs(offset) * 1000, offset >= 0 ? "after" : "before")
    }
}
