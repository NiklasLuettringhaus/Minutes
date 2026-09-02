import Foundation
import AVFoundation

/// The Mic Stream: the local user, attributed structurally (AD-11).
/// There is no AVAudioSession on macOS — do not port iOS session code.
final class MicCapture {
    private let engine = AVAudioEngine()
    private var writer: StreamFileWriter?
    private var ring: RingBuffer?
    private(set) var isRunning = false
    private(set) var format: AVAudioFormat?

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(url: URL) throws {
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
        let r = RingBuffer(capacity: Int(fmt.sampleRate) * Int(fmt.channelCount) * 10)
        ring = r
        let w = StreamFileWriter(url: url, format: fmt, ring: r)
        try w.start()
        writer = w

        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buffer, _ in
            guard let ch = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
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

        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            w.stop(); writer = nil; ring = nil
            throw MinutesError.microphoneUnavailable(error.localizedDescription)
        }
        isRunning = true
        Log.audio.info("mic capture started sr=\(fmt.sampleRate) ch=\(fmt.channelCount)")
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
    func stop() -> (duration: TimeInterval, evidence: AudioEvidence) {
        guard isRunning else { return (0, .none) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Hold the writer past the teardown so its counters can be read once it
        // has finished flushing.
        let w = writer
        w?.stop()
        ring?.reset()
        writer = nil; ring = nil
        isRunning = false
        let d = w?.duration ?? 0
        let e = w?.evidence ?? .none
        Log.audio.info("mic capture stopped duration=\(d) peak=\(e.peak) nonSilent=\(e.nonSilentSeconds)")
        return (d, e)
    }

    var level: Float { writer?.peak ?? 0 }
}
