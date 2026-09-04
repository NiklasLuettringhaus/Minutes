---
stepsCompleted: [1, 2, 3, 4]
revisions:
  - 2026-09-04 increment 10 — Epic 16 is re-affirmed rather than rewritten. Stories
    16.9 to 16.15 were written in increment 9 and are unchanged in scope; their
    architecture references are updated because AD-53 to AD-56 now exist and AD-44,
    AD-49, AD-50 and AD-51 were amended by implementation. One story is added,
    16.16, for the new FR-101. No epic, story or requirement is renumbered, and no
    new epic was needed — FR-101 is about the same instrument Story 16.1 built.
  - 2026-09-03 increment 9 — added Epic 16 (15 stories, FR-89 to FR-100 plus the FR-17,
    FR-21, FR-22 and FR-23 amendments) after a measurement harness was built first and
    found that three of twelve dual-stream recordings had the microphone recording the
    far end. Epics 1-15 untouched and not renumbered. The first epic whose opening story
    is the instrument rather than a fix, and the first to retract one of its own
    conclusions mid-investigation.
  - 2026-09-03 increment 8 — added Epic 15 (7 stories, FR-84 to FR-88 plus the FR-67
    amendment) after seven of sixteen recordings were found to have transcribed into
    invented dialogue for three days. Epics 1-14 untouched and not renumbered. The
    first epic written from a defect the *user* found and documented before the
    product did.
  - 2026-09-03 increment 7 — added Epic 14 (11 stories, FR-77 to FR-83 plus the FR-35,
    FR-40, FR-53 and FR-54 amendments) after a single user report and a measured
    reconstruction of what the app did with a renamed Note. Epics 1-13 untouched and not
    renumbered. The first epic whose ordering is set by what has already been lost rather
    than by dependency.
  - 2026-09-02 increment 5 — added Epics 11, 12 and 13 (15 stories, FR-66 to FR-76) after
    the repository was published and the app was audited for the first time against a
    machine other than the author's. Epics 1-10 untouched and not renumbered. First
    increment whose defects were all found by reading code rather than by using the app.
  - 2026-09-01 increment 4 — added Epic 10 (7 stories, FR-62 to FR-65 plus the FR-21,
    FR-25 and FR-46 amendments) headless, after a spike and a threshold calibration.
    Epics 1-9 untouched and not renumbered. First epic whose central constant was
    measured before any of its stories were written.
  - 2026-08-31 increment 3 — added Epic 9 (7 stories, FR-55 to FR-61) headless, after
    a review and a spike. Epics 1-8 untouched and not renumbered.
  - 2026-08-31 increment 2 — added Epic 8 (6 stories, FR-49 to FR-54 plus the
    FR-40 amendment) headless. Existing epics and stories untouched and not renumbered.
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-meeting-recorder-2026-08-31/prd.md
  - _bmad-output/planning-artifacts/prds/prd-meeting-recorder-2026-08-31/addendum.md
  - _bmad-output/planning-artifacts/architecture/architecture-meeting-recorder-2026-08-31/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/ux-designs/ux-meeting-recorder-2026-08-31/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-meeting-recorder-2026-08-31/EXPERIENCE.md
  - _bmad-output/planning-artifacts/briefs/brief-meeting-recorder-2026-08-31/addendum.md
  - _bmad-output/planning-artifacts/spikes/spike-mic-isolation-2026-09-01.md
  - _bmad-output/planning-artifacts/spikes/calibration-speaker-threshold-2026-09-01.md
  - _bmad-output/planning-artifacts/spikes/investigation-note-linkage-2026-09-03.md
  - _bmad-output/planning-artifacts/spikes/investigation-transcription-quality-2026-09-03.md
  - _bmad-output/planning-artifacts/spikes/calibration-echo-threshold-2026-09-03.md
  - _bmad-output/planning-artifacts/spikes/research-multisource-transcription-2026-09-04.md
  - _bmad-output/planning-artifacts/RELEASE-PLAN.md
---

# Minutes - Epic Breakdown

## Overview

This document decomposes the 101 functional requirements, 8 cross-cutting NFRs, the 56 architecture decisions and the two UX spines into 113 implementable stories across 16 epics (the count read 41 before increment 2; the real figure for epics 1-7 is 43, corrected then rather than left stale). Epics 1-7 (FR-1 to FR-48) are built; Epic 8 is increment 2, added after the user operated that build; Epic 9 is increment 3; Epic 10 is increment 4; Epics 11-13 are increment 5, the first aimed at a machine other than the author's; Epic 14 is increment 7, the first written from something the product had already destroyed; Epic 15 is increment 8, written from a defect the user found and documented before the product did; Epic 16 is increment 9, the first written from a defect nobody had noticed, because the affected notes merely read as verbose until accuracy became measurable, and it is carried into increment 10, which builds the half of it that increment 9 wrote and left. Epics are capability-shaped; the PRD's build-order tier is recorded per story so sprint planning can sequence a walking skeleton first.

Every FR is covered by exactly one story — verified programmatically, see the FR Coverage Map for increment 1 and each later epic's own coverage table.

**Requirements inventory scope.** The inventory below covers FR-1 to FR-48, the requirement set that existed when this document was created. Every increment since has carried its new requirements inside its own epic section, restated there rather than duplicated at the top. Epic 10, Epics 11-13 and Epic 14 follow that convention.

## Requirements Inventory

### Functional Requirements

**FR-1 — Menu bar presence** *(tier T0)*: Minutes runs as a menu-bar-only application with no Dock icon and no window on launch.

**FR-2 — Three-state icon** *(tier T0)*: The icon renders a distinct appearance for each of Idle, Recording, and Transcribing.

**FR-3 — Start and stop a Session from the menu** *(tier T0)*: The user can start a Session and stop a running Session from the menu bar menu.

**FR-4 — Session status in the menu** *(tier T2)*: While Recording or Transcribing, the menu shows what is happening.

**FR-5 — Menu access to the main window and Quit** *(tier T2)*: The menu provides entry to the main window's panes and to Quit.

**FR-6 — Dual-stream capture** *(tier T0)*: A Session captures the Mic Stream and the System Stream concurrently, as separately addressable audio.

**FR-7 — Graceful degradation to Mic-only** *(tier T1)*: If the System Stream cannot be captured, the Session proceeds with the Mic Stream alone rather than failing.

**FR-8 — Survive output device changes** *(tier T2)*: Changing the default output device during a Session does not end the Session or lose the System Stream.

**FR-9 — Long-Session durability** *(tier T1)*: A Session can run for at least 3 hours without loss.

**FR-10 — Do not capture while Idle** *(tier T0)*: No audio is captured outside an explicit Session.

**FR-11 — Detect audio-input activity by application** *(tier T1)*: Minutes determines which applications are actively using the audio input device, and their identity.

**FR-12 — Debounced Detection Prompt** *(tier T1)*: When a Watched App holds the input device for a sustained interval, Minutes shows a Detection Prompt.

**FR-13 — Accepting a Prompt starts a Session** *(tier T1)*: Choosing Record on a Detection Prompt starts a Session identical to a manually started one.

**FR-14 — Auto-stop on meeting end** *(tier T1)*: A Session started from a Detection Prompt stops automatically when the triggering application releases the input device.

**FR-15 — Suppress detection per app and globally** *(tier T2)*: The user can stop being asked, for one Watched App or for all of them.

**FR-16 — Transcribe locally after Capture ends** *(tier T0)*: Stopping a Session produces a Transcript, computed entirely on-device.

**FR-17 — Select a Transcription Model** *(tier T1)*: The user can choose among available Transcription Models.

**FR-18 — Download and cache models with visible progress** *(tier T1)*: Selecting a model that is not present downloads it, showing progress.

**FR-19 — Transcription failure is reported, and audio is kept** *(tier T1)*: A Session whose transcription fails does not lose its audio.

**FR-20 — Queue concurrent work** *(tier T2)*: A Session that stops while another Meeting is transcribing is not lost.

**FR-21 — Attribute the Mic Stream to the Local Speaker** *(tier T0)*: All Utterances derived from the Mic Stream carry the Local Speaker's Speaker Label.

**FR-22 — Diarize the System Stream into Remote Speakers** *(tier T1)*: Utterances derived from the System Stream are assigned Remote Speaker labels by on-device Diarization.

**FR-23 — Merge Streams into one ordered Transcript** *(tier T0)*: The Transcript interleaves Mic and System Stream Utterances in chronological order.

**FR-24 — Rename a Speaker Label** *(tier T2)*: The user can rename any Speaker Label on a Meeting.

**FR-25 — Remember a named voice across Meetings** *(tier T3)*: Naming a Remote Speaker creates a Speaker Profile so the same voice is labelled automatically in later Meetings.

**FR-26 — Derive Metadata for every Meeting** *(tier T0)*: Every Meeting receives a title, a tag set, and a summary.

**FR-27 — Prefer the LLM Backend when available** *(tier T3)*: When the on-device foundation model is available, it produces the Metadata.

**FR-28 — Heuristic Backend always available** *(tier T0)*: The Heuristic Backend produces Metadata with no model and no network.

**FR-29 — Extract decisions and action items** *(tier T2)*: Where the Transcript contains decisions or action items, they appear in the Note.

**FR-30 — Record which Backend produced the Metadata** *(tier T1)*: Every Note names its Metadata Backend.

**FR-31 — Write one Note per Meeting** *(tier T0)*: Each completed Meeting produces exactly one Markdown file in the Notes Folder.

**FR-32 — YAML frontmatter carrying Metadata** *(tier T0)*: The Note begins with YAML frontmatter.

**FR-33 — Body structure — Metadata then Transcript** *(tier T0)*: The body presents the derived content before the raw record.

**FR-34 — Choose the Notes Folder** *(tier T1)*: The user chooses where Notes are written.

**FR-35 — Rewrite a Note in place on edit** *(tier T2)*: Editing a Meeting's title or Speaker Labels updates its Note.

**FR-36 — List past Meetings** *(tier T2)*: The Library lists Meetings in reverse chronological order.

**FR-37 — Open and read a Meeting** *(tier T2)*: Selecting a Meeting shows its Metadata and Transcript.

**FR-38 — Edit title and Speaker Labels from the Library** *(tier T2)*: The user can rename a Meeting and its Speaker Labels here.

**FR-39 — Retry a failed transcription** *(tier T2)*: A Meeting whose transcription failed can be retried.

**FR-40 — Delete a Meeting** *(tier T2)*: The user can delete a Meeting, including its audio.

**FR-41 — First-run setup** *(tier T1)*: On first launch the app guides the user to a working state.

**FR-42 — Permission state is visible and actionable** *(tier T1)*: Settings shows the state of each permission the app needs.

**FR-43 — Configure detection** *(tier T2)*: The user can turn Detection off entirely or per Watched App. Satisfies FR-15 from the Settings surface.

**FR-44 — Configure audio retention** *(tier T2)*: The user controls whether Session audio is kept after a Note is written.

**FR-45 — Launch at login** *(tier T2)*: The user can have Minutes start at login.

**FR-46 — Setup Checklist** *(tier T1)*: The Setup pane presents an ordered checklist of everything required for a working install, each row showing its own state.

**FR-47 — Test Playground** *(tier T1)*: The Setup pane provides an in-app test that exercises Capture, transcription and attribution end-to-end.

**FR-48 — Re-run onboarding** *(tier T3)*: The user can re-enter the first-run flow after initial setup.


### NonFunctional Requirements

**NFR-1 — On-device by default; egress only by explicit, per-use consent**: All inference — transcription, Diarization, Metadata — executes locally unless the user has deliberately configured a Remote Summarisation Backend and consented for that Meeting. **Amended by PRD increment 3 and corrected here in increment 4**, where this entry still carried the retired absolute ("No audio, Transcript, or Metadata is transmitted anywhere, ever") three increments after the PRD replaced it. Three parts survive as invariants: audio never leaves the device; Speaker Profiles — including the Enrolled Voice (FR-64) — never leave the device; and nothing leaves without the user having both configured it and consented to it. Model downloads and, when configured, Remote Summarisation requests are the only permitted network activity, and both are user-initiated.

**NFR-2 — Apple Silicon, macOS 15+**: Targets Apple Silicon; deployment target no lower than macOS 14.4 for audio-capture permission reasons, and 15.0+ preferred. Intel is unsupported.

**NFR-3 — Negligible idle cost**: While Idle, CPU use is effectively zero apart from Detection polling, which itself must be cheap enough not to affect battery life measurably.

**NFR-4 — Bounded memory**: Memory during Capture is flat with respect to Session duration. Peak memory during transcription is bounded by the chosen model and does not risk system pressure on a 24 GB machine; two models never load concurrently (FR-20).

**NFR-5 — Failure is visible and non-destructive**: No failure path silently discards audio, a Transcript, or a Note. Every failure surfaces a reason and leaves the underlying data recoverable.

**NFR-6 — Verifiable egress**: The zero-egress claim must be verifiable by an outside observer with a network monitor, not merely asserted in documentation.

**NFR-7 — Accessible enough to trust**: Session state is conveyed by shape as well as colour (FR-2). Settings and Library are keyboard-navigable and legible at default system font sizes in light and dark mode.

**NFR-8 — Plain-text durability**: Notes remain fully useful if the app is deleted. No proprietary index, database or sidecar is required to read a Note.


### Additional Requirements

From the Architecture Spine. These are not optional implementation detail — each was verified by running code on the target machine, and several contradict published documentation.

- **No starter template.** Greenfield SPM package; the build is `swift build` plus `Scripts/build-app.sh`, which assembles and ad-hoc signs `Minutes.app`. No `.xcodeproj` anywhere (AD-16).
- **Ad-hoc signing is part of the build, not packaging.** TCC consent binds to the code signature; an unsigned binary can never receive audio permission. Consequence: consent is invalidated on rebuild.
- **`AudioDeviceCreateIOProcIDWithBlock` must never be used** — it deadlocks indefinitely on a tap-backed aggregate device. Use the C-function-pointer variant with an `Unmanaged<Self>` refCon (AD-1).
- **Detection must match bundle-ID by prefix.** Teams exposes no bare `com.microsoft.teams2` audio process object, so exact matching detects Teams never (AD-5).
- **Transcription model identifiers are `openai_whisper-`-prefixed** and must be enumerated at run time; the published docs list bare names and is wrong (AD-13).
- **`argmax-oss-swift` pinned exact `1.1.0`**, linking `WhisperKit` and `SpeakerKit` only, not the `ArgmaxOSS` umbrella.
- **Swift 5 language mode** on the app target, because the dependency declares `swiftLanguageVersions: [.v5]` (AD-15).
- **App Sandbox off, Hardened Runtime on.** Audio taps are unreliable under sandbox.
- **Deployment target macOS 15.0**, Apple Silicon only.
- **Single serial executor for all ML**; two CoreML models never load concurrently (AD-14).
- **The Meeting directory is the source of truth; the Note is a projection** the app never parses back (AD-9).
- **`MeetingStore` is the sole writer of `meeting.json`**; adapters return values and never persist (AD-21).
- **Staged, resumable pipeline**: `captured → transcribed → diarized → attributed → metadata → written`, with only the Pipeline advancing `stage` (AD-8, AD-20).
- **Atomic writes** for Notes, `meeting.json` and Speaker Profiles (AD-10).
- **Detection reads metadata only, never audio content** — a privacy invariant, not an optimisation (AD-6).

### UX Design Requirements

From `DESIGN.md` and `EXPERIENCE.md`. The setup pattern is a direct user directive (FluidVoice reference supplied mid-run), not a designer inference.

- **UX-DR1** — Menu bar icon: three states differing in **silhouette as well as tint**; Idle as a template image, Recording and Transcribing as palette images. **Never animate, in any state** — amended increment 4, when FR-50's Recording pulse was withdrawn on use.
- **UX-DR2** — Checklist row component: leading indicator (satisfied glyph vs. ordinal in a ring), title, one-line subtitle, trailing control (dim non-interactive `Done` pill vs. live action button). Satisfied rows drop to ~55% opacity with secondary-colour titles. Hairline separators inset to text origin.
- **UX-DR3** — `Done` pill is **not a button**: fully round, no border, no hover state, not focusable, announced by VoiceOver as status.
- **UX-DR4** — Single window, `NavigationSplitView`, grouped sidebar: SETUP (Getting Started) · CONFIGURE (Transcription, Detection, General) · ACTIVITY (Meetings). Default destination Getting Started on first launch, Meetings thereafter.
- **UX-DR5** — State banner component with recording / transcribing / degraded variants at 12% tinted background; the degraded variant carries a warning glyph.
- **UX-DR6** — Speaker chip: Local Speaker brand-tinted, Remote Speakers neutral, auto-applied names prefixed to mark them inferred. This single visual difference encodes the product's structural claim.
- **UX-DR7** — Determinate download progress only; an indeterminate spinner is forbidden.
- **UX-DR8** — Resolve every colour, grey and type role from AppKit semantic colours at render time. Only three literal colours exist: Recording red `#E5484D`, Transcribing amber `#F5A524`, brand teal `#12A594`. Standard controls keep the user's own system accent.
- **UX-DR9** — Two depth levels, **no shadows on cards, no borders on top of a tonal step**. Card headings sit outside the card.
- **UX-DR10** — Monospaced digits for anything that ticks or counts; transcript text is prose, never monospaced.
- **UX-DR11** — Accessibility floor: full keyboard navigation, focus order following visual order, VoiceOver labels stating meaning not appearance, live-region announcements for Session state changes, usable at the largest accessibility text size.
- **UX-DR12** — Voice and tone: no exclamation marks, no emoji, no first-person plural. Every permission ask states its reason in one line. Never claim certainty macOS does not provide. Absence is stated, not padded. Glossary terms used verbatim; `Session` never leaks into user-facing copy.
- **UX-DR13** — Test Playground result card reporting Transcript text, per-Stream audio presence, model used, and measured time with an extrapolation.
- **UX-DR14** — Deliberate omissions: no dashboard, statistics, changelog pane, feedback form, illustrations, gradients, or in-app update prompts.

### FR Coverage Map

| FR | Tier | Story | FR | Tier | Story |
| --- | --- | --- | --- | --- | --- |
| FR-1 | T0 | 1.2 | FR-25 | T3 | 4.3 |
| FR-2 | T0 | 1.2 | FR-26 | T0 | 1.9 |
| FR-3 | T0 | 1.3 | FR-27 | T3 | 7.1 |
| FR-4 | T2 | 6.6 | FR-28 | T0 | 1.9 |
| FR-5 | T2 | 6.6 | FR-29 | T2 | 7.2 |
| FR-6 | T0 | 1.5 | FR-30 | T1 | 7.3 |
| FR-7 | T1 | 6.1 | FR-31 | T0 | 1.10 |
| FR-8 | T2 | 6.2 | FR-32 | T0 | 1.10 |
| FR-9 | T1 | 6.3 | FR-33 | T0 | 1.10 |
| FR-10 | T0 | 1.4 | FR-34 | T1 | 2.4 |
| FR-11 | T1 | 3.1 | FR-35 | T2 | 5.3 |
| FR-12 | T1 | 3.2 | FR-36 | T2 | 5.1 |
| FR-13 | T1 | 3.3 | FR-37 | T2 | 5.2 |
| FR-14 | T1 | 3.4 | FR-38 | T2 | 5.3 |
| FR-15 | T2 | 3.5 | FR-39 | T2 | 5.4 |
| FR-16 | T0 | 1.7 | FR-40 | T2 | 5.5 |
| FR-17 | T1 | 2.2 | FR-41 | T1 | 2.5 |
| FR-18 | T1 | 2.3 | FR-42 | T1 | 2.7 |
| FR-19 | T1 | 6.4 | FR-43 | T2 | 3.5 |
| FR-20 | T2 | 6.5 | FR-44 | T2 | 6.7 |
| FR-21 | T0 | 1.8 | FR-45 | T2 | 6.8 |
| FR-22 | T1 | 4.1 | FR-46 | T1 | 2.6 |
| FR-23 | T0 | 1.8 | FR-47 | T1 | 2.8 |
| FR-24 | T2 | 4.2 | FR-48 | T3 | 2.9 |

All 48 FRs of increment 1 covered exactly once; no FR appears in two stories. FR-49 to FR-54 are mapped in Epic 8's own coverage table.

## Epic List

1. **Epic 1: Foundation and Walking Skeleton** — 10 stories, tiers T0
2. **Epic 2: Transcription Models and the Setup Surface** — 9 stories, tiers T1, T3
3. **Epic 3: Meeting Detection** — 5 stories, tiers T1, T2
4. **Epic 4: Speaker Attribution** — 3 stories, tiers T1, T2, T3
5. **Epic 5: Meeting Library and Note Lifecycle** — 5 stories, tiers T2
6. **Epic 6: Resilience and Settings** — 8 stories, tiers T1, T2
7. **Epic 7: Metadata Intelligence** — 3 stories, tiers T1, T2, T3
8. **Epic 8: Trust the List, See the State** — 6 stories, tier T4 (increment 2)
9. **Epic 9: Summarisation You Choose and Can Trust** — 7 stories, tier T5 (increment 3)
10. **Epic 10: Knowing Which Voice Is Yours** — 7 stories, tier T6 (increment 4)


