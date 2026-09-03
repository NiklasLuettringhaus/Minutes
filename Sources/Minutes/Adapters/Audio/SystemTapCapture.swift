import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// The System Stream: everything the *other* participants say (AD-11).
///
/// Implements the CoreAudio process-tap sequence exactly as AD-1/AD-2/AD-3
/// require. Every one of those rules was established by running code, and each
/// exists because violating it fails **silently**:
///
///  - AD-1: `AudioDeviceCreateIOProcIDWithBlock` deadlocks indefinitely on a
///    tap-backed aggregate device. Only the C-function-pointer variant works.
///  - AD-2: fixed construction/teardown order, on every path.
///  - AD-3: never assume the format; query `kAudioTapPropertyFormat`.
final class SystemTapCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioDeviceID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: StreamFileWriter?
    private var ring: RingBuffer?
    private(set) var isRunning = false
    private(set) var format: AVAudioFormat?

    /// Passed to the C IOProc as its refCon, because a C function pointer cannot
    /// capture Swift context (AD-1).
    private var selfRef: Unmanaged<SystemTapCapture>?

    func start(url: URL) throws {
        try buildDeviceChain()

        guard let fmt = format, let asbd = fmt.streamDescription.pointee as AudioStreamBasicDescription? else {
            teardown()
            throw MinutesError.systemAudioTapFailed(stage: "resolve format", status: -1)
        }
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let r = RingBuffer(capacity: Int(asbd.mSampleRate) * channels * 10)
        ring = r
        let w = StreamFileWriter(url: url, format: fmt, ring: r)
        // FR-84: the user finds out during the meeting, not at the end.
        //
        // This was claimed in the requirement and left unwired in the first pass:
        // the writer raised the callback and nobody subscribed, so a disagreement
        // only surfaced at stop. A requirement whose code does not implement it is
        // worse than an unwritten one, because the document says it is done.
        w.onRateDisagreement = { fidelity in
            Task { @MainActor in
                if let corrected = fidelity.correctedTo {
                    // Corrected, so this is information rather than a failure —
                    // and it is worth saying, because the alternative is the app
                    // quietly compensating for a broken device for ever.
                    Log.audio.info("system stream rate corrected to \(corrected, privacy: .public) Hz mid-recording")
                } else if let why = fidelity.explanation {
                    AppState.shared.lastError = .captureRateMismatch(
                        stream: "the far end of the call", detail: why)
                }
            }
        }
        try w.start()
        writer = w

        try startIO()
        isRunning = true
        observeDeviceChanges()
    }

    /// Rebuilds ONLY the CoreAudio objects, against whatever the default output
    /// device now is. The RingBuffer and StreamFileWriter survive, so the
    /// recording continues into the same file with only a short gap (FR-8).
    private func rebuildForDeviceChange() {
        guard isRunning else { return }
        Log.audio.info("output device changed — rebuilding tap chain")
        let previous = format
        stopIO()
        destroyDeviceChain()
        do {
            try buildDeviceChain()
            // A format change mid-recording would corrupt the file we are already
            // writing. Degrade honestly rather than write wrong-rate samples.
            if let p = previous, let n = format,
               p.sampleRate != n.sampleRate || p.channelCount != n.channelCount {
                Log.audio.error("tap format changed across device switch (\(p.sampleRate)/\(p.channelCount) -> \(n.sampleRate)/\(n.channelCount)); stopping system stream")
                destroyDeviceChain()
                isRunning = false
                return
            }
            try startIO()
            Log.audio.info("tap chain rebuilt")
        } catch {
            Log.audio.error("tap rebuild failed: \(error.localizedDescription, privacy: .public)")
            isRunning = false
        }
    }

    private func buildDeviceChain() throws {
        // 1. Tap description. `init(stereoGlobalTapButExcludeProcesses:)` sets
        //    exclusive = true, meaning "tap everything EXCEPT these PIDs".
        //    Never mutate isExclusive afterwards — it inverts the meaning and
        //    silently captures nothing (AD-2).
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        desc.name = "Minutes System Audio"

        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        Log.audio.info("AudioHardwareCreateProcessTap -> \(st) tap=\(self.tapID)")
        guard st == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            throw MinutesError.systemAudioTapFailed(stage: "create tap", status: st)
        }

        // 2. Default output device and its UID.
        guard let outUID = Self.defaultOutputDeviceUID() else {
            teardown()
            throw MinutesError.noDefaultOutputDevice
        }

        // 3. Private aggregate: the REAL output device is the main sub-device and
        //    the tap rides as a sub-tap. TapAutoStart must be true, or callbacks
        //    fire with every sample zero (AD-2).
        let aggUID = "dev.niklas.minutes.agg.\(UUID().uuidString)"
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Minutes Capture",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregateID)
        Log.audio.info("AudioHardwareCreateAggregateDevice -> \(st) agg=\(self.aggregateID)")
        guard st == noErr, aggregateID != 0 else {
            teardown()
            throw MinutesError.systemAudioTapFailed(stage: "create aggregate device", status: st)
        }

        // 4. Query the tap's real format — never assume it (AD-3).
        var asbd = AudioStreamBasicDescription()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        st = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd)
        guard st == noErr, asbd.mSampleRate > 0,
              let fmt = AVAudioFormat(streamDescription: &asbd) else {
            teardown()
            throw MinutesError.systemAudioTapFailed(stage: "read tap format", status: st)
        }
        format = fmt
        Log.audio.info("tap format sr=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) flags=\(asbd.mFormatFlags)")

    }

    // 5 & 6. IOProc with a C function pointer, then start. NOT the block variant (AD-1).
    private func startIO() throws {
        selfRef = Unmanaged.passRetained(self)
        var st = AudioDeviceCreateIOProcID(aggregateID, Self.ioProc,
                                           selfRef!.toOpaque(), &ioProcID)
        Log.audio.info("AudioDeviceCreateIOProcID -> \(st)")
        guard st == noErr, let proc = ioProcID else {
            throw MinutesError.systemAudioTapFailed(stage: "create IOProc", status: st)
        }
        st = AudioDeviceStart(aggregateID, proc)
        Log.audio.info("AudioDeviceStart -> \(st)")
        guard st == noErr else {
            throw MinutesError.systemAudioTapFailed(stage: "start device", status: st)
        }
        logTapFormatAfterStart()
    }

    /// Story 15.7 / AD-3 as amended. Re-reads the tap's format once the device is
    /// actually running.
    ///
    /// The format used to be read only at step 4, immediately after
    /// `AudioHardwareCreateAggregateDevice` — a claim about that instant, not about
    /// what the device goes on to deliver. That is the located mechanism of the
    /// sample-rate defect: with a Bluetooth headset as the *input* device the
    /// shared clock moves, and the app resampled as though it had not.
    ///
    /// It logs rather than corrects, deliberately. A disagreement here is a
    /// *second* signal on the same fact that AD-44 already measures from the
    /// samples, and the measured one is the trustworthy one — this reading is the
    /// same API that was wrong before. So the observable stays authoritative and
    /// this exists to say, in the log of a future failure, whether CoreAudio's own
    /// answer had changed by the time capture started.
    private func logTapFormatAfterStart() {
        var asbd = AudioStreamBasicDescription()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let st = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd)
        guard st == noErr, asbd.mSampleRate > 0 else {
            Log.audio.error("could not re-read tap format after start (OSStatus \(st))")
            return
        }
        let declared = format?.sampleRate ?? 0
        if abs(asbd.mSampleRate - declared) > 1 {
            // Not a thrown error: the writer's own measurement decides, and this
            // reading has already been proven capable of being wrong.
            Log.audio.error("tap format CHANGED between creation and start: \(declared, privacy: .public) -> \(asbd.mSampleRate, privacy: .public) Hz; the writer's measured rate decides")
        } else {
            Log.audio.info("tap format after start confirms \(asbd.mSampleRate, privacy: .public) Hz")
        }
    }

    private func stopIO() {
        if let proc = ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        selfRef?.release(); selfRef = nil
    }

    /// What the capture can honestly claim. This is the only evidence available
    /// that system-audio capture worked, because macOS exposes no API to query
    /// the permission (FR-42) — so it is derived from the samples and never from
    /// elapsed time (AD-36).
    func stop() -> (duration: TimeInterval, evidence: AudioEvidence, rate: RateFidelity) {
        // Hold the writer past teardown: teardown calls writer.stop(), which is
        // what flushes the remainder of the ring. Reading the counters before it
        // under-reports the tail.
        let w = writer
        // Read the rate *before* teardown. Its denominator is wall time since
        // start, which keeps running while teardown flushes — so reading it after
        // would divide the same frames by a longer elapsed and invent a
        // disagreement on every recording.
        let r = w?.rateFidelity ?? .unknown
        teardown()
        let e = w?.evidence ?? .none
        Log.audio.info("system capture stopped duration=\(e.duration) peak=\(e.peak) nonSilent=\(e.nonSilentSeconds) producedAudio=\(e.producedAudio) declaredRate=\(r.declaredRate) observedRate=\(r.observedRate)")
        if let why = e.failureReason {
            Log.audio.error("system stream produced no usable audio: \(why, privacy: .public)")
        }
        if let why = r.explanation {
            Log.audio.error("system stream rate: \(why, privacy: .public)")
        }
        return (e.duration, e, r)
    }

    var level: Float { writer?.peak ?? 0 }

    /// AD-2: strict reverse order, and it runs on error paths too. A leaked
    /// aggregate device is visible system-wide.
    private func destroyDeviceChain() {
        if aggregateID != 0 {
            let st = AudioHardwareDestroyAggregateDevice(aggregateID)
            if st != noErr { Log.audio.error("DestroyAggregateDevice -> \(st)") }
            aggregateID = 0
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            let st = AudioHardwareDestroyProcessTap(tapID)
            if st != noErr { Log.audio.error("DestroyProcessTap -> \(st)") }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func teardown() {
        unobserveDeviceChanges()
        stopIO()
        destroyDeviceChain()
        writer?.stop(); writer = nil
        ring?.reset(); ring = nil
        isRunning = false
    }

    // MARK: - Output device changes (FR-8)

    private var deviceListenerInstalled = false

    private static var deviceChangeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private func observeDeviceChanges() {
        guard !deviceListenerInstalled else { return }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        let st = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.deviceChangeAddress,
            Self.deviceChangeListener,
            ref)
        deviceListenerInstalled = (st == noErr)
        Log.audio.info("AudioObjectAddPropertyListener(defaultOutputDevice) -> \(st)")
    }

    private func unobserveDeviceChanges() {
        guard deviceListenerInstalled else { return }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.deviceChangeAddress,
            Self.deviceChangeListener,
            ref)
        deviceListenerInstalled = false
    }

    private static let deviceChangeListener: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData else { return noErr }
        let me = Unmanaged<SystemTapCapture>.fromOpaque(clientData).takeUnretainedValue()
        // Rebuild off the notification thread; CoreAudio setup must not run here.
        DispatchQueue.global(qos: .userInitiated).async { me.rebuildForDeviceChange() }
        return noErr
    }

    deinit { teardown() }

    // MARK: - Real-time IO callback

    /// No allocation, no locks beyond the ring's index guard, no logging
    /// (architecture convention). Context arrives via refCon because a C function
    /// pointer cannot capture Swift state.
    private static let ioProc: AudioDeviceIOProc = { _, _, inInputData, _, _, _, clientData in
        guard let clientData else { return noErr }
        let me = Unmanaged<SystemTapCapture>.fromOpaque(clientData).takeUnretainedValue()
        guard let ring = me.ring else { return noErr }

        let list = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inInputData))
        // Handle interleaved, non-interleaved and mono by inspecting the list —
        // never by indexing past mBuffers.0 (AD-3).
        if list.count == 1 {
            let b = list[0]
            if let md = b.mData {
                ring.write(md.assumingMemoryBound(to: Float.self),
                           count: Int(b.mDataByteSize) / 4)
            }
        } else {
            for b in list {
                if let md = b.mData {
                    ring.write(md.assumingMemoryBound(to: Float.self),
                               count: Int(b.mDataByteSize) / 4)
                }
            }
        }
        return noErr
    }

    // MARK: - Device helpers

    static func defaultOutputDeviceUID() -> String? {
        var dev = AudioDeviceID(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                        &addr, 0, nil, &size, &dev) == noErr else { return nil }
        return deviceUID(dev)
    }

    static func deviceUID(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: Unmanaged<CFString>?
        let st = withUnsafeMutablePointer(to: &out) { p in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, p)
        }
        guard st == noErr else { return nil }
        return out?.takeUnretainedValue() as String?
    }
}
