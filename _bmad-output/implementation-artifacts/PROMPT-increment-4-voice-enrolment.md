Run the entire BMAD flow autonomously to build **voice enrolment** for Minutes, the
local-first macOS meeting recorder in this repo. Do not ask me questions — every
decision you need is below or in the named artifacts. I will review at the end.

## What to build

A user records ~20–30 seconds of their own voice, once, from the onboarding flow.
Minutes stores a voice fingerprint locally and thereafter uses it to identify which
voice on the microphone stream is the user, instead of guessing.

**It must be part of the Getting Started checklist**, as its own row, optional but
prominent. Follow the existing row pattern exactly — do not invent a second
onboarding style. The Test Playground (FR-47) is the precedent for a
record-and-verify affordance in that pane; reuse its shape.

## Why, and the defect it closes

The app already separates the voices on the mic stream. It cannot tell which one is
the user. In the first real meeting — an 8-person Slack huddle with two colleagues
talking beside the user — 723 of 1501 transcript words (48%) were the neighbouring
conversation, and 14 utterances the diarizer could not place fell through to a
default and were printed as the user's own words. That default is now
`.inRoomUnidentified`, which is honest but still not an identification.

Enrolment replaces the guess with a measurement.

## Decisions already made — implement these, do not re-litigate

- **Opt-in.** Nothing happens until the user records a sample. Deletable in one click.
- **Local only.** The fingerprint never leaves the machine. It is biometric-adjacent
  data and PRD §9.1 governs it, exactly as Speaker Profiles already are.
- **Reuse the existing store.** `SpeakerDirectory` already persists
  `Profile { name, centroid, samples, updatedAt }` with `match`, `remember`,
  `forget`, `forgetAll`, `summaries`, `rename`. Enrolment feeds the same store
  deliberately instead of accidentally via a rename. The Remembered voices list in
  General must keep working and should show the enrolled profile distinctly.
- **The matching threshold is NOT user-configurable.** It is the number most likely
  to be set wrongly, and a wrong value puts the wrong name on someone's words with
  no way for the user to notice. Ship one value; expose *corrections* instead, which
  the voices list already does. `SpeakerDirectory.matchThreshold` is currently 0.45
  and has never been calibrated — enrolment is what finally makes calibration
  possible, so calibrate it against real data if you can and say so if you cannot.
- **The mechanism must be plain maths on the sound.** No Apple-specific dependency
  on the identification path. The user wants the design flexible enough to plug into
  other systems: Apple-only tricks may exist as adapters behind a port, never as the
  mechanism. This is why Voice Isolation was explicitly rejected.
- **Enrolment does not distinguish participants from bystanders.** Both are "not the
  user". A conference room normally holds several participants and that is correct
  behaviour. Deciding which non-user voice belongs in the note is already handled by
  the per-speaker Exclude control in the meeting detail — do not duplicate or
  automate it.

### Explicitly rejected — do not build

- Automatically excluding in-room voices from the note.
- A Voice Isolation prompt or nudge (Mac-only).
- Auto-muting the microphone when the far end speaks.
- Any user-facing slider for thresholds, VAD parameters, or cluster counts.

### Deferred to a separate increment — out of scope here

macOS input voice processing (`setVoiceProcessingEnabled`). It works but changes the
input format from 1 channel to 3 deinterleaved, and which channel carries the clean
signal is unmeasured. It needs a controlled recording first. Leave it alone.

## Verified facts — do not re-research these

- `SpeakerKit.DiarizationResult` exposes `nearestSpeakerCentroid(to: [Float]) ->
  (speakerId: Int, distance: Float)` and `centroidCosineDistance(between:and:)`.
  Already linked via `argmax-oss-swift` 1.1.0. No new dependency is needed.
- Per-meeting centroids are already written to `centroids.json` in each meeting
  directory.
- Audio is written at 16 kHz mono 16-bit; both engines and the diarizer resample to
  16 kHz mono on read.
