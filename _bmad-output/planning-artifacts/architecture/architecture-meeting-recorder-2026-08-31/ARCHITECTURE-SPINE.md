---
name: 'Minutes'
type: architecture-spine
purpose: build-substrate
altitude: feature
paradigm: 'layered ports-and-adapters with a staged, resumable pipeline'
scope: 'The whole Minutes application: menu bar control, dual-stream capture, detection, transcription, diarization, metadata, Markdown output, library, settings.'
status: final
created: '2026-08-31'
updated: 2026-09-03
binds: [FR-1..FR-83, NFR-1..NFR-8]
sources:
  - ../../prds/prd-meeting-recorder-2026-08-31/prd.md
  - ../../prds/prd-meeting-recorder-2026-08-31/addendum.md
  - ../../ux-designs/ux-meeting-recorder-2026-08-31/DESIGN.md
  - ../../ux-designs/ux-meeting-recorder-2026-08-31/EXPERIENCE.md
  - ../../briefs/brief-meeting-recorder-2026-08-31/addendum.md
  - ../../spikes/spike-local-llm-2026-08-31.md
  - ../../spikes/spike-mic-isolation-2026-09-01.md
  - ../../spikes/calibration-speaker-threshold-2026-09-01.md
  - ../../spikes/investigation-note-linkage-2026-09-03.md
  - ../../RELEASE-PLAN.md
companions: []
---

# Architecture Spine — Minutes

Four spikes were run before this spine was written; each committed decision below that touches an OS or ML boundary was verified by running code on the target machine, not asserted. Findings are in `.memlog.md`.

AD-33 … AD-38 (2026-09-02) come from a different kind of investigation: the first audit of the code against a machine other than the one it was written on, plus current Apple and Homebrew documentation on what it takes to install an app somewhere else. Two of those decisions are forced by mechanism rather than chosen — see AD-34's recorded note.

Two further measurement runs (2026-09-01) inform AD-11 and AD-28 … AD-32: a spike on isolating the user's voice from a conversation happening beside them, and a calibration of the speaker-matching threshold against the centroids of five real Meetings. The threshold is the first number in this spine that was *measured* rather than chosen.

## Design Paradigm

**Layered ports-and-adapters, with a staged resumable pipeline for post-processing.**

| Layer | Namespace | May import |
|---|---|---|
| **Core** — domain types and pure logic | `Sources/Minutes/Core` | `Foundation` only |
| **Services** — orchestration, state, policy | `Sources/Minutes/Services` | Core, port protocols |
| **Adapters** — one per OS/ML boundary | `Sources/Minutes/Adapters/*` | Core, its own framework |
| **UI** — SwiftUI views | `Sources/Minutes/UI` | Core, Services |
| **App** — entry point, scenes | `Sources/Minutes/App` | all |

Every OS and ML dependency (CoreAudio, WhisperKit, SpeakerKit, FoundationModels, UserNotifications, FileManager) sits behind a port protocol defined in Services and implemented in exactly one adapter. This is what makes the Heuristic Backend testable without Apple Intelligence, and the pipeline testable without audio hardware.

```mermaid
graph TD
    App[App] --> UI[UI]
    App --> SVC[Services]
    UI --> SVC
    UI --> CORE[Core]
    SVC --> CORE
    SVC -. port protocols .-> ADP[Adapters]
    ADP --> CORE
    ADP --> FW[OS / ML frameworks]
```

Arrows are the only permitted dependency directions. Notably: **no adapter may import another adapter**, and **Core imports nothing but Foundation**.

## Invariants & Rules

### AD-1 — CoreAudio tap IO uses a C-function-pointer IOProc

- **Binds:** FR-6, FR-8, FR-47, the System Stream adapter
- **Prevents:** an implementer reaching for the ergonomic block-based API and shipping a process that hangs on first record with no error and no crash log
- **Rule:** Use `AudioDeviceCreateIOProcID` with a C function pointer and an `Unmanaged<Self>` refCon for context. **Never** `AudioDeviceCreateIOProcIDWithBlock`. *(Verified: the block variant deadlocks indefinitely on a tap-backed aggregate device on macOS 26.6, on both main and background threads. The C variant captured 117,600 frames at peak 0.359 on the first attempt.)*

### AD-2 — Fixed CoreAudio construction and teardown order, on every path

- **Binds:** FR-6, FR-8, FR-9, NFR-5
- **Prevents:** leaked aggregate devices and taps that persist system-wide after a crash, and zero-sample captures from a malformed aggregate
- **Rule:** Construct: tap → default-output UID → private aggregate (real output as `kAudioAggregateDeviceMainSubDeviceKey`, tap in `kAudioAggregateDeviceTapListKey`, `kAudioAggregateDeviceTapAutoStartKey: true`) → IOProc → start. Tear down in exactly the reverse: `AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` → `AudioHardwareDestroyProcessTap`. Teardown runs in a `defer`/error path too, never only on the happy path. `CATapDescription.isExclusive` is never mutated after `init(stereoGlobalTapButExcludeProcesses:)`.

### AD-3 — Query the tap's audio format; never assume it

- **Binds:** FR-6, FR-47
- **Prevents:** two adapters disagreeing on sample rate or channel layout and silently producing garbage or half-length audio
- **Rule:** Read `kAudioTapPropertyFormat` after tap creation and drive all downstream buffer handling from it. Handle interleaved, non-interleaved and mono layouts by inspecting the `AudioBufferList`, via `UnsafeMutableAudioBufferListPointer` — never by indexing past `mBuffers.0`. *(Measured on this host: 48 kHz, 2 ch, Float32, flags 9 = IsFloat|IsPacked.)*

*Amended 2026-09-03, after the failure named in this AD's own Prevents clause happened anyway.*

**Querying the format is necessary and is not sufficient.** This rule was followed exactly — the format is read from the tap, never assumed — and seven of sixteen recordings still came out at two or three times speed, because a rate read **once, at tap creation** is a claim about that instant and not about what the device goes on to deliver. Selecting a Bluetooth headset as the *input* device moves the shared clock, and the tap then delivers at a rate the app already believes it knows.

The rule therefore gains a second half: a declared rate is a starting hypothesis, and it must be **checked against the session clock while recording** (AD-44). "Never assume it" now means never assume it *stays true* either.

### AD-4 — One session clock; all times are offsets from it

- **Binds:** FR-6, FR-23, FR-29, FR-33
- **Prevents:** the two Streams being timestamped from different clocks, which makes the merged Transcript subtly and unfixably out of order
- **Rule:** A Session captures one monotonic start reference at Capture start. Every Utterance, segment and diarization boundary is a `TimeInterval` offset in seconds from that reference. No wall-clock timestamps below the Meeting level, and no per-Stream clocks.

### AD-5 — Detection matches Watched Apps by bundle-ID prefix, and polls

- **Binds:** FR-11, FR-12, FR-15, FR-43
- **Prevents:** shipping detection that never fires for Teams, and detection that misses events because a listener did not
- **Rule:** Enumerate `kAudioHardwarePropertyProcessObjectList` and match a Watched App by **bundle-ID prefix**. A timer poll (≈2 s) is the source of truth; property listeners may only shorten latency and may never be the sole signal. *(Verified: Teams exposes no bare `com.microsoft.teams2` audio object — only `.modulehost`, `.helper`, `.notificationcenter`. Exact matching detects Teams never.)*

### AD-6 — Detection reads metadata only, never audio

- **Binds:** FR-10, NFR-1, PRD §9.1
- **Prevents:** the product's central privacy claim being quietly broken by a future convenience
- **Rule:** While Idle, the app holds no audio device open and reads no audio data. Detection may read only process/device *properties*. Any change that reads audio content outside a Session is a breach of the product premise, not a feature.

### AD-7 — One owner of application state; mutation only through intents

- **Binds:** all UI, FR-3, FR-4, FR-13, FR-24
- **Prevents:** the menu bar, the window and the pipeline each holding their own idea of whether a Session is running
- **Rule:** Exactly one `@MainActor @Observable AppState` holds observable app state. Views never mutate it directly; they call intent methods on `SessionCoordinator`, which is the sole writer. Adapters never touch `AppState` — they return values or publish events upward.

### AD-8 — The Session pipeline is staged, and each stage persists before the next begins

