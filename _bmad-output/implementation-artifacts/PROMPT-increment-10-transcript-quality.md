Run the entire BMAD flow autonomously to **substantially improve transcript
quality** in Minutes, the local-first macOS meeting recorder in this repo. Do not
ask me questions — every decision you need is below or in the named artifacts. I
will review at the end.

**No phases may be skipped.** Run the full chain in order, headless: `bmad-prd`
(update) → `bmad-architecture` (update) → `bmad-ux` (update) →
`bmad-create-epics-and-stories` → `bmad-sprint-planning` → implementation
(`bmad-dev-auto` / `bmad-dev-story` per story, or `bmad-build-auto`) →
`bmad-code-review` → `bmad-retrospective`. Finish with the implementation
working, tested, and committed.

---

## Read these first. They are measured, not speculative — do not re-derive them

- `_bmad-output/planning-artifacts/spikes/investigation-transcription-quality-2026-09-03.md`
- `_bmad-output/planning-artifacts/spikes/calibration-echo-threshold-2026-09-03.md`
- `_bmad-output/planning-artifacts/spikes/research-multisource-transcription-2026-09-04.md`
- PRD §4.14 (FR-89 to FR-100), spine AD-47 to AD-52, Epic 16 (15 stories)

Numbering, and **never renumber anything that exists**: next FR is **FR-101**,
next AD is **AD-53**, next epic is **Epic 17**. Epic 16's stories 16.9 to 16.15
are already written, tiered and FR-mapped — re-affirm them, do not rewrite them.

---

## State of play

`sprint-status.yaml` is accurate. Epic 16 is `in-progress`:

| Story | Status | What exists |
|---|---|---|
| 16.1 accuracy is measurable | **done** | `Scripts/eval/asr_eval.py`, `--asr` CLI, AMI corpus outside the repo |
| 16.2 detect the echo | **done** | `EchoDetector`, offset search, `--check-echo`; 8/8 correct on the real library |
| 16.3 floors | **done** | `EchoAnalysis.classify`, FR-91 floors, tests |
| 16.4 exclusion | **in-progress** | transcript rule shipped; the diarisation half was withdrawn |
| 16.5 count from the room | **withdrawn** | measured *worse*; superseded by 16.15 |
| 16.6 the record says so | **done** | `Meeting.echo`, unknown reads as unknown |
| 16.7 no sentence twice | **in-progress** | rule ships and residual is reported; the merged-output invariant test is missing |
| 16.8 no unmeasured accuracy claims | **done** | `measuredWordErrorRate`, UI, `.accurate` role removed |
| **16.9 – 16.15** | **backlog** | **this is your work** |

Backlog, in the order the evidence ranks them:

- **16.14** cancel the far end during the Session (linear + **non-linear
  residual** + double-talk detector, tap as reference)
- **16.13** read the output device instead of inferring echo from a threshold
- **16.15** find in-room voices by excluding clusters matching far-end embeddings
- **16.12** apply the two streams' start offset so the transcript is ordered by time
- **16.9** verify the capture rate against the **audio clock**, not `Date()`
- **16.10** carry the engine's confidence through the `Transcribing` port
- **16.11** record an interval the engine could not read as a gap

---

## The bar. This is the whole point of the increment

**A change that cannot be shown to improve a measured number does not ship.**
The harness exists precisely so this is enforceable rather than rhetorical.

Baseline to beat, pooled over three AMI sessions (7,374 reference words per
condition, errors pooled over pooled words — never average percentages):

| | close mics | far field |
|---|---|---|
| WER | 22.6% | 29.4% |
| content WER | 22.3% | 29.6% |
| proper-noun recall | 82% | 77% |

Echo, on the author's own library (3 of 12 affected; `--check-echo` prints it):

- transcript duplicates removed: **51%, 55%, 5%** of mic words; **0%** on all clean recordings
- **the in-room voice count must FALL** on the three affected recordings. It is
  currently 5, 6, 3. The withdrawn approach moved it to 7, 6, 5. A test must
  assert the *direction*, because assuming it is exactly what went wrong.
- unique mic content must not fall at all on any recording

Report every figure before and after. Where a change makes something worse, say
so and revert it — that has already happened twice in this epic and both times
the honest record was worth more than the change.

---

## Decisions already made — implement, do not re-litigate

- **Cancellation is permitted only at capture, only with a non-linear residual
  stage, and only once measured.** The upper bound on any *post-hoc linear*
  filter is 8.7–10.6 dB against the 20–40 dB a canceller needs. AD-48 as amended
  governs this; the bound is what makes the linear-only route closed, not a
  preference.
- **`kAudioUnitSubType_VoiceProcessingIO` is not a route.** Its echo reference is
  our own output bus and the conferencing app plays the meeting audio.
  `AVAudioEngine` also cannot be retargeted to a tap-backed aggregate device
  (AD-1). Do not spend time rediscovering either.
