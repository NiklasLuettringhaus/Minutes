# Investigation: what actually limits transcription quality

**Date:** 2026-09-03
**Prompt:** improve transcription substantially — techniques from FluidVoice or anywhere else.
**Method:** a measurement harness built first, then measured. Nothing here is inferred from reading code alone.

---

## Why a harness came first

Speed has been measurable in this project since `--benchmark`. Accuracy never has.
Every accuracy claim in the product is an assumption written into `ModelCatalog`
and never checked:

- `parakeet-tdt-0.6b-v2-en` — *"English only, and a little sharper for it."*
- `openai_whisper-large-v3-v20240930_turbo_632MB` — *"Balanced"*, role `.accurate`, accuracy **5/5**
- `parakeet-tdt-0.6b-v3` — accuracy **4/5**

None of the three is safe to state. One turns out to be **supported**, one is
**still unverified**, and the third rests on a ranking that swings by ±8 points
depending on which meeting you measure (§2). They were not lies; they were
never measurable. So the first deliverable is `Scripts/eval/asr_eval.py` plus a
`--asr` CLI, and every number below comes out of it.

### The corpus

**AMI Meeting Corpus** (CC BY 4.0), three sessions, 67 minutes, four speakers
each, ~7,900 reference words with word-level timings. Chosen because its two
microphone conditions map onto the two streams Minutes actually records:

| AMI condition | What it is | The Minutes stream it stands for |
|---|---|---|
| `Mix-Headset` | each participant's own close mic, mixed | the far end of a video call, down the system tap |
| `Array1-01` | one microphone in the middle of the room | the laptop mic with people around it |

Held outside the repository at `~/Library/Application Support/MinutesEval`
(PRD §9.1). AMI is not in any Minutes training path, but note that FluidAudio
also ships an `ls-eend` diarisation model *tuned on AMI* — anything evaluated
against that model on this corpus would be contaminated, so it is excluded.

### The metrics, and why raw WER is not enough

Raw WER on the first baseline run was 16.3%, and its **most-deleted words were
`yeah` (38), `ok` (17) and `right` (13)** — backchannels spoken over whoever had
the floor. A quarter of all errors were words Minutes already strips on purpose
(FR-31). Optimising raw WER would have meant chasing words the pipeline
deliberately deletes.

So the harness also reports **`contentWer`** (excluding a closed-class
function/backchannel list) and **proper-noun recall**, because a wrong name is
the error a reader of a meeting note actually notices. Raw WER is still
reported — a metric that only flatters what it measures is not a metric.

---

## 1. The dominant defect is acoustic echo, not the model

Found by measuring the user's own library (18 recordings, 12 with both streams),
not the corpus. Three independent methods agree.

### 1a. Signal: the microphone contains the system stream

Full-file normalised cross-correlation between `mic.wav` and `system.wav`:

| recording | peak cross-correlation | lag |
|---|---|---|
| 50.3 min | **0.771** | 39 ms |
| 16.3 min | **0.574** | — |
| 33.8 min | **0.349** | 130 ms |
| the other 9 | ≤ 0.025 | — |

39 ms is the acoustic path from speakers to microphone. The affected recordings
were taken on speakers or in a room; the clean ones on headphones.

### 1b. Text: a third of those transcripts is the same speech twice

Time-overlapping mic/system utterance pairs above 0.6 text similarity:

| recording | duplicate pairs | share of all words |
|---|---|---|
| 50.3 min | 335 | **33.6%** |
| 16.3 min | 88 | **32.2%** |
| 33.8 min | 60 | 11.9% |
| the other 9 | 0–8 | ≤ 1.7% |

These shares are of the *stored* transcript, after the pipeline's own filler
stripping. Measured against a fresh transcription of `mic.wav` the same defect
reads higher still — 57.6% of mic words on the worst recording (§1g) — because
nothing has been stripped yet. Both denominators are honest; they are not
interchangeable.

Corroborating symptoms in the same two recordings: **226 and 270 words/minute**
against a library median of 148 (natural speech is 110–160), and repetition
rates of **15.0%** and **10.3%** against a median of 0.5%.

### 1c. The knock-on: phantom people, and the user never identified

The far end, arriving through the microphone, is clustered by the diariser as
people *in the room*:

| recording | in-room speaker labels | `local` assigned |
|---|---|---|
| 50.3 min | **6** (`room-0` … `room-5`) | **never** |
| 33.8 min | 5 | 6 utterances |
| 16.3 min | 3 | never |
| clean recordings | `local` only, or ≤ 3 | yes |

So the defect does not merely pad the transcript. It invents attendees, and in
the worst case it prevents the user from being recognised at all — which is the
"Me" mislabel class of failure, with a cause nobody had located.

### 1d. The two detectors agree with each other

