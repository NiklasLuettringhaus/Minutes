import Foundation
import AVFoundation

/// Captures both Streams on one session clock (AD-4).
///
/// The product's central design bet: the Mic Stream is the Local Speaker by
/// construction, and the System Stream holds everyone else. Recording them
/// separately makes "who is the user" a fact rather than a prediction (AD-11).
///
/// Degrades to Mic-only rather than failing when the tap is unavailable (FR-7) —
/// a user who declined the permission still wants their own side captured, and a
/// recording must never be blocked by a permission dialog.
final class DualStreamCapture: Capturing {
    private let mic = MicCapture()
    private var system: SystemTapCapture?
    /// FR-98 / AD-54. Owned here rather than by the tap, because the question
    /// must be answerable on a mic-only Session — which is the degraded case
    /// where the far end reaches the microphone and nothing else records it.
    private let outputDevice = OutputDeviceMonitor()
    private var directory: URL?
    private var startedAt: Date?
    /// What each stage of start cost, on the callbacks' own clock (FR-104).
    private(set) var startTiming = CaptureStartTiming.unknown
    private(set) var isRunning = false
    private(set) var systemFailure: MinutesError?

    /// True when the System Stream is not being captured, so the UI can say so
    /// rather than degrade silently (FR-7).
    var isDegraded: Bool { isRunning && system?.isRunning != true }

    /// AD-59. **Prepare both, then start both, with nothing in between.**
    ///
    /// The previous order was: open the microphone, then build the tap chain —
    /// process tap, default-output UID, private aggregate device, IOProc — then
    /// start the tap. All of that construction happened while the microphone was
    /// already recording, so every millisecond of it landed in the offset FR-97
    /// measures. Measured at **+1,006 ms** on a real 42.4-minute meeting.
    ///
    /// Three things about this order are deliberate and each is a constraint
    /// rather than a preference:
    ///
    ///  - **The tap chain is built before the microphone is started, not
    ///    before it is prepared.** `MicCapture.prepare` allocates the engine's
    ///    render resources and installs the tap block, which is the expensive
    ///    part and now costs the offset nothing.
    ///  - **FR-7 still wins.** A tap that cannot be built degrades the Session
    ///    and never fails it, and the microphone is started on that path too.
    ///    What it now costs is the *time* the failing chain took, which
    ///    `startTiming` records so it is a measured cost rather than an unknown
    ///    one.
    ///  - **The two `begin()` calls are adjacent**, and nothing may be inserted
    ///    between them. Anything that looks like it belongs there belongs above.
    func start(into dir: URL) throws {
        guard !isRunning else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directory = dir
        systemFailure = nil
        var timing = CaptureStartTiming()
        timing.beganAt = AudioClockTap.seconds(fromHostTime: mach_absolute_time())
        outputDevice.start()

        // 1. Prepare the microphone. It is the Stream we cannot do without and
        //    the one with a real permission API, so its failure is still fatal.
        try mic.prepare(url: dir.appendingPathComponent("mic.wav"))
        timing.micPreparedAt = AudioClockTap.seconds(fromHostTime: mach_absolute_time())

        // 2. Build the whole tap chain, while nothing is recording yet. Never
        //    fatal: its failure degrades the Session (FR-7).
        let tap = SystemTapCapture()
        var prepared: SystemTapCapture?
        do {
            try tap.prepare(url: dir.appendingPathComponent("system.wav"))
            prepared = tap
        } catch let e as MinutesError {
            systemFailure = e
            Log.audio.error("system stream unavailable, continuing mic-only: \(e.localizedDescription, privacy: .public)")
        }
        timing.tapChainBuiltAt = AudioClockTap.seconds(fromHostTime: mach_absolute_time())

        // 3. Start both devices, back to back. Nothing goes between these.
        //
        // The microphone's failure is still fatal, and it now has a prepared tap
        // chain to give back before it propagates. Without this the aggregate
        // device and the process tap leak for the life of the process — visible
        // system-wide (AD-2) — and the tap's drain thread spins on a file it
        // never closes, because `createIOProc` retains the tap and `deinit`
        // therefore cannot run.
        do {
            try mic.begin()
        } catch {
            prepared?.discard()
            outputDevice.stop()
            throw error
        }
        timing.micStartedAt = AudioClockTap.seconds(fromHostTime: mach_absolute_time())
        if let p = prepared {
            do {
                try p.begin()
                system = p
                timing.systemStartedAt = p.startedHostSeconds
            } catch let e as MinutesError {
                systemFailure = e
                system = nil
                // `begin()` tears itself down on failure, so nothing is left to
                // release here — but the Session continues mic-only, and this is
                // the path where forgetting it would leak silently.
                Log.audio.error("system stream could not be started, continuing mic-only: \(e.localizedDescription, privacy: .public)")
            }
        }

        startTiming = timing
        startedAt = Date()
        isRunning = true
        if let build = timing.tapChainBuildSeconds {
            Log.audio.info("capture start: tap chain built in \(Int(build * 1000)) ms before either device was started")
        }
    }

