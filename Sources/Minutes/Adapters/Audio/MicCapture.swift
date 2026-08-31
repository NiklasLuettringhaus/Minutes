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

    func stop() -> TimeInterval {
        guard isRunning else { return 0 }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let d = writer?.duration ?? 0
        writer?.stop()
        ring?.reset()
        writer = nil; ring = nil
        isRunning = false
        Log.audio.info("mic capture stopped duration=\(d)")
        return d
    }

    var level: Float { writer?.peak ?? 0 }
}
