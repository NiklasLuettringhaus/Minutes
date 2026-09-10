Run the entire BMAD flow autonomously to make **the two Streams actually line
up**, in Minutes, the local-first macOS meeting recorder in this repo. Do not
ask me questions — every decision you need is below or in the named artifacts.
I will review at the end.

**No phases may be skipped.** Run the full chain in order, headless: `bmad-prd`
(update) → `bmad-architecture` (update) → `bmad-ux` (update where a surface
changed) → `bmad-create-epics-and-stories` → `bmad-sprint-planning` →
implementation (`bmad-build-auto` per story) → `bmad-code-review` →
`bmad-retrospective`. Finish with the implementation working, tested, and
committed.

**Fix root causes, not symptoms.** This increment exists because the last one
fixed a symptom well and left the cause in place. Read §"The distinction this
increment is about" before you plan anything.

---

## Read these first. They are measured, not speculative — do not re-derive them

- `_bmad-output/implementation-artifacts/retrospective.md`, the increment-10
  entry — in particular what the measurements changed about the plan
- `_bmad-output/implementation-artifacts/code-review-increment-10.md`
- PRD §4.14 FR-94 and FR-97, spine AD-4, AD-44, AD-51, AD-53
- `Sources/Minutes/Core/AudioClock.swift`,
  `Sources/Minutes/Adapters/Audio/StreamFileWriter.swift`,
  `Sources/Minutes/Adapters/Audio/RingBuffer.swift`,
  `Sources/Minutes/Adapters/Audio/DualStreamCapture.swift`

Numbering, and **never renumber anything that exists**: next FR is **FR-102**,
next AD is **AD-57**, next epic is **Epic 17**. Epic 16 is closed — 15 of its 16
stories are `done`, 16.5 is `backlog` because it was refuted rather than
delivered. Do not reopen it.

---

## The defect, as measured on 2026-09-07

Two separate faults, and they are not the same fault at two sizes.

### 1. The Streams do not start together — about a second on a real meeting

The most recent 42.4-minute meeting recorded a **+1006 ms** start offset: the
System Stream's first sample arrived a full second after the Mic Stream's.

`--check-clock` over a five-second capture reads **+35 to +54 ms** across six
runs. So the short probe understates a real session by a factor of twenty, and
whatever costs the extra second is not exercised by a cold five-second open.
`DualStreamCapture.start` opens the microphone, then builds the tap chain — tap,
default-output UID, private aggregate, IOProc, start — **serially**, and each
Stream begins whenever its own first callback lands.

FR-6 has claimed since increment 1 that a sound "appears at the same offset
(±100 ms) in both". It is out by ten times.

### 2. The Streams drift apart while recording — nine seconds by the end

Same recording, and this is the one nobody had seen:

| | frames the device delivered | frames written to the file | missing |
|---|---|---|---|
| Mic Stream | 121,987,200 | 40,662,047 | **353** (22 ms) |
| System Stream | 121,947,136 | 40,515,272 | **133,773** (8.36 s) |

Both devices ran within **0.84 s** of each other. Both report **zero missing
frames and zero discontinuities** on the audio clock, which means the device
handed us everything it counted. So 8.36 seconds of the System Stream was
**received by this process and never written** — the loss is between the ring
buffer and the file, in our own code, and it is **380× worse on the System
Stream than on the Mic Stream**.

`mic.wav` is 2541.4 s and `system.wav` is 2532.2 s. A single start offset cannot
correct a drift, so by the end of that meeting the two files are nine seconds
apart no matter what the merge does with FR-97's number.

### It is not proportional to anything obvious, and that matters

Every dual-stream recording, mic minus system file length, 16 kHz headers only
(the eight rate-repaired recordings have rewritten headers and are not
comparable):

