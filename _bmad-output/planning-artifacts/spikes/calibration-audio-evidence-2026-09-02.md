---
title: Calibrating what counts as "audio was captured"
date: 2026-09-02
intent: measure
subject: the constants behind AD-36 / FR-67, and the defect that made them necessary
inputs: 26 audio streams from the 13 real Meetings on the author's machine
verdict: the shipped rule accepted all 26 streams, including 32 and 13 minutes of pure digital silence; the calibrated rule accepts 23
---

# What counts as evidence that audio was captured

## Why this was measured

FR-42 rests on a limitation: macOS offers **no API** to ask whether
system-audio permission was granted. So the app cannot query; it can only
observe what arrived in the file. That makes the observation load-bearing —
every sentence the product says about capture working traces back to it.

The shipped rule was:

```swift
let gotAudio = (writer?.peak ?? 0) > 0.0001 || d > 0.25
```

It is wrong twice, and the two faults concealed each other.

**First, duration is not evidence.** Frames are written whether or not anything
is playing, so `d > 0.25` made a quarter second of silence sufficient. A tap
that ran and delivered nothing passed.

**Second, that `peak` is the UI level meter, and it decays.** In
`StreamFileWriter`:

```swift
peak = isMuted ? 0 : max(peak * 0.85, localPeak)
```

Decay is correct for a meter — it is what makes the bars fall when someone stops
talking. It is useless as a session-level fact, because by `stop()` it reflects
only the last moments. **Most meetings end in silence**, so the peak term would
usually have been near zero on its own. Had the duration clause not been there,
the check would have failed on working captures; because it was there, the check
never failed at all.

A test could not have caught this by construction: the condition was
unfalsifiable on any machine where capture worked.

## What the real data shows

26 streams, 13 Meetings, measured by scanning each file in 8192-frame chunks —
the same chunk size the writer drains — recording the highest absolute sample
and the seconds spent above each candidate floor.

**Three system streams hold pure digital silence.** Not quiet: peak **exactly
0.0000**, zero non-silent seconds at every floor tested including zero.

| Meeting | Stream | Duration | Peak | Non-silent |
| --- | --- | --- | --- | --- |
| `…-13ap` | system | **1894 s (32 min)** | 0.0000 | 0.0 s |
| `…-hkt0` | system | **757 s (13 min)** | 0.0000 | 0.0 s |
| `…-w39q` | system | 8 s | 0.0000 | 0.0 s |

All three were reported to the user as *"Last recording captured system audio"*.

**Two more captured almost nothing**, which is a different condition and not a
permission failure — the tap worked, little was playing:

| Meeting | Stream | Duration | Peak | Non-silent |
| --- | --- | --- | --- | --- |
| `…-x3wg` | system | 1116 s | 0.3680 | **1.5 s** |
| `…-9xlr` | system | 3433 s | 0.6438 | 33.3 s |

**Working streams are not marginal.** The rest score hundreds to thousands of
non-silent seconds: 222, 299, 319, 436, 447, 1617, 2018. Every mic stream
works, the quietest at peak 0.0237 over 8 seconds.

The populations do not touch. Failure is exactly zero; success is orders of
magnitude away. That is a much easier separation than the speaker-threshold
calibration faced, and it is worth saying so rather than implying the number was
hard-won.

## The constants, and why these values

```swift
static let silenceFloor: Float = 0.0005          // ≈ -66 dBFS
static let minimumSignalSeconds: TimeInterval = 0.5
var producedAudio: Bool { peak > silenceFloor && nonSilentSeconds >= minimumSignalSeconds }
```

**`silenceFloor = 0.0005`.** A tap without permission delivers digital silence,
not a faint signal, so any floor above zero separates the populations. The value
is not zero because a single stray non-zero sample should not count as audio,
and it is far below the quietest working stream (peak 0.0237, i.e. 47× higher).
Between 0.0 and 0.0005 the data shows a lot of near-silent content — `…-kndb`
system scores 2005 s at floor 0 but 448 s at 0.0005 — so the floor also
usefully excludes dither and noise from the *seconds* count without affecting
any verdict.

**`minimumSignalSeconds = 0.5`.** Bounded from both sides by things that matter:

- It must stay well under five seconds, because the Test Playground records for
  exactly that long (FR-47). A threshold tuned to meeting lengths would make the
  test unpassable, and nobody would find out until someone ran it.
- It must exceed a click or a pop, which last milliseconds.
- Failed streams score 0.0 s; the quietest genuinely-working stream scores 1.5 s.
  0.5 sits between them without being fitted to either.

**Both conditions are required**, because either alone is defeatable: a peak
with no duration is a pop, and duration with no peak is the original bug.

## Verified consequence

`AudioEvidenceCalibrationTests`, run against the real Meetings
(`MINUTES_AUDIO_CALIBRATION=1`):

```
26 real streams examined
the shipped rule accepted 26; this rule accepts 23
system streams the old rule got wrong: 3
long streams of pure digital silence: …-13ap/system 1893s, …-hkt0/system 757s
```

The test asserts the invariant directly — a stream whose peak is exactly zero is
never accepted, however long — and asserts the new rule is never *more*
permissive than the one it replaces. It is gated behind an environment variable
because it reads about a gigabyte and takes 56 seconds; the default suite stays
at 0.27 s.

It also skips cleanly where there are no Meetings, and copies nothing into the
repository. These are colleagues' voices; PRD §9.1 keeps them on the machine
that recorded them.

## What this does not settle

- **Why those three taps produced silence is not established here.** Revoked
  consent after a rebuild is the likeliest cause and matches the pattern
  (§12), but this measurement identifies the symptom, not the cause.
- **The floor has not been tested against a genuinely noisy room** on hardware
  other than the author's. The reasoning is that a *permission* failure yields
  exact zeros regardless of the room, which makes the floor's precise value
  uncritical — but that is an argument, not a second measurement.
- **`x3wg`'s 1.5 seconds now passes.** That is deliberate: the tap did work and
  captured real audio; almost nothing was playing. Reporting it as a capture
  failure would be a different false claim.
