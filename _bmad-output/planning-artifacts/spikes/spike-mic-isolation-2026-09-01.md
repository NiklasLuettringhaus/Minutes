---
title: Spike — isolating the user's voice from background conversation
date: 2026-09-01
status: complete
verdict: the best fix needs no new dependency; the cheapest fix is free and not portable
---

# Spike: mic capture with people talking next to you

Driven by the first real meeting, where 723 of 1501 transcript words (48%) were a
conversation beside the user rather than the meeting. Everything below was
executed on the target machine, not recalled.

## Constraint added mid-spike

The app must work on other people's machines: another Mac's built-in mic, a
headset, **and a Windows PC**.

**The Windows half is not achievable as a port, and this needs saying plainly.**
System-audio capture is built on CoreAudio process taps
(`AudioHardwareCreateProcessTap`), which have no Windows equivalent; transcription
and diarization run on CoreML/ANE; the UI is SwiftUI with `MenuBarExtra`; detection
reads CoreAudio process objects. A Windows version is a second product sharing a
file format, not a recompile. PRD NFR-2 already scopes this to Apple Silicon.

What the constraint *does* legitimately change is the ranking below: any technique
that leans on Apple-specific processing must be treated as an optimisation for one
platform, never as the mechanism the feature depends on. That rules out making
Apple's Voice Isolation the answer, even though it is the cheapest thing here.

## Verified on this machine

| Fact | Evidence |
| --- | --- |
| Voice Isolation exists | `AVCaptureMicrophoneMode.voiceIsolation`, macOS 12+ |
| It was **off** during the meeting | `AVCaptureDevice.preferredMicrophoneMode == 0` (standard), `activeMicrophoneMode == 0` |
| Apps cannot set it | `preferredMicrophoneMode` and `activeMicrophoneMode` are `readonly class` properties. KVO-observable |
| Apps *can* deep-link to the picker | `AVCaptureDevice.showSystemUserInterface(.microphoneModes)`, macOS 12+ |
| Input device in use | **AirPods Pro**, `1 ch, 24000 Hz, Float32` — not the MacBook mic |
| We do not record which device was used | No device field on the Meeting record. Diagnosing this required an external probe |
| `setVoiceProcessingEnabled(true)` works | Returns OK; `isVoiceProcessingEnabled == true`; captured 32768 frames in 1.5 s |
| …but it changes the format | `1 ch, 24000 Hz` → **`3 ch, 24000 Hz, deinterleaved`** |
| Target-speaker matching is already linked | `SpeakerKit.DiarizationResult.nearestSpeakerCentroid(to:) -> (speakerId, distance)` and `centroidCosineDistance(between:and:)` |
| VAD is already linked | FluidAudio 0.15.6 ships `VadManager`, `VadConfig`, `VadSegment`, a streaming variant and an FSMN VAD — pulled in already for Parakeet |

### The 3-channel trap

With voice processing enabled the input node reports **three deinterleaved
channels**. `StreamFileWriter` hands the buffer to `AVAudioConverter` for a downmix
to mono, which averages all channels — so if the processed voice is one channel and
the others carry reference or raw signal, averaging would **re-add the noise the
unit just removed**. Which channel carries what was not established: doing so needs
a controlled recording with a known interfering source, and the user was mid-meeting.
**No voice-processing change should ship before that measurement.**

## A mislabel found while reading the data

With `multipleInRoom == true`, `Pipeline.assign` maps every *matched* mic span to
`room-N`. But an unmatched mic utterance falls through to the `Utterance` default,
which is `.local` — so it is labelled **"Me"**.

In the real meeting that is 14 utterances and 62 words attributed to the user that
the diarizer could not place at all:

```
 63.2s  Double check verify
 83.0s  We do the
102.1s  But it's not like the marshmallow
141.0s  On
255.4s  Slash
```

This is the same class of error AD-11 was revised to prevent: claiming an identity
the data does not support. When more than one voice is in the room, an unplaceable
mic utterance must be labelled as unidentified in-room speech, not as the user.
Independent of everything else in this spike, and a bug.

## Techniques, ranked by value per unit of work

Portability column: **any** = works on any mic and would survive a future
non-Apple implementation; **macOS** = Apple-specific.

