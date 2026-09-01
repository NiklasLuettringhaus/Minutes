---
title: Handoff — increment 4, voice enrolment
date: 2026-09-01
state: planned, built, reviewed, NOT installed
supersedes: HANDOFF-increment-3.md (for the items it listed as outstanding)
---

# Handoff: increment 4 (Epic 10)

The whole BMAD flow ran and the code is written, tested and reviewed. **It is not
installed.** A recording was in progress on this machine throughout the
implementation, and `Scripts/build-app.sh` quits the running app before
installing, which would have destroyed a live meeting. The signed bundle is
staged and ready.

## The one action outstanding

```
# 1. Confirm nothing is recording (mic.wav must not be growing):
cd ~/Library/Application\ Support/Minutes/Meetings
for d in */; do echo "$d $(stat -f %z "$d/mic.wav")"; done; sleep 3
for d in */; do echo "$d $(stat -f %z "$d/mic.wav")"; done

# 2. Then install:
cd ~/Desktop/Code/Meeting\ recorder && ./Scripts/build-app.sh

# 3. macOS will have revoked consent, because the signature changed:
tccutil reset SystemAudioCaptureRequests dev.niklas.minutes
tccutil reset Microphone dev.niklas.minutes
```

Then: **Getting Started → row 7 → Record Voice**, and read a paragraph out loud
for 25 seconds with nobody else talking.

## Measured versus assumed

The distinction this increment was built around, so it is the first thing here.

### Measured, on this machine, from real data

| Claim | Figure | How |
| --- | --- | --- |
| The same in-room voice across separate recordings | **0.058 – 0.248** cosine distance, n=7 pairs | 24 centroids from five real Meetings, `centroids.json` on disk |
| Two different in-room voices in one Meeting | **0.596 – 1.091**, n=13 pairs | same source, 0% temporal overlap confirmed per pair |
| Two different *remote* voices, tightest genuine pair | **0.254** | same source, 0% overlap, unrelated text |
| Two "impostor" pairs that were actually one person | **0.128** and **0.373** | 83–93% temporal overlap and near-identical text — a colleague in the room who was also on the huddle, reaching both Streams |
| The shipped threshold | **0.35** — 41% headroom over the observed same-voice max, 1.7× under the tightest genuine in-room impostor | derived from the above |
| Cross-meeting identification on real data | **14 matched, 0 ambiguous, 23 no-match** over 37 probes | `EnrolmentCalibrationTests`, reading the real Meetings |
| Every stored centroid is one width | 256 dimensions, no mixing | same test |
| The no-enrolment path is unchanged | 76 pre-existing tests pass against unchanged call sites | `swift test` |
| Test suite | **129 passing**, 0 failures | `swift test` |
| The build signs and bundles | adhoc + runtime, `dev.niklas.minutes` | `INSTALL=0 ./Scripts/build-app.sh` |
| `--doctor` reports the new state | "not enrolled", threshold 0.35, margin 0.1 | ran against the staged bundle |

### Assumed, and labelled as such

| Assumption | Why it is not measured | What would settle it |
| --- | --- | --- |
| 25 seconds is the right sample length | The range 20–30 s was given; the value inside it is a judgement. The two shortest samples in the calibration data (11 words, 1 word) were visibly unreliable, which is the reason it is not 5 s — but no enrolment sample has ever been measured | One real enrolment, then compare its fingerprint's cross-meeting behaviour with the meeting-derived ones |
| A fingerprint from a deliberate 25 s sample behaves like one from a whole meeting | Every figure above comes from meeting-derived centroids. A sample is shorter but cleaner, which *should* help | PRD §13 Q18 |
| A fingerprint recorded on one input device matches a meeting recorded on another | The calibration's four Meetings all used one device. The spike already found the app had been recording through AirPods without recording *that* it had | PRD §13 Q19 — and the fix, if needed, is a fingerprint per device, not a change to AD-28 |
| Refusing when two in-room voices are both close is the right call | It never fired on 37 real probes, so the trade-off is untested in practice | PRD §13 Q20 — count how often it fires before changing it |
| Under 10 s to derive a fingerprint from a 25 s sample | Stated as a target in PRD §11 and never run | One enrolment, timed. **This blocks a real fix** — see below |
| The multi-voice refusal thresholds (1 voice, ≥85% dominant share, ≥8 s speech) | Chosen from the cost asymmetry, not from measurement | Enrol with a colleague talking, and see whether `voicesFound` reports 2 |

### Not verified at all

Three, and they are in the code review with instructions for closing each:

1. **`VoiceEnrolment.run()` has never executed.** Needs a microphone and a voice.
   The part that matters is that **AD-32's deletion of the sample audio is a
   `defer` no test has run.** After the first enrolment, check that no
   `minutes-enrol-*` directory remains under `$TMPDIR`.
2. **`SpeakerKitVoiceEmbedder.embed()` has never executed.** Needs the pyannote
   models loaded, which would have contended for memory against a live meeting.
3. **No meeting has been processed with a fingerprint present.** The pure parts are
   tested exhaustively; the wiring is a handful of lines.

## What was built

| Story | What | Status |
| --- | --- | --- |
| 10.1 | Threshold 0.45 → **0.35**, calibrated, in one place, with a test that fails if it drifts outside the measured gap | done |
| 10.2 | `VoiceEmbedding` port; `VoiceMatch` in Core (Foundation only); `Profile` gains `kind`/`producer`/`speechSeconds` with a hand-written decoder | done |
| 10.3 | `VoiceEnrolment` — records 25 s of mic only, embeds, deletes the audio in a `defer` | done, recording path unrun |
| 10.4 | `Pipeline.assign` gains `localMicVoice`; the enrolled voice decides which mic cluster is `.local` | done |
| 10.5 | Getting Started row 7 + the enrolment card, in the Test Playground's shape | done |
| 10.6 | The enrolled voice in Remembered voices, badged, deletable, named in `Forget all` | done |
| 10.7 | The detail pane and the Note say what the identification rests on | done |

## Read these, in this order

1. `_bmad-output/implementation-artifacts/code-review-increment-4.md` — four
   defects found and fixed, three verification gaps, and one fix deliberately
   *declined*. **Read first; it is the honest account of what is and is not
   proven.**
2. `_bmad-output/planning-artifacts/spikes/calibration-speaker-threshold-2026-09-01.md`
   — the measurement the increment rests on, including the two "impostors" that
   turned out to be one person heard twice.
3. `_bmad-output/planning-artifacts/epics.md` § Epic 10 — the seven stories, and
   the list of things this increment deliberately did **not** build.
4. `ARCHITECTURE-SPINE.md` — AD-11 as amended, and AD-28 … AD-32.
5. `EXPERIENCE.md` § *Voice enrolment*, § *Identity, claimed or refused*, KF-8.

## Where the design constraint bit

The user's rule was that the identification mechanism must be plain maths with no
Apple dependency — Apple-only tricks may live as adapters behind a port, never as
the mechanism. The concrete consequence, and it cost something real: the
mic-isolation spike found Apple's **Voice Isolation** is free, already in macOS,
and aggressive at removing other voices on AirPods. It was the cheapest effective
option available and it was rejected, because adopting it as the mechanism would
have made the answer macOS-only. AD-28 encodes that as a mechanical test —
**`VoiceMatch.swift` must compile against `Foundation` alone** — so the next person
cannot erode it by accident.

## Known outstanding, updated

From `HANDOFF-increment-3.md`, with what changed:

- ~~The Speaker Profile 0.45 threshold is still uncalibrated.~~ **Calibrated.** 0.35,
  measured, with the report and a test that pins it.
- **FR-49's menu bar timer text has never been seen by a human.** Unchanged.
  `MenuBarExtra` label rendering is still unverified from a terminal.
- **5 of 8 meetings show *Note missing*** (dev-sandbox artefacts). Unchanged;
  *Rewrite note* fixes each.
- **The Metal toolchain is still uninstalled**, so Epic 9's story 9.5 remains
  unverifiable. Unchanged — `xcodebuild -downloadComponent MetalToolchain`.

New, from this increment:

- **`ux-designs/.../mockups/getting-started.html`** still shows the increment-1
  row set (five rows, no voice row). It is an increment-1 artifact and the spines
  win on conflict, so it was left alone rather than half-updated.
- **Lowering the threshold to 0.35 makes existing remembered voices slightly
  harder to match.** Intended, recorded in the PRD, and mentioned in no UI. A user
  whose colleague stops being recognised has no way to connect it to this change.
- **`VoiceEnrolment` has no escape from `.analysing`.** If embedding hangs, the
  card is stuck until the app is quit. The fix is a timeout and the timeout needs a
  measured duration — see the assumptions table. Deliberately not guessed.

## State of the working tree

Everything through increment 3 is built and installed at `/Applications/Minutes.app`
and running — **that is the previous binary, and it does not contain any of this
increment.** The new bundle is staged at
`.build/stage.noindex/Minutes.app`, signed adhoc + runtime, and has not been
installed. 129 tests pass. Nothing is pushed.