| minutes | difference | drift |
|---|---|---|
| 0.1 | −0.00 s | −0.04% |
| 12.6 | −0.08 s | −0.01% |
| 22.1 | −0.14 s | −0.01% |
| 26.8 | +0.05 s | 0.00% |
| 28.7 | +0.04 s | 0.00% |
| 50.3 | −0.07 s | −0.00% |
| 16.3 | +0.87 s | 0.09% |
| 12.4 | +0.88 s | 0.12% |
| 33.9 | +2.37 s | 0.12% |
| 31.6 | +1.56 s | 0.08% |
| 18.6 | +2.32 s | 0.21% |
| 57.3 | +3.28 s | 0.10% |
| **31.6** | **+6.95 s** | **0.37%** |
| **42.4** | **+9.17 s** | **0.36%** |

**A 50.3-minute recording lost nothing and a 31.6-minute one lost seven
seconds.** So it is not duration, and it is not a constant per-call cost. It is
conditional on something — load, callback size, what else was running — and
finding out which is the first story, not an assumption to build on.

Note the two worst are the two most recent, and the 31.6-minute one was recorded
on 4 September at 14:06 by the build that predates increment 10. **This is not a
regression introduced by increment 10; it is a defect increment 10's continuity
check made visible for the first time.**

---

## The distinction this increment is about

Increment 10 measured the start offset and applied it at the merge. That was the
right thing to do and it is a **symptom fix**: the transcript comes out in the
right order while the recording on disk stays misaligned. Everything downstream
that wants to compare the two Streams — the echo detector, any future canceller,
the cross-stream voice comparison — still has to search for an offset that
capture could simply not have introduced.

**What a root-cause fix looks like here, and what it does not:**

| the symptom | the symptomatic fix | the root cause |
|---|---|---|
| the transcript is out of order | apply a measured offset at the merge | **already shipped — leave it in place** |
| the files are misaligned at the start | pad or trim one file | the two Streams are opened serially and each starts at its own first callback |
| the files drift apart | resample one to match the other's length | samples are received and not written, and nothing counts them |
| we cannot tell which | add a tolerance | the quantity that would tell us is computed and discarded |

**Explicitly forbidden, because each is the tempting cheap version:**

- **Do not pad, trim, or resample either file to make the lengths match.** That
  destroys the evidence of the defect and makes the next occurrence invisible —
  which is exactly what a rewritten header did to eight recordings in increment
  8, and they are still not comparable today.
- **Do not widen a tolerance.** AD-51 replaced a 12% window with a figure derived
  per measurement precisely so that this class of problem stops being absorbed.
- **Do not "fix" it by making the merge cleverer.** The merge already does the
  best that can be done with a misaligned pair. More work there is more work
  compensating for a fault upstream of it.

---

## The one quantity that is already being thrown away

`RingBuffer.didOverflow` is set on line 35 of `RingBuffer.swift` when the
producer has to drop samples because the consumer fell behind. **It is read by
nobody.** No caller, no record, no log line.

That is the same shape of defect increment 10 found twice — the device's
sample-time and host-time counters were parameters of every callback and bound
to `_` — and it is the leading candidate here, because a ring overflow drops
samples *between the callback and the writer*, which is precisely the gap the
audio clock cannot see. The device counted them. We received them. They are not
in the file.

It is a candidate, **not a conclusion.** At least three mechanisms fit the
measurement and the increment must establish which, by measuring:

1. **Ring overflow.** The System Stream's callbacks are 512 frames (10.7 ms) against
   the microphone's 4800 (100 ms), so its drain thread must wake ~93 times a
   second at `.utility` QoS. Fits the 380× asymmetry and the load-dependence.
2. **Resampler tail loss.** `StreamFileWriter.convert` hands `AVAudioConverter` one
   buffer per drain and takes whatever comes back on `inputRanDry`. If it
   discards a filter tail per call, more calls means more loss — and the System
   Stream drains far more often. Fits the asymmetry; fits the load-dependence
   less well.
3. **Something else.** The two above are the ones visible from reading the code,
   which is exactly the evidence increment 10 learned not to trust on its own.

**Measure before choosing.** A fix aimed at the wrong one of these will move the
number on one recording and not on another, which is the signature this defect
already has.

---

## The bar. This is the whole point of the increment

