import Foundation

/// Single-producer / single-consumer float ring buffer.
///
/// The CoreAudio IOProc must be real-time safe — no allocation, no locks, no
/// logging (architecture convention). It therefore only ever memcpy's into this
/// preallocated storage; a consumer thread drains it to disk.
final class RingBuffer {
    private let storage: UnsafeMutablePointer<Float>
    let capacity: Int
    private var writeIndex = 0          // producer only
    private var readIndex = 0           // consumer only
    private let lock = NSLock()         // guards the indices only, never the audio copy

    /// Samples the producer had to drop because the consumer fell behind.
    ///
    /// **This used to be `didOverflow: Bool`, and it was read by nobody** — no
    /// caller, no record, no log line — for as long as this file has existed.
    /// It is the same shape of defect AD-51 found twice, where the device's own
    /// sample-time and host-time counters were parameters of every callback and
    /// bound to `_`.
    ///
    /// A Bool was also the wrong shape regardless of who read it. On one
    /// 42.4-minute recording the Mic Stream lost 22 ms and the System Stream lost
    /// 8.37 s — a factor of 380, and the only real clue the measurement carries.
    /// A flag renders those two identically (AD-58, FR-102).
    private(set) var droppedSamples = 0

    /// Separate occasions on which the producer had to drop anything.
    ///
    /// One overflow of eight seconds and eight hundred of ten milliseconds are
    /// different faults with the same total. Counting the occasions is what
    /// distinguishes a single stall from sustained inability to keep up, and it
    /// costs one increment on the audio thread.
    private(set) var overflowEvents = 0

    /// The largest backlog a *reader* ever found waiting here (FR-103).
    ///
    /// Deliberately updated on the **consumer's** side, inside `read`, from the
    /// fill it already computes. AD-58 keeps the producer to counters that cost
    /// an increment, and this is the consumer's own view of how far behind it
    /// was — which is the quantity that means something. The producer's view
    /// would peak at capacity on every overflow and say nothing new, because
    /// `droppedSamples` already says that.
    private(set) var highWaterFill = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Producer side. Called from the audio IO thread.
    func write(_ src: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        let available = capacity - fillCountLocked() - 1
        let n = max(0, min(count, available))
        if n < count {
            droppedSamples += count - n
            overflowEvents += 1
        }
        var idx = writeIndex
        lock.unlock()

        // The copy itself happens outside the lock: only this thread advances writeIndex.
        guard n > 0 else { return }
        var remaining = n
        var offset = 0
        while remaining > 0 {
            let chunk = min(remaining, capacity - idx)
            (storage + idx).update(from: src + offset, count: chunk)
            idx = (idx + chunk) % capacity
            offset += chunk
            remaining -= chunk
        }

        lock.lock(); writeIndex = idx; lock.unlock()
    }

    /// Consumer side. Returns up to `max` samples.
    func read(max maxCount: Int) -> [Float] {
        lock.lock()
        let fill = fillCountLocked()
        if fill > highWaterFill { highWaterFill = fill }
        let n = min(maxCount, fill)
        var idx = readIndex
        lock.unlock()
        guard n > 0 else { return [] }

        var out = [Float](repeating: 0, count: n)
        out.withUnsafeMutableBufferPointer { dst in
            var remaining = n, offset = 0
            while remaining > 0 {
                let chunk = min(remaining, capacity - idx)
                dst.baseAddress!.advanced(by: offset).update(from: storage + idx, count: chunk)
                idx = (idx + chunk) % capacity
                offset += chunk
                remaining -= chunk
            }
        }
        lock.lock(); readIndex = idx; lock.unlock()
        return out
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return fillCountLocked()
    }

    /// Every counter, read together under the lock.
    ///
    /// The individual `private(set)` properties are written under the lock and
    /// were being read without it, which is benign in practice — the producer is
    /// always stopped before the writer reads them — and is a race by the
    /// memory model for no benefit. Reading them as one tuple also means the
    /// four numbers describe the same instant, which is the property the
    /// accounting identity rests on.
    var counters: (dropped: Int, overflows: Int, highWater: Int, resident: Int) {
        lock.lock(); defer { lock.unlock() }
        return (droppedSamples, overflowEvents, highWaterFill, fillCountLocked())
    }

    /// Zeroed on stop, or stale samples bleed into the next recording.
    func reset() {
        lock.lock()
        writeIndex = 0; readIndex = 0
        droppedSamples = 0; overflowEvents = 0; highWaterFill = 0
        storage.update(repeating: 0, count: capacity)
        lock.unlock()
    }

    private func fillCountLocked() -> Int {
        writeIndex >= readIndex ? writeIndex - readIndex : capacity - readIndex + writeIndex
    }
}
