# Minutes

Records a meeting on your Mac, transcribes it locally, works out who said what,
writes one Markdown file. Menu bar only. Nothing leaves the machine except the
transcription model it downloads once.

Apple Silicon, macOS 15+.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/NiklasLuettringhaus/Minutes/main/Scripts/install.sh | bash
```

That works with no security prompt, and not by bypassing one: macOS blocks an
app like this only when the file is quarantined, and quarantine is set by
browsers, not by `curl`. **If you download the zip from the Releases page in a
browser instead, macOS will block it** — that copy needs
`xattr -dr com.apple.quarantine Minutes.app`, or System Settings → Privacy &
Security → Open Anyway.

Or build it, which needs no download at all. Requires Xcode; takes about a
minute.

```bash
git clone https://github.com/NiklasLuettringhaus/Minutes.git
cd Minutes && ./Scripts/build-app.sh
```

## First run

Click the icon to start and stop — red recording, amber transcribing. When Slack
or Teams takes the microphone, a notification asks whether to record; it never
starts on its own.

- macOS asks for the microphone. It also needs system-audio permission, which no
  API can check — Getting Started has a five-second test that reports, per
  stream, whether audio actually arrived. Run it once.
- The first meeting downloads a model, 460–630 MB.
- **Updates revoke both permissions**, because consent is tied to the signature
  and the signature changes every build. That is why recording stops working
  after an update:

```bash
tccutil reset Microphone dev.niklas.minutes
tccutil reset SystemAudioCaptureRequests dev.niklas.minutes
```

## Your data

All of it, nowhere else:

```
~/Library/Application Support/Minutes/
├── Meetings/       audio, transcripts, per-speaker voice centroids
├── speakers.json   remembered voices, and your enrolled voice if you made one
└── models/         downloaded transcription models
```

Plus the notes folder you pick. Nothing is transmitted anywhere. Settings are
still in `~/Library/Preferences/` — a known gap.

## Why it gets speakers right

The microphone and the system output are recorded as two separate streams, so
"which voice is yours" is a fact rather than a guess. Only the system stream
needs diarizing. Transcription is WhisperKit or Parakeet on the Neural Engine;
speaker separation is pyannote v4; your own voice is matched by cosine distance
against a threshold measured on real meetings, not chosen.

## Uninstall

```bash
rm -rf /Applications/Minutes.app
rm -f  ~/Library/LaunchAgents/dev.niklas.minutes.login.plist
rm -f  ~/Library/Preferences/dev.niklas.minutes.plist
rm -rf ~/Library/Application\ Support/Minutes    # your meetings. destructive.
```

## Development

```bash
./Scripts/setup-dev.sh   # pre-commit hook
swift test               # 153 tests
./Scripts/uishot.sh      # render every pane and look at it
```

[CONTRIBUTING.md](CONTRIBUTING.md) for branching and review rules. `_bmad-output/`
for requirements, architecture decisions and the release plan.
