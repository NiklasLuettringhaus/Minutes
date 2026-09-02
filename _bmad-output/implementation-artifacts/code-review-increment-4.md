---
title: Code review — increment 4, voice enrolment
date: 2026-09-01
scope: commits aad4266..HEAD (Epic 10 · PRD FR-62…FR-65 · AD-11 amended, AD-28…AD-32)
verdict: shipped and installed; five defects found and fixed, one gap closed against real audio, two gaps still needing a human voice
tests: 149 passing via `swift test` (76 before this increment), plus 4 ML integration tests behind `MINUTES_ML_TESTS=1`
---

# Code review: voice enrolment

## How this review was run, and where it is weak

Three lenses — a blind hunt, an edge-case path trace, and a verification-gap
trace — run **inline, by the author, not as independent subagents.** The skill's
own reviewer guidance says an inline self-check does not count for the reason
that matters: a fresh context finds what the author talks past. That weakness is
real and is not being glossed. It is the single largest limitation of this
review, and the mitigation was to lean on mechanical checks the author cannot
talk past — reintroducing each fixed defect and watching the suite go red.

Two environment constraints shaped the first pass, and one has since lifted:

- **A recording was in progress throughout the review.** A meeting
  (`20260901-130459-13ap`) started at 13:04 and was still growing when this was
  written, so the app was built and signed but **not** installed —
  `Scripts/build-app.sh` quits the running app before installing, which would have
  destroyed a live recording. No test opened an audio device.
- **That meeting then finished.** Its pipeline drained on its own (`stage: written`,
  559 utterances, note on disk), the build was installed to
  `/Applications/Minutes.app`, and one of the three verification gaps was closed
  against real audio. This document was updated rather than superseded; each
  section below says whether it predates that or followed it.

## Verdict

Shipped and installed. Five defects found and fixed, one of them user-visible and
introduced by this increment. One verification gap closed once the machine went
idle; **two remain, and both need a human voice** — no enrolment sample has been
recorded, so the recording path and the sample-quality question are still open.

## Defects found and fixed

### 1. In-room speakers numbered from 2 whenever the user was identified — *user-visible, introduced by this increment*

`SpeakerLabelID.local.isInRoom` is `true`, because the Local Speaker **is** in the
room. The numbering loop advanced the in-room counter for any already-named
in-room label, so a named `local` consumed "In-room 1" without using it and the
first colleague came out as `In-room 2`.

This was latent and unreachable before increment 4: with several voices on the
microphone, `local` was never a speaker on the Meeting at all, so the branch never
ran with `local` in it. An enrolment match is precisely what puts a named `local`
into `speakers`, so this increment made a two-month-old line wrong.

Fixed, and the fix exposed a second problem: the numbering lived inline inside
`Pipeline.attributeStage`, a private method on an actor that needs a
`MeetingStore` — so it had **no seam to test at**, which is why the latent bug sat
there unnoticed. It is now `Meeting.assignedSpeakerNames(localName:)`, pure and in
Core. Three tests cover it, including one asserting a *remembered colleague still
does* consume a number, so the fix did not simply make every named in-room label
free.

Verified by reintroducing the bug: three assertions fail, with the messages that
name the rule.

### 2. The diarizer-glue round trip had no seam either — *latent, would have been silent*

`diarizeStage` turned `[Int: [Float]]` cluster centroids into candidates keyed by
`String(idx)`, resolved them, and converted the winning key back with `Int(key)`.
Three lines that decide **which voice is the user**, reachable only by a test that
loads a CoreML model and reads a WAV file. If the round trip were wrong, the wrong
colleague would be labelled as the user and every test in the repository would
still have passed.

Extracted to `VoiceMatch.candidates(from:producer:)` and
`VoiceMatch.micVoiceIndex(_:)`. Seven tests, including the one that would actually
have caught a naive implementation: **double-digit cluster indices**, where
string ordering puts `"10"` before `"2"` and `resolve`'s tie-break orders by key.
The extracted function sorts numerically.

### 3. Two types independently asserted the same producer string — *would have diverged silently*

`Pipeline` tagged the diarizer's own per-cluster centroids with
`"speakerkit/pyannote-v4-community-1"`, and `SpeakerKitVoiceEmbedder` declared the
same literal for the fingerprints it produces. Correct today, and only because
both happened to be written the same. The first time either changed, every
comparison would return `nil` — and AD-29's entire purpose is that such a
divergence is *detectable* rather than silent, so having it introduced by a
duplicated literal is the specific irony worth avoiding.

Now one `static let producerID`, referenced by name from both sites, with a test
pinning them together and a comment saying that a future model change should
update it deliberately.

### 4. Two smaller ones, found before the lenses ran

- **`isRunning` was derived from `phase` alone**, and `phase` only becomes
  `.recording` after an `await` on the microphone permission request. Two taps
  inside that window both passed the guard, started two `MicCapture`s on one audio
  engine, and the second one's failure was reported for a recording that was
  running fine. Now a separate `inFlight` flag set synchronously on entry.
