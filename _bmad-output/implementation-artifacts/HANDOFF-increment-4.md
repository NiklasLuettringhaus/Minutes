---
title: Handoff — increment 4, voice enrolment
date: 2026-09-01
state: planned, built, reviewed, installed. Two verification gaps remain, both needing a human voice.
supersedes: HANDOFF-increment-3.md (for the items it listed as outstanding)
---

# Handoff: increment 4 (Epic 10)

The whole BMAD flow ran, the code is written, tested and reviewed, and it is
**installed at `/Applications/Minutes.app`** and running.

Installation waited for a meeting that was recording throughout the
implementation — `Scripts/build-app.sh` quits the running app before installing,
which would have destroyed it. That meeting finished, its pipeline drained on its
own (`stage: written`, 559 utterances, note written), and the build went in.
`tccutil reset Microphone` succeeded; `tccutil reset SystemAudioCaptureRequests`
reported a failure, which is the usual best-effort behaviour for that service and
is why FR-47's Test Playground exists — run it to find out empirically whether
system audio still works.

## The one action outstanding

**Getting Started → row 7 → Record Voice**, and read a paragraph out loud for 25
seconds with nobody else talking.

That is the only thing standing between this increment and being verified end to
end. Two of the three verification gaps in the code review close the moment it
happens, and one of them — that the sample audio is actually deleted — is the
increment's central privacy guarantee. Worth checking once, right after:

```
ls "$TMPDIR" | grep minutes-enrol   # must print nothing
```

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
| Test suite | **149 passing**, 0 failures, plus 4 ML integration tests | `swift test` · `MINUTES_ML_TESTS=1 swift test` |
| The build signs, bundles and installs | adhoc + runtime, `dev.niklas.minutes`, at `/Applications/Minutes.app` | `./Scripts/build-app.sh` |
| `--doctor` reports the new state | "not enrolled", threshold 0.35, margin 0.1 | ran against the **installed** bundle |
| The installed app launches and stays up | no errors in `log show`, alive after 15 s | `open /Applications/Minutes.app` |

### Assumed, and labelled as such

| Assumption | Why it is not measured | What would settle it |
| --- | --- | --- |
| 25 seconds is the right sample length | The range 20–30 s was given; the value inside it is a judgement. The two shortest samples in the calibration data (11 words, 1 word) were visibly unreliable, which is the reason it is not 5 s — but no enrolment sample has ever been measured | One real enrolment, then compare its fingerprint's cross-meeting behaviour with the meeting-derived ones |
| A fingerprint from a deliberate 25 s sample behaves like one from a whole meeting | Every figure above comes from meeting-derived centroids. A sample is shorter but cleaner, which *should* help | PRD §13 Q18 |
| A fingerprint recorded on one input device matches a meeting recorded on another | The calibration's four Meetings all used one device. The spike already found the app had been recording through AirPods without recording *that* it had | PRD §13 Q19 — and the fix, if needed, is a fingerprint per device, not a change to AD-28 |
| Refusing when two in-room voices are both close is the right call | It never fired on 37 real probes, so the trade-off is untested in practice | PRD §13 Q20 — count how often it fires before changing it |
| ~~Under 10 s to derive a fingerprint from a 25 s sample~~ | **Measured.** 0.30 s for an 8.4-second recording in a fresh process; the 25-second figure is a short extrapolation from that and the 34-minute run | Nothing further; see the measurement table below |
| The multi-voice refusal thresholds (1 voice, ≥85% dominant share, ≥8 s speech) | Chosen from the cost asymmetry, not from measurement | Enrol with a colleague talking, and see whether `voicesFound` reports 2 |

### Measured after the meeting finished

The machine went idle, so the embedder ran against real audio for the first time
(`MINUTES_ML_TESTS=1 swift test --filter VoiceEmbedderIntegrationTests`):

| Measurement | Figure |
| --- | --- |
| Embed a 2032-second mic stream (34 min, 5 in-room voices) | usable 256-dim fingerprint, 1858 s of speech found |
| `voicesFound` vs the Diarizer's own count for that room | **5 vs 5 — exact agreement** |
| Embed an 8.4-second recording, fresh process | **0.30 s** |
| Embed the 2032-second stream, models warm | 8.5 s |
| Dominant-speaker pick where the loudest voice holds 38% of the speech | one cluster, deterministically |
| embed → enrol → identify → relaunch | distance 0, producer intact after reopen |

The `voicesFound` agreement is the one that mattered: FR-62's multi-voice refusal
is what stops a fingerprint of two people being stored for months, and it rests
entirely on that count being right.

### Still not verified — both need a human voice

1. **`VoiceEnrolment.run()` has never executed.** The recording path — mic start,
   countdown, metering, stop, and the `defer` that deletes the sample. The part
   that matters is that **AD-32's deletion of the sample audio is a `defer` no test
   has run.** One `ls "$TMPDIR" | grep minutes-enrol` after the first enrolment
   settles it.
2. **No meeting has been processed with a fingerprint present.** The pure parts are
   tested exhaustively and the embedder is now proven; what is left is the wiring,
   a handful of lines. Enrol, then record a short meeting with a second voice in
   the room: the detail pane should say "recognised from your recorded voice" and
   the note's frontmatter should carry `you_identified_by: enrolled_voice`.

The *quality* half of §13 Q18 also stays open: whether a deliberate 25-second
sample's centroid lands as close to the same person's meeting centroids as two
meeting centroids land to each other. Only a real enrolment followed by a real
meeting answers it.

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
- ~~**`VoiceEnrolment` has no escape from `.analysing`.**~~ **Fixed.** The
  measurement made a timeout groundable and, in doing so, showed it was the wrong
  fix: any value long enough not to misfire while queued behind a transcription is
  far too long to help someone staring at a stuck card. `cancel()` now works during
  analysis instead, and the card says why the wait can be long.

## State of the working tree

Everything through increment 3 is built and installed at `/Applications/Minutes.app`
and running — **that is the previous binary, and it does not contain any of this
increment.** The new bundle is staged at
`.build/stage.noindex/Minutes.app`, signed adhoc + runtime, and has not been
installed. 129 tests pass. Nothing is pushed.
