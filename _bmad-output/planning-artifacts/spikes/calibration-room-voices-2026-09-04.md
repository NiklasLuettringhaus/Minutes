# Calibration: ruling the far end out of the room

**Date:** 2026-09-04
**Question:** AD-31's speaker threshold is **0.35**, measured between voices
captured the *same* way. FR-100 asks it to decide something else — whether a
voice on the microphone is the far end, which has been through a loudspeaker, a
room and a different microphone on its way there. AD-56 forbids using it across
that boundary without a measurement taken across it. This is that measurement.
**Command:** `Minutes --check-echo --diarize`, on the author's library.

---

## Why this exists at all

The previous attempt at the same requirement was built, committed and described
before anyone counted the speakers. When they were counted it had made them
worse: muting the Echo before clustering moved the in-room voice count **5 → 7,
6 → 6, 3 → 5**, because muting punches silence through continuous speech and the
clusterer splits one voice into several.

So this one asserts the *direction* of the change on real recordings before it
ships, and it measures the threshold rather than inheriting it.

## The result, on every dual-stream recording

Fifteen recordings hold both Streams. Eight cannot be compared — increment 8's
rate repair rewrote their System Stream header to 8000 or 5333 Hz against the
microphone's 16000, and the detector refuses mismatched indices (PRD §13 Q22).
That leaves **thirteen**: three affected, nine clean, one too short to judge.

### The count falls on all three affected recordings

| recording | before | after muting *(withdrawn)* | **after ruling out the call** |
|---|---|---|---|
| 33.9 min | 5 | 7 | **4** |
| 50.3 min | 6 | 6 | **1** |
| 16.3 min | 3 | 5 | **1** |

The two severe recordings collapse to a single in-room voice, which is the
result the investigation predicted and the muting approach could not produce: on
the 50.3-minute recording the Diarizer had reported **six** people in the room
and never identified the user at all, because their own voice was one polluted
cluster among six. One voice on the microphone is the user *by construction*
(AD-11), so identification is restored without an enrolment.

### And not one clean recording loses a voice

| recording | in-room voices before | after | far-end clusters available |
|---|---|---|---|
| 19.1 min | 2 | **2** | 1 |
| 31.6 min | 5 | **5** | 0 |
| 28.7 min | 3 | **3** | 7 |
| 12.6 min | 2 | **2** | 0 |
| 57.3 min | 4 | **4** | 1 |
| 12.4 min | 2 | **2** | 3 |
| 22.1 min | 2 | **2** | 2 |
| 26.8 min | 2 | **2** | 1 |
| 34.1 min | 2 | **2** | 0 |

This is the control, and it is the property that makes the rule safe to ship.
Four of these recordings had far-end clusters to compare against and the nearest
was still 0.389 or further; the rest had none, and a comparison that cannot be
made excludes nothing (AD-29 — *not comparable* is never *far away*).

## The two populations, and where 0.35 sits

Every microphone cluster in the library, by its distance to the nearest far-end
centroid:

**Ruled out** (all on affected recordings):
`0.049 0.066 0.068 0.071 0.109 0.128 0.291 0.295`

**Kept** (affected and clean alike):
`0.373 0.389 0.402 0.687 0.746 0.778 0.783 0.793 0.819 0.826 0.834 0.838 0.841
0.868 0.885 0.923 0.929 0.937 0.987 1.014 1.027`

| | value |
|---|---|
| highest distance ruled out | **0.295** |
| lowest distance kept | **0.373** |
| the gap | 0.078, with nothing in it |
| **0.35** sits | 0.055 above the first, 0.023 below the second |

**So AD-31's threshold survives the boundary it was not measured across**, and
that is a finding rather than a formality: a voice that has been through a
laptop loudspeaker, a room and a microphone still lands 0.049–0.295 from its own
electrical copy — comparable to the 0.058–0.248 that the same voice measured
across separate recordings on the same channel (`calibration-speaker-threshold-2026-09-01.md`).

## Limits, stated rather than discovered later

- **The margin on the keep side is 0.023, and it is the tightest number in this
  increment.** Two genuine in-room voices sit at 0.373 and 0.389. A real
  attendee at 0.36 would be ruled out. The consequence is bounded by design —
  the cluster is **relabelled, never deleted**, so their words stay in the
  transcript and only stop being counted as a person in the room — but it is the
  number to watch, and it is why the distance is stored on the Meeting rather
  than only acted on.
- **0.35 is not centred in the gap.** A value near 0.33 would be. It is kept
  because it is the number AD-31 already carries for the sibling question, and
  one threshold with one meaning is worth more than 0.02 of centring — but that
  is a judgement, not a measurement, and it is recorded as one.
- **The 33.9-minute recording ends at four in-room voices and nobody has checked
  whether four is right.** It is the mild case (24% frame share, 5% of mic words
  duplicated) and one cluster was ruled out at 0.128. The claim measured here is
  the *direction*, which is what the previous attempt got wrong; the absolute
  count is not verified against the room.
- **Three affected recordings, one machine, one room, one pair of
  loudspeakers** — the same limit the echo calibration carries, for the same
  reason.
- Eight recordings are still not comparable at all, so this is thirteen
  recordings and not twenty-one.