- **Binds:** FR-9, FR-16, FR-19, FR-20, FR-22, FR-26, FR-31, FR-39, NFR-5
- **Prevents:** a late failure discarding expensive upstream work, and two components disagreeing on how far a Meeting got
- **Rule:** Post-Capture processing is an ordered pipeline: `captured → transcribed → diarized → attributed → metadata → written`. Each stage writes its output into the Meeting's own directory and advances a single persisted `stage` field before the next stage runs. A stage failure leaves the Meeting at the last completed stage with a recorded reason, and is resumable from there. No stage may be skipped or reordered.

### AD-9 — The Meeting directory is the source of truth; the Note is a projection

- **Binds:** FR-24, FR-31, FR-35, FR-36, FR-40, NFR-8
- **Prevents:** two owners of Meeting data — the classic failure where editing the Markdown and editing in-app diverge
- **Rule:** Each Meeting owns one directory under Application Support, named by a sortable ID. It holds the audio, a `meeting.json` record, and stage outputs. The Note in the Notes Folder is **generated from** that record and may be regenerated at any time. The app never parses a Note back into state.

*Amended 2026-09-03, after a renamed Note cost a Meeting.* Two clarifications, neither of which relaxes the rule:

1. **Identity is not content.** Reading a Note's frontmatter to learn *which Meeting it is* is permitted and is the mechanism AD-39 depends on. Reading anything else out of a Note — a title, a summary, a transcript line, a speaker name — remains forbidden. The dividing line is mechanical: the identity reader returns a Meeting ID and a start time, and its return type makes a body field unrepresentable.
2. **"Those edits will be overwritten" is no longer the whole consequence.** It was the consequence while the app could not tell its own output from a human's. AD-41 gives it that ability, so the rule becomes: a projection is regenerated freely over the app's own bytes, and never over bytes the app did not write without the user saying so. The original clause's obligation — *and this must be stated in the UI* — stood unmet for six increments; it is now FR-81's job and not a comment's.

### AD-10 — Atomic writes for anything the user can lose

- **Binds:** FR-31, FR-34, FR-35, NFR-5, NFR-8
- **Prevents:** a truncated Note or a corrupt `meeting.json` after a crash or a full disk
- **Rule:** Write to a temporary file in the destination directory, `fsync`, then atomically replace. Applies to Notes, `meeting.json`, and Speaker Profiles. Never write in place.

### AD-11 — Where a voice was is structural; who it is may be inferred

*Amended 2026-08-31 after a user correction: "My microphone is not always me. I might have the mic but be in a meeting room with others." The original rule assigned every Mic Stream Utterance to the Local Speaker without inference, which in a conference room attributes colleagues' words to the user — strictly worse than an anonymous label.*

*Amended again 2026-09-01 (increment 4). The 2026-08-31 rule was right and incomplete: refusing to claim an identity is honest, and it is still not an answer. Identity now has a measured resolution path. **Nothing about place changes**, and the amendment is deliberately narrow — it adds one way for a voice to become the Local Speaker and removes none of the guarantees that hold when it does not fire.*