- **The FR-25 passive path could name the `local` label.** If the user had ever
  renamed their own voice, `match()` would apply that name to `local` and add it
  to `inferredSpeakers` — so the one chip that was either certain or measured
  rendered as `~Niklas`, marked as a guess. AD-30 gives the user's identity two
  sources and their display name one owner; this was a third writer. `local` is
  now excluded from that loop.

## Edge-case trace: paths reachable from the diff and not guarded

### Reported, then fixed once the measurement arrived

**`VoiceEnrolment` had no escape from `.analysing`**, and **nothing bounded how
long the ML serial executor could make enrolment wait.** Two findings, one root
cause: embedding runs on the same serial executor as transcription (AD-14/AD-26),
which is correct — it is what stops two models being resident at once — so a user
who records their voice while a two-hour meeting is transcribing sits in
`.analysing` until that finishes. `cancel()` only worked during the countdown, so
the card was stuck and the only recovery was quitting the app.

The review initially declined to fix this, because the obvious fix is a timeout
and no measurement existed for what a reasonable one would be. **The measurement
then arrived** — 0.30 s for an 8.4-second recording in a fresh process, see the
closed gap below — which made a timeout groundable and, in doing so, made it
clearly the *wrong* fix. Any value long enough not to misfire while queued behind
a transcription is far too long to help someone staring at a stuck card. Those two
requirements do not fit in one number.

Fixed without a number instead: `cancel()` now works during analysis too. The
embedder cannot be interrupted mid-call, so the work finishes and its result is
discarded — nothing reaches the store, and the sample audio still goes in the
`defer` (AD-32). The card gains a Cancel button and says why the wait may be long:
*"If Minutes is transcribing a meeting, this waits until that finishes — only one
model runs at a time."* A way out needs no measurement and cannot misfire.

**`SpeakerKitVoiceEmbedder` assumes 16 kHz when reporting a too-short sample.**
`voiceSampleTooShort(seconds: Double(samples.count) / 16_000)` hard-codes the
rate. It is correct — `AudioProcessor.loadAudioAsFloatArray` returns 16 kHz, and
the writer stores 16 kHz — but it is an assumption in an error message rather than
a derived value, and it would silently misreport a duration if either changed. Low
consequence: the number appears only in a failure the user is about to retry.

### Traced and found handled

- Permission denied, not-determined, and denied-after-request: guarded before any
  directory is created.
- `createDirectory` failure: reported, and the `defer` removing the directory is
  declared *before* the attempt, so a failed create leaves nothing behind.
- Cancellation mid-countdown: breaks the loop, stops the capture, removes the
  directory, returns `.idle` — indistinguishable on disk from never starting.
- A sample with speech but two speakers, and a sample with one speaker but 3
  seconds of speech: distinct named refusals, not one generic error.
- A sample where the diarizer finds one cluster but the centroid map has no entry
  for it: throws rather than storing an empty fingerprint.
- `seconds[dominant]!` — the key comes from `seconds.max()`, so the force-unwrap
  cannot fail.
- Zero-length and mismatched-length vectors, and zero vectors: all return "cannot
  say" rather than a distance.
- A match on a cluster index no span carries: changes nothing rather than
  relabelling a different voice. Tested.
- Enrolment deleted between meetings: `identifyLocal` returns `.notComparable`,
  and attribution reverts to the pre-enrolment path. Tested.
- A `speakers.json` written before this increment: loads, with every new field
  defaulted, and a profile with no recorded producer is *not comparable* rather
  than coerced. Tested — and this is the failure that already happened once, when
  adding one field to `Meeting` orphaned five real recordings.

## Verification gaps

Three were recorded. **One is now closed** — see below; the other two still need a
human voice. Recorded rather than hidden.

### `VoiceEnrolment.run()` has never executed

The recording half of FR-62 — mic start, countdown, level metering, stop, the
`defer` that deletes the sample — is untested and has not been run. It needs a
microphone and a human voice.

What *is* verified: the policy that sits on top of it (multi-voice refusal
thresholds, minimum speech) is expressed as constants and the store path is
tested end-to-end with a real file and a fresh actor. What is not: that the audio
actually reaches disk, and — the one that matters — **that the sample is actually
deleted.** AD-32 is the increment's central privacy guarantee and its
implementation is a `defer` that no test has executed.

*How to close it:* record a sample from Getting Started, then confirm no
`minutes-enrol-*` directory remains under `$TMPDIR`. One command, one minute,
needs an idle machine.

### ~~`SpeakerKitVoiceEmbedder.embed()` has never executed~~ — **CLOSED 2026-09-01**

Closed as soon as the machine went idle, exactly as this section proposed:
`VoiceEmbedderIntegrationTests` points `embed()` at the real `mic.wav` files. It
is guarded by `MINUTES_ML_TESTS=1` so the default suite stays in the tens of
milliseconds, and by the presence of real Meetings, and it copies nothing into the
repository.

Four tests, all passing, and the figures are the point:

| What was run | Result |
| --- | --- |
| Embed a 2032-second mic stream (34 minutes, 5 in-room voices) | usable 256-dim fingerprint, `speech=1858.1 s`, `dominantShare=0.38` |
| `voicesFound` against the Diarizer's own ground truth for that room | **5 reported, 5 recorded — exact agreement** |
| Embed an 8.4-second recording in a fresh process | **0.30 s**; `7.0 s` of speech found, 1 voice |
| Whether the enrolment policy would refuse the 5-voice sample | yes, on both the voice count and the dominant share |
| Whether the enrolment policy would refuse the 8.4-second one | yes, on speech found (7.0 s < 8.0 s minimum) |
| embed → enrol → identify → relaunch, on a real fingerprint | resolves at distance 0, producer intact after reopen |

The `voicesFound` agreement is the one that mattered. FR-62's multi-voice refusal
is the guard that stops a fingerprint of two people being stored for months, and
it rests entirely on that count being right. It is now measured against the
Diarizer's own answer on the hardest real case available — a five-person room.

The dominant-speaker selection is also confirmed working rather than assumed: on
a room where the loudest voice holds only 38% of the speech, it still picked one
cluster deterministically instead of failing or returning the first.

### The full pipeline path has never run with a fingerprint present

`diarizeStage`'s enrolment lookup is now three tested pure functions plus an
`await` on the store, and `assign` is tested exhaustively — but no meeting has
been processed end to end with an enrolled voice. The remaining untested surface
is the wiring, which is a handful of lines and is the smallest of the three gaps
after the extraction in defect 2.

*How to close it:* enrol, then record a short meeting with a second voice in the
room, and check the detail pane says "recognised from your recorded voice" and the
note's frontmatter carries `you_identified_by: enrolled_voice`.

## Contract compliance

| Contract | Status |
|---|---|
| AD-28 — mechanism is arithmetic in Core, no Apple type on the identification path | Held. `VoiceMatch.swift` imports `Foundation` only. The one Apple-aware file is the adapter. |
| AD-29 — a fingerprint is comparable only within its producer and dimension | Held, and tested at both the distance and resolution levels. Defect 3 was the one place it was fragile. |
| AD-30 — `.local` by structure or enrolment, never by passive learning | Held after defect 4. Tested with an identical vector, which is the strongest form of the check. |
| AD-31 — one calibrated constant, not a setting | Held. 0.35 in one place, absent from `Preferences`, `UserDefaults` and every pane. Three tests pin it, including one that fails if it drifts outside the measured gap. |
| AD-32 — enrolment audio is transient | Implemented as a `defer`, **not executed by any test.** See gaps. |
| AD-11 as amended — place stays structural | Held. Tested directly: an enrolled voice cannot relabel a system-stream utterance, and unplaceable mic speech stays unidentified. |
| AD-8 — no stage added to the pipeline | Held. The lookup is inside `diarize`; attribution receives a value. |
| FR-65 — no exposed dial | Held. A measured distance is displayed in three places and settable in none. |
| PRD §9.1 — never transmitted, never logged | Held. Vectors are never logged; the adapter logs dimensions and counts only. `--doctor` was tightened during review to print sample depth rather than colleagues' names, since its output gets pasted into messages. |
| "byte-for-byte unchanged without a fingerprint" | Held, and this is the test that matters most: the 76 pre-existing tests pass against unchanged call sites, because `assign`'s new parameter has a default. |

## Smaller observations, not acted on

- Lowering the threshold from 0.45 to 0.35 makes existing remembered voices
  slightly harder to match. That is the intended consequence of calibrating, it is
  recorded in the PRD, and no UI mentions it. Defensible; noted because a user
  whose colleague stopped being recognised has no way to connect it to this change.
- `VoiceMatch.resolve` treats a runner-up *outside* the threshold as grounds for
  ambiguity when it is within the margin of the best (e.g. 0.34 against 0.40).
  Stricter than strictly necessary, in the safe direction, and it never fired on
  37 real probes.
- `Meeting.Basis` has five cases and the UI renders four of them; `.remote` is
  deliberately silent. Worth keeping in mind if a remote-identity feature ever
  lands.
- The enrolment card's copy says "about 25 seconds" while the constant is exactly
  25. Fine, and it should stay approximate rather than being derived, so the copy
  does not read as a countdown promise.

## What changed as a result of this review

| Change | Kind |
|---|---|
| `Meeting.assignedSpeakerNames(localName:)` extracted from `Pipeline.attributeStage`; in-room numbering fixed | defect fix + new test seam |
| `VoiceMatch.candidates(from:producer:)` and `micVoiceIndex(_:)` extracted from `diarizeStage` | latent-defect prevention + new test seam |
| `SpeakerKitVoiceEmbedder.producerID` made the single declaration | latent-defect prevention |
| `VoiceEnrolment.inFlight` | defect fix |
| `local` excluded from the FR-25 naming loop | defect fix |
| `--doctor` prints sample depth, not colleagues' names | privacy tightening |
| `cancel()` works during `.analysing`; the card explains the queue | defect fix — after the measurement made a timeout indefensible |
| `VoiceEmbedderIntegrationTests` — 4 tests against real audio, behind `MINUTES_ML_TESTS=1` | closed a verification gap |
| 30 new tests (149 total plus 4 ML integration tests, from 76 before the increment) | coverage |
