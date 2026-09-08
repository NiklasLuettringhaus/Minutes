---
title: Retrospective — Minutes, autonomous BMAD run
date: 2026-08-31
mode: headless (user away for the whole run)
verdict: accept with three items requiring the user
---

# Retrospective — autonomous BMAD run

## What the run produced

| Artifact | Substance |
|---|---|
| Product brief + addendum | Scope, thesis, and verified platform research |
| PRD | 48 FRs with testable consequences, 8 NFRs, build-order tiers, 17 indexed assumptions |
| UX spines | `DESIGN.md` (34 resolving tokens) + `EXPERIENCE.md` (5 key flows) + one key-screen mock |
| Architecture spine | 21 ADs, lint-clean, two reviewer passes |
| Epics | 7 epics, 43 stories, all 48 FRs covered exactly once (verified programmatically) |
| Sprint status | 43 stories tracked |
| Code | ~5,000 lines of Swift, 9 commits, 33 tests, a signed runnable `.app` |
| Reviews | Version-verification, adversarial, and code review — 5 defects found and fixed |

## What worked, and is worth repeating

**Spiking before writing the architecture was the single highest-value decision.**
Four spikes ran against real APIs before any AD was committed. They produced three
corrections to published documentation, one of which — `AudioDeviceCreateIOProcIDWithBlock`
deadlocking on a tap-backed aggregate device — would have been an unexplainable hang
discovered mid-build, with no crash log to work from. The architecture then encoded
each finding as a rule with the reason attached, so the build could not regress into it.

