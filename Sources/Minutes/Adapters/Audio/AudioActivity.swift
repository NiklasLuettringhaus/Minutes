import Foundation
import AVFoundation
import Accelerate

/// Where a recording carries signal, frame by frame (FR-96).
///
/// The only evidence that separates a **gap** from **silence**: the engines
/// cannot help, because everything they report about an interval they produced
/// nothing for — `[BLANK_AUDIO]`, a high no-speech probability, no tokens at all
/// — describes silence, which is the opposite question. Signal was there and no
/// Utterance covers it is the statement that means the app failed.
///
/// Deliberately the same frame length and the same floor as `EchoAnalysis`, so a
/// frame is the same unit everywhere in this increment and an interval excluded
/// as Echo lines up exactly with a frame here.
enum AudioActivity {

    /// A per-frame "carried signal" mask for one file.
    static func mask(of url: URL,
                     frameSeconds: TimeInterval = EchoAnalysis.frameSeconds)
        throws -> (active: [Bool], frameSeconds: TimeInterval) {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else {
            throw MinutesError.transcriptionFailed(
                "Could not read \(url.lastPathComponent) to look for gaps.")
        }
        let format = file.processingFormat
        guard format.commonFormat == .pcmFormatFloat32, format.channelCount > 0 else {
            throw MinutesError.transcriptionFailed(
                "\(url.lastPathComponent) is not in a format Minutes can scan.")
        }
        let channels = Int(format.channelCount)
        let frameLength = max(1, Int(format.sampleRate * frameSeconds))
        let chunk = AVAudioFrameCount(frameLength * 8)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw MinutesError.transcriptionFailed("Could not allocate a scan buffer.")
        }

        var out: [Bool] = []
        out.reserveCapacity(Int(file.length) / frameLength + 1)
        var carry: [Float] = []
        while file.framePosition < file.length {
            buffer.frameLength = 0
            do { try file.read(into: buffer, frameCount: chunk) } catch { break }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            carry.reserveCapacity(carry.count + frames)
            if channels == 1 {
                carry.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
            } else {
                let scale = 1.0 / Float(channels)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += data[c][f] }
                    carry.append(sum * scale)
                }
            }
            while carry.count >= frameLength {
                out.append(Self.isActive(Array(carry[0..<frameLength])))
                carry.removeFirst(frameLength)
            }
        }
        if !carry.isEmpty { out.append(Self.isActive(carry)) }
        return (out, frameSeconds)
    }

    private static func isActive(_ frame: [Float]) -> Bool {
        var peak: Float = 0
        vDSP_maxmgv(frame, 1, &peak, vDSP_Length(frame.count))
        return peak >= EchoAnalysis.activityFloor
    }
}
