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
    private var directory: URL?
    private var startedAt: Date?
    private(set) var isRunning = false
    private(set) var systemFailure: MinutesError?

    /// True when the System Stream is not being captured, so the UI can say so
    /// rather than degrade silently (FR-7).
    var isDegraded: Bool { isRunning && system?.isRunning != true }

    func start(into dir: URL) throws {
        guard !isRunning else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directory = dir
        systemFailure = nil

        // Mic first: it is the stream we cannot do without, and it is the one with
        // a real permission API.
        try mic.start(url: dir.appendingPathComponent("mic.wav"))

        // System tap second, and never fatal. Its failure degrades the Session.
        let tap = SystemTapCapture()
        do {
            try tap.start(url: dir.appendingPathComponent("system.wav"))
            system = tap
        } catch let e as MinutesError {
            systemFailure = e
            system = nil
            Log.audio.error("system stream unavailable, continuing mic-only: \(e.localizedDescription, privacy: .public)")
        }

        startedAt = Date()
        isRunning = true
    }

    func stop() -> CapturedStreams {
        guard isRunning, let dir = directory else {
            return CapturedStreams(micURL: nil, systemURL: nil, duration: 0, systemCaptured: false)
        }
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
            micContinuity: micResult.continuity,
            systemContinuity: systemResult.continuity,
            streamStartOffset: offset)
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
