import Foundation
import Darwin

/// Carries `AudioClock` across the two threads that need it (AD-51).
///
/// The producer is the audio callback and the consumer is the writer's drain
/// thread, which is exactly `RingBuffer`'s shape — and this uses the same
/// `NSLock` for the same reason. Recording a tick is three `Double` compares and
/// a handful of adds under a lock held for nanoseconds, against a `memcpy` of up
/// to 8192 floats that the ring already does under the same discipline. Nothing
/// is allocated and nothing is logged on the audio thread.
///
/// It also owns the one platform fact `AudioClock` deliberately does not know:
/// how to turn a mach host time into seconds. Keeping that here is what lets the
/// decision type be tested with three literals.
final class AudioClockTap {

    private let lock = NSLock()
    private var clock = AudioClock()

    /// Mach ticks to seconds, read once. `mach_absolute_time` is in units the
    /// timebase defines and is **not** nanoseconds on every machine — assuming it
    /// is happens to work on Apple Silicon and is exactly the kind of assumption
    /// this increment exists to stop making.
    private static let secondsPerHostTick: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return 1e-9 }
        return Double(info.numer) / Double(info.denom) * 1e-9
    }()

    static func seconds(fromHostTime host: UInt64) -> Double {
        Double(host) * secondsPerHostTick
    }

    /// The inverse, so a test can hand this a host time meaning an exact number
    /// of seconds. `RateCorrectionTests` drives the whole rate measurement
    /// through it, which is what let its `MINUTES_RATE_TIMING` gate come off.
    static func hostTime(fromSeconds seconds: Double) -> UInt64 {
        UInt64((seconds / secondsPerHostTick).rounded())
    }

    /// Called from the audio callback. `hostTime` is a mach absolute time.
    func record(sampleTime: Double, hostTime: UInt64, frames: Int) {
        guard frames > 0, hostTime > 0 else { return }
        let tick = AudioClock.Tick(sampleTime: sampleTime,
                                   hostSeconds: Self.seconds(fromHostTime: hostTime),
                                   frames: Double(frames))
        lock.lock()
        clock.record(tick)
        lock.unlock()
    }

    /// A consistent copy, for the drain thread and for `stop()`.
    var snapshot: AudioClock {
        lock.lock(); defer { lock.unlock() }
        return clock
    }

    func reset() {
        lock.lock(); clock = AudioClock(); lock.unlock()
    }
}
