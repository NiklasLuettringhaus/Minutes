import Foundation

/// What the audio device itself says about the samples it handed over (AD-51, FR-94).
///
/// **The whole type exists because two numbers were being thrown away.** Every
/// audio callback on both Streams carries the device's own sample counter and a
/// host-clock stamp taken at the same instant — `mSampleTime`/`mHostTime` in the
/// tap's IOProc, `sampleTime`/`hostTime` on the `AVAudioTime` handed to the
/// microphone tap block. Both adapters bound them to `_`. Everything below is
/// arithmetic on values the process was already being given.
///
/// It answers two questions that AD-44's wall-clock check conflated, and keeping
/// them apart is what makes the tolerance derivable rather than tuned:
///
///  - **Rate.** Sample-time advance over host-time elapsed. Both halves come from
///    the same callback, so scheduling jitter — the thing AD-44's 12% window and
///    3-second settling period were absorbing — is not in the quotient at all.
///    Two callbacks are enough to have an answer.
///  - **Continuity.** Sample-time advance against the frames this process
///    actually received. A shortfall is audio the device produced and the app
///    never got: a hole. The wall clock cannot see it, because a dropped buffer
///    lowers the frame count and the elapsed time it is divided by keeps
///    running, so the two errors partly cancel.
///
/// Pure and clock-free by construction: it is handed host times **already in
/// seconds**, so nothing here knows about `mach_timebase_info` and every case
/// below is testable with three literals.
struct AudioClock: Equatable, Sendable, Codable {

    /// One callback's report. Both values describe the *same instant* — the
    /// device's counter at the first frame of this buffer, and the host clock
    /// then — which is the property the whole measurement rests on.
    struct Tick: Equatable, Sendable, Codable {
        /// The device's own sample counter at this buffer's first frame.
        var sampleTime: Double
        /// The host clock at that instant, in seconds. Any epoch; only
        /// differences are used.
        var hostSeconds: Double
        /// Frames this callback delivered.
        var frames: Double
    }

    /// How far the audio device's crystal and the host's may honestly differ.
    ///
    /// **0.5%**, and it is an allowance rather than a threshold: it is not
    /// separating two populations, it is keeping an exact measurement from
    /// firing on two oscillators that were never synchronised. The failures this
    /// check exists for are ratios of **2 and 3** — 100% and 200% — so the
    /// figure has three orders of magnitude of room, and the wall-clock check it
    /// replaces needed 12% to do the same job. A device that resamples
    /// internally is the reason it is not tighter still.
    ///
    /// Unlike AD-44's tolerance this is not the whole tolerance. It is one term
    /// of `tolerance`, which also carries a quantisation term that *shrinks as
    /// the measurement grows* — which is the property a declared percentage
    /// cannot have.
    static let oscillatorDrift = 0.005

    /// Host time of the very first sample this stream ever delivered.
    ///
    /// Deliberately **never reset**, unlike `first`. A device change renumbers
    /// the device's sample counter (FR-8 rebuilds the tap chain) but does not
    /// move the beginning of the file, and FR-97's offset between the two
    /// Streams is measured from exactly this instant.
    private(set) var originHostSeconds: Double?

    /// The baseline the rate is measured from. Rebased when the device's counter
    /// restarts, because a rate measured across a discontinuity is not a rate.
    private(set) var first: Tick?
    private(set) var last: Tick?
    private(set) var ticks = 0
    /// Frames actually handed to this process between `first` and `last`.
    private(set) var framesDelivered: Double = 0
    /// Frames the device counted past that never arrived here.
    private(set) var framesMissing: Double = 0
    private(set) var discontinuities = 0
    /// The largest single callback seen. The quantisation term of `tolerance`.
    private(set) var largestTick: Double = 0
    /// The device's counter restarted — a rebuilt tap chain, not lost audio.
    private(set) var rebases = 0

    /// Every frame the device's counter accounted for since the first sample,
    /// **across rebases** (AD-57, FR-102).
    ///
    /// Distinct from `sampleAdvance`, which is measured from `first` and is
    /// therefore reset by a rebase — correct for a *rate*, and wrong for an
    /// accounting identity that has to balance over the whole Session. A tap
    /// chain rebuilt on an output-device change (FR-8) would otherwise make the
    /// ledger report the entire pre-rebase recording as unaccounted for.
    ///
    /// It excludes the final callback's own frames, exactly as `sampleAdvance`
    /// does, because a counter difference cannot see past the last buffer's
    /// start. `framesProduced` adds them back.
    private(set) var framesCounted: Double = 0

    init() {}

