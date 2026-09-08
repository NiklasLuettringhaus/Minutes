import Foundation

/// FR-9, FR-107: make the audio of an interrupted Session readable again.
///
/// A WAV file records the length of its audio in two size fields, and both are
/// written when the file is **closed**. A recording that ends because the process
/// died — a crash, a force quit, an installer replacing the app mid-Session —
/// therefore leaves every sample on disk under a header that says the audio is
/// **zero bytes long**. Every reader believes the header.
///
/// That is how FR-9's "a crash leaves the captured audio recoverable" came to be
/// true only on paper. Five Meetings on the author's machine sat at `captured`
/// carrying *"Invalid audio data provided. Must be at least 300ms of 16kHz
/// audio"* — three of them holding 26 minutes, 5 minutes and 3 minutes of real
/// conversation — and `Pipeline.resumeInterrupted` skips anything with a failure
/// recorded, so they were excluded permanently. Nothing was lost. Nothing was
/// readable either.
///
/// **What it changes: eight bytes.** The `data` chunk's size and the `RIFF`
/// size, computed from the bytes actually present. No sample is read, none is
/// written, nothing is resampled and nothing is re-encoded — the same discipline
/// as `WavRateRepair`, which repairs a different lie in the same header.
///
/// Deliberately separate from `WavRateRepair`. That one answers "this file says
/// the wrong rate"; this one answers "this file says it is empty and is not".
/// Folding them together would put two unrelated repairs behind one verdict, and
/// the rate repair explicitly refuses to guess where this one has nothing to
/// guess about.
enum WavTailRepair {

    /// What a file claims about its length, against what it holds.
    struct Assessment: Equatable, Sendable {
        /// Bytes of audio the header claims.
        var declaredDataBytes: Int
        /// Bytes of audio actually present, rounded down to a whole frame.
        var actualDataBytes: Int
        var bytesPerFrame: Int
        var sampleRate: Double
        /// Byte offset of the `data` chunk's size field, for the repair write.
        var dataSizeOffset: Int

        /// True when the header under-claims: the signature of a file that was
        /// never closed.
        ///
        /// **Only ever under-claiming.** A header claiming *more* than the file
        /// holds is a truncated or corrupt file, which is a different fault, and
        /// raising its claim would feed whatever follows the audio to the
        /// transcriber as if it were speech.
        var needsRepair: Bool { actualDataBytes > declaredDataBytes }

        /// Seconds of audio the repair would make readable.
        var recoverableSeconds: Double {
            guard sampleRate > 0, bytesPerFrame > 0 else { return 0 }
            return Double(actualDataBytes - declaredDataBytes)
                / (sampleRate * Double(bytesPerFrame))
        }
    }

    enum RepairError: LocalizedError {
        case notAWaveFile
        case noDataChunk

        var errorDescription: String? {
            switch self {
            case .notAWaveFile: return "That file is not a WAVE recording."
            case .noDataChunk: return "That recording has no audio chunk to measure."
            }
        }
    }

    /// Reads the header. Never reads the audio.
    static func assess(_ url: URL) throws -> Assessment {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        guard let head = try h.read(upToCount: 8192), head.count >= 44,
              head.prefix(4) == Data("RIFF".utf8),
              head[8..<12] == Data("WAVE".utf8) else { throw RepairError.notAWaveFile }

        let total = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        var pos = 12
        var rate: Double = 0
        var bytesPerFrame = 0
        while pos + 8 <= head.count {
            let id = head[pos..<(pos + 4)]
            let size = Int(u32(head, pos + 4))
            if id == Data("fmt ".utf8) {
                let o = pos + 8
                let channels = Int(u16(head, o + 2))
                rate = Double(u32(head, o + 4))
                let bits = Int(u16(head, o + 14))
                bytesPerFrame = max(1, channels * bits / 8)
            } else if id == Data("data".utf8) {
                let payload = pos + 8
                // Round down to a whole frame. A process killed mid-write can
                // leave a partial frame, and half a sample is not audio.
                let present = max(0, total - payload)
                let whole = bytesPerFrame > 0 ? (present / bytesPerFrame) * bytesPerFrame : present
                return Assessment(declaredDataBytes: min(size, present),
                                  actualDataBytes: whole,
                                  bytesPerFrame: bytesPerFrame,
                                  sampleRate: rate,
                                  dataSizeOffset: pos + 4)
            }
            // A zero-sized chunk that is not `data` would loop forever.
            guard size > 0 || id == Data("data".utf8) else { break }
            pos += 8 + size + (size & 1)
        }
        throw RepairError.noDataChunk
    }

