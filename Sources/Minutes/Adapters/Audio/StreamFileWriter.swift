import Foundation
import AVFoundation

/// Drains a RingBuffer to a WAV file on a background thread.
///
/// Audio is committed to disk incrementally, never buffered in memory until stop,
/// so memory stays flat with respect to Session duration and a crash leaves the
/// captured audio recoverable (FR-9).
final class StreamFileWriter {
    private let url: URL
    private let format: AVAudioFormat
    private let ring: RingBuffer
    private var file: AVAudioFile?
    private var thread: Thread?
    private var running = false
    private(set) var framesWritten: AVAudioFramePosition = 0
    private(set) var peak: Float = 0

    init(url: URL, format: AVAudioFormat, ring: RingBuffer) {
        self.url = url
        self.format = format
        self.ring = ring
    }

    func start() throws {
        // Write interleaved 32-bit float WAV; WhisperKit resamples on read.
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        settings[AVLinearPCMIsNonInterleaved] = false
        do {
            file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: true)
        } catch {
            throw MinutesError.audioFileWriteFailed(error.localizedDescription)
        }
        running = true
        let t = Thread { [weak self] in self?.drainLoop() }
        t.name = "minutes.writer.\(url.lastPathComponent)"
        t.qualityOfService = .utility
        thread = t
        t.start()
    }

    func stop() {
        running = false
        // Give the drain loop a moment to flush what is left.
        for _ in 0..<50 where ring.count > 0 { usleep(10_000) }
        drainOnce()
        file = nil
        thread = nil
    }

    var duration: TimeInterval {
        format.sampleRate > 0 ? Double(framesWritten) / format.sampleRate : 0
    }

    private func drainLoop() {
        while running {
            if ring.count == 0 { usleep(20_000); continue }
            drainOnce()
        }
    }

    private func drainOnce() {
        guard let file else { return }
        let channels = Int(format.channelCount)
        let wanted = 8192 * channels
        let samples = ring.read(max: wanted)
        guard !samples.isEmpty else { return }
        let frames = samples.count / max(1, channels)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        guard let dst = buf.floatChannelData?[0] else { return }
        var localPeak: Float = 0
        samples.withUnsafeBufferPointer { src in
            dst.update(from: src.baseAddress!, count: frames * channels)
            for i in 0..<(frames * channels) { localPeak = max(localPeak, abs(src[i])) }
        }
        peak = max(peak * 0.85, localPeak)
        do {
            try file.write(from: buf)
            framesWritten += AVAudioFramePosition(frames)
        } catch {
            Log.audio.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