- **Binds:** FR-21, FR-22, FR-23, FR-25, FR-63
- **Prevents:** a future refactor that diarizes a mixed stream and loses the room/far-end distinction; the original rule's failure mode of asserting an identity the audio does not support; and — after the amendment — the opposite failure of treating an enrolment *measurement* as though it carried the same certainty as the structural fact
- **Rule:** The **place** of a voice is never inferred: a Mic Stream Utterance is always an in-room voice and a System Stream Utterance is always a remote voice, and neither may ever be relabelled across that boundary. **Identity** is separate. Diarization runs on **both** streams.
  - One voice on the Mic Stream **is** the Local Speaker. Structural, and cannot be wrong.
  - Several voices on the Mic Stream, with an Enrolled Voice matching one of them within AD-31's threshold and unambiguously: **that** voice is the Local Speaker. This is a measurement, not a structural fact, and AD-30 governs how it is made and how it is recorded.
  - Several voices on the Mic Stream with no Enrolled Voice, or no unambiguous match: each becomes an anonymous in-room label and **no voice may be claimed as the Local Speaker.** Unchanged.
  - Mic Stream speech no diarized span covers, when several voices share the microphone, is unidentified in-room speech. Never the Local Speaker by default. *(This was a real defect: the default fell through to the Local Speaker and printed 14 utterances of a neighbouring conversation as the user's own words.)*

  Every Utterance carries its origin stream so the distinction survives into the data and the UI (`components.speaker-chip` in DESIGN.md renders the three places distinctly). Enrolment changes **which** in-room voice is the Local Speaker; it never changes the structural rules, and the attribution function's other behaviour is byte-for-byte the same with and without a fingerprint present.

### AD-12 — Metadata is a port with several implementations; the deterministic one is the floor

- **Binds:** FR-26, FR-27, FR-28, FR-29, FR-30, FR-55, FR-56, FR-61
- **Prevents:** an LLM-only design that cannot title a meeting on the machine it was built for, and untestable metadata
- **Rule:** `MetadataBackend` is a protocol. `HeuristicBackend` is pure, deterministic, dependency-free, and always available — it is the floor and the unit-test target. Every other implementation is selected only after a run-time availability check, must produce a typed structure rather than parsed free text, and every Meeting records which backend ran.
- **Amended (increment 3):** the port now has four implementations, not two — `Heuristic`, `FoundationModels`, `LocalLLM`, `Remote`. Two consequences follow, and they are the whole reason the amendment is worth writing down rather than treating as more of the same:
  1. **The floor is no longer a summariser.** `HeuristicBackend` produces a title and tags and *not* a summary (FR-55), so the port splits into `MetadataBackend` (all four) and `Summarizing` (the other three). "Is a summary possible" becomes a type-level question rather than a runtime guess.
  2. **Availability is no longer a Bool.** With one optional backend, `isAvailable() -> Bool` was sufficient. With three it must carry a reason and a remedy, because FR-58 requires an unavailable backend to explain itself. See AD-22.

### AD-13 — Model identifiers are never hardcoded

- **Binds:** FR-17, FR-18, FR-56
- **Prevents:** a stale model list that silently offers identifiers the library no longer serves
- **Rule:** The model catalogue is obtained from the library at run time (`recommendedModels()` locally, `fetchAvailableModels()` when online). Only the *default* identifier is a constant. *(Verified: real identifiers are `openai_whisper-`-prefixed; the published docs list bare names and is wrong.)*
- **Extended (increment 3):** the same rule binds the summarisation model list. The spike found `Qwen3.5`, `Qwen3.6` and `Qwen3.8` conversions all live on `mlx-community` — a list written from memory would have been wrong on the day it was written. `LLMModelFactory.shared.modelRegistry` is the run-time source, with curation applied on top of it rather than in place of it.

### AD-14 — Serial ML execution

- **Binds:** FR-16, FR-20, FR-22, NFR-4
- **Prevents:** two CoreML models loading at once and putting a 24 GB machine under memory pressure mid-meeting
- **Rule:** All transcription and diarization runs on a single serial executor. A Session may be recorded while another Meeting processes, but two model inferences never run concurrently. Models are loaded lazily and released when the queue drains.

### AD-15 — Swift 5 language mode for the app target `[ADOPTED]`

- **Binds:** the whole build
- **Prevents:** a same-day build drowning in Sendable/isolation diagnostics originating from a dependency that is not Swift-6-ready
- **Rule:** `swiftSettings: [.swiftLanguageMode(.v5)]` on the app target. *(argmax-oss-swift declares `swiftLanguageVersions: [.v5]`.)* Concurrency discipline is still enforced by hand: `@MainActor` for UI and `AppState`, an actor for the capture engine, a serial executor for ML.

### AD-16 — The build produces an ad-hoc signed .app bundle from SPM, with no Xcode project

- **Binds:** the whole build, FR-1, FR-41, FR-42, PRD §12
- **Prevents:** an unsigned or bundle-less binary, which cannot receive TCC consent, cannot post notifications, and cannot own a menu bar item
- **Rule:** `swift build` produces the executable; a checked-in script assembles `Minutes.app` with the Info.plist and ad-hoc signs it with `--options runtime` and the entitlements file. Signing is part of the build, never a manual afterthought. Required Info.plist keys: `LSUIElement`, `CFBundleIdentifier`, `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`. App Sandbox off, Hardened Runtime on. *(Verified end to end: bundle signs as adhoc+runtime and captured system audio successfully.)*

### AD-17 — Failure is surfaced and never silently swallowed

- **Binds:** NFR-5, FR-7, FR-19, FR-22, FR-27, FR-47
- **Prevents:** the app's worst possible behaviour — appearing to record and producing nothing
- **Rule:** Every adapter returns a typed error; no `try?` that discards a user-visible failure. Each of the three degradations (no System Stream, no diarization, no LLM backend) has an explicit representation on the Meeting record and a defined UI treatment. A degradation is recorded even when it is the expected path.

### AD-18 — The Note filename is derived once and stored on the Meeting record

- **Binds:** FR-31, FR-35, AD-9
- **Prevents:** two components each deriving a filename from the title and producing two Notes for one Meeting — the concrete failure AD-9 leaves open, because AD-9 fixes ownership of *state* but not of the *filename*
- **Rule:** `NoteWriter` is the only component that computes a Note filename. It derives it once at first write and persists it on the Meeting record. On a title change the stored filename is authoritative: `NoteWriter` renames the existing file and updates the record in the same operation. No other component may infer a Note path from a title.

*Amended 2026-09-03.* The authority above holds only while the name on disk is still the name the app wrote. The moment they differ the file is **user-named**, and AD-40 inverts the authority: the app follows the file and no component renames it. The derived name never disappears — it stays on the record as the thing the divergence is measured against.

### AD-19 — Utterances reference a stable Speaker Label ID, never a display name

- **Binds:** FR-21, FR-23, FR-24, FR-25
- **Prevents:** rename becoming a rewrite of every Utterance, and label-merge being ambiguous — two compliant implementations could store raw name strings and make FR-24's merge behaviour undefined
- **Rule:** An `Utterance` carries a `SpeakerLabelID` (stable, assigned at attribution). Display names live in one per-Meeting `[SpeakerLabelID: String]` map on the Meeting record. Renaming edits the map only. Renaming two IDs to the same string is precisely what FR-24's merge means, and requires no Utterance mutation.

### AD-20 — Only the Pipeline advances `stage`; stages return values

- **Binds:** AD-8, FR-19, FR-20, FR-39
- **Prevents:** a stage advancing past itself, two stages double-advancing, or a partial advance on failure
- **Rule:** A pipeline stage is a function from inputs to an output value. It never writes the Meeting record and never touches `stage`. The `Pipeline` persists a stage's output and advances `stage` only after that stage returns successfully. Failure leaves `stage` untouched and records a reason alongside it.

### AD-21 — `MeetingStore` is the sole writer of the Meeting record

- **Binds:** AD-8, AD-9, AD-10, AD-17
- **Prevents:** read-modify-write clobbering — Capture writing `systemStreamCaptured`, Diarize writing `diarizationFailed` and Metadata writing `backend` can each silently drop the others' fields if adapters persist the whole record
- **Rule:** Adapters never write `meeting.json`. They return typed results. `MeetingStore` performs all reads and writes, applies field-level updates, and is the only holder of the atomic-write path (AD-10). One serial access point per Meeting.

### AD-22 — Capability is a value with a reason and a remedy, never a Bool

- **Binds:** FR-56, FR-57, FR-58
- **Prevents:** the failure that produced this increment — the app knowing exactly why it could not summarise and having nowhere to put that knowledge
- **Rule:** A backend reports `Capability`, not `Bool`: `.ready`, `.needsDownload(bytes:)`, `.needsKey`, or `.blocked(reason:remedy:)`. `remedy` is structured enough to render as a command where the remedy *is* a command. Every UI state in EXPERIENCE.md's readiness table maps to exactly one case, and a `.blocked` backend is never selectable. Capability is computed on demand, never cached across a pane appearance, so a prerequisite fixed outside the app is picked up without a relaunch.

### AD-23 — Backend precedence is a pure function, evaluated in one place

- **Binds:** FR-52, FR-57
- **Prevents:** two settings that can silently disagree, and an ordering that lives only in whichever branch was written first
- **Rule:** One function maps `(user selection, capabilities) → (backend to run, why)`. It is pure, unit-tested against every combination, and is the only code that decides. The order is: explicit user selection if `.ready`; else the first `.ready` backend in a fixed preference order; else no summariser. The UI displays *what this function returns*, which is why the pane can state which backend will run for the next Meeting rather than only which is selected.

### AD-24 — Egress is a single chokepoint, and audio never reaches it

- **Binds:** FR-59, NFR-1, NFR-6
- **Prevents:** the amended NFR-1 decaying into "some code somewhere makes requests", and any future path that transmits more than was agreed
- **Rule:** Exactly one type in the app may open a network connection for summarisation. It accepts Transcript text and nothing else — its input type cannot express audio, a file URL, or a Speaker Profile, so "audio never leaves" is enforced by the signature rather than by review. It refuses to send without both a stored key and a consent token for that specific Meeting. It is the only place the key is read, and the key is read from the Keychain at the moment of use and never held. NFR-6 stays verifiable because there is exactly one place to look.

### AD-25 — Model storage and download are one mechanism for both kinds of model

- **Binds:** FR-18, FR-56, FR-60
- **Prevents:** a second downloader with its own directory layout, its own progress reporting and its own partial-file bug
- **Rule:** `ModelStorage` owns the download root for transcription *and* summarisation models, in sibling directories under one base. The spike verified `HubApi(downloadBase:)` honours an explicit root, so this is a configuration choice rather than a fight with the library. A failed or cancelled download leaves no partial model that could later load as valid — the rule already in force for transcription models, restated because the failure mode is identical and the code is new.

### AD-26 — Summarisation memory is bounded by unloading transcription first

- **Binds:** NFR-4, FR-61
- **Prevents:** a 24 GB machine under memory pressure holding a Whisper model and a 6 GB language model at once
- **Rule:** AD-14's serial ML execution extends to summarisation: the transcription model is unloaded before a summarisation model loads, and the two are never resident together. Because summarisation runs after transcription in AD-8's stage order this is achievable, but it is an explicit sequencing requirement and not a happy accident. A long Transcript's KV cache growth is bounded by the same chunk-and-combine contract FR-27 already defines, applied regardless of which backend is running.

### AD-27 — The Metal toolchain is a detected prerequisite, not an assumption `[ADOPTED]`

- **Binds:** FR-58
- **Prevents:** offering a multi-gigabyte download on a machine that cannot execute a single token of the result
- **Rule:** MLX requires a compiled `metallib`, which `mlx-swift` builds at build time from `mlx-generated` sources — it ships no prebuilt one. The `LocalLLM` backend therefore reports `.blocked` unless the metallib is present, checked before any download is offered. Two consequences bind the build as well as the app: the build script must copy SPM resource bundles into `Minutes.app/Contents/Resources/`, which AD-16's current script does not do; and the developer machine needs `xcodebuild -downloadComponent MetalToolchain`, which is *currently uninstalled* here. Marked `[ADOPTED]` because it is a measured property of the toolchain, not a choice.

### AD-28 — Voice identity is a port over a fixed-length embedding, and the mechanism is arithmetic in Core

- **Binds:** FR-62, FR-63, FR-65, AD-11
- **Prevents:** the identification path acquiring a platform dependency — the one place in the product where the user asked explicitly for the design to stay portable. It also prevents the cheapest available shortcut: the mic-isolation spike found Apple's Voice Isolation is free, already in macOS, and aggressive at removing other voices, and rejected it *for this reason and no other*.
- **Rule:** `VoiceEmbedding` is a port protocol in Services — `embed(url:) async throws -> VoiceFingerprint`, plus an identifier naming the producer. The **comparison** is Foundation-only code in Core, operating on `[Float]` and nothing else; no framework type crosses into it. An adapter may be as Apple-specific as it likes — `SpeakerKitVoiceEmbedder` is, and uses `SpeakerKit`'s centroid embeddings — but neither the port's signature nor the matching arithmetic may name a single Apple type. The test is mechanical: the identification path must compile against `Foundation` alone. An Apple-only technique is permitted as an *optimisation behind the port* and never as the thing the feature depends on.

### AD-29 — A fingerprint is comparable only to one from the same producer, at the same dimension

- **Binds:** FR-63, FR-64, FR-25, AD-28
- **Prevents:** the worst failure available to this feature — a future embedder swap comparing incompatible vectors and returning a confident number, because a wrong distance is indistinguishable from a right one. There is no error, no crash and no log line; there is only the wrong name on someone's words.
- **Rule:** Every persisted fingerprint carries the producer's identifier and its dimension. A comparison across producers or dimensions yields **no information** — not a large distance, and not a non-match: the function returns nothing and the caller must treat that as "cannot say", never as "far apart". Collapsing those two is how a fingerprint written by one embedder becomes a permanent non-match under the next. *(`cosineDistance` already returns nil on a length mismatch, which does half of this by accident. The identifier makes it deliberate, and the distinction between "no answer" and "no match" is the half that was missing.)*

### AD-30 — The Local Speaker is resolved by structure or by enrolment, and by nothing else

- **Binds:** FR-21, FR-25, FR-63, FR-65, AD-11
- **Prevents:** the user's own name arriving on a voice through FR-25's passive rename-learning path, which *cannot* be correct there — passive learning needs a known-correct label to start from, and several voices on one microphone provide none. Also prevents two components each deciding who the user is.
- **Rule:** `.local` is assigned in exactly two ways and no third exists.
  1. **Structurally** — the Mic Stream held one voice.
  2. **By enrolment** — among the in-room clusters, the nearest to the Enrolled fingerprint is within AD-31's threshold **and** unambiguous: no other cluster is within AD-31's margin of it. Two clusters that close is either a Diarization split of the user's own voice or a genuine ambiguity, and in both cases **nothing is claimed** — which is AD-11's rule, applied to its own new path.

  `SpeakerDirectory.match` — the FR-25 passive path — **excludes the enrolled profile from its candidate set.** It therefore cannot apply the user's name to any voice, and the user's display name keeps its single existing owner. When enrolment does resolve `.local`, the Meeting records that it was enrolment that did so and how close the match was, because a measurement presented like a structural fact is the thing AD-11 exists to prevent.

  **Where it happens, so two implementations cannot differ:** the lookup runs inside the existing *diarize* stage, which is the only stage holding the mic clusters' embeddings, and its result is passed to the attribution function as **data** — one value naming which mic cluster is the local voice, or nothing. Attribution stays a pure function of its arguments (AD-20) and gains no dependency on `SpeakerDirectory`. **No stage is added to AD-8's list**, and adding one would be a violation rather than an implementation choice.

### AD-31 — The match threshold is a calibrated constant with its measurement attached `[ADOPTED]`

- **Binds:** FR-25, FR-63, FR-65
- **Prevents:** the number drifting by opinion between increments, and the appearance of the single setting that would let a user break attribution invisibly — a wrong threshold puts the wrong name on someone's words with nothing to notice
- **Rule:** One constant, in one place, with the measurement and the date written beside it. **0.35**, calibrated 2026-09-01 against 24 centroids from five real Meetings: the same in-room voice measured 0.058–0.248 apart across four independent recordings, different in-room voices in one Meeting 0.596 and above. The ambiguity margin AD-30 requires is **0.10**, which the same measurement makes generous — genuine in-room voices are 2.4× further apart than that. Neither value lives in `Preferences`, in `UserDefaults`, or on any pane. Changing either requires re-running the calibration, whose method and inputs are recorded in `../../spikes/calibration-speaker-threshold-2026-09-01.md` rather than the number being asserted alone. Marked `[ADOPTED]` because it is a measured property of this embedding on this data, not a preference.
- **Recorded limit, not a gap:** for Remote Speakers the two populations touch — same speaker up to 0.248, different speakers from 0.254 — so **no threshold separates them.** 0.35 admits two measured false matches there. That is accepted rather than papered over: FR-25 renders an auto-applied name as inferred and FR-51 makes it correctable, so the cost is one rename. A threshold tight enough to exclude them (0.25) leaves 0.002 of headroom above the observed same-voice maximum, at which point enrolment stops working.

### AD-32 — Enrolment audio is transient; only the fingerprint persists

- **Binds:** FR-62, FR-64, PRD §9.1
- **Prevents:** an enrolment recording accumulating on disk beside the fingerprint. That single failure converts the thing §9.1 permits — a vector nobody can play back — into the thing it does not: a voice recording of a named person, kept for identification.
- **Rule:** One operation records, embeds, and deletes. The sample is written to a temporary directory outside the Meetings root; the fingerprint is derived; the directory is removed on **every** exit path, including failure and cancellation — a `defer`, never a happy-path cleanup. The sample never enters a Meeting directory, never becomes a Meeting record, and never reaches the Notes Folder. Nothing is persisted at all until the fingerprint exists, so a cancelled enrolment is indistinguishable from one that never started. A re-record **replaces** the fingerprint rather than averaging into it, which also means no history of samples exists to leak.

### AD-33 — Release identity comes from the tag, never from a maintained literal

- **Binds:** FR-71, FR-72
- **Prevents:** two different builds claiming the same version, which makes every bug report ambiguous and every "did you update?" unanswerable. Also prevents the routine failure where the literal is bumped in one place and forgotten in the other.
- **Rule:** The version is derived from the git tag at bundle-assembly time and substituted into `Info.plist`. The plist in the repository carries a placeholder, never a version. A build from an untagged commit is marked as a development build rather than inheriting the last release's number. Exactly one component knows how to derive it, and both `--doctor` and the interface read it back from the bundle rather than recomputing it.

### AD-34 — Signing is Developer ID with notarization; Gatekeeper is satisfied, never bypassed

- **Binds:** FR-72, FR-73, PRD §12
- **Prevents:** two distinct failures with one rule. First, consent loss on every update: macOS re-checks an app's designated requirement on each access, and ad-hoc code's requirement is tied to that specific binary (Apple TN3127), so every rebuild revokes microphone and system-audio consent. Second, the instinct to reach for a workaround — stripping the quarantine attribute, a postflight `xattr -cr`, telling a colleague to right-click — each of which defeats the check rather than passing it, and each of which the project would then depend on.
- **Rule:** Release bundles are signed with a Developer ID Application certificate, with hardened runtime and a secure timestamp, then notarized and **stapled to the `.app`** — not to the archive, which cannot carry a ticket — and re-archived afterwards. The bundle identifier `dev.niklas.minutes` is permanent; consent is keyed to it. App Sandbox stays off (notarization does not require it, and AD-16's reasoning is unchanged). No release ever ships depending on a quarantine bypass. A local development build with no certificate present remains ad-hoc signed and says which it is.
- **Recorded, because it removes the alternative:** `--no-quarantine` is gone from Homebrew as of 6.0.20, verified on this machine — absent from `brew install --cask --help` and rejected as an argument. macOS 15 removed the Control-click override. There is no longer a low-friction path for an unnotarized app through Homebrew.
- **Amended 2026-09-02, by the owner's decision.** Homebrew distribution is dropped and the Developer ID is not being bought yet. The shipped install path is a GitHub Release archive fetched by a `curl` installer. **This turned out not to require a bypass at all, and the reason is worth recording because it inverts the finding above:** macOS blocks an unnotarized app only when the file carries a quarantine flag, and quarantine is applied by browsers — and by Homebrew, deliberately — but *not* by `curl`. Measured on this machine: a `curl`-fetched release has no quarantine attribute and launches normally; the identical bundle carrying a browser's quarantine flag is blocked outright. So dropping Homebrew removed the Gatekeeper problem rather than merely the tap requirement. The installer still clears the attribute defensively, for the case where someone downloads the zip in a browser and installs by hand; on the documented path that call is a no-op, and both the installer and the README now say so rather than claiming a bypass that is not happening.
- **What this decision does not fix, and it is the one that recurs:** the signature is still ad-hoc, so **every update revokes microphone and system-audio consent**. FR-73 stays open. That cost, not Gatekeeper, is what a Developer ID would buy — revisit when the app has more than one or two users.

### AD-35 — Distribution is a cask in a first-party tap

- **Binds:** FR-72, FR-76
- **Prevents:** a bespoke installer, a `curl | bash` script, or a hand-written updater — three mechanisms the project would own forever to deliver what one already-installed tool does. Also prevents a second update path competing with the first.
- **Rule:** A Homebrew cask in a tap owned by the project. Homebrew is the *only* update mechanism; the app contains no update check and no in-app updater. The cask declares its OS and architecture requirements so an unsupported Mac is refused rather than served. It declares how to quit the running app, so an upgrade closes a menu-bar process instead of replacing it underneath itself. Its removal list and the documented uninstall are generated from the same source as the footprint inventory (AD-37), so the three cannot disagree. Submission to official `homebrew/cask` is out of scope: it requires notability the project does not have, and gains nothing a first-party tap does not already give.

### AD-36 — Evidence of capture is signal; elapsed time is never evidence

- **Binds:** FR-42, FR-67, FR-47
- **Prevents:** the failure this rule was written from — a check that cannot fail. macOS exposes no API to query system-audio permission, so a measurement is the only evidence available, and a measurement satisfied by silence is indistinguishable from success. The app then asserts a green tick on a machine where capture is quietly broken, which is worse than admitting the unknown.
- **Rule:** Any claim that a stream produced audio is derived from the samples — a peak above a stated floor, or a proportion of non-silent frames. Duration never contributes. The existence of a file never contributes. Every constant in that decision carries the reasoning for its value, and none is a setting. A test asserts that a silent capture of ample duration reports no audio; that test is the rule's enforcement, because this defect is invisible on any machine where capture works.

*Amended 2026-09-03. The rule stands; its scope was too narrow.*

**This AD answers "was anything captured", and that is not the only way a capture can be worthless.** A stream running at three times speed is full of signal, so it satisfies every clause above and is unintelligible. Seven recordings passed this check and transcribed into fluent invented dialogue.

The distinction that keeps "duration never contributes" intact, because it is two different questions:

- **Was audio captured?** Signal answers it. Duration is irrelevant, and a long silent file is the failure this AD exists to catch.
- **Are the samples at the rate they claim?** Only the *ratio* of sample count to elapsed time answers it, and nothing else can. Duration is not evidence of capture here either — it is the denominator of a rate.

So capture evidence has two independent parts, and a stream must satisfy both to be trusted: it produced signal (this AD), and its sample count agrees with the clock (AD-45).

### AD-37 — The user-data directory is the whole footprint

- **Binds:** FR-74, FR-75, FR-76, PRD §9.1
- **Prevents:** the footprint drifting apart from the claim made about it. The product's central promise is that everything stays on this Mac; a promise whose scope nobody can enumerate is not checkable, and today it is already wrong in two places — settings live in a different directory, and the login-item launch agent survives deleting the app.
- **Rule:** One directory holds meetings, remembered voices, models and settings. Settings move into it as a readable document, migrated once from `UserDefaults`, which is then no longer read; `Preferences` remains their sole reader and writer (AD-21's pattern, a different store). Deleting that directory returns the app to a first-run state. Anything the app writes outside it — the launch agent, the user's chosen Notes Folder — is enumerated in one place in the code, and the footprint listing, the uninstall documentation and the cask's removal list are all derived from that enumeration rather than maintained in parallel.

### AD-38 — Biometric-adjacent data leaves the machine only by a separate, explicit choice

- **Binds:** FR-75, PRD §9.1, AD-29, AD-32
- **Prevents:** a Voice Fingerprint leaving on the coat-tails of something the user asked for. Export is the first capability in the product's life that can move data off the Mac at all, and a fingerprint bundled into "export my meetings" would be a §9.1 breach performed by a feature nobody thought of as a transmission.
- **Rule:** A Voice Fingerprint is excluded from any export by default. Including one requires a choice distinct from the choice to export, off by default, accompanied by a plain statement of what the data is and why it is treated unlike everything else. No export or import touches the network. This rule is about the *default* and the *separateness*; whether the override should exist at all is a product decision that remains open, and the code must not settle it by defaulting.


### AD-39 — A Note carries its Meeting's identity, and the link is resolved rather than assumed

- **Binds:** FR-77, FR-78, FR-53, FR-54, AD-9, AD-18, AD-21
- **Prevents:** a filename serving as an identity. A filename is the one property of a file a user is most likely to change, and while it was the only link, a rename in Finder orphaned a Note permanently and the app's own remedy for the break — rewrite — made it unrecoverable. Two independently built components would otherwise each choose their own way to "find the Note", one by path and one by scanning, and disagree about which file a Meeting owns.
- **Rule:** `NoteWriter` stamps the Meeting ID into the Note's frontmatter at every write. Resolving a Note Link goes through one port, `NoteLocating`, which takes a Meeting and a folder and returns a located file or nothing. It reads frontmatter identity only — Meeting ID, falling back to `started_at` for Notes written before the stamp existed — and its return type cannot carry a body field. It is invoked **only when the recorded path does not exist**: a library with no broken link performs no folder read. A single unambiguous match is persisted through `MeetingStore` (AD-21) because "this file is this Meeting's Note" is a durable fact; more than one match is returned as an ambiguity for the user to settle and persists nothing; no match persists nothing, because absence is a display state and must never become a claim in the record. Resolution never creates, renames, moves or deletes a file.

### AD-40 — A user-named Note file outranks the name the app would derive

- **Binds:** FR-80, FR-35, AD-18, AD-39
- **Prevents:** the app overwriting a naming decision the user made deliberately. Without a stored record of what the app itself last wrote, no component can tell a user's rename from a stale filename, so every one of them has to guess — and AD-18's rule makes the confident guess the destructive one.
- **Rule:** The Meeting record carries two names: the file the link points at, and the filename `NoteWriter` last wrote. Equal means the app owns the name and AD-18 applies unchanged. Different means the user owns it: no component renames the file, a title change alters only the Note's contents, and the name shown in the UI is the user's. The comparison is the only test; there is no separate "user renamed this" flag to fall out of sync with the filesystem.

### AD-41 — The app records what it wrote, so it can tell an edit from its own output

- **Binds:** FR-81, FR-83, AD-9, AD-10
- **Prevents:** both halves of a symmetric failure — silently destroying a user's edit, and prompting about every ordinary rewrite because the app cannot recognise its own bytes. A component that only compares timestamps produces the second; one that compares nothing produces the first.
- **Rule:** Every Note write persists a digest of the exact bytes written, on the Meeting record, in the same update that persists the filename. Before overwriting, the file's bytes are digested and compared: equal means the app's own output and the write proceeds silently; different means the write does not happen and a conflict value is returned for the UI to resolve (FR-81). Rendering is never the comparison — the renderer has changed in four increments, so re-rendering an old Note legitimately differs from the file on disk and would report every Note as edited.
- **Migration, and its limit:** a Note written before this rule has no digest. The app adopts the current bytes as the baseline when the file's modification time is not later than the record's last write, and treats it as a possible edit when it is later. That is evidence rather than an assumption, and it is a weaker signal than a digest: it cannot see an edit that preserved the timestamp. Measured on the fifteen Notes on the author's machine — none is modified after its record, so all fifteen adopt cleanly.

### AD-42 — Anything the user can lose goes to the Trash, and a failure to do so is reported

- **Binds:** FR-40, FR-83, AD-10
- **Prevents:** an unrecoverable delete. This is not hypothetical: `removeItem` on a Meeting directory has already destroyed a real recording, with `~/.Trash` empty afterwards and no route back. It also prevents the quieter failure of a Trash call that fails on a volume without one and falls back to unlinking, which turns a safety mechanism into an inconsistent one.
- **Rule:** Deleting a Meeting directory, or a Note on the user's behalf, uses `trashItem`. `removeItem` remains correct for temporary files, staged writes and app-internal scratch, and is used for nothing the user has ever seen. A `trashItem` failure surfaces as an error with its reason; there is no fallback to unlinking, because a delete the user cannot undo is precisely the outcome this decision exists to prevent.

### AD-43 — The app enumerates only the files it wrote

- **Binds:** FR-82, FR-79, PRD §9.1
- **Prevents:** the app treating a user's folder as its own index. The Notes Folder holds the user's documents; listing, claiming or acting on a Markdown file Minutes did not write is an overstep, and a component that lists "every `.md`" will do exactly that.
- **Rule:** Any enumeration of the Notes Folder considers a file only if its frontmatter carries a Minutes identity marker — a Meeting ID, or `generated_by: Minutes` together with `started_at` for files written before the stamp. Files without one are not listed, not linked automatically, and never modified. The one exception is FR-79, where the user names a specific file: an explicit choice may point at a file the app did not write, and the app then states what the next rewrite will do to it rather than refusing or staying silent.


### AD-44 — The capture rate is observed, not merely declared

- **Binds:** FR-6, FR-7, AD-3, AD-36, AD-45
- **Prevents:** the defect that produced seven fabricated transcripts — a declared rate that the device does not honour, resampled as if it did. A component that reads the rate once at setup cannot tell a correct 48 kHz stream from a 16 kHz stream mislabelled as 48 kHz, and both are ordinary-looking float samples in a ring buffer.
- **Rule:** A stream's writer counts the input frames it consumes and the elapsed time it has been running, and compares the two against the format it was given. A disagreement beyond a stated tolerance is a **named failure**, surfaced with both rates, and never a silent resample. The tolerance and the settling period before the first check both carry their reasoning at their declaration, and neither is a setting. The comparison runs while recording, not only at the end, because a two-hour meeting is too expensive to discover afterwards. What the app does about a disagreement — correct the converter, or stop the stream and say so — is a story-level decision; that it must not proceed silently is not.

### AD-45 — A stream is trusted only if its sample count agrees with the clock

- **Binds:** FR-42, FR-67, AD-36, AD-44, AD-46
- **Prevents:** any future defect of this shape shipping silently, whatever its cause. A rate misread, a dropped-buffer bug, a converter misconfiguration and a clock drift all present identically: a file whose sample count does not match the time it took to record. One check catches the class, and it would have surfaced all seven of these at record time rather than after the notes were written.
- **Rule:** Capture evidence gains a second, independent component: `samples / elapsed` against the format's rate. A stream that disagrees beyond AD-44's tolerance is recorded as **untrustworthy** on the Meeting, alongside the observed and declared rates, and that flag travels with the record — it is not a transient display state. Trust is per stream: the microphone being sound says nothing about the system stream, and in every observed case the microphone was sound. This check is cheap, is derived from values the writer already holds, and must not be gated on a preference.

### AD-46 — Derived content is never generated from audio the app cannot vouch for

- **Binds:** FR-26, FR-27, FR-30, AD-12, AD-45
- **Prevents:** the reason this defect looked fine for three days. The title, the tags and the summary were generated from fabricated text, so a broken recording arrived with a confident name and a plausible shape — and the provenance field said `heuristic`, which was true and told the reader nothing. Metadata derived from untrustworthy audio is worse than absent metadata, because it disguises the failure.
- **Rule:** A Meeting whose stream failed AD-45 does not have Metadata derived from that stream's text. The Note states which stream is untrustworthy and why, in the same voice as every other degradation (AD-17, FR-7): the transcript that exists is still written, because the samples are the user's and discarding them would be worse, but nothing is inferred *from* it and no title, tag or summary is produced from it. Where only one of the two streams is untrustworthy, the trustworthy stream's text may still produce Metadata, and the Note says that is what happened.

## Consistency Conventions


| Concern | Convention |
| --- | --- |
| Naming — types | PRD Glossary terms verbatim as type names: `Meeting`, `Session`, `Utterance`, `SpeakerLabel`, `SpeakerProfile`, `TranscriptionModel`, `MetadataBackend`, `Note`. No synonyms — no `Recording`, no `Segment` for an Utterance. |
| Naming — ports vs adapters | Port protocol `Xxxing` or `XxxPort` in Services; adapter `ConcreteXxx` in `Adapters/`. E.g. `Transcribing` ← `WhisperKitTranscriber`. |
| Naming — files | One primary type per file, filename == type name. |
| IDs | Meeting ID is a sortable string `yyyyMMdd-HHmmss-<4 random chars>`; it is the directory name and never changes, including on rename. |
| Dates & times | Wall-clock as ISO 8601 with offset, at Meeting level only. Everything below is `TimeInterval` seconds from the session clock (AD-4). |
| Durations in UI | Monospaced digits, `mm:ss` under an hour, `h:mm:ss` over. |
| Errors | One `MinutesError` enum per adapter domain, each case carrying a user-presentable reason. No `NSError`, no string-typed errors. |
| Logging | `os.Logger` with subsystem `dev.niklas.minutes` and one category per layer. Every CoreAudio call's `OSStatus` is logged at the boundary — the spikes proved this is how a silent failure gets found. Never log transcript text. |
| Config / preferences | A readable settings document in the user-data directory, migrated once from `UserDefaults` (AD-37); the Notes Folder as a security-scoped bookmark, not a path string. Until that migration ships, `UserDefaults` for scalars. |
| Security-scoped access | `Preferences` resolves the Notes Folder bookmark and owns the single balanced `startAccessingSecurityScopedResource` / `stop…` pair. No other component starts or stops access. |
| Meeting record writes | Field-level updates through `MeetingStore` only (AD-21). Adapters return values. |
| Note identity | Every Note carries its Meeting ID in frontmatter; the link is resolved through `NoteLocating`, never inferred from a path (AD-39). No component reads a Note's body — the identity reader's return type makes it unrepresentable. |
| Note filenames | Two names on the record: the linked file, and the last name the app wrote. Divergence means the user owns the name (AD-40). No `didUserRename` flag. |
| Overwriting a user's file | Compare a stored digest of the app's last write against the bytes on disk (AD-41). Never compare against a fresh render; the renderer changes between increments. |
| Deleting | `trashItem` for anything the user has seen; `removeItem` only for temporary and staged files (AD-42). A Trash failure is an error, never a silent unlink. |
| Reading the Notes Folder | Only files carrying a Minutes identity marker are enumerated (AD-43). |
| State mutation | Only `SessionCoordinator` writes `AppState` (AD-7). |
| Concurrency | `@MainActor`: UI, `AppState`, `SessionCoordinator`, `VoiceEnrolment` (it drives a capture and publishes phase to a view, exactly as `TestPlayground` does). `actor`: capture engine, `SpeakerDirectory`. Serial executor: ML (AD-14) — and embedding a voice sample runs on it, so an enrolment during an active transcription queues rather than contending. IOProc: C callback, real-time-safe — no allocation, no locks, no logging inside it. |
| Persistence format | `meeting.json` via `Codable` with explicit `CodingKeys`; unknown-key tolerant on read so an older record still loads. |
| Visual tokens | Never hardcode a colour or metric present in `DESIGN.md`; resolve semantic colours from AppKit at render time. |
| Voice fingerprints | `[Float]` plus a producer identifier and a dimension, persisted in `speakers.json` alongside Speaker Profiles (AD-29). Compared only in Core. Never logged, never rendered as numbers to the user beyond a single measured distance stated as a fact, never transmitted (PRD §9.1). |
| Version | Derived from the git tag at bundle time and read back from the bundle (AD-33). No version literal is maintained in source or in the plist. |
| Evidence of capture | Two independent parts, both required: signal in the samples (AD-36), and a sample count that agrees with the clock (AD-45). Never the existence of a file. |
| Sample rates | A declared rate is a hypothesis. The writer compares consumed frames against elapsed time and names a disagreement (AD-44). No component resamples on a rate it has not checked. |
| Derived content | Never generated from a stream that failed its evidence check (AD-46). A confident title on a broken recording is what hid this defect for three days. |
| Paths outside the user-data directory | Enumerated in exactly one place, and the footprint listing, uninstall documentation and cask removal list all derive from it (AD-37). |
| Calibrated constants | A number derived from measurement carries the measurement's date and a path to the report, in a comment at its declaration. If it cannot cite one it is a guess and must be labelled as one (AD-31). |
| Decodable evolution | Every persisted `Codable` type that has shipped gets a hand-written `init(from:)` using `decodeIfPresent` with defaults. Swift ignores a property's default value when the key is absent and throws `keyNotFound` instead, which is how adding one field to `Meeting` silently orphaned five real recordings. `SpeakerDirectory.Profile` gains fields in increment 4 and therefore gains the same treatment. |

## Stack

Verified on the target machine on 2026-08-31.

| Name | Version |
| --- | --- |
| macOS (target / host) | deployment 15.0 · host 26.6.2 (25G83) |
| Swift toolchain | 6.3.3 (language mode 5 — AD-15) |
| swift-tools-version | 6.0 |
| Xcode CLI tools | 26.6 (17F113) |
| argmaxinc/argmax-oss-swift | exact 1.1.0 (products `WhisperKit`, `SpeakerKit`) |
| Default Transcription Model | `openai_whisper-large-v3-v20240930_turbo_632MB` |
| Diarization models | pyannote v4 community-1 via `argmaxinc/speakerkit-coreml` (lazy, first `diarize()`) |
| UI | SwiftUI (`MenuBarExtra`, `NavigationSplitView`) |
| Apple on-device LLM (optional) | `FoundationModels` — run-time availability check. **Verified unavailable on this host:** `appleIntelligenceNotEnabled`, i.e. eligible hardware with the feature declined at Setup Assistant |
| Local downloadable LLM (increment 3) | `ml-explore/mlx-swift-examples` exact `2.29.1` (products `MLXLLM`, `MLXLMCommon`) → `mlx-swift` `0.31.6`. Adds `swift-transformers` 1.0.x and `GzipSwift` 6.0.1 transitively; no conflict with the argmax graph, which vendors its own dependencies |
| Metal toolchain | **required by the above and currently `uninstalled`** — `xcodebuild -downloadComponent MetalToolchain`. See AD-27 |
| Candidate summarisation models | sizes fetched live, not estimated: `Qwen3.5-4B-MLX-4bit` 3.03 GB · `Llama-3.1-8B-Instruct-4bit` 4.52 GB · `Qwen3.5-9B-MLX-4bit` 5.95 GB. Curation pending PRD §13 Q13 |
| Voice embeddings (increment 4) | **No new dependency.** `SpeakerKit.DiarizationResult` already exposes `nearestSpeakerCentroid(to:) -> (speakerId, distance)` and `centroidCosineDistance(between:and:)` through the already-linked `argmax-oss-swift` exact 1.1.0, and per-speaker centroids are already persisted per Meeting. 256-dimensional, pyannote v4 community-1 |
| Speaker match threshold | **0.35, measured** — calibrated 2026-09-01 against five real Meetings (AD-31). Was 0.45, never calibrated |
| Build/packaging | `swift build` + `Scripts/build-app.sh` (assemble + ad-hoc `codesign`) |

## Structural Seed

### Processing pipeline (AD-8)

```mermaid
graph LR
    MIC[Mic Stream] --> CAP[Capture]
    SYS[System Stream] --> CAP
    CAP -->|captured| TR[Transcribe]
    TR -->|transcribed| DI[Diarize BOTH streams]
    SD[(SpeakerDirectory<br/>profiles + enrolled voice)] -. read .-> DI
    DI -->|diarized| AT[Attribute + merge]
    AT -->|attributed| MD[Metadata]
    MD -->|metadata| WR[Write Note]
    WR -->|written| DONE[Meeting complete]
```

Each edge label is the persisted `stage` value reached. Any stage may fail and be resumed from the previous label.

Two corrections and one addition, 2026-09-01. The diarize node read *"Diarize system stream"*, and the code has diarized both streams since AD-11 was amended — the diagram was describing the design AD-11 replaced. The `SpeakerDirectory` read is drawn as a **dotted read into an existing stage, not a new stage**: AD-8's stage list is fixed, and enrolment resolves an *input* to attribution rather than adding a step to the pipeline. Enrolment itself appears nowhere on this diagram, because it is not part of a Meeting's processing at all (AD-32).

### Voice enrolment (AD-28, AD-32)

Separate from the pipeline on purpose. It produces no Meeting, writes no Note, and touches no Meeting directory.

```mermaid
graph LR
    REC[Record mic only<br/>~25 s, temp dir] --> EMB[VoiceEmbedding port]
    EMB --> CHK{one voice?<br/>enough speech?}
    CHK -->|no| REJ[Refuse, state which]
    CHK -->|yes| FP[Fingerprint + producer id]
    FP --> SD[(SpeakerDirectory<br/>enrolled profile)]
    REC -.->|deleted on every exit path| DEL((audio gone))
    REJ -.-> DEL
```

### Core entities

```mermaid
erDiagram
    MEETING ||--o{ UTTERANCE : contains
    MEETING ||--o{ SPEAKER_LABEL : participants
    MEETING ||--|| METADATA : has
    MEETING ||--|| NOTE : projects_to
    SPEAKER_LABEL }o--o| SPEAKER_PROFILE : resolved_by
    UTTERANCE }o--|| SPEAKER_LABEL : attributed_to
```

`NOTE` is a projection, not stored state (AD-9). `SPEAKER_PROFILE` is app-global, not per-Meeting.

### Source tree

```text
Minutes/
  Package.swift
  Scripts/
    build-app.sh          # swift build -> assemble Minutes.app -> ad-hoc codesign (AD-16)
    Info.plist            # LSUIElement, usage descriptions, bundle id
    Minutes.entitlements  # sandbox off, audio-input on
  Sources/Minutes/
    App/                  # @main entry, MenuBarExtra scene, window scene
    Core/                 # Meeting, Utterance, SpeakerLabel, Stage, errors, VoiceMatch —
                          # Foundation only. VoiceMatch is the identification MECHANISM and
                          # must stay compilable against Foundation alone (AD-28).
    Services/
      SessionCoordinator  # sole writer of AppState (AD-7); starts/stops Sessions
      Pipeline            # staged processing (AD-8)
      DetectionService    # poll + prefix match (AD-5)
      ModelCatalog        # runtime model list (AD-13)
      SpeakerDirectory    # SpeakerProfile matching + the enrolled voice (FR-25, FR-62..64)
      VoiceEnrolment      # records, embeds, discards (AD-32); no Meeting, no Note
      Ports/              # protocols: Capturing, Transcribing, Diarizing, MetadataBackend,
                          #            NoteWriting, VoiceEmbedding (AD-28)
    Adapters/
      Audio/              # MicCapture, SystemTapCapture (AD-1..3), StreamFileWriter
      Transcribe/         # WhisperKitTranscriber
      Diarize/            # SpeakerKitDiarizer, SpeakerKitVoiceEmbedder (an adapter may be
                          # Apple-specific; the port and the maths may not — AD-28)
      Metadata/           # HeuristicBackend (pure), FoundationModelsBackend
      Persistence/        # MeetingStore, NoteWriter, Preferences
      System/             # Notifier, LoginItem, Permissions
    UI/                   # MenuBarContent, GettingStartedPane, TranscriptionPane,
                          # DetectionPane, GeneralPane, MeetingsPane, components/
  Tests/MinutesTests/     # Heuristic backend, merge/attribution, Note rendering, stage machine
```

## Capability → Architecture Map

| Capability / Area | Lives in | Governed by |
| --- | --- | --- |
| Menu bar control (FR-1…5) | `App/`, `UI/MenuBarContent` | AD-7, DESIGN.md components.menubar-icon |
| Dual-stream capture (FR-6…10) | `Adapters/Audio` | AD-1, AD-2, AD-3, AD-4, AD-6 |
| Detection + prompt (FR-11…15) | `Services/DetectionService`, `Adapters/System/Notifier` | AD-5, AD-6 |
| Transcription + models (FR-16…20) | `Adapters/Transcribe`, `Services/ModelCatalog` | AD-13, AD-14, AD-8 |
| Speaker attribution (FR-21…25) | `Adapters/Diarize`, `Services/SpeakerDirectory` | AD-11, AD-4 |
| Metadata (FR-26…30) | `Adapters/Metadata` | AD-12, AD-17 |
| Note output (FR-31…35) | `Adapters/Persistence/NoteWriter` | AD-9, AD-10 |
| Library (FR-36…40) | `UI/MeetingsPane`, `Adapters/Persistence/MeetingStore` | AD-9, AD-8 |
| Setup / settings (FR-41…48) | `UI/GettingStartedPane` + panes | AD-16, EXPERIENCE.md § Permission Choreography |
| Library management (FR-49…54) | `UI/MeetingsPane`, `UI/GeneralPane`, `Services/AppState` | AD-9, AD-8, AD-21 |
| Summarisation intelligence (FR-55…61) | `Adapters/Metadata/*`, `Services/SummarizerCatalog`, `Adapters/System/KeyStore`, `UI/SummariesPane` | AD-12, AD-22, AD-23, AD-24, AD-25, AD-26, AD-27 |
| Voice enrolment (FR-62…65) | `Core/VoiceMatch`, `Services/VoiceEnrolment`, `Services/SpeakerDirectory`, `Adapters/Diarize/SpeakerKitVoiceEmbedder`, `UI/GettingStartedPane` + `UI/GeneralPane` | AD-11 (amended), AD-28, AD-29, AD-30, AD-31, AD-32 |
| Note file management (FR-77…83) | `Core/NoteIdentity`, `Services/Ports` (`NoteLocating`), `Adapters/Persistence/NoteLocator` + `NoteWriter`, `Adapters/Persistence/MeetingStore`, `UI/MeetingsPane` | AD-9 (amended), AD-18 (amended), AD-39, AD-40, AD-41, AD-42, AD-43 |
| Rate fidelity (FR-84…88) | `Core/AudioEvidence`, `Adapters/Audio/StreamFileWriter`, `Adapters/Audio/SystemTapCapture`, `Services/Pipeline`, `Adapters/Persistence/NoteWriter`, `UI/MeetingsPane` | AD-3 (amended), AD-36 (amended), AD-44, AD-45, AD-46 |

## Build and Delivery Envelope, Increment 5

Increment 5 is the first whose subject *is* the build and delivery envelope, so this section changes substantively rather than asserting that nothing moved.

- **The build script grows a signing decision.** It signs Developer ID when a certificate is present and ad-hoc when none is, and states which it did. AD-16's reasoning is unchanged — signing remains part of the build, not packaging — but the identity is no longer always ad-hoc, and that is what makes consent survive an update (AD-34).
- **The plist stops carrying a version.** Bundle assembly substitutes it from the tag (AD-33). This is the first value in the bundle that is computed rather than copied.
- **A release path exists, separate from the build path.** Notarization and stapling happen only on a tagged release, in CI, with credentials that never exist on a developer machine. `./Scripts/build-app.sh` remains the local path and gains no network dependency.
- **A second repository enters the picture** — the Homebrew tap (AD-35). It holds one cask file and is updated by CI on release. It is not a submodule and the app does not know it exists.
- **One new persisted file shape, and this one is a migration.** Settings move out of `UserDefaults` into the user-data directory (AD-37). Unlike increment 4's additive change to `speakers.json`, this one moves data between stores, so it runs once, is idempotent, and must carry the Notes Folder's security-scoped bookmark across intact — the one piece that cannot be recreated from a default.
- **No new entitlement, and no new dependency.** Nothing in this increment needs either.

## Build and Delivery Envelope, Increment 4

Stated because the reviewer checklist treats a silent dimension as a finding, and because increment 3's AD-27 *did* bind the build — so "nothing changes here" is a claim worth making explicitly rather than leaving to be inferred.

- **No build-script change.** Enrolment adds no SPM resource bundle, no framework, and no bundled asset, so `Scripts/build-app.sh` is untouched by this increment. AD-16 stands as written.
- **No new dependency and no new entitlement.** Enrolment reads the microphone, for which `NSMicrophoneUsageDescription` and the audio-input entitlement already exist. It never opens the System Stream, so it needs nothing from AD-16's system-audio path and cannot be broken by the TCC re-grant that follows a rebuild.
- **No new model download.** The Diarizer's models are already fetched lazily on first `diarize()` and are the same models enrolment embeds with. A machine that has completed one Meeting can enrol offline.
- **One new persisted file shape, backward-compatibly.** `speakers.json` gains fields on `Profile`; the Decodable-evolution convention above is what stops that repeating the `Meeting` defect. There is no migration step and no schema version — an older file loads with the new fields defaulted.

## Deferred

- **Live/streaming transcription.** PRD §6.2 defers it to v2. AD-8's staged pipeline is deliberately batch-shaped; streaming would need a different decomposition, and pre-building for it would compromise the reliable path.
- **Crash-recovery UI.** AD-8 makes an interrupted Meeting resumable and AD-10 keeps its data intact, so recovery is a UI affordance, not an architectural gap. Deferred per PRD §6.2.
- ~~**Speaker Profile matching algorithm.**~~ **Decided 2026-09-01.** The embedding is SpeakerKit's 256-dimensional centroid behind AD-28's port; the comparison is cosine distance in Core; the threshold is measured (AD-31). PRD §13 Q4 is answered for in-room voices and narrowed for Remote Speakers, where AD-31 records the limit rather than hiding it. What the deferral got right is worth keeping: the port stays, and if the embedding proves unreliable the implementation degrades to manual rename without touching anything above it.
- **Aggregate device rebuild on output-device change.** FR-8 requires surviving the change; whether that means rebuilding the aggregate or the HAL handling it is unresolved (PRD §13 Q7). AD-2 fixes the ordering either way, so this is a story-level experiment.
- ~~**Notes Folder conflict policy for hand-edited Notes.**~~ **Split 2026-09-03.** *Detection* is now in scope and decided: AD-41 stores a digest of what the app wrote, so an edit is a fact rather than a guess, and FR-81 makes the user the one who chooses. *Merging* stays out of scope and should stay out permanently — there is no mechanism that could reconcile a paragraph a human wrote with a transcript the app renders, and any attempt produces a file neither party recognises. What the original deferral got wrong is worth recording: it was reasonable while the app was the only thing that ever touched a Note, and it stopped being reasonable the moment the user started filing them, which nothing in the architecture was watching for.
- **Watching the Notes Folder.** A rename is noticed on the next reload rather than as it happens, so a renamed Note reads as missing until something reloads (PRD §13 Q23). AD-39 owns the correctness; a watcher would own only the latency, at the cost of a live subsystem and a class of event storms. Ranked last deliberately.
- **Adopting a user's filename as the Meeting's title.** Tempting, and refused: it would read content back into state against AD-9, and a filename is a date prefix plus a slug rather than a title. Renaming a Meeting in the app already works and stays the answer.
- **Re-importing an Unclaimed Note as a Meeting.** AD-43 lists them and AD-9 forbids parsing them, so the two together make this structurally impossible rather than merely unbuilt. A half-Meeting with a transcript and no audio would be a second kind of record for every consumer of `Meeting` to special-case.
- **Distribution, notarization, auto-update.** Excluded by PRD §5. AD-16 stops at a locally installed ad-hoc signed bundle.
- **Model eviction policy.** FR-44 exposes disk use and removal; an automatic policy is deferred — the user decides.
- **Global hotkey.** EXPERIENCE.md defers it to v2; it would add a permission surface and a conflict UI.
- **Which local model, and whether a 4-bit model in the 3-6 GB class is good enough at all.** AD-12 fixes the port and AD-13 fixes where the list comes from; the curation is a story-level decision that cannot be made before PRD §13 Q13 is measured — and it cannot be measured until AD-27's prerequisite is installed. This is the increment's critical path.
- **Which remote endpoint, and whether the remote backend should ship.** AD-24 fixes the chokepoint and its contract, so the shape is settled whatever the answer. Whether to build it depends on the local path's measured quality and on whether an employer-approved vendor under a data processing agreement exists (PRD §13 Q17). The architecture is deliberately indifferent to the answer.
- **Streaming summarisation output.** The spike confirmed the local path returns an `AsyncStream` of chunks, so partial output is available. Whether the UI shows a summary assembling itself is a UX decision with no architectural consequence — the port returns a completed structure either way (AD-12's typed-output rule).
- **macOS input voice processing** (`setVoiceProcessingEnabled`). Measured, and deliberately not adopted: it works and returns OK, and it changes the input from 1 channel to **3 deinterleaved** channels. Which channel carries the clean signal is unmeasured, and `StreamFileWriter`'s downmix averages all channels — so adopting it blind would average the noise back in. It is also macOS-only, which AD-28 permits behind the port but never as the mechanism. Needs a controlled recording with a known interfering source before any code.
- **Per-device voice fingerprints.** AD-29 makes a fingerprint carry its producer, not its microphone, and the calibration's four Meetings all used one input device. AirPods and a built-in microphone colour a voice differently, and the mic-isolation spike found the app had been recording through AirPods without recording *that* it had. If PRD §13 Q19 turns out badly, the fix is a fingerprint per device rather than a change to AD-28 — the port already returns a value the caller may key however it likes.
- **Enrolment for anyone but the user.** PRD §6.2's deferral was reversed for one person only. AD-28's port is indifferent to whose voice it embeds, so the architecture does not forbid it; nothing in this increment builds toward it, and the consent question it raises is a product decision, not a structural one.
- **A voice-activity gate before embedding.** The mic-isolation spike found `VadManager` already linked via FluidAudio. It would produce a cleaner fingerprint from a sample containing silence. Held: enrolment asks the user to talk continuously for 25 seconds, so the silence problem it solves is one the interaction already avoids. Revisit only if measured sample quality demands it.
- **Prompt design and its versioning.** Summary quality will depend heavily on the prompt, and a changed prompt changes output for the same Transcript. Whether the prompt version belongs in the Note's provenance alongside the model identifier is deferred until there is a prompt worth versioning.
