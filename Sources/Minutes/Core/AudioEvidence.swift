import Foundation

/// Whether a capture actually produced audio, decided from the samples.
///
/// AD-36. macOS exposes no API to ask whether system-audio permission was
/// granted (FR-42), so the only evidence available is what arrived in the file.
/// That makes this the load-bearing check behind every sentence the app says
/// about capture working — and it is why the rule is that **duration is never
/// evidence**.
///
/// The rule exists because the previous test was
/// `peak > 0.0001 || duration > 0.25`, and it was wrong twice over:
///
/// 1. The duration clause made a quarter second of silence sufficient. Frames
///    are written whether or not anything is playing, so a tap that ran and
///    delivered nothing still passed.
/// 2. The peak it consulted was the UI level meter, which **decays**
///    (`max(peak * 0.85, localPeak)`). At stop time it reflects the last
///    moments, not the session. Most meetings end in silence, so even the
///    signal half of the test would have failed had the duration clause not
///    been masking it.
///
/// Measured consequence on the 13 real meetings on the author's machine
/// (`spikes/calibration-audio-evidence-2026-09-02.md`): three system streams
/// hold **pure digital silence, peak exactly 0.0000** — one of them 32 minutes
/// long — and all three were reported as captured successfully.
struct AudioEvidence: Equatable, Sendable, Codable {
    /// Highest absolute sample seen over the whole capture. Never decays.
    var peak: Float
    /// Seconds during which the signal exceeded `silenceFloor`.
    var nonSilentSeconds: TimeInterval
    /// Total captured length. Recorded for diagnosis, never used to decide.
    var duration: TimeInterval

    /// Above digital silence, far below anything audible (about -66 dBFS).
    ///
    /// Calibrated 2026-09-02 against 26 real streams. The failed streams are not
    /// merely quiet, they are *exactly* zero — a tap that lacks permission
    /// delivers digital silence, not a faint signal. Any floor above zero
    /// separates them; this value sits just high enough that a single stray
    /// non-zero sample cannot count as audio, and low enough that genuine
    /// low-level room noise still does.
    static let silenceFloor: Float = 0.0005

    /// How much signal has to be present before capture counts as working.
    ///
    /// Half a second. It must stay small because the Test Playground records for
    /// only five (FR-47). On the calibration data the failed streams scored
    /// 0.0 s and the quietest working stream scored 1.5 s, so this sits between
    /// them without being tuned to either.
    ///
    /// **Its resolution is coarse and worth stating.** `nonSilentSeconds` is
    /// accumulated per drained chunk — about 170 ms at 48 kHz — so a chunk
    /// containing one loud sample counts whole. Three isolated clicks landing in
    /// three different chunks would therefore clear this threshold. That is a
    /// deliberate trade: per-sample counting is *worse*, because every waveform
    /// passes through zero constantly and a genuine tone would undercount
    /// badly. So this rejects a single pop, not a deliberate sequence of them —
    /// which is the failure mode that actually occurs (a tap delivering exact
    /// zeros), not the one an adversary would construct.
    static let minimumSignalSeconds: TimeInterval = 0.5

    /// The claim itself. Both conditions, because either alone is defeatable:
    /// a peak with no duration is a pop, and duration with no peak is silence.
    var producedAudio: Bool {
        peak > Self.silenceFloor && nonSilentSeconds >= Self.minimumSignalSeconds
    }

    /// Why, in the app's own words, when it did not.
    var failureReason: String? {
        guard !producedAudio else { return nil }
        if peak <= Self.silenceFloor {
            return duration < 0.25
                ? "nothing was recorded"
                : "\(Self.spell(duration)) of recording, and every sample is silent"
        }
        // Clamped because the accumulators advance before the file write: a
        // failed resample or write increments non-silent frames without
        // advancing duration, which read as "only 3 seconds of the 1 second
        // recorded". Clamping fixes the sentence; the write failure is logged
        // where it happens rather than hidden here.
        return "only \(Self.spell(min(nonSilentSeconds, duration))) of the \(Self.spell(duration)) recorded contained any sound"
    }

    /// A duration a person can read. Minutes past a minute and a half, because
    /// "757 seconds" is a number the reader has to convert before it means
    /// anything.
    static func spell(_ s: TimeInterval) -> String {
        if s < 1 { return String(format: "%.2f seconds", s) }
        if s < 90 { return String(format: "%.0f second%@", s, s < 1.5 ? "" : "s") }
        let m = (s / 60).rounded()
        return "\(Int(m)) minute\(m == 1 ? "" : "s")"
    }

    static let none = AudioEvidence(peak: 0, nonSilentSeconds: 0, duration: 0)
}