    func stop() -> CapturedStreams {
        guard isRunning, let dir = directory else {
            return CapturedStreams(micURL: nil, systemURL: nil, duration: 0, systemCaptured: false)
        }
        outputDevice.stop()
        let micResult = mic.stop()
        let micDuration = micResult.duration
        let micEvidence = micResult.evidence
        let micRate = micResult.rate
        var systemResult = StreamCaptureResult()
        let tapEstablished = (system != nil)
        if let s = system { systemResult = s.stop() }
        let systemDuration = systemResult.duration
        let systemEvidence = systemResult.evidence
        let systemRate = systemResult.rate

        // FR-97 / AD-53. The two Streams do not start at the same instant — the
        // microphone opens first and the tap chain takes as long as it takes —
        // and until now nothing recorded by how much. Measured across the real
        // library the two files differ in length by −364 ms to +3,278 ms, and
        // FR-6's claim that a sound "appears at the same offset (±100 ms) in
        // both" was an assertion nobody had checked.
        //
        // This is a subtraction of two numbers the devices handed us, not an
        // estimate. It is available on every dual-stream Session, including the
        // clean ones a correlation search has nothing to align on.
        var offset: TimeInterval?
        if let micOrigin = micResult.originHostSeconds,
           let sysOrigin = systemResult.originHostSeconds {
            offset = sysOrigin - micOrigin
            Log.audio.info("stream start offset \(Int((offset ?? 0) * 1000)) ms (system later than mic)")
        }
        // FR-104. The same offset, reached from the per-stage stamps, so it can
        // be split into the part capture caused and the part the devices did.
        // The two routes to it must agree; a disagreement is a defect in
        // `CaptureStartTiming` rather than a fact about the capture.
        var timing = startTiming
        timing.micFirstSampleAt = micResult.originHostSeconds
        timing.systemFirstSampleAt = systemResult.originHostSeconds
        if let d = timing.decomposition {
            Log.audio.info("start offset decomposes: \(Int(d.serialisation * 1000)) ms between the two device starts, \(Int(d.deviceLatencyGap * 1000)) ms of difference between the two devices' first-callback latencies")
        }
        // FR-102. The one number this increment exists for, on the record
        // whether it is zero or not.
        for (name, led) in [("mic", micResult.ledger), ("system", systemResult.ledger)]
        where led.isMeasured {
            Log.audio.info("\(name, privacy: .public) ledger: device \(Int(led.deviceFrames)) frames, dropped \(Int(led.droppedFrames)) in \(led.overflows) overflow(s), consumed \(Int(led.consumedFrames)), written \(Int(led.writtenFrames)), unaccounted \(Int(led.unaccountedFrames)), lost \(led.lostSeconds) s")
        }
        let produced = systemEvidence.producedAudio
        system = nil
        isRunning = false

        let wall = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        // Trust wall-clock for the Meeting duration; the frame-derived figures are
        // a cross-check (the spike showed a possible framing discrepancy).
        let duration = max(wall, max(micDuration, systemDuration))
        Log.audio.info("capture stopped wall=\(wall) mic=\(micDuration) sys=\(systemDuration) produced=\(produced)")
        if let why = systemEvidence.failureReason {
            Log.audio.error("system stream unusable: \(why, privacy: .public)")
        }

        let micURL = dir.appendingPathComponent("mic.wav")
        let sysURL = dir.appendingPathComponent("system.wav")
        let fm = FileManager.default
        return CapturedStreams(
            micURL: fm.fileExists(atPath: micURL.path) ? micURL : nil,
            systemURL: (produced && fm.fileExists(atPath: sysURL.path)) ? sysURL : nil,
            duration: duration,
            systemCaptured: produced,
            micEvidence: micEvidence,
            systemEvidence: systemEvidence,
            micRate: micRate,
            systemRate: systemRate,
            systemTapEstablished: tapEstablished,
            micEndedEarly: mic.endedEarlyReason,
            micContinuity: micResult.continuity,
            systemContinuity: systemResult.continuity,
            streamStartOffset: offset,
            outputDevice: outputDevice.result,
            outputDeviceChanged: outputDevice.changedDuringSession,
            micLedger: micResult.ledger,
            systemLedger: systemResult.ledger,
            micPressure: micResult.pressure,
            systemPressure: systemResult.pressure,
            startTiming: timing)
    }

    /// Mutes only the Mic Stream. The System Stream — the far end of the meeting —
    /// keeps recording, which is the whole point: you stop contributing the room
    /// without losing the meeting.
    var isMicMuted: Bool {
        get { mic.isMuted }
        set { mic.isMuted = newValue }
    }

    func level(for stream: StreamKind) -> Float {
        switch stream {
        case .mic: return mic.level
        case .system: return system?.level ?? 0
        }
    }
}