**Verifying by running, not by reading.** Two bugs were only findable by executing
the real thing: models landing in `~/Documents` (which also broke the setup
checklist's readiness check), and Whisper hallucinating `"Thank you."` over a silent
microphone — inventing a participant, which quietly undermines the product's core
attribution claim. Neither is visible in code review.

**The adversarial architecture pass earned its keep.** The original 17 ADs were
strong on OS boundaries — where the spikes had forced precision — and thin on
ownership of *persisted* state. Constructing two compliant-but-incompatible
components found four holes, the worst of which would have let a mic-only recording
be presented as a full one.

**The readiness gate was not a rubber stamp.** It caught that no story built the
main window and no story owned the meeting record — both hard dependencies for a
dozen later stories. Fixing them before the build cost minutes; after, it would
have meant reworking Epic 2 and Epic 5.

**Building the self-test as a product feature, not scaffolding.** The Test Playground
exists because macOS offers no API to query system-audio permission. Making it a
real feature meant the same code path could verify the build headlessly — which is
the only reason an autonomous run could confirm the pipeline at all.

## What went wrong, and what it cost

**I wrote a deadlock into my own test harness.** `sem.wait()` on the main thread
while the work was `@MainActor`. Cost one debugging cycle, and it is exactly the
same class of bug as the CoreAudio deadlock I had just spent four spike iterations
finding — I should have recognised it faster.

**I trusted a published guide over the SDK.** The article recommending the block-based
IOProc variant was recent, specific, and wrong. The architecture now says to prefer
SDK headers and working sample repos over web summaries; that rule was learned the
expensive way.

**I invented a product name.** "Kokoro" in the first draft, replaced with "Minutes"
during the review pass for being arbitrary and exotic for a utility. Reasonable to
name an unnamed thing, but it should have been flagged as a decision from the start
rather than presented as settled.

**Type-checker timeouts from over-chained expressions.** Three functions in the
heuristic backend had to be rewritten with explicit types. Self-inflicted; a habit
worth breaking.

**The interactive skills fought the mandate.** `bmad-create-epics-and-stories` and
`bmad-build` are menu-gated with mandatory human checkpoints and no headless mode.
Running "100% autonomously" meant auto-confirming those gates and, for the build,
working at epic-wave granularity rather than 43 separate spec-writing loops — which
would have consumed the day producing specs instead of code. That was a judgment
call, and it is logged rather than hidden.

## Action items

| # | Item | Owner | Condition |
|---|---|---|---|
| 1 | Join a real Slack huddle and confirm the Detection Prompt appears | Niklas | Blocks trusting detection at all; PRD open question 8 |
| 2 | Review PRD §14 (17 assumptions), especially reading "etc." as summary/decisions/actions | Niklas | Before any further building on the PRD |
| 3 | Decide whether an Apple Developer certificate is obtainable | Niklas | Would remove the rebuild-revokes-consent problem entirely |
| 4 | Calibrate the Speaker Profile threshold (currently 0.45, a guess) against real colleagues | Niklas + follow-up | After a week of real meetings |
| 5 | Look at every UI pane once — none has been seen by a human | Niklas | First launch |
| 6 | Add Chrome as a Watched App | follow-up | Only once detection is proven for Slack and Teams |
| 7 | Confirm audio survives an AirPods switch mid-recording | follow-up | PRD open question 7 |
| 8 | Turn on Apple Intelligence to light up the better metadata path | Niklas | Optional; heuristic backend covers it meanwhile |

## Honest assessment

The product's hard parts work: dual-stream capture, on-device transcription,
diarization that got 6/6 lines right across two models, and a Markdown file that is
useful without editing. The risk is concentrated in exactly one place — whether
detection fires during a real call — and in the gap between "compiles and is
covered by tests" and "a human has looked at it". Eleven of 43 stories are marked
`done` on evidence; the other 32 are marked `review` rather than `done`, which is
the accurate state and not a formality.

---

# Retrospective — Epic 16, increment 10

**Date:** 2026-09-04 · **Mode:** headless · **Range:** `986566d..2df2b5d`, 11 commits
**Evidence:** the diff, `spikes/calibration-room-voices-2026-09-04.md`,
`spikes/measurement-echo-cancellation-2026-09-04.md`,
`code-review-increment-10.md`, `sprint-status.yaml`, and the recorded output of
`--check-clock`, `--check-echo --diarize`, `--check-aec`, `--check-rates`,
`--doctor` and `asr_eval.py pool`.

## What the measurements changed about the plan

This is the section the increment exists for. Four things the plan asserted were
overturned by taking the measurement, and in three of them the plan was the
*more* plausible answer.

**1. The plan spent a story searching for something the callbacks already
carried.** FR-97 said the two Streams' start offset should be *measured*, and
left where as `[NOTE FOR PM]`. Story 16.2 had already built a correlation search
for the acoustic delay and it returned 920 ms on one recording, which was twice
dismissed as physically impossible. Reading the capture path for a different
story found that both adapters receive the device's own sample counter and a
host-time stamp in every callback and bind them to `_`. The offset is a
subtraction of two numbers the process was already being handed — and it works
on the nine *clean* recordings, which a correlation search cannot touch because
there is nothing correlated to align on. One discarded fact answered three
requirements (AD-53).

**2. The residual echo suppressor — the thing AD-48 was amended to permit —
buys nothing here, and the control is what says so.** FR-99's argument was
sound: the linear bound is 8.7–10.6 dB because the loudspeaker path is not
linear, and a power-domain stage does not need it to be. Built and measured, the
best figure is **7.3 dB against a 20 dB bar**. What settles it is not that
number but the control: on a **headphones** recording, where no echo can exist,
the same canceller reports **6.49 dB** — more than two of the three genuinely
affected recordings. It is attenuation, not cancellation, and at 6× suppression
the clean figure (8.80 dB) *exceeds* the affected one (7.32 dB). There is no
operating point that tells the two apart.

**3. Three canceller implementations failed before the fourth worked, and every
one was caught by a control rather than by reading the code.** `+ 1e-6` as the
NLMS regularisation let a near-silent reference explode the weights: −30 dB, the
canceller adding a thousand times the energy it removed. A double-talk freeze
gated on "the filter already explains half this frame" was circular and froze on
frame one: 1.4 × 10⁻⁸ dB. Minimum statistics for the power coupling — correct
for *noise*, which is stationary — landed on frames where the echo had not
arrived: mean gain 0.997 at 32× suppression, the stage doing nothing at all.
**Every one of the three would have produced a publishable-looking negative
result.** What stopped them was printing the mean applied gain beside the ERLE: a
stage that is not working and a stage working on audio it cannot help are
indistinguishable without it.

**4. A threshold measured for one question survived being pointed at the
opposite one, and nobody knew until it was measured.** AD-31's 0.35 was
calibrated between voices captured the same way; FR-100 asks it to compare a
voice that has been through a loudspeaker, a room and a different microphone
against its own electrical copy. AD-56 forbade using it without a cross-stream
measurement, so the mechanism reported distances and changed nothing until one
existed. It separates: **0.049–0.295 matched against 0.373–1.027 kept**, with
0.35 in the gap. The in-room count falls 5→4, 6→1, 3→1 on the affected
recordings and **not one of nine clean recordings loses a voice**.

## What the plan got right, and it is worth naming

The build order in the epic was **dependency order, not value order**, and it was
argued for in writing before anything was built: 16.14 needs the aligned
reference 16.9 provides and the device gate 16.13 provides. Had the epic been
built in the evidence ranking it named, the canceller would have been built first
— on an unmeasured offset and no gate — and its negative result would have been
uninterpretable.

## Findings from the code review, folded in

Three defects, **all in code the tests already covered**, which is the finding as
much as the defects are: the coverage was aimed at what the code was meant to do
rather than at what it would do when a device behaved unusually.

- The writer could hold a whole meeting in memory and never write it. AD-44 says
  nothing reaches the file until the rate settles; AD-51 made the device the
  authority on when that is; and decisiveness needs a number of *callbacks*, not
  of seconds. A device delivering one enormous buffer per second is usable and
  permanently undecidable. Four gigabytes held over two hours and an empty file
  if the process dies — exactly what FR-9's incremental commit prevents.
- The phantom attendee came back on the call's side: `farEndEcho`'s place is
  `.remote`, so `assignedSpeakerNames` gave it a Speaker number and it rendered
  as "Speaker 3" beside the real remote speakers.
- Three loads of the same record a few lines apart in one pipeline stage.

## What the epic produced, against what it promised

| | before | after | source |
|---|---|---|---|
| pooled WER, close mics / far field | 22.6% / 29.4% | **22.6% / 29.4%** | `asr_eval.py pool`, re-run through the shipping path |
| pooled proper-noun recall, close mics | 82% *(a mean, forbidden)* | **81%** *(pooled)* | FR-101 |
| in-room voices, three affected recordings | 5, 6, 3 | **4, 1, 1** | `--check-echo --diarize` |
| in-room voices, nine clean recordings | 2,5,3,2,4,2,2,2,2 | **unchanged** | the control |
| transcript duplicates removed | 51%, 55%, 5% | unchanged | echo rule untouched |
| rate check tolerance, system tap | 12% declared | **0.63% derived** | `--check-clock` |
| frames the device produced and we never got | unmeasurable | **0 of 388,096** | `--check-clock` |
| `RateCorrectionTests` | gated, ~1 run in 3 failed | **ungated, 8/8 including under load** | `swift test` |
| tests run by a plain `swift test` | 173 of 306 *(the rest lost to a crash)* | **373, 0 failures** | `swift test` |
| ERLE from cancellation | unmeasured | **7.3 dB against a 20 dB bar — not shipped** | `--check-aec` |

**Nothing moved the AMI numbers, and nothing was supposed to.** Every change here
is to capture, alignment, attribution or disclosure; the recogniser and its input
are untouched. Re-running the corpus through the shipping path after the work
is how that is known rather than assumed.

## Action items

| # | Item | Owner | Condition |
|---|---|---|---|
| 16-1 | Reprocess the three affected recordings — **the user's decision, command prepared, not run** | Niklas | It rewrites those three notes; see the increment's closing report |
| 16-2 | Decide Q22: should the detector resample so the eight repaired recordings can be echo-checked at all? | whoever next touches `EchoDetector.read` | A third of the library is currently unanalysable |
| 16-3 | Watch the 0.023 margin on FR-100's keep side | follow-up | Two genuine in-room voices sit at 0.373 and 0.389; a real attendee at 0.36 would be ruled out |
| 16-4 | If FR-99 is ever revisited, fix `EchoCanceller`'s quadratic history first, and measure at the capture rate rather than at 16 kHz | follow-up | Both recorded in the review; neither worth doing while the measurement says do not ship |
| 16-5 | Confirm the in-room count of 4 on the mild recording is actually right | Niklas | Only the *direction* is measured; the absolute count is unverified against the room |
| 16-6 | Q19 still open: nine or more sessions before the default model moves | follow-up | Unchanged by this increment |

## Acceptance verdict

**Machine verdict: rejected.** One story in epic 16 is not `done` —
`16-5-the-people-in-the-room-are-counted-from-the-room` — and the rubric makes
any unfinished story a rejection regardless of why.

**Why a human would likely override to `accepted-with-open-items`:** 16.5 was
*withdrawn on measurement* in increment 9 (muting made the count worse: 5→7,
6→6, 3→5) and is superseded by 16.15, which is done and whose number moves in the
right direction on all three recordings. Leaving it un-`done` is the accurate
record of a story that was refuted rather than delivered. That override is the
user's to make and has not been made here.

Fifteen of sixteen stories are `done`, including 16.14 — built, measured, and
deliberately not shipped, which the epic's own bar names as an acceptable and
better outcome than an unmeasured change.

## Assumptions recorded (headless run)

- Epic 16 was supplied, not detected.
- `pending_stories` = `["16-5-..."]`; proceeding over it was not confirmed by a
  human, and the machine verdict above reflects it.
- The acceptance verdict is the machine's. No human override was sought or given.
- Every action item above is *proposed*, not applied.
- Phase 3's team discussion was skipped, as headless runs require.
- No previous epic-16 retrospective existed, so there is no follow-through record
  to check.

---

# Retrospective — Epic 17, increment 11

**Date:** 2026-09-08 · **Mode:** headless · **Range:** `ef3d494..HEAD`, 8 commits
**Evidence:** the diff, `spikes/measurement-stream-alignment-2026-09-07.md`,
`code-review-increment-11.md`, `sprint-status.yaml`, `Scripts/decompose-capture.py`,
`Scripts/measure-stream-drift.py`, and the recorded output of `--check-drain`,
`--check-clock`, `--check-rates`, `--check-echo`, `--doctor` and `asr_eval.py`.

## What the measurements changed about the plan

The section this increment exists for. **Six things the plan or I asserted were
overturned by measuring them, and in four of them the assertion was the more
plausible answer.**

**1. The mechanism the increment was scoped around never happened.** The prompt's
leading candidate, and the reason `RingBuffer.didOverflow` existed at all, was
ring overflow: a producer dropping samples because the consumer fell behind. It
is now counted rather than flagged, and across every reproduction taken — idle,
under six competing threads, under ten, and on five producer shapes — **the drop
count is zero and the ring's high-water mark never exceeded 3.84% of a
ten-second capacity.** Not once. The instrument built to catch it exonerated it,
which is the outcome an instrument is for.

**2. The resampler was refuted before a story was written on it, and the
refutation was cheap.** The second candidate — a filter tail discarded per
`convert` call — takes twenty minutes to test against `AVAudioConverter` driven
exactly as the writer drives it. The deficit is a **constant ~11 frames in
total** across runs of 1,500 to 20,000 calls, and across uniform *and* arbitrary
chunk sizes: 0.0003%, four orders of magnitude too small, and not per-call at
all. One candidate gone for a reason on the first afternoon.

**3. The one that was actually true was the one nobody had proposed.** The loss
is in the conversion step and it is neither of the two mechanisms the increment
named. The identity localised it — dropped 0, write failures 0, unaccounted 0,
`produced` short of `expected` — and two changes remove it, each sufficient
alone: asking the converter whether it has more, and giving it more room to
answer. **Before: 7 of 10 cells lost audio, worst 4.200%. After: 0 of 10.**

**4. And *why* those changes work is still not known.** This is the honest end of
the increment. The arithmetic says the output buffer always covers the chunk in
hand, so no backlog should form — and a deterministic 8 kHz fixture at the old
64-frame slack writes every frame. The loss appears only under load. I published
a mechanism for it, the arithmetic refuted it inside an hour, and the note now
carries the refutation next to the claim. It is PRD Q27, not a story.

**5a. And then the real Session corroborated it from the other side.** The
first capture on the fixed build spent **693 ms** building the tap chain — against
41–63 ms on a cold probe, which is the twentyfold understatement the prompt
predicted, measured. So the serialisation term genuinely is worth hundreds of
milliseconds on a real Session, and AD-59 removes all of it: 0.045 ms between the
two starts. **But FR-6 still fails, in the opposite direction.** The residual is
−209 ms and every millisecond of it is the microphone taking 209 ms to deliver
its first sample where the tap takes 0.07 ms. So ±100 ms is withdrawn as a claim
about capture rather than replaced with a wider number — a wider number would be
a new assertion of exactly the kind that has been wrong for eleven increments.

**5. The number that justified half the increment was the worst of four.** The
+1,006 ms start offset was measured on one recording. Three more instrumented
recordings arrived during the increment and read **+21, +53 and +60 ms** through
the same unfixed code. The serialisation is real, it is removed, and it is worth
far less on a median meeting than the single measurement implied. The reorder is
still right — it removes a *variable* term whose worst case is a second — but the
scoping was built on an outlier and saying so is cheaper than having it noticed.

**6. The QoS suspicion was instrumented and then not run, and when run it was
wrong.** "A `.utility` drain thread is scheduled on the efficiency cores and
throttled" is a good story, it was the reason the seam existed, and the seam was
documented as swept while `measure` was called with a hard-coded `.utility` — the
review caught that. Swept properly, raising the thread to `.userInitiated` and
changing nothing else leaves **6 of 10 cells still losing audio**. Not the
mechanism.

## What the plan got right, and it is worth naming

**Ordering the instrument before the fix was the whole increment.** Tier 7 and
Epic 17 both said so in writing before anything was built, and story 17.6 was
deliberately left unspecified — "the fix the measurement names". Had the epic
been built in the order the evidence *looked* like it wanted, the first story
would have been a bigger ring buffer, which is a tolerance, and it would have
moved the number on some recordings and not others: the exact signature this
defect already had.

**Building the table before forming a hypothesis.** The entering assumption was
a constant per-call cost. The drift table across the whole library killed it in
a minute — a 50.3-minute recording losing nothing beside a 31.6-minute one losing
seven seconds — before any code existed to be attached to it.

## Findings from the code review, folded in

Fourteen, and **the two serious ones were created by this increment rather than
found in passing**, which is the finding as much as the defects are.

- **The reorder that fixes the start offset opened a resource leak that could not
  exist before it.** `createIOProc` retains `self`, so `deinit` can never fire;
  AD-59 moved the chain build to *before* the microphone starts, so a microphone
  that throws now drops a fully-built chain — leaking a system-visible aggregate
  device, a global process tap and a drain thread that never exits, once per
  retry.
- **The identity built to find missing audio had a term counted twice.** The held
  opening was in `residentFrames` and `consumedFrames` at once, making
  `unaccountedFrames` negative by up to six seconds. Invisible only because every
  caller reads after the flush; the first live readout would have failed its own
  identity and pointed at a mechanism that does not exist. An instrument that
  lies is worse than no instrument.
- Two defects were in the **tests this increment added**: one crashed the whole
  process with signal 5 by force-unwrapping a temp directory its own `setUp`
  skips before assigning — the shape of the crash increment 10 found stopping 133
  tests — and one failed for a reason it was not testing, which was resolved by
  moving the cycling into a gated measurement rather than by loosening the
  assertion.

## What the epic produced, against what it promised

| | before | after | source |
|---|---|---|---|
| start offset, `--check-clock` | +40, +41, +62 ms | **+14, +15, +15, +16, +18 ms** | `--check-clock 6` ×5, installed build |
| gap between the two device starts, probe | the whole tap-chain build | **+0.0 to +0.1 ms** | the same runs |
| gap between the two device starts, **real Session** | **693 ms** of tap-chain build | **0.045 ms** | first Session on the fixed build |
| start offset, **real Session** | ~+484 ms under the old order | **−209 ms**, all of it the mic's own warm-up | the same Session |
| FR-6's ±100 ms | asserted, never met | **withdrawn as a claim; measured instead** | FR-6 as amended |
| audio lost on a **real Session**, both Streams | 0.005% / 0.325–0.426% | **0 frames. Every term equal, not "within a callback"** | the same Session |
| audio consumed and never written, under load | **7 of 10 cells, worst 4.200%** | **0 of 10 cells** | `--check-drain 10 6` ×2 |
| drain thread at `.userInitiated` instead | — | 6 of 10 cells still lost | the same sweep |
| ring overflows, every cell of every sweep | **unmeasurable** | **0** | `--check-drain` |
| ring high-water mark | unmeasurable | **≤ 3.84% of 10 s** | `--check-drain`, `--check-clock` |
| resampler loss per call | assumed to be the cause | **~11 frames in total, 0.0003%** | a 20,000-call sweep |
| `mic.wav − system.wav`, worst recording | +9.17 s | decomposed: **0.84 s offset + 8.37 s unwritten** | `Scripts/decompose-capture.py` |
| records readable | 24 of 24 | **31 of 31, 0 unreadable** | `--doctor`, installed build |
| `--check-rates` | 23 checked, 0 failing | **28 checked, 0 failing** | `--check-rates` |
| `--check-echo` | 51%, 55%, 5% duplicates | **unchanged: 3 affected, 14 clean** | `--check-echo` |
| pooled WER, close mics / far field | 22.6% / 29.4% | **22.6% / 29.4%** | `asr_eval.py sweep` then `pool` |
| suite | 373 tests, 0 failures | **415 tests, 1 failure** | `swift test` |

**Nothing moved the AMI numbers, and nothing was supposed to.** The corpus was
re-transcribed through the shipping path after the change and pooled by the
harness: byte-identical. Re-running it is how that is known rather than assumed.

**The one failing test is not this increment's**, and that is checkable rather
than assertable. `EnrolmentCalibrationTests` is byte-identical to base, as are
`VoiceMatch` and `RoomVoices`; it fails because the library gained a meeting
recorded at 15:01 on 7 September — by the *installed base build* — whose in-room
pair sits at 0.2322 against AD-31's 0.35. The library changed, the code did not.
Recorded and not fixed: the threshold is the user's.

## What was not delivered, and why

- **A 42-minute loudspeaker meeting on the fixed build.** A real four-minute
  Session on a Bluetooth headset *was* captured and it is the increment's
  strongest evidence — both Streams' identities close **exactly**, every term
  equal to every other, and it measured 693 ms of tap-chain build now paid before
  either device starts. What it is not is the condition the drift likes: 42
  minutes, loudspeakers, video-call load. The instrument answers that on the next
  such Session without anybody remembering to look.
- **Why extra output room helps** (Q27), above.
- **The `rebuildForDeviceChange` defect** the review found: a failed rebuild nils
  the writer and ring mid-recording, contradicting its own comment and discarding
  the System Stream. Pre-existing, FR-8's territory, never observed on this
  hardware, and a fix for an unobserved fault is how a different defect gets
  written.

## Action items

| # | Item | Owner | Condition |
|---|---|---|---|
| 17-1 | **I interrupted a recording.** `Scripts/build-app.sh` installs into `/Applications` rather than staging, and I ran it while a Session was live: the 09:48 meeting stopped at 197 s. Audio intact, `stage: captured`, recoverable via *Finish transcription* | Niklas | Immediate; the app is relaunched and consent may need re-granting |
| 17-2 | Make `build-app.sh` refuse to install while a recording is live, or split staging from installing | follow-up | It is the guardrail that failed, and a script that cannot be run safely by reading its first page is the defect |
| 17-3 | **Four Sessions on this machine hold a microphone that delivered nothing** — `--check-echo` reports "mic.wav holds no audio" four times, and one Session recorded 0.13 s of mic against 57 s of system with `framesObserved` at zero | Niklas | Predates this increment; a real fault with no story |
| 17-4 | Q27: why more output room helps under load | follow-up | Needs visibility into `AVAudioConverter`'s own accounting |
| 17-5 | The 9.353% outlier in the shipping configuration, taken under memory pressure, split not captured | follow-up | Reproduce under memory pressure rather than CPU load |
| 17-6 | `rebuildForDeviceChange` discards the System Stream on a failed rebuild | follow-up | FR-8; unobserved on this hardware |
| 17-7 | `EnrolmentCalibrationTests` now fails on this library at 0.2322 against 0.35 | Niklas | Bears on the 0.023 margin already flagged as 16-3 |

## Acceptance verdict

**Machine verdict: rejected.** The suite is not green on this machine — one
failure — and the rubric makes that a rejection regardless of cause.

**Why a human would likely override to `accepted-with-open-items`:** the failure
is in a test byte-identical to base, caused by data written by the base build,
and the increment's own instructions forbid touching the threshold it asserts.
Every story in Epic 17 is `done`, both faults are fixed at the source with
before-and-after numbers, and the two changes that ship were each measured
sufficient alone. That override is the user's to make and has not been made here.

## Assumptions recorded (headless run)

- Epic 17 and its numbering were supplied, not detected.
- No human confirmed the FR-102..FR-105 split, the Tier 7 ordering, or the UX
  notice's position at rank 2.
- Q25, Q26 and Q27 are recorded as open rather than answered.
- The acceptance verdict is the machine's. No human override was sought or given.
- Every action item above is *proposed*, not applied — except 17-1, which is a
  report of something that already happened.
- Phase 3's team discussion was skipped, as headless runs require.
- `git push` fails with 403 (`niklas-luettringhaus-pm` lacks write access), so
  the branch is committed locally and no PR was opened.
