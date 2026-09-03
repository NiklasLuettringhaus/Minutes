import Foundation

/// FR-88: assess a recording already on disk, and repair a declared rate that is
/// demonstrably wrong.
///
/// This exists because seven recordings were repaired by hand on 2026-09-03,
/// before any of this code did. A fix that lives in a script somebody ran once is
/// not a fix for the next person — and the next person is a colleague with a
/// Bluetooth headset who has never seen this repository.
///
/// **What it changes: four bytes.** The samples are complete and intact; only the
/// header's claim about their rate is wrong. So the repair rewrites `sampleRate`
/// and `byteRate` in the `fmt ` chunk and touches nothing else. No resampling, no
/// re-encoding, no re-writing of the audio, and the original declared rate is
/// returned so the change is reversible.
enum WavRateRepair {

    /// What a file on disk says about itself.
    struct Header: Equatable, Sendable {
        var channels: Int
        var declaredRate: Double
        var bitsPerSample: Int
        var dataBytes: Int
        /// Byte offset of the `fmt ` chunk's payload, for the repair write.
        var formatOffset: Int

        var frames: Int { dataBytes / max(1, channels * bitsPerSample / 8) }
    }

    enum RepairError: LocalizedError {
        case notAWaveFile
        case noFormatChunk
        case rateNotRecoverable(observed: Double, declared: Double)

        var errorDescription: String? {
            switch self {
            case .notAWaveFile: return "That file is not a WAVE recording."
            case .noFormatChunk: return "That recording has no readable format header."
            case .rateNotRecoverable(let o, let d):
                return String(format:
                    "The true rate cannot be worked out from this recording: it holds %.0f Hz of "
                    + "audio against a declared %.0f Hz, which is not a whole-number factor. "
                    + "Repairing it would be guessing.", o, d)
            }
        }
    }

    /// Reads the header without reading the audio.
    static func header(of url: URL) throws -> Header {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        guard let head = try h.read(upToCount: 8192), head.count > 44,
              head.prefix(4) == Data("RIFF".utf8),
              head[8..<12] == Data("WAVE".utf8) else { throw RepairError.notAWaveFile }

        let total = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var pos = 12
        var fmt: (Int, Double, Int, Int)?     // channels, rate, bits, offset
        var dataBytes: Int?
        while pos + 8 <= head.count {
            let id = head[pos..<(pos + 4)]
            let size = Int(u32(head, pos + 4))
            if id == Data("fmt ".utf8) {
                let o = pos + 8
                let channels = Int(u16(head, o + 2))
                let rate = Double(u32(head, o + 4))
                let bits = Int(u16(head, o + 14))
                fmt = (channels, rate, bits, o)
            } else if id == Data("data".utf8) {
                dataBytes = min(size, max(0, total - (pos + 8)))
                break
            }
            pos += 8 + size + (size & 1)
        }
        guard let (channels, rate, bits, offset) = fmt else { throw RepairError.noFormatChunk }
        return Header(channels: channels, declaredRate: rate, bitsPerSample: bits,
                      dataBytes: dataBytes ?? 0, formatOffset: offset)
    }

    /// What this file's samples say about their own rate, given how long the
    /// Session actually ran.
    static func fidelity(of url: URL, sessionDuration: TimeInterval) throws -> RateFidelity {
        let h = try header(of: url)
        return RateFidelity(declaredRate: h.declaredRate,
                            framesObserved: Double(h.frames),
                            elapsedSeconds: sessionDuration)
    }

    /// Rewrites the declared rate to the true one. Returns what it changed.
    ///
    /// The true rate is `declared / integerRatio`, **not** the raw observation.
    /// The observation reads a few per mil low because the wall clock includes the
    /// moments before the first sample arrived and after the last — which is how a
    /// true 8000 Hz measured as 7919 to 7996 across five real recordings. Snapping
    /// to the integer factor removes that noise; refusing when there is no integer
    /// factor is what keeps this from guessing at a different defect.
    @discardableResult
    static func repair(_ url: URL, sessionDuration: TimeInterval) throws -> (was: Double, now: Double) {
        let f = try fidelity(of: url, sessionDuration: sessionDuration)
        guard let ratio = f.integerRatio else {
            throw RepairError.rateNotRecoverable(observed: f.observedRate, declared: f.declaredRate)
        }
        let h = try header(of: url)
        let trueRate = (h.declaredRate / Double(ratio)).rounded()

        let fh = try FileHandle(forUpdating: url)
        defer { try? fh.close() }
        try fh.seek(toOffset: UInt64(h.formatOffset + 4))
        try fh.write(contentsOf: le32(UInt32(trueRate)))
        try fh.seek(toOffset: UInt64(h.formatOffset + 8))
        try fh.write(contentsOf: le32(UInt32(trueRate * Double(h.channels * h.bitsPerSample / 8))))
        try fh.synchronize()

        Log.audio.info("repaired \(url.lastPathComponent, privacy: .public): \(h.declaredRate, privacy: .public) Hz -> \(trueRate, privacy: .public) Hz")
        return (h.declaredRate, trueRate)
    }

    // MARK: - Little-endian scalars

    private static func u16(_ d: Data, _ o: Int) -> UInt16 {
        UInt16(d[o]) | UInt16(d[o + 1]) << 8
    }
    private static func u32(_ d: Data, _ o: Int) -> UInt32 {
        UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
    }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
              UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
    }
}