## Epic 1: Foundation and Walking Skeleton

Stand up the build, signing and bundle pipeline, then get one complete pass through the product working end to end: click record, talk, and get a titled Markdown file with speakers. Nothing outside this epic starts until this runs, because every later epic depends on this path existing.

### Story 1.1: Project scaffold, build and ad-hoc signing pipeline

*Requirements: AD-16, AD-15 · Tier -*

As a developer,
I want a Swift package that builds and ad-hoc signs a Minutes.app bundle with one command,
So that every later story can be run and tested as a real signed app, which is the only form macOS will grant audio permissions to.

**Acceptance Criteria:**

**Given** a clean checkout
**When** I run Scripts/build-app.sh
**Then** Minutes.app is produced, ad-hoc signed with the hardened runtime, and launches with a menu bar icon


**Implementation constraints:**

- Package.swift pins argmax-oss-swift exact 1.1.0 and links only WhisperKit and SpeakerKit, not the ArgmaxOSS umbrella (AD-15).
- The app target uses .swiftLanguageMode(.v5); the entry point is an explicit @main type, not top-level code.
- Info.plist carries LSUIElement, CFBundleIdentifier dev.niklas.minutes, NSMicrophoneUsageDescription and NSAudioCaptureUsageDescription.
- Signing uses --options runtime with an entitlements file setting app-sandbox false and device.audio-input true.
- codesign -dv reports adhoc+runtime with the identifier set.
- The script is idempotent and re-signs on every build, because consent is bound to the signature (AD-16).

### Story 1.2: Menu bar presence and three-state icon

*Requirements: FR-1, FR-2 · Tier T0*

As a user,
I want a menu bar icon that tells me at a glance whether Minutes is idle, recording or transcribing,
So that I never have to wonder whether I am being recorded.

**Acceptance Criteria:**

**Given** Minutes is running
**When** I look at the menu bar
**Then** the icon shows exactly one of three visually distinct states


**And** each of the following holds:

- The icon appears in the menu bar within 2 seconds of launch.
- No Dock icon appears at any point during normal operation.
- Quitting from the menu removes the icon and terminates the process.
- Each state uses both a distinct colour and a distinct glyph, so the states remain distinguishable in greyscale.
- The icon changes state within 500 ms of the underlying state change.
- The icon remains legible in both light and dark menu bars.

**Implementation constraints:**

- Idle renders as a template image so macOS tints it; Recording and Transcribing render as palette images because their colour is load-bearing (DESIGN.md components.menubar-icon).
- The three states differ in silhouette as well as tint, so they survive greyscale and colour blindness.

### Story 1.3: Start and stop a Session from the menu

*Requirements: FR-3 · Tier T0*

As a user,
I want to start and stop a recording from the menu bar menu,
So that capturing a meeting costs two clicks and no setup.

**Acceptance Criteria:**

**Given** Minutes is Idle
**When** I choose Start Recording
**Then** the icon turns Recording only once audio is actually being captured


**And** each of the following holds:

- The menu offers Start Recording when Idle and Stop Recording when Recording; never both.
- Start transitions the icon to Recording within 500 ms of audio actually being captured, not before.
- Stop ends Capture and begins transcription, transitioning the icon to Transcribing.
- Selecting Start when microphone permission is absent surfaces the permission problem rather than silently failing.

**Implementation constraints:**

- SessionCoordinator is the sole writer of AppState (AD-7).
- A single monotonic session clock is captured at Capture start; all downstream times are offsets from it (AD-4).

### Story 1.4: Microphone Stream capture

*Requirements: FR-10 · Tier T0*

As a user,
I want my microphone captured for the duration of a Session,
So that my own side of the conversation is always recorded.

**Acceptance Criteria:**

**Given** a Session is running
**When** I speak
**Then** microphone audio is written incrementally to disk on the session clock


**And** each of the following holds:

- Between Sessions, no audio device is held open by the app and no audio data is written.
- Detection (§4.3) reads only device-activity metadata; it never reads audio content. This is verifiable by inspection and is a privacy invariant, not an optimisation.

**Implementation constraints:**

- Uses AVCaptureDevice.requestAccess(for: .audio); there is no AVAudioSession on macOS.
- Between Sessions no audio device is held open and no audio is written (FR-10, AD-6).

### Story 1.5: System audio Stream capture via CoreAudio tap

*Requirements: FR-6 · Tier T0*

As a user,
I want the audio other participants produce captured separately from my microphone,
So that the transcript can tell me apart from them without guessing.

**Acceptance Criteria:**

**Given** a Session is running and remote participants are speaking
**When** the System Stream is captured
**Then** system audio is written to a separate artifact sharing the session clock


**And** each of the following holds:

- Two audio artifacts exist for a Session, each independently decodable.
- Both carry timestamps on a shared time base; a sound occurring at a known wall-clock moment appears at the same offset (±100 ms) in both.
- Audio is captured at a sample rate and format suitable for the Transcription Model without a lossy intermediate step.

**Implementation constraints:**

- MUST use AudioDeviceCreateIOProcID with a C function pointer and an Unmanaged<Self> refCon. The block variant deadlocks indefinitely — verified (AD-1).
- Construction and teardown follow AD-2's fixed order, with teardown on every error path.
- Format is read from kAudioTapPropertyFormat, never assumed; buffer walking uses UnsafeMutableAudioBufferListPointer (AD-3).
- CATapDescription.isExclusive is never mutated after init.
- Verify frame accounting by writing a file and comparing its duration to wall-clock — the spike showed a possible 2x discrepancy (open question).

### Story 1.6: Meeting record, store and staged pipeline

*Requirements: AD-8, AD-9, AD-10, AD-20, AD-21 · Tier -*

As a developer,
I want a Meeting record with a single writer and a staged, resumable pipeline,
So that expensive work is never lost to a late failure and no two components can clobber each other's fields.

**Acceptance Criteria:**

**Given** a Session has been captured
**When** the pipeline runs
**Then** each stage's output is persisted and `stage` advanced only after that stage returns successfully


**Implementation constraints:**

- MUST precede stories 1.7-1.10 — they are pipeline stages and have nowhere to write without this.
- Stages are pure functions from inputs to an output value; they never write the Meeting record and never touch `stage` (AD-20).
- MeetingStore is the SOLE writer of meeting.json, applying field-level updates through one serial access point. Adapters return values and never persist (AD-21).
- Without AD-21, Capture writing systemStreamCaptured, Diarize writing diarizationFailed and Metadata writing backend each silently drop the others' fields — which would present a Mic-only recording as a full one.
- Each Meeting owns one directory named yyyyMMdd-HHmmss-XXXX under Application Support, holding audio, meeting.json and stage outputs (AD-9).
- Atomic writes throughout: temp file in the destination, fsync, atomic replace (AD-10).
- meeting.json is Codable with explicit CodingKeys and tolerates unknown keys on read so older records still load.
- A stage failure leaves `stage` at the last completed value with a recorded reason, and is resumable from there (AD-8).

### Story 1.7: Local transcription with WhisperKit

*Requirements: FR-16 · Tier T0*

As a user,
I want my recording transcribed on this machine after the Session ends,
So that I get a transcript without any audio leaving the Mac.

**Acceptance Criteria:**

**Given** a Session has just stopped
**When** transcription runs
**Then** a Transcript of timestamped Utterances is produced with no network request


**And** each of the following holds:

- Transcription starts automatically on Session stop, with no user action.
- Each Utterance carries a start time, an end time, and text.
- The app makes no network request during transcription, verifiable by network monitoring.
- Transcription of a 30-minute Session with the default model completes in under 5 minutes on the target machine.

**Implementation constraints:**

- Runs on a single serial executor; two models never load concurrently (AD-14).
- Model identifier comes from the catalogue, never a hardcoded string (AD-13).
- Stage output is persisted and `stage` advanced by the Pipeline only, after the stage returns (AD-8, AD-20).

### Story 1.8: Local Speaker attribution and chronological merge

*Requirements: FR-21, FR-23 · Tier T0*

As a user,
I want every line of the transcript attributed to a speaker, with my own lines always correct,
So that I can read who said what without checking anything.

**Acceptance Criteria:**

**Given** both Streams have been transcribed
**When** the Transcript is assembled
**Then** Mic Stream Utterances carry the Local Speaker label and all Utterances appear in ascending start-time order


**And** each of the following holds:

- No Mic Stream Utterance is ever attributed to a Remote Speaker.
- The Local Speaker Label defaults to `Me` and is user-editable in Settings.
- This attribution involves no model inference and cannot be wrong.
- Utterances appear in ascending start-time order regardless of source Stream.
- Overlapping speech from both Streams is represented as separate Utterances, not merged or dropped — people talk over each other and the record should show it.
- Every Utterance in the Transcript carries exactly one Speaker Label.

**Implementation constraints:**

- Local Speaker attribution involves no inference and cannot be wrong (AD-11).
- Utterances reference a stable SpeakerLabelID, never a display name (AD-19).
- Overlapping speech from both Streams stays as separate Utterances — people talk over each other and the record should show it.

### Story 1.9: Heuristic metadata backend

*Requirements: FR-26, FR-28 · Tier T0*

As a user,
I want a title, tags and a summary generated on this machine with no model required,
So that every meeting gets a usable name even with Apple Intelligence switched off.

**Acceptance Criteria:**

**Given** a Transcript exists
**When** the Heuristic Backend runs
**Then** a title, 3-6 lowercase tags and a summary are produced deterministically in under 2 seconds for a 2-hour Transcript


**And** each of the following holds:

- No Meeting is ever left untitled; a fallback title derived from date, time and detected application is always available.
- Tags are a small set (target 3-6), lowercase and consistent enough to be usable for filtering across Meetings.
- Metadata generation runs entirely on-device.
- It runs with no downloaded assets and no Apple Intelligence.
- It is deterministic: the same Transcript yields the same Metadata, which makes it testable.
- It extracts tags by keyphrase salience, a summary by sentence selection, and a title from the strongest early keyphrase.
- It completes in under 2 seconds for a 2-hour Transcript.

**Implementation constraints:**

- Pure, dependency-free and deterministic — this is also the unit-test target (AD-12).
- Keyphrase salience for tags, sentence scoring for the summary, strongest early keyphrase for the title.
- No Meeting is ever left untitled; a date/time/app fallback title always exists.

### Story 1.10: Markdown Note output

*Requirements: FR-31, FR-32, FR-33 · Tier T0*

As a user,
I want one Markdown file per meeting in a folder I choose,
So that meeting notes live in the same plain-text world as the rest of my notes.

**Acceptance Criteria:**

**Given** a Meeting has Metadata and a Transcript
**When** the Note is written
**Then** exactly one valid UTF-8 Markdown file exists with parseable YAML frontmatter followed by Metadata then Transcript


**And** each of the following holds:

- The filename is stable, sorts chronologically, and is readable — date, time and a slug of the title.
- Filename collisions are resolved without overwriting an existing Note.
- The file is valid UTF-8 Markdown and opens correctly in a plain text editor and in Obsidian.
- Frontmatter includes title, date, start time, duration, participants (Speaker Labels), tags, Transcription Model, Metadata Backend, and whether the System Stream was captured.
- The YAML parses with a standard parser; titles containing colons or quotes do not break it.
- Tags are emitted as a YAML list so note tools can index them.
- Order is summary, then decisions, then action items, then the full Transcript.
- Empty sections are omitted rather than left as empty headings.
- Transcript entries show a timestamp and a Speaker Label, and are grouped so a single speaker's continuous speech is not fragmented line by line.
- Timestamps are relative to Session start and formatted so they can be scanned.

**Implementation constraints:**

- Atomic write: temp file in the destination, fsync, atomic replace (AD-10).
- NoteWriter is the only component that computes a Note filename, and stores it on the Meeting record (AD-18).
- Titles containing colons or quotes must not break the YAML.
- Empty sections are omitted rather than left as empty headings.
- Consecutive Utterances from one Speaker are grouped under a single label.


## Epic 2: Transcription Models and the Setup Surface

Make the app configurable and, crucially, verifiable. The user picks a model and gets it downloaded, and the Setup Checklist plus Test Playground let them confirm the whole chain works on their own machine before trusting it with a real meeting.

### Story 2.1: Main window shell and sidebar navigation

*Requirements: UX-DR4 · Tier -*

As a user,
I want one window with a grouped sidebar,
So that setup, settings and my meetings all live in a single place instead of scattered windows.

**Acceptance Criteria:**

**Given** I open Minutes from the menu bar
**When** the window appears
**Then** a NavigationSplitView shows grouped sidebar destinations and the selected pane renders in the detail area


**Implementation constraints:**

- MUST precede all other Epic 2 and Epic 5 stories — they are panes and have nowhere to render without this.
- Sidebar groups exactly as EXPERIENCE.md specifies: SETUP (Getting Started) - CONFIGURE (Transcription, Detection, General) - ACTIVITY (Meetings) (UX-DR4).
- Default destination is Getting Started on first launch and Meetings thereafter; selection persists across launches.
- Exactly ONE window ever exists. Opening from the menu brings it forward on the requested pane rather than creating a second (FR-5).
- Closing the window does not quit the app; it is menu-bar-resident.
- Each pane is a scrollable vertical stack of cards with headings OUTSIDE the card (UX-DR9).
- Panes fit a 13-inch display without scrolling in their default state and are fully keyboard navigable (UX-DR11).

### Story 2.2: Model catalogue and selection

*Requirements: FR-17 · Tier T1*

As a user,
I want to choose which Whisper model transcribes my meetings,
So that I can trade speed against accuracy for my own situation.

**Acceptance Criteria:**

**Given** I open the Transcription pane
**When** the model list renders
**Then** each row shows name, size on disk and a speed/accuracy character, with the active model unambiguous


**And** each of the following holds:

- The list states, per model, its relative speed, its relative accuracy, and its size on disk.
- The currently active model is unambiguous.
- The available list reflects what the transcription stack actually offers rather than a hardcoded list that can drift.
- A recommended default is pre-selected so a user can proceed without choosing.

**Implementation constraints:**

- List comes from WhisperKit.recommendedModels() offline and fetchAvailableModels() when online — never hardcoded (AD-13).
- Real identifiers are openai_whisper-prefixed; the published docs list bare names and is wrong.
- Default is openai_whisper-large-v3-v20240930_turbo_632MB.
- Speed guidance derived from a Test Playground measurement where one exists, labelled as an estimate otherwise.

### Story 2.3: Model download with determinate progress

*Requirements: FR-18 · Tier T1*

As a user,
I want a model downloaded with visible progress,
So that a 600 MB download is never indistinguishable from a hang.

**Acceptance Criteria:**

**Given** I select a model that is not present
**When** the download runs
**Then** progress is shown as a determinate proportion with bytes, and the model becomes active only on completion


**And** each of the following holds:

- Download progress is shown as a proportion, not an indeterminate spinner.
- A model already cached is used without any network access.
- A failed or interrupted download reports the failure and leaves no partial model that would later be loaded as valid.
- The UI states plainly that model download is the only time the app uses the network.

**Implementation constraints:**

- Determinate progress only — an indeterminate spinner is explicitly forbidden (FR-18).
- An interrupted download leaves no partial model that could later load as valid.
- The pane states once that model download is the only time the app uses the network.

### Story 2.4: Notes Folder selection

*Requirements: FR-34 · Tier T1*

As a user,
I want to choose where Notes are written,
So that meetings land in the notes repo I already use.

**Acceptance Criteria:**

**Given** I choose a folder
**When** the choice is stored
**Then** the folder persists across restarts and is writable without re-prompting


**And** each of the following holds:

- A default location is used if the user does not choose, so the app works before it is configured.
- The chosen folder persists across restarts and is re-accessible after restart without re-prompting.
- If the folder is missing or unwritable at write time, the failure is surfaced and the Note is retained so nothing is lost.

**Implementation constraints:**

- Stored as a security-scoped bookmark, not a path string.
- Preferences owns the single balanced start/stopAccessingSecurityScopedResource pair.
- A default location works before the user configures anything.

### Story 2.5: First-run setup and permission requests

*Requirements: FR-41 · Tier T1*

As a user,
I want to be walked to a working state on first launch,
So that I can start using the app without reading anything.

**Acceptance Criteria:**

**Given** I launch Minutes for the first time
**When** the window opens on Getting Started
**Then** microphone permission is requested with a reason, and the Notes Folder and model have working defaults


**And** each of the following holds:

- Microphone permission is requested with a clear explanation of why.
- The user is told that system-audio capture requires a separate macOS permission which will be prompted on first recording, and that declining it degrades to Mic-only (FR-7) rather than breaking the app.
- The Notes Folder and Transcription Model are set, each with a working default so the flow can be completed by accepting defaults.
- The app is usable immediately after setup with no restart.

**Implementation constraints:**

- Explains that system-audio capture is prompted by macOS on first recording and that declining degrades to Mic-only rather than breaking the app.
- The flow is completable by accepting defaults, and the app is usable immediately with no restart.

### Story 2.6: Setup Checklist with live-derived state

*Requirements: FR-46 · Tier T1*

As a user,
I want a checklist showing exactly what is and is not set up,
So that I can see what is left to do rather than a wall of green.

**Acceptance Criteria:**

**Given** I open Getting Started
**When** the Setup Checklist renders
**Then** satisfied rows show a dim non-interactive Done indicator and recede, and outstanding rows show an ordinal and a live action


**And** each of the following holds:

- Rows cover, at minimum: Transcription Model ready, microphone permission, system-audio capture verified, Notes Folder chosen.
- Each row states in one line why the item is needed — never a bare label.
- A satisfied row shows a non-interactive "Done" indicator and is visually de-emphasised; an outstanding row shows an ordinal and a control that performs or navigates to the fix.
- Row state is derived from live system state, not from a stored "setup completed" flag, so a permission revoked later shows as outstanding again.
- The checklist distinguishes required rows from optional ones; an optional row left undone never blocks the app or shows as an error.
- The pane states plainly when every row is satisfied.

**Implementation constraints:**

- Row state is derived from live system state on appearance and window focus — there is no stored setup-completed flag, so a permission revoked later shows outstanding again.
- Every row carries a one-line reason it exists; a subtitle running to two lines means the copy is wrong.
- Optional rows are titled '(Optional)' and never render as an error or block completion.
- Rows never reorder as they are satisfied.
- Follows DESIGN.md components.checklist-row and EXPERIENCE.md's five-row table.

### Story 2.7: Permission state visibility

*Requirements: FR-42 · Tier T1*

As a user,
I want to see the state of each permission the app needs,
So that I can fix a broken permission instead of guessing why recording failed.

**Acceptance Criteria:**

**Given** I open the Setup pane
**When** permission states render
**Then** microphone state is stated as fact and system-audio state is stated as inferred from the last capture


**And** each of the following holds:

- Microphone permission state is shown accurately.
- System-audio capture state is shown as *inferred* — from whether Capture has succeeded — because macOS exposes no API to query it. The UI must not claim certainty it cannot have.
- Where a permission is missing, Settings links to the relevant System Settings pane and explains what to do, including the reset command needed after a rebuild.

**Implementation constraints:**

- macOS exposes no API to query system-audio permission; the UI must not claim certainty it cannot have (FR-42).
- Where a permission is missing, link to the System Settings pane and surface the copyable reset command, naming rebuild-invalidates-consent as the likely cause.

### Story 2.8: Test Playground

*Requirements: FR-47 · Tier T1*

As a user,
I want a five-second test that proves the whole chain works,
So that I know Minutes can actually record a meeting before I rely on it.

**Acceptance Criteria:**

**Given** I click Start Test with audio playing
**When** the test runs
**Then** the Transcript appears alongside per-Stream audio presence, the model used, and measured transcription time with an extrapolation


**And** each of the following holds:

- A single control starts a short test Capture of both Streams and displays the resulting Transcript in-app.
- The result reports, separately, whether the Mic Stream and the System Stream each produced non-silent audio — this is the only reliable way to confirm system-audio capture works (§12), and it drives the corresponding Setup Checklist row.
- The test states which Transcription Model ran and how long transcription took, giving the user real throughput on their own machine rather than a generic claim (see §13 open question 1).
- A test run produces no Meeting and writes no Note; it never appears in the Library.
- The test reports a specific failure per stage — no audio captured, model missing, transcription failed — rather than a single generic error.
- The test is available at any time from Setup, not only on first run.

**Implementation constraints:**

- This is the product's only reliable system-audio permission diagnostic (AD-16, EXPERIENCE.md Permission Choreography).
- Live per-Stream level meters during the run are the diagnostic; a flat System meter is the answer.
- Failures are staged and named: no mic audio, no system audio, model missing, transcription failed — never one generic error.
- Produces no Meeting and writes no Note; must not appear in the Library.
- Tells the user to play something BEFORE they start, so a flat System meter is not a false negative.
- The measured timing feeds story 2.1's speed guidance and answers PRD open question 1.

### Story 2.9: Re-run onboarding

