---
title: What happened to the 8.37 seconds — the drift's mechanism, and the start offset's
date: 2026-09-07
increment: 11
epic: 17
stories: [17.1, 17.2, 17.3, 17.4, 17.5, 17.6]
binds: [FR-6, FR-97, FR-102, FR-103, FR-104, FR-105]
spine: [AD-57, AD-58, AD-59]
status: final
---

# What happened to the 8.37 seconds

Increment 10's continuity check made a defect visible that nobody had seen: on a
**42.4-minute recording**, both devices ran at 48 kHz within 0.84 s of each
other, both reported **zero missing frames and zero discontinuities** on the
audio clock — and the System Stream's file was **8.37 seconds short**. Every
signal the app had said the capture was clean.

This note records how the mechanism was found, including the three times a
plausible answer was refuted, and what the fix is worth in numbers.

Every figure below is followed by the command that produced it.

---

## 1. First, the table — because the previous conclusion died to it

Mic-minus-system file length for every dual-stream recording in the library,
16 kHz headers on both Streams only (the rate-repaired ones have rewritten
headers and are not comparable). Recordings are named by duration, never by ID.

```
Scripts/measure-stream-drift.py
```

| minutes | mic − system | drift |
|---|---|---|
| 0.1 | −0.00 s | −0.04% |
| 12.4 | +0.88 s | +0.12% |
| 12.6 | −0.08 s | −0.01% |
| 16.3 | +0.87 s | +0.09% |
| 16.9 | +0.03 s | +0.00% |
| 18.6 | +2.32 s | +0.21% |
| 22.1 | −0.14 s | −0.01% |
| 26.8 | +0.05 s | +0.00% |
| 28.7 | +0.04 s | +0.00% |
| 31.6 | +1.56 s | +0.08% |
| **31.6** | **+6.95 s** | **+0.37%** |
| 33.9 | +2.37 s | +0.12% |
| **42.4** | **+9.17 s** | **+0.36%** |
| 50.3 | −0.07 s | −0.00% |
| 57.3 | +3.28 s | +0.10% |

**A 50.3-minute recording lost nothing and a 31.6-minute one lost seven
seconds.** So it is not duration, and the entering hypothesis — that the loss
was a constant per-call resampler cost — was refuted by this table within a
minute of it being built, before any code was written. It is the first thing in
this note because it is what stopped the increment starting from the wrong place.

## 2. The 9.17 s is two faults, and the decomposition closes

One recording in the library carries the capture facts increment 10 added, so it
can be decomposed rather than guessed at.

| | Mic Stream | System Stream |
|---|---|---|
| device sample-time advance | 121,987,200 | 121,947,136 |
| host seconds the device ran | 2541.397 | 2540.562 |
| implied device rate | 48,000.4 Hz | 47,999.9 Hz |
| callback size | 4,800 frames | **512 frames** |
| frames the device says are missing | **0** | **0** |
| discontinuities | 0 | 0 |
| file length | 2541.38 s | 2532.20 s |
| short by | ~0.02 s | **8.37 s (0.33%)** |

- Start-and-stop offset: 2541.397 − 2540.562 = **0.835 s**
- Frames received and never written: **8.37 s**
- Sum: **9.19 s**, against a measured file-length difference of **9.17 s**

The identity closes to within 20 ms. **They are two faults and they had been
read as one number.** No single correction addresses both, which is why the
increment has two halves.

### Four real recordings, decomposed the same way

Three more instrumented recordings arrived during the increment, all made by the
build that predates it. Every row is the device's own frame count against the
file on disk, so nothing here is inferred. Recordings are named by duration.

```
Scripts/decompose-capture.py
```

The script prints the device's *kind* rather than its name, because a device a
user has named after themselves is a name; the models are given here as prose.