Per-frame (0.5 s) correlation against the delay-aligned system stream, versus
the independent text-similarity list:

| recording | text-duplicates the signal also flags | non-duplicates it flags |
|---|---|---|
| 50.3 min | **286 / 325 (88%)** | 82 / 361 (23%) |
| 16.3 min | **78 / 88 (89%)** | 41 / 142 (29%) |
| 33.8 min | 25 / 59 (42%) | **10 / 447 (2%)** |

Two methods sharing no code and no assumption arriving at the same frames is
the strongest evidence in this document.

### 1e. Cancellation was tested and rejected — on numbers

The obvious fix is an echo canceller. It cannot work on these recordings.

Upper bound on ERLE for **any** linear filter, from magnitude-squared coherence
(so it is independent of filter length), delay-compensated:

| analysis window | median bound | p90 |
|---|---|---|
| 128 ms | 8.7 dB | 11.3 dB |
| 512 ms | 9.9 dB | 14.8 dB |
| 2048 ms | 10.6 dB | 16.8 dB |

A useful AEC needs 20–40 dB. A least-squares FIR fit confirmed it empirically:
7.5 dB median at 512 taps, never above 20 dB on any frame. The microphone
signal is simply not a linear function of the system signal here — two
independent device clocks, speaker nonlinearity, and a reverb tail longer than
any window tried.

> **A correction to my own measurement.** The first coherence run reported
> 1.6 dB and I nearly wrote down "cancellation is impossible". That run did not
> compensate the 39 ms delay, and a 128 ms window biases such a figure badly
> low. The corrected figure is ~10 dB. The conclusion survives; the number I
> first had did not, and a decisive-looking negative result is exactly the kind
> that needs checking twice.

### 1f. What exclusion costs, measured

The far end is *already recorded perfectly* on the system stream. The
microphone's copy of it carries no new information, so removing it can only
lose something where the user speaks *at the same time*. On the worst recording:

| mic-active frames (0.5 s) | 5,917 | |
|---|---|---|
| system silent — unambiguously the room | 2,376 | 40% — never at risk under any policy |
| concurrent with system audio | 3,541 | 60% |
| …of which echo-dominated | 2,754 | 47% of mic activity — the exclusion target |
| …leaving probable double-talk | 787 | 13% — kept |

**Conclusion: detect and exclude, do not cancel.** And exclude *before*
transcription and diarisation, because §1c is a clustering failure that
transcript-level de-duplication would not fix.

### 1g. The fix was built and re-transcribed — it works

Echo-dominated frames were muted with 10 ms ramps and the microphone was
re-transcribed through the shipping engine. No ground truth is needed for this
question: the far end is already on the system stream, so a mic word that
duplicates it is pure loss, and a mic word that does not is what must survive.

| recording | | mic words | duplicating the system stream | unique to the mic |
|---|---|---|---|---|
| **50.3 min** | before | 6,798 | 3,918 (**57.6%**) | 2,880 |
| | after | 2,910 | 337 (**11.6%**) | 2,573 |
| **33.8 min** | before | 5,832 | 906 (15.5%) | 4,926 |
| | after | 5,499 | 553 (10.1%) | **4,946** |

On the severe recording **91% of the duplication is gone**. On the moderate one
the duplication falls by a third and the mic's unique content does not just
survive, it goes *up* by 20 words — removing the echo made the remaining speech
easier to recognise.

**The honest cost:** the severe recording loses 307 unique mic words, 10.7% of
its own content. That is double-talk — the user speaking over the far end — and
correlation alone cannot keep it. Refining the test from "is correlated" to
"echo dominates the frame's energy" is the obvious next move, and it is why this
ships behind a measured threshold rather than as an unconditional filter.

---

## 2. Model ranking swings by meeting, and my first conclusion was wrong

**Retraction.** An earlier draft of this document, written when only one session
had run, said: *"`v2-en` is not 'a little sharper' for English. It is worse
than `v3` on every metric in both conditions."* That was measured on ES2004a
alone and the pooled result reverses it. The claim is withdrawn. It is recorded
rather than deleted because the mistake is the finding: I built this harness to
stop unmeasured accuracy claims, and then made one from a single session.

### Per session, close mics — the swing is larger than the models

| session | `parakeet-v3` | `parakeet-v2-en` |
|---|---|---|
| ES2004a | **16.3%** | 18.6% |
| IS1000a | 35.1% | **27.4%** |
| TS3003a | 15.7% | **14.5%** |

`v3` alone ranges from 15.7% to 35.1% depending on which meeting it is given.
**Session variance dwarfs the difference between models**, so any ranking drawn
from one meeting is noise. Both engines transcribed IS1000a end to end in plain
English with near-identical word counts (2,372 vs 2,370), so the gap there is
ordinary recognition quality, not a failure mode.

### Pooled over all three sessions — total errors over total reference words