- **Never remove audio to fix a speaker count.** Muting fragments continuous
  speech and the clusterer splits one voice into several — measured, 5→7 and
  3→5. Filter *clusters*, using far-end embeddings from the System Stream.
  AD-31's threshold and its measured separation already exist for FR-63; point
  the same machinery at the opposite question.
- **Headphones mean no echo.** Read the output device (the property listener
  already exists for FR-8) rather than gating on a correlation threshold. Where
  the device fact and the signal measurement disagree, record both.
- **Absent means unknown, never zero and never clean.** Applies to confidence
  (16.10), to gaps (16.11) and to the echo verdict on old records.
- **Do not change the default transcription model.** Pooled, the English-only
  Parakeet leads by 2.3 points on close mics — but the per-session swing is ±8
  points, larger than the effect. Q19 records the revisit condition: nine or more
  sessions spanning native and non-native English.
- **Rejected, with reasons, so they are not re-proposed:** VAD segmentation (no
  effect on deletion rates, and deletions are 290 of our 405 baseline errors);
  guided source separation (an array technique; two channels give a fraction of
  seven-channel benefit); Canary-1B-v2 (measured 8.5 points worse, 22× slower, no
  timings); long-file chunking (measured unnecessary — 57.3 min at 100% coverage).

---

## Guardrails. These are not negotiable

- **This repository is public. User data must never enter it.** Run
  `./Scripts/check-no-user-data.sh` before every commit. No audio, no
  `meeting.json`, no embeddings, no real meeting titles — not in docs, not in
  fixtures, not in commit messages. Corpus and results live in
  `~/Library/Application Support/MinutesEval`.
- **Check whether a recording is in progress before installing or relaunching**
  the app: compare the newest meeting's `mic.wav` size about two seconds apart.
  The author's real meetings are irreplaceable.
- **Never assert a measurement you did not take.** If you claim a number, the
  command that produced it must be in the commit or the doc.
- **Commit as you go**, on a branch, one coherent change at a time. Push and open
  a PR at the end. Note: `git push` currently fails with a 403 — the active
  `gh` account lacks write access. If it still fails, commit locally, say so, and
  do not improvise another remote.
- Existing test suite: **306 tests, 0 failures**, and it must stay that way.
  `RateCorrectionTests` is opt-in behind `MINUTES_RATE_TIMING=1` because it
  measures live rate correction against a wall clock; **run it before finishing**
  (16.9 is what removes the need for the gate).

---

## Traps that already cost time in this epic

Each of these is a mistake actually made here. Do not repeat them.

1. **Do not bound a search by what sounds physically plausible.** A 920 ms
   stream offset was twice dismissed as impossible; the two files start at
   different instants (measured length differences −364 ms to +3,278 ms). The
   bound would have permanently excluded one of the three recordings it was
   written to protect.
2. **Choose the statistic that discriminates, not the one that sounds
   principled.** Envelope correlation and peak prominence both failed — a clean
   recording scored 6.82 on prominence and an affected one 1.18. What worked was
   the quantity the decision actually consumes.
3. **A synthetic fixture can invent the effect you are testing for.** Two
   "unrelated" speech streams built on one burst schedule correlated strongly on
   their shared silences, and the detector called them an echo. It was right.
4. **Do not tune a test until it passes.** Four attempts at a deterministic rate
   harness are recorded in `WavRateRepairTests`; `drainOnce` reads up to 8192
   samples per wake, so one drain can span two chunks and frames-consumed is not
   predictable from the chunk index.
5. **One session is not a measurement.** A model ranking drawn from one AMI
   session reversed when all three were pooled.
6. **Verify the claim you are most confident about.** The phantom-speaker fix was
   built, committed and described before anyone counted the speakers. When
   counted, it had made them worse.

---

## Definition of done

1. Every phase of the BMAD chain run, and its artifacts written: PRD updated
   (FR-101+ if needed), spine updated (AD-53+ if needed) and `lint_spine` clean,
   UX spines updated where a surface changed, epics/stories written,
   `sprint-status.yaml` regenerated with 0 dropped orphans.
2. Stories 16.9 to 16.15 implemented, or explicitly not implemented **with the
   measurement that ruled them out** — that is an acceptable outcome and a
   better one than an unmeasured change.
3. The numbers above re-measured and reported before and after, including the
   in-room voice count on the three affected recordings.
4. Full suite green, plus `MINUTES_RATE_TIMING=1` run once.
5. `./Scripts/check-no-user-data.sh` clean.
6. `--check-echo`, `--check-rates` and `--doctor` all run and their output
   reported. `--doctor` needs the installed app bundle, not `.build/release`.
7. A retrospective naming what the measurements changed about the plan.

## One open decision, which is mine and not yours

Three of the author's meetings still hold the doubled transcripts and phantom
speakers on disk. Reprocessing would fix them and rewrites those notes. **Do not
reprocess them.** Prepare the command and leave it for me.
