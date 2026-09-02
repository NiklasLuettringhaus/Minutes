---
title: Code review — increment 6, stories 11.1 and 11.2
date: 2026-09-02
scope: branch fix/honest-failure-reporting (FR-66, FR-67, AD-36)
lens: adversarial, run as a subagent against the committed diff
verdict: nine findings, two high; all nine addressed; one was the same class of defect the stories exist to remove
---

# Code review: saying why it failed, and not calling silence success

Nine findings. Two were serious, and the more interesting of the two is that
**the change committed the same category of error it was written to fix.**

## The two that mattered

### 1. The app diagnosed what it cannot distinguish — HIGH

`SessionCoordinator` raised a new error when the system stream ran and produced
silence, and its recovery text said: *"Enable Minutes under Audio Recording, or
run the reset command in Settings."*

But a working tap with nothing playing delivers **exact digital zeros** — the
same signature as a revoked permission. The calibration spike states this
plainly ("identifies the symptom, not the cause"); the error string went ahead
and named a cause anyway.

The failure scenario is ordinary, not exotic: a solo memo, an in-room meeting
with nothing playing, a call where the far end never unmutes. Each would raise a
banner instructing the user to reset TCC for a permission that was never broken.

So the old rule's false positive had been traded for a false negative carrying a
confident wrong remedy — which is worse than the bug it replaced, because a
wrong instruction costs the user work.

**Fixed** by naming both causes, stating that macOS cannot separate them, and
adding `Remedy.runAudioTest` so the offer is the thing that *discriminates*
rather than a fix for whichever cause was guessed. A tap that fails to
*establish* keeps the settings remedy, because that one is genuinely diagnostic.

### 2. The fix had no test where the bug actually lived — HIGH

The reviewer did the decisive thing: reverted `peak: peakEver` back to the
decaying meter — reintroducing the original defect verbatim — and **all 174
tests still passed.**

`AudioEvidenceTests` pinned the *rule* thoroughly and would fail if the duration
clause returned. Nothing pinned the *wiring*, and the wiring is where the
decaying-meter bug lived. `peakEver` and `nonSilentInputFrames` appeared nowhere
in `Tests/`, and the calibration test re-implemented the arithmetic against a
finished WAV rather than exercising the writer.

**Fixed** with `StreamFileWriterEvidenceTests`, which drives the real writer
through the real ring buffer using synthetic audio — loud, then a long silent
tail, the shape of essentially every real meeting. Confirmed by re-doing the
revert: it now fails, reporting a peak of 0.050 where 0.5 was required. A
companion test asserts the meter *still* decays, so the fix cannot overshoot and
freeze the level bars. `CorePurityTests` was added in the same pass, because
"Core imports Foundation alone" was a comment rather than a check.

## The other seven

| # | Finding | Resolution |
| --- | --- | --- |
| 3 | "On every pane" was false for 2 of 6 — `GettingStartedPane` and `MeetingsPane` build their own roots, so the banner was absent from the pane the silence remedy sends the user to | Banner moved to the window root |
| 4 | The chunk accumulator resolves to ~170 ms, so three separate clicks clear the half-second threshold; the docs claimed a finer discrimination | Approach kept — per-sample counting is *worse*, since every waveform crosses zero constantly — and the claim corrected to state the real resolution |
| 5 | Two calibration assertions could not fail: `guard falsePositives > 0 else { skip }` followed by `XCTAssert(falsePositives > 0)` | Rewritten to assert per-stream properties; the skip now covers only "this machine has nothing to demonstrate on" |
| 6 | The accumulators advance before the file write, so a write failure could produce *"only 3 seconds of the 1 second recorded"* | Sentence clamped; the write failure is still logged where it happens rather than hidden |
| 7 | The Test Playground's failure text blamed a mute that cannot be set on that path | Removed; replaced with input device and input volume, which can |
| 8 | The new error was gated on `duration > 0`, silently dropping a tap that started and delivered no callbacks — reproducing the exact silence FR-66 exists to remove | Gated on `systemTapEstablished` instead |
| 9 | A pane-selecting remedy pressed from the menu bar set `paneRequest` with no subscriber, because the window is created lazily | Opens the window first; the remedy→pane mapping now lives beside the remedy |

## What the review checked and found correct

Recorded because a review's silence should be informative rather than ambiguous:

- **Units and stereo.** `nonSilentSeconds` divides by the input rate,
  `duration` by the 16 kHz output rate, and they agree because output frames
  scale by the resample ratio. The frame count added is frames, not samples, so
  stereo is right.
- **Thread safety, and whether the change worsened it.** It did not. With the
  ordering fix the evidence counters are read only after `stop()` has joined the
  drain thread. `peak` and `framesWritten` remain raced by the level timer,
  which is pre-existing and untouched.
- **A muted mic cannot fabricate a system failure**, and a muted writer's
  evidence correctly agrees with the file it wrote.
- **`isDegraded` does not fire the new error** — a tap that never started is
  excluded, and reported itself at start.
- **No clobbering of `lastError`**, and only one error is representable at a
  time, so a later true failure replaces an earlier one.
- **`ViewThatFits` always has a layout**, and `controls(_:)` appears in both
  branches so Dismiss is always reachable.
- **`UIShot` does not break** on `PaneScaffold`'s environment requirement.
- **`AudioEvidence` is Foundation-only.**

## The one it found that I had already found

The review opened on the uncommitted tree and flagged that both streams read
their evidence *before* the writer's final flush. That was real; it had been
fixed mid-review, after I traced `StreamFileWriter.stop()` and found the comment
recording that draining once "truncated the tail of every recording". Worth
noting because the two accounts agree on both the defect and the fix, which is
the useful outcome when a review and an author overlap.

## Still not verified, and needing a human

- **The banner has never been seen in the running app**, only rendered.
  `ImageRenderer` shows no focus, no animation and no menu bar.
- **The menu bar items have never been seen at all.** `MenuBarExtra` content is
  not renderable from a terminal; this is a standing gap in the project, not
  new here.
- **No failure has been triggered live.** Declining the microphone prompt on a
  real machine is the test that matters.
- **Why three real taps produced silence is still unknown.** Revoked consent
  after a rebuild fits, but this increment identifies the symptom only.
- **VoiceOver does not announce the banner** when it appears. Flagged by the
  review, not fixed: the right behaviour needs a human with VoiceOver on.
