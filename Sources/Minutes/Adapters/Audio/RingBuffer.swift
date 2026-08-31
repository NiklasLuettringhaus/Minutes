import Foundation

/// Single-producer / single-consumer float ring buffer.
///
/// The CoreAudio IOProc must be real-time safe — no allocation, no locks, no
/// logging (architecture convention). It therefore only ever memcpy's into this
/// preallocated storage; a consumer thread drains it to disk.
final class RingBuffer {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writeIndex = 0          // producer only
    private var readIndex = 0           // consumer only
    private let lock = NSLock()         // guards the indices only, never the audio copy

    /// Set when the producer had to drop samples because the consumer fell behind.
    private(set) var didOverflow = false

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
        let n = min(count, available)
        if n < count { didOverflow = true }
        var idx = writeIndex
        lock.unlock()

        // The copy itself happens outside the lock: only this thread advances writeIndex.
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

    /// Zeroed on stop, or stale samples bleed into the next recording.
    func reset() {
        lock.lock()
        writeIndex = 0; readIndex = 0; didOverflow = false
        storage.update(repeating: 0, count: capacity)
        lock.unlock()
    }

    private func fillCountLocked() -> Int {
        writeIndex >= readIndex ? writeIndex - readIndex : capacity - readIndex + writeIndex
    }
}