    /// Repairs the two size fields, and returns what it did — or nil when the
    /// file was already consistent, which is the common case and must stay cheap.
    ///
    /// The returned assessment carries the original claim, so the change is
    /// reversible by writing `declaredDataBytes` back.
    @discardableResult
    static func repair(_ url: URL) throws -> Assessment? {
        guard let a = try stamp(url, sync: true) else { return nil }
        Log.audio.info("""
            repaired an unclosed recording: header claimed \
            \(a.declaredDataBytes, privacy: .public) bytes, file holds \
            \(a.actualDataBytes, privacy: .public); recovered \
            \(String(format: "%.1f", a.recoverableSeconds), privacy: .public)s
            """)
        return a
    }

    /// The write itself, without the log line — called both by `repair` after
    /// the fact and by `StreamFileWriter` *during* a recording (FR-107).
    ///
    /// Stamping while recording is what makes the file readable by anything at
    /// all after a crash, rather than only by a Minutes that knows to repair it.
    /// It is safe to run against a file `AVAudioFile` has open: the two size
    /// fields are at fixed low offsets and the audio is appended at the end, so
    /// the byte ranges never overlap, and `AVAudioFile`'s own close writes the
    /// correct final values over these.
    ///
    /// **It can only ever under-claim.** The length comes from the file's size
    /// on disk, which lags what the writer has buffered, and is rounded down to
    /// a whole frame. A header that claims less than the file holds costs the
    /// tail of a recording; one that claims more feeds whatever follows to the
    /// transcriber as speech.
    @discardableResult
    static func stamp(_ url: URL, sync: Bool) throws -> Assessment? {
        let a = try assess(url)
        guard a.needsRepair else { return nil }

        let h = try FileHandle(forUpdating: url)
        defer { try? h.close() }
        // `data` first. If the process dies between the two writes, a correct
        // data size under an under-claiming RIFF size is readable by every
        // reader that walks chunks; the reverse is not.
        try h.seek(toOffset: UInt64(a.dataSizeOffset))
        try h.write(contentsOf: le32(a.actualDataBytes))
        // RIFF size counts everything after the first eight bytes.
        let riff = a.dataSizeOffset + 4 + a.actualDataBytes - 8
        try h.seek(toOffset: 4)
        try h.write(contentsOf: le32(riff))
        // Not synchronised on the periodic stamp: a *process* death leaves the
        // page cache intact, which is the case this defends against, and an
        // fsync every few seconds on the drain thread is a hitch for nothing.
        if sync { try h.synchronize() }
        return a
    }

    // MARK: - Byte helpers

    private static func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[d.startIndex + i]) | UInt16(d[d.startIndex + i + 1]) << 8
    }

    private static func u32(_ d: Data, _ i: Int) -> UInt32 {
        var v: UInt32 = 0
        for b in (0..<4).reversed() { v = v << 8 | UInt32(d[d.startIndex + i + b]) }
        return v
    }

    private static func le32(_ v: Int) -> Data {
        let u = UInt32(truncatingIfNeeded: max(0, v))
        return Data([UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF),
                     UInt8((u >> 16) & 0xFF), UInt8((u >> 24) & 0xFF)])
    }
}
