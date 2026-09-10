import Foundation

/// When holding the audio input device means a meeting has begun, and when
/// letting go of it means the meeting has ended (FR-12, FR-14, FR-106).
///
/// Pure by design: handed a set of identities and a clock reading, it answers.
/// It is separate from `DetectionService` because all of the interesting
/// behaviour is the hysteresis, and none of it was reachable by a test while it
/// sat inline in a method that enumerates CoreAudio process objects. The two
/// faults this type exists to remove both lived in those few lines and neither
/// had a test that could have caught them.
///
/// **The hysteresis is asymmetric on purpose, in both directions.** Holding the
/// device has to persist for `debounce` before a meeting is believed to have
/// started, so a device probe does not raise a prompt. Releasing it has to
/// persist for `grace` before a meeting is believed to have ended, because
/// moving audio to different hardware makes an application let go of one input
/// device and take another, and for a moment it holds neither. Without the
/// second half, that moment is indistinguishable from a call ending — which is
/// exactly what it was read as: one meeting became three recordings, each
/// needing its own prompt.
struct DetectionWindow {

    /// Held this long before a meeting is believed to have started (FR-12).
    let debounce: TimeInterval

    /// Absent this long before it is believed to have ended (FR-14, FR-106).
    ///
    /// FR-14 budgets thirty seconds to notice a meeting has ended. The
    /// implementation used to spend none of it — one poll's absence stopped the
    /// recording — and that unspent budget is where this fix comes from. It is
    /// not a widened tolerance: the deadline was always thirty seconds and the
    /// code was simply tighter than the requirement, in the one direction that
    /// turns a device switch into a lost recording.
    let grace: TimeInterval

    /// When each identity was first seen holding the device in this episode.
    private var firstHeld: [String: Date] = [:]
    /// When each identity was last seen holding it. A gap shorter than `grace`
    /// does not end the episode, so `firstHeld` survives it and the debounce is
    /// not restarted by a switch.
    private var lastHeld: [String: Date] = [:]
    /// Identities already offered to the user in this episode, so a declined
    /// meeting is not asked about again while the same call continues (FR-12).
    private var announced: Set<String> = []

    init(debounce: TimeInterval, grace: TimeInterval) {
        self.debounce = debounce
        self.grace = grace
    }

    struct Verdict: Equatable {
        /// Held past the debounce and not yet announced. The caller applies its
        /// own policy (suppressed, already recording) and calls `announce` only
        /// if it actually asks — which is why this is a candidate and not an
        /// instruction.
        var candidates: [String] = []
        /// Absent past the grace period: the meeting is over.
        var ended: [String] = []
    }

    mutating func update(held: Set<String>, now: Date) -> Verdict {
        var v = Verdict()

        for id in held {
            if firstHeld[id] == nil { firstHeld[id] = now }
            lastHeld[id] = now
        }

        // Snapshot the keys before mutating: removing from a dictionary while
        // iterating its own `keys` is undefined behaviour and did crash here.
        for id in Array(firstHeld.keys) where !held.contains(id) {
            let last = lastHeld[id] ?? .distantPast
            guard now.timeIntervalSince(last) >= grace else { continue }
            firstHeld.removeValue(forKey: id)
            lastHeld.removeValue(forKey: id)
            announced.remove(id)
            v.ended.append(id)
        }

        for id in held.sorted() {
            guard let since = firstHeld[id],
                  now.timeIntervalSince(since) >= debounce,
                  !announced.contains(id) else { continue }
            v.candidates.append(id)
        }

        return v
    }

    /// Records that the user was actually asked about this identity.
    mutating func announce(_ id: String) { announced.insert(id) }

    mutating func reset() {
        firstHeld = [:]
        lastHeld = [:]
        announced = []
    }

    /// Seconds this identity has been absent, or nil when it is held or unknown.
    /// For diagnostics: a recording that is inside the grace period is in a state
    /// worth being able to see.
    func absence(of id: String, now: Date) -> TimeInterval? {
        guard firstHeld[id] != nil, let last = lastHeld[id] else { return nil }
        let gap = now.timeIntervalSince(last)
        return gap > 0 ? gap : nil
    }

    /// Identities currently tracked, held or inside their grace period.
    var tracked: [String] { firstHeld.keys.sorted() }
}
