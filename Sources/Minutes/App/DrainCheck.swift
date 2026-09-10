import Foundation
import AVFoundation

/// `--check-drain [seconds] [load]` — FR-102, FR-103, Story 17.3.
///
/// **Why this exists as a command rather than as a test.** A 42.4-minute
/// recording lost 8.37 seconds of the System Stream between the callback and the
/// file, with the audio clock reporting zero missing frames on both Streams. At
/// least three mechanisms fit that measurement and all three are visible from
/// reading the code, which is the evidence increment 10 learned not to trust on
/// its own. So the mechanism has to be reproduced under conditions somebody
/// controls — and the reproduction cannot be a unit test, because it depends on
/// load and a load-dependent assertion in the suite is the flakiness that took
/// four attempts to get out of `RateCorrectionTests`.
///
/// It drives the **real** `RingBuffer` and the **real** `StreamFileWriter` with a
/// synthetic producer, so no audio device is opened and it is safe to run while
/// a Session is recording. Only the producer is a fixture, which is what makes
/// the offered frame count exact.
///
/// It sweeps the one structural difference between the two Streams. The system
/// tap delivers **512 frames every 10.7 ms**; the microphone delivers **4,800
/// frames every 100 ms**. Same bytes per second on the mic, twice as many on a
/// stereo tap, and nine times the number of wakeups — and the loss was 380×
/// worse on the tap. If callback size under load is the mechanism, this is where
/// it shows.
///
/// Writes to a temporary directory which is removed on the way out, and prints
/// counts and milliseconds only (PRD §9.1).
enum DrainCheck {

    /// One producer shape, named for the Stream it imitates.
    private struct Shape {
        let name: String
        let callbackFrames: Int
        let channels: AVAudioChannelCount
        let rate: Double
    }

    static func run() {
        let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
        let seconds = max(2, min(1800, args.first ?? 20))
        let loadThreads = Int(max(0, min(64, args.dropFirst().first ?? 0)))

        print("=== Minutes: drain-pressure check ===")
        print("No audio device is opened; the producer is synthetic and the ring and")
        print("writer are the shipping ones. Safe to run during a recording.\n")
        print(String(format: "%.0f s per shape, %d competing CPU thread(s), ring holds %d s\n",
                     seconds, loadThreads, StreamRingSizing.seconds))

        let shapes = [
            Shape(name: "system tap  (512 fr / 10.7 ms, stereo 48k)",
                  callbackFrames: 512, channels: 2, rate: 48_000),
            Shape(name: "microphone  (4800 fr / 100 ms, mono 48k)",
                  callbackFrames: 4800, channels: 1, rate: 48_000),
            Shape(name: "system tap  (480 fr / 20 ms, stereo 24k)",
                  callbackFrames: 480, channels: 2, rate: 24_000),
            // The controls that isolate one variable at a time. Both stereo
            // shapes above lost frames and the mono one lost exactly zero, and
            // callback size and channel count were varying together.
            Shape(name: "control     (512 fr / 10.7 ms, MONO 48k)",
                  callbackFrames: 512, channels: 1, rate: 48_000),
            Shape(name: "control     (4800 fr / 100 ms, STEREO 48k)",
                  callbackFrames: 4800, channels: 2, rate: 48_000),
        ]

        let stop = Load.start(threads: loadThreads)
        defer { stop() }

        // Both scheduling classes, so the difference is a measurement rather
        // than an argument. `.utility` is what has shipped since the writer was
        // written; it is the lowest non-background class and on Apple Silicon it
        // is scheduled on the efficiency cores and throttled.
        // The A/B interleaved in one binary, so machine state drifting between
        // two separate builds cannot be mistaken for the effect.
        // Every configuration interleaved in one binary, so machine state
        // drifting between separate builds cannot be mistaken for the effect.
        // The halves of the fix are swept apart because a change nobody can
        // attribute is a change that gets reverted for the wrong reason.
        //
        // **The scheduling class is swept too.** It is the increment's own
        // entering suspicion — a `.utility` drain thread is scheduled on the
        // efficiency cores and throttled, and if it is late the ring overflows —
        // and the first version of this tool documented a seam for it and then
        // called `measure` with a hard-coded `.utility`. A suspicion that is
        // instrumented and not run is an assertion.
        let configurations: [(name: String, slack: AVAudioFrameCount,
                              pull: Bool, qos: QualityOfService)] = [
            ("slack 64, one pass, .utility        <- what shipped before increment 11",
             64, false, .utility),
            ("slack 64, one pass, .userInitiated  <- does the QoS alone fix it?",
             64, false, .userInitiated),
            ("slack 4096, one pass, .utility      <- the constant alone",
             StreamFileWriter.outputSlackFrames, false, .utility),
            ("slack 64, pull until dry, .utility  <- the loop alone",
             64, true, .utility),
            ("slack 4096, pull until dry, .utility  <- shipping",
             StreamFileWriter.outputSlackFrames, true, .utility),
        ]
        for c in configurations {
            StreamFileWriter.pullUntilDryOverride = c.pull
            StreamFileWriter.outputSlackOverride = c.slack
            print("--- \(c.name) ---")
            for shape in shapes {
                measure(shape, seconds: seconds, qos: c.qos)
            }
        }
        StreamFileWriter.outputSlackOverride = nil
        StreamFileWriter.pullUntilDryOverride = nil

        print("\nThe reading to compare against a real recording: a loss the ring")
        print("explains appears as `dropped`; a loss it does not appears as")
        print("`unaccounted` or as a conversion remainder, and those are different faults.")
        exit(0)
    }

