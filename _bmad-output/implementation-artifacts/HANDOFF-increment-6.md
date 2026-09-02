---
title: Handoff — increment 6, the first two Epic 11 stories
date: 2026-09-02
state: built, reviewed, merged, released as v0.1.1, installed and running
supersedes: nothing; HANDOFF-increment-4.md's outstanding items are still outstanding except where noted
---

# Handoff: increment 6 (stories 11.1 and 11.2)

The repository is public at **github.com/NiklasLuettringhaus/Minutes**, `main` is
protected, CI runs three jobs on every push and pull request, and **v0.1.1 is
released and installable in one command**:

```bash
curl -fsSL https://raw.githubusercontent.com/NiklasLuettringhaus/Minutes/main/Scripts/install.sh | bash
```

Verified end to end on this machine: the installer fetched v0.1.1, installed it,
and the app reports `0.1.1 (56)`, built from `v0.1.1`, and runs.

## What shipped, and the measurement behind it

| Story | What | Evidence |
| --- | --- | --- |
| 11.1 (FR-66) | A failure states its reason and its remedy, in the window and the menu bar | `AppState.lastError` had four writers and one reader — a CLI file |
| 11.2 (FR-67, AD-36) | Evidence of capture is signal, never duration | The old rule accepted **26 of 26** real streams; the new one accepts 23 |

The 11.2 number is the one worth remembering: **three of your thirteen meetings
have system streams of pure digital silence** — peak exactly 0.0000, one of them
32 minutes long — and all three were reported to you as *"Last recording
captured system audio"*.

Two defects were found only because the fix was written, and both are recorded
rather than smoothed over:

- **`StreamFileWriter.peak` decays** (`max(peak * 0.85, localPeak)`) because it
  is the UI level meter. So even the signal half of the old test was near zero by
  `stop()` on any meeting that ends quietly. The duration clause was masking it,
  which is why the check could never fail.
- **Evidence was read before the writer's final flush** in both streams.
  `StreamFileWriter.stop()` exists to flush the tail — its own comment records
  that draining once "truncated the tail of every recording" — so `duration` has
  always been slightly short, and the new evidence would have been wrong on a
  short capture with late speech. Both now read after the flush, which is also
  race-free: `stop()` joins the drain thread first.

## Read this first

`_bmad-output/implementation-artifacts/code-review-increment-6.md`. Nine
findings, two high. The most instructive is that the change **committed the same
class of error it was written to fix**: the new "no system audio" error asserted
a revoked permission, when a working tap with nothing playing produces identical
digital zeros. Recording a solo memo would have told the user to reset TCC for
nothing. It now names both causes and offers the test that discriminates.

The second high finding is the one to internalise about testing: the reviewer
reverted one line — `peak: peakEver` back to the decaying meter — and **all 174
tests still passed.** The rule was pinned; the wiring where the bug lived was
not. `StreamFileWriterEvidenceTests` now fails on that revert, verified by
re-doing it.

## Measured on this machine

| Claim | Figure |
| --- | --- |
| Test suite | **183 passing, 6 skipped, 0 failures**, 1.2 s |
| Real streams examined by the audio calibration | 26, from 13 meetings |
| Streams the old rule accepted / the new rule accepts | **26 / 23** |
| Longest silent stream previously reported as captured | 1893 s (32 min), peak 0.0000 |
| Fresh clone from GitHub | 1 s, 6.2 MB |
| Clean build + bundle + sign | **67 s**, 1.1 GB of artifacts |
| Command Line Tools alone can build this app | **No** — the FoundationModels macro plugin is Xcode-only |
| …with that one backend stubbed | **Yes** — so a 3.7 GB prerequisite is caused by one optional feature |
| Homebrew `--no-quarantine` | Removed as of 6.0.20 |
| `curl` sets a quarantine flag | **No** — so the curl install needs no bypass; a browser download does |
| Your meetings, after a full day of work | **53 of 53 files byte-identical** |

## Still not verified, and needing a human

1. **The banner has never been seen in the running app**, only rendered.
   `ImageRenderer` shows no focus, no animation and no menu bar.
2. **The menu bar items have never been seen at all.** `MenuBarExtra` content is
   not renderable from a terminal — a standing gap, not new here.
3. **No failure has been triggered live.** Decline the microphone prompt once and
   confirm the banner appears with a working button. That is the test that
   matters for 11.1.
4. **Why three real taps produced silence is unknown.** Revoked consent after a
   rebuild fits, but this increment identifies the symptom only. The next
   recording will now say so out loud, which is itself the diagnostic.
5. **VoiceOver does not announce the banner** when it appears. Flagged in review,
   deliberately not guessed at.
6. Everything in `HANDOFF-increment-4.md` that needed a human voice is still
   open: no enrolment sample has been recorded, so `VoiceEnrolment.run()` has
   still never executed and AD-32's deletion of the sample audio is still a
   `defer` no test has run.

## Next, in order

**Epic 11 has five stories left, and two are close to data loss:**

- **11.3** — every launch can delete the whole of `~/Documents/huggingface`.
- **11.4** — the default notes folder is `~/Documents/Minutes`, which iCloud may
  sync, while the app says nothing leaves the Mac.
- **11.5** — the first meeting downloads 460–630 MB with no warning.
- **11.7** — includes making the Apple Intelligence backend conditional, which
  drops the build prerequisite from full Xcode to `xcode-select --install`. That
  is the highest-leverage remaining item for anyone installing from source.
- **11.6** is **done in substance** — the version now comes from the tag
  (AD-33) and `--doctor` prints it, including labelling a development build as
  one. What is missing is an About surface in the window.

**The one decision still open** is the Apple Developer ID. It buys exactly one
thing now that Gatekeeper turned out not to be an obstacle for a `curl` install:
**consent surviving an update.** Today every update revokes microphone and
system-audio permission. FR-73 stays open until that is bought.