**A change that cannot be shown to improve a measured number does not ship.**

Baselines to beat, all reproducible from a terminal today:

| | now | target |
|---|---|---|
| start offset, real meeting | **+1006 ms** | inside FR-6's ±100 ms, or FR-6 amended to what capture can actually deliver — **with the measurement** |
| start offset, `--check-clock` | +35 to +54 ms | must not get worse |
| frames received and not written, System Stream | **133,773 (8.36 s / 0.33%)** | **zero, or counted and reported** |
| frames received and not written, Mic Stream | 353 (22 ms / 0.0009%) | must not get worse |
| mic − system file length, worst recording | **+9.17 s** | falls, and the *direction* is asserted |
| ring overflows per Session | **unmeasurable** | measured and on the record |
| pooled WER, close mics / far field | 22.6% / 29.4% | **unchanged** — nothing here touches the recogniser, and re-run it to know rather than assume |
| suite | 373 tests, 0 failures | stays that way |

Report every figure before and after. **A recording made after the fix is the
only proof** — the existing library was captured by the broken path and cannot
show a start offset that was never recorded. Plan for that: the increment needs
at least one new real dual-stream capture, and `--check-clock` is not a
substitute because it understates the fault twentyfold.

Where a change makes something worse, say so and revert it. That has happened
three times across increments 9 and 10 and every time the honest record was
worth more than the change.

---

## Decisions already made — implement, do not re-litigate

- **AD-4's single session clock stands.** One clock for Utterances. This
  increment is about making both Streams *start* on it, not about introducing a
  second time base.
- **AD-51 stands: the device's own counters are the authority on rate.** They are
  also now known not to be the authority on what reached the file, which is the
  gap this increment closes. Do not weaken AD-51 to cover it — add to it.
- **FR-97's measured offset and its application at the merge stay**, whatever
  happens at capture. A Meeting recorded before the fix still needs it, and an
  offset that has genuinely fallen to zero costs nothing to apply.
- **`StreamFileWriter`'s 16 kHz mono output stays.** It is a 16-fold saving with
  no consumer of the extra data, and re-litigating it is a different increment.
- **AD-1 stands: no allocation, no locks, no logging inside the IOProc.** Note
  the existing violation honestly — `RingBuffer` takes an `NSLock` on that
  thread and `AudioClockTap` now does too — and if the measurement says the lock
  is the cause, that is a finding, not licence to ignore the rule elsewhere.
- **Rejected, with reasons, so they are not re-proposed:** padding or trimming a
  file to match lengths; resampling to match lengths; widening any tolerance;
  a second session clock; making the merge compensate harder;
  `kAudioUnitSubType_VoiceProcessingIO` (AD-48 — its reference is our own output
  bus); retiring the wall-clock rate check (AD-51 — it is the fallback and it is
  what caught the original defect).

---

## Guardrails. These are not negotiable

- **This repository is public. User data must never enter it.** Run
  `./Scripts/check-no-user-data.sh` before every commit. No audio, no
  `meeting.json`, no embeddings, no real meeting titles, **no meeting IDs** — not
  in docs, not in fixtures, not in commit messages. Refer to a recording by its
  duration, as the spikes do. Corpus and results live in
  `~/Library/Application Support/MinutesEval`.
- **Check whether a recording is in progress before installing or relaunching
  the app, and before anything that opens an audio device** — compare the newest
  meeting's `mic.wav` size about two seconds apart. The author's real meetings
  are irreplaceable. This bit twice in increment 10: a 40-minute meeting ran
  through the middle of it and all device work had to wait.
- **Never assert a measurement you did not take.** If you claim a number, the
  command that produced it must be in the commit or the doc. Increment 10 had to
  correct a published 82% that was a mean of three percentages, and had to throw
  away three canceller implementations whose negative results were measurements
  of bugs.
- **Commit as you go**, on a branch, one coherent change at a time. Push and open
  a PR at the end. Note: `git push` currently fails with a 403 — the active `gh`
  account lacks write access. If it still fails, commit locally, say so, and do
  not improvise another remote.