| # | Technique | Effect | Portability | Work | New deps |
| --- | --- | --- | --- | --- | --- |
| 1 | Exclude in-room speakers from the Note | Removes 48% of that transcript | any | Small | none |
| 2 | Enrol the user's voice; keep only their mic cluster | Distinguishes the user *from* the room | any | Medium | none |
| 3 | Detect Voice Isolation is off and say so | Large when acted on | macOS | Tiny | none |
| 4 | Record the input device on the Meeting | Diagnosis, not isolation | any | Tiny | none |
| 5 | `setVoiceProcessingEnabled(true)` | Unknown until measured | macOS | Medium | none |
| 6 | Per-utterance level as a near/far tiebreaker | Weak alone, useful as a tiebreak | any | Small | none |
| 7 | VAD-gate before embedding | Fewer spurious clusters | any | Small | none |

### 1. Exclude in-room speakers from the Note

The separation already worked: `room-0`, `room-1` and the four remote speakers were
correctly distinguished, and `multipleInRoom` was correctly `true`. Nothing needs to
be detected that is not already detected — the only question is what the Note does
with it. This is a rendering decision, and it is the highest ratio of benefit to
work anywhere in this spike.

### 2. Enrol the user's voice

The enabling step for everything identity-shaped, and the only technique that
answers *which* voice is the user rather than *how many* voices there are.
`SpeakerDirectory` already stores centroids and does cosine matching; `SpeakerKit`
already exposes `nearestSpeakerCentroid`. So this is thirty seconds of the user
reading a sentence, one stored profile, and a comparison at attribution time.

PRD §6.2 explicitly deferred *"Voiceprint enrolment (record 10 seconds of Mikkel)"*
to v2, on the reasoning that FR-25 learns passively from renames. That reasoning
holds for *other* people and fails for the user: passive learning needs a correct
label to learn from, and when several voices share the mic there is no reliable
label to start from. **Enrolling one person — the user — is a different requirement
from enrolling everyone, and it should not have been deferred with it.**

### 3. Voice Isolation was off, and the app never mentioned it

Free, already built into macOS, and on AirPods Pro it is aggressive at removing
other voices. The app cannot switch it on, but it can read the mode, notice it is
`standard`, and deep-link to the picker. Not portable, so it belongs in the setup
surface as an optimisation — never as the mechanism.

### 5. Voice processing: promising, unmeasured, and riskiest

It is the only technique that could remove the neighbour's voice *before* it reaches
disk. Against it: the 3-channel format question above; it couples the input node to
the output node for echo cancellation, which may interact with the system tap;
and it is tuned for VoIP, which may thin the user's own voice. Worth measuring,
not worth assuming.

## Recommendation

Build 1, 3 and 4 now — small, independent, and 4 makes every future measurement
interpretable. Then 2, which is the real fix. Treat 5 as a spike of its own with a
controlled recording before any code. Hold 6 and 7 unless 2 proves insufficient.

## What should be configurable, and what must not be

The principle: **expose outcomes, hide mechanisms.** A user can reasonably decide
what appears in their notes. Nobody should be tuning a cosine distance.

**Configurable**

- Whether in-room voices other than the user appear in the Note — with a per-meeting
  override. This is an editorial decision about the user's own document.
- Voice enrolment itself: opt-in, re-recordable, deletable. It is biometric-adjacent
  data and §9.1 already governs it.
- The mic mute, which already exists.
- Apple voice processing: a single switch, defaulting **off** until measured, worded
  as an effect rather than as an audio-unit name.

**Not configurable**

- The speaker-matching threshold. It is the single number most likely to be set
  wrongly and hardest to reason about, and a wrong value puts the wrong name on
  someone's words. Calibrate it, ship one value, and expose *corrections* instead —
  which FR-51's voices list already does.
- VAD parameters, level thresholds, cluster counts, which VPIO channel to read.
- Whether diarization runs at all. It is load-bearing for attribution.
- Anything that would let the user silently disable the honesty guarantees: a room
  voice may be excluded from the Note but must still be visible in the app, and the
  Note must still record that speech was excluded.

**Deliberately not offered**

- Auto-muting the mic when the far end speaks. It would have helped here and it
  fails exactly when the user is the one talking.
- A "clean up my audio" master switch. It would bundle techniques with different
  portability and different failure modes behind one control nobody could reason
  about.