`Mix-Headset` (7,374 reference words):

| model | WER | content WER | deletions | proper nouns |
|---|---|---|---|---|
| `parakeet-tdt-0.6b-v2-en` | **20.3%** | **18.5%** | 12.3% | 80% |
| `parakeet-tdt-0.6b-v3` | 22.6% | 22.3% | 12.8% | 82% |

`Array1-01` (7,374 reference words):

| model | WER | content WER | deletions | proper nouns |
|---|---|---|---|---|
| `parakeet-tdt-0.6b-v3` | **29.4%** | 29.6% | 17.1% | 77% |
| `parakeet-tdt-0.6b-v2-en` | 29.8% | 29.0% | 17.5% | 75% |

So on English meeting speech: **`v2-en` is 2.3 points better on close mics and
tied far-field.** The catalogue's note — *"English only, and a little sharper
for it"* — is **supported**, and our default (`v3`) is arguably the wrong
default for English meetings. That is the opposite of what one session said.

### Pooled, all three engines, all three sessions

The confirmation run has now landed, so this is the complete picture.

**Close mics** (7,374 reference words):

| model | WER | content WER | proper nouns | ×realtime |
|---|---|---|---|---|
| `parakeet-tdt-0.6b-v2-en` | **20.3%** | **18.5%** | 80% | 0.005 |
| `parakeet-tdt-0.6b-v3` | 22.6% | 22.3% | **82%** | 0.005 |
| `whisper-large-v3-turbo-632MB` | 22.8% | 19.3% | 77% | 0.039 |

**Far field** (7,374 reference words):

| model | WER | content WER | proper nouns | ×realtime |
|---|---|---|---|---|
| `parakeet-tdt-0.6b-v3` | **29.4%** | 29.6% | **77%** | 0.005 |
| `parakeet-tdt-0.6b-v2-en` | 29.8% | **29.0%** | 75% | 0.005 |
| `whisper-large-v3-turbo-632MB` | 40.8% | 38.5% | 60% | 0.044 |

What survives as a statement about the models we ship:

1. **Both Parakeet variants match or beat Whisper turbo everywhere, at ~8× the
   speed.** Close mics are a tie (22.6 / 22.8); far-field Whisper is **11.4
   points behind** with proper-noun recall of 60% against 77%.
2. **The catalogue's accuracy ratings are not supported.** It rates
   `whisper-large-v3-turbo` 5/5 and gives it the `.accurate` role against
   `parakeet-v3` at 4/5. The measurement makes that a tie in the best case for
   Whisper and a rout against it in the worst.
3. **Between the two Parakeet variants, nothing separates them reliably.**
   `v2-en` leads by 2.3 points pooled on close mics and trails by 0.4
   far-field, inside a per-session swing of ±8.

An earlier draft of this section said the ratings were "inverted". On close
mics they are not — they are a tie, and a tie does not justify a 5-versus-4
rating either. The right correction is to **remove ratings the harness cannot
support**, not to renumber them from a measurement this thin.

**Canary-1B-v2 is rejected.** Reputationally the strongest model available and
reachable through the FluidAudio version already pinned, it came 8.5 points
behind the current default on close mics and 9.2 behind far-field, at 22× the
cost, and returns no timings. Measuring it cost an afternoon and saved building
a pipeline around it.

## 3. The far-field case is much worse, and normalisation half-helps

Same model, same meeting, different microphone: pooled WER **22.6% → 29.4%**
and proper-noun recall **82% → 77%**. The room is where quality is lost, and
the room is exactly where §1's echo also happens.

Level and dynamic-range normalisation were measured (ES2004a, `parakeet-v3`):

| preprocessing | close mics | far-field |
|---|---|---|
| none | 16.3% | 26.1% |
| `loudnorm` (EBU R128 to −16 LUFS) | 18.4% (**+2.1**) | **24.0%** (−2.1) |
| `highpass 80 Hz` + `dynaudnorm` | 17.0% (**+0.6**) | **24.0%** (−2.0) |
| `dynaudnorm` | 17.5% (**+1.1**) | 24.7% (−1.4) |

**It helps far-field by ~2 points and hurts close mics by ~1–2.** Consistent and
symmetric: quiet distant audio benefits from gain, well-levelled close audio is
damaged by compression. Proper-noun recall does not move either way (76%).

So the technique is real but conditional, and the gate is the whole problem —
**and the obvious gate does not work.** Integrated loudness does not separate
the two conditions:

| | close mics | far-field |
|---|---|---|
| ES2004a | −34.1 LUFS | −48.8 LUFS |
| IS1000a | **−17.6 LUFS** | −34.0 LUFS |
| TS3003a | **−43.8 LUFS** | −51.5 LUFS |

