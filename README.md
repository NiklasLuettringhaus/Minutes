# Minutes

A small macOS menu bar app that records a meeting, transcribes it on this Mac,
works out who said what, and writes one Markdown file.

Nothing leaves the machine. There is no account, no server, and no network
traffic at run time — the only network use is downloading a transcription model.

## Build and run

```bash
./Scripts/build-app.sh
open /Applications/Minutes.app
```

That installs `/Applications/Minutes.app`, ad-hoc signed with the hardened
runtime. The bundle is staged inside `.build/stage.noindex/` and removed after
install, so exactly one copy exists on the machine — two would mean two
Spotlight hits for the same app.
Signing is part of the build, not packaging: macOS ties audio permission to the
code signature, and an unsigned binary never even gets the prompt.

To verify the whole chain without clicking anything:

```bash
# records 10s, transcribes, prints the resulting note
/Applications/Minutes.app/Contents/MacOS/Minutes --selftest 10
```

## Using it

- **Click the menu bar icon** to start and stop. The icon turns red while
  recording and amber while transcribing.
- **When Slack or Teams takes your microphone**, a notification asks whether to
  record. It never starts on its own.
- **Notes** are written to the folder you choose in Settings → General
  (default `~/Documents/Minutes`).

The window has five panes: Getting Started (setup checklist and a five-second
test), Transcription (model choice), Detection (watched apps), General (folder,
retention, login), and Meetings (the library).

## How it works

Two audio streams are recorded separately: your microphone, and everything else
the Mac is playing. That is the design bet — your microphone *is* you, so "who is
the user" is a fact rather than a model's guess. Only the system stream needs
diarizing, which is the easier remaining problem.

| Concern | Choice |
| --- | --- |
| Transcription | WhisperKit (CoreML, Neural Engine) |
| Speaker separation | SpeakerKit / pyannote v4 |
| Title, tags, summary | Apple Foundation Models when available, otherwise a deterministic local extractor |
| System audio | CoreAudio process tap |
| Storage | One directory per meeting; the Markdown note is a projection of it |

## If recording stops working

The app is ad-hoc signed because there is no Apple Developer certificate on this
machine. macOS ties consent to the signature, so **rebuilding revokes it**:

```bash
tccutil reset SystemAudioCaptureRequests dev.niklas.minutes
tccutil reset Microphone dev.niklas.minutes
```

Then run the test in Getting Started. It reports, per stream, whether audio was
actually captured — which is the only reliable way to check, because macOS
provides no API to query system-audio permission.

## Requirements

macOS 15+, Apple Silicon. App Sandbox is off (audio taps are unreliable under
it); Hardened Runtime is on.

## Tests

```bash
swift test    # 33 tests over the deterministic core
```

## Planning

Built through the full BMAD pipeline. Artifacts in `_bmad-output/`:
brief → PRD (48 requirements) → UX spines → architecture spine (21 decisions) →
43 stories → sprint status → code review.
