# Minutes

A small macOS menu bar app that records a meeting, transcribes it on this Mac,
works out who said what, and writes one Markdown file.

Nothing leaves the machine. There is no account, no server, and no network
traffic at run time — the only network use is downloading a transcription model.

## Your data stays on your Mac

Not a slogan; it is where the files are. Everything Minutes knows about you
lives in one folder you can open, inspect and delete:

```
~/Library/Application Support/Minutes/
├── Meetings/          audio, transcript, per-speaker voice centroids
├── speakers.json      remembered voices, and your enrolled fingerprint if you made one
└── models/            downloaded transcription models
```

…plus the Markdown notes, in the folder you choose in Settings → General
(default `~/Documents/Minutes`).

Delete that folder and Minutes knows nothing about you. None of it is ever sent
anywhere, and none of it can reach this repository: a pre-commit hook and a CI
job reject meeting audio, voice embeddings and settings by shape as well as by
filename. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Installing

**On another Mac, today:** build from source. A one-command install via Homebrew
is planned — see
[`_bmad-output/planning-artifacts/RELEASE-PLAN.md`](_bmad-output/planning-artifacts/RELEASE-PLAN.md)
for what it needs and where it stands.

```bash
git clone https://github.com/NiklasLuettringhaus/Minutes.git
cd Minutes
./Scripts/build-app.sh
open /Applications/Minutes.app
```

That installs `/Applications/Minutes.app`, ad-hoc signed with the hardened
runtime. Signing is part of the build, not packaging: macOS ties audio
permission to the code signature, and an unsigned binary never even gets the
prompt.

To verify the whole chain without clicking anything:

```bash
# records 10s, transcribes, prints the resulting note
/Applications/Minutes.app/Contents/MacOS/Minutes --selftest 10

# permissions, models, pipeline state
/Applications/Minutes.app/Contents/MacOS/Minutes --doctor
```

## Using it

- **Click the menu bar icon** to start and stop. The icon turns red while
  recording and amber while transcribing.
- **When Slack or Teams takes your microphone**, a notification asks whether to
  record. It never starts on its own.
- **Notes** are written to the folder you choose in Settings → General.

Six panes: Getting Started (setup checklist, a five-second audio test, and
optional voice enrolment), Transcription (model choice), Detection (watched
apps), Summaries (how the title and summary are produced), General (folder,
retention, login), and Meetings (the library).

## How it works

Two audio streams are recorded separately: your microphone, and everything else
the Mac is playing. That is the design bet — your microphone *is* you, so "who is
the user" is a fact rather than a model's guess. Only the system stream needs
diarizing, which is the easier remaining problem.

| Concern | Choice |
| --- | --- |
| Transcription | WhisperKit or NVIDIA Parakeet, both CoreML on the Neural Engine |
| Speaker separation | SpeakerKit / pyannote v4 |
| Recognising your own voice | 256-dimensional embedding, cosine distance, threshold 0.35 measured against real meetings |
| Title, tags, summary | Apple Foundation Models when available, otherwise a deterministic local extractor |
| System audio | CoreAudio process tap |
| Storage | One directory per meeting; the Markdown note is a projection of it |

Voice identification is deliberately plain maths on a fixed-length embedding,
with no Apple-specific dependency on the identification path — `VoiceMatch.swift`
must compile against Foundation alone. Apple-only tricks are allowed as adapters
behind a port, never as the mechanism.

## If recording stops working

The app is ad-hoc signed because there is no Apple Developer certificate yet.
macOS ties consent to the signature, so **rebuilding revokes it**:

```bash
tccutil reset SystemAudioCaptureRequests dev.niklas.minutes
tccutil reset Microphone dev.niklas.minutes
```

Then run the test in Getting Started. It reports, per stream, whether audio was
actually captured — which is the only reliable way to check, because macOS
provides no API to query system-audio permission.

Fixing this properly is the first item in the release plan: a Developer ID gives
a stable signature, so consent survives an update instead of being revoked by it.

## Requirements

macOS 15 or later, Apple Silicon. App Sandbox is off (audio taps are unreliable
under it); Hardened Runtime is on.

## Development

```bash
./Scripts/setup-dev.sh    # enable the pre-commit hook
swift test                # 153 tests, 4 skipped (they need real meetings or an audio device)
./Scripts/uishot.sh --open   # render every pane at 320 / 460 / 720pt and look at it
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching model and what a change
needs before it merges.

## Planning

Built through the full BMAD pipeline. Artifacts in `_bmad-output/`:
brief → PRD (65 requirements) → UX spines (`DESIGN.md`, `EXPERIENCE.md`) →
architecture spine (32 decisions) → 63 stories across 10 epics → sprint status →
code reviews.

Two conventions in there are load-bearing: **no measurement is asserted that was
not taken**, and nothing is ever renumbered — an FR, AD, story or epic ID means
the same thing for the life of the project.