*Requirements: FR-48 · Tier T3*

As a user,
I want to re-run the onboarding flow,
So that I can revisit setup without hunting through panes.

**Acceptance Criteria:**

**Given** setup is already complete
**When** I choose Run Onboarding Again
**Then** the guided flow restarts without resetting preferences


**And** each of the following holds:

- A control in the Setup pane restarts the guided flow without resetting the user's existing preferences.
- Re-running is non-destructive: it does not delete Meetings, downloaded models, or Speaker Profiles.

**Implementation constraints:**

- Non-destructive: never deletes Meetings, downloaded models or Speaker Profiles.


## Epic 3: Meeting Detection

Remove the need to remember. Watch which applications hold the audio input device, offer to record when a Watched App takes it, stop when it lets go, and make it easy to be left alone.

### Story 3.1: Audio process enumeration and Watched App prefix matching

*Requirements: FR-11 · Tier T1*

As a user,
I want Minutes to notice which apps are using my microphone,
So that it can offer to record without me remembering.

**Acceptance Criteria:**

**Given** Slack or Teams takes the audio input device
**When** detection polls
**Then** the app identifies the application within 15 seconds


**And** each of the following holds:

- Joining a Slack huddle is detected within 15 seconds.
- Joining a Microsoft Teams call is detected within 15 seconds.
- Detection works when the app routes audio through helper processes rather than its main process — matching is by application identity, not by an exact process match.
- Detection works with a Bluetooth input device (AirPods), not only built-in and wired microphones.
- Releasing the input device is detected within 15 seconds.

**Implementation constraints:**

- MUST match by bundle-ID PREFIX. Teams exposes no bare com.microsoft.teams2 audio object — only .modulehost, .helper and .notificationcenter — so exact matching detects Teams never (AD-5, verified).
- Timer poll (~2s) is the source of truth; property listeners only shorten latency and are never the sole signal.
- Works with a Bluetooth input device; kAudioDevicePropertyDeviceIsRunningSomewhere is unusable because it always reports inactive for Bluetooth mics.
- Reads process and device properties only, never audio content (AD-6).

### Story 3.2: Debounced Detection Prompt

*Requirements: FR-12 · Tier T1*

As a user,
I want to be asked whether to record a detected meeting,
So that recording costs one click instead of a memory.

**Acceptance Criteria:**

**Given** a Watched App has held the input device for the debounce interval
**When** the Detection Prompt appears
**Then** it names the app and offers Record, Not now, and Never for that app, and starts nothing unless Record is chosen


**And** each of the following holds:

- The Prompt names the detected application.
- The Prompt offers Record and a decline, and starts nothing unless Record is chosen.
- An ignored Prompt expires without starting a Session.
- Brief input activity below the debounce threshold produces no Prompt, so notification sounds and device probes do not trigger it.
- At most one Prompt is shown per detected meeting; a Prompt is not repeated for a Session already declined.

**Implementation constraints:**

- An ignored Prompt expires and records nothing — silence is a decline, never a default yes.
- Brief activity below the debounce threshold produces no Prompt, so notification sounds and device probes do not trigger it.
- At most one Prompt per detected meeting; a declined meeting is not re-prompted during the same input session.
- Never for <app> must be on the notification itself, not only in Settings.

### Story 3.3: Accepting a Prompt starts a Session

*Requirements: FR-13 · Tier T1*

As a user,
I want accepting the prompt to start a full recording,
So that a detected meeting is captured exactly like a manual one.

**Acceptance Criteria:**

**Given** I click Record on a Detection Prompt
**When** a Session starts
**Then** both Streams are captured and the triggering application is recorded on the Meeting


**And** each of the following holds:

- The Session records both Streams per FR-6.
- The Session records which application triggered it, and the Note reflects it.
- Time between clicking Record and audio being captured is under 2 seconds.

**Implementation constraints:**

- Time from click to audio being captured is under 2 seconds.
- The notification action must not steal focus — the user is mid-conversation.

### Story 3.4: Auto-stop when the meeting ends

*Requirements: FR-14 · Tier T1*

As a user,
I want a detected meeting to stop recording when the meeting ends,
So that I do not end up with an hour of silence after the call.

**Acceptance Criteria:**

**Given** a Session started from a Detection Prompt is running
**When** the triggering app releases the input device
**Then** the Session stops within 30 seconds and runs the normal completion path


**And** each of the following holds:

- The Session stops within 30 seconds of the application releasing the input device.
- A manually started Session is never auto-stopped — only the user stops it.
- Auto-stop runs the same completion path as a manual stop, producing a Note.

**Implementation constraints:**

- A manually started Session is NEVER auto-stopped (FR-14).
- If input-release detection proves unreliable, a fallback is needed — PRD open question 8.

### Story 3.5: Suppression per app and globally

*Requirements: FR-15, FR-43 · Tier T2*

As a user,
I want to stop being asked about an app, or at all,
So that the feature never becomes a nag.

**Acceptance Criteria:**

**Given** I decline a Prompt with Never for this app
**When** detection continues
**Then** no further Prompts appear for that app while other Watched Apps stay active


**And** each of the following holds:

- A per-app suppression is offered at the point of declining, not buried in Settings.
- Suppressing an app prevents further Prompts for it while leaving other Watched Apps active.
- Detection can be disabled entirely in Settings, after which no Prompt appears and no audio-process polling occurs.
- Suppression choices survive an app restart.
- Each Watched App can be toggled independently.
- Disabling Detection stops all polling, verifiable by the absence of periodic audio-process enumeration.

**Implementation constraints:**

- Disabling Detection entirely stops all polling, verifiable by the absence of periodic audio-process enumeration.
- Suppression choices survive an app restart.
- Counter-metric SM-C1: prefer a missed huddle to a spurious prompt.


## Epic 4: Speaker Attribution

Turn the System Stream into named people. Diarization splits remote speakers, renaming fixes what it got wrong, and a rename is remembered so the same voice arrives pre-named next time.

### Story 4.1: Diarize the System Stream

*Requirements: FR-22 · Tier T1*

As a user,
I want remote participants separated into distinct speakers,
So that I can follow a multi-person conversation in the transcript.

**Acceptance Criteria:**

**Given** a System Stream has been transcribed
**When** diarization runs on it
**Then** Utterances receive Remote Speaker labels determined from the audio, entirely on-device


**And** each of the following holds:

- Diarization runs entirely on-device with no network access.
- A System Stream with a single speaker yields one Remote Speaker label, not several.
- The number of Remote Speakers is determined from the audio; the user is not required to state it in advance.
- Diarization failure degrades to a single `Speaker` label for the whole System Stream rather than failing the Meeting.

**Implementation constraints:**

- Diarization runs on the System Stream ONLY — never a mixed stream (AD-11).
- Speaker count is determined from the audio; the user is not required to state it.
- Failure degrades to a single Speaker label for the whole System Stream rather than failing the Meeting (AD-17).
- SpeakerKit.diarize() has never been executed — this story retires that risk.

### Story 4.2: Rename a Speaker Label

*Requirements: FR-24 · Tier T2*

As a user,
I want to rename a speaker label,
So that the transcript uses real names instead of Speaker 2.

**Acceptance Criteria:**

**Given** a Meeting has anonymous Remote Speaker labels
**When** I rename one
**Then** every Utterance with that label shows the new name and the Note is rewritten in place


**And** each of the following holds:

- Renaming updates every Utterance carrying that label, and the Note is rewritten in place.
- Renaming two labels to the same name merges them, which is the correct fix for one person split across two labels.
- A rename is applied without re-running transcription or Diarization.

**Implementation constraints:**

- Renaming edits a per-Meeting [SpeakerLabelID: String] map only; no Utterance is mutated (AD-19).
- Renaming two labels to the same name merges them — the correct fix for one person split across two labels.
- Applied without re-running transcription or diarization.
- Inline on the chip in the detail header, committed on Return, cancelled on Escape.

### Story 4.3: Speaker Profiles across Meetings

*Requirements: FR-25 · Tier T3*

As a user,
I want a named voice recognised in later meetings,
So that I do not name the same colleague every week.

**Acceptance Criteria:**

**Given** I have named a Remote Speaker in one Meeting
**When** a later Meeting contains that voice
**Then** the name is applied automatically and marked as inferred


**And** each of the following holds:

- After naming a Remote Speaker in one Meeting, a later Meeting containing that voice presents that name rather than an anonymous label.
- An automatically applied name is marked as inferred, so a wrong match is recognisable and correctable.
- A wrong automatic match can be corrected, and the correction updates the Speaker Profile rather than only the one Meeting.
- Speaker Profiles are stored locally and are never transmitted.

**Implementation constraints:**

- An auto-applied name is visibly marked inferred so a wrong match is recognisable and correctable.
- Correcting a wrong match updates the Speaker Profile, not just the one Meeting.
- Profiles are biometric-adjacent: stored locally, never transmitted, and deletable.
- Highest technical uncertainty in the PRD (open question 4). If unreliable, drop to v2; degrades to manual renaming.


## Epic 5: Meeting Library and Note Lifecycle

Give past meetings a home: find one, read it, fix what is wrong, retry what failed, and delete what should not be kept.

### Story 5.1: Meetings list

*Requirements: FR-36 · Tier T2*

As a user,
I want a list of my past meetings,
So that I can find a meeting from last week.

**Acceptance Criteria:**

**Given** I open the Meetings pane
**When** the list renders
**Then** meetings appear newest first with title, date, duration and participant chips, and remain responsive at 500+ meetings


**And** each of the following holds:

- Each row shows title, date, duration, and participant labels.
- A Meeting still transcribing is shown with that state; a failed one is shown as failed.
- The list remains responsive with at least 500 Meetings.

**Implementation constraints:**

- A meeting still transcribing shows that state; a failed one shows as failed.
- Empty state is one line of text — no illustration, no mascot.

### Story 5.2: Meeting detail view

*Requirements: FR-37 · Tier T2*

As a user,
I want to read a meeting inside the app,
So that I can check the transcript without opening a file.

**Acceptance Criteria:**

**Given** I select a Meeting
**When** the detail pane renders
**Then** Metadata, then summary/decisions/actions if present, then the Transcript with labels and timestamps


**And** each of the following holds:

- The Transcript is readable in-app with Speaker Labels and timestamps.
- The Note can be revealed in Finder and opened in the user's default Markdown editor.

**Implementation constraints:**

- Consecutive Utterances from one Speaker grouped under a single label.
- Reveal in Finder and Open in Editor both available.

### Story 5.3: Edit title and Speaker Labels from the Library

*Requirements: FR-38, FR-35 · Tier T2*

As a user,
I want to fix a meeting's title and speaker names from the library,
So that I can correct what the machine got wrong.

**Acceptance Criteria:**

**Given** I edit a Meeting's title
**When** the change commits
**Then** the Note is rewritten and no second Note file is created


**And** each of the following holds:

- Renaming a Speaker Label from the Library satisfies FR-24 and FR-25.
- Editing the title rewrites the Note per FR-35.
- The Note is rewritten to reflect the change without creating a second file.
- A title change that would change the filename either renames the file or leaves it stable — the behaviour is defined, not incidental, and never leaves two Notes for one Meeting.

**Implementation constraints:**

- NoteWriter renames the existing file and updates the stored filename in one operation (AD-18).
- The Note is a projection — hand edits to a Note are overwritten on in-app edit, and the UI must say so (AD-9).

### Story 5.4: Retry a failed transcription

*Requirements: FR-39 · Tier T2*

As a user,
I want to retry a transcription that failed,
So that a failure costs me a click, not a meeting.

**Acceptance Criteria:**

**Given** a Meeting's transcription failed
**When** I choose Retry
**Then** it transcribes from retained audio using the current model without re-recording


**And** each of the following holds:

- Retry is offered on failed Meetings only.
- Retry uses the retained audio (FR-19) and the currently selected Transcription Model.

**Implementation constraints:**

- Retry offered on failed Meetings only, and resumes from the last completed stage (AD-8).
- Absent when retention was set to delete-after-Note, with the row saying why.

### Story 5.5: Delete a Meeting

*Requirements: FR-40 · Tier T2*

As a user,
I want to delete a meeting and its audio,
So that deleting is a real privacy action, not a list-hiding one.

**Acceptance Criteria:**

**Given** I choose Delete on a Meeting
**When** the confirmation appears
**Then** it enumerates exactly what will be removed before removing it


**And** each of the following holds:

- Deletion states what will be removed before removing it.
- Deletion removes retained audio, so deletion is a real privacy action rather than a list-hiding one.
- Whether the Note file is also deleted is explicit in the confirmation, never a surprise.

**Implementation constraints:**

- Removes retained audio.
- Whether the Note file is also deleted is explicit in the confirmation, never a surprise.


## Epic 6: Resilience and Settings

Survive a working day. Degrade visibly instead of failing, keep recording through device changes, never lose audio, and expose the handful of preferences that decide whether the app stays installed.

### Story 6.1: Graceful degradation to Mic-only

*Requirements: FR-7 · Tier T1*

As a user,
I want recording to continue with my microphone alone when system audio is unavailable,
So that a declined permission costs me half the conversation, not all of it.

**Acceptance Criteria:**

**Given** system-audio capture is unavailable
**When** I start a Session
**Then** the Session starts successfully and tells me in the menu and the window that only the Mic Stream is captured


**And** each of the following holds:

- A Session starts successfully when system-audio permission has not been granted.
- The user is told, at start and in the menu, that only the Mic Stream is being captured — degradation is never silent.
- The resulting Note records that the System Stream was absent, so a transcript with no Remote Speakers is not mistaken for a monologue.

**Implementation constraints:**

- Degradation is never silent (FR-7, AD-17).
- The Note records that the System Stream was absent, so a transcript with no Remote Speakers is not mistaken for a monologue.
- Never block the start of a recording on a permission dialog — a meeting is happening.

### Story 6.2: Survive output device changes mid-Session

*Requirements: FR-8 · Tier T2*

As a user,
I want recording to survive switching to AirPods mid-call,
So that changing headphones does not cost me the meeting.

**Acceptance Criteria:**

**Given** a Session is running
**When** the default output device changes
**Then** the System Stream keeps capturing with a gap under 2 seconds


**And** each of the following holds:

- Connecting AirPods mid-Session keeps the System Stream capturing; any gap is under 2 seconds.
- Disconnecting the active output device likewise does not terminate the Session.
- Device changes are recorded in the Session log so an audio gap is explainable after the fact.

**Implementation constraints:**

- The aggregate device references a specific output UID and may need rebuilding — PRD open question 7.
- Device changes are recorded in the Session log so an audio gap is explainable afterwards.
- Teardown/rebuild follows AD-2's fixed ordering.

### Story 6.3: Long-Session durability and crash-safe audio

*Requirements: FR-9 · Tier T1*

As a user,
I want a three-hour meeting recorded without loss,
So that long meetings are exactly the ones worth recording.

**Acceptance Criteria:**

**Given** a Session runs for 3 hours
**When** I stop it
**Then** all audio is present, and memory use stayed flat rather than growing with duration


**And** each of the following holds:

- Audio is committed to disk incrementally during Capture, not buffered in memory until stop.
- Memory use during Capture stays flat over time rather than growing with duration (see NFR-4).
- If the app crashes or is force-quit mid-Session, the audio captured up to that point remains on disk and is recoverable into a Meeting.

**Implementation constraints:**

- Audio is committed to disk incrementally, not buffered until stop.
- If the app crashes mid-Session the captured audio remains on disk and is recoverable into a Meeting.
- The IOProc is real-time-safe: no allocation, no locks, no logging inside it.

### Story 6.4: Transcription failure retains audio

*Requirements: FR-19 · Tier T1*

As a user,
I want my audio kept when transcription fails,
So that a bad model download does not destroy a meeting.

**Acceptance Criteria:**

**Given** transcription fails
**When** the failure surfaces
**Then** the reason is shown, the audio is retained, and retry is available from the Library


**And** each of the following holds:

- The failure is surfaced to the user with a reason, not swallowed.
- Session audio is retained so transcription can be retried.
- Retry is available from the Library without re-recording.

**Implementation constraints:**

- No try? that discards a user-visible failure (AD-17).
- stage is left at the last completed value with a recorded reason (AD-20).

### Story 6.5: Serial processing queue

*Requirements: FR-20 · Tier T2*

As a user,
I want to record a new meeting while a previous one is still transcribing,
So that back-to-back meetings do not collide.

**Acceptance Criteria:**

**Given** a Meeting is transcribing
**When** I start a new Session
**Then** the new Session records and its processing is queued behind the first


**And** each of the following holds:

- Transcription requests are processed serially; two models never load simultaneously and contend for memory.
- A Session can be recorded while a previous Meeting is still transcribing.
- The queue is in-memory only and is discarded on quit; the recorded audio is not (FR-19), so a queued Meeting can still be transcribed later from the Library.

**Implementation constraints:**

- Serial processing; two models never load concurrently (AD-14).
- The queue is in-memory and discarded on quit; the audio is not, so a queued Meeting can be transcribed later from the Library.

### Story 6.6: Session status and window access in the menu

*Requirements: FR-4, FR-5 · Tier T2*

As a user,
I want the menu to tell me what is happening and get me to the window,
So that the menu bar is enough for everything routine.

**Acceptance Criteria:**

**Given** a Session is Recording
**When** I open the menu
**Then** elapsed time updates at least once per second and the stream status shows whether system audio is being captured


**And** each of the following holds:

- Recording shows elapsed time, updating at least once per second while the menu is open.
- Recording indicates whether the System Stream is being captured or only the Mic Stream.
- Transcribing shows a progress indication and which Meeting is being processed.
- The menu contains no more than 8 items in any single state; the menu stays scannable.
- Opening Meetings or Settings from the menu brings the single main window to the front, focused, on the requested pane — never a second window.

**Implementation constraints:**

- At most 8 items in any state; Start and Stop are never both present.
- Status lines are disabled items so VoiceOver reads them in menu order.
- Opening Meetings or Settings brings the single window forward on the requested pane — never a second window.

### Story 6.7: Audio retention control

*Requirements: FR-44 · Tier T2*

As a user,
I want control over whether recorded audio is kept,
So that I decide how much of my working day sits on disk.

**Acceptance Criteria:**

**Given** I open the General pane
**When** retention options render
**Then** keep-audio and delete-after-Note are explicit, with disk used shown and a way to clear it


**And** each of the following holds:

- The options are explicit: keep audio, or delete it once the Note is written.
- The default keeps audio, because FR-19 retry and FR-39 depend on it; the trade-off is stated in the UI.
- Deleting audio disables retry for those Meetings, and the UI says so.
- Disk used by retained audio is shown, with a way to clear it.

**Implementation constraints:**

- Default keeps audio because retry depends on it, and the trade-off is stated in the UI.
- Deleting audio disables retry for those Meetings and the UI says so.

### Story 6.8: Launch at login

*Requirements: FR-45 · Tier T2*

As a user,
I want Minutes to start at login,
So that a menu bar tool I have to launch by hand will not survive.

**Acceptance Criteria:**

**Given** I enable launch at login
**When** I reboot
**Then** Minutes is running in the menu bar


**And** each of the following holds:

- The setting takes effect without a restart and survives reboot.
- It is off by default; the app does not install itself into login items uninvited.

**Implementation constraints:**

- Off by default; the app does not install itself into login items uninvited.
- Takes effect without a restart.


## Epic 7: Metadata Intelligence

Improve the derived content where the machine allows it: use Apple's on-device model when it is available, pull out decisions and action items, and always record which backend produced what.

### Story 7.1: Foundation Models backend behind an availability check

*Requirements: FR-27 · Tier T3*

As a user,
I want better titles and summaries when Apple Intelligence is available,
So that the derived content improves on machines that can do it.

**Acceptance Criteria:**

**Given** the on-device foundation model is available
**When** Metadata is generated
**Then** the LLM Backend produces it as a typed structure rather than parsed free text


**And** each of the following holds:

- Backend availability is checked at run time, not assumed at build time.
- When the model is unavailable — including because Apple Intelligence is disabled — the Heuristic Backend runs instead and the Meeting still completes.
- Output is requested as a typed structure rather than parsed out of free text, so a malformed generation cannot corrupt a Note.
- A Transcript too long for the model's context is handled by summarising in parts and combining, not truncated silently.

**Implementation constraints:**

- Availability is checked at run time, not assumed at build time; expect .unavailable(.appleIntelligenceNotEnabled) on this host.
- Falls back to the Heuristic Backend with the Meeting still completing, and this is NOT surfaced as a warning — it is the expected path here (AD-12, AD-17).
- A Transcript too long for the context window is summarised in parts and combined, never silently truncated.
- Neither the framework availability nor the guided-generation shape has been verified at run time.

### Story 7.2: Decisions and action items extraction

*Requirements: FR-29 · Tier T2*

As a user,
I want decisions and action items pulled out of the transcript,
So that I can see what was agreed without re-reading the whole meeting.

**Acceptance Criteria:**

**Given** a Transcript contains decisions or commitments
**When** Metadata is generated
**Then** each extracted item references the timestamp it came from


**And** each of the following holds:

- Each extracted item references the timestamp it came from, so a reader can verify it against the Transcript.
- Absence is represented honestly — an empty section or none at all, never invented content.
- Action items name an owner where the Transcript identifies one, and omit the owner where it does not.

**Implementation constraints:**

- Absence is represented honestly — an empty section or none at all, never invented content.
- Action items name an owner where the Transcript identifies one, and omit it where it does not.
- Heuristic path uses cue phrases; LLM path uses the same typed structure.

### Story 7.3: Metadata provenance in the Note

*Requirements: FR-30 · Tier T1*

As a user,
I want every note to say which backend wrote its summary,
So that I can tell an inference from a keyphrase extraction.

**Acceptance Criteria:**

**Given** a Note is written
**When** I read its frontmatter
**Then** it names the Metadata Backend and the Transcription Model used


**And** each of the following holds:

- The Note's frontmatter identifies the Backend and the Transcription Model used.
- A reader can therefore tell whether a summary came from a language model or from keyphrase extraction — provenance is never ambiguous.

**Implementation constraints:**

- Provenance is never ambiguous (FR-30).
- Pairs with story 7.2's timestamp references so derived content is checkable against the record.

---

## Epic 8: Trust the List, See the State

*Increment 2 · Tier T4 · 6 stories · FR-49, FR-50, FR-51, FR-52, FR-53, FR-54 and the FR-40 amendment*

**Why this epic exists.** Epics 1-7 are built and running on the target Mac. Every story below came from the user operating that build, which makes this the first epic in the project grounded in observation rather than inference. Two of the six close defects the user found; the rest close gaps where a capability was built but left unreachable.

The epic has one theme, and it is worth naming because it explains the ordering: **the app knew things it did not show.** Speaker Profiles existed with no way to see them. The Metadata Backend was recorded in the Note but never in the app. Delete, retry and rename existed only behind a context menu. And the Meetings list reported state derived from the record rather than from reality, so it was confidently wrong twice. Stories 8.1 and 8.2 fix correctness; 8.3 to 8.6 fix reachability.

### Story 8.1: A Meeting's Note is verified against the folder

*Requirements: FR-53 · Tier T4*

As a user,
I want the app to notice when a note it claims to have written is not there,
So that the Meetings list and my notes folder tell me the same story.

**Acceptance Criteria:**

**Given** a Meeting recorded as complete with a note filename
**When** that file is absent from the Notes Folder currently in effect
**Then** the Meeting is shown as missing its note rather than as complete
**And** I can rewrite the note from the stored record without re-transcribing

**And** each of the following holds:

- A Meeting marked complete whose Note file is absent is shown as such, not as complete.
- Rewriting loses no Speaker Labels or edits held in the record, and runs no model.
- A Note deleted deliberately in Finder is not silently recreated — rewriting is a user action.
- The check never parses the Note; a missing Note is rewritten *from* the record, never inferred back *into* it.
- Changing the Notes Folder does not mark past Meetings broken; the check is against the folder in effect and its result is a display state, not a mutation.

**Implementation constraints:**

- Derive the missing-note condition on read. Writing it into `meeting.json` would make a transient filesystem condition permanent.
- AD-9 holds without exception: the record is the source of truth and the Note is a projection.
- Observed defect this closes: seven Meetings held `stage: written` with a filename while two files existed on disk. Nothing compared the two facts.

### Story 8.2: Refresh the Library from disk

*Requirements: FR-54 · Tier T4*

As a user,
I want a refresh that re-reads what is actually on disk,
So that deleting something in Finder does not leave the app showing a stale list.

**Acceptance Criteria:**

**Given** I changed the Meeting store or the Notes Folder outside the app
**When** I refresh the Library
**Then** every row's state is re-derived, including story 8.1's note check
**And** nothing is deleted, moved or rewritten as a side effect

**And** each of the following holds:

- A Meeting record removed outside the app disappears after a refresh rather than persisting until relaunch.
- A Note deleted outside the app is reflected after a refresh.
- Refresh is idempotent and destroys nothing: it changes what is displayed, never what is stored.
- A Meeting record whose payload cannot be read is surfaced as unreadable, not omitted.

**Implementation constraints:**

- The unreadable-record rule is the point of the story, not a detail. A permissive `try?` in the store's listing once dropped five Meetings from the UI while they sat intact on disk; a list that silently discards what it cannot parse is wrong without appearing wrong.
- Refresh must not become the only path to correctness. In-app changes keep updating themselves; this is a repair tool for out-of-band edits.

### Story 8.3: Delete meetings without hunting for a context menu

*Requirements: FR-40 (amended) · Tier T4*

As a user,
I want deleting meetings to be an obvious, repeatable action,
So that clearing out a handful of test recordings is not a puzzle.

**Acceptance Criteria:**

**Given** one or more Meetings selected in the Library
**When** I use the visible delete control or press the Delete key
**Then** one confirmation enumerates exactly what will be removed across the whole selection
**And** confirming removes the records and their retained audio

**And** each of the following holds:

- Deletion is reachable without discovering a context menu: a visible control, and the standard Delete key on a selection.
- Multi-select delete is confirmed once, and the confirmation states the count and whether Note files are included.
- The existing FR-40 guarantees are unchanged: audio is really removed, and Note deletion is explicit rather than a surprise.
- Discoverability does not weaken confirmation — a destructive action still asks.

**Implementation constraints:**

- Keep the context menu. This adds a discoverable path; it does not move the old one.
- The user did not find the existing delete at all, so the acceptance test is whether it is findable without being told.

### Story 8.4: See and curate remembered voices

*Requirements: FR-51 · Tier T4*

As a user,
I want to see which voices Minutes remembers and fix them individually,
So that a wrong match is correctable without waiting for a meeting that happens to contain that voice.

**Acceptance Criteria:**

**Given** Minutes has remembered one or more voices
**When** I open the remembered-voices list
**Then** each voice appears with the name it will apply, its sample count and when it last matched
**And** I can rename or forget any single entry

**And** each of the following holds:

- Every remembered voice is visible, so the user can tell what Minutes thinks it knows without recording a Meeting to find out.
- Each entry can be forgotten individually; "Forget all" remains but is no longer the only option.
- A rename applies to the Profile, so the next Meeting containing that voice uses the corrected name.
- The list states, where the data is shown, that Profiles never leave the Mac.

**Implementation constraints:**

- The data and operations already exist — name, centroid, sample count, updated-at, plus lookup / remember / forget-one / forget-all. This story is a surface over a built capability.
- A rename does not retroactively relabel written Meetings. That was not requested, and it would rewrite Notes the user may have edited by hand.
- This also makes §13 Q4 (does voice matching hold up across recordings?) answerable by observation rather than argument.

### Story 8.5: Elapsed time and a living recording indicator in the menu bar

*Requirements: FR-49; FR-50 (withdrawn increment 4) · Tier T4*

As a user,
I want to see how long I have been recording without opening the menu,
So that a running session is obvious at a glance.

**Acceptance Criteria:**