- Existing test suite: **373 tests, 0 failures**, on a plain `swift test` with no
  environment variable. `MINUTES_RATE_TIMING` no longer gates anything — do not
  reintroduce a gate; increment 10 removed it and found that the gate had been
  hiding a crash that stopped 133 tests from running at all.
- **`--doctor` needs the installed app bundle**, not `.build/release`.

---

## Traps that already cost time here

Each of these is a mistake actually made in this project. Do not repeat them.

1. **Reading the code is not measuring it.** Two mechanisms above are visible
   from reading `StreamFileWriter`, and increment 10 threw away three canceller
   implementations that each looked right on the page: an epsilon that made the
   filter diverge to −30 dB, a double-talk freeze that was circular and froze on
   the first frame, and minimum statistics that are correct for noise and wrong
   for an echo. All three produced plausible-looking negative results.
2. **A control is worth more than the headline number.** The canceller's 7.3 dB
   looked like a weak pass until the same code scored 6.49 dB on a recording with
   **no echo in it**. Here the equivalent control is the Mic Stream: it loses
   353 frames where the System Stream loses 133,773, and any explanation that
   does not account for that asymmetry is wrong.
3. **Do not bound a search by what sounds physically plausible.** A 920 ms stream
   offset was twice dismissed as impossible before anyone measured that the two
   files start at different instants. A 1006 ms start offset would have been
   dismissed the same way last week.
4. **Do not tune a test until it passes.** Four attempts at a deterministic rate
   harness are recorded in `WavRateRepairTests`; the resolution was to remove the
   wall clock the test depended on, not to loosen the assertion.
5. **One recording is not a measurement.** A 50.3-minute recording shows 0.00%
   drift and a 31.6-minute one shows 0.37%. Anything concluded from either alone
   is noise.
6. **Verify the claim you are most confident about.** In this session I stated
   the drift was a constant per-call resampler loss, on an asymmetry that fitted
   it perfectly. The table above — a 50-minute recording losing nothing —
   refuted it within a minute of being built. Build the table first.

---

## Definition of done

1. Every phase of the BMAD chain run, and its artifacts written: PRD updated
   (FR-102+), spine updated (AD-57+) and `lint_spine` clean, UX spines updated
   where a surface changed, epics/stories written, `sprint-status.yaml`
   regenerated with 0 dropped orphans.
2. The root cause of the drift **identified by measurement** and named, with the
   command that identified it. If more than one mechanism contributes, say which
   contributes how much.
3. Both faults fixed at the source, or explicitly not fixed **with the
   measurement that ruled the fix out** — that is an acceptable outcome and a
   better one than an unmeasured change. FR-6's ±100 ms either holds on a new
   recording or is amended to what capture can deliver, with the number.
4. Samples received and not written are **counted and on the record**, whether or
   not the count is zero. `RingBuffer.didOverflow` reaches a consumer.
5. The numbers above re-measured and reported before and after, **including at
   least one new real dual-stream recording** — the existing library cannot
   demonstrate a start offset it never recorded.
6. Full suite green on a plain `swift test`.
7. `./Scripts/check-no-user-data.sh` clean.
8. `--check-clock`, `--check-echo`, `--check-rates` and `--doctor` all run and
   their output reported.
9. A retrospective naming what the measurements changed about the plan.

## Two open decisions, which are mine and not yours

1. **Three of my meetings still hold the doubled transcripts and phantom
   speakers on disk**, and one more (the 42.4-minute one) was recorded on
   loudspeakers with four mic clusters ruled out as the far end while the echo
   verdict came back `clean`. Reprocessing rewrites those notes. **Do not
   reprocess them.** The command already exists — `--reprocess <id>… --yes` —
   leave it for me.
2. On that same recording a cluster was ruled out at **0.345** against FR-100's
   0.35 threshold, inside the 0.023 margin the increment-10 calibration flagged.
   Whether that was a real person in the room is mine to check. **Do not move the
   threshold**; if you find evidence either way, record it and leave it.