- Attribution lives in `Pipeline.assign(micSpans:systemSpans:multipleInRoom:to:)`.
  Today: with several mic voices, matched spans become `room-N` and unmatched become
  `.inRoomUnidentified`; with one mic voice everything is `.local`. Enrolment should
  change *which* mic cluster becomes `.local`, not the structural rules (AD-11:
  place is structural, identity is inferred).
- `PRD §6.2` deferred *"Voiceprint enrolment (record 10 seconds of Mikkel)"* to v2
  on the reasoning that profiles are learned passively from renames. **That
  reasoning holds for other people and fails for the user**, because passive
  learning needs a correct label to start from and several voices on one mic provide
  none. Reverse that deferral in writing for the user's own voice only.
- Current counts: PRD has 61 FRs (new ones start at FR-62), the architecture spine
  has 27 ADs (new start at AD-28), `epics.md` has 9 epics (add Epic 10). 76 tests
  pass via `swift test`.

## The flow to run

Use the BMAD skills, headless, in this order. Update in place; never renumber
existing FRs, ADs, stories or epics.

1. `bmad-prd` — `-H update` the PRD at
   `_bmad-output/planning-artifacts/prds/prd-meeting-recorder-2026-08-31/prd.md`.
   Add the new FRs, amend FR-21/FR-25/§6.2 where enrolment changes them, and log
   every decision through `memlog.py`.
2. `bmad-ux` — `-H update` `DESIGN.md` and `EXPERIENCE.md` under
   `_bmad-output/planning-artifacts/ux-designs/ux-meeting-recorder-2026-08-31/`.
   The enrolment row, its recording state, and a key flow. Verify every
   `{token}` reference resolves.
3. `bmad-architecture` — `-H update`
   `_bmad-output/planning-artifacts/architecture/architecture-meeting-recorder-2026-08-31/ARCHITECTURE-SPINE.md`.
   Amend AD-11 if identity resolution changes, and add ADs for the enrolment port.
4. `bmad-create-epics-and-stories` — `-H`, add Epic 10 to
   `_bmad-output/planning-artifacts/epics.md`.
5. `bmad-sprint-planning` — `-H sprint-planning`, merge into
   `_bmad-output/implementation-artifacts/sprint-status.yaml`. Verify the script
   reports 0 changed and no dropped orphans.
6. **Build it.** Then `bmad-code-review`.

## Guardrails

- **Check whether a recording is in progress before installing or relaunching.** The
  app is live at `/Applications/Minutes.app`. Compare a meeting's `mic.wav` size two
  seconds apart; if it is growing, build and test but do not install, and say so.
- `./Scripts/build-app.sh` builds, signs ad-hoc and installs. `--doctor` prints live
  state; `--selftest` exercises the whole pipeline and writes a real note.
- Do not assert any measurement you did not take. If enrolment accuracy or the
  threshold is unverified, say it is unverified.
- Four real meetings from 2026-09-01 are on disk under
  `~/Library/Application Support/Minutes/Meetings/` — including the 8-person huddle
  with two in-room voices. Use them as test data rather than inventing fixtures.
- Commit as you go, locally. Do not push.

## Read first

- `_bmad-output/planning-artifacts/spikes/spike-mic-isolation-2026-09-01.md` — the
  research this comes from, including what was measured and what was rejected.
- `_bmad-output/implementation-artifacts/HANDOFF-increment-3.md` — conventions, the
  toolchain blocker for the unrelated summarisation increment, and what is unmeasured.
- `CLAUDE.md` if present, then `Sources/Minutes/Services/SpeakerDirectory.swift`,
  `Sources/Minutes/Services/Pipeline.swift` and
  `Sources/Minutes/UI/GettingStartedPane.swift`.

## Done means

The PRD, UX spines, architecture spine, epics and sprint status all updated and
self-consistent; enrolment reachable from Getting Started; a recorded sample
produces a stored profile that survives relaunch; a meeting with several mic voices
labels the enrolled user as themselves and the rest as in-room; the Remembered
voices list shows and can delete the enrolled profile; `swift test` green with new
tests covering the matching logic; a code review written; and a short report of what
is measured versus assumed.