**Given** a Session is Recording
**When** I look at the menu bar with the menu closed
**Then** the elapsed time is readable and advances at least once per second
**And** the recording indicator is a steady solid dot *(amended increment 4: FR-50's pulse was withdrawn on use)*

**And** each of the following holds:

- The timer disappears the moment Recording ends, so the menu bar never implies a Session that is not running.
- Transcribing shows no timer — elapsed time answers "how much have I recorded", which is not a question about processing.
- ~~The pulse is confined to Recording; Idle and Transcribing do not animate.~~ **Nothing animates, in any state.**
- Recording stays identifiable without any animation: silhouette and tint carry the state (FR-2, NFR-7). This was already required of the pulse, which is why withdrawing it costs no information.

**Implementation constraints:**

- Cost is the design constraint. The menu bar label is re-rendered by the system, so drive the timer from one coalesced tick that stops dead when Recording ends — never leave a 1 Hz timer running while Idle (NFR-3).
- ~~Express the pulse as a bounded, slow opacity or scale cycle…~~ **Withdrawn in increment 4** on the user's instruction after living with it. The icon is one image per state, built once; §13 Q10 is retired unanswered and moot.
- FR-4's in-menu timer already ships and stays. This is the closed-menu case, which is a different requirement.

### Story 8.6: Say what writes the summaries, and let it be pinned

*Requirements: FR-52 · Tier T4*

As a user,
I want the app to tell me what produces titles and summaries,
So that I am not guessing whether an LLM is involved.

**Acceptance Criteria:**

**Given** I open the metadata settings
**When** the LLM Backend is unavailable
**Then** the pane names the active Backend and states the reason, not just the outcome
**And** I can pin the Heuristic Backend even when the LLM Backend is available

**And** each of the following holds:

- The active Backend is stated in plain language, and unavailability is explained rather than hidden.
- Pinning affects Meetings processed afterwards and does not silently rewrite Metadata already derived.
- Nothing in the pane implies a cloud model, a download or an API key, because none exist.

**Implementation constraints:**

- Verified at runtime on the target machine: `SystemLanguageModel.default.availability = unavailable(appleIntelligenceNotEnabled)`. The honest content of this pane there is that summarisation is deterministic keyphrase extraction, and §9.3 requires saying so.
- Amends FR-27: preferring the LLM Backend is a default, and an explicit user choice wins over availability.
- The risk to avoid is a settings pane whose mere existence implies a configurable LLM. Fewer controls, more explanation.

### Epic 8 FR Coverage

| FR | Tier | Story |
| --- | --- | --- |
| FR-49 | T4 | 8.5 |
| FR-50 | T4 | 8.5 |
| FR-51 | T4 | 8.4 |
| FR-52 | T4 | 8.6 |
| FR-53 | T4 | 8.1 |
| FR-54 | T4 | 8.2 |
| FR-40 (amendment) | T4 | 8.3 |

FR-40's original consequences remain covered by story 5.5; story 8.3 covers only the increment-2 amendment, so no FR is claimed by two stories.

---

## Epic 9: Summarisation You Choose and Can Trust

*Increment 3 · Tier T5 · 7 stories · FR-55 … FR-61*

**Why this epic exists.** The user asked what produced the summaries, found no setting, and learned the answer was keyphrase extraction — sentence selection dressed as a summary. Their instruction was specific: *"lets only enable that if we can actually use an llm for it… The user may supply an LMM key to get summaries, better titles etc."*, then, after review, *"Lets not rely on apple intelligence for this. But keep it as a possibitly… We could allow local download, or the key."*

Two things happened between the request and this epic, and both shape it. A **review** (`prds/…/review-llm-key-proposal.md`) found that a cloud key contradicts NFR-1 and NFR-6 outright and carries a consent problem an individual cannot solve for their colleagues — so the key is last, not first. A **spike** (`spikes/spike-local-llm-2026-08-31.md`) proved the local path works and found a hard prerequisite that is *currently unmet*: the Xcode Metal toolchain is uninstalled, and without it MLX cannot execute a single token.

The epic's theme is the inverse of Epic 8's. Epic 8 was *the app knew things it did not show*. This one is **the app must not pretend to a capability it does not have** — and when it lacks one, it must say which, why, and what would fix it.

**Ordering is load-bearing.** Story 9.1 ships alone and improves the product immediately. 9.6 must precede any download work. 9.7 is last because it is the only part that transmits anything.

### Story 9.1: A summary appears only when something real produced it

*Requirements: FR-55, FR-26 (amended) · Tier T5*

As a user,
I want no summary rather than a fake one,
So that what I read in a note is something I can act on.

**Acceptance Criteria:**

**Given** no summarising backend is available or selected
**When** a meeting's note is written
**Then** it contains the transcript, the title and the tags
**And** the summary, decisions and action items sections are absent entirely

**And** each of the following holds:

- Sections are omitted, not rendered empty with a heading, and never filled with sentences extracted from the transcript.
- Keyphrase extraction still produces the title and tags, which it does adequately.
- The meeting detail says why those sections are missing and links to where that is fixed.
- A meeting summarised earlier by a different backend keeps its summary. Changing the setting never retroactively strips or rewrites derived content.
- No meeting is ever left untitled — FR-26's title guarantee survives while its summary guarantee does not.

**Implementation constraints:**

- Ship this independently of every other story in the epic. It costs nothing, depends on nothing, and removes a misleading artefact the user is reading today.
- §9.3 already required that absence be represented honestly rather than as invented content. The extract summary was in breach and read convincingly enough to be believed, which is what made it worse than nothing.

### Story 9.2: Capability is a value with a reason and a remedy

*Requirements: FR-58 (foundation) · Tier T5*

As a developer,
I want a backend to report why it cannot run and what would fix it,
So that no part of the UI has to guess and no reason gets lost.

**Acceptance Criteria:**

**Given** any summarisation backend
**When** its readiness is queried
**Then** it returns `.ready`, `.needsDownload(bytes:)`, `.needsKey`, or `.blocked(reason:remedy:)`
**And** every readiness state in the UI maps to exactly one of those cases

**And** each of the following holds:

- `remedy` is structured enough to render as a shell command where the remedy is a command.
- Apple's backend distinguishes *Apple Intelligence is switched off* from *this device is ineligible*. Both are detectable at run time and only one is fixable.
- Capability is computed on demand and not cached across a pane appearance, so a prerequisite fixed outside the app is reflected without a relaunch.
- A `.blocked` backend can never be selected — the type makes the invalid state unrepresentable rather than relying on a UI guard.

**Implementation constraints:**

- AD-22. This story exists because `isAvailable() -> Bool` was adequate for one optional backend and is not adequate for three.
- Do this before 9.3: the pane cannot be built honestly on top of a Bool.

### Story 9.3: Backend precedence is one pure function

*Requirements: FR-57, FR-52 (amended) · Tier T5*

As a user,
I want to know which backend will actually run for my next meeting,
So that two settings can never quietly disagree.

**Acceptance Criteria:**

**Given** a user selection and the current capabilities
**When** the app decides what will summarise the next meeting
**Then** one pure function returns the backend and the reason
**And** the pane displays exactly what that function returned

**And** each of the following holds:

- The order is: explicit user selection if ready; else the first ready backend in a fixed preference order; else no summariser.
- The pane states which backend will run for the *next* meeting, which differs from the selection whenever a selection has become unavailable.
- When a selection is impossible, the pane says so and says what will happen instead — it never silently substitutes.
- The function is unit-tested over every combination of selection and capability, including all-blocked.

**Implementation constraints:**

- AD-23. Increment 2's FR-52 created a setting that could disagree with availability; a third backend would have made the ordering undocumented. The review caught this before it shipped.

### Story 9.4: The Summaries pane

*Requirements: FR-56 · Tier T5*

As a user,
I want to compare the ways this app can summarise, the way I compare transcription models,
So that I can pick one knowing what it costs and what it needs.

**Acceptance Criteria:**

**Given** the Summaries pane
**When** I read it
**Then** three families are grouped under headings: on this Mac built in, on this Mac downloaded, somewhere else
**And** each row states what it is for before it states anything technical

**And** each of the following holds:

- Row anatomy matches the Transcription pane's model row. A second visual language for the same job is a defect.
- Each row carries provider, technical identifier, cost (disk size or per-meeting estimate) and readiness.
- No two rows render with the same display name — the increment-1 defect where 22 model IDs collapsed into 12 indistinguishable names must not recur.
- The downloadable list is built from a live registry at run time, never hardcoded.
- Selecting an uninstalled entry offers installation and does not silently select something else.
- A blocked row shows its reason where a button would be, and is not selectable.

**Implementation constraints:**

- The user asked for this pane to be "similar to the model selection for transcription", so shared anatomy is a requirement rather than a convenience.
- AD-13 extended: the spike found `Qwen3.5`, `Qwen3.6` and `Qwen3.8` conversions all live on `mlx-community`. A list written from memory would have been wrong the day it was written.

### Story 9.5: A local model, downloaded and run on this Mac

*Requirements: FR-60 (local half), FR-61 · Tier T5*

As a user,
I want a real summary from a model on my own machine,
So that I get one without depending on Apple Intelligence or sending anything away.

**Acceptance Criteria:**

**Given** a curated local model and an installed prerequisite
**When** I choose it
**Then** it downloads with determinate progress showing bytes and percentage
**And** it summarises a meeting entirely on this Mac

**And** each of the following holds:

- Download progress is determinate. The registry reports continuous progress, so an indeterminate spinner would discard information the app already has.
- A failed or cancelled download leaves no partial model that could later load as valid.
- Duration is shown as measured on this Mac, or as not measured yet — never an estimate presented as a measurement.
- The transcription model is unloaded before the summarisation model loads; the two are never resident together.
- A long transcript is chunked and combined rather than truncated, using the contract FR-27 already defines.
- Any failure — model load, out of memory, timeout — still writes the note with transcript, title and tags, and records the failure.
- A failed summarisation is retryable without re-transcribing.
- The note's frontmatter names the specific model that produced its metadata.

**Implementation constraints:**

- AD-25: one download mechanism and one storage root for both kinds of model. The spike verified `HubApi(downloadBase:)` honours an explicit root, so this is configuration rather than a fight with the library.
- AD-26: memory is the binding constraint. A 4-bit 9B model is roughly 6 GB resident plus KV cache that grows with transcript length; a two-hour meeting is the case to bound on 24 GB.
- Verified API shape: `LLMModelFactory.shared.loadContainer(hub:configuration:progressHandler:)` → `container.perform { ctx in }` → `ctx.processor.prepare(input:)` → `MLXLMCommon.generate(input:parameters:context:)` returning an `AsyncStream` of chunks.
- **Quality and speed are unmeasured.** The spike could not generate a token. No throughput or quality figure may be asserted until measured on real audio.

### Story 9.6: Prerequisites are detected before anything is downloaded

*Requirements: FR-58 · Tier T5*

As a user,
I want to be told my machine cannot run something before I download three gigabytes,
So that a missing prerequisite costs me a sentence instead of twenty minutes.

**Acceptance Criteria:**

**Given** the Metal toolchain is not installed
**When** I open the Summaries pane
**Then** every local model row is blocked, with the reason and the exact command that fixes it
**And** no download is offered

**And** each of the following holds:

- The remedy is specific enough to paste: `xcodebuild -downloadComponent MetalToolchain`, not "install the Metal toolchain".
- Apple's row states *Apple Intelligence is switched off* and where to turn it on, distinctly from *this device is ineligible*.
- Prerequisite state is re-read when the pane appears, so fixing it outside the app needs no relaunch.
- The shipped app bundle contains the metallib. A machine where the build succeeded must not hit the spike's runtime error.

**Implementation constraints:**

- AD-27, and this is measured rather than hypothetical: `xcodebuild -showComponent MetalToolchain` reports `uninstalled` on the target machine right now, and MLX fails with `Failed to load the default metallib`.
- Binds the build as well as the app: `Scripts/build-app.sh` must copy SPM resource bundles into `Minutes.app/Contents/Resources/`, which it currently does not do.
- **Must land before story 9.5's download work.** Reversing the order means shipping the exact failure this story prevents.

### Story 9.7: A remote model, with a key and consent per meeting

*Requirements: FR-59, FR-60 (remote half) · Tier T5*

As a user,
I want the option of a better summary from a remote model,
So that I can choose it deliberately, for one meeting at a time, knowing what leaves my Mac.

**Acceptance Criteria:**

**Given** a saved key
**When** a meeting could be summarised remotely
**Then** I am asked for that meeting specifically, and told the recipient, the transcript length, the estimated cost, and the participants whose speech it contains
**And** nothing is sent unless I agree

**And** each of the following holds:

- Entering a key does not enable sending. Configuring is not consenting, and the copy says so.
- There is no "always send" affordance. A per-meeting decision that can be permanently switched off is not a per-meeting decision.
- Audio is never transmitted. Neither are speaker profiles. Only transcript text.
- The key lives in the Keychain, never in preferences, the notes folder or a log, and is never rendered back after saving.
- Removing the key stops all remote capability immediately and leaves existing summaries and their provenance untouched.
- An empty or near-empty transcript is never sent — a silent recording must not become a paid request.
- Estimated cost is shown before the request; a running total of spend is visible in the pane.
- Any failure — unreachable, 401, 429, quota, timeout — still writes the note with transcript, title and tags, and records the failure. The note is never blocked on a network call.
- The note names the provider and model that produced its metadata, and a note written by one backend is never relabelled by a later setting change.

**Implementation constraints:**

- AD-24: one chokepoint whose input type cannot express audio, a file URL or a speaker profile, so "audio never leaves" is enforced by the signature rather than by review.
- **Last in the epic, and genuinely optional.** Build it only if story 9.5's measured quality proves insufficient.
- `[NOTE FOR PM]` The reviewer's consent finding is recorded, not resolved: in an EU employment context an individual cannot establish a lawful basis for sending colleagues' speech to a third-party processor on their behalf. The product can make the act explicit, per-meeting and off by default. It cannot make it lawful. If an employer-approved vendor under a data processing agreement exists, that is the endpoint to configure — and PRD §13 Q17 leaves open whether this story should ship at all.

### Epic 9 FR Coverage

| FR | Tier | Story |
| --- | --- | --- |
| FR-55 | T5 | 9.1 |
| FR-56 | T5 | 9.4 |
| FR-57 | T5 | 9.3 |
| FR-58 | T5 | 9.2 (foundation), 9.6 (surface) |
| FR-59 | T5 | 9.7 |
| FR-60 | T5 | 9.5 (local), 9.7 (remote) |
| FR-61 | T5 | 9.5 |

FR-58 and FR-60 are each split across two stories on purpose: FR-58's capability *type* must exist before its *presentation* can be honest, and FR-60's local and remote halves are separated so the remote half can be dropped without losing the local one. Amended requirements (FR-26, FR-52) stay owned by their original stories; the amendments are covered here.

---

## Epic 10: Knowing Which Voice Is Yours

*Increment 4 · Tier T6 · 7 stories · FR-62 … FR-65, plus the FR-21, FR-25 and FR-46 amendments*

**Why this epic exists.** The user recorded their first real meeting: an eight-person Slack huddle, taken at a desk with two colleagues talking beside them. The app performed correctly and the result was nearly useless. It separated the voices on the microphone — `In-room 1`, `In-room 2` — and it refused to say which was the user, because AD-11 forbids claiming an identity the audio does not support. 723 of 1501 transcript words were the neighbouring conversation, and 14 utterances the diarizer could not place at all fell through to a default and printed as the user's own words.

That default is fixed and is now `In-room, unidentified`, which is honest. **Honest is not the same as useful.** Separation without identification is half an answer, and the missing half cannot be supplied by the mechanism the PRD already had: FR-25 learns a voice from a rename, a rename needs a correct label to start from, and several voices on one microphone provide none. There is nothing to rename that is known to be you.

This epic replaces the guess with a measurement. The user records their own voice once; the app compares it against the in-room voices of every later meeting.

**What happened before any story was written, and why it matters.** The threshold that decides a match had been `0.45` since FR-25 shipped, with a comment admitting it was chosen rather than measured. Five real meetings had written per-speaker centroids to disk, so it was measurable, and it was measured (`spikes/calibration-speaker-threshold-2026-09-01.md`): the same in-room voice lands 0.058–0.248 apart across four independent recordings, different in-room voices in one meeting stay 0.596 and above. The calibrated value is **0.35**. Two apparent counter-examples turned out to be one person heard on both streams — a colleague in the room who was also on the huddle — which is the embedding working, not failing.

**Ordering is load-bearing.** Story 10.1 is the measurement and ships alone, improving FR-25 today with no enrolment in sight. 10.2 is the port, and 10.3 cannot be built honestly without it. 10.4 is the point of the epic. 10.5 through 10.7 are the surfaces, and the epic is **not shippable without 10.6** — a stored fingerprint the user cannot see or delete breaches PRD §9.1.

**What this epic explicitly does not build**, because each was considered and rejected: automatically excluding in-room voices from the note (a conference room full of participants is the normal case; the per-meeting Exclude control is the whole answer); a Voice Isolation prompt or nudge (it works, and it is macOS-only, and AD-28 forbids the mechanism depending on it); auto-muting the microphone when the far end speaks (it would have helped in that huddle and it fails exactly when the user is the one talking); and any user-facing dial for a threshold, a voice-activity parameter or a speaker count.

### Story 10.1: One calibrated threshold, and the measurement that produced it

*Requirements: FR-65 (the calibration half), FR-25 (amended) · Tier T6*

As a user,
I want the number that decides whether two recordings are the same person to have been measured,
So that a name arriving automatically is a judgement I can trust rather than someone's guess.

**Acceptance Criteria:**

**Given** the speaker-matching threshold
**When** a voice is compared against a stored profile
**Then** the constant used is 0.35, not 0.45
**And** the measurement and date that produced it are recorded at its declaration, with a path to the report

**And** each of the following holds:

- The threshold lives in exactly one place. It is not in `Preferences`, not in `UserDefaults`, and not reachable from any pane.
- The ambiguity margin story 10.4 needs — 0.10 — sits beside it, from the same measurement.
- A test verifies the constants are what the calibration concluded, so a later edit by opinion fails rather than passes quietly.
- A calibration test reads the real meeting centroids on this machine when they are present and skips cleanly when they are not. It never copies a centroid into the repository: those are biometric-adjacent data belonging to the user's colleagues, and PRD §9.1 keeps them on the machine that recorded them.
- The measured limit is recorded alongside the number, not hidden: for Remote Speakers the two populations touch and no threshold separates them, so remote matching stays a correctable inference.

**Implementation constraints:**

- AD-31, marked `[ADOPTED]` — a measured property of this embedding on this data, not a preference.
- **Ship this independently of everything else in the epic.** It changes one constant and improves FR-25's behaviour today, with no enrolment anywhere near it.
- Do not assert a figure this story did not measure. Every number in the report came from files on disk; none is extrapolated.

### Story 10.2: A voice fingerprint is a port and a comparison, not a framework call

*Requirements: FR-62 (foundation), FR-64 (storage) · Tier T6*

As a developer,
I want voice identity to sit behind a port with the comparison in pure code,
So that the one thing the user asked to stay portable does not quietly acquire an Apple dependency.

**Acceptance Criteria:**

**Given** the identification path
**When** it is compiled
**Then** the comparison code depends on `Foundation` alone and names no Apple type
**And** the embedder behind the port may be as platform-specific as it likes

**And** each of the following holds:

- The port takes audio and returns a fixed-length fingerprint plus an identifier naming the producer.
- The comparison lives in Core, operates on `[Float]`, and is unit-tested without audio hardware, without a model, and without a diarizer.
- A stored fingerprint carries its producer identifier and its dimension. A comparison across producers or dimensions returns **no information** — not a large distance and not a non-match, because collapsing "cannot say" into "no match" turns an embedder swap into a permanent silent failure.
- The store gains the enrolled profile as a *kind* of profile rather than a second store. `SpeakerDirectory` is reused; nothing is duplicated.
- The persisted profile type gets a hand-written decoder using `decodeIfPresent` with defaults. Swift ignores a property's default when the key is absent and throws `keyNotFound` instead, which is exactly how adding one field to `Meeting` silently orphaned five real recordings.
- An older `speakers.json` written before this story loads without error, with the new fields defaulted. There is no migration step and no schema version.
- The enrolled profile is excluded from the passive FR-25 match, so it can never apply a name to a voice.

**Implementation constraints:**

- AD-28, AD-29, AD-30. The mechanical test for AD-28 is that the identification path compiles against `Foundation` alone — check it, do not assume it.
- No new dependency. `SpeakerKit.DiarizationResult` already exposes `nearestSpeakerCentroid(to:)` and `centroidCosineDistance(between:and:)` through the already-linked `argmax-oss-swift` 1.1.0.
- Do this before 10.3. A recorder built on a framework call rather than a port would have to be rewritten to satisfy AD-28, and the rewrite is the expensive kind.

### Story 10.3: Record twenty-five seconds and store a fingerprint

*Requirements: FR-62 · Tier T6*

As a user,
I want to record my own voice once,
So that Minutes has something to recognise me by.

**Acceptance Criteria:**

**Given** microphone permission and nothing else — no model download, no network, no summarisation backend
**When** I record a sample
**Then** a fingerprint is stored on this Mac
**And** the sample audio is deleted in the same operation

**And** each of the following holds:

- **Nothing is written until the fingerprint exists.** A cancelled recording, a failed one, and one that never started are indistinguishable on disk.
- The audio is deleted on every exit path including failure and cancellation — a `defer`, not a happy-path cleanup. It never enters a Meeting directory, never becomes a Meeting record, and never reaches the Notes Folder.
- Only the Mic Stream is captured. The System Stream is never opened, so enrolment cannot trigger the system-audio permission and cannot record the far end.
- The result reports measurements, not a verdict: seconds of speech found, and how many voices were found.
- A sample containing more than one voice is **refused, with that reason stated**. A fingerprint of two people would put a colleague's name on the user's words for months, and a second attempt costs twenty-five seconds.
- Failures are staged and named: permission missing · nothing was said · more than one voice · too short. Never one generic error.
- Re-recording **replaces** the fingerprint rather than averaging into it, and no history of previous samples is kept.
- Enrolment produces no Meeting and writes no Note, and never appears in the Library.

**Implementation constraints:**

- AD-32. The deletion-on-every-path rule is the one thing in this story that is invisible when broken, so it is the one thing to test explicitly rather than eyeball.
- Follow `TestPlayground`'s shape — it already records, reports and cleans up, and it is the precedent the UX spine names.
- Embedding runs on the existing ML serial executor, so an enrolment during an active transcription queues rather than contending for memory.

### Story 10.4: The enrolled voice decides which voice on the microphone is the user

*Requirements: FR-63, FR-21 (amended) · Tier T6*

As a user,
I want my own lines under my own name when I am in a room with other people,
So that a meeting where colleagues sat beside me is still a record of what I said.

**Acceptance Criteria:**

**Given** several voices on the Mic Stream and an enrolled fingerprint
**When** attribution runs
**Then** the in-room voice matching the fingerprint is the Local Speaker
**And** the others stay anonymous in-room voices

**And** each of the following holds:

- With no enrolled fingerprint, behaviour is **byte-for-byte** what it is today. This is a test, not an aspiration.
- A match is accepted only when it is within the threshold **and** unambiguous — no other in-room voice within the margin of it. Two voices that close is a diarizer split or a genuine ambiguity, and either way nothing is claimed.
- Place is untouched. A Mic Stream utterance can still never become a Remote Speaker, and a System Stream utterance can never become an in-room one.
- Mic Stream speech no diarized span covers, with several voices present, stays unidentified in-room speech. Enrolment does not change that, and must not.
- No stage is added to the pipeline. The lookup happens inside the existing diarize stage, and its result reaches attribution as one value — attribution stays a pure function of its arguments and gains no dependency on the store.
- The Meeting records that the Local Speaker was identified by enrolment, and how close the match was.
- Enrolment draws no line between a participant and a bystander. Both are "not the user", and deciding which non-user voice belongs in the note stays the per-meeting Exclude control's job.
- A meeting on disk with several in-room voices is used as the test case, not an invented fixture.

**Implementation constraints:**

- AD-11 as amended, AD-30. `Pipeline.assign` gains one parameter and nothing else changes in it.
- The structural rules are the product's oldest guarantee. A change here that makes the no-enrolment path behave differently is a regression even if every new test passes.

### Story 10.5: Your voice, as a row in Getting Started

*Requirements: FR-62 (surface), FR-46 (amended) · Tier T6*

As a user,
I want to find this where I found everything else about setting the app up,
So that I do not have to know the feature exists to discover it.

**Acceptance Criteria:**

**Given** the Getting Started pane
**When** I read the checklist
**Then** there is a row for my voice, marked optional, using the existing row anatomy
**And** a card below it records and reports, in the Test Playground's shape

**And** each of the following holds:

- The row is the same component as every other row: leading indicator, title, one-line subtitle, trailing control. **A second onboarding style is a defect.**
- Row state is derived live from whether a fingerprint exists, never from a stored completion flag.
- The subtitle says what the row buys, not what it is: that Minutes can tell which voice in the room is the user instead of leaving it unattributed.
- The row is last, so no shipped row is renumbered. Position in the checklist is stable by rule.
- The card shows **one** level meter, labelled Microphone. Not two — enrolment never opens the System Stream, and a System meter would misdescribe what is being read.
- Before the recording starts, the card says how long it takes, what is stored, and that the recording itself is deleted.
- The card asks the user to let nobody else talk, because a two-voice sample is refused.
- The result is `{components.fact-chip}`s — seconds of speech, voices found — and a `Re-record`. No score, no waveform portrait, no "good sample!".
- The optional row never renders as an error and never blocks the pane's "Setup complete" statement.

**Implementation constraints:**

- `EXPERIENCE.md` § *Voice enrolment* and § *Checklist row*; `DESIGN.md` `components.enrolment-card`. The card's parent shape is the Test Playground card, deliberately.
- The pane already recomputes row state on appearance and on window focus. Use that; do not add a second refresh path.

### Story 10.6: The stored voice is visible, distinguishable and deletable

*Requirements: FR-64 · Tier T6*

As a user,
I want to see the fingerprint the app is keeping of me and remove it in one click,
So that the most sensitive thing this app stores is something I can look at and undo.

**Acceptance Criteria:**

**Given** an enrolled fingerprint
**When** I open the remembered-voices list in General
**Then** it appears there, marked as mine, with one control that deletes it

**And** each of the following holds:

- FR-51's list keeps working unchanged. The enrolled entry is the **same row** with a different glyph and a badge — not its own section, not its own card.
- It sorts first. It is the only entry that is the user, and the only one whose deletion changes how future meetings are attributed.
- It carries provenance: how much audio produced it, and when. A remembered colleague keeps showing meetings-confirmed and last-heard.
- It offers no rename. The user's display name comes from "Your name in transcripts" in the same pane, because two places to edit one name is a defect.
- Deleting it returns attribution to pre-enrolment behaviour for meetings processed afterwards. Meetings already written keep their labels, which is FR-51's existing rule and is stated in the UI because a user deleting a fingerprint may reasonably expect otherwise.
- `Forget all` removes it too, and its confirmation **names it separately** from the count of colleagues. "3 voices will be forgotten" hides the one that matters.
- The card states, where the data is shown, that none of it leaves the Mac.
- A relaunch shows the same entry with the same provenance. The fingerprint survives a restart or the feature does not exist.

**Implementation constraints:**

- `DESIGN.md` `components.voice-row`; `EXPERIENCE.md` § *Remembered voices row*.
- **The epic is not shippable without this story.** A stored fingerprint the user cannot see or delete breaches PRD §9.1, and §9.1 is not a nice-to-have in a product whose entire claim is that nothing leaves the machine.

### Story 10.7: The identification says what it rests on

*Requirements: FR-65 (the disclosure half) · Tier T6*

As a user,
I want to know whether my name on a line is a fact or a measurement,
So that I can tell the difference between something that cannot be wrong and something that can.

**Acceptance Criteria:**

**Given** a meeting whose Local Speaker was identified by enrolment
**When** I open its detail
**Then** it says so, and says how close the match was
**And** a meeting whose Local Speaker was structural says that instead

**And** each of the following holds:

- The two cases look identical in the transcript and must not look identical in the detail. One is structural and cannot be wrong; the other is a measurement.
- The measured distance is shown as a fact. It is never editable, and no control anywhere sets it — a number the user can check but not set is honesty, not a dial.
- A wrong identification is corrected with the rename and Exclude controls that already exist. No new correction mechanism is added.
- An honest refusal renders as ordinary in-room attribution with no warning glyph. The app declining to guess is the product working, and dressing it as a failure pushes the user toward wanting the guess back.
- VoiceOver states the basis, not just the name: recognised from the enrolled voice, or the microphone held a single voice. The distinction is the honesty guarantee, so it cannot be visual-only.

**Implementation constraints:**

- `EXPERIENCE.md` § *Identity, claimed or refused* is the contract for all four situations, including the two that predate this epic.
- PRD FR-65 forbids a *settable* threshold. Displaying a measured distance is permitted on the same grounds as the Test Playground's throughput figure, and the distinction is worth keeping straight in review.

### Epic 10 FR Coverage

| FR | Tier | Story |
| --- | --- | --- |
| FR-62 | T6 | 10.2 (foundation), 10.3 (the act), 10.5 (the surface) |
| FR-63 | T6 | 10.4 |
| FR-64 | T6 | 10.2 (storage), 10.6 (the surface) |
| FR-65 | T6 | 10.1 (the calibration), 10.7 (the disclosure) |

Amended requirements stay owned by their original stories — FR-21 by 1.8, FR-25 by 4.3, FR-46 by 2.6 — and the amendments are covered here: FR-21 by 10.4, FR-25 by 10.1 and 10.2, FR-46 by 10.5.

FR-62, FR-64 and FR-65 are each split across stories on purpose, and in each case the split separates a *mechanism* from its *surface* so that the mechanism can be verified before anything is drawn on top of it. FR-65's split is the sharpest: its calibration half (10.1) ships first and alone, and its disclosure half (10.7) ships last, because there is nothing to disclose until 10.4 makes a claim.

---

## Epic 11: Works on a Mac That Is Not Mine

**Why this epic exists.** The app has run on exactly one machine for its whole
life, and a colleague is about to install it. Reading the code with that question
in mind found a class of defect no test could have caught and no amount of use on
the author's Mac would ever surface: the failures that only happen when the
environment differs. Every item below was verified at a file and line, not
inferred from behaviour.

The headline is the smallest change and the largest one. `AppState.lastError` is
written on four failure paths and read by one command-line file. A colleague who
declines the microphone prompt gets no explanation from the interface at all —
while the correct, actionable sentence already exists in `MinutesError` and is
simply unreachable. The app has been unable to say why it failed for its entire
existence, and it never mattered until now.

Two findings are worse than cosmetic. The evidence that system-audio capture
worked accepts a quarter second of silence as proof, which makes FR-42's entire
permission story vacuous on any machine where the tap quietly fails. And every
launch can delete `~/Documents/huggingface` in full — safe on one machine,
data loss on a colleague's.

**Ordering is load-bearing.** 11.1 first: an app that cannot say why it failed
should not be handed to anyone. 11.6 (version) is a hard prerequisite for Epic
12, because you cannot ship a second release when every build claims to be 1.0.

**What this epic explicitly does not build:** a crash reporter or any telemetry
(PRD §9.1 governs, and the app has no network path at run time); a support-bundle
uploader; retries around permission failures, which hide the problem the user
needs to see.

### Story 11.1: A failure states its reason and its remedy

*(tier T1 · FR-66)*

As someone using Minutes for the first time on my own Mac, when recording does
not start, I want the app to tell me why and what to do, so that I am not left
guessing whether the app is broken or I am.

**Acceptance Criteria:**

**Given** any failure that prevents a recording from starting
**When** the user has attempted to start one
**Then** the reason and its remedy appear in the interface, not only in the log
**And** the text is `MinutesError`'s existing description and recovery sentence

**And** each of the following holds:

- Both the window and the menu bar surface it. The menu is where the user just
  clicked, so a failure that is only visible in a window they have not opened is
  still silent.
- The four paths in `SessionCoordinator` that set `lastError` are all covered:
  permission denied, persistence failure, a capture error, and an unavailable
  microphone.
- A Mac with no input device attached produces a stated reason, not a no-op. The
  author's machine has a built-in microphone, so this path has never run.
- The error clears when a subsequent attempt succeeds. A stale error is its own
  bug.
- The remedy is actionable without leaving the app to search: where a System
  Settings pane is the answer, the app offers to open it.

**Implementation constraints:**

- `MinutesError`'s strings are already correct and already reviewed. Surface
  them; do not write new ones.
- No new error type. This is a wiring story, and it should read as one.

### Story 11.2: Evidence of capture is signal, never duration

*(tier T1 · FR-67)*

As someone whose meeting notes depend on system audio being captured, I want the
app's claim that it worked to rest on hearing something, so that a green tick
means the thing it says.

**Acceptance Criteria:**

**Given** a completed capture on either stream
**When** the app reports whether audio was produced
**Then** the answer is derived from signal in the samples
**And** elapsed duration is never sufficient on its own

**And** each of the following holds:

- `SystemTapCapture.stop()`'s `|| d > 0.25` clause is gone. Frames are written
  whether or not anything is playing, so duration proves only that the tap ran.
- `TestPlayground`'s `micHadAudio` stops meaning "the file exists".
- The threshold that decides "signal" is stated with the reasoning for its value,
  and is not a setting.
- A test constructs a silent buffer of ample duration and asserts the answer is
  false. That test would have failed before this story.
- Every sentence that currently asserts capture succeeded — the checklist row,
  the Test Playground chip, `--doctor` — is true after this change or is
  reworded.

**Implementation constraints:**

- FR-42 rests entirely on this: macOS offers no API to query system-audio
  permission, so measured evidence is the only evidence available. A vacuous
  measurement is worse than an admitted unknown, because it is indistinguishable
  from success.
- AD-36 governs.

### Story 11.3: The app never removes a directory it did not create

*(tier T1 · FR-68)*

As someone who keeps machine-learning models in my home folder, I want Minutes to
leave my files alone, so that installing it costs me nothing I did not agree to.

**Acceptance Criteria:**

**Given** a `~/Documents/huggingface` directory containing models Minutes did not
download
**When** Minutes launches and adopts any legacy downloads
**Then** only the subtree Minutes created is removed
**And** the parent directory survives with its other contents intact

**And** each of the following holds:

- Adoption remains best-effort and silent on success; it is a migration, not a
  feature.
- A test builds a legacy tree containing one adoptable model and one unrelated
  directory, runs adoption, and asserts the unrelated directory still exists.
- If adoption cannot complete, nothing is deleted at all.

**Implementation constraints:**

- The current code removes `legacy` — the whole `~/Documents/huggingface` — when
  only its `models/argmaxinc/whisperkit-coreml` subtree is empty. That is the
  defect; narrow the target, do not add a guard around the same call.

### Story 11.4: The notes folder's default matches the privacy claim

*(tier T1 · FR-69)*

As someone who was told nothing leaves this Mac, I want that to be true of where
my notes are written, so that the claim and the filesystem agree.

**Acceptance Criteria:**

**Given** a Mac with iCloud Desktop & Documents sync enabled
**When** Minutes chooses or reports the default notes folder
**Then** either the default sits outside the synced tree, or the app states
plainly that notes in this location are synced to iCloud
**And** no pane asserts that nothing leaves the Mac while notes are being synced

**And** each of the following holds:

- The detection, if used, is a fact about the folder rather than a guess about
  the user's settings.
- The user may still choose a synced folder deliberately. This story removes a
  false claim, not a capability.
- The folder is reported as ready only if it was actually created. Today the
  creation uses `try?` and reports success either way.

**Implementation constraints:**

- `SummariesPane` and `GettingStartedPane` both carry the absolute claim. Whatever
  this story decides, those sentences are part of it.

### Story 11.5: A model is a prerequisite, not a mid-meeting discovery

*(tier T2 · FR-70)*

As someone recording my first meeting, I want to know a 600 MB download is needed
before the meeting depends on it, so that I do not lose a recording to a
surprise.

**Acceptance Criteria:**

**Given** no transcription model on the machine
**When** the user is about to rely on one
**Then** the requirement is stated and the download is offered before the meeting
**And** a meeting recorded without a model still keeps its audio and can be
transcribed later

**And** each of the following holds:

- Progress is visible while a model downloads, wherever that download was
  triggered.
- Offline with no model produces a stated reason before recording, not a failure
  after it.
- Nothing in this story deletes or refuses to keep audio. A meeting already
  captured is not the place to enforce a prerequisite.

### Story 11.6: The app knows its own version, and the version comes from the tag

*(tier T1 · FR-71)*

As someone reading a bug report, I want the version in it to identify a specific
build, so that "1.0" does not mean every release ever made.

**Acceptance Criteria:**

**Given** a build produced from a tagged commit
**When** the app reports its version
**Then** the value derives from that tag
**And** an untagged development build is identifiable as one

**And** each of the following holds:

- `CFBundleShortVersionString` and `CFBundleVersion` are substituted at bundle
  time. The plist in the repository stops carrying a literal version.
- `--doctor` prints it, and the window shows it somewhere a user can find and
  quote.
- The bug report template asks for it and the command to obtain it works.

**Implementation constraints:**

- AD-33 governs. **Prerequisite for Epic 12** — a release process that cannot
  distinguish two releases is not one.
- No update-check mechanism in this story. Homebrew is the update mechanism
  (Epic 12); an in-app checker would be a second, competing one.

### Story 11.7: The remaining single-machine assumptions

*(tier T2 · FR-66 shared)*

As someone whose Mac differs from the author's, I want the app's claims about my
machine to be about my machine, so that its statements are worth reading.

**Acceptance Criteria:**

**Given** hardware, installed apps or capabilities that differ from the author's
**When** Minutes reports on them
**Then** each statement reflects what was actually determined
**And** no unavailability is explained by a reason that was not the reason

**And** each of the following holds:

- The default transcription model is guaranteed to appear in the picker, and
  something is always shown as selected. *Suspected, not confirmed: on an M1 the
  hardcoded turbo variant may be absent from WhisperKit's supported list, in
  which case the curated list filters it out and the "always offer the active
  model" fallback fails too. Verify on an M1 before writing the fix.*
- Apple Intelligence unavailability states the real reason, which
  `FoundationModelsBackend` already receives and currently discards.
- Detection covers the call apps people actually use, not two bundle
  identifiers. Classic Teams is not a prefix match for `teams2`.
- Disk space is checked before a model download and before a long recording.
- `--doctor` stops printing note filenames, which are derived meeting titles,
  given that the README asks users to share its output.

**FR Coverage — Epic 11**

| FR | Story |
| --- | --- |
| FR-66 | 11.1 (with 11.7) |
| FR-67 | 11.2 |
| FR-68 | 11.3 |
| FR-69 | 11.4 |
| FR-70 | 11.5 |
| FR-71 | 11.6 |

---

## Epic 12: One Command to Install

**Why this epic exists.** The ask was a single terminal command. Two things
found while planning it turned that from a packaging problem into a purchasing
decision.

First, permissions. Apple's TN3127 states that macOS records an app's designated
requirement when consent is granted and re-checks it on every access, and that
ad-hoc signed code's requirement "is tied to that specific version of the code".
A Developer ID requirement checks the Apple anchor, the bundle identifier and the
Team ID — not a hash. So ad-hoc signing costs the user their microphone and
system-audio consent on **every** update, and a Developer ID does not.

Second, the escape hatch closed. Homebrew applies quarantine to every cask
install from any tap, and `--no-quarantine` has been removed — verified on
Homebrew 6.0.20 on this machine: absent from `brew install --cask --help` and
rejected as an argument. Official `homebrew/cask` began removing casks that fail
Gatekeeper checks on 1 September 2026. And macOS 15 removed the Control-click
bypass, so an unnotarized app now requires a trip through System Settings.

**This epic is therefore gated on an Apple Developer Program membership.**
Without it there is no honest one-command install through Homebrew; the fallback
is building from source on the colleague's machine, which is a different promise.

**Ordering.** 12.1 before 12.2 — get signing and notarization working by hand
once, so that when CI fails it fails for one reason instead of two. 12.3 last,
because a cask pointing at a release that does not exist is untestable.

**What this epic explicitly does not build:** an in-app updater or Sparkle
(Homebrew is the update mechanism, and two updaters is worse than one); a `.dmg`
with a drag-to-install background; submission to official `homebrew/cask`, which
wants notability the project does not have and would gain nothing today; a
`curl | bash` installer, which for a GUI app is strictly worse than a cask.

### Story 12.1: Signed with a Developer ID, notarized and stapled

*(tier T1 · FR-73)*

As someone installing an update, I want my microphone permission to survive it,
so that every release does not cost me a trip through System Settings.

**Acceptance Criteria:**

**Given** a Developer ID Application certificate
**When** a release bundle is produced
**Then** it is signed with hardened runtime and a secure timestamp, notarized,
and the ticket is stapled to the `.app`
**And** `spctl --assess` accepts it

**And** each of the following holds:

- The ticket is stapled to the app bundle and the app is then **re-**archived. A
  zip cannot be stapled; getting this backwards yields a release that works
  online and fails offline.
- The bundle identifier does not change, now or later. Consent is keyed to it.
- A build with no certificate available still produces an ad-hoc bundle for local
  development, and says which one it made.
- The entitlements file is XML and carries no `get-task-allow`. Both are
  documented notarization rejections.

**Implementation constraints:**

- AD-34 governs. `notarytool`, not `altool` — the notary service stopped
  accepting `altool` in November 2023.
- Sandbox stays off. Notarization does not require it, and
  `com.apple.security.device.audio-input` is a normal hardened-runtime
  entitlement that attracts no extra scrutiny.
- Do the first one by hand and record what the notary log said, including
  warnings on success.

### Story 12.2: A tag produces a release

*(tier T2 · FR-72)*

As the author, I want pushing a tag to produce a published, notarized release, so
that shipping is not a sequence I have to remember correctly.

**Acceptance Criteria:**

**Given** a tag matching `v*` pushed to `main`
**When** CI runs
**Then** it builds, signs, notarizes, staples, packages and publishes a GitHub
Release with a checksum
**And** the version in the bundle matches the tag

**And** each of the following holds:

- Credentials are an App Store Connect API key rather than an Apple ID, because
  a key does not interact with two-factor authentication.
- The signing keychain is created, unlocked, has its partition list set, and is
  deleted afterwards even on failure. A keychain that exists but is locked or
  absent from the search list fails in a way that looks like a signing problem.
- A release cannot be published if tests or the user-data guard failed.
- The workflow is runnable manually for a dry run that signs but does not
  publish.

### Story 12.3: `brew install --cask` and it is installed

*(tier T2 · FR-72)*

As a colleague who was sent one command, I want it to work, so that I can use
the app without being walked through it.

**Acceptance Criteria:**

**Given** a published, notarized release
**When** the user runs `brew install --cask NiklasLuettringhaus/minutes/minutes`
**Then** Minutes is installed and opens
**And** no separate `brew tap` step is required

**And** each of the following holds:

- The cask declares `depends_on macos: ">= :sequoia"` and `arch: :arm64`.
- `uninstall quit: "dev.niklas.minutes"` is present so an upgrade can close a
  running menu-bar app rather than replacing it underneath itself.
- `zap trash:` covers the app's **whole** footprint, including the login-item
  launch agent that survives deleting the app.
- `livecheck` discovers new releases; CI bumps the cask's version and checksum,
  because a personal tap has no bot to do it.
- Gatekeeper is satisfied, never bypassed. No quarantine-stripping in a
  postflight block — that is precisely the protection Homebrew has just finished
  enforcing.

### Story 12.4: Apple Silicon, said out loud

*(tier T2 · FR-72 shared)*

As someone on an Intel Mac, I want to be told this app is not for my machine, so
that I do not install something that runs badly.

**Acceptance Criteria:**

**Given** a Mac that is not Apple Silicon
**When** installation is attempted
**Then** it refuses with a plain sentence naming the requirement
**And** nothing is partially installed

**Implementation constraints:**

- The declared support is arm64 because that is where every measurement in this
  repository was taken. Whether the CoreML dependencies build for x86_64 at all
  is **unverified** — do not claim universal support without testing it.

**FR Coverage — Epic 12**

| FR | Story |
| --- | --- |
| FR-72 | 12.2, 12.3, 12.4 |
| FR-73 | 12.1 |

---

## Epic 13: One Folder Is the Whole Footprint

**Why this epic exists.** The user's framing: *"all user data is local only"* —
meetings, the voice mapping, and settings, in one place the app loads, so that
working with GitHub is never a worry.

Most of this is already true and was true before the repository existed.
Meetings, remembered voices and models live under one directory, and no commit in
the project's history has ever contained audio, a meeting record or a speaker
directory. Two gaps remain between that and what the README now claims.

Settings are the odd one out: they are in `~/Library/Preferences/`, so "delete
that folder and Minutes knows nothing about you" is not currently true. And full
removal takes six steps, of which the README names three — the one that matters
being a launch agent that survives deleting the app and keeps trying to start
something that is no longer there.

**One design question inside this epic needs an answer before its code.** An
export is the first feature in the app's life that lets a voice fingerprint leave
the machine, and PRD §9.1 treats it as biometric-adjacent. The default is that it
does not leave; whether and how the user may override that is a decision to be
taken deliberately, not defaulted.

**What this epic explicitly does not build:** sync of any kind; a remote backup;
an account; a settings format anyone else is expected to author by hand.

### Story 13.1: Settings become a document in the user-data folder

*(tier T2 · FR-74)*

As someone who was told one folder holds everything, I want that to include my
settings, so that the claim is true and I can read what the app stored.

**Acceptance Criteria:**

**Given** an existing installation with settings in `UserDefaults`
**When** Minutes launches after this change
**Then** settings are migrated once into a readable document in the user-data
directory
**And** the notes-folder permission survives the migration

**And** each of the following holds:

- The file is human-readable and stable enough to diff.
- Migration runs once, is idempotent, and afterwards `UserDefaults` is not read.
- A missing or corrupt file yields defaults and a stated reason, never a crash
  and never a silent reset of everything.
- The security-scoped bookmark for the notes folder round-trips. If it cannot,
  the user is asked to pick the folder again rather than silently losing access.
- Deleting the user-data directory returns the app to a first-run state, with
  nothing about the user surviving anywhere else.

**Implementation constraints:**

- AD-37 governs. `Preferences` remains the only reader and writer of settings
  (the AD-21 pattern), so this is a change of store, not of ownership.

### Story 13.2: The app can show you everything it stores about you

*(tier T2 · FR-75)*

As a privacy-conscious user, I want to see the app's whole footprint on my Mac,
so that its promise is a list I can click rather than a sentence I have to trust.

**Acceptance Criteria:**

**Given** any installation state
**When** the user asks what Minutes stores
**Then** every location is listed with its size and what it holds
**And** each can be revealed in Finder

**And** each of the following holds:

- The list is derived from the same constants the app writes through, so it
  cannot drift out of date.
- It names the launch agent and the notes folder, not only the user-data
  directory.
- No meeting content, speaker name or embedding appears in the listing itself.

### Story 13.3: Export and import the folder

*(tier T3 · FR-75)*

As someone moving to a new Mac, I want to take my meetings, voices and settings
with me deliberately, so that changing machines does not mean starting over.

**Acceptance Criteria:**

**Given** an export the user has requested
**When** it is produced
**Then** it contains meetings, notes and settings
**And** it contains no voice fingerprint unless the user separately chose to
include one

**And** each of the following holds:

- The separate choice for voices is explicit, off by default, and accompanied by
  a plain statement of what a fingerprint is and why it is treated differently.
- Import states what it is about to overwrite before it does so.
- An import from a different app version either migrates or refuses with a
  reason. It never partially applies.
- Neither direction touches the network.

**Implementation constraints:**

- AD-38 governs. **Blocked on a product decision:** whether a fingerprint may be
  exported at all, and in what words. Do not default it.

### Story 13.4: Uninstall is complete, and documented completely

*(tier T3 · FR-76)*

As someone removing Minutes, I want everything gone, so that I am not left with
a launch agent starting an app that no longer exists.

**Acceptance Criteria:**

**Given** an installation with Launch at Login enabled
**When** the user follows the documented uninstall
**Then** nothing of Minutes remains
**And** no launch agent refers to a missing bundle

**And** each of the following holds:

- The launch agent is removed. It lives outside the app bundle and survives
  deleting it.
- The cask's `zap` stanza matches the documented list exactly, and both are
  derived from the same source as the 13.2 inventory.
- The documentation names the permission reset commands, since macOS retains
  consent records after the app is gone.
- Removing the app without the data is still possible and is still the default;
  a user's meetings are not deleted by an uninstall they did not ask to be
  destructive.

### Story 13.5: Meeting content cannot reach the repository through prose

*(tier T2 · PRD §9.1 as amended)*

As someone whose meetings are private and whose repository is public, I want the
guard to cover the way content actually escaped, so that "all user data is local"
holds for documents as well as for files.

**Acceptance Criteria:**

**Given** a staged change quoting a real meeting title from the local library
**When** the pre-commit guard runs
**Then** the commit is refused, naming the file, the line and the title it matched
**And** the same guard in CI states that it cannot run this check and why

**And** each of the following holds:

- The title list is derived from the local library at check time — meeting titles
  and Note filenames — and is never written to a file in the repository, because
  a list of what must not be committed would itself be the leak.
- Single common words are not matched. A title of "Meeting" or "Sorry" would
  otherwise refuse every commit; the check requires a multi-word title, or a
  distinctive single word above a length threshold.
- The check is local-only by construction. In CI there is no library, so it
  reports *skipped, no library present* rather than passing silently — the
  increment-6 rule that a check which cannot run must say so.
- The two known leaks are fixed in the working tree: the `--uishot` fixtures use
  invented words, and the one review sentence naming a real meeting is rewritten.
- **The history is not rewritten, and that is stated rather than quietly left.**
  The titles are already in the public commit history from earlier increments.
  Rewriting 50-odd commits a second time to remove three strings is a poor trade
  against the disruption, and it cannot un-publish them; the decision belongs to
  the user, and this story records it as theirs to take.

**FR Coverage — Epic 13**

| FR | Story |
| --- | --- |
| FR-74 | 13.1 |
| FR-75 | 13.2, 13.3 |
| FR-76 | 13.4 |
| §9.1 (amended) | 13.5 |

---

## Epic 14: The Note Is Yours, Not the App's

**Why this epic exists.** The user renamed a Note in Finder to a name that
described the meeting. The app reported the Note as missing, offered one remedy
that would have orphaned the renamed file permanently, showed the renamed file
nowhere in the UI, and then deleted the Meeting on a confirmation that named a
file it did not touch. **The recording is not recoverable.** The Trash was empty;
`removeItem` does not use it.

The whole epic follows from one sentence the product had not believed: the Note is
the user's file, in the user's folder, and they will rename it, move it and edit
it. `Meeting.noteFilename` was a `String` and the only link — so the link was a
*name*, and a name is the one property of a file a user is most likely to change.

Measured account, including the reconstruction from disk:
`../spikes/investigation-note-linkage-2026-09-03.md`.

**The ordering is set by what has already been lost, not by dependencies.**
Story 14.1 — deletion to the Trash — is first because it depends on nothing, is
a few lines, and is the only story here that prevents the outcome that has already
happened. Everything after it is in dependency order: identity, then finding, then
the surfaces that report it, then the two writes that must stop being destructive,
then the confirmation, then visibility of what was already orphaned.

**What this epic explicitly does not build:** parsing a Note's content back into
state; merging a user's edit with a fresh render; adopting a filename as the
Meeting's title; watching the Notes Folder with FSEvents. The first two are
refused permanently and the spine records why. The last two are deferred with
their reasons — a filename is a date prefix plus a slug rather than a title, and a
watcher owns only the latency while AD-39 owns the correctness.

### Story 14.1: Deleting a Meeting can be undone

*(tier T2 · FR-40 amended · AD-42)*

As someone who has already lost a recording to a confirmed delete, I want deletion
to be recoverable, so that a mistake costs me a drag out of the Trash rather than
the meeting.

**Acceptance Criteria:**

**Given** a Meeting selected in the Library
**When** the user confirms the delete
**Then** the Meeting directory is in the Trash and can be restored intact
**And** if the user chose to delete the Note, that file is in the Trash too

**And** each of the following holds:

- `trashItem` is used, not `removeItem`. A restored directory holds the audio and
  the record exactly as they were.
- A `trashItem` failure surfaces as an error naming the reason. There is **no**
  fallback to unlinking — a volume without a Trash means the delete does not
  happen, because an undoable delete is the entire point of this story.
- `removeItem` remains in use for staged writes and temporary files, and a test
  pins that no user-visible path calls it.
- Deleting audio only (FR-44) goes to the Trash on the same rule.

**Implementation constraints:**

- `MeetingStore.delete(id:alsoDeleteNote:)` and `deleteAudio(id:)` are the only
  call sites. AD-42 governs.

### Story 14.2: A Note says which Meeting it belongs to

*(tier T6 · FR-77 · AD-39, AD-9 amended)*

As someone whose notes are files in my own folder, I want each Note to carry its
own provenance, so that renaming or moving it cannot sever it from its meeting.

**Acceptance Criteria:**

**Given** a Meeting whose Note is written
**When** the Note is rendered
**Then** its frontmatter carries the Meeting's ID
**And** a reader can tell what the file is with no other file present

**And** each of the following holds:

- `NoteIdentity` lives in Core, compiles against Foundation alone, and parses a
  frontmatter block into a Meeting ID and a start time — **nothing else.** Its
  return type cannot represent a title, a summary or a transcript line, so AD-9's
  identity-versus-content line is enforced by the type rather than by discipline.
- It reads only up to the closing `---`, and refuses a file whose first line is
  not `---` rather than scanning an arbitrary document.
- The `started_at` fallback parses every one of the fifteen real Notes on the
  author's machine, and a test reads them from disk to prove it.
- No existing Note is rewritten to add the stamp. The stamp appears when a Note is
  next written for its own reasons.
- A file with neither a Meeting ID nor `generated_by: Minutes` plus `started_at`
  yields no identity at all, and is therefore never claimed (AD-43).

### Story 14.3: Finding a Note that moved

*(tier T6 · FR-78 · AD-39, AD-43)*

As someone who renames files, I want Minutes to look for my note before it tells
me anything about it, so that it does not report a file as gone while I am looking
at it.

**Acceptance Criteria:**

**Given** a Meeting whose recorded Note path does not exist
**When** the link is resolved
**Then** the folder's Notes are matched by identity and exactly one match relinks
**And** two matches are reported as an ambiguity and nothing is assumed
**And** no match leaves the record untouched

**And** each of the following holds:

- One port, `NoteLocating`, taking a Meeting and a folder and returning
  `located(URL)` / `ambiguous([URL])` / `notFound`. No caller reaches into the
  folder itself.
- Only files carrying a Minutes identity marker are considered. A test puts an
  unrelated `.md` file in the folder and proves it is never returned, never
  listed and never touched.
- Matching prefers the Meeting ID and falls back to `started_at` within one
  second, because the frontmatter's ISO timestamp is second-precision while
  `Meeting.startedAt` is not.
- The locator creates, renames, moves and deletes nothing. A test asserts the
  folder's contents and every file's modification time are identical before and
  after a resolution.
- Subdirectories are searched one level, because "moved it" often means "moved it
  into a folder", and a bounded depth is the difference between a fix and a
  filesystem crawl.

### Story 14.4: "Missing" means Minutes looked and did not find it

*(tier T6 · FR-78, FR-53 amended, FR-54 amended)*

As someone reading the Library, I want its claims about my folder to be true, so
that a badge means something.

**Acceptance Criteria:**

**Given** a library with one Meeting whose Note was renamed and one whose Note was
deleted
**When** the Library reloads
**Then** the renamed one is silently relinked and shows no badge
**And** only the deleted one is reported as not found

**And** each of the following holds:

- Reconciliation runs **only** when an existence check has failed. A library with
  no broken link performs zero folder reads, and a test proves it by counting
  reads through the port.
- A single match is persisted through `MeetingStore` (AD-21). Ambiguity and
  absence persist nothing, so a folder that is temporarily unavailable cannot
  write a false claim into history.
- Relinking is silent: no banner, no alert, no confirmation. The only visible
  change is the filename the detail pane shows.
- The explicit refresh (FR-54) reconciles and recounts, in both directions —
  records against files and files against records.
- Moving the Notes Folder still does not mark every past Meeting broken.

### Story 14.5: Row and detail actions tell the truth about what is there

*(tier T2 · FR-53 amended, FR-37 · EXPERIENCE.md Row actions)*

As someone right-clicking a meeting, I want the actions on offer to work, so that
the app stops handing me a system error.

**Acceptance Criteria:**

**Given** a Meeting whose Note cannot be found
**When** the user opens the row's context menu
**Then** `Reveal in Finder` and `Open in Editor` are absent
**And** `Locate note…` and `Rewrite note` are present

**And** each of the following holds:

- The condition is *a file has been located*, never *a filename is recorded*.
  This is the defect the user reported as "file not found": `NSWorkspace.open` on
  an absent path produces macOS's own alert.
- The detail pane and the row menu apply one rule from one place. They had
  diverged, with the fix and a comment explaining it living only in the detail
  pane.
- The unresolved copy says what was looked for and where, and distinguishes the
  two remedies by what each does to the file on disk.
- The ambiguous state lists the competing files by name with `Use this one` per
  file, and the app picks none.

### Story 14.6: Pointing a Meeting at a file

*(tier T6 · FR-79 · AD-43)*

As the user who renamed the file, I want to attach it to the meeting myself, so
that I am not dependent on the app guessing right.

**Acceptance Criteria:**

**Given** any Meeting
**When** the user chooses `Locate note…` and picks a Markdown file
**Then** that file becomes the Meeting's Note
**And** the file's contents are not modified by the act of choosing

**And** each of the following holds:

- Available on an unresolved link and on a linked Meeting alike — a user may want
  to point at a different file.
- If the chosen file's frontmatter identifies a different Meeting, the app names
  that Meeting and asks. It does not refuse, and it does not stay silent: one file
  linked to two Meetings means the next rewrite destroys one of them.
- If the file carries no Minutes frontmatter, the app states plainly that the next
  rewrite of this Meeting would replace its contents — before the link is made.
- The chooser starts in the Notes Folder and is filtered to Markdown.
- Nothing is stamped, moved or reformatted on linking.

### Story 14.7: The name you gave the file is the name it keeps

*(tier T6 · FR-80 · AD-40, AD-18 amended, FR-35 amended)*

As someone who named a file deliberately, I want the app to stop renaming it back,
so that my filing survives editing the meeting.

**Acceptance Criteria:**

**Given** a Note the user has renamed in Finder
**When** the Meeting's title changes
**Then** the file keeps the user's name and only its contents change
**And** the app shows the user's name for the file

**And** each of the following holds:

- The record carries two names: the linked file, and the filename `NoteWriter`
  last wrote. Divergence *is* the test — there is no `didUserRename` flag to fall
  out of sync with the filesystem.
- While the two are equal, AD-18 applies unchanged and a title change renames the
  file as it always has.
- Every surface that names the file uses the user's name, in
  `{typography.mono-inline}`. A test pins that the derived name appears in no
  user-facing string once the two have diverged.
- Adopting the filename as the Meeting's title is **not** implemented, and the
  story records why rather than leaving it as an apparent oversight.

### Story 14.8: A rewrite finds the file before it writes one

*(tier T2 · FR-35 amended, FR-83)*

As someone clicking the only button the app offered, I want it not to be the
action that makes my problem permanent.

**Acceptance Criteria:**

**Given** a Meeting whose Note was renamed and whose link is broken
**When** the user chooses `Rewrite note`
**Then** the existing file is found and rewritten under its own name
**And** no second file is created

**And** each of the following holds:

- A new file is created only when reconciliation returns `notFound`. A test
  reproduces the original defect — rename the file, rewrite, and assert the folder
  still holds exactly one Note for that Meeting.
- The rename branch in `NoteWriter` no longer treats an absent stored filename as
  a reason to write at the old path.
- `Rewrite note` remains a user action. A Note the user deliberately deleted is
  still not silently recreated (FR-53).

### Story 14.9: The app knows what it wrote, so it can tell your edit from its own

*(tier T6 · FR-81 · AD-41, AD-9 amended · DESIGN.md components.decision-banner)*

As someone who might add a paragraph of my own to a note, I want the app to notice
rather than discard it, so that my folder is a place I can actually work in.

**Acceptance Criteria:**

**Given** a Note whose bytes on disk differ from what Minutes last wrote
**When** an edit would rewrite it
**Then** nothing is written
**And** the user is offered exactly two outcomes: keep the file, or replace it

**And** each of the following holds:

- Every write persists a digest of the exact bytes written, in the same
  `MeetingStore` update that persists the filename.
- The comparison is digest against disk bytes — **never** against a fresh render.
  The renderer has changed in four increments, so re-rendering an old Note
  legitimately differs and would report every Note as edited. A test pins this by
  rendering an increment-3-era record and asserting no conflict is raised.
- The banner is `{components.decision-banner}`: it states what was found, not what
  the user should do, and the prominent control is the one that changes nothing on
  disk.
- The choice is per Note and is not remembered as a preference.
- The record edit that triggered the rewrite is still applied. The record is not
  the file, and holding a rename hostage to a file conflict would be a second
  defect.
- **Migration:** a Note with no digest adopts the current bytes as its baseline
  when the file's modification time is not later than the record's last write, and
  raises a conflict when it is later. All fifteen real Notes adopt cleanly —
  measured — and a test constructs the later-mtime case to prove the other branch
  fires.

### Story 14.10: The delete confirmation names the file it will delete

*(tier T2 · FR-40 amended · EXPERIENCE.md destructive-action rule)*

As someone about to delete something permanently, I want the dialog to describe my
filesystem rather than the app's memory of it.

**Acceptance Criteria:**

**Given** a Meeting whose Note has been renamed, with *also delete notes* ticked
**When** the confirmation is shown
**Then** it names the file that will actually be deleted
**And** deleting it removes that file

**And** each of the following holds:

- The link is resolved when the dialog is composed, not read from the record.
- When no file can be found, the dialog says so instead of naming the file the
  record remembers.
- The dialog says the items go to the Trash.
- A multi-selection enumerates per Meeting and the count of Notes is the count of
  files actually resolved.
- The reverse case is covered by a test: a Note renamed to the filename another
  Meeting's record holds must not be deleted as that Meeting's Note.

### Story 14.11: A note whose meeting is gone is still visible

*(tier T6 · FR-82 · AD-43 · DESIGN.md components.voice-row reuse)*

As someone whose meeting was deleted while its renamed note survived, I want the
app to admit the file exists, so that it is not invisible in the one place that
should know about it.

**Acceptance Criteria:**

**Given** a Notes Folder containing a Note Minutes wrote whose Meeting is deleted
**When** the Library is shown
**Then** a footer reports how many such files there are
**And** expanding it lists each with the date and title from its own frontmatter

**And** each of the following holds:

- The list uses `{components.voice-row}`'s anatomy verbatim — leading `doc.text`
  glyph, the *actual* filename as the title, its own frontmatter as the subtitle,
  `Reveal` and a minus-circle `Dismiss`.
- `Dismiss` changes the listing only and never touches the file.
- Files Minutes did not write are not listed at all.
- They are not offered as an import. A Note cannot be parsed back into a Meeting,
  and the epic's non-goals say so.
- The footer is absent, not empty, when there are none.
- The specific file that prompted this epic —
  `2026-09-03 0930 Morning -standup.md`, whose Meeting was deleted on 3 September
  2026 — appears in this list on the author's machine when the story is done. That
  is the story's acceptance test on real data.

**FR Coverage — Epic 14**

| FR | Story |
| --- | --- |
| FR-77 | 14.2 |
| FR-78 | 14.3, 14.4 |
| FR-79 | 14.6 |
| FR-80 | 14.7 |
| FR-81 | 14.9 |
| FR-82 | 14.11 |
| FR-83 | 14.1, 14.8, 14.10 |
| FR-35 (amended) | 14.7, 14.8 |
| FR-40 (amended) | 14.1, 14.10 |
| FR-53 (amended) | 14.4, 14.5 |
| FR-54 (amended) | 14.4 |

---

## Epic 15: A Recording the App Cannot Vouch For

**Why this epic exists.** For three days Minutes wrote confident, well-formatted,
entirely invented dialogue for the remote half of seven meetings, and every check
it had said everything was fine.

**Seven of sixteen recordings.** A system stream declaring 16 kHz whose real rate
was 8 kHz or 5.3 kHz — two or three times too fast. Speech at that speed is still
speech-like, so transcription did not fail. It fabricated. Then the title, the
tags and the summary were derived from the fabrication, so a broken recording
arrived with a plausible name. Every affected recording had a Bluetooth headset as
the *input* device. Every microphone stream was correct.

**The user found it, not the product.** They measured the sample counts, wrote up
the mechanism and the recovery, and left the report in their notes folder. The
product's own capture-evidence check — built one increment earlier for exactly the
purpose of not asserting a capture it could not prove — passed all seven, because
it checks for *signal*, and a stream at three times speed is full of signal.

Two lessons are written into the spine rather than left here. **AD-3's Prevents
clause already named this exact failure** — "two adapters disagreeing on sample
rate and silently producing garbage or half-length audio" — so the rule was
followed and was insufficient: reading a format once at tap creation says nothing
about what the device goes on to deliver. And **AD-36's scope was too narrow**:
*was anything captured* and *is it at the rate it claims* are different questions.

**What this epic explicitly does not build:** a fix aimed only at Bluetooth input
devices, or only at sample rates. The correlation is 7 of 7 and the mechanism is
not proven against Apple's source, so the guard is built on the *observable* — a
sample count that disagrees with the clock — which catches a rate misread, a
dropped-buffer bug, a converter misconfiguration and a clock drift alike. It also
does not build automatic repair without asking, and it does not delete or hide a
flagged recording: the samples are the user's.

### Story 15.1: A stream knows the rate it is actually receiving

*(tier T1 · FR-84 · AD-44)*

As someone recording a meeting, I want the app to notice when audio is arriving at
a different rate from the one it believes, so that it cannot resample my meeting
into nonsense.

**Acceptance Criteria:**

**Given** a stream whose declared format says 48 kHz while frames arrive at 16 kHz
**When** the stream has been running past its settling period
**Then** the observed rate is available alongside the declared one
**And** the disagreement is detectable without waiting for the Session to end

**And** each of the following holds:

- The writer counts input frames consumed and the wall time it has been running.
  Both are values it already holds; nothing new is measured.
- The observed rate is `frames / elapsed`, and it is reported as a number, never
  as a verdict on its own.
- A settling period passes before the first comparison, because the first buffers
  arrive irregularly. Its length carries its reasoning at its declaration.
- On the nine correct recordings on this machine the observed rate sits within
  3% of the declared one. A test drives the writer at a deliberately wrong rate
  and asserts the ratio comes back as 2 and as 3.

### Story 15.2: A rate disagreement is a named failure, not a silent resample

*(tier T1 · FR-84 · AD-44)*

As someone whose recording is being quietly ruined, I want the app to stop and say
so, so that I find out during the meeting rather than in six months.

**Acceptance Criteria:**

**Given** a stream whose observed rate disagrees with its declared rate
**When** the disagreement exceeds the tolerance
**Then** a failure is raised naming both rates
**And** the Session continues with whatever streams are still sound

**And** each of the following holds:

- The error names the declared rate, the observed rate and the stream. "Audio
  problem" is not an acceptable message; a reader must be able to tell what
  happened from the sentence.
- It follows FR-7's degradation rule: the microphone surviving means the Session
  survives, mic-only, and says so.
- The tolerance is a stated constant with its reasoning, and is not a setting.
- A correct recording never raises it — asserted against real ratios of 1.00–1.03.

### Story 15.3: The record says which stream cannot be relied on

*(tier T1 · FR-85 · AD-45)*

As someone reading a meeting months later, I want the record to say the far end
was unreliable, so that I do not trust a transcript I should not.

**Acceptance Criteria:**

**Given** a Session in which one stream failed its rate check
**When** the Meeting is persisted
**Then** the record carries, per stream, whether it passed and both rates
**And** that survives a relaunch

**And** each of the following holds:

- Stored, not derived on read. It is a fact about a recording that happened.
- **Per stream.** In all seven observed cases the microphone was correct and the
  system stream was not, so a per-Meeting flag would be wrong in both directions.
- The field decodes as absent on every record written before it existed, per the
  Decodable-evolution convention — adding one field to `Meeting` once orphaned
  five real recordings.
- Capture evidence now has two independent parts and a test asserts a stream can
  fail either one alone: full of signal at the wrong rate, and silent at the right
  rate.

### Story 15.4: No title or summary is derived from a transcript the app cannot vouch for

*(tier T1 · FR-86 · AD-46)*

As someone scanning a list of meetings, I want a broken recording to look broken,
so that a confident title does not hide it.

**Acceptance Criteria:**

**Given** a Meeting whose system stream failed its rate check
**When** the metadata stage runs
**Then** no title, tags or summary are derived from that stream's text
**And** the transcript itself is still written

**And** each of the following holds:

- This is the clause that addresses *why the defect looked fine*. Titles like
  "Die", "Sorry" and "Put The Fashion" were generated from fabricated text and
  looked like ordinary weak auto-titles.
- Where the microphone passed and the system stream did not, metadata may come
  from the microphone's text alone, and the Note says that is what happened.
- The Meeting still gets a title — a date and time, which is honest — rather than
  no title at all.
- Nothing is discarded. The samples are the user's.

### Story 15.5: The app says which recordings it cannot vouch for

*(tier T2 · FR-87 · AD-46)*

As someone with sixteen meetings in a list, I want to see which ones are suspect
without opening each, so that I know what I am dealing with.

**Acceptance Criteria:**

**Given** a library containing a Meeting that failed its rate check
**When** the Library is shown
**Then** that Meeting is marked
**And** its detail pane states which stream, both rates, and what it means

**And** each of the following holds:

- The Note carries the same statement. In six months the Note is all there is.
- The copy names a Bluetooth input device as the likely cause where one was
  recorded, and does not assert it as certain — the correlation is 7 of 7 and the
  mechanism is not proven against Apple's source.
- It uses the existing degradation treatment rather than a new one. A recording
  the app cannot vouch for is a degradation, and the product already has a voice
  for those.
- Nothing is hidden, greyed out or auto-deleted.

### Story 15.6: An existing recording can be re-checked and repaired

*(tier T2 · FR-88)*

As someone who already has seven ruined recordings, I want the app to find and fix
them, so that the fix is not a script somebody ran once.

**Acceptance Criteria:**

**Given** recordings made before the rate check existed
**When** the user asks the app to check them
**Then** each stream is assessed and the failures are named with both rates
**And** where the true rate is recoverable the recording can be repaired and re-run

**And** each of the following holds:

- The true rate is derived from the stream's own sample count and the Session's
  duration, snapped to the integer ratio — the empirical figure reads a few per
  mil low because the wall clock includes the moments before the first sample
  arrived, which is how 8000 Hz measured as 7919–7996.
- Repair rewrites only the declared rate. Samples are not resampled, re-encoded
  or discarded, and the original declared rate is recorded so the change is
  reversible.
- Re-running uses the retained audio and the existing pipeline. No second
  transcription path exists.
- Nothing is repaired without the user asking.
- Verified on real data: the seven affected recordings recovered, one of them from
  144 to 355 utterances, and a German meeting from word salad to grammatical
  German.

### Story 15.7: The rate the tap reports is read again when it can change

*(tier T2 · FR-84 · AD-3 amended)*

As someone who plugs in headphones mid-meeting, I want the app to keep up, so that
a device change does not silently corrupt the rest of the recording.

**Acceptance Criteria:**

**Given** a running Session
**When** the tap's format is re-read after the device chain is fully started
**Then** the rate driving the converter is the one the device is actually using
**And** a change that cannot be honoured stops the stream with a stated reason

**And** each of the following holds:

- The format is re-read after `AudioDeviceStart`, not only after the aggregate
  device is created. Reading it at creation is what produced this defect.
- The existing device-change path already refuses to continue on a format change
  mid-recording (FR-8). That behaviour is kept; this story makes the *initial*
  rate as trustworthy as the post-change one.
- This story is ranked last deliberately. It addresses the mechanism, which is
  inferred; 15.1 through 15.4 address the observable, which is measured. If the
  mechanism turns out to be something else, the guard still holds.

**FR Coverage — Epic 15**

| FR | Story |
| --- | --- |
| FR-84 | 15.1, 15.2, 15.7 |
| FR-85 | 15.3 |
| FR-86 | 15.4 |
| FR-87 | 15.5 |
| FR-88 | 15.6 |
| FR-67 (amended) | 15.3 |

## Epic 16: The Microphone Was Also Listening to the Call

**Why this epic exists.** Asked to improve transcription, the first thing built
was not a transcription change. It was a way to tell whether any change helped —
because the product had been asserting a five-point accuracy rating for fourteen
models on the basis of no measurement at all, and there was no way to know
whether a change made things better or worse.

The harness found something bigger than a model choice. **Three of twelve
recordings holding both streams had the microphone recording the far end**
through the loudspeakers: cross-correlation 0.771 at a 39 ms lag on the worst,
against 0.025 or below on the nine clean ones. The consequences compound:

- **57.6% of freshly transcribed microphone words duplicated a system-stream
  utterance.** The merge preserved both copies, exactly as FR-23 told it to.
- **The diariser reported six people in the room** (`room-0` … `room-5`), and
  **never identified the user at all** — their own voice was one polluted
  cluster among six. This is the "Me" mislabel class of failure, with a cause
  nobody had located.
- The note, and the summary derived from it, were built on all of that.

**What makes this epic different from Epic 15.** That one was written from a
defect the user found. This one was written from a defect *nobody had noticed* —
the affected notes read as merely verbose. It surfaced only because accuracy
became measurable, which is the argument for Story 16.1 existing at all.

**Cancellation is out of scope, and the reason is measured, not aesthetic.**
Subtracting the reference signal is the textbook fix. On these recordings the
upper bound on ERLE for *any* linear filter — from magnitude-squared coherence,
so independent of filter length — is **8.7 dB at 128 ms, 9.9 dB at 512 ms,
10.6 dB at 2048 ms**, against the 20–40 dB a useful canceller needs. Two
independent device clocks, a nonlinear speaker path and a reverberation tail
outlasting any window tried. Detection needs only that the relationship exists;
cancellation needs it to be invertible, and it is not (AD-48).

**What this epic explicitly does not build.** It does not change the default
model: pooled over three sessions the English-only Parakeet leads the shipped
default by 2.3 points on close mics, but the per-session swing is ±8 points —
larger than the effect, so three sessions cannot move a default every user gets
(§13 Q19). It does not adopt Canary-1B-v2, which measured 8.5 points worse at
22× the cost. It does not normalise far-field audio, worth a real ~2 points but
needing a gate that integrated loudness demonstrably cannot provide (§13 Q20).
And it does not de-duplicate utterances after transcription, which would tidy
the text and leave the speaker count just as wrong.

**One story rewrote three others before any of them was built.** Story 16.3
asked for the frame test to be *energy dominance* rather than correlation.
Calibrated, energy dominance bought 1.1 points over plain correlation and the
honest ceiling for any audio-only rule was 86% recall at **13% of the user's own
words** — because the echo path is not linear, the same fact that ruled out
cancellation. What was wrong was not the statistic but the premise that
Diarization and the Transcript need the same test. They do not: clustering
tolerates missing frames, and the Transcript has a second signal available in
the text. FR-90, FR-91, AD-47 and Stories 16.3, 16.4 and 16.7 were amended
before implementation, and the Transcript's cost in unique content went from 13%
to nil. See `spikes/calibration-echo-threshold-2026-09-03.md`.

**Increment 10 builds 16.9 to 16.15, and re-affirms them rather than rewriting
them.** All seven were written in increment 9 against measurements that still
stand, so nothing in their scope moves. What moved is underneath them: the
architecture gained AD-53 to AD-56 and amended four existing decisions, because
building the first two stories found that the fact both were reasoning about
indirectly — the device's own sample-time and host-time counters — is handed to
the app in every audio callback and thrown away in both capture adapters. That
single fact makes 16.9 exact, turns 16.12 from a correlation search into a
subtraction, and gives 16.14 the aligned reference it needs. One story is added,
**16.16**, and it comes from a figure in this epic failing its own rule.

**The order they are built in is not the order the evidence ranks them, and the
reason is dependency rather than preference.** By value the ranking is 16.14,
16.13, 16.15, 16.12, 16.9, 16.10, 16.11. But 16.14 needs the aligned reference
16.9 provides and the device gate 16.13 provides, so building it first means
building both of them badly inside it. The build order is therefore 16.9, 16.12,
16.13, 16.15, 16.10, 16.11, 16.16, 16.14 — foundations, then the two stories
with a number to move, then the port contract, then the largest and least
certain last, where its measurement can be reported without holding up the rest.

**Ordering.** The instrument first, because every story after it is validated
with it. Then the safety floor *before* the exclusion it constrains — the same
discipline as Epic 14, where what has already been lost outranks dependency
order. Exclusion, then what the record says, then what the user sees. The
honesty fix to the model list comes next because it is cheap and the claim is
live in the UI today. The clock and the port contract close it out.

### Story 16.1: Transcription accuracy can be measured from a terminal

*(tier T1 · FR-93 · AD-50)*

As someone changing how transcription works, I want to measure accuracy against
a reference corpus, so that I can tell an improvement from a regression instead
of guessing.

**Acceptance Criteria:**

**Given** an audio file and a reference transcript
**When** the measurement command is run
**Then** it reports a word error rate, a content-word error rate and proper-noun recall
**And** the figures come from the same `Transcribing` port the app uses

**And** each of the following holds:

- One command transcribes a file through the shipping code path and emits
  machine-readable utterances. The harness measures the product, not a copy of
  it, so the two cannot drift (AD-50).
- Raw WER is reported **and is not the only figure**. At the baseline the
  most-deleted words were `yeah` (38), `ok` (17) and `right` (13) — a quarter of
  all errors, and words FR-31 strips on purpose. A content-word rate excluding a
  closed-class list is reported beside it, with proper-noun recall, because a
  wrong name is the error a reader notices.
- A repetition measure is reported, as a model-independent signature of the
  §4.13 fabrication failure.
- Results aggregate by pooling errors over pooled reference words. Averaging
  per-session percentages is not permitted and a test asserts the two differ.
- Neither corpus audio nor results are written into the repository, and
  `check-no-user-data.sh` still passes (§9.1).
- The normaliser is symmetric: hesitations, digits-versus-words and apostrophes
  are treated identically on both sides, and a test proves a reference scored
  against itself yields exactly 0%.

### Story 16.2: The app can tell that the microphone was hearing the call

*(tier T1 · FR-89 · AD-47, AD-48)*

As someone who took a call on speakers, I want the app to notice that my
microphone also picked up the other side, so that it does not treat the call as
if it happened twice.

**Acceptance Criteria:**

**Given** a Session with both streams
**When** the streams are compared
**Then** a verdict says whether the mic stream contains a delayed copy of the system stream, and how much of it does
**And** a headphones recording is not flagged

**And** each of the following holds:

- The delay is **estimated, not assumed**, and a delay that is not physically
  plausible is reported as *failure to detect* rather than used. This is not
  hypothetical: one real recording's estimator returned 920 ms, which no
  speaker-to-microphone path explains, and a wrong delay would silently disable
  the whole test.
- Detection is by correlation against the delay-aligned system stream and
  **never inspects transcript text**. Text similarity was how the signal test
  was *validated* (88–89% agreement on two recordings, 2% false-positive rate on
  a third) and is not the mechanism — a detector needing a transcript could not
  run before transcription.
- The verdict carries a proportion, not just a flag: 47% of mic-active frames on
  the worst real recording against 6% on the mildest.
- Fixtures reproduce both sides. A synthesised mic stream built from a known
  system stream plus delay and gain is detected; two unrelated speech signals
  are not.
- The nine clean real recordings must all come back clean. Their measured
  cross-correlation is at or below 0.025 and the threshold sits far above it.

### Story 16.3: What cannot be echo is never excluded

*(tier T1 · FR-91 · AD-47)*

As someone who talks over people, I want my own words kept even when the far end
is speaking, so that removing an echo does not remove me.

**Acceptance Criteria:**

**Given** mic audio recorded while the system stream is silent
**When** echo exclusion runs
**Then** none of it is ever excluded, at any threshold

**And** each of the following holds:

- With no system stream, or a silent one, nothing is excluded. On the worst real
  recording this covers 2,376 of 5,917 mic-active frames — **40% of mic
  activity, unambiguously the room**.
- Speech concurrent with the far end but uncorrelated with it is retained as
  double-talk: 787 frames, 13% of mic activity, on the same recording.
- **The transcript loses no unique content at all**, because the rule that
  touches it requires two independent signals to agree (Story 16.4). This story
  was rewritten by its own calibration: it originally demanded *energy
  dominance* rather than correlation, and measurement showed energy dominance
  buys 1.1 points over plain correlation while the honest ceiling for any
  audio-only rule is 86% recall at **13% of the user's own words**. The floor
  did not change; what changed is that the transcript no longer relies on it
  alone.
- The frame test is known to be **weak on mild echo**: at the calibrated
  threshold it reaches 86% recall on the worst recording and 18% on the
  moderate one. That is acceptable only because its false positives reach
  clustering and never the transcript.
- This story is ordered before the one that excludes, deliberately. The floor
  has to exist before the thing it constrains.

### Story 16.4: The echo never reaches the model or the diariser

*(tier T1 · FR-90 · AD-47, AD-49)*

As someone reading a note, I want each thing said counted once, so that the
transcript is a record of the meeting rather than of the room's acoustics.

**Acceptance Criteria:**

**Given** a recording whose mic stream contains echo
**When** the Meeting is processed
**Then** the echo reaches neither the Transcription Model nor the Diarizer
**And** the recording on disk is unchanged

**And** each of the following holds:

- **Nothing is excluded unless the recording clears the gate.** Seven of the
  nine clean real recordings hold literally zero coincidentally duplicated
  words, so a headphones recording must pass through untouched — proven, not
  assumed.
- ~~**Diarization** clusters from audio with echo frames excluded, muted in the
  processing path with ramps rather than hard cuts.~~ **Withdrawn by measurement
  before it shipped, and now forbidden** (AD-47 as amended): the in-room voice
  count went 5→7, 6→6 and 3→5, because muting fragments continuous speech and
  the clusterer splits one voice into several. Story 16.15 replaces it — the Mic
  Stream is diarized unmodified and the far end's *clusters* are ruled out by
  comparison. The app never edits the user's recording to fix its own problem
  (AD-49), and it no longer edits a derived copy either.
- **The transcript** drops a mic Utterance only where the frame test *and* the
  text agree — flagged as echo **and** substantially repeating a time-overlapping
  system Utterance. It cannot delete unique content, because it only ever
  removes a duplicate of something already held on the other stream.
- Post-hoc de-duplication *of the transcript alone* stays rejected: it tidies
  the text and leaves the speaker count wrong, which was the larger harm
  (AD-47). The two rules are not alternatives; both run.
- Measured effect across the three affected recordings: **16%, 58% and 59%** of
  mic words removed as duplicates, of which **98% sit in Utterances longer than
  two words**. Coincidental agreement is short; verbatim multi-word repetition
  at the same instant is the loudspeaker.
- A **partial overlap** — echo and a room voice inside one Utterance — is not
  fixed by the text rule and stays in the residual. A test asserts the residual
  is reported rather than assumed to be zero.

### Story 16.5: The people in the room are counted from the room

*(tier T1 · amends FR-21, FR-22 · AD-11, AD-47)*

As someone recording in a meeting room, I want the app to count the people
actually with me, so that it does not introduce the far end as colleagues.

**Acceptance Criteria:**

**Given** a mic stream that contained echo
**When** diarization runs
**Then** in-room voices are clustered from the retained audio only

**And** each of the following holds:

- The In-Room Speaker count comes from post-exclusion audio. On the worst real
  recording the pre-exclusion count was **six** (`room-0` … `room-5`) and the
  user was **never** identified as `local`.
- `local` identification is re-evaluated against the retained audio, so the
  enrolled-voice match of FR-63 competes against the room rather than against
  the room plus the far end.
- AD-11's structural claim is amended, not abandoned: place remains structural
  for the *retained* mic stream. A retained mic voice is still never relabelled
  as remote.
- A test drives a synthesised two-in-the-room recording with echo from three
  far-end voices and asserts the count is two, not five.

### Story 16.6: The record says the recording was affected, and by how much

*(tier T2 · FR-92 · AD-49)*

As someone deciding how much of a note to trust, I want to know that my
microphone was also hearing the call, so that I can judge the result and change
what I do next time.

**Acceptance Criteria:**

**Given** a Meeting whose mic stream contained echo
**When** its record is read
**Then** the verdict, the estimated delay and the excluded proportion are all there

**And** each of the following holds:

- A recording processed before this existed carries an **unknown** verdict, and
  unknown reads as unknown — never as clean (AD-49). This is the same rule the
  rate work settled on and for the same reason.
- The stored values are enough to re-derive the decision after a threshold
  change, without re-running detection from audio.
- A `Decodable` record written by an older build still loads, and a test covers
  the older shape rather than only the current one.

### Story 16.7: The same sentence never appears twice

*(tier T2 · amends FR-23 · AD-47)*

As someone reading a transcript, I want overlapping speech to mean two people
talking, not one person recorded twice, so that the record is not padded with
its own echo.

**Acceptance Criteria:**

**Given** a merged Transcript
**When** it is checked
**Then** no mic-stream Utterance substantially repeats a time-overlapping system-stream Utterance

**And** each of the following holds:

- FR-23's overlap clause is narrowed in wording as well as behaviour: it
  licenses *genuine* overlap and never the same speech from two streams.
- The invariant is a test over the merged output, not a property assumed from
  the upstream stage — the stage can regress and this must catch it.
- The check reports the proportion, so the 33.6% and 32.2% measured on real
  recordings become a number that is tracked. It is **not** asserted to reach
  zero: partial overlaps survive the Utterance-level rule by construction, and a
  test that demanded zero would be asserting something the design does not
  deliver.
- A word-rate sanity signal is available: the two affected recordings read
  **226 and 270 words per minute** against a library median of 148, and natural
  speech is 110–160.

### Story 16.8: The app stops rating accuracy it has not measured

*(tier T6 · amends FR-17 · AD-50)*

As someone choosing a model, I want the app to tell me only what it knows, so
that I am not steered by a number somebody invented.

**Acceptance Criteria:**

**Given** the model list
**When** it is shown
**Then** an accuracy figure appears only where it has been measured, and is absent elsewhere

**And** each of the following holds:

- The five-point accuracy rating is **removed** where nothing measured backs it,
  not re-estimated. Fourteen models carried one; zero had been measured.
- Speed claims stay, because `--benchmark` has always measured them. The
  asymmetry is the point: the product may keep the claim it can support.
- The note on the English-only Parakeet — *"English only, and a little sharper
  for it"* — is now **supported** on close mics (20.3% against 22.6% pooled) and
  is kept, with the measurement named. This story exists partly because the
  opposite conclusion was drawn from a single session and had to be retracted.
- `whisper-large-v3-turbo` loses the `.accurate` role and its 5/5 rating: it
  measured a tie with Parakeet v3 on close mics (22.8% against 22.6%) and
  **11.4 points worse** far-field (40.8% against 29.4%), at 8× the cost.
- The default model does **not** change in this story, and §13 Q19 records why
  with its revisit condition.

### Story 16.9: The rate is checked against the audio clock

*(tier T6 · FR-94 · AD-51 as amended, amends AD-3, AD-44)*

As someone recording on a device that lies about its rate, I want the check to
use the device's own clock, so that it is exact rather than tolerant.

**Acceptance Criteria:**

**Given** an IOProc callback carrying the device's sample time and host time
**When** the rate is verified
**Then** frames are compared against the device's sample time taken at the same instant

**And** each of the following holds:

- `mSampleTime` and `mHostTime` are passed through to whatever judges the rate.
  Both are available in every callback today and both are discarded — the
  callback signature binds them to `_`.
- A gap between successive callbacks' sample times exceeding the frames
  delivered is recorded as a **discontinuity** — samples the app never received
  — which the wall-clock check cannot see at all.
- The 12% tolerance and 3-second settling window shrink or disappear, and
  whatever replaces them is **derived** from the clock's properties rather than
  tuned against recordings.
- AD-4's single session clock is untouched and remains the time base for
  Utterances. This story changes only how *rate* is verified.
- AD-45's refusal to snap to a rate no real device uses still holds, and its
  test still passes.

### Story 16.10: An Utterance carries how sure the engine was

*(tier T6 · FR-95 · AD-52)*

As someone whose recording came out badly, I want the app to keep the engine's
own uncertainty, so that a doubtful transcript can be treated as doubtful.

**Acceptance Criteria:**

**Given** an engine that reports per-segment confidence
**When** a Meeting is transcribed
**Then** the confidence reaches the Meeting record

**And** each of the following holds:

- Confidence crosses the port boundary. Today `TranscribedSegment` carries
  `start`, `end` and `text` and nothing else, so the adapter discards the only
  signal that would have caught §4.13's fabrication by its symptom.
- An engine reporting no confidence yields **absent**, never zero. Absent means
  unknown and a test asserts it does not read as low confidence.
- AD-46's metadata gate may consult it, turning a binary trust decision into an
  evidenced one, and may never treat absent as failing.
- A Meeting largely composed of low-confidence text is distinguishable from one
  that is not, without re-running transcription.

### Story 16.11: Audio the engine could not read is a recorded gap

*(tier T6 · FR-96 · AD-52)*

As someone reading a summary, I want to know that a stretch of the meeting
produced no usable text, so that I do not read an incomplete record as a
complete one.

**Acceptance Criteria:**

**Given** an interval the engine returned nothing usable for
**When** the Transcript is written
**Then** the interval is recorded as a gap with a start and an end

**And** each of the following holds:

- A gap is distinguishable from silence. One is speech the app failed on, the
  other is nothing to transcribe, and conflating them is how the failure hides.
- A Note derived from a Transcript with substantial gaps says so, in the same
  voice as every other degradation (AD-17, FR-7).
- Echo-excluded audio is **not** a gap. It is speech the app has, once, on the
  other stream — a test asserts exclusion produces no gaps.

### Story 16.12: The transcript is ordered by when things were said

*(tier T2 · FR-97 as amended · AD-53, AD-4, AD-47, AD-51)*

As someone reading a transcript, I want the two sides of the call interleaved by
when they happened, so that a reply does not appear before the thing it answers.

**Acceptance Criteria:**

**Given** a Session whose two streams did not start at the same instant
**When** the Transcript is merged
**Then** Utterances are ordered by when they were said, not by position in their own file

**And** each of the following holds:

- The offset is **measured**, recorded on the Meeting, and applied by the merge.
- FR-6's claim that a sound "appears at the same offset (±100 ms) in both"
  becomes a test rather than an assertion. Measured on the real library it fails
  by up to **3,278 ms**, with differences ranging from −364 ms to +3,278 ms.
- A Meeting recorded before this existed keeps an unknown offset and is **not**
  silently re-ordered by a guess.
- This was found while building echo detection, where a 920 ms "impossible
  acoustic delay" turned out to be almost entirely the two files starting at
  different times. It is listed last because it is a different defect from the
  echo, not a part of it — and because fixing it at capture rather than at the
  merge is the better answer and belongs to whichever increment owns capture.

### Story 16.13: Minutes knows whether the echo is even possible

*(tier T2 · FR-98 · AD-54, AD-47)*

As someone who sometimes wears headphones and sometimes does not, I want the app
to know which, so that it is not guessing at something it can simply look up.

**Acceptance Criteria:**

**Given** a Session
**When** it starts, and whenever the output device changes
**Then** the output device kind is recorded, and echo handling is off on headphones

**And** each of the following holds:

- Read from the device, not inferred from the signal. The property listener
  already exists for FR-8; this is a fact available for free where Story 16.2
  spends a search to estimate it.
- Every clean recording in the library was on headphones and every affected one
  was not, so this is expected to reproduce the same split the correlation gate
  found — and a test asserts they agree on the library.
- Where the device kind and the signal measurement **disagree**, both are
  recorded and neither is silently preferred. A disagreement is information.

### Story 16.14: The far end is cancelled while recording, not reasoned about later

*(tier T1 · FR-99 · AD-48 as amended, AD-55)*

As someone who takes calls on speakers, I want the other side kept out of my
microphone track in the first place, so that nothing downstream has to guess.

**Acceptance Criteria:**

**Given** a Session where the output device makes echo possible
**When** audio is captured
**Then** the far end is cancelled from the Mic Stream using the System Stream as reference

**And** each of the following holds:

- Runs **inside** the Session, where the reference is aligned by construction.
  Post hoc on two independently-clocked files is the hardest version of the
  problem, and is why the measured offsets ran to 920 ms.
- Includes a **non-linear residual** stage. A linear filter alone is measured
  insufficient — 8.7–10.6 dB against the 20–40 dB needed — which is what a
  first pass at this concluded made cancellation impossible altogether. It made
  *post-hoc linear* cancellation impossible.
- The benefit is **measured with Story 16.1's harness before this is relied on**,
  and published like the model figures. Story 16.4's post-hoc rule is not
  removed on the strength of an expectation.
- Apple's `VoiceProcessingIO` is **not** the mechanism, and the story records
  why so it is not rediscovered: its reference is our own output bus, and the
  meeting audio is played by the conferencing app.
- A recording that was cancelled is distinguishable from one that was not.

### Story 16.15: The people in the room are found by ruling out the call

*(tier T1 · FR-100 · AD-56, AD-47 as amended, AD-30, AD-31)*

As someone recording in a room, I want the app to work out who was with me by
ruling out who was on the call, so that the far end never becomes an attendee.

**Acceptance Criteria:**

**Given** an affected recording
**When** diarization runs
**Then** the in-room voice count falls, and no audio was modified to achieve it

**And** each of the following holds:

- The Mic Stream is diarized **unmodified**. This story exists because the
  previous approach removed audio first and the count went **5→7, 6→6 and 3→5**:
  muting fragments continuous speech and the clusterer splits one voice into
  several.
- Speaker embeddings from the **System Stream** identify the far end, and a
  matching in-room cluster is excluded or relabelled. AD-31's threshold and its
  measured separation already exist for FR-63; this points the same machinery at
  the opposite question.
- **The test asserts the direction of the change**, on the three affected
  recordings, because assuming it is what went wrong last time.
- `local` identification is re-evaluated afterwards, since the user's own voice
  was competing with the far end for a cluster.

### Story 16.16: A pooled figure is something the harness prints

*(tier T6 · FR-101 · AD-50 as amended)*

As someone reading an accuracy claim, I want the number to have come out of a
command, so that the rule about how to aggregate it is enforced rather than
remembered.

**Acceptance Criteria:**

**Given** results for a set of sessions
**When** the harness is asked to pool them
**Then** it prints total errors over total reference words, and the per-session
rows beside them

**And** each of the following holds:

- The pooled figure is **produced**, not assembled. Story 16.1 built a harness
  that prints per-session rows, and every pooled figure in every document since
  was added up by hand from those rows. One of them was added up the way AD-50
  forbids: **82% proper-noun recall on close mics is the mean of 90, 78 and 77.**
  Pooled over pooled reference words it is **81%**.
- Content word error and proper-noun recall pool the same way — total content
  errors over total content reference words, total names found over total names
  present. A recall that averages three session percentages is the same mistake
  wearing a different metric.
- A set with a session missing is **refused**, not silently pooled over what is
  there. Two sessions and three sessions are not comparable figures, and the
  per-session swing is ±8 points — larger than any difference the pooled number
  is used to argue about.
- The per-session rows stay. The pooled figure hides the swing that makes a
  single session untrustworthy, and a reader needs both to trust either.
- The corrected figure is **published as a correction**, not quietly restated.
  Nothing rested on 82 against 81, and that is exactly why it survived: a rule
  is only tested when following it is inconvenient, and this one never was.
- Neither corpus audio nor results enter the repository (§9.1, unchanged).

### Epic 16 FR Coverage

| FR | Story | What it covers |
|---|---|---|
| FR-89 | 16.2 | detect that the mic recorded the system stream |
| FR-90 | 16.4 | exclude before transcription and diarization |
| FR-91 | 16.3 | never exclude what cannot be echo |
| FR-92 | 16.6 | the record says it was affected, and by how much |
| FR-93 | 16.1 | accuracy is measurable from a terminal |
| FR-94 | 16.9 | verify rate against the audio clock |
| FR-95 | 16.10 | an Utterance carries confidence |
| FR-96 | 16.11 | an unreadable interval is a recorded gap |
| FR-17 (amended) | 16.8 | no accuracy claim without a measurement |
| FR-21, FR-22 (amended) | 16.5 | in-room voices counted from retained audio |
| FR-23 (amended) | 16.7 | the same sentence never appears twice |
| FR-97 | 16.12 | the transcript is ordered by when things were said |
| FR-98 | 16.13 | whether echo is possible is read, not inferred |
| FR-99 | 16.14 | the far end is cancelled while recording |
| FR-100 | 16.15 | in-room voices found by ruling out the call |
| FR-101 | 16.16 | the pooled figure is produced by the harness |

