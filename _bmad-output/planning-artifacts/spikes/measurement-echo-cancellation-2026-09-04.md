# Measurement: cancelling the far end, and why it does not ship

**Date:** 2026-09-04
**Requirement:** FR-99 · **Governed by:** AD-48 as amended, AD-55
**Command:** `Minutes --check-aec [--suppression <x>] [--taps <n>]`
**Outcome:** built, measured, **not wired into capture**. The measurement rules
it out, and the control is what rules it out rather than the headline number.

---

## What was built

The shape the field uses and AD-48 permits: a **linear NLMS filter** followed by
a **non-linear residual suppressor**, with the System Stream as the reference.

The residual stage is the one that matters, and its idea is the one that makes
the whole thing plausible against the coherence bound. The loudspeaker path is
not linear, so the echo's *waveform* is not a filtered copy of the reference —
which is what defeats the linear filter — but its *power envelope* still is. So
the suppressor learns a per-bin power coupling from the reference to the residual,
predicts the echo's power in each bin, and applies a Wiener gain. Nothing about
that requires the path to be invertible.

## Three implementations, and each was caught by a control rather than by reading

Recorded because the sequence is the finding as much as the number is.

1. **The regularisation, not an epsilon.** NLMS normalises by the reference
   energy, and the first version added `1e-6` to it. A near-silent reference then
   divided the update by almost nothing, the weights exploded, and when the far
   end came back the filter produced a large output resembling nothing. Measured:
   **−30 dB ERLE** — the canceller adding a thousand times the energy it removed.
   Two of the four fixture controls failed and both failures were this one
   number.
2. **The double-talk freeze deadlocked the filter.** The second version froze
   adaptation whenever the frame did not look echo-dominated, where
   "echo-dominated" meant the filter already explained half the frame's energy.
   That is circular: a filter starting from zero explains nothing, so it froze on
   the first frame and never adapted. Measured: **1.4 × 10⁻⁸ dB**. Properly
   regularised NLMS does not need the freeze — double-talk costs it
   misadjustment, which is a few decibels, not a divergence.
3. **Minimum statistics does not transfer from noise to echo.** The third
   version estimated the coupling as a per-bin *minimum* of the observed ratio,
   on the sound argument that a minimum ignores double-talk by construction —
   which is exactly how a noise-power estimator avoids tracking speech. Noise is
   stationary and an echo is not, so the minimum lands on the frames where the
   echo has not arrived or the loudspeaker does not radiate. Measured: the mean
   applied gain was **0.997 even at thirty-two times over-suppression**. The
   stage was doing nothing at all, and a negative result from it would have been
   a measurement of a bug.

Only the fourth — two smoothed powers, divided — actually suppresses anything.
Every one of the first three would have produced a publishable-looking negative
result, and the reason none of them did is that `--check-aec` reports the **mean
applied gain** beside the ERLE. A stage that is not working and a stage that is
working on audio it cannot help look identical without it.

## The result, at the default over-suppression of 2.0

| recording | verdict | ERLE | mean gain | lost where the far end was silent |
|---|---|---|---|---|
| 33.9 min | **affected** | 2.28 dB | 0.36 | 0.00 dB |
| 50.3 min | **affected** | 5.75 dB | 0.46 | 0.08 dB |
| 16.3 min | **affected** | 3.39 dB | 0.43 | −0.00 dB |
| 57.3 min | clean | **6.49 dB** | 0.41 | 0.00 dB |
| 26.8 min | clean | **4.37 dB** | 0.55 | 0.00 dB |
| 22.1 min | clean | 0.16 dB | 0.53 | −0.00 dB |
| 28.7 min | clean | −0.05 dB | 0.62 | −0.00 dB |
| 12.4 min | clean | −0.41 dB | 0.61 | −0.00 dB |
| 19.1 min | clean | 0.25 dB | 0.62 | −0.00 dB |

**The control is the finding.** On the 57.3-minute recording — headphones, where
no acoustic path exists and therefore no echo can exist — the canceller reports
**6.49 dB of "ERLE", higher than two of the three genuinely affected
recordings**. What it is producing is attenuation, not cancellation. Since
"frames with the far end playing" on a clean recording are frames where the user
is speaking over the call, that 6.49 dB is 6.49 dB taken out of **the user's own
voice**, on a recording with nothing wrong with it.

It is not a threshold problem. Turning over-suppression up moves both columns
together:

| over-suppression | worst affected | worst clean | mean gain (affected) |
|---|---|---|---|
| 1.0 | 4.83 dB | **5.35 dB** | 0.43–0.54 |
| 2.0 | 5.75 dB | **6.49 dB** | 0.36–0.46 |
| 6.0 | 7.32 dB | **8.80 dB** | 0.26–0.34 |

At six times, the stage is removing about **70% of the energy in every bin** and
buying 7.3 dB on the worst affected recording — while removing 8.8 dB from a
clean one. There is no operating point at which it distinguishes an echo from a
headphones recording.

## Against the bar

FR-99's benefit had to be measured before it was relied on, and the bar is the
one the field quotes: **20 to 40 dB**. The best figure here is **7.3 dB**, which
is inside the 8.7–10.6 dB bound the coherence measurement already put on a purely
*linear* filter. The non-linear residual stage — the thing AD-48 was amended to
permit, on the argument that it "exists precisely for cheap laptop hardware where
speakers distort" — **buys nothing measurable on these recordings**.

So FR-99 is not implemented at capture. AD-55 is the rule that says what to do
instead: the component may be built and exercised offline and may **not** be
wired into the path that writes the user's audio until a measurement supports it.
FR-90's post-hoc exclusion rule stands, unchanged, on its own measurement.

## What this does not establish, stated plainly

**This is the hardest version of the problem and the asymmetry matters.** AD-48
says cancellation must run at capture, where the reference is aligned by
construction and the filter adapts continuously; this ran post hoc on two
independently-clocked files. A *good* result here would have been strong
evidence. A poor one is weaker evidence against, and the honest reading is:

- **Ruled out:** that this design, at any over-suppression tried, separates echo
  from near-end speech on these recordings. That failure is not about alignment —
  it shows up on a recording with **no echo at all**, where alignment is
  irrelevant.
- **Not ruled out:** that a canceller with a genuinely aligned reference and a
  better residual stage — AEC3's, rather than one afternoon's — would do better.
  Nothing here measures AEC3. What is measured is that the plausible cheap
  version of its idea does not pay, and that the coherence bound that closed the
  linear route is not visibly beaten by adding a power-domain stage.

## What is kept

- `Core/EchoCancellation` — the parameters, the report, and the bar as a function
  rather than as a sentence somebody has to remember.
- `Adapters/Audio/EchoCanceller` — the implementation, with all three failures
  recorded at the lines that caused them.
- `--check-aec` — so the next person to try starts from a harness and a baseline
  rather than from an afternoon.
- Five fixture tests, including the two controls that caught two of the three
  bugs: that it removes almost nothing given an unrelated reference, and that it
  leaves audio alone where the far end was silent.

## Limits

- Three affected recordings, one machine, one room, one pair of loudspeakers —
  the same calibration set as everything else in this epic.
- The 16 kHz storage format is what the canceller sees. Cancelling at the capture
  rate before downsampling would give the filter more to work with, and that is
  untested.
- ERLE is measured over frames where the reference was active, which on a clean
  recording means frames where the user talked over the call. That is what makes
  the control meaningful and it is also why the clean figures are not zero for a
  *correct* canceller either — a correct one would be near zero, and 6.49 dB is
  not near zero.