    mutating func record(_ tick: Tick) {
        guard tick.frames > 0 else { return }
        if originHostSeconds == nil { originHostSeconds = tick.hostSeconds }
        largestTick = max(largestTick, tick.frames)
        ticks += 1

        guard let previous = last else {
            first = tick; last = tick
            return
        }
        let advance = tick.sampleTime - previous.sampleTime
        // A counter that goes backwards is a *new device*, not a hole. FR-8
        // rebuilds the aggregate on an output-device change and the replacement
        // starts its own numbering. Rebasing keeps the rate honest; counting it
        // as missing audio would invent a defect out of a supported feature.
        guard advance >= 0 else {
            rebases += 1
            // The old device's last buffer is the best available account of what
            // it produced after its final callback began. Assuming zero would
            // charge the ledger for it; assuming more would invent audio.
            framesCounted += previous.frames
            first = tick; last = tick
            framesDelivered = 0; framesMissing = 0
            return
        }
        framesCounted += advance
        framesDelivered += previous.frames
        // Half a frame of slack, because these are Doubles and a device is
        // entitled to report a fractional sample time.
        let missing = advance - previous.frames
        if missing > 0.5 {
            framesMissing += missing
            discontinuities += 1
        }
        last = tick
    }

    // MARK: - Derived

    /// Host-clock seconds between the baseline and the latest callback.
    var elapsedSeconds: Double {
        guard let f = first, let l = last else { return 0 }
        return l.hostSeconds - f.hostSeconds
    }

    /// How far the device's own counter advanced over that span.
    var sampleAdvance: Double {
        guard let f = first, let l = last else { return 0 }
        return l.sampleTime - f.sampleTime
    }

    /// Everything the device counted, from the first sample to the end of the
    /// last buffer it handed over (AD-57).
    ///
    /// The numerator of the ledger's first term. `framesCounted` stops at the
    /// last callback's *start*, so the last buffer's own frames are added here —
    /// they were produced and delivered, and leaving them out would report one
    /// buffer of every recording as lost.
    var framesProduced: Double {
        guard let l = last else { return 0 }
        return framesCounted + l.frames
    }

    /// Frames per second, as the device counts them. Zero until measurable.
    var observedRate: Double {
        elapsedSeconds > 0 ? sampleAdvance / elapsedSeconds : 0
    }

    /// Whether there is enough to say anything at all.
    ///
    /// **Two callbacks**, because that is what a difference needs — not a
    /// settling period. There is no startup transient to wait out: the first
    /// callback's sample time is the device's counter at that instant, not a
    /// full buffer divided by a near-zero elapsed, which is the artefact that
    /// forced AD-44's three seconds.
    var isUsable: Bool {
        ticks >= 2 && elapsedSeconds > 0 && sampleAdvance > 0
    }

    /// How far the measurement may sit from the declared rate before it means
    /// something — **computed from this measurement**, not declared.
    ///
    /// Two terms. The first is one callback's worth of host time over the span
    /// measured: CoreAudio's pairing of a sample time with a host time is not
    /// perfect, and a buffer's worth is the honest bound on how far apart they
    /// can be. That term *shrinks as the window grows*, which is the whole
    /// difference from a declared percentage. The second is `oscillatorDrift`,
    /// which does not.
    var tolerance: Double {
        guard sampleAdvance > 0 else { return 1 }
        return largestTick / sampleAdvance + Self.oscillatorDrift
    }

    /// The tolerance at which this measurement can decide the question it is for.
    ///
    /// **4.4%, and it is derived rather than picked.** The app must be able to
    /// tell one real device rate from its nearest neighbour, and the closest pair
    /// on `RateFidelity.standardRate`'s list is 22050 and 24000 — **8.8% apart**.
    /// A tolerance of half that gap separates them; anything wider cannot, and a
    /// measurement that cannot answer the question is `settling` rather than
    /// `correct`. That is what stops a two-callback reading, whose tolerance is
    /// about 100%, from confirming any rate you like.
    static let decisiveTolerance = 0.044

    /// Whether the tolerance has narrowed enough to answer anything.
    ///
    /// This is what replaced AD-44's three-second settling period. It is not a
    /// duration: on the system tap's ~512-frame callbacks at 48 kHz it is reached
    /// in about a quarter of a second, and on a microphone delivering ten times
    /// as much per callback it takes proportionally longer. The measurement
    /// decides when it is ready, rather than a clock deciding for it.
    var isDecisive: Bool { isUsable && tolerance <= Self.decisiveTolerance }

    /// Frames the device produced that this process never received, as a share
    /// of what it should have received. Absent when nothing is measurable.
    var missingProportion: Double? {
        guard isUsable, sampleAdvance > 0 else { return nil }
        return framesMissing / sampleAdvance
    }
}