TS3003a's *close* mix (−43.8) is quieter than IS1000a's *far-field* (−34.0), so
no single threshold classifies them, and the user's own library spreads from
−18.7 to −70.0 LUFS. A loudness-gated normaliser would misfire on real
recordings and cost 2 points when it did.

**Verdict: not ready.** A 2-point conditional gain with no reliable gate is not
worth a story yet. What would make it one is a gate keyed on something that
actually distinguishes the conditions — reverberation or direct-to-reverberant
ratio rather than level — which is unmeasured and therefore a spike, not a task.

## 4. What I checked that is *not* broken

- **No long-file truncation.** FluidVoice chunks at 20 min citing a 24-minute
  model limit, and Minutes does not chunk at all. But the longest real
  recording is **57.3 min** and its transcript's last utterance lands at
  **57.3 min — 100% coverage**, as do the 50.3 and 33.9 minute ones. FluidAudio
  handles it internally. No defect; I nearly reported one.
- **Repetition on clean recordings** sits at a 0.5% median. The hallucination
  problem was a symptom of bad audio, not a standing property of the engine.

---

## Techniques reviewed, and where they landed

From **FluidVoice** (GPL-3.0 — techniques only, no code copied):

| technique | verdict |
|---|---|
| per-packet sample rate + `inputHostTime`/`inputSampleTime` | **adopt** — we discard the audio clock and reconstruct rate from `Date()` with a 12% tolerance |
| ASBD format fingerprint + dirty flag + packet gate | **adopt** — we re-read the tap format once and only log |
| confidence carried end-to-end | **adopt** — `TranscribedSegment` has no confidence field at all |
| explicit `SpeakerTranscriptGap` in the transcript | **adopt** — we drop unusable intervals silently |
| custom dictionary / keyword correction | **adopt via Canary's `CanaryKeywordBooster`** |
| 20-minute chunking | **reject** — measured unnecessary (§4) |

Already in `FluidAudio` 0.15.6, which we already ship and do not use:

- `silero-vad` / `fsmn-vad` — segmentation, which is also where a timing-less
  engine would get its timings
- `canary-1b-v2` + `CanaryKeywordBooster` — accuracy candidate and proper-noun
  biasing (marked beta upstream; returns a bare `String`, no timings)
- `ITN/TextNormalizer` — spoken-to-written numbers, for readability
- `sortformer`, `ls-eend` — overlap-aware diarisation (the AMI-tuned variant is
  excluded from evaluation as contaminated)

---

## Recommendation, in order of measured value

1. **Echo exclusion (§1).** The only change here with a large, validated
   effect: 91% of the duplication gone on the worst recording, the phantom
   attendees with it, and `local` identification restored. Detection by
   correlation against the delay-aligned system stream; exclusion before
   transcription *and* diarisation; never cancellation (§1e). Refine the test
   to energy dominance so double-talk survives (§1g).
2. **Stop making accuracy claims the harness cannot support (§2).** Not
   "correct the ratings" — *remove* them where nothing measured backs them. The
   catalogue currently asserts a 5-point accuracy scale across fourteen models
   from a corpus of zero measurements.
3. **The audio clock (FluidVoice).** Replaces a 12%-tolerance wall-clock
   heuristic with an exact comparison and catches dropped packets it cannot
   currently see. Correctness, not accuracy.
4. **Confidence and gaps through the port.** An independent net for the
   fabrication failure, by symptom rather than by cause.
5. **Keep the harness.** It has already retracted one of my conclusions and
   rejected the model I would otherwise have adopted. That is its return.

**Not recommended now:** far-field normalisation (§3 — real but ungated),
Canary (§2 — measured worse), long-file chunking (§4 — measured unnecessary),
overlap-aware diarisation (unmeasured, and the AMI-tuned variant cannot be
evaluated on this corpus), streaming transcription (no measured need).

## Open questions

- **Does `v2-en` deserve to be the default for English?** Pooled it is 2.3
  points better on close mics, but the per-session swing is ±8. Three sessions
  is not enough to move a default; six or nine would be.
- **`whisper-large-v3-turbo` is measured on one session only.** Its 5/5
  accuracy rating is unverified either way until the confirmation run lands.
- **The echo threshold** (0.25 correlation, 0.3 frame-share) was hand-set on
  three recordings and costs 10.7% of unique mic words on the worst one. It
  needs an energy-dominance formulation and held-out validation.
- **The delay estimator is not robust.** The 16.3-minute recording returned
  920 ms, which is not a plausible acoustic path. Detection survived via local
  lag search, but a wrong delay would silently disable the whole test.
- **Why does session variance dominate?** IS1000a is the hardest session for
  both engines (27–35% WER) and it is AMI's non-native-speaker set. If accent
  is the driver it matters directly: these meetings are not held in first-
  language English either.
- **What is a far-field gate keyed on?** Level does not work (§3).