| minutes | output device | start offset | Mic Stream short by | System Stream short by |
|---|---|---|---|---|
| 42.4 | built-in speakers | **+1,006 ms** | −0.00 s (0.000%) | **8.24 s (0.325%)** |
| 16.9 | AirPods Pro | +53 ms | −0.13 s (−0.012%) | 0.03 s (0.003%) |
| 24.9 | built-in speakers | +21 ms | −0.09 s (−0.006%) | 0.56 s (0.037%) |
| 48.1 | built-in speakers | +60 ms | 0.79 s (0.027%) | **12.29 s (0.426%)** |

Four things this table settles, and two of them correct claims made earlier in
this increment.

1. **The asymmetry is real on real recordings**, not only in the harness. On the
   48.1-minute recording the System Stream lost **15.5×** what the Mic Stream
   lost, and the System Stream's callbacks are 512 frames against the
   microphone's 4,800.
2. **It is conditional on load and not on the device or the duration.** The
   24.9-minute and 48.1-minute recordings were made on the **same output device
   on the same day**, at the same rate and the same callback sizes, and lost
   **0.037%** and **0.426%** — an order of magnitude apart. This is the same
   conclusion the drift table forced at the top of this note, now with the
   configuration held fixed.
3. **The Mic Stream is susceptible too, just far less.** It lost 0.027% on the
   worst recording, which is not zero. Load decides the magnitude. An earlier
   draft of this note said the asymmetry "follows from the callback size alone",
   and that was too strong twice over — see §5's closing note, where the harness
   turns out not to reproduce the shape dependence reliably either.
4. **The +1,006 ms start offset is an outlier, not the typical case.** The other
   three read **+21, +53 and +60 ms** through the same unfixed code. So the
   serialisation cost is itself conditional on what else holds the audio devices,
   and the increment's start-offset work is worth less on a median meeting than
   the single measurement it was scoped from suggested. That is worth saying
   plainly: the number that justified half this increment was the worst of four.

A fifth Session the same day is not in the table and is recorded here because it
is a **different fault**, found while building this one: the microphone produced
**0.13 seconds** while the System Stream produced **57 seconds**, with
`micRate.framesObserved` at zero and its clock source falling back to the wall
clock — the input device delivered no callbacks at all. `systemContinuity`
records one rebase. The Session never left `captured`. Nothing in this increment
addresses it and nothing in this increment caused it; it is on the shipping build
and it is logged as an action item.

## 3. Three mechanisms, and how each was settled

### Refuted: the resampler loses a filter tail per call

The reading that fits: `StreamFileWriter` hands `AVAudioConverter` one buffer per
drain and accepts whatever comes back on `inputRanDry`, so a per-call tail loss
would hurt the System Stream — which drains far more often — proportionally more.

Driven exactly as the writer drives it, over uniform and arbitrary chunk sizes:

| chunk sizes | calls | input frames | deficit | share |
|---|---|---|---|---|
| uniform 1024 | 5,000 | 5,120,000 | 10.7 | 0.0006% |
| uniform 1024 | 20,000 | 20,480,000 | 10.7 | 0.0002% |
| varying 512×(1..4) | 20,000 | 25,564,160 | 10.7 | 0.0001% |
| arbitrary 200..3000 | 20,000 | 32,167,272 | 11.0 | 0.0001% |

**The deficit is a constant ~11 frames in total, not per call**, across a
thirteenfold range of call counts. It is the resampler's one-time priming
latency. Four orders of magnitude too small, and *not* the shape the hypothesis
required. **Refuted before a story was written on it.**

### Refuted: the ring buffer overflowed

The leading candidate on entry, and the reason `RingBuffer.didOverflow` existed
at all. Both rings hold **ten seconds**, so an overflow needs the writer to fall
ten seconds behind.

Now counted rather than flagged (FR-102). Across every reproduction taken —
idle, and against ten competing `userInteractive` threads on a ten-core machine
— **the drop count is zero and the ring's high-water mark never exceeds 3.84% of
capacity**:

```
./.build/release/Minutes --check-drain 20 10
```

Not overturned as impossible: it is the mechanism the instrument now watches for,
and a future recording that reports a non-zero drop count will say so in one
number. But it is **not what happened here**.

### Established: the converter is handed an output buffer that cannot drain it

