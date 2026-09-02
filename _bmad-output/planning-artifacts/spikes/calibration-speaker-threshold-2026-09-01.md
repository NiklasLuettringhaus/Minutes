---
title: Calibration — the speaker-matching threshold, measured on real meetings
date: 2026-09-01
status: complete
method: offline analysis of centroids.json from five real Meetings on this machine
verdict: 0.45 was never calibrated and is measurably too loose; 0.35 is the calibrated value
---

# Calibrating `SpeakerDirectory.matchThreshold`

`SpeakerDirectory.matchThreshold` has been `0.45` since FR-25 was implemented, with a
comment admitting it was set "conservatively" rather than measured. PRD §13 Q4 asks
whether voice-embedding similarity holds up across separate recordings at all. Both
questions are answerable now, because five real Meetings recorded on 2026-09-01 wrote
per-speaker centroid embeddings to `centroids.json`, and voice enrolment is the feature
that makes the answer load-bearing.

Everything below was computed from those files. Nothing is estimated.

## The data

| Meeting | Duration | In-room voices | Remote voices |
| --- | --- | --- | --- |
| `20260901-093248-evi3` | 506 s | 2 | 4 |
| `20260901-094602-t89h` | 1040 s | 2 | 3 |
| `20260901-101311-x3wg` | 1145 s | 2 | 1 |
| `20260901-105923-kndb` | 2032 s | 5 | 3 |
| `20260901-123106-w39q` | 8 s | 1 (`local`) | 0 |

24 centroids, 256 dimensions each, produced by SpeakerKit's pyannote v4 community-1
embedding. Distance is cosine distance, the same function `SpeakerDirectory` uses.

## Two populations, and one trap between them

The naive split is "pairs inside one Meeting are different speakers; pairs across
Meetings are unknown". The first half of that is **wrong**, and finding out why is the
most useful thing in this exercise.

Within-Meeting pairs, sorted, closest first:

| Distance | Meeting | Pair |
| --- | --- | --- |
| **0.128** | kndb | `remote-0` vs `room-3` |
| 0.254 | t89h | `remote-0` vs `remote-1` |
| 0.314 | evi3 | `remote-1` vs `remote-2` |
| **0.373** | kndb | `remote-1` vs `room-4` |
| 0.426 | t89h | `remote-0` vs `remote-2` |
| 0.451 | evi3 | `remote-0` vs `remote-2` |
| 0.596 | x3wg | `room-0` vs `room-1` |
| … | | 49 further pairs, up to 1.091 |

The two bolded pairs are **the same physical person**, not two people. Checked by
temporal overlap and text:

```
kndb  remote-0 (70 utterances) vs room-3 (57 utterances)
      82.7% of remote-0's speaking time overlaps room-3's; 92.6% the other way
      remote-0  54.7-56.1  [4-word utterance]
      room-3    55.0-56.2  [the same 4 words]

kndb  remote-1 (17 utterances) vs room-4 (20 utterances)
      85.1% / 80.0% overlap
      remote-1 1310.8-1318.9 [8-word utterance naming a product]
      room-4   1313.0-1316.3 [the same 8 words, product name transcribed differently]
```

A colleague sitting in the room who is *also* joined to the huddle on their own laptop
reaches both Streams: the room microphone hears them directly, and the system tap hears
them returning down the call. The embedding scored them 0.128 apart — which is the
embedding working correctly, not failing.

Every other close pair has **0.0% temporal overlap** and unrelated text, so those are
genuine different speakers.

## The measured distributions

**Same speaker, same Stream kind, different Meetings.** Seven in-room pairs form one
connected cluster across four Meetings recorded hours apart on the same input device:

```
x3wg/room-0 ↔ kndb/room-1   0.058
evi3/room-1 ↔ t89h/room-1   0.098
evi3/room-0 ↔ t89h/room-0   0.115
t89h/room-0 ↔ x3wg/room-0   0.148
evi3/room-0 ↔ x3wg/room-0   0.183
t89h/room-0 ↔ kndb/room-1   0.207
evi3/room-0 ↔ kndb/room-1   0.248
```

**Range 0.058 – 0.248.** This is the population enrolment depends on: one in-room voice,
reproducible across independent recordings.

**Different in-room speakers, same Meeting** (n = 13, all with 0% temporal overlap):
**range 0.596 – 1.091**, minimum 0.596.

**Different remote speakers, same Meeting** (n = 12, excluding the two cross-Stream
same-person pairs): minimum **0.254**.

## What this settles, and what it does not

**Settled — PRD §13 Q4, for in-room voices.** Voice-embedding similarity does hold up
across separate recordings. Same speaker ≤ 0.248; different in-room speakers ≥ 0.596.
That is a factor-of-2.4 gap with nothing in it. Enrolment is not a gamble.

**Settled — 0.45 is too loose.** Two genuinely different remote speakers measured 0.254
apart and two more 0.314 apart. At 0.45 the directory would call both pairs the same
person. Counting matches at each threshold, with the two proven same-person pairs
excluded from the error count:

| Threshold | Same-in-room-speaker pairs caught (of 7) | False matches (measured) |
| --- | --- | --- |
| 0.25 | 7 | 0 |
| 0.30 | 7 | 1 |
| **0.35** | **7** | **2** |
| 0.45 (shipped) | 7 | 3 |
| 0.60 | 7 | 5 |

**Chosen: 0.35.** 0.25 has zero measured false matches but only 0.002 of headroom above
the observed same-speaker maximum of 0.248 — a different room or a different microphone
would push a genuine match past it, and a missed enrolment match drops the user back to
`In-room, unidentified`, which is the exact state this increment exists to remove. 0.35
keeps 41% headroom on the genuine side, stays 1.7× below the tightest genuine in-room
impostor, and is strictly better than the shipped 0.45 on both axes.

**Not settled — remote-vs-remote.** Same-speaker distances reach 0.248 and
different-speaker distances start at 0.254. Those populations touch, and **no single
threshold separates them on this data.** 0.35 therefore admits two known false matches
among remote speakers. That is accepted rather than fixed, because the product already
has the correction path FR-25 was designed around: an auto-applied name renders as
`~Name`, and FR-51's voices list makes it visible and correctable. A wrong remote name is
recoverable in one click; the alternative is a threshold so tight that enrolment stops
working.

**Not measured.** Whether the enrolled centroid from a deliberate 20–30 s sample behaves
like a centroid derived from a whole meeting. The enrolment sample is shorter and cleaner
than a meeting, which should help, but no enrolment sample exists yet — the only figures
above come from meeting-derived centroids. Two tiny-sample centroids in the data
(`kndb/remote-2`, 11 words; `w39q/local`, 1 word) sat 0.325 apart from each other and
from unrelated voices, which is the visible cost of a short sample and the reason
enrolment asks for 20–30 s rather than 5.

## Reproducing this

The analysis reads only `~/Library/Application Support/Minutes/Meetings/*/centroids.json`
and `meeting.json`. It is not committed: the centroids are biometric-adjacent data
belonging to the user's colleagues, and PRD §9.1 keeps them on this machine. The
`EnrolmentCalibrationTests` case reads the same files if they are present on the machine
and skips otherwise, so the numbers above stay checkable without copying anyone's voice
into the repository.
