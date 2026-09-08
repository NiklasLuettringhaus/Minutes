import Foundation
import AVFoundation

/// The Mic Stream: the local user, attributed structurally (AD-11).
/// There is no AVAudioSession on macOS — do not port iOS session code.
final class MicCapture {
    private let engine = AVAudioEngine()
    private var writer: StreamFileWriter?
    private var ring: RingBuffer?
    private var clock: AudioClockTap?
    private(set) var isRunning = false
    private(set) var format: AVAudioFormat?
    private var configObserver: NSObjectProtocol?
    /// Serialises a device-change rebuild against `stop()`. The rebuild arrives
    /// on a background queue and `stop()` frees the writer it is retuning.
    private let lifecycle = NSLock()
    /// Set when a device change could not be absorbed, so `stop()` can say the
    /// Mic Stream ended early rather than let a short file look complete.
    private(set) var endedEarlyReason: String?

    // MARK: - Surviving an input device change (FR-106, AD-60)

    /// `AVAudioEngine` stops itself when the input hardware changes and
    /// invalidates the tap installed on the input node. **Nothing observed this
    /// notification**, in a class whose System Stream counterpart has had a full
    /// rebuild path for its own device change since FR-8 — so putting AirPods in
    /// mid-meeting silently ended the microphone, and the only reason it had not
    /// been noticed is that the detector was ending the whole Session two
    /// seconds later anyway.
    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // Off the notification thread. Restarting an engine and reading
            // CoreAudio properties are both forbidden there, for the same reason
            // the tap's own listener hops off it.
            DispatchQueue.global(qos: .userInitiated).async { self?.inputDeviceChanged() }
        }
    }

    /// Rebuilds onto the new device, into the same file.
    ///
    /// The output file is 16 kHz whatever the device does, so a rate change is
    /// absorbed by retuning the converter — the file needs no rewriting and not
    /// one sample already in it is touched. This is the case that matters on
    /// real hardware: the built-in microphone here declares 48 kHz and AirPods
    /// declare 24 kHz, so the ordinary act of putting AirPods in during a call
    /// changes the rate and a handler that only restarted the engine would have
    /// written the rest of the meeting at half speed.
    ///
    /// A change in *channel count* is not absorbed. The ring's interleaving and
    /// the writer's per-frame arithmetic are both built on one channel count,
    /// and the honest end of that road is to stop the Stream and say so rather
    /// than write frames nobody can interpret.
    private func inputDeviceChanged() {
        lifecycle.lock(); defer { lifecycle.unlock() }
        guard isRunning, let writer, let recording = format else { return }
        let input = engine.inputNode
        engine.stop()
        input.removeTap(onBus: 0)

        let fresh = input.outputFormat(forBus: 0)
        guard fresh.sampleRate > 0, fresh.channelCount > 0 else {
            endEarly("the new input device reported no usable format")
            return
        }
        guard fresh.channelCount == recording.channelCount else {
            endEarly("""
                the new input device is \(fresh.channelCount)-channel and this \
                recording is \(recording.channelCount)-channel
                """)
            return
        }
        guard let r = ring, let c = clock else {
            endEarly("the capture was torn down while the device changed")
            return
        }
        if fresh.sampleRate != writer.converterInputRate,
           !writer.retune(inputRate: fresh.sampleRate) {
            endEarly("could not convert from the new device's \(fresh.sampleRate) Hz")
            return
        }

        installTap(format: fresh, ring: r, clock: c)
        engine.prepare()
        do { try engine.start() } catch {
            endEarly("the engine would not restart: \(error.localizedDescription)")
            return
        }
        Log.audio.info("mic capture rebuilt across an input device change sr=\(fresh.sampleRate) ch=\(fresh.channelCount)")
    }

    /// **Deliberately does not clear `isRunning`.** `stop()` guards on it, so
    /// clearing it here would make the Session throw away every sample captured
    /// before the device changed — turning a partial recording into no recording
    /// at all, which is the opposite of the point. The engine is already stopped,
    /// so nothing further arrives; the writer still owns a file it will flush and
    /// close correctly.
    private func endEarly(_ why: String) {
        endedEarlyReason = why
        Log.audio.error("mic stream ends here: \(why, privacy: .public)")
    }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Everything that can be done before the device is running (AD-59).
    ///
    /// Split out of `start` so that the two Streams' devices can be started
    /// **adjacently**, with the tap chain's construction moved to before either
    /// of them rather than sitting between them. Every millisecond that used to
    /// pass between `engine.start()` here and `AudioDeviceStart` on the tap
    /// landed in FR-97's offset, and the microphone recorded through all of it.
    ///
    /// `engine.prepare()` is the expensive half — it allocates the render
    /// resources — and it is deliberately on this side of the line.
    func prepare(url: URL) throws {
        guard Self.authorizationStatus() == .authorized else {
            throw MinutesError.microphonePermissionDenied
        }
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw MinutesError.microphoneUnavailable("The input device reported no usable format.")
        }
        format = fmt

        // ~10 s of headroom; the writer thread drains continuously.
        let r = RingBuffer(capacity: Int(fmt.sampleRate) * Int(fmt.channelCount)
                           * StreamRingSizing.seconds)
        ring = r
        let w = StreamFileWriter(url: url, format: fmt, ring: r)
        let c = AudioClockTap()
        clock = c
        w.clock = c
        try w.start()
        writer = w

        installTap(format: fmt, ring: r, clock: c)
        observeConfigurationChanges()

        engine.prepare()
        Log.audio.info("mic capture prepared sr=\(fmt.sampleRate) ch=\(fmt.channelCount)")
    }

    /// The tap body, in one place because a device change has to reinstall it.
    ///
    /// `ring` and `clock` arrive as parameters and are captured directly rather
    /// than reached through `self`. That is deliberate and must stay: this
    /// closure runs on the audio thread on every buffer, and capturing `self`
    /// would put an ARC retain and release in it.
    private func installTap(format fmt: AVAudioFormat,
                            ring r: RingBuffer,
                            clock c: AudioClockTap) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buffer, when in
            guard let ch = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            // AD-51. The second argument was bound to `_` since this file was
            // written, and it is the device's own account of what it just
            // delivered — the sample counter and a host stamp for the same
            // instant. Both carry validity flags and an invalid one yields
            // nothing rather than a zero, because absent is unknown.
            if when.isSampleTimeValid, when.isHostTimeValid {
                c.record(sampleTime: Double(when.sampleTime),
                         hostTime: when.hostTime, frames: frames)
            }
            if buffer.format.isInterleaved {
                r.write(ch[0], count: frames * channels)
            } else if channels == 1 {
                r.write(ch[0], count: frames)
            } else {
                // Interleave non-interleaved input so the file format stays simple.
                var tmp = [Float](repeating: 0, count: frames * channels)
                for f in 0..<frames {
                    for c in 0..<channels { tmp[f * channels + c] = ch[c][f] }
                }
                tmp.withUnsafeBufferPointer { r.write($0.baseAddress!, count: tmp.count) }
            }
        }
    }

    /// Starts the device. Kept to the smallest possible amount of work, because
    /// the whole point of the split is that this call and the tap's equivalent
    /// happen next to each other (AD-59).
    func begin() throws {
        guard writer != nil else {
            throw MinutesError.microphoneUnavailable("prepare() was not called")
        }
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            if let o = configObserver {
                NotificationCenter.default.removeObserver(o)
                configObserver = nil
            }
            writer?.stop(); writer = nil; ring = nil; clock = nil
            throw MinutesError.microphoneUnavailable(error.localizedDescription)
        }
        isRunning = true
        Log.audio.info("mic capture started")
    }

    /// Prepare and begin in one call, for the one path with no second Stream to
    /// line up with: Voice Enrolment. (`TestPlayground` uses
    /// `DualStreamCapture`, so it gets the adjacent starts of AD-59.)
    func start(url: URL) throws {
        try prepare(url: url)
        try begin()
    }

    /// FR-10-adjacent: muting the microphone in Slack or Teams stops *their*
    /// outgoing stream; the macOS input device stays live and this capture keeps
    /// reading it. In the first real meeting that meant a conversation happening
    /// beside the user was recorded and transcribed throughout. This is the switch
    /// that does what muting in the meeting app looks like it should do.
    var isMuted: Bool {
        get { writer?.isMuted ?? false }
        set { writer?.isMuted = newValue }
    }

    /// Ends capture and reports what it can honestly claim (AD-36).
    ///
    /// Both figures are read **after** `writer.stop()`, because that call is what
    /// flushes the rest of the ring — its own comment records that draining only
    /// once "truncated the tail of every recording". Reading before it therefore
    /// under-reports, which for `duration` was a long-standing inaccuracy and for
    /// evidence would be a wrong verdict: on a five-second Test Playground where
    /// the speech lands late, the unflushed tail could hold all of the signal.
    func stop() -> StreamCaptureResult {
        lifecycle.lock(); defer { lifecycle.unlock() }
        if let o = configObserver {
            NotificationCenter.default.removeObserver(o)
            configObserver = nil
        }
        guard isRunning else { return StreamCaptureResult() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Hold the writer past the teardown so its counters can be read once it
        // has finished flushing.
        let w = writer
        // Before the flush, for the same reason as the system stream: the rate's
        // denominator is wall time and keeps running. (With the audio clock it
        // no longer does — both halves are frozen at the last callback — but the
        // wall-clock fallback is still live and the ordering must suit both.)
        let r = w?.rateFidelity ?? .unknown
        let cont = w?.continuity ?? .unknown
        let origin = w?.originHostSeconds
        w?.stop()
        // The ledger is read after the flush and **before** `ring.reset()`, for
        // two different reasons that both matter. `stop()` is what drains the
        // rest of the ring, so reading before it would report the tail as
        // resident rather than written; and `reset()` zeroes the drop counters,
        // so reading after it would report every recording as clean.
        let led = w?.ledger ?? .unknown
        let press = w?.drainPressure ?? .unknown
        ring?.reset()
        writer = nil; ring = nil; clock = nil
        isRunning = false
        let d = w?.duration ?? 0
        let e = w?.evidence ?? .none
        Log.audio.info("mic capture stopped duration=\(d) peak=\(e.peak) nonSilent=\(e.nonSilentSeconds) declaredRate=\(r.declaredRate) observedRate=\(r.observedRate) clock=\(r.source.rawValue, privacy: .public)")
        if let why = r.explanation {
            Log.audio.error("mic stream rate: \(why, privacy: .public)")
        }
        if let why = cont.explanation {
            Log.audio.error("mic stream continuity: \(why, privacy: .public)")
        }
        return StreamCaptureResult(duration: d, evidence: e, rate: r,
                                   continuity: cont, originHostSeconds: origin,
                                   ledger: led, pressure: press)
    }

    var level: Float { writer?.peak ?? 0 }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }
}
