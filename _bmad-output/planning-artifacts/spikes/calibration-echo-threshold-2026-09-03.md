# Calibration: the echo threshold, and the design it changed

**Date:** 2026-09-03
**Input:** `investigation-transcription-quality-2026-09-03.md` §1
**Outcome:** the planned test was measured, failed, and was replaced. FR-90,
FR-91, AD-47 and Stories 16.3, 16.4 and 16.7 were amended to match.

---

## What was planned

Story 16.3 as first written required the per-frame test to be **energy
dominance, not correlation alone** — exclude a frame only where the aligned
System Stream *explains the frame's energy*, so that a frame carrying the user's
voice as well as an echo survives. The reasoning was sound: correlation alone
cost 10.7% of unique microphone words on the worst recording.

## What was measured

Candidate per-frame statistics, swept against an independent label. The label is
the text-level duplicate list — mic Utterances that substantially repeat a
time-overlapping System Stream Utterance — which shares no code and no
assumption with any signal statistic. Positives are known echo; negatives are
content that must survive. Each cell is `recall% / cost%`, weighted by words.

**50.3 min recording** — 325 echo Utterances, 359 to protect:

| statistic | 0.05 / 0.5 dB | 0.25 / 4.5 dB | 0.45 / 8.5 dB | 0.65 / 12.5 dB |
|---|---|---|---|---|
| `ρ` (correlation) | 100 / 18 | 91 / 15 | 39 / 5 | 2 / 0 |
| ERLE, 1 tap | 21 / 5 | 0 / 0 | 0 / 0 | 0 / 0 |
| ERLE, 8 taps | 86 / 12 | 0 / 0 | 0 / 0 | 0 / 0 |
| ERLE, 32 taps | 91 / 15 | 4 / 0 | 0 / 0 | 0 / 0 |

Cheapest operating point reaching 80% recall:

| statistic | threshold | recall | cost |
|---|---|---|---|
| `ρ` | 0.30 | 86% | 13.4% |
| ERLE, 8 taps | 0.5 dB | 86% | 12.3% |
| ERLE, 32 taps | 1.0 dB | 87% | 13.2% |

**Energy dominance does not work here, and the reason is the same one that
killed cancellation.** ERLE collapses to nothing above 4.5 dB — almost no frame
has more than a few dB of its energy linearly explained by the System Stream,
because the echo path is not linear (§1e). The elaborate statistic buys **1.1
points of cost over plain correlation**, inside the noise of a single recording.

The 33.8-minute recording reaches 80% recall at no threshold on any statistic.

**So the honest ceiling for muting is ~86% recall at ~13% cost** — 350-odd words
of the user's own speech deleted to remove 3,600 duplicated ones. Net positive
for the transcript, and still deleting real content.

## The design that replaced it

The premise that needed questioning was not the statistic. It was the assumption
that **both consumers need the same test**. They do not:

- **Diarisation** needs the far end kept out of the room's clusters. It is
  robust to missing frames — clustering needs enough audio per speaker, not all
  of it — so a 13% frame-level false-positive rate costs it very little.
- **The transcript** must not lose a word the user said. It has a second,
  independent signal available that diarisation does not: **the text**.

So the tests are split by consumer.

### The recording-level gate is decisive on its own

| recording | gated? | duplicate words | coincidental duplicates when not gated |
|---|---|---|---|
| 8.4 min | no | — | **0** |
| 10.7 min | no | — | 7 |
| 10.8 min | no | — | **0** |
| 11.5 min | no | — | **0** |
| 17.3 min | no | — | 44 |
| 26.1 min | no | — | **0** |
| 28.6 min | no | — | **0** |
| 0.9 / 4.5 min | no | — | **0** |
| **16.3 min** | **yes** | 1,498 (59% of mic words) | |
| **33.8 min** | **yes** | 906 (16%) | |
| **50.3 min** | **yes** | 3,918 (58%) | |

Nine recordings fail the gate and seven of them contain **literally zero**
coincidentally duplicated words. Gated text removal therefore does nothing at
all to a headphones recording — which is the property that makes it safe.

### The duplicates are not coincidence

Of the duplicated words on the three affected recordings, only **74, 6 and 4**
sit in Utterances of two words or fewer. **98% of what would be removed is
multi-word.** Coincidental agreement is short — someone in the room saying
"yeah" as the far end says "yeah". Verbatim repetition of a multi-word sentence
at the same instant is not coincidence, it is the loudspeaker.

## The rules, as calibrated

1. **Recording gate — 10% of concurrent frames over the frame threshold**, at
   the best offset found by the search in Part two. Measured: **0–1% on every
   clean recording and 24%, 61%, 63% on the three affected ones.** An earlier
   version of this rule used a global waveform cross-correlation instead (≤0.025
   clean against ≥0.349 affected) and was replaced when the offset search made
   the frame share available, because the two could disagree and the frame share
   is the quantity the exclusion actually consumes. Below the gate, nothing is
   excluded by any rule.
2. **Transcript — both signals must agree.** On a gated recording, a mic
   Utterance is dropped only where it substantially repeats a time-overlapping
   System Stream Utterance. **Loses no unique microphone content by
   construction**, because it can only ever remove an Utterance that duplicates
   one already held on the other stream.
