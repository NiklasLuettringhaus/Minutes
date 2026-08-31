---
title: "Addendum: Minutes — verified technical context"
status: draft
created: 2026-08-31
updated: 2026-08-31
consumers: [bmad-prd, bmad-ux, bmad-architecture]
---

# Addendum: verified technical context

Everything here was verified on the target machine or against primary sources on 2026-08-31. It exists so downstream documents do not re-derive it. Where a claim is unverified it is marked **UNVERIFIED**.

## 1. Host environment (verified)

| Fact | Value | How verified |
|---|---|---|
| macOS | 26.6.2, build 25G83 | `sw_vers` |
| Kernel | Darwin 25.6.0, arm64 | `uname -a` |
| Xcode | 26.6 (17F113) | `xcodebuild -version` |
| Swift | 6.3.3 | `swift --version` |
| macOS SDK | 26.5 | `xcodebuild -showsdks` |
| CPU / RAM | Apple M5, 24 GB, 10 cores | `sysctl` |
| Codesigning identities | **none (0 valid)** | `security find-identity -v -p codesigning` |
| FoundationModels.framework | present | `/System/Library/Frameworks/FoundationModels.framework` |
| Apple Intelligence | **opted out** (`opted_out_buddy = 1`) | `defaults read com.apple.CloudSubscriptionFeatures.optIn` |
| Slack | `com.tinyspeck.slackmacgap` | Info.plist |
| Microsoft Teams | `com.microsoft.teams2` | Info.plist |
| uv / Python | uv 0.12.7, Python 3.14.3 | `uv --version` |

Build machine == run machine. No cross-compilation, no deployment concerns beyond this host.

## 2. Transcription and diarization: argmax-oss-swift

Chosen stack: `https://github.com/argmaxinc/argmax-oss-swift` — MIT licensed, products `WhisperKit`, `SpeakerKit`, `TTSKit` (only the first two are needed; do not link TTSKit).

- **Latest tag `v1.1.0`** — verified with `git ls-remote --tags`. The README on the web still shows `from: "0.9.0"`; trust the tag list, and pin explicitly.
- Requirements: macOS 14.0+ (WhisperKit), macOS 13.0+ (SpeakerKit), Swift 5.9+. Well within target.
- **WhisperKit** — CoreML, runs on the Neural Engine. `WhisperKit(WhisperKitConfig(model: "..."))`, then `transcribe(audioPath:)`. Models come from Hugging Face `argmaxinc/whisperkit-coreml`, downloaded on first use and cached locally.
- Known model variants: `tiny`, `tiny.en`, `base`, `base.en`, `small`, `small.en`, `large-v3-v20240930_626MB` (recommended general), `large-v3-v20240930_turbo` (fastest large on macOS). **UNVERIFIED**: exact on-disk sizes and the full variant list — enumerate at build time rather than hardcoding a stale list.
- **SpeakerKit** — pyannote v4 (community-1) via CoreML, models from `argmaxinc/speakerkit-coreml`, loaded lazily on first `diarize()`. API: `SpeakerKit()`, `AudioProcessor.loadAudioAsFloatArray(fromPath:)`, `diarize(audioArray:options:)` with `PyannoteDiarizationOptions(numberOfSpeakers:clusterDistanceThreshold:useExclusiveReconciliation:)`.
- No API key or Pro licence gate on the OSS products. (Argmax sells a separate Pro SDK; it is not required and must not be depended on.)

Rejected: **whisper.cpp** — C API needing a Swift wrapper, no bundled diarization, and weaker ANE utilisation. Rejected: **pyannote via Python** — would drag a Python runtime into a menu bar app.

Model downloads are the one legitimate network activity, and only until the chosen model is cached. This does not violate the local-only promise but must be stated plainly in the UI.

## 3. System audio capture: CoreAudio process taps

macOS 14.2+/14.4+ API. Chosen over ScreenCaptureKit because SCK demands Screen Recording permission and shows the screen-capture indicator for what is an audio-only job.

