# Contributing to Minutes

## The one rule that is not negotiable

**User data never enters this repository.** Meetings, voice fingerprints and
settings live only on the machine that recorded them:

| What | Where |
| --- | --- |
| Meetings — audio, transcript, per-speaker centroids | `~/Library/Application Support/Minutes/Meetings/` |
| Remembered voices and any enrolled fingerprint | `~/Library/Application Support/Minutes/speakers.json` |
| Downloaded transcription models | `~/Library/Application Support/Minutes/models/` |
| The Markdown notes | the folder chosen in Settings → General |

This is the product's central privacy claim, so it is enforced rather than
remembered. `Scripts/check-no-user-data.sh` runs as a pre-commit hook and again
in CI, and it rejects by *shape* as well as by name — a `speakers.json` renamed
to `fixture-data.json` is still caught, because a run of 32 or more floats in one
array is a voice embedding whatever the file is called.

If you need a hard case for a test, **write a fixture**. Fixtures can be harsher
than reality, and they can exist before the meeting does.

## Setting up

```bash
git clone https://github.com/NiklasLuettringhaus/Minutes.git
cd Minutes
./Scripts/setup-dev.sh      # enables the pre-commit hook
swift test
./Scripts/build-app.sh      # builds, signs, installs to /Applications
```

Requires macOS 15 or later on Apple Silicon, and Xcode.

## Branching

`main` is always releasable. Nothing is committed to it directly.

```
main ────────●────────────●───────────●──────▶
              \          /             \
   feat/voice-enrolment ─┘      fix/rename-popover ─┘
```

- One branch per piece of work, named `feat/…`, `fix/…`, `docs/…`, `chore/…` or
  `spike/…`.
- Keep them short-lived. A branch open for a week is a merge problem being saved
  up for later.
- Open a pull request into `main`. CI must be green: the user-data guard, the
  build, the tests, and the bundle assembling and signing.
- Squash on merge, so `main` reads as one commit per change.
- Releases are tags on `main`: `v0.1.0`, `v0.2.0`, …

## Commit messages

Say what changed and what it means, in a sentence. The history of this project is
meant to be readable by someone trying to understand a decision a year later:

```
The rename popover opened on the wrong row, and that was also why it was slow
Speaker index with devices, per-speaker exclusion, and the 'Me' mislabel fix
Story 9.1: no summary unless something real wrote it; store audio at 16 kHz mono
```

Not `fix bug`, not `wip`, not `address review comments`.

## What a change needs before it merges

- `swift test` green. The suite is fast and there is no reason to skip it.
- **A human has looked at any pane whose layout changed.** This is a standing
  condition, not a nicety: two increments shipped critical layout defects past a
  green test suite because SwiftUI layout is not unit-testable. Render the panes
  with `./Scripts/uishot.sh --open` and look. The tool cannot draw a `Button`, a
  `Picker` or a `ProgressView`, and it cannot show a popover — so it answers
  *does this layout hold at this width*, never *is the app correct*.
- **No measurement asserted that was not taken.** If a number is an estimate, it
  says so. This applies to code comments, to documentation and to pull request
  descriptions equally.
- Planning artifacts updated when a decision changed, under `_bmad-output/`.
  Never renumber an existing FR, AD, story or epic — amend in place, or add the
  next number.

## Architecture in one paragraph

Ports and adapters around a staged, resumable pipeline. The microphone and the
system output are recorded as two separate streams, so "which voice is the user"
is a structural fact rather than a model's guess. `Sources/Minutes/Core/` is pure
and depends on Foundation alone — `VoiceMatch.swift` in particular must compile
against Foundation only, which is what keeps voice identification plain maths
instead of an Apple-specific trick. The binding decisions are in
`_bmad-output/planning-artifacts/architecture/…/ARCHITECTURE-SPINE.md`; read
AD-8, AD-11, AD-20, AD-21 and AD-28 before changing how identity or storage work.
