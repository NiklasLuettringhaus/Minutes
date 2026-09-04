# Code review — increment 10

**Date:** 2026-09-04
**Branch:** `increment-10-transcript-quality` against `986566d`
**Scope:** the whole diff — 51 source and test files, ~6,500 lines
**Spec:** Epic 16, stories 16.4 and 16.7 and 16.9 through 16.16
**Suite at review time:** 373 tests, 0 failures

---

## Verdict

Three defects found and fixed, one of them serious. Every one was in code the
tests already covered — which is worth saying plainly, because it means the
coverage was aimed at what the code was *supposed* to do rather than at what it
would do when a device behaved unusually.

Two further findings are recorded and **not** fixed, with the reasoning.

---

## Fixed

### 1. The writer could hold a whole meeting in memory and never write it (serious)

`StreamFileWriter`, capture path.

AD-44 says nothing reaches the file until the rate has settled. AD-51 made the
device's own clock the authority on when that is. Together they have a failure
mode neither has alone: `AudioClock.isDecisive` needs the measurement's tolerance
to narrow below 4.4%, which takes a number of *callbacks* rather than a number of
seconds — so a device delivering very large buffers takes proportionally longer,
and a device delivering one enormous buffer per second never gets there at all.
`verdict` then stays `.settling` for the whole Session, `pending` grows without
bound, and the file stays empty until stop.

Two hours is about four gigabytes held, and a crash loses all of it — which is
precisely what FR-9's incremental commit exists to prevent. The previous
wall-clock design could not do this because three seconds always elapse.

**Fixed:** the device is the authority on the *rate* and not on whether the
recording gets written. If its clock has not become decisive within
`audioClockPatience` (six seconds, twice the wall clock's own settling period),
the wall clock decides and the held opening reaches the file. Covered by
`testAnUndecidableDeviceClockDoesNotHoldTheRecordingForEver`, whose fixture is
one 16,000-frame callback per second — usable, and permanently undecidable.

### 2. The phantom attendee came back on the other side of the room

`Meeting.assignedSpeakerNames`.

Story 16.15 gives the far end reaching the microphone its own label so it stops
being counted as somebody in the room. `assignedSpeakerNames` then walked every
speaker and handed out numbers by *place* — and `farEndEcho`'s place is `.remote`,
so it took a Speaker number and rendered as "Speaker 3" beside the real remote
speakers. The defect the story exists to remove, one side over.

**Fixed:** `farEndEcho` gets its own name and consumes no number. Covered by
`testTheFarEndEchoNeverTakesASpeakerNumber`, which asserts both halves — that the
real remote speaker keeps the first number and that no second one was issued.

### 3. Three loads of the same record inside one stage

`Pipeline.transcribeStage` read `meeting.json` three times a few lines apart —
once for the echo verdict's device kind, once for the stream offset, once at the
top. A parse each, and three chances to read a record a concurrent update had
moved underneath them.

**Fixed:** read once, at the point capture's own facts are needed.

---

## Found, and deliberately not changed

### `AudioClockTap` takes a lock on the audio thread

AD-1's convention says no locks inside the IOProc. This takes an `NSLock` for the
duration of three compares and a handful of adds.

Not changed, for two reasons that should both be stated rather than one. First,
`RingBuffer` — which every captured sample already passes through — takes the
same lock on the same thread for a `memcpy` of up to 8,192 floats, so this is
strictly smaller than what the path already does and changing one without the
other would be theatre. Second, the alternative is a lock-free triple buffer,
which is real work and buys nothing measurable until the existing one is a
problem.

**What would change this:** any observed dropout. The continuity measurement
this increment added is exactly the instrument that would show it, and on the
author's hardware it currently reports **0 frames missing of 388,096** over an
eight-second capture on both streams.

### `EchoCanceller.process` is O(n²) in the filter length

`history.removeFirst()` on a 1,600-element array, once per sample. A circular
buffer is the obvious fix.

Not changed because the component is deliberately not in the capture path
(AD-55), and optimising code that is not shipping — on the strength of a
measurement that says it should not ship — is work aimed at the wrong question.
`--check-aec` takes a few minutes over the whole library, which is what it needs
to be. **If FR-99 is ever revisited this is the first thing to fix**, and it is
recorded here so it is found rather than rediscovered.

---

## Checked and sound

- **Every persisted type added a field, and every one has a hand-written
  `init(from:)`.** `Meeting` gains seven, `Utterance` one, and `RateFidelity`,
  `StreamContinuity`, `OutputDevice`, `TranscriptGap` and `RuledOutVoice` are
  new. `EchoAnalysis` had shipped in increment 9 with the *synthesised* decoder
  and was one field away from throwing `keyNotFound` on every meeting recorded
  since; it now has one too. Verified against the real library rather than
  asserted: `--doctor` reports **21 readable, 0 unreadable**.
- **FR-91's floors survive cancellation.** The Wiener gain is 1 where the
  reference is silent by arithmetic rather than by a branch, and the fixture test
  measures the loss at ≤ 1 dB.
- **Echo exclusion cannot delete unique content**, unchanged: the transcript rule
  still requires the text to agree, and `--check-echo` reproduces increment 9's
  figures exactly (51%, 55%, 5%).
- **The AMI corpus is unchanged.** Re-run through the shipping path after every
  change in this increment: 22.6% / 29.4% pooled WER, byte-identical to the
  baseline. Nothing here was supposed to move it and nothing did.
- **`RoomVoices` never empties the room**, and a single mic voice is never ruled
  out — the case where a wrong answer would be worst.
- **No new `removeItem` outside AD-42's allowlist.** Two were added
  (`ClockCheck`, `AecCheck`), both on temporary directories, both with their
  reason recorded in the allowlist the test reads.
- **Core imports Foundation only.** `AudioClock`, `StreamAlignment`,
  `TranscriptGaps`, `RoomVoices`, `OutputDeviceKind`, `EchoCancellation` and
  `TranscriptConfidence` are all decision types with no framework in them; the
  Accelerate and CoreAudio work sits in adapters. `CorePurityTests` passes.
