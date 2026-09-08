import Foundation
import CoreAudio

/// `--check-device-switch [seconds]` — FR-106, AD-60.
///
/// Records both Streams, changes the **default input device** at the halfway
/// mark, and reports what survived. It is the measurement FR-106 rests on, and
/// it exists because the fault it covers was found in a user's recordings rather
/// than by anything in this repository: one call became three recordings and the
/// only evidence was two Meeting records with different microphones in them.
///
/// The switch is performed the way macOS performs it — by setting
/// `kAudioHardwarePropertyDefaultInputDevice` — so what the app sees is what it
/// sees when AirPods connect. **The device is put back on the way out**, on
/// every path including a failure, because leaving someone's input device
/// changed is not an acceptable cost of a diagnostic.
///
/// **It creates no Meeting and keeps no audio.** Like `--check-clock`, it writes
/// to a temporary directory that is removed on exit, and prints rates, counts
/// and milliseconds — never a title, never a transcript line (PRD §9.1).
///
/// It needs two input devices to have anything to say. With one it says so and
/// stops rather than reporting a switch that did not happen.
enum DeviceSwitchCheck {

    static func run() {
        let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 20
        // `--before` measures the behaviour this fix replaces, so the figures in
        // the note have a command behind both halves.
        if CommandLine.arguments.contains("--before") {
            MicCapture.suppressDeviceRebuildForMeasurement = true
        }
        let sem = DispatchSemaphore(value: 0)
        Task {
            await go(seconds: max(6, min(3600, seconds)))
            sem.signal()
        }
        // The main thread pumps rather than blocks: AVAudioEngine needs a live
        // run loop, exactly as `ClockCheck` does.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

    private static func go(seconds: Double) async {
        print("=== Minutes: input device switch check ===")
        if MicCapture.suppressDeviceRebuildForMeasurement {
            print("  MEASURING THE OLD BEHAVIOUR: the device-change rebuild is suppressed")
        }

        let inputs = Devices.inputs()
        guard let original = Devices.defaultInput() else {
            print("no default input device; nothing to measure")
            return
        }
        guard let target = inputs.first(where: { $0 != original }) else {
            print("""
                only one input device on this Mac, so there is no switch to make.
                Connect a second one — a USB microphone or AirPods — and run this again.
                """)
            return
        }

        print("  from: \(Devices.name(original)) at \(Devices.rate(original)) Hz")
        print("  to:   \(Devices.name(target)) at \(Devices.rate(target)) Hz")
        if Devices.rate(original) == Devices.rate(target) {
            print("""
                  note: both devices run at the same rate, so this exercises the
                        engine rebuild but not the converter retune. A 48 kHz
                        device and a 24 kHz one (AirPods) exercise both.
                """)
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-devswitch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            // The device first, then the scratch audio. In that order, because
            // the device is the user's and the directory is only ours.
            Devices.setDefaultInput(original)
            try? FileManager.default.removeItem(at: dir)
        }

        let capture = DualStreamCapture()
        do { try capture.start(into: dir) } catch {
            print("could not start capture: \(error.localizedDescription)")
            return
        }
        print("\nrecording \(Int(seconds))s — switching input device at the halfway mark")

        let half = seconds / 2
        try? await Task.sleep(nanoseconds: UInt64(half * 1e9))
        let switchedAt = Date()
        let ok = Devices.setDefaultInput(target)
        print("  switch \(ok ? "applied" : "FAILED") at +\(Int(half))s")
        try? await Task.sleep(nanoseconds: UInt64((seconds - half) * 1e9))

        let streams = capture.stop()
        let elapsed = Date().timeIntervalSince(switchedAt)

        print("\n--- what survived ---")
        print("  session ran           \(fmt(streams.duration)) s of a \(Int(seconds)) s capture")
        if let why = streams.micEndedEarly {
            print("  MIC STREAM ENDED EARLY: \(why)")
        } else {
            print("  mic stream            survived the change")
        }
        print("  system stream         \(streams.systemCaptured ? "captured" : "PRODUCED NO AUDIO")")

        // The number that matters: a mic that died at the switch leaves a file
        // about half the length of the capture.
        let expectedAfter = elapsed
        print("""
              mic audio after the switch, if the file is as long as the capture,
                is \(fmt(expectedAfter)) s of the \(fmt(streams.duration)) s total
            """)

        for (label, ledger, rate) in [
            ("mic", streams.micLedger, streams.micRate),
            ("system", streams.systemLedger, streams.systemRate),
        ] {
            print("\n  \(label) stream")
            if ledger.isMeasured || ledger.isWriterMeasured {
                print("    device \(Int(ledger.deviceFrames)) in -> dropped \(Int(ledger.droppedFrames)), consumed \(Int(ledger.consumedFrames)), written \(Int(ledger.writtenFrames)) out")
                print("    unaccounted \(Int(ledger.unaccountedFrames)) in; never converted \(Int(ledger.unproducedFrames)) out")
                if let counted = ledger.expectedOutputFrames {
                    print("    expected output counted per rate: \(Int(counted)) frames (the device changed rate)")
                } else {
                    print("    expected output derived from one rate: \(Int(ledger.expectedWrittenFrames)) frames")
                }
            } else {
                print("    not measured")
            }
            print("    rate: \(rate.source.rawValue) declared \(fmt(rate.declaredRate)) Hz observed \(fmt(rate.observedRate)) Hz")
            if let why = rate.explanation { print("    rate says: \(why)") }
        }

        print("""

            --- what this does not measure ---
            Whether the *detector* would have ended the Session. That is
            DetectionWindow's job and it is covered by tests; here there is no
            watched app holding the device, so nothing decides the meeting is
            over. Prove that half with a real call.
            """)
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

    /// The three CoreAudio reads and one write this command needs. Kept local:
    /// `SystemTapCapture` has its own device helpers for the *output* side and
    /// merging them would put a setter next to a capture path that must never
    /// have one.
    private enum Devices {

        static func inputs() -> [AudioDeviceID] {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                                 &a, 0, nil, &size) == noErr, size > 0 else { return [] }
            var ids = [AudioDeviceID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &a, 0, nil, &size, &ids) == noErr else { return [] }
            // Input channels only. A device with none is not a candidate, and
            // the tap's own aggregate must never be one either.
            return ids.filter { inputChannels($0) > 0 && !name($0).hasPrefix("Minutes") }
        }

        static func inputChannels(_ d: AudioDeviceID) -> Int {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(d, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
            let p = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
            defer { p.deallocate() }
            guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, p) == noErr else { return 0 }
            let list = UnsafeMutableAudioBufferListPointer(
                p.assumingMemoryBound(to: AudioBufferList.self))
            return list.reduce(0) { $0 + Int($1.mNumberChannels) }
        }

        static func name(_ d: AudioDeviceID) -> String {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<CFString?>.size)
            var out: Unmanaged<CFString>?
            let st = withUnsafeMutablePointer(to: &out) {
                AudioObjectGetPropertyData(d, &a, 0, nil, &size, $0)
            }
            guard st == noErr else { return "device \(d)" }
            return out?.takeRetainedValue() as String? ?? "device \(d)"
        }

        static func rate(_ d: AudioDeviceID) -> Double {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var r = Double(0)
            var size = UInt32(MemoryLayout<Double>.size)
            guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, &r) == noErr else { return 0 }
            return r
        }

        static func defaultInput() -> AudioDeviceID? {
            var d = AudioDeviceID(0)
            var a = address
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &a, 0, nil, &size, &d) == noErr, d != 0 else { return nil }
            return d
        }

        @discardableResult
        static func setDefaultInput(_ d: AudioDeviceID) -> Bool {
            var value = d
            var a = address
            let st = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                UInt32(MemoryLayout<AudioDeviceID>.size), &value)
            if st != noErr { Log.audio.error("SetDefaultInputDevice -> \(st)") }
            return st == noErr
        }

        private static var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}
