# Code review — increment 11

**Date:** 2026-09-07
**Branch:** `increment-11-stream-alignment` against `ef3d494`
**Scope:** the whole diff — 34 source and test files, ~3,800 lines
**Spec:** Epic 17, stories 17.1 through 17.7
**Suite at review time:** 415 tests, 1 failure (not this increment's — see below)

---

## Verdict

Fourteen findings. **Two are serious and both are mine, created by this
increment rather than found in passing** — which is the finding as much as the
defects are: the reorder that fixes the start offset opened a resource-leak path
that could not exist before it, and the accounting identity built to find a
missing-audio defect had a term counted twice.

All fourteen are fixed. Three pre-existing findings are recorded and
deliberately not changed, with the reasoning. Two further defects were in the
**tests this increment added**, and both are the kind that make a suite lie
rather than fail.

---

## Fixed

### 1. A microphone that fails to start leaks the whole tap chain, permanently (serious)

`DualStreamCapture.start`, `SystemTapCapture.begin`/`prepare`.

`SystemTapCapture.createIOProc` does `Unmanaged.passRetained(self)`. That is a
self-retain: once `prepare()` has run, the only thing that can release it is
`stopIO()`, reached only from `teardown()` — and `deinit` can never fire,
because the object holds a reference to itself. A prepared-but-never-begun tap
that is simply dropped is immortal.

AD-59 moved the whole chain build to *before* `mic.begin()`, and step 3 had no
cleanup around it. So a microphone that throws — the input device being switched,
another app holding it exclusively — left behind, for the life of the process:
the private aggregate device, a **global** process tap, the IOProc, and the
writer's drain thread, which cannot exit because `drainLoop` retains `self` for
the duration of the call and only returns when `running` goes false. `system.wav`
stays open. `isRunning` stays false, so `stop()` early-returns and the output
device monitor is never stopped either. **Every retry leaks another chain.**

AD-2 names the harm exactly: "a leaked aggregate device is visible system-wide."

Before this increment the path could not exist — the chain was built *after* the
microphone had started, so a microphone failure happened before there was
anything to leak. **Moving the build earlier created it**, and that is the
honest description: the fix for one fault opened another.

**Fixed:** a `discard()` entry point on `SystemTapCapture` so a caller that
prepares a tap and then fails on the other Stream can give it back; a
`catch` around `mic.begin()` that discards the prepared tap and stops the output
monitor before rethrowing; teardown on both of `begin()`'s throws; and teardown
on `prepare()`'s two late failures, which had been relying on that unreachable
`deinit`. Covered by `CaptureTeardownTests`, and by
`StartOrderRegressionTests`'s fifteen full cycles.

### 2. The accounting identity double-counted the held opening (serious)

`StreamFileWriter.ledger`, `CaptureLedger.residentFrames`.

`drainOnce` increments `inputFramesConsumed` *before* the `!rateSettled` branch
moves the same samples into `pending`, and `ledger` then added
`pending.count / channels` into `residentFrames`. The same frames were in two
terms at once, so

    unaccountedFrames = deviceFrames − dropped − consumed − resident

was short by the whole held opening — up to `audioClockPatience` (six seconds)
of audio, about 288,000 frames at 48 kHz — and **negative**.

Latent only because all three call sites read after `writer.stop()`, which
flushes `pending` to empty. But publishing the ledger is the point of the
increment: the first live readout would have failed its own identity by a wide
margin and pointed at a mechanism that does not exist. **An instrument that
lies is worse than no instrument**, and this one was built to find a defect of
exactly this size.

**Fixed:** `heldFrames` is its own term, documented as a *subset* of
`consumedFrames` rather than a term beside it, and `expectedWrittenFrames`
subtracts it. Covered by the identity assertions in `CaptureLedgerTests` and by
`CaptureLedgerRealLibraryTests`, which checks it against every record on disk.

### 3. The counter snapshot could be overwritten with zeros

`StreamFileWriter.frozen`. The freeze exists because
`SystemTapCapture.stop` resets the ring before reading the result, which made
the System Stream report zero drops and a zero high-water mark on **every**
capture — the exact reading this increment wants, and one that would have looked
like good news. The freeze was unconditional, so a second `stop()` taken after a
reset would replace the real counters with zeros and reinstate that failure.

**Fixed:** frozen once. One line, and it closes a regression hazard in the one
place where a wrong answer is indistinguishable from success.

### 4. The QoS hypothesis was documented as measured and was not measured

`StreamFileWriter.qualityOfService`, `DrainCheck`.

The seam documents itself as existing because "`--check-drain` has to be able to
sweep it and report the difference. A change that cannot be shown to improve a
measured number does not ship." Nothing swept it: `measure(...)` was called with
a hard-coded `.utility`, and the surrounding comment claimed "both scheduling
classes" and "all four combinations" where the four were slack × pull. So the
increment's own entering suspicion — a `.utility` drain thread is scheduled on
the efficiency cores and throttled, and if it is late the ring overflows — was
asserted, instrumented, and then not run.

**Fixed:** the sweep is a list of five named configurations and the scheduling
class is one of the dimensions.

### 5. The baseline row of the sweep was not the baseline

`flushConverter` looped unconditionally while only `convertAndAppend` consulted
`pullUntilDryOverride`. The end-of-stream tail flush is itself new in this
increment, so the row labelled "what shipped before increment 11" still received
it. The whole reason the halves are swept apart is attribution.

**Fixed:** the override applies to both.

### 6. `unproducedFrames` returned zero in the worst case of the fault it names

`CaptureLedger`. Guarded on `producedFrames > 0`, so a converter that produced
*nothing at all* — the worst case — reported zero loss and dropped its own term
out of the attribution list. Replacing the guard with nothing was also wrong, and
three tests caught it: `produced == 0` with `written > 0` is impossible and
therefore means "never recorded", and reporting the whole recording as
unconverted there invents a defect out of an absent field.

**Fixed:** guarded on `producedFrames >= writtenFrames`, which separates the two.
`attribution` also multiplied frame counts by 16,000 on a ledger with no input
rate, via `max(1, inputRate)`; it now returns nothing rather than nonsense.

### 7. Eight smaller findings

- **`StreamRingSizing` consolidated nothing.** Its doc claimed two adapters and
  one method read it; all three still held literals, and `readFrames` was read by
  nobody. Resizing a ring would have silently desynchronised it from the
  "ring holds N s" that `--check-drain` prints. Now actually read by all three.
- **`decomposition.deviceLatency` is not a device's latency.** It reduces to the
  *difference* between the two devices' warm-ups and is negative whenever the
  microphone is the slower, and it was logged as "N ms of device first-callback
  latency". Renamed `deviceLatencyGap`; both absolute terms already print
  separately.
- **The ring's counters were read without its lock** at three call sites. Benign
  — the producer is always stopped first — and a race by the memory model for no
  benefit. Now one locked tuple, which also makes the four numbers describe the
  same instant, which is what the identity rests on.
- **`stop()`'s three-second join deadline was inside a race with the new flush.**
  If the drain thread outlives the deadline, `stop()` proceeded anyway and now ran
  `flushConverter` beside a live `drainOnce` — and telling the converter the
  stream has ended would make the live thread's conversions return end-of-stream
  and discard audio silently. The most reachable case is `--check-drain` itself,
  which deliberately starves that thread. The flush and the tail drain are now
  conditional on the join, and a failure to join is logged.
- **The samples-to-frames divisor had no test that would fail if it were
  removed.** Every non-zero drop fixture was mono; the one stereo case asserted
  zero. Removing the division would have doubled every stereo recording's
  reported loss with the suite green. Covered now.
- **Dead code and a doc naming a caller that isn't one.** `SystemTapCapture.start`
  had no callers; `MicCapture.start`'s doc named `TestPlayground`, which uses
  `DualStreamCapture`. Removed and corrected.
- **`makeOutputBuffer`'s `guard capacity > 0` was unreachable** — capacity is at
  least the slack — and read as though the arithmetic could produce zero.
- **A log line said "the chunk is abandoned"** where 64 buffers had already been
  written and only the residue was.

### 8. Two defects in the tests this increment added

Both are the kind that make a suite lie rather than fail, which is why they are
listed as defects and not as tidying.

- **A test that crashed the whole process.** `StartOrderRegressionTests`
  force-unwrapped a temp directory in `tearDownWithError` that
  `setUpWithError` skips *before* assigning — so on any machine where the gate is
  unset it exited with signal 5 and took every remaining test with it. Precisely
  the shape of the defect increment 10 found, where a crash stopped 133 tests
  from running at all.
- **A test that failed for a reason it was not testing.** A three-Session rapid
  cycle failed inside the suite with `-10868`
  (`kAudioUnitErr_FormatNotSupported`) while passing in isolation, because
  several tests open the input device in quick succession and it will not always
  reopen. **The resolution was not to loosen the assertion** — that is the
  mistake `WavRateRepairTests` records four attempts at. The cycling belonged in
  a gated measurement, and it is now fifteen interleaved cycles of each start
  order in `StartOrderRegressionTests`, which measures **0/15 microphone
  failures for both orders** and answers the real question: AD-59's reorder does
  not make the microphone fail to start.

---

## Found, and deliberately not changed

### `rebuildForDeviceChange` discards the System Stream when a rebuild fails

`SystemTapCapture`. Its own comment says "the RingBuffer and StreamFileWriter
survive, so the recording continues into the same file". A `buildDeviceChain()`
failure during the rebuild calls `teardown()`, which nils both — so
`stop()` then reads `.unknown`/`.none` and the whole System Stream is discarded,
contradicting the comment and losing audio already on disk.

Pre-existing, untouched by this increment, and in FR-8's territory rather than
this epic's. **Not changed because a fix needs its own measurement**: the
failure mode has never been observed on this hardware, `outputDeviceChanged` is
`false` on all four instrumented recordings, and guessing at a recovery path for
an unobserved fault is how a different defect gets written. Recorded as an
action item so it is found rather than rediscovered.

### The ring can drop half a frame

`available = capacity − fill − 1` is odd for an even capacity, so a stereo
overflow truncates mid-frame: `droppedFrames` can legitimately come back as
`x.5`, and the reader's channel pairing is offset by one sample until the next
fully-drained read discards the stray. Inaudible after the stereo-to-mono
downmix, self-healing at one sample per overflow, and it means the drop count is
not guaranteed to be a whole number of frames. Not changed: the fix is a
frame-aligned capacity, which touches the one data structure in the capture path
that has never been wrong, to correct an error of half a frame.

### `RingBuffer` and `AudioClockTap` still take a lock on the audio thread

AD-1's convention, recorded unchanged for the second increment running. What is
new is that the instrument this increment added is now the thing that would show
it mattering — and across every reproduction taken, idle and under ten competing
`userInteractive` threads, **the drop count is zero and the high-water mark never
exceeded 3.84% of a ten-second ring**. The lock is not costing audio on this
hardware. AD-58 states the rule: if a measurement ever says it is, the fix is a
lock-free ring and not a relaxed convention.

### The two sweep overrides are unsynchronised statics

`outputSlackOverride` and `pullUntilDryOverride` are written from the main thread
and read from the drain thread. They compile only because the target pins Swift 5
language mode and would be errors under Swift 6. The current ordering is safe by
convention — written before `Thread.start()`, cleared after the join — and
`DrainCheck` carries a hand-rolled lock box whose own comment condemns exactly
this shape. Not changed, and documented at the declaration rather than left to be
discovered: a measurement seam that costs a lock on the drain thread is worse
than one that costs a convention, and they are named `Override` so nothing
mistakes them for configuration.

---

## Checked and sound

- **`AudioClock.framesProduced` balances across a rebase.** The algebra was
  checked term by term: `(A_k − A_1) + F_k + (B_m − B_1) + F_m` is both devices'
  full spans with the inter-device gap correctly excluded. It matters because
  `sampleAdvance` is reset by a rebase — correct for a rate, and wrong for an
  identity that must balance over a whole Session, where it would have reported
  the entire pre-rebase recording as unaccounted for.
- **Neither conversion loop can spin or silently abandon audio.**
  `convertAndAppend` needs one extra pass in the common case and each pass
  carries at least 4,096 output frames at the shipping slack, so 64 passes is
  ~16 s of audio — orders above one chunk at any ratio the app meets.
  `flushConverter` terminates on `.inputRanDry`, `.endOfStream` or a zero-length
  buffer. The one reachable abandonment is inside the sweep's `slack 64,
  pull until dry` row, and it logs.
- **`MicCapture.begin()`'s failure path leaves the writer, ring and clock
  consistent.** `removeTap` runs before `writer?.stop()`, so the producer is
  stopped before the flush; the tap block's strong captures of the ring and clock
  are released by the `removeTap`; and `isRunning` stays false, so `stop()`
  returns an empty result rather than reading a half-built writer.
- **Every persisted type that gained a field has a hand-written `init(from:)`,
  verified against the real library rather than asserted.** `Meeting` gains five
  and `CaptureLedger`, `DrainPressure` and `CaptureStartTiming` are new.
  `CaptureLedgerRealLibraryTests` decodes **every record on disk** — not with
  `try?`, which would skip past the failure this checks for — and every one
  decodes, with records written before this increment carrying no ledger and
  raising no notice. This is the check `--doctor` normally does, taken here
  because `--doctor` needs the installed bundle and installing an ad-hoc-signed
  build revokes microphone consent.
- **Core still imports Foundation only.** `CaptureLedger`, `DrainPressure` and
  `CaptureStartTiming` are decision types with no framework in them; the
  CoreAudio and AVFoundation work stays in adapters. `CorePurityTests` passes.
- **No new `removeItem` outside AD-42's allowlist.** One was added,
  `DrainCheck`, with its reason recorded in the allowlist the test reads — and
  the test caught it rather than a human noticing.
- **Nothing pads, trims or resamples a file.** The epic forbids it and the diff
  contains no such path; the counts explain the lengths and never correct them.

---

## The one failing test, and why it is not this increment's

`EnrolmentCalibrationTests.testTwoDifferentInRoomVoicesAreNeverConfusedAtTheCalibratedThreshold`
fails: one of 71 known-different in-room voice pairs sits at **0.2322** against
AD-31's 0.35.

It is not caused by this work, and that is checkable rather than assertable. The
test file is **byte-identical to the base commit**, as are `VoiceMatch` and
`RoomVoices`. The failing pair comes from a meeting recorded at 15:01 today —
*by the installed build*, which predates this branch — so the centroids that
fail were written by base-commit code. The library changed; the code did not.

It bears directly on the user's own open question about the 0.023 margin on
FR-100's keep side, and the increment's instructions are explicit that the
threshold is not to be moved. **Recorded, not fixed.**