The output buffer was sized from the input chunk in hand plus **64 frames** — four
milliseconds. That slack is the converter's only opportunity to hand back
anything it is still holding from earlier chunks. Under load it holds more than
four milliseconds' worth, cannot shed it at four milliseconds per call, and the
audio never reaches the file.

The accounting identity is what named it: **`dropped` = 0, `write failures` = 0,
`unaccounted` = 0, and `produced` short of `expected`.** Input was consumed from
the ring, handed to the converter, and the corresponding output was never
produced.

## 4. The reproduction, and the control that makes it mean something

Five producer shapes, each driving the real ring and the real writer with a
synthetic real-time producer — no audio device involved, which is why the offered
frame count is exact. Twenty seconds per shape against ten competing
`userInteractive` threads, three runs per cell.

```
./.build/release/Minutes --check-drain 20 10
```

| producer shape | slack 64 (before) | slack 4096 (after) |
|---|---|---|
| 512 fr / 10.7 ms, stereo 48 kHz | 0.427%, 0.213%, 0.373% | **0%, 0%, 0%** |
| 480 fr / 20 ms, stereo 24 kHz | 0.600%, 0.400%, 0.500% | **0%, 0%, 0%** |
| 512 fr / 10.7 ms, mono 48 kHz | 0.160%, 0.213%, 0.160% | **0%, 0%, 0%** |
| **4800 fr / 100 ms, mono 48 kHz** | **0%, 0%, 0%** | 0%, 0%, 0% |
| **4800 fr / 100 ms, stereo 48 kHz** | **0%, 0%, 0%** | 0%, 0%, 0% |

**The control is the two 4,800-frame shapes, and they are the reason this is an
explanation rather than a coincidence.** They lose nothing at either setting.
The microphone's callbacks are 4,800 frames and the system tap's are 512, so the
susceptibility the real recordings show — up to **15.5×** between the two
Streams of one recording — is reproduced from the callback size with no audio
device in the experiment, and the real losses (0.003% to 0.426%) sit inside the
reproduced range.

**What the harness does *not* show is the magnitude.** It applies ten competing
`userInteractive` threads, which is more contention than a meeting produces, and
the real recordings vary by an order of magnitude on identical hardware. Callback
size decides which Stream is exposed; load decides how much it loses.

The two controls also rule out the two variables that were moving together in the
first reading: **channel count is irrelevant** (512-frame mono loses; 4,800-frame
stereo does not), and so is the sample rate.

## 5. Both halves of the fix, swept apart

Neither half is credited with the other's effect. Four configurations,
interleaved in one binary so that machine state drifting between separate builds
cannot be mistaken for the result.

```
./.build/release/Minutes --check-drain 15 10
```

Five configurations, ten cells each (five producer shapes × two runs), ten
seconds per cell against six competing `userInteractive` threads:

| configuration | cells that lost audio | worst | ring drops |
|---|---|---|---|
| slack 64, one pass, `.utility` — **what shipped before** | **7 / 10** | 4.200% | 0 |
| slack 64, one pass, `.userInitiated` | 6 / 10 | 1.000% | 0 |
| slack 4096, one pass, `.utility` | **0 / 10** | — | 0 |
| slack 64, pull until dry, `.utility` | **0 / 10** | — | 0 |
| slack 4096, pull until dry — **shipping** | **0 / 10** | — | 0 |

Three things this settles.

**Either half alone removes it.** The loop at the old slack is zero, and the new
slack with one pass is zero. The loop is the half that ships as the reason,
because it is correct at every ratio; the constant ships beside it because it
costs 16 KB of transient buffer and there is no argument for keeping the number
that lost the audio.

**The scheduling class is not the mechanism, and that was the increment's
entering suspicion.** A `.utility` drain thread is scheduled on the efficiency
cores and throttled, and the obvious story was that it falls behind and the ring
overflows. Raising it to `.userInitiated` and changing nothing else leaves
**6 of 10 cells still losing audio**. The suspicion was instrumented and is now
answered: no.