3. **Diarisation — the frame test, at `ρ ≥ 0.30`.** 86% of echo frames on the
   worst recording. Its 13% false-positive rate reaches clustering only, never
   the transcript, so it cannot delete a word the user said.
4. **The floors of FR-91 are unchanged and apply to both.** System Stream
   silent, or concurrent-but-uncorrelated, is never excluded.

## Part two: how the offset is found, after two methods failed

The threshold above decides *which frames* are echo. Finding the offset to
compare them at turned out to be the harder half, and two implementations were
built and discarded on measurement before the third worked.

### Attempt 1 — correlate the energy envelopes

| recording | envelope peak | truth |
|---|---|---|
| 19.1 min | 0.063 | clean |
| 33.9 min | **0.071** | **affected** (12% duplicated) |
| 28.7 min | 0.096 | clean |
| 57.3 min | 0.140 | clean |
| 50.3 min | **0.684** | affected |
| 16.3 min | **0.549** | affected |

Separates the two severe recordings cleanly and is **blind to the mild one**.

### Attempt 2 — judge that curve by peak prominence

Worse than useless. A genuinely clean recording scored **6.82** and an affected
one **1.18**; the statistic is anti-correlated with the truth on this set. It
also rejected two recordings whose maximum sat exactly at the search boundary,
which is how the boundary itself got noticed.

### The boundary that should never have existed

Both attempts were bounded by a "plausible acoustic delay". A
speaker-to-microphone path is tens of milliseconds, so 920 ms was dismissed as
impossible — twice.

It was not impossible. The offset between the two files is the acoustic delay
**plus the instant each capture started**:

| recording | `mic.wav` − `system.wav` length |
|---|---|
| 12.6 min | −78 ms |
| 26.1 min | −364 ms |
| 50.3 min | −69 ms |
| **16.3 min** | **+868 ms** |
| 33.9 min | +2,372 ms |
| 57.3 min | +3,278 ms |

The recording whose 920 ms lag was "impossible" has an **868 ms** length
difference. A physical bound would have permanently excluded one of the three
recordings it was written to protect — **the check would have hidden the defect
it was checking for.** (That the two streams are misaligned at all is a second
defect, recorded as FR-97.)

### Attempt 3 — search on the statistic that discriminates

Maximise the **share of concurrent frames that correlate**, which is the
quantity the exclusion depends on anyway:

| recording | best offset | frame share | truth |
|---|---|---|---|
| 18.6 min | — | **0%** | clean |
| 31.6 min | — | **0%** | clean |
| 28.7 min | −960 ms | **1%** | clean |
| 12.6 min | — | **0%** | clean |
| 57.3 min | — | **0%** | clean |
| 19.1 min | — | **0%** | clean |
| **33.9 min** | 140 ms | **24%** | affected |
| **50.3 min** | 50 ms | **61%** | affected |
| **16.3 min** | 920 ms | **63%** | affected |

**Eight of eight correct**, with the gate at 10% sitting in a gap from 1% to
24%. None of the recovered offsets equals the file-length difference, so that
shortcut does not work either. The whole library analyses in **3.3 seconds**.

Applied to the stored transcripts, the Transcript rule would drop 51% and 55% of
mic words on the two severe recordings, 5% on the mild one, and **nothing at all
on any clean recording**.

### The lesson, which is not about echo

Two of the three failed attempts failed on *plausibility reasoning* — a bound
that sounded physical, and a curve statistic that sounded principled. Both were
overturned by a number. The method that worked is the one whose statistic is the
same thing the decision consumes.

## What this cost, and what it bought

The elaborate statistic was discarded and plain correlation kept, which looks
like a step backwards until the design change is counted: the transcript went
from losing **13% of the user's own words** to losing **none**, and diarisation
kept the recall it needed. The calibration was worth running precisely because
it refuted the story that asked for it.

## Limits to state plainly

- Three affected recordings is a small calibration set, and all three are from
  one machine, one room and one pair of loudspeakers.
- `ρ ≥ 0.30` is the cheapest ≥80%-recall point on **one** recording; the second
  reaches 18% recall at that threshold and the third could not be scored.
  The frame test is therefore known to be weak on mild echo, and it shows in the
  end-to-end result: the mild recording gets 5% of its mic audio excluded and
  the Transcript rule catches 284 of roughly 900 duplicated words. Severe echo
  is handled well; mild echo is handled partially, and that is the honest
  summary.
- Eight recordings classify correctly, but the seven from the increment-8 rate
  defect **cannot be compared at all** — their repaired `system.wav` headers
  read 8000 or 5333 Hz against the microphone's 16000 Hz, so the detector
  refuses rather than comparing mismatched indices. That refusal is correct, and
  it means the calibration set is eight recordings, not fifteen.
- The text rule's precision cannot be measured in this framework: its label *is*
  the ground truth. The evidence that it is sound is indirect — the zero
  coincidence rate on ungated recordings, and the 98% multi-word share.
- Utterance-level text removal cannot fix a *partial* overlap, where the echo
  and a room voice land inside one Utterance. Those survive as duplicates and
  are counted in the residual.
