import Foundation
import CoreAudio

/// Reads what the audio is playing through, and keeps reading it (FR-98, AD-54).
///
/// A separate object from `SystemTapCapture` deliberately, even though that class
/// already listens for the same notification. Its listener exists to rebuild a
/// tap chain and only runs when the tap started; this question has to be
/// answerable on a mic-only Session (FR-7), which is the degraded case where the
/// far end reaches the microphone and nothing else records it.
///
/// It accumulates rather than samples. A user who starts a call on the built-in
/// speakers and puts AirPods in ten minutes later had an echo for ten minutes,
/// and `OutputDeviceKind.union` is what stops the last reading erasing that.
final class OutputDeviceMonitor {

    private let lock = NSLock()
    private var seen: [OutputDeviceKind] = []
    private var firstDevice: OutputDevice?
    private var installed = false

    /// The device at the moment this is asked, or nil when there is none.
    static func current() -> OutputDevice? {
        var dev = AudioDeviceID(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &dev) == noErr, dev != 0 else {
            return nil
        }
        return OutputDevice(name: name(of: dev),
                            transport: fourCharacter(of: dev, kAudioDevicePropertyTransportType) ?? "",
                            dataSource: dataSource(of: dev))
    }

    func start() {
        sample()
        lock.lock(); let already = installed; installed = true; lock.unlock()
        guard !already else { return }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        let st = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &Self.address, Self.listener, ref)
        if st != noErr {
            Log.audio.error("output device listener -> \(st)")
            lock.lock(); installed = false; lock.unlock()
        }
    }

    func stop() {
        sample()
        lock.lock(); let was = installed; installed = false; lock.unlock()
        guard was else { return }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &Self.address, Self.listener, ref)
    }

    /// What the Session should record: the first device seen, carrying the union
    /// of every kind seen while it ran.
    ///
    /// The *name* is the first device's because a name is for a reader, and the
    /// *kind* is the union because the kind is what a decision is made on. Where
    /// they disagree — started on speakers, ended on AirPods — the union is the
    /// one that must not be softened.
    var result: OutputDevice? {
        lock.lock(); defer { lock.unlock() }
        guard var first = firstDevice else { return nil }
        first.kind = OutputDeviceKind.union(seen)
        return first
    }

    /// True when the device changed kind during the Session.
    var changedDuringSession: Bool {
        lock.lock(); defer { lock.unlock() }
        return Set(seen).count > 1
    }

    private func sample() {
        guard let device = Self.current() else {
            lock.lock(); seen.append(.unknown); lock.unlock()
            return
        }
        lock.lock()
        if firstDevice == nil { firstDevice = device }
        if seen.last != device.kind { seen.append(device.kind) }
        lock.unlock()
        Log.audio.info("""
            output device: \(device.transport, privacy: .public)\
            /\(device.dataSource ?? "-", privacy: .public) -> \
            \(device.kind.rawValue, privacy: .public)
            """)
    }

    deinit { stop() }

    private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static let listener: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData else { return noErr }
        let me = Unmanaged<OutputDeviceMonitor>.fromOpaque(clientData).takeUnretainedValue()
        // Off the notification thread, like the tap's own listener: CoreAudio
        // property reads must not run there.
        DispatchQueue.global(qos: .utility).async { me.sample() }
        return noErr
    }

    // MARK: - Property reads

    private static func name(of device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: Unmanaged<CFString>?
        let st = withUnsafeMutablePointer(to: &out) { p in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, p)
        }
        guard st == noErr else { return nil }
        return out?.takeRetainedValue() as String?
    }

    /// The data source of the *output* scope, which is what tells the headphone
    /// jack from the built-in speakers on the one device that is both.
    private static func dataSource(of device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return Self.text(value)
    }

    private static func fourCharacter(of device: AudioDeviceID,
                                      _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return Self.text(value)
    }

    /// A four-character code as the four characters it is.
    ///
    /// `kAudioDeviceTransportTypeUnknown` is **0**, which decodes to four NUL
    /// bytes — printable to nobody, comparable to nothing, and it would have been
    /// stored on the record and rendered in a diagnostic as four blanks. A code
    /// that is not four printable ASCII characters is no code at all. The space
    /// in `"usb "` is deliberate and must survive.
    static func text(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                     UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return "" }
        return String(decoding: bytes, as: UTF8.self)
    }
}