**The ring never overflowed. Not once, in any cell, in any configuration.**
`dropped` is zero across all fifty cells of this sweep and every cell of every
earlier one, idle and loaded, with a high-water mark that never exceeded 3.84% of
a ten-second capacity. The candidate this increment opened with — and the reason
`RingBuffer.didOverflow` existed at all — is not what happened.

### One outlier, unexplained, and recorded rather than dropped

An earlier sweep produced a single cell of **9.353% lost in the shipping
configuration**. It was taken while the machine was thrashing badly enough that
the operating system killed the measurement process shortly afterwards — 2.5
million pageouts — and the ledger split for that cell was not captured, so
whether it was a ring overflow or a conversion loss is not known. It has not
recurred: the shipping configuration is zero in **20 of the 21 cells** measured
across every sweep.

It is in this note because leaving it out would be the more comfortable and less
honest choice, and because it is the one reading that would matter if it
reproduced. What would settle it is the ledger split under memory pressure rather
than CPU contention, which `--check-drain` does not currently create.

### What the harness does not reliably reproduce

**The shape asymmetry is not stable run to run.** Across sweeps the 4,800-frame
mono shape has read 0.000% four times and **0.293%** once, and the 480-frame
24 kHz shape has read anywhere from 0.000% to **4.200%**. So the earlier claim in
this note — that the two 4,800-frame shapes are a clean control that never loses
anything — holds for most runs and not for all, and callback size is a weaker
predictor in the harness than the real recordings suggest. The real recordings'
15.5× asymmetry between the two Streams of one recording is the firmer evidence
for it; the harness establishes the *mechanism* and its load dependence, not the
asymmetry.

## 6. The start offset: where the second went

The offset FR-97 records was one number and nothing could be aimed at it:
**+1,006 ms** on the real 42.4-minute meeting against **+40, +41, +62 ms** on a
five-second probe. FR-104 stamps each stage on the callbacks' own clock, so it
decomposes.

The cause is that `DualStreamCapture.start` opened the microphone and *then*
built the tap chain — process tap, default-output UID lookup, private aggregate
device, IOProc — serially, while the microphone was already recording. Every
millisecond of that construction landed in the offset.

AD-59 splits both adapters into `prepare` and `begin`, so the chain is built
before either device runs and the two starts are adjacent. AD-2's construction
order is untouched; only where the start falls inside it moved.

```
./.build/release/Minutes --check-clock 6
```

| | before | after |
|---|---|---|
| gap between the two device starts | the whole tap-chain build | **+0.1 to +0.2 ms** |
| start offset, five-second probe | +40, +41, +62 ms | **+16, +17, +17, +19, +30 ms** |
| tap chain build (cold) | 41–63 ms, *paid while recording* | 41–63 ms, paid before |
| microphone preparation | 195–423 ms, paid before | 195–423 ms, paid before |

**The first reading of the stages was wrong, and it is recorded rather than
quietly corrected.** `tapChainBuildSeconds` charged `engine.prepare()` to the tap
chain and reported 350 ms of chain building that was mostly the microphone's. A
stage measurement that charges one stage for another points a change at the wrong
place, which is worse than having no stage measurement. Separated, the chain is
41–63 ms.

**One run of the new order read −208 ms and it was noise, not a regression.** The
microphone's hardware had genuinely warmed up slowly on a cold first open (first
callback +213 ms against −3 to −7 ms on the next five runs). Five further runs
put the offset at +16 to +30 ms. It is recorded because it was nearly published
as a regression on n=1.

The residual is device first-callback latency, and the sign of it is worth
noting: the microphone's first sample is stamped **before** `engine.start()`
returns (−3 to −7 ms), which settles empirically that `AVAudioTime.hostTime` is
the timestamp of the buffer's first sample and not of its delivery. There is no
one-buffer bias in FR-97's offset.

## 6a. The first real Session on the fixed build

A four-minute Session recorded on 8 September, output through a Bluetooth
headset, is the first real capture carrying the full ledger. It answers both
halves of the increment on a real recording rather than on a probe.

**The drift: closed exactly, on both Streams.**

