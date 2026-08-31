# Reviewer: version & reality verification

Lens (from `finalize_reviewers`): *verify every committed decision was web-researched or reality-checked rather than asserted from training data.*

**Verdict: PASS with three named gaps.** Every load-bearing technology in the Stack table was verified by executing something on the target machine. The gaps below are stated rather than papered over, and none blocks the build.

## Verified by running code on the target machine

| Claim | How verified | Result |
|---|---|---|
| macOS 26.6.2 / Darwin 25.6.0 / arm64 | `sw_vers`, `uname -a` | confirmed |
| Swift 6.3.3, Xcode 26.6 (17F113), SDK 26.5 | `swift --version`, `xcodebuild -version/-showsdks` | confirmed |
| argmax-oss-swift latest tag is **1.1.0** | `git ls-remote --tags` | confirmed — corrected the docs page, which still shows `from: "0.9.0"` |
| It exposes `WhisperKit` + `SpeakerKit` as products, macOS 13+ | `curl` of `Package.swift` **at the v1.1.0 tag** | confirmed, including that `SpeakerKit` depends on `WhisperKit` |
| It declares `swiftLanguageVersions: [.v5]` | same manifest read | confirmed → drove AD-15 |
| Both products compile against an SPM executable | full `swift build -c release` | confirmed, 45 s, zero source changes |
| Real Transcription Model identifiers | ran `WhisperKit.fetchAvailableModels()` | **corrected a wrong published list** — real names are `openai_whisper-` prefixed; 22 variants returned |
| The chosen default model exists | present in that returned list | confirmed |
| `recommendedModels()` needs no network | ran it | confirmed → lets the picker work offline |
| CoreAudio process tap captures system audio | ran the tap spike | confirmed: 117,600 frames, peak 0.359, clean teardown, works over Bluetooth output |
| Tap audio format | read `kAudioTapPropertyFormat` | 48 kHz / 2 ch / Float32 / flags 9 |
| `AudioDeviceCreateIOProcIDWithBlock` deadlocks | reproduced 3× on main and background threads | **contradicts the published guidance** → AD-1 |
| Audio process enumeration + bundle IDs | ran the detection spike | 44 objects, IDs and PIDs readable |
| Teams has **no** bare `com.microsoft.teams2` audio object | same spike output | confirmed → AD-5's prefix rule is load-bearing, not stylistic |
| `IsRunningOutput` reports real activity | Spotify showed `YES` while playing | confirmed |
| SPM + `MenuBarExtra` + Swift 5 mode builds | built and launched | confirmed |
| Hand-assembled bundle ad-hoc signs and runs | `codesign` + `codesign -dv` + launch | confirmed adhoc+runtime, identifier set |
| System-audio capture needs no TCC prompt here | tap spike produced audio with no dialog | confirmed on this host — see gap 3 |
| FoundationModels.framework is present | filesystem check | present |
| Apple Intelligence is opted out | `defaults read com.apple.CloudSubscriptionFeatures.optIn` | `opted_out_buddy = 1` |

## Gaps — asserted, not yet verified

1. **`SpeakerKit.diarize()` has never been executed.** It compiles and links, and its API shape came from documentation. The pyannote v4 / `argmaxinc/speakerkit-coreml` model-repo details are also documentation-sourced. AD-11 fixes where diarization lives regardless, and AD-17 requires a degradation path, so a surprise here costs a story rather than the architecture — but the first diarization run is the next real risk to retire.
2. **`FoundationModels` availability and the `@Generable` guided-generation shape are unverified at run time.** Expected to report unavailable on this host. AD-12 makes the Heuristic Backend the floor precisely so this cannot block anything, and it is logged as an assumption rather than a fact.
3. **The no-TCC-prompt result may not generalise.** System-audio capture worked with no consent dialog on *this* host, which may reflect prior consent state, an ad-hoc-signing path, or a macOS 26 behaviour change. The inference-based permission UI (FR-42, EXPERIENCE.md § Permission Choreography) is retained deliberately — the spine must not assume the easy case.
4. **Minor, low risk:** `NavigationSplitView` was not spiked. Stock API, no platform quirk suspected.