Sequence (each step's failure is distinguishable — instrument all of them):

1. `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`; set `uuid`, `muteBehavior = .unmuted`, `isPrivate = true`, `name`.
2. `AudioHardwareCreateProcessTap(desc, &tapID)` — **this call is what fires the TCC prompt.**
3. Read default output device: `kAudioHardwarePropertyDefaultOutputDevice`, then its `kAudioDevicePropertyDeviceUID`.
4. `AudioHardwareCreateAggregateDevice` with: `kAudioAggregateDeviceMainSubDeviceKey` = real output UID, `kAudioAggregateDeviceSubDeviceListKey` = `[[kAudioSubDeviceUIDKey: outputUID]]`, `kAudioAggregateDeviceTapListKey` = `[[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]]`, `kAudioAggregateDeviceIsPrivateKey` = true, `kAudioAggregateDeviceIsStackedKey` = false, `kAudioAggregateDeviceTapAutoStartKey` = **true**.
5. `AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { ... }`
6. `AudioDeviceStart(aggregateID, ioProcID)`

Teardown, in this order: `AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` → `AudioHardwareDestroyProcessTap`. Leaked aggregate devices are visible system-wide and are a real bug class; destroy them even on crash paths where possible.

### Traps that produce silent failure (all cost hours if rediscovered)

- **`isExclusive` is a direction flag, not a lock.** `init(stereoGlobalTapButExcludeProcesses:)` sets `exclusive = true`, meaning "tap everything EXCEPT these PIDs". Flipping it to `false` inverts the meaning to "tap ONLY these PIDs" and silently captures nothing. Never touch it after init.
- **`AVAudioEngine` cannot be pointed at the aggregate device.** Setting `kAudioOutputUnitProperty_CurrentDevice` returns `noErr` and then keeps reading the system default input. The IOProc must be installed on the aggregate device directly.
- **`kAudioAggregateDeviceTapAutoStartKey: true` is mandatory.** Without it, callbacks fire and every sample is zero.
- **A tap as main sub-device with an empty sub-device list yields zero samples**, also without error.
- **The IOProc dispatch queue must not be `nil` on macOS 26+** — it silently fails. Use `DispatchQueue(label:, qos: .userInteractive)`.
- **Do not assume the format.** Taps are typically 48 kHz Float32 stereo; query `kAudioStreamPropertyVirtualFormat` after device creation, and handle interleaved, non-interleaved and mono buffer layouts in the callback.
- Zero the ring buffer on stop, or stale samples bleed into the next recording.

### Permission and signing (the sharpest constraint)

- `NSAudioCaptureUsageDescription` in Info.plist is required for the prompt to appear; `NSMicrophoneUsageDescription` for the mic.
- **There is no public API to query or request system-audio-capture permission.** State must be inferred from whether tap creation succeeds and produces non-zero samples. Design the UI around inference, not around a permission API that does not exist.
- Mic permission *does* have an API: `AVCaptureDevice.requestAccess(for: .audio)`. There is no `AVAudioSession` on macOS — do not port iOS session code.
- **TCC consent is keyed to the code signature.** Truly unsigned builds never get the prompt at all. With no Developer ID on this machine the app must be **ad-hoc signed** (`codesign --force --sign -`), and because ad-hoc identity is the cdhash, *consent is invalidated on every rebuild*. Practical consequence: install to a stable location, expect to re-grant after rebuilds, and give the user a one-liner: `tccutil reset SystemAudioCaptureRequests <bundle-id>`.
- Deployment target must be **≥ macOS 14.4** (earlier versions land in a different TCC category with different prompt copy). Targeting 15.0+ is safe and simpler.
- **App Sandbox must be off** for v1 — CATap under sandbox is fragile. Keep Hardened Runtime on. Not App Store distributable; that is already out of scope.

## 4. Meeting detection

Enumerate audio processes via `kAudioHardwarePropertyProcessObjectList`, reading `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`, and `kAudioProcessPropertyIsRunningInput`. A process holding the *input* device during a call is the signal — output alone is just media playback.

- **Listeners on `kAudioProcessPropertyIsRunningInput` are documented as unreliable** (do not always fire). Therefore: register listeners *and* poll on a timer (~2s). Poll is the source of truth; listeners only shorten latency.
- `kAudioProcessPropertyIsRunningOutput` reflects IO registration rather than actual sample contribution — not a usable activity signal.
- `kAudioDevicePropertyDeviceIsRunningSomewhere` works for built-in and wired mics but **is always reported inactive for Bluetooth mics** — unusable as the primary signal given AirPods are the common case.
- **Slack and Teams are Electron apps and route call audio through helper processes** (verified: `Slack Helper`, `Microsoft Teams` helpers running now). The bundle ID seen on the audio process object may be the helper's. **Match by bundle-ID prefix** (`com.tinyspeck.slackmacgap*`, `com.microsoft.teams2*`), and fall back to mapping PID → responsible/parent application.
- Slack huddles cannot be distinguished from other Slack audio use via CoreAudio alone. Accept the false-positive rate; the prompt is cheap to decline, and per-app suppression exists for exactly this.
- Debounce: require the input-active state to hold for a few seconds before prompting, so device probes and notification sounds do not trigger it.

## 5. Metadata generation

Two backends behind one interface. This is not gold-plating — Apple Intelligence is off on the target machine, so an FM-only design ships an app that cannot title a meeting on the very Mac it was built for.

- **Preferred: Apple FoundationModels.** `import FoundationModels`, `LanguageModelSession`, ~3B on-device model, macOS 26. Use `@Generable` guided generation for a typed `{title, tags[], summary, decisions[], actions[]}` result rather than parsing free text. **Must** check `SystemLanguageModel.default.availability` and degrade — expect `.unavailable(.appleIntelligenceNotEnabled)` on this host today. **UNVERIFIED**: exact context-window limit; long transcripts will need chunk-then-reduce.
- **Always-available: deterministic extractor.** Keyphrase extraction for tags (stopword-filtered n-gram scoring), extractive summary (sentence scoring over keyphrase density and position), cue-phrase matching for decisions and action items ("we decided", "I'll take", "action item", "let's", "by <date>"), title from the highest-scoring early keyphrase. No models, no latency, no dependencies, fully deterministic — and therefore also the right thing to run in tests.

The Markdown writer must record which backend produced the metadata, so output is never ambiguous about its own provenance.

## 6. Open questions carried forward

1. Real transcription throughput per model on M5 — measure, do not estimate; the model picker's speed guidance should come from measurement.
2. SpeakerKit accuracy on real huddle audio with 3+ remote speakers, and whether `numberOfSpeakers` should be left unset (auto) or estimated.
3. Whether diarizing the remote stream only is materially better than diarizing the mix — the design assumes yes; worth a comparison once real audio exists.
4. Whether ad-hoc-signed TCC consent survives rebuilds in practice more often than theory suggests. Determines whether a stable install location plus a re-grant note is sufficient UX.
5. FoundationModels context limit, hence the chunking threshold for long meetings.
6. Behaviour when the default output device changes mid-recording (AirPods connecting) — the aggregate device references a specific output UID and probably needs rebuilding on device change.