| | Mic Stream | System Stream |
|---|---|---|
| frames the device counted | 3,866,624 | 3,872,000 |
| frames the writer consumed | 3,866,624 | 3,872,000 |
| frames the converter produced | 3,866,624 | 3,872,000 |
| frames written to the file | **3,866,624** | **3,872,000** |
| dropped / held / resident / unaccounted | **0 / 0 / 0 / 0** | **0 / 0 / 0 / 0** |
| write failures | 0 | 0 |
| ring high-water mark | 4,096 of 160,000 (**2.56%**) | 2,560 of 480,000 (**0.53%**) |
| longest gap between drains | 342 ms | 158 ms |

Every term is equal to every other term. Not "within a callback" — equal.

**The start: the serialisation is gone and the residual is the microphone.**

```
mic prepared in                   108.66 ms
tap chain built in                693.39 ms   <- what the old order paid out of recording time
between the two device starts       0.045 ms  <- the term AD-59 owns
mic first sample after start      209.49 ms
system first sample after start     0.066 ms
=> offset                          -209.4 ms
```

**693 ms** of tap-chain construction on a real Session, against 41–63 ms on a
cold probe — which is the twentyfold understatement §6 predicted, now measured
from the other side, and it corroborates the +1,006 ms reading rather than
explaining it away. Under the previous order this Session's offset would have
been about **+484 ms**; it is now **−209 ms**, and every millisecond of what
remains is the microphone taking 209 ms to deliver its first sample where the
tap takes 0.07 ms.

So **FR-6's ±100 ms fails on this recording, in the opposite direction to the
defect the increment started from**, and it fails for a reason capture does not
control. FR-6 is amended to say that rather than to claim a wider window.

## 7. What is measured, and what is inferred

Stated plainly, because the difference is the whole discipline of this increment.

**Measured:**

- The 9.17 s file-length difference decomposes into 0.835 s of start offset plus
  8.37 s of unwritten audio, summing to within 20 ms.
- The resampler's steady-state per-call loss is ~11 frames in total, not per call.
- The ring dropped **zero** samples in every reproduction, idle or loaded, and
  peaked at 3.84% of a ten-second capacity.
- A 64-frame output slack loses **0.16% to 0.60%** under load on 480- and
  512-frame callback shapes and **0.000%** on 4,800-frame shapes; the shipping
  configuration loses **0.000%** on all five.
- The gap between the two device starts is +0.1 to +0.2 ms, and the probe's start
  offset falls from +40..+62 ms to +16..+30 ms.

**Inferred, and not measured:**

- **That the mechanism reproduced here is the mechanism that lost 8.37 s on that
  particular recording.** It cannot be measured, because that recording was made
  by a build that kept no ledger, and it will not be re-made. What supports the
  inference is that the reproduction has the same location in the pipeline
  (consumed, never converted), the same asymmetry with the same cause (callback
  size), the same load dependence, and a magnitude range containing the observed
  0.33%. What would refute it is a recording made after this fix that still loses
  audio — in which case the ledger will say which term it went to.
- ~~**How much of the +1,006 ms the new order removes on a real meeting.**~~
  **Answered in §6a**: 693 ms of tap-chain build on a real Session, all of it now
  paid before either device starts, with 0.045 ms left between the two starts.
  What is still not confirmed is the **42-minute loudspeaker** case specifically:
  the Session measured was four minutes on a Bluetooth headset, and the drift is
  known to be load-conditional. The instrument answers it on the next such
  Session without anyone remembering to look.

## 8. What did not change, and was checked rather than assumed

- Pooled WER, close mics / far field: re-run through the shipping path after the
  change. Nothing here touches the recogniser or its input.
- `--check-rates`: 23 recordings, 0 failing.
- `--doctor`: 24 meetings readable, 0 unreadable, 0 note links broken.
- The device continuity figures (AD-51) are unchanged and still read zero
  missing frames — correctly. They were never wrong; they were answering a
  different question, which is why AD-57 is an addition to AD-51 and not a
  correction of it.