    private static func measure(_ shape: Shape, seconds: Double, qos: QualityOfService) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-drain-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: shape.rate,
                                      channels: shape.channels,
                                      interleaved: shape.channels > 1) else { return }
        // Exactly the sizing the adapters use, so the high-water share means the
        // same thing here as it does on a real capture.
        let ring = RingBuffer(capacity: Int(shape.rate) * Int(shape.channels)
                              * StreamRingSizing.seconds)
        let writer = StreamFileWriter(url: dir.appendingPathComponent("s.wav"),
                                      format: fmt, ring: ring)
        writer.qualityOfService = qos
        do { try writer.start() } catch {
            print("\(shape.name): could not start the writer: \(error.localizedDescription)")
            return
        }

        // The producer runs at the highest priority a Thread can ask for, which
        // is what a real IOProc effectively has. Without that this measures the
        // scheduler's treatment of two equal threads rather than a real-time
        // producer against a `.utility` consumer.
        let samplesPerCallback = shape.callbackFrames * Int(shape.channels)
        let block = [Float](repeating: 0.25, count: samplesPerCallback)
        let period = Double(shape.callbackFrames) / shape.rate
        let callbacks = Int((seconds / period).rounded())
        var offeredFrames = 0
        let done = DispatchSemaphore(value: 0)

        let producer = Thread {
            var next = Date()
            block.withUnsafeBufferPointer { p in
                for _ in 0..<callbacks {
                    ring.write(p.baseAddress!, count: samplesPerCallback)
                    next = next.addingTimeInterval(period)
                    let wait = next.timeIntervalSinceNow
                    if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
                }
            }
            done.signal()
        }
        producer.threadPriority = 1.0
        producer.qualityOfService = .userInteractive
        producer.start()
        done.wait()
        offeredFrames = callbacks * shape.callbackFrames
        writer.stop()

        let l = writer.ledger
        let p = writer.drainPressure
        print(shape.name)
        print(String(format: "  offered  %10d frames in %d callbacks", offeredFrames, callbacks))
        print(String(format: "  dropped  %10.0f frames in %d overflow(s)   consumed %10.0f   written %9.0f out",
                     l.droppedFrames, l.overflows, l.consumedFrames, l.writtenFrames))
        let unaccounted = Double(offeredFrames) - l.droppedFrames - l.consumedFrames - l.residentFrames
        print(String(format: "  identity offered - dropped - consumed - resident = %.0f", unaccounted))
        let expected = Double(offeredFrames) * (StreamFileWriter.outputSampleRate / shape.rate)
        let deficit = expected - l.writtenFrames
        print(String(format: "  file     short by %.0f out of %.0f  (%.4f%%, %.3f s)",
                     deficit, expected, deficit / expected * 100,
                     deficit / StreamFileWriter.outputSampleRate))
        print(String(format: "  split    produced %.0f, never converted %.0f, converted-not-written %.0f in %d failure(s)",
                     l.producedFrames, l.unproducedFrames,
                     l.writeFailureFrames, l.writeFailures))
        print(String(format: "  rate     declared %.0f, corrected %@, converter in %.0f Hz",
                     shape.rate,
                     writer.correctedRate.map { String(format: "%.0f", $0) } ?? "none",
                     writer.converterInputRate))
        print(String(format: "  pressure high water %.0f frames (%.2f%% of %.1f s), longest gap %.1f ms with %.0f frames waiting",
                     p.highWaterFrames, (p.highWaterProportion ?? 0) * 100,
                     p.capacitySeconds, p.longestGapSeconds * 1000, p.backlogAtLongestGap))
        print("")
    }

    /// Competing CPU work, so the `.utility` drain thread has to contend for a
    /// core. Deliberately `userInteractive`: the question is what happens to the
    /// writer when something more important than it is running, which is what a
    /// video call is.
    private enum Load {
        static func start(threads: Int) -> () -> Void {
            guard threads > 0 else { return {} }
            let running = Atomic(true)
            for _ in 0..<threads {
                let t = Thread {
                    var x = 1.000001
                    while running.value {
                        for _ in 0..<200_000 { x = x * 1.0000001 + 1e-9 }
                        if x > 1e30 { x = 1.000001 }
                    }
                }
                t.qualityOfService = .userInteractive
                t.start()
            }
            return { running.value = false }
        }

        /// A one-field lock box. `nonisolated(unsafe)` on a shared `Bool` is the
        /// thing this exists to avoid.
        final class Atomic: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: Bool
            init(_ v: Bool) { stored = v }
            var value: Bool {
                get { lock.lock(); defer { lock.unlock() }; return stored }
                set { lock.lock(); stored = newValue; lock.unlock() }
            }
        }
    }
}
