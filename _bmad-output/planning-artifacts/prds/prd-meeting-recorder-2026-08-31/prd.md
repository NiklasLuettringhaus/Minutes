---
title: Minutes — local-first meeting recorder for macOS
status: final
created: 2026-08-31
updated: 2026-09-03
owner: Niklas
mode: headless (-A); increment 2 applied headless (-H update)
revisions:
  - 2026-08-31 increment 2 — first-use feedback after the build shipped. Adds FR-49
    through FR-54 and amends FR-40. Every addition comes from the user operating
    the built app, so this increment carries observation rather than inference.
  - 2026-08-31 increment 3 — summarisation intelligence becomes a chosen, installable
    capability rather than an assumed one. Adds FR-55 through FR-61, amends FR-26,
    FR-27 and FR-52, and amends NFR-1 for the first time in the project's life.
    Preceded by a spike (planning-artifacts/spikes/spike-local-llm-2026-08-31.md)
    and a review (prds/.../review-llm-key-proposal.md).
  - 2026-09-02 increment 5 — running on someone else's Mac. Adds FR-66 through FR-76 and
    amends §12 (the absence of a signing certificate stops being an accepted condition
    once anyone but the author installs the app). Driven by publishing the repository and
    by the first audit of the code against a machine other than the one it was written on;
    every requirement answers a defect verified at a file and line. See
    planning-artifacts/RELEASE-PLAN.md.
  - 2026-09-01 increment 4 — voice enrolment. Adds FR-62 through FR-65, amends FR-21,
    FR-25, FR-46, SM-2, §9.1 and the Glossary, and reverses one line of §6.2. Driven
    by the first four real meetings and by two measurement runs on their audio:
    planning-artifacts/spikes/spike-mic-isolation-2026-09-01.md and
    planning-artifacts/spikes/calibration-speaker-threshold-2026-09-01.md. This is the
    first increment whose central number — the matching threshold — was measured rather
    than chosen.
inputs:
  - _bmad-output/planning-artifacts/briefs/brief-meeting-recorder-2026-08-31/brief.md
  - _bmad-output/planning-artifacts/briefs/brief-meeting-recorder-2026-08-31/addendum.md
  - 2026-09-03 increment 8 — a recording the app cannot vouch for. Adds §4.13
    (FR-84 through FR-88) and amends FR-67 and §9.3. Driven by seven of sixteen
    recordings transcribing into invented dialogue for three days without one
    signal, and by the user's own written bug report finding it before the product
    did.
  - 2026-09-03 increment 7 — the Note is the user's file. Adds §4.12 (FR-77 through
    FR-83) and amends FR-35, FR-40, FR-53, FR-54 and §4.8. Driven by a single user
    report — a Note renamed in Finder, reported missing, and the Meeting then deleted
    permanently — and by a measured reconstruction of what the app did with it.
    Answers §13 Q12.
---

# PRD: Minutes — local-first meeting recorder for macOS

*Working title. The name lives in one constant; rename freely.*

## 0. Document Purpose

This PRD is the contract between the product brief and everything downstream — UX, architecture, epics and stories. It is written for a single implementer building for a single known machine, so it optimises for *implementable* over *persuasive*: features are grouped, functional requirements are globally numbered with stable IDs, and every requirement is stated so that a reviewer can tell whether the built thing satisfies it.

Two inputs already exist and are not duplicated here. `brief.md` carries the product story and the scope boundary. `addendum.md` carries verified technical context — host facts, the chosen transcription stack, the CoreAudio tap sequence and its silent-failure traps, permission and signing constraints. Where this PRD constrains a mechanism it is because the mechanism is load-bearing on the requirement; the *how* otherwise stays in the addendum and the architecture. Vocabulary is fixed by §3 Glossary and used verbatim throughout.

## 1. Vision

Meetings are where decisions get made and where they get lost. Every tool that fixes this — Granola, Otter, Fireflies, Teams recap — fixes it by moving your colleagues' voices onto someone else's servers. For anyone working under a DPA, discussing unreleased product, or simply unwilling to post their working day to a vendor, that is not a trade they can make. So the meeting goes unrecorded, and the notes get taken badly by hand, or not at all.

Minutes is a macOS menu bar app that records a meeting, transcribes it, works out who said what, gives the result a title and tags, and writes one Markdown file into a folder you choose. Every model runs on the machine. There is no account, no server, and no network traffic at run time once models are cached. It is deliberately not a meeting-intelligence platform — one icon, one folder of Markdown files, one small settings window.

**The thesis, in one sentence: this niche is open because local-only cannot support a business, and it is buildable now because transcription, diarization and summarisation all finally run on-device — so the right move is to build the version nobody can sell.** Every requirement below is subordinate to that boundary. Two design choices make it more than a novelty. It notices when a meeting starts, so capturing one costs a click rather than a memory. And it records the microphone and the system output as two separate streams, so "you" is never confused with "them" — the hardest half of speaker attribution is solved by construction instead of by a model guessing.

## 2. Target User

### 2.1 Jobs To Be Done

- **Be fully present in a meeting** without paying for it in lost information — stop trading participation against note-taking.
- **Settle "what did we agree?"** a week later, from a searchable record rather than from memory.
- **Record colleagues and customers without exporting their voices** to a third party, so the tool survives contact with policy and with conscience.
- **Stop having to remember to record.** Anything that depends on discipline before the first sentence of a call will not be used by week three.
- **Keep meeting notes in the same plain-text world as everything else** — grep-able, diff-able, droppable into an existing notes repo, with no export step.
- **Choose the speed/accuracy trade-off per situation** rather than accept one vendor default.

### 2.2 Non-Users (v1)

- Teams wanting a shared meeting archive — there is no server, so there is nothing to share.
- Intel Mac users — the transcription stack requires Apple Silicon.
- Anyone needing a record of a meeting they did not attend — capture happens on the endpoint.
- Anyone who needs App Store distribution, notarized installs, or managed deployment.

### 2.3 Key User Journeys

- **UJ-1. Niklas is offered a recording he would have forgotten to start.**
  Niklas is at his desk with Minutes running and idle in the menu bar. A colleague starts a Slack huddle and he joins. Within a few seconds of Slack taking the microphone, a macOS notification appears: *"Slack huddle detected — record this meeting?"* with **Record** and **Not now**. He clicks **Record**. The menu bar icon turns red. He says nothing else about it and talks for 22 minutes. When the huddle ends, Slack releases the microphone; Minutes notices, stops on its own, and the icon turns amber while it transcribes. A few minutes later a notification says the file is ready and names the meeting. **Edge case:** if he ignores the notification entirely it dismisses itself and nothing is recorded — silence is a "no", never a default yes.

- **UJ-2. Niklas records an ad-hoc conversation manually.**
  A call comes in on a surface Minutes does not detect. He clicks the menu bar icon and picks **Start Recording**; the icon turns red immediately. Mid-call he switches from laptop speakers to AirPods and the recording continues without a gap. He clicks the icon and picks **Stop Recording**. The icon turns amber, then returns to idle when the Markdown file lands in his notes folder.

- **UJ-3. Niklas turns `Speaker 2` into a colleague's name, once.**
  The transcript is right but the speakers are labelled `Me`, `Speaker 1`, `Speaker 2`. He opens the meeting from the Minutes library, reads the first line attributed to `Speaker 2`, recognises it, and renames the label to `Mikkel`. The Markdown file rewrites in place. In next week's recording of the same standup, that voice comes back already labelled `Mikkel` — he does not do this twice for the same person. **Edge case:** if diarization split one person across two labels, he merges them by renaming both to the same name.

- **UJ-4. Niklas sets it up once and picks a model.**
  First launch puts an icon in the menu bar and opens a single window. It asks for microphone access, explains that recording system audio needs a separate permission that macOS will prompt for on first recording, and asks where to save Markdown files. It shows a short list of transcription models with the honest trade-off — speed, accuracy, disk cost — and he picks the default recommendation. It downloads with a progress bar. He is done; the window closes and he does not open it again for weeks.

## 3. Glossary

Downstream artifacts must use these terms verbatim. No synonyms anywhere.

- **Meeting** — one recorded conversation and everything derived from it: audio, Transcript, Metadata, and the Note. Has a start time, a duration, and exactly one Note.
- **Session** — the live act of recording a Meeting, from Capture start to Capture stop. A Session becomes a Meeting once it has been transcribed.
- **Capture** — acquisition of audio during a Session. Always two Streams.
- **Stream** — one of exactly two audio sources in a Capture: the **Mic Stream** (local microphone, attributed to the Local Speaker) or the **System Stream** (all other applications' audio output, containing Remote Speakers). **Amended in increment 9.** The two are not independent: when the user is on speakers rather than headphones, the Mic Stream contains a delayed copy of the System Stream. The System Stream is therefore *authoritative* for far-end speech, and the Mic Stream's copy of it is Echo (FR-89).
- **Echo** — the portion of the Mic Stream that is a delayed copy of the System Stream, arriving acoustically from the speakers. It carries no information the System Stream does not already hold, and is excluded before transcription and Diarization (FR-90). Not to be confused with genuine **Double-talk**, where the user speaks *while* the far end is speaking; that is kept (FR-91).
- **Local Speaker** — the person at the machine. Certain when the Mic Stream held a single voice, and identified when the Enrolled Voice matches exactly one of several in-room voices (FR-63). Default label `Me`.
- **In-Room Speaker** — a voice in the Mic Stream when it held more than one, i.e. someone physically with the user. Anonymous (`In-room 1`, `In-room 2`, …) until renamed; the app does not guess which one is the Local Speaker.
- **Remote Speaker** — a participant on the far end, present only in the System Stream. Anonymous (`Speaker 1`, `Speaker 2`, …) until renamed.
- **Place** — whether a voice was in the room or remote. Derived from which Stream carried it, so it is structural and never inferred — unlike identity.
- **Speaker Label** — the display name for a Local or Remote Speaker in a Note. User-editable.
- **Speaker Profile** — a persisted association between a voice and a Speaker Label, used to reapply a name in later Meetings. Created either by renaming a voice (FR-25) or, for the user's own voice only, by Voice Enrolment (FR-62).
- **Voice Embedding** — a fixed-length vector derived from audio, in which two recordings of the same person land closer together than recordings of two different people. It is the unit of comparison behind every Speaker Profile, and the comparison itself is arithmetic on the vector — nothing platform-specific decides a match.
- **Voice Enrolment** — the one-time act of recording a short sample of the user's own voice so Minutes can recognise it later. Optional and opt-in: nothing is stored until a sample has been recorded, and one control deletes it.
- **Enrolled Voice** — the Speaker Profile produced by Voice Enrolment. Exactly one exists, it belongs to the Local Speaker, and it is the only Speaker Profile the app creates from a deliberate recording rather than from a rename.
- **Diarization** — splitting the System Stream into time segments per Remote Speaker.
- **Transcript** — the ordered list of Utterances for a Meeting.
- **Utterance** — one contiguous span of speech: start time, end time, text, and exactly one Speaker Label.
- **Transcription Model** — a selectable local Whisper model variant, with a size on disk and a speed/accuracy character.
- **Metadata** — the derived, non-transcript content of a Meeting: title, tags, summary, decisions, action items, and the name of the Metadata Backend that produced them.
- **Metadata Backend** — the component producing Metadata. Exactly one per Meeting, never two. **Revised in increment 3** from a two-member set to four, because "the LLM Backend" stopped being a single thing:
  - **Heuristic Backend** — deterministic local extraction. Always available. Produces title and tags; no longer produces a summary (FR-55).
  - **Apple Backend** — Apple's on-device foundation model. Available only when Apple Intelligence is switched on.
  - **Local Model Backend** — a language model the user downloads, running on this Mac. Requires the Metal toolchain (FR-58).
  - **Remote Backend** — a language model reached over the network with a user-supplied key. Off by default; the only Backend that transmits anything (FR-59).
- **Summarisation Backend** — a Metadata Backend capable of producing a summary, decisions and action items: the Apple, Local Model and Remote Backends. The Heuristic Backend is a Metadata Backend but not a Summarisation Backend, and that distinction is what FR-55 gates on.
- **Prerequisite** — a condition the app can detect but cannot satisfy on the user's behalf: Apple Intelligence being switched on, the Metal toolchain being installed, a key being present. Reported with the reason and the remedy, never as a bare unavailability (FR-58).
- **Note** — the single Markdown file written for a Meeting: YAML frontmatter, then Metadata, then Transcript. It is the user's file, in the user's folder: they may rename it, move it within the folder, or edit it, and none of those makes it stop being this Meeting's Note. Its frontmatter therefore carries the Meeting's identity (FR-77).
- **Note Link** — the association between a Meeting and its Note file. Held on the Meeting record and repaired by matching identity, never assumed from a filename (FR-78). A Note Link is *broken* when the recorded file is absent, and *unresolved* when reconciliation has looked and found nothing.
- **Unclaimed Note** — a file in the Notes Folder that Minutes wrote and no Meeting now links to, because its Meeting was deleted. Shown rather than hidden (FR-82); never re-imported, because a Note cannot be parsed back into a Meeting.
- **Notes Folder** — the user-chosen directory where Notes are written.
- **Detection** — passive observation of which applications hold the audio input device, used to recognise that a meeting is underway.
- **Watched App** — an application whose audio-input activity triggers a Detection Prompt. Slack and Microsoft Teams in v1.
- **Detection Prompt** — the notification asking whether to record a detected meeting.
- **Library** — the in-app list of past Meetings.

## 4. Features

### 4.1 Menu Bar Control

**Description:** The app's primary and usually only surface. A menu bar icon shows Session state at a glance and a click opens a short menu. There is no Dock icon and no main window competing for attention. Realizes UJ-2.

The icon has exactly three visual states, distinguishable at a glance and without relying on colour alone (shape changes too, for colour-blind users and for menu bar theme variation): **Idle**, **Recording**, **Transcribing**. State is never ambiguous — a user must never wonder whether they are being recorded.

**Functional Requirements:**

#### FR-1: Menu bar presence
Minutes runs as a menu-bar-only application with no Dock icon and no window on launch. Realizes UJ-2.

**Consequences (testable):**
- The icon appears in the menu bar within 2 seconds of launch.
- No Dock icon appears at any point during normal operation.
- Quitting from the menu removes the icon and terminates the process.

#### FR-2: Three-state icon
The icon renders a distinct appearance for each of Idle, Recording, and Transcribing.

**Consequences (testable):**
- Each state uses both a distinct colour and a distinct glyph, so the states remain distinguishable in greyscale.
- The icon changes state within 500 ms of the underlying state change.
- The icon remains legible in both light and dark menu bars.

#### FR-3: Start and stop a Session from the menu
The user can start a Session and stop a running Session from the menu bar menu. Realizes UJ-2.

**Consequences (testable):**
- The menu offers Start Recording when Idle and Stop Recording when Recording; never both.
- Start transitions the icon to Recording within 500 ms of audio actually being captured, not before.
- Stop ends Capture and begins transcription, transitioning the icon to Transcribing.
- Selecting Start when microphone permission is absent surfaces the permission problem rather than silently failing.

#### FR-4: Session status in the menu
While Recording or Transcribing, the menu shows what is happening.

**Consequences (testable):**
- Recording shows elapsed time, updating at least once per second while the menu is open.
- Recording indicates whether the System Stream is being captured or only the Mic Stream.
- Transcribing shows a progress indication and which Meeting is being processed.

#### FR-5: Menu access to the main window and Quit
The menu provides entry to the main window's panes and to Quit.

**Consequences (testable):**
- The menu contains no more than 8 items in any single state; the menu stays scannable.
- Opening Meetings or Settings from the menu brings the single main window to the front, focused, on the requested pane — never a second window.

#### FR-49: Elapsed time is visible without opening the menu
While Recording, the menu bar itself shows how long the Session has been running.

**Consequences (testable):**
- The elapsed time is readable from the menu bar with the menu closed, and advances at least once per second.
- It disappears the moment Recording ends, so the menu bar never implies a Session that is not running.
- Transcribing does not show a timer: elapsed time answers "how much have I recorded", which is not a question about processing.

**Notes:**
- FR-4 already required elapsed time *inside the open menu*, and that shipped. This is a separate requirement: the user's ask was to know the answer without clicking. Both hold.

#### ~~FR-50: The Recording indicator is animated~~ — **withdrawn 2026-09-01**
~~While Recording, the menu bar indicator carries a slow pulse.~~ **The Recording indicator is a steady solid dot and does not animate.**

*Withdrawn on use, by the person who asked for it: "revert the change that made the recording icon animated. the solid red circle was better." Built in increment 2 from "animate the red dot slightly", shipped, lived with, and rejected.*

**Consequences (testable):**
- Nothing in the menu bar animates, in any state. FR-2's silhouette-and-tint rule carries Recording on its own, which it always did — the pulse was explicitly never allowed to be the signal (NFR-7), so removing it costs no information.
- The icon image is constant while a state holds, so it is built once rather than per tick. The pulse was the only reason it was ever rebuilt.
- The elapsed-time tick (FR-4, FR-49) survives untouched: it updates text, not the icon.

**Notes:**
- The withdrawal is recorded rather than deleted, because the reasoning that produced it was sound and the outcome still went the other way. A status light that varies invites a second look to work out *whether* it is varying, and the most-seen element in the product should not ask that of anyone. §14 recorded "that it should be a slow pulse rather than a blink" as an assumption; the assumption was wrong in a way only use could establish.
- It retires §13 Q10, which asked whether the pulse survived NFR-3 over a two-hour Session. The question is moot and the answer is now free.

**Feature-specific NFRs:**
- Idle CPU use attributable to the menu bar component is negligible (see NFR-3), and with FR-50 withdrawn the icon does not animate in *any* state — which is strictly cheaper than the exemption FR-50 used to need.

---

### 4.2 Meeting Capture

**Description:** Every Session captures two Streams simultaneously: the Mic Stream and the System Stream. This is the mechanism behind the product's speaker-attribution claim, so it is stated as a requirement rather than left to architecture. The two Streams are recorded to disk separately and share one time base, so Utterances from either can be merged into one ordered Transcript. Realizes UJ-1, UJ-2.

Capture must survive the ordinary disturbances of a working day: output device changes mid-call, sleep and wake, and the user talking for two hours.

**Functional Requirements:**

#### FR-6: Dual-stream capture
A Session captures the Mic Stream and the System Stream concurrently, as separately addressable audio.

**Consequences (testable):**
- Two audio artifacts exist for a Session, each independently decodable.
- Both carry timestamps on a shared time base; a sound occurring at a known wall-clock moment appears at the same offset (±100 ms) in both.
- Audio is captured at a sample rate and format suitable for the Transcription Model without a lossy intermediate step.
- **Amended in increment 9.** The two Streams are separately addressable but not acoustically independent: on speakers, the Mic Stream contains the System Stream delayed by the speaker-to-microphone path. Measured at cross-correlation 0.771 with a 39 ms lag on one real recording. Nothing downstream may assume that a voice in the Mic Stream was in the room.

#### FR-7: Graceful degradation to Mic-only
If the System Stream cannot be captured, the Session proceeds with the Mic Stream alone rather than failing. `[ASSUMPTION: degrading rather than refusing to record is inferred; a user who declined a permission still wants their own side of the call captured.]`

**Consequences (testable):**
- A Session starts successfully when system-audio permission has not been granted.
- The user is told, at start and in the menu, that only the Mic Stream is being captured — degradation is never silent.
- The resulting Note records that the System Stream was absent, so a transcript with no Remote Speakers is not mistaken for a monologue.

#### FR-8: Survive output device changes
Changing the default output device during a Session does not end the Session or lose the System Stream.

**Consequences (testable):**
- Connecting AirPods mid-Session keeps the System Stream capturing; any gap is under 2 seconds.
- Disconnecting the active output device likewise does not terminate the Session.
- Device changes are recorded in the Session log so an audio gap is explainable after the fact.

#### FR-9: Long-Session durability
A Session can run for at least 3 hours without loss.

**Consequences (testable):**
- Audio is committed to disk incrementally during Capture, not buffered in memory until stop.
- Memory use during Capture stays flat over time rather than growing with duration (see NFR-4).
- If the app crashes or is force-quit mid-Session, the audio captured up to that point remains on disk and is recoverable into a Meeting.

#### FR-10: Do not capture while Idle
No audio is captured outside an explicit Session.

**Consequences (testable):**
- Between Sessions, no audio device is held open by the app and no audio data is written.
- Detection (§4.3) reads only device-activity metadata; it never reads audio content. This is verifiable by inspection and is a privacy invariant, not an optimisation.

---

### 4.3 Meeting Detection and Prompt

**Description:** Minutes watches which applications hold the audio input device. When a Watched App takes the microphone, Minutes offers to record. It observes metadata only — never audio content — and it never starts recording on its own. Realizes UJ-1.

Detection is a convenience over a fundamentally unreliable signal, so the requirements are shaped by that honesty: false positives are expected and made cheap to dismiss, and the user can silence any app or the whole feature.

**Functional Requirements:**

#### FR-11: Detect audio-input activity by application
Minutes determines which applications are actively using the audio input device, and their identity. Realizes UJ-1.

**Consequences (testable):**
- Joining a Slack huddle is detected within 15 seconds.
- Joining a Microsoft Teams call is detected within 15 seconds.
- Detection works when the app routes audio through helper processes rather than its main process — matching is by application identity, not by an exact process match.
- Detection works with a Bluetooth input device (AirPods), not only built-in and wired microphones.
- Releasing the input device is detected within 15 seconds.

#### FR-12: Debounced Detection Prompt
When a Watched App holds the input device for a sustained interval, Minutes shows a Detection Prompt. Realizes UJ-1.

**Consequences (testable):**
- The Prompt names the detected application.
- The Prompt offers Record and a decline, and starts nothing unless Record is chosen.
- An ignored Prompt expires without starting a Session.
- Brief input activity below the debounce threshold produces no Prompt, so notification sounds and device probes do not trigger it.
- At most one Prompt is shown per detected meeting; a Prompt is not repeated for a Session already declined.

#### FR-13: Accepting a Prompt starts a Session
Choosing Record on a Detection Prompt starts a Session identical to a manually started one. Realizes UJ-1.

**Consequences (testable):**
- The Session records both Streams per FR-6.
- The Session records which application triggered it, and the Note reflects it.
- Time between clicking Record and audio being captured is under 2 seconds.

#### FR-14: Auto-stop on meeting end
A Session started from a Detection Prompt stops automatically when the triggering application releases the input device. Realizes UJ-1. `[ASSUMPTION: auto-stop was not requested — only the start prompt was. It is inferred from the same motivation (not having to remember) and deliberately restricted to detected Sessions so a manual recording is never cut short.]`

**Consequences (testable):**
- The Session stops within 30 seconds of the application releasing the input device.
- A manually started Session is never auto-stopped — only the user stops it.
- Auto-stop runs the same completion path as a manual stop, producing a Note.

#### FR-15: Suppress detection per app and globally
The user can stop being asked, for one Watched App or for all of them.

**Consequences (testable):**
- A per-app suppression is offered at the point of declining, not buried in Settings.
- Suppressing an app prevents further Prompts for it while leaving other Watched Apps active.
- Detection can be disabled entirely in Settings, after which no Prompt appears and no audio-process polling occurs.
- Suppression choices survive an app restart.

**Notes:**
- `[ASSUMPTION]` A Slack huddle cannot be distinguished from other Slack microphone use through audio-device observation alone. The accepted consequence is a false-positive Prompt when Slack takes the mic for another reason; FR-12 and FR-15 make that cheap. Distinguishing them would require reading Slack's state, which is out of scope and hostile to the privacy claim.

---

### 4.4 Local Transcription

**Description:** When a Session stops, its audio becomes a Transcript using a locally cached Whisper model running on the Neural Engine. Nothing leaves the machine. The user chooses the model once and can change it; the choice is presented as an honest trade-off rather than as a set of opaque names. Realizes UJ-4.

Model files are downloaded on first use — the one legitimate network activity in the product, and stated as such in the UI.

**Functional Requirements:**

#### FR-16: Transcribe locally after Capture ends
Stopping a Session produces a Transcript, computed entirely on-device.

**Consequences (testable):**
- Transcription starts automatically on Session stop, with no user action.
- Each Utterance carries a start time, an end time, and text.
- The app makes no network request during transcription, verifiable by network monitoring.
- Transcription of a 30-minute Session with the default model completes in under 5 minutes on the target machine.
- **Amended in increment 9.** Echo exclusion (FR-90) runs before transcription, not after. Transcribing first and de-duplicating afterwards would leave FR-21's speaker count already wrong.

#### FR-17: Select a Transcription Model
The user can choose among available Transcription Models. Realizes UJ-4.

**Consequences (testable):**
- The list states, per model, its relative speed and its size on disk.
- The currently active model is unambiguous.
- The available list reflects what the transcription stack actually offers rather than a hardcoded list that can drift.
- A recommended default is pre-selected so a user can proceed without choosing.
- **Amended in increment 9: an accuracy claim requires a measurement.** The
  original wording promised "its relative accuracy" per model, and the product
  duly showed a five-point accuracy rating for every model — derived from
  nothing. Speed was always measured (`--benchmark`); accuracy never was. A
  model's accuracy is now stated only where FR-93's harness has measured it,
  and is absent, not estimated, everywhere else. An unmeasured rating is worse
  than no rating: it looks like knowledge.

#### FR-18: Download and cache models with visible progress
Selecting a model that is not present downloads it, showing progress. Realizes UJ-4.

**Consequences (testable):**
- Download progress is shown as a proportion, not an indeterminate spinner.
- A model already cached is used without any network access.
- A failed or interrupted download reports the failure and leaves no partial model that would later be loaded as valid.
- The UI states plainly that model download is the only time the app uses the network.

#### FR-19: Transcription failure is reported, and audio is kept
A Session whose transcription fails does not lose its audio.

**Consequences (testable):**
- The failure is surfaced to the user with a reason, not swallowed.
- Session audio is retained so transcription can be retried.
- Retry is available from the Library without re-recording.

#### FR-20: Queue concurrent work
A Session that stops while another Meeting is transcribing is not lost.

**Consequences (testable):**
- Transcription requests are processed serially; two models never load simultaneously and contend for memory.
- A Session can be recorded while a previous Meeting is still transcribing.
- The queue is in-memory only and is discarded on quit; the recorded audio is not (FR-19), so a queued Meeting can still be transcribed later from the Library.

---

### 4.5 Speaker Attribution

**Description:** Speakers are resolved by combining a structural fact with a model. *Where* a voice was is structural: the Mic Stream is the room, the System Stream is the far end, and neither can be wrong. *Who* a voice is, is inferred. The two Streams are merged into one chronological Transcript. Anonymous labels are renameable, and a rename is remembered so the same voice arrives pre-named next time. Realizes UJ-3.

**Amended in increment 4.** One in-room voice can now be identified rather than guessed. When several people share the microphone the app previously refused to say which one was the user — correct, and still not an answer. Voice Enrolment (FR-62) lets the user record their own voice once, and FR-63 uses it to identify them among the in-room voices. Everything else in this section is unchanged: place stays structural, non-user in-room voices stay anonymous until renamed, and with no Enrolled Voice the behaviour is exactly what it was.

**Functional Requirements:**

#### FR-21: Attribute the Mic Stream to in-room voices
All Utterances derived from the Mic Stream are attributed to an in-room voice — the Local Speaker when the Mic Stream held a single voice, otherwise an anonymous In-Room Speaker.

*Revised 2026-08-31 on user correction: the microphone is not necessarily the user. In a meeting room it captures the user and whoever is beside them, and attributing all of it to the Local Speaker puts colleagues' words in the user's mouth.*

**Consequences (testable):**
- No Mic Stream Utterance is ever attributed to a Remote Speaker, and no System Stream Utterance is ever attributed to an in-room voice. This is structural and cannot be wrong.
- When the Mic Stream contains exactly one voice, it is the Local Speaker. This attribution cannot be wrong either.
- When the Mic Stream contains more than one voice, each becomes a distinct In-Room Speaker and **none is claimed to be the Local Speaker** — unless an Enrolled Voice identifies one of them (FR-63).
- **Amended in increment 9.** In-room voices are counted only from Mic Stream audio that is not Echo. Counting them from the raw Mic Stream put the far end in the room: one real recording produced **six** In-Room Speakers and never identified the user at all, because their own voice was one polluted cluster among six. The number of people in the room is not evidence of anything if the microphone was also hearing the call.
- **Amended (increment 4):** with an Enrolled Voice present and matching exactly one in-room voice, that voice is the Local Speaker. This is an identification, not an assumption, and it is recorded as such on the Meeting. With no Enrolled Voice, or no unambiguous match, the original rule stands untouched.
- Mic Stream speech the Diarizer cannot place at all, when several voices share the microphone, is labelled as unidentified in-room speech — never as the user. *(Added in increment 4 after the defect: such speech fell through to the Local Speaker default and printed 14 utterances of a neighbouring conversation as the user's own words.)*
- The Meeting records that the room held several people, and the Note discloses it.
- The Local Speaker Label defaults to `Me` and is user-editable in Settings. It is the only place that name comes from, including when the Local Speaker was identified by enrolment.
- Naming an In-Room Speaker creates a Speaker Profile, so the same voice is recognised in later Meetings (FR-25). Naming *oneself* is no longer the mechanism by which the app learns the user's voice — FR-62 is.

#### FR-22: Diarize both Streams
Utterances are assigned speaker labels by on-device Diarization, run separately on each Stream: the System Stream yields Remote Speakers, and the Mic Stream yields the Local Speaker or In-Room Speakers per FR-21.

**Consequences (testable):**
- Diarization runs entirely on-device with no network access.
- Each Stream is diarized independently; a speaker found in one Stream is never merged with one found in the other.
- A Stream with a single speaker yields one label, not several.
- The number of Remote Speakers is determined from the audio; the user is not required to state it in advance.
- Diarization failure degrades to a single `Speaker` label for the whole System Stream rather than failing the Meeting.
- **Amended in increment 9.** The Mic Stream is diarized *after* Echo exclusion (FR-90). This is the requirement the defect actually broke: duplicated text is an annoyance, but a phantom attendee is a false statement about who was present.

#### FR-23: Merge Streams into one ordered Transcript
The Transcript interleaves Mic and System Stream Utterances in chronological order.

**Consequences (testable):**
- Utterances appear in ascending start-time order regardless of source Stream.
- Overlapping speech from both Streams is represented as separate Utterances, not merged or dropped — people talk over each other and the record should show it.
- Every Utterance in the Transcript carries exactly one Speaker Label.
- **Amended in increment 9.** The clause above is about *genuine* overlap — two people speaking at once. It is not licence for the same speech to appear twice from two Streams. On affected recordings **33.6% and 32.2% of all Transcript words were one utterance recorded on both Streams**, and the merge dutifully preserved both copies. After FR-90 the invariant is testable: no Mic Stream Utterance may substantially repeat a time-overlapping System Stream Utterance.

#### FR-24: Rename a Speaker Label
The user can rename any Speaker Label on a Meeting. Realizes UJ-3.

**Consequences (testable):**
- Renaming updates every Utterance carrying that label, and the Note is rewritten in place.
- Renaming two labels to the same name merges them, which is the correct fix for one person split across two labels.
- A rename is applied without re-running transcription or Diarization.

#### FR-25: Remember a named voice across Meetings
Naming a Remote Speaker creates a Speaker Profile so the same voice is labelled automatically in later Meetings. Realizes UJ-3. `[ASSUMPTION: persisting names across Meetings goes beyond the literal ask of "try and figure out speakers"; inferred because the ask is about usefulness, not labels.]`

**Consequences (testable):**
- After naming a Remote Speaker in one Meeting, a later Meeting containing that voice presents that name rather than an anonymous label.
- An automatically applied name is marked as inferred, so a wrong match is recognisable and correctable.
- A wrong automatic match can be corrected, and the correction updates the Speaker Profile rather than only the one Meeting.
- Speaker Profiles are stored locally and are never transmitted.

**Consequences added in increment 4:**
- Passive learning applies to other people and **not** to the user. It needs a correct label to learn from, and several voices on one microphone provide none. The user's own voice is learned by Voice Enrolment (FR-62) and by nothing else.
- The Enrolled Voice is excluded from FR-25's automatic name application. It answers one question — which in-room voice is the user — and never puts a name on a voice by itself.

**Notes:**
- `[NOTE FOR PM]` FR-25 was the highest-uncertainty requirement in the PRD, resting on whether voice-embedding similarity holds up across separate recordings. **Measured on 2026-09-01** (see `spikes/calibration-speaker-threshold-2026-09-01.md`) and the answer is yes for in-room voices: the same voice landed 0.058–0.248 apart across four independent Meetings, while different in-room voices in one Meeting stayed 0.596 and above. §13 Q4 is answered for that case and narrowed for Remote Speakers, where the populations touch and the inference stays correctable rather than certain.
- The threshold that decides a match was never calibrated until that run, and is now. See FR-65.

#### FR-51: See and curate the remembered voices
The set of Speaker Profiles is visible as a list, and each entry can be renamed or forgotten on its own.

**Consequences (testable):**
- Every remembered voice appears with the name it will apply, so the user can tell what Minutes thinks it knows without recording a Meeting to find out.
- Each entry can be forgotten individually. "Forget all" remains, but is no longer the only option.
- Each entry can be renamed, and the rename applies to the Profile — so the next Meeting containing that voice uses the corrected name.
- An entry shows enough provenance to be judged: how many Meetings contributed to it, and when it was last matched.
- The list states that Profiles never leave the Mac, in the same place the data is shown.

**Notes:**
- This closes a gap FR-25 left open. FR-25 created Profiles and FR-24 corrected a name *within a Meeting*, but the Profile set itself was write-only: the settings pane offered one destructive "Forget all remembered voices" and no way to see what would be lost.
- `[ASSUMPTION: renaming a Profile does not retroactively relabel Meetings already written. Retro-editing was not requested, and it would rewrite Notes the user may have edited by hand.]`

#### FR-62: Enrol the user's own voice
The user can record a short sample of their own voice, once, and Minutes stores a fingerprint of it on this Mac.

**Consequences (testable):**
- The affordance is reachable from the Setup Checklist as its own row, marked optional, following the existing row anatomy (§10.3, FR-46). It does not introduce a second onboarding style.
- **Nothing is stored until a sample has been recorded.** Reading the row, opening the card, or starting and cancelling a recording all leave the machine exactly as they found it. This is what makes it opt-in rather than a default with an off switch.
- The recording runs 20–30 seconds — long enough for a stable fingerprint, short enough to do once — and the app states the duration before it starts, not after.
- Enrolment captures the Mic Stream only. It never opens the System Stream, so it never triggers the system-audio permission and never records the far end.
- The sample is converted to a fingerprint and the audio is deleted in the same operation. Only the fingerprint persists, and the UI says so where the recording happens.
- An enrolment run produces no Meeting and writes no Note, and never appears in the Library — FR-47's rule, for the same reason.
- The result is reported as a measurement, not a reassurance: how many seconds of speech were found, and whether it held exactly one voice. A sample containing a second voice is rejected *with that reason*, because a fingerprint of two people is worse than no fingerprint.
- Re-recording replaces the fingerprint rather than averaging into it. A re-record is a correction, and correcting means the old value goes.
- Enrolment works with microphone permission alone. It requires no model download, no network, and no Summarisation Backend.

**Notes:**
- This reverses one line of §6.2 for one person only. The reasoning is there, and it is the requirement's real justification.

#### FR-63: Use the Enrolled Voice to identify the user among in-room voices
When the Mic Stream holds several voices and an Enrolled Voice exists, the in-room voice matching it is the Local Speaker.

**Consequences (testable):**
- With no Enrolled Voice, behaviour is exactly what it is today: several mic voices become anonymous In-Room Speakers and none is claimed to be the user. Enrolment adds an identification; it removes no honesty.
- **Place is unaffected.** Enrolment changes which in-room voice is the Local Speaker, never whether a voice was in the room. A Mic Stream Utterance can still never become a Remote Speaker.
- Matching is a comparison of Voice Embeddings and nothing else. It must not depend on any platform-specific capability, so the same rule is implementable on another system.
- A match is accepted only when it is both **close enough and unambiguous**: the nearest in-room voice must be within the calibrated threshold, and it must be clearly nearer than the next one. Two in-room voices both close to the Enrolled Voice is either a Diarization split or a genuine ambiguity, and in both cases the app claims nothing.
- When nothing matches, the Meeting is attributed exactly as it is today, including unidentified in-room speech for mic audio that could not be placed at all.
- Enrolment draws no line between a participant and a bystander. Both are "not the user". A conference room normally holds several participants and that is the correct reading; deciding which non-user voice belongs in the Note remains the per-Meeting Exclude control's job and is never automated.
- The Meeting records that the Local Speaker was identified by enrolment, and how close the match was, so the claim is checkable after the fact.

**Notes:**
- The measured problem this solves: in an 8-person Slack huddle with two colleagues talking beside the user, 723 of 1501 transcript words (48%) were the neighbouring conversation, and the app could separate those voices but not say which was the user's. Separation without identification is half an answer.

#### FR-64: The Enrolled Voice is visible, distinguishable and deletable
The Enrolled Voice appears in the remembered-voices list, marked as the user's own, and is removable in one click.

**Consequences (testable):**
- FR-51's list keeps working unchanged and shows the Enrolled Voice as a *distinct kind* of entry, not as one more remembered colleague.
- One control deletes it. Deletion returns attribution to pre-enrolment behaviour for Meetings processed afterwards; Meetings already written keep their labels, per FR-51's rule.
- "Forget all" removes the Enrolled Voice too, and its confirmation says so — a destructive action enumerates what it destroys (FR-40).
- The Enrolled Voice is biometric-adjacent data under §9.1: stored locally, never transmitted under any configuration *including* a configured Remote Backend, and never written into a Note or a log.
- The entry states where it came from and how much audio produced it, so it is judgeable the way a colleague's Profile already is.
- The user's display name still comes from the one setting that owns it (FR-21). The Enrolled Voice never applies a name of its own.

#### FR-65: The match is disclosed, correctable, and has no exposed dial
An identification is visible in the app, fixable when wrong, and produced by a threshold the user cannot set.

**Consequences (testable):**
- The meeting detail says the Local Speaker was recognised from the Enrolled Voice, and how close the match was. A silent identification would be indistinguishable from the guess it replaced.
- A wrong identification is corrected with the rename and Exclude controls that already exist (FR-24, FR-40). No new correction mechanism is added, and none is needed.
- **There is no user-facing control for the matching threshold, for voice-activity parameters, or for a speaker count.** Exposing an outcome is a product decision; exposing a mechanism is a defect.
- The threshold is one calibrated constant, recorded with the measurement and the date that produced it, so a future change has something to argue against rather than a silence to slip through.
- Calibrated on real data, 2026-09-01: the same in-room voice measured 0.058–0.248 apart across four independent Meetings; different in-room voices within one Meeting measured 0.596 and above. The shipped value moves from 0.45 — never calibrated — to **0.35**, which keeps 41% headroom above the observed same-voice maximum and stays 1.7× below the tightest genuine in-room impostor.
- A limit found by the same measurement is recorded rather than hidden: for Remote Speakers the two populations touch (same speaker up to 0.248, different speakers from 0.254), so **no threshold separates them**. Remote matching therefore stays a correctable inference, rendered as inferred per FR-25, and is not presented as a fact.

**Notes:**
- `[NOTE FOR PM]` The threshold is the single number most likely to be set wrongly and the hardest to reason about, and a wrong value puts the wrong name on someone's words with no way to notice. Ship one value; expose corrections. Recorded here so the instruction survives the increment that received it.
- The two false matches 0.35 admits are both Remote-vs-Remote. They are recoverable in one rename because FR-25 marks an automatic name as inferred and FR-51 makes the Profile visible. A threshold tight enough to exclude them (0.25) leaves 0.002 of headroom above the observed same-voice maximum, at which point enrolment stops working — which is a worse failure than a correctable name.

---

### 4.6 Meeting Metadata

**Description:** Every Meeting gets a title, tags and a summary derived on-device from its Transcript, plus decisions and action items where they can be found. `[ASSUMPTION: the request named "the title, tags etc."; summary, decisions and action items are this PRD's reading of "etc." and are the largest interpretive leap in the document.]` Two Metadata Backends satisfy this: the LLM Backend uses Apple's on-device foundation model; the Heuristic Backend uses deterministic local extraction. The LLM Backend is preferred when available and the Heuristic Backend always works — including on the target machine today, where Apple Intelligence is switched off.

**Functional Requirements:**

#### FR-26: Derive Metadata for every Meeting
Every Meeting receives a title and a tag set. A summary, decisions and action items are produced only when a Summarisation Backend capable of them is available.

**Consequences (testable):**
- No Meeting is ever left untitled; a fallback title derived from date, time and detected application is always available.
- Tags are a small set (target 3-6), lowercase and consistent enough to be usable for filtering across Meetings.
- Metadata generation runs on-device unless a Remote Summarisation Backend is configured and consented for that Meeting (FR-59, NFR-1).
- **Amended (increment 3):** the summary is no longer guaranteed. With no capable Backend, the Note carries the Transcript, the title and the tags, and omits the summary, decisions and action items sections entirely rather than filling them with sentence extracts. See FR-55.

**Notes:**
- The title guarantee is deliberately kept while the summary guarantee is dropped. A Meeting with no title is unfindable; a Meeting with no summary is merely less useful, and an honestly absent summary beats a misleading one (§9.3).

#### FR-27: Apple's on-device foundation model is one available Backend
When the on-device foundation model is available, it can produce the Metadata. It is no longer the only path to a real summary.

**Consequences (testable):**
- Backend availability is checked at run time, not assumed at build time.
- **Amended (increment 2):** the preference is a default, not a rule. FR-52 lets the user pin a Backend, and an explicit choice wins over availability.
- **Amended (increment 3):** this Backend is one entry in the Summarisation Backend list (FR-56), not a privileged tier. When it is unavailable the reason is stated and actionable (FR-58) rather than silently falling through.
- When it is unavailable *because Apple Intelligence is switched off* — as opposed to the device being ineligible — the app says so and says where to turn it on. Those two cases are distinguishable at run time and must not be reported identically.

**Notes:**
- Demoted from "the LLM Backend" on the user's explicit instruction: *"Lets not rely on apple intelligence for this. But keep it as a possibility."* The demotion is the requirement.
- When the model is unavailable — including because Apple Intelligence is disabled — the Heuristic Backend runs instead and the Meeting still completes.
- Output is requested as a typed structure rather than parsed out of free text, so a malformed generation cannot corrupt a Note.
- A Transcript too long for the model's context is handled by summarising in parts and combining, not truncated silently.

#### FR-28: Heuristic Backend always available
The Heuristic Backend produces Metadata with no model and no network.

**Consequences (testable):**
- It runs with no downloaded assets and no Apple Intelligence.
- It is deterministic: the same Transcript yields the same Metadata, which makes it testable.
- It extracts tags by keyphrase salience, a summary by sentence selection, and a title from the strongest early keyphrase.
- It completes in under 2 seconds for a 2-hour Transcript.

#### FR-29: Extract decisions and action items
Where the Transcript contains decisions or action items, they appear in the Note.

**Consequences (testable):**
- Each extracted item references the timestamp it came from, so a reader can verify it against the Transcript.
- Absence is represented honestly — an empty section or none at all, never invented content.
- Action items name an owner where the Transcript identifies one, and omit the owner where it does not.

#### FR-30: Record which Backend produced the Metadata
Every Note names its Metadata Backend.

**Consequences (testable):**
- The Note's frontmatter identifies the Backend and the Transcription Model used.
- A reader can therefore tell whether a summary came from a language model or from keyphrase extraction — provenance is never ambiguous.

#### FR-52: The Metadata Backend is visible and selectable in the app
Settings names which Backend will produce Metadata and why. **Amended (increment 3):** the two-way choice becomes a selection from the Summarisation Backend list (FR-56), and the precedence rule is stated in FR-57 rather than implied by availability.

**Consequences (testable):**
- Settings states which Backend is active in plain language, and when the LLM Backend is unavailable it states the reason rather than only the outcome.
- The user can force the Heuristic Backend even when the LLM Backend is available, because a deterministic summary is sometimes the one you want.
- Choosing a Backend affects Meetings processed afterwards; it does not silently rewrite Metadata already derived.
- No setting implies a cloud model, a model download, or an API key exists — because none do (§9.1).

**Notes:**
- Prompted by the user asking what performs summarisation and finding no setting for it. FR-30 recorded provenance in the *Note*, which is the wrong surface for the question "what is this app doing" — the Note is read after the fact, and only if you open it.
- The honest content of this pane on the target machine is that Apple Intelligence is disabled, so summarisation is keyphrase extraction. §9.3 requires that be said, not softened.

#### FR-55: Derived content appears only when something real produced it
The summary, decisions and action items are gated on a Summarisation Backend that can genuinely produce them.

**Consequences (testable):**
- With no capable Backend selected or available, the Note contains the Transcript, the title and the tags, and the summary, decisions and action items sections are absent — not empty-with-a-heading, and never filled with extracted sentences.
- The Library's meeting detail says why those sections are missing and links to where that is fixed.
- Keyphrase extraction continues to produce the **title and tags**, which it does adequately. It no longer produces a summary.
- A Meeting summarised earlier by a different Backend keeps its summary. Changing this setting never retroactively strips or rewrites content already derived.

**Notes:**
- This is the increment's one uncontested improvement, and it stands on its own: it makes the product more honest today at no cost. §9.3 already required that absence be represented honestly rather than as invented content; the sentence-extract summary was in breach of that and read convincingly enough to be believed.

---

### 4.7 Markdown Note Output

**Description:** The deliverable of the whole product is one Markdown file per Meeting, in a folder the user chose, readable without the app and useful without editing. Realizes UJ-1, UJ-2, UJ-3.

**Functional Requirements:**

#### FR-31: Write one Note per Meeting
Each completed Meeting produces exactly one Markdown file in the Notes Folder.

**Consequences (testable):**
- The filename is stable, sorts chronologically, and is readable — date, time and a slug of the title.
- Filename collisions are resolved without overwriting an existing Note.
- The file is valid UTF-8 Markdown and opens correctly in a plain text editor and in Obsidian.

#### FR-32: YAML frontmatter carrying Metadata
The Note begins with YAML frontmatter.

**Consequences (testable):**
- Frontmatter includes title, date, start time, duration, participants (Speaker Labels), tags, Transcription Model, Metadata Backend, and whether the System Stream was captured.
- The YAML parses with a standard parser; titles containing colons or quotes do not break it.
- Tags are emitted as a YAML list so note tools can index them.

#### FR-33: Body structure — Metadata then Transcript
The body presents the derived content before the raw record.

**Consequences (testable):**
- Order is summary, then decisions, then action items, then the full Transcript.
- Empty sections are omitted rather than left as empty headings.
- Transcript entries show a timestamp and a Speaker Label, and are grouped so a single speaker's continuous speech is not fragmented line by line.
- Timestamps are relative to Session start and formatted so they can be scanned.

#### FR-34: Choose the Notes Folder
The user chooses where Notes are written. Realizes UJ-4.

**Consequences (testable):**
- A default location is used if the user does not choose, so the app works before it is configured.
- The chosen folder persists across restarts and is re-accessible after restart without re-prompting.
- If the folder is missing or unwritable at write time, the failure is surfaced and the Note is retained so nothing is lost.

#### FR-35: Rewrite a Note in place on edit
Editing a Meeting's title or Speaker Labels updates its Note. Realizes UJ-3.

**Consequences (testable):**
- The Note is rewritten to reflect the change without creating a second file.
- A title change that would change the filename either renames the file or leaves it stable — the behaviour is defined, not incidental, and never leaves two Notes for one Meeting.
- **Amended (increment 7):** the app renames the file only while the name on disk is still the name the app last wrote. Once the user has renamed it, their name is authoritative and a title change no longer touches the filename — the Note's title changes inside the file and the file keeps the name the user gave it. Renaming a user-named file back to a derived one destroys a decision the user made deliberately, which is worse than a filename that no longer matches its title.
- **Amended (increment 7):** a rewrite whose target file is absent does not write a new file until reconciliation (FR-78) has looked for the existing one. Writing first is how a renamed Note becomes a permanently orphaned duplicate.

#### FR-53: A Meeting's Note is verified to exist, and a missing one can be rewritten
Recording that a Note was written is not the same as the file being there. Minutes checks, and offers to fix.

**Consequences (testable):**
- A Meeting marked complete whose Note file is absent from the Notes Folder is shown as such, not as complete.
- Such a Meeting can have its Note rewritten from the stored record, with no re-transcription and no loss of Speaker Labels or edits held in the record.
- A Note deleted deliberately in Finder is not silently recreated; rewriting is a user action.
- The check never parses the Note. A missing Note is reported and rewritten *from* the record, never inferred back *into* it (AD-9).
- Moving the Notes Folder does not mark every past Meeting broken: the check is against the folder currently in effect, and its result is a display state, not a mutation of history.

- **Amended (increment 7):** "missing" now means *not found after reconciliation* (FR-78), not *absent from the recorded path*. Until this amendment the app reported a renamed Note as missing, which is a false claim about the user's folder — the file was there, and the user was looking at it.
- **Amended (increment 7):** rewriting is offered alongside locating (FR-79), and the copy distinguishes them: rewriting produces a fresh file from the record, locating adopts a file that already exists. Offering only the first makes the app's remedy for a broken link the action that makes the break permanent.

**Notes:**
- Observed, not hypothesised. Seven Meetings held `stage: written` and a filename while two files existed on disk; the write had been discarded by a sandbox during development and nothing ever noticed. The requirement is that the app can tell the difference.

---

### 4.8 Library

**Description:** A pane in the main window (§4.9) listing past Meetings so the user can find one, read it, fix a Speaker Label, retry a failed transcription, reveal the Note in Finder, or repair the link to a Note the user has renamed or moved (§4.12). `[ASSUMPTION: a browsing surface was not requested; it is inferred as necessary because renaming (FR-24) and retry (FR-39) need somewhere to live, and the request did ask for a small clean UI.]` It is a utility view over the Notes, not a second home for the data. Realizes UJ-3.

**Functional Requirements:**

#### FR-36: List past Meetings
The Library lists Meetings in reverse chronological order.

**Consequences (testable):**
- Each row shows title, date, duration, and participant labels.
- A Meeting still transcribing is shown with that state; a failed one is shown as failed.
- The list remains responsive with at least 500 Meetings.

#### FR-37: Open and read a Meeting
Selecting a Meeting shows its Metadata and Transcript.

**Consequences (testable):**
- The Transcript is readable in-app with Speaker Labels and timestamps.
- The Note can be revealed in Finder and opened in the user's default Markdown editor.

#### FR-38: Edit title and Speaker Labels from the Library
The user can rename a Meeting and its Speaker Labels here. Realizes UJ-3.

**Consequences (testable):**
- Renaming a Speaker Label from the Library satisfies FR-24 and FR-25.
- Editing the title rewrites the Note per FR-35.

#### FR-39: Retry a failed transcription
A Meeting whose transcription failed can be retried.

**Consequences (testable):**
- Retry is offered on failed Meetings only.
- Retry uses the retained audio (FR-19) and the currently selected Transcription Model.

#### FR-40: Delete a Meeting
The user can delete a Meeting, including its audio.

**Consequences (testable):**
- Deletion states what will be removed before removing it.
- Deletion removes retained audio, so deletion is a real privacy action rather than a list-hiding one.
- Whether the Note file is also deleted is explicit in the confirmation, never a surprise.
- **Amended (increment 2):** deletion is reachable without discovering a context menu — a visible control in the Library, and the standard Delete key on a selected Meeting. A destructive action still requires the confirmation above; discoverability is not permission.
- **Amended (increment 2):** more than one Meeting can be selected and deleted in one confirmed action, which is what "manage" means once a handful of test recordings exist.
- **Amended (increment 7):** deletion is **recoverable**. The Meeting directory, and the Note when the user chose to delete it, go to the Trash rather than being unlinked. A confirmation is not a substitute for a route back, and this is the only gesture in the product that destroys audio — the one input that cannot be regenerated.
- **Amended (increment 7):** the confirmation names the file it will actually delete. The Note Link is resolved (FR-78) before the dialog is composed; if no file can be found, the dialog says so rather than naming the file the record remembers. Naming a file that will not be touched is a false statement in a destructive dialog, and the same code path could delete a *different* file if a name were reused.

#### FR-54: Refresh the Library from disk
The Library can be resynchronised with what is actually on disk.

**Consequences (testable):**
- An explicit refresh re-reads the Meeting store and the Notes Folder and updates every row's state, including FR-53's Note-present check.
- A Meeting record removed outside the app disappears from the list after a refresh, rather than persisting until relaunch.
- A Note deleted outside the app is reflected after a refresh.
- Refresh is idempotent and destroys nothing: it changes what is displayed, never what is stored.
- A Meeting record whose payload cannot be read is surfaced as unreadable, not omitted from the list. Silently skipping an unreadable record is how the list can be wrong without appearing wrong.
- **Amended (increment 7):** refresh also reconciles Note Links (FR-78) and recounts Unclaimed Notes (FR-82). Refresh is the user's answer to "the app and my folder disagree", so it has to look in both directions — records against files, and files against records. It reads the folder; it still never parses a Note's content.

**Notes:**
- The last consequence is the lesson of a real defect: an unreadable record was skipped by a permissive load, so five Meetings vanished from the list while intact on disk. A list that quietly drops what it cannot parse is worse than one that shows a broken row.

---

### 4.9 Setup, Settings and First Run

**Description:** One window with a grouped sidebar, opened rarely. It handles first-run setup — permissions, Notes Folder, Transcription Model — and then the handful of preferences worth changing, plus the Library (§4.8). Realizes UJ-4.

The setup experience follows a pattern the user explicitly asked for, modelled on FluidVoice: a **Setup Checklist** of rows that each carry a state icon, a title, a one-line explanation of *why*, and a right-aligned control that is either a dim "Done" pill or a live action button. Satisfied rows recede visually so attention falls on what is still outstanding. Below it sits a **Test Playground** that proves the whole pipeline end-to-end before the user trusts it with a real meeting.

The Test Playground is not a convenience. macOS provides no API to query system-audio-capture permission (§12), so "is this app actually able to record a meeting?" is otherwise unanswerable. A five-second record-and-transcribe makes it empirical.

**Functional Requirements:**

#### FR-41: First-run setup
On first launch the app guides the user to a working state. Realizes UJ-4.

**Consequences (testable):**
- Microphone permission is requested with a clear explanation of why.
- The user is told that system-audio capture requires a separate macOS permission which will be prompted on first recording, and that declining it degrades to Mic-only (FR-7) rather than breaking the app.
- The Notes Folder and Transcription Model are set, each with a working default so the flow can be completed by accepting defaults.
- The app is usable immediately after setup with no restart.

#### FR-42: Permission state is visible and actionable
Settings shows the state of each permission the app needs.

**Consequences (testable):**
- Microphone permission state is shown accurately.
- System-audio capture state is shown as *inferred* — from whether Capture has succeeded — because macOS exposes no API to query it. The UI must not claim certainty it cannot have.
- Where a permission is missing, Settings links to the relevant System Settings pane and explains what to do, including the reset command needed after a rebuild.

#### FR-43: Configure detection
The user can turn Detection off entirely or per Watched App. Satisfies FR-15 from the Settings surface.

**Consequences (testable):**
- Each Watched App can be toggled independently.
- Disabling Detection stops all polling, verifiable by the absence of periodic audio-process enumeration.

#### FR-44: Configure audio retention
The user controls whether Session audio is kept after a Note is written. `[ASSUMPTION: retention as a user-facing choice was not requested; inferred from retry (FR-19) needing audio and from privacy hygiene requiring an off switch.]`

**Consequences (testable):**
- The options are explicit: keep audio, or delete it once the Note is written.
- The default keeps audio, because FR-19 retry and FR-39 depend on it; the trade-off is stated in the UI.
- Deleting audio disables retry for those Meetings, and the UI says so.
- Disk used by retained audio is shown, with a way to clear it.

#### FR-45: Launch at login
The user can have Minutes start at login. `[ASSUMPTION: not requested; inferred from SM-4 — a menu bar tool that must be launched by hand will not survive three weeks.]`

**Consequences (testable):**
- The setting takes effect without a restart and survives reboot.
- It is off by default; the app does not install itself into login items uninvited.

#### FR-46: Setup Checklist
The Setup pane presents an ordered checklist of everything required for a working install, each row showing its own state. Realizes UJ-4.

**Consequences (testable):**
- Rows cover, at minimum: Transcription Model ready, microphone permission, system-audio capture verified, Notes Folder chosen.
- **Amended (increment 4):** Voice Enrolment (FR-62) is one of these rows — optional, and prominent by being in this list rather than buried in a settings pane. It uses the same row anatomy and the same live-derived state rule as every other row; a second onboarding style is a defect.
- Each row states in one line why the item is needed — never a bare label.
- A satisfied row shows a non-interactive "Done" indicator and is visually de-emphasised; an outstanding row shows an ordinal and a control that performs or navigates to the fix.
- Row state is derived from live system state, not from a stored "setup completed" flag, so a permission revoked later shows as outstanding again.
- The checklist distinguishes required rows from optional ones; an optional row left undone never blocks the app or shows as an error.
- The pane states plainly when every row is satisfied.

#### FR-47: Test Playground
The Setup pane provides an in-app test that exercises Capture, transcription and attribution end-to-end. Realizes UJ-4.

**Consequences (testable):**
- A single control starts a short test Capture of both Streams and displays the resulting Transcript in-app.
- The result reports, separately, whether the Mic Stream and the System Stream each produced non-silent audio — this is the only reliable way to confirm system-audio capture works (§12), and it drives the corresponding Setup Checklist row.
- The test states which Transcription Model ran and how long transcription took, giving the user real throughput on their own machine rather than a generic claim (see §13 open question 1).
- A test run produces no Meeting and writes no Note; it never appears in the Library.
- The test reports a specific failure per stage — no audio captured, model missing, transcription failed — rather than a single generic error.
- The test is available at any time from Setup, not only on first run.

#### FR-48: Re-run onboarding
The user can re-enter the first-run flow after initial setup. Realizes UJ-4.

**Consequences (testable):**
- A control in the Setup pane restarts the guided flow without resetting the user's existing preferences.
- Re-running is non-destructive: it does not delete Meetings, downloaded models, or Speaker Profiles.

**Feature-specific NFRs:**
- The window fits comfortably on a laptop display without scrolling in its default state, and is keyboard-navigable.
- The sidebar is the only navigation; the app must not accumulate a second window for settings or library.

---

### 4.10 Summarisation Intelligence

**Description:** A pane that treats summarisation the way §4.4 treats transcription — a small set of real choices, each explaining what it is for, what it costs and what it requires, with installation and readiness visible in the same place. Introduced in increment 3 on the user's instruction not to depend on Apple Intelligence while keeping it available. Realizes the same "small, clean UI for selecting models" ask that produced FR-17, applied to the second kind of model in the product.

**Functional Requirements:**

#### FR-56: Choose a Summarisation Backend from a curated list
One pane lists every way the app can summarise, in a shape a reader can compare.

**Consequences (testable):**
- Three families are represented: Apple's on-device model, a downloadable local model, and a remote model reached with a user-supplied key.
- Each entry states what it is for in plain language before it states anything technical, and carries its provider, its size or cost, and its readiness — mirroring FR-17's row anatomy rather than inventing a second visual language.
- No two entries render with the same display name. The increment-1 defect where 22 model IDs collapsed into 12 indistinguishable names must not recur.
- The list of downloadable local models is built from a live registry at run time, never from a hardcoded list, because the ecosystem's model names move faster than a release cycle.
- Selecting an entry that is not installed offers installation; it does not silently select something else.
- The pane never implies a capability the machine does not have. An entry whose prerequisite is missing is shown as blocked with the reason (FR-58), not hidden and not offered.

#### FR-57: Backend precedence is stated, not inferred
With several Backends possible, which one runs is defined and visible.

**Consequences (testable):**
- The order is: an explicit user selection first; then availability among the remaining Backends; then no summary at all (FR-55).
- The pane states which Backend will run for the *next* Meeting, not merely which is selected — those differ when a selection is unavailable.
- Two settings can no longer contradict each other silently: if a selection is impossible, the pane says so and says what will happen instead.

**Notes:**
- Written because increment 2's FR-52 created a second setting that could disagree with availability, and a third Backend would have made the ordering undocumented. The review flagged this before it shipped.

#### FR-58: Prerequisites are detected, explained and actionable
A Backend the app cannot use says why, and says what would fix it.

**Consequences (testable):**
- Every unavailable Backend gives a reason the user can act on, not a bare "unavailable".
- Apple's model distinguishes *Apple Intelligence is switched off* from *this device is ineligible*, because only one of those is fixable and the app can tell them apart at run time.
- The local model path detects a missing Metal toolchain and states the exact command that installs it. This is a verified, currently-unmet prerequisite on the target machine, not a hypothetical: `xcodebuild -showComponent MetalToolchain` reports `uninstalled`, and without it MLX cannot execute a single token.
- A missing prerequisite is reported *before* a multi-gigabyte download, not after.
- Prerequisite state is re-read when the pane appears, so fixing it outside the app is reflected without a relaunch — the same rule FR-46 already applies to permissions.

#### FR-59: A remote Backend requires a key, and consent per Meeting
The remote option exists, is off by default, and never sends anything the user has not agreed to send for that Meeting.

**Consequences (testable):**
- No remote request is ever made until the user has both entered a key and consented for that Meeting. Configuring a key is not consent.
- The consent moment names what will be sent — the Transcript — and who will receive it, and shows the participants whose speech it contains.
- Audio is never transmitted under any configuration. Neither are Speaker Profiles. Only Transcript text.
- The key is stored in the system Keychain, never in preferences, never in the Notes Folder, never in a log, and is not readable back into the UI after saving.
- Removing the key stops all remote capability immediately and leaves previously generated summaries and their provenance untouched.
- An empty or near-empty Transcript is never sent. A silent recording must not become a paid request.
- The pane states, where the key is entered, that this is the only feature in the app that transmits anything, and that meeting participants have not consented to it.

**Notes:**
- `[NOTE FOR PM]` The reviewer's finding stands and is recorded rather than resolved: a Transcript contains colleagues' speech, and in an EU employment context an individual cannot establish a lawful basis for sending it to a third-party processor on their colleagues' behalf. The product's contribution is to make the act explicit, per-Meeting, and off by default. It cannot make it lawful. If a company-approved vendor with a data processing agreement exists, that is the endpoint to configure.

#### FR-60: Cost and duration are shown before they are incurred
Neither money nor a long wait arrives unannounced.

**Consequences (testable):**
- Before a remote request, an estimated token count and cost is shown, derived from the actual Transcript.
- A running total of remote spend is visible in the pane, so cost is observable rather than discovered on a statement.
- For a local model, the pane shows a measured duration for this Mac once measured, and says plainly when it has not been measured yet rather than showing an estimate dressed as a measurement — the distinction FR-17's speed card already draws.
- A local model download shows real progress. The registry's download reporting is continuous, so a coarse indeterminate spinner is not acceptable here.

#### FR-61: Summarisation never blocks the Note
A Backend that fails, times out, or is offline costs the user nothing that was already earned.

**Consequences (testable):**
- Any Backend failure — unreachable network, rejected key, exhausted quota, timeout, model load failure, out-of-memory — still writes the Note with the Transcript, title and tags, and records the failure on the Meeting.
- The Note is never blocked on a network call.
- A failed summarisation is retryable without re-transcribing, reusing the stored Transcript (the FR-39 pattern).
- Transcription and summarisation models are never resident simultaneously; the pipeline unloads one before loading the other (NFR-4).
- Provenance stays truthful across every path: each Note names the Backend that actually produced its Metadata, including the specific local model or remote model identifier, and a Note written by one Backend is never relabelled by a later change of setting (FR-30, §9.3).

---

### 4.11 Running on Someone Else's Mac

**Description:** Everything above was specified, built and operated on one machine. This section covers what a second machine requires: that failures explain themselves, that claims about the environment are about *that* environment, that installing is one command, that an update does not cost the user their permissions, and that the app's whole footprint is one folder the user can see, move and remove. Added in increment 5, after the repository was published and the code was audited for the first time with a different Mac in mind. Every requirement here answers a defect verified at a file and line, not a hypothetical.

**Functional Requirements:**

#### FR-66: A failure states its reason and its remedy
When Minutes cannot do what the user asked, it says why, in the interface, with the remedy.

**Consequences (testable):**
- Every failure that prevents a recording from starting is surfaced where the user acted — the menu bar as well as the window. A reason visible only in a window the user has not opened is still silence.
- The text is the reason and the remedy together. "Recording failed" without "enable Minutes in System Settings > Privacy & Security > Microphone" leaves the user exactly where they were.
- A reason is cleared by a subsequent success. A stale error asserting a present failure is its own defect.
- Where the remedy is a System Settings pane, the app offers to open it rather than describing where it is.
- No statement about the machine is made unless it was determined on *that* machine. An unavailability is explained by the reason that actually applied, never by the most likely one.

**Notes:**
- The strings already exist and are already good. `AppState.lastError` is written on four failure paths in `SessionCoordinator` and read by exactly one file, `App/SelfTest.swift` — a command-line path. The app has never been able to explain a failure through its interface, and on one machine, with permissions long since granted, that never showed.

#### FR-67: Evidence that audio was captured is signal, never duration
Any claim that a stream produced audio rests on there having been audio in it.

**Consequences (testable):**
- Elapsed time is never sufficient. Frames are written whether or not anything is playing, so duration establishes only that the capture ran.
- A silent capture of any length reports that it produced no audio, and a test asserts exactly that.
- "The file exists" is not evidence either. The Test Playground's per-stream verdicts test the samples.
- Every sentence in the product that asserts capture succeeded is true after this requirement, or is reworded.

**Notes:**
- This is load-bearing for FR-42 rather than incidental to it. macOS exposes no API to query system-audio permission, so a measurement is the only evidence obtainable — and a measurement that cannot fail is indistinguishable from success. Verified: `SystemTapCapture.stop()` accepts `duration > 0.25` as proof, three lines below a comment calling the value "the only evidence we can have that system-audio capture actually worked".

- **Amended in increment 8: signal is necessary and is not sufficient.** Seven recordings passed every clause above and were unusable, because a stream running at three times speed is full of signal. This requirement answers *did it capture anything*; FR-84 and FR-85 answer *is what it captured at the rate it claims*. Both must hold. The clause "elapsed time is never sufficient" stands unchanged and is not in tension with the new check: there, duration was being offered as evidence of capture; in FR-84 it is the denominator of a rate, which is the only way that question can be answered at all.

#### FR-68: Minutes never removes a directory it did not create
The app deletes only what it wrote.

**Consequences (testable):**
- Migration of previously downloaded models removes the subtree Minutes created and leaves its parent and the parent's other contents intact.
- A migration that cannot complete deletes nothing at all.
- A test places unrelated content beside adoptable content and asserts the unrelated content survives.

**Notes:**
- Verified: every launch can remove the whole of `~/Documents/huggingface` when only its `models/argmaxinc/whisperkit-coreml` subtree is empty. Harmless on a machine that keeps no other models there; silent data loss on one that does.

#### FR-69: Where notes are written matches what the app claims about them
The default note location does not contradict the privacy statement.

**Consequences (testable):**
- Either the default sits outside a cloud-synced tree, or the app states plainly that notes in this location are synced off the Mac.
- No surface asserts that nothing leaves this Mac while notes are being synchronised from it.
- The user may still choose a synced folder deliberately; this removes a false claim, not a capability.
- A folder is reported ready only if it was created. Reporting success from a failed creation is a separate defect in the same code path.

**Notes:**
- Verified: the default is `~/Documents/Minutes`, and iCloud's Desktop & Documents sync — common on managed fleets — uploads everything in it, while the Summaries pane states "Nothing about your meetings leaves this Mac". The app is not lying; it does not know. §9.1 makes this a requirement rather than a nicety.

#### FR-70: A transcription model is a declared prerequisite
The user learns a model is needed before a meeting depends on one.

**Consequences (testable):**
- The requirement is stated and the download offered before the first meeting that would need it, not discovered inside the pipeline that already has the audio.
- Progress is visible while a model downloads, wherever the download began.
- A meeting recorded without a model keeps its audio and can be transcribed later. A prerequisite is never enforced by discarding something already captured.
- Offline and without a model, the user is told before recording rather than after.

#### FR-71: The app knows its own version, and the version identifies the build
A reported version distinguishes one release from another.

**Consequences (testable):**
- The version derives from the release tag and is applied when the bundle is assembled. No version literal is maintained by hand.
- `--doctor` prints it, and the interface shows it somewhere a user can find and quote.
- A development build is identifiable as one rather than claiming to be a release.

**Notes:**
- Verified: `Info.plist` carries `1.0`/`1` and nothing in the source reads either key. There is no About surface. Without this, every bug report from every user of every future release says the same thing.

#### FR-72: Installing on another Mac is a single command
A person who has never seen the project installs it with one command and opens it.

**Consequences (testable):**
- One command, with no separate tap, clone, build or unarchive step.
- The installed app opens. Gatekeeper is satisfied, never bypassed, disabled, or worked around.
- Hardware and OS requirements are declared by the installer and enforced before anything is written. An unsupported Mac is refused with a sentence naming the requirement, not given a degraded install.
- Uninstalling is available through the same mechanism.

**Notes:**
- The mechanism is a Homebrew cask in a first-party tap. Official `homebrew/cask` requires notability the project does not have, and — since 1 September 2026 — that the cask pass Gatekeeper checks; the second is a requirement the project intends to meet regardless, the first is not worth pursuing.
- `[ASSUMPTION: the target is Apple Silicon. Every measurement in the project was taken there. Whether the CoreML dependencies build for x86_64 at all is untested, so universal support is not claimed.]`

#### FR-73: An update does not cost the user their permissions
Installing a new version preserves consent already granted.

**Consequences (testable):**
- Microphone and system-audio consent survive an update. The user does not re-grant permissions or re-run the audio test because a new version arrived.
- The bundle identifier is stable across releases, permanently.
- An update closes a running instance cleanly rather than replacing it underneath itself.

**Notes:**
- This is the requirement that justifies the signing cost, and it is a mechanism rather than a preference. Apple's TN3127 states that macOS records an app's designated requirement when consent is granted and re-checks it on each access, and that ad-hoc signed code's requirement "is tied to that specific version of the code". A Developer ID requirement checks the Apple anchor, the identifier and the Team ID, and not a hash — so consent survives updates, and survives certificate renewal.
- Amends §12, which recorded the absence of a signing certificate as an accepted condition. It is no longer acceptable once someone other than the author installs the app.

#### FR-74: Settings live in the single user-data directory
The app's configuration is part of the footprint the user can see.

**Consequences (testable):**
- Settings are a readable document in the same directory as meetings and remembered voices.
- Deleting that directory returns Minutes to a first-run state, with nothing about the user surviving elsewhere.
- Migration from the previous store happens once, is idempotent, and afterwards the previous store is not read.
- The notes-folder permission survives migration. If it cannot, the user is asked to choose the folder again rather than silently losing access to it.
- A missing or unreadable settings document yields defaults with a stated reason, never a crash and never a silent reset.

**Notes:**
- Requested directly: all user data local, in one place the app loads. Meetings, voices and models already satisfy that; settings are the exception, which is why "delete that folder and Minutes knows nothing about you" is not currently true.

#### FR-75: The user can see, and deliberately move, their whole footprint
Minutes can show everything it stores, and the user can take it to another Mac.

**Consequences (testable):**
- Every location is listed with its size and what it holds, and each can be revealed in Finder. The list derives from the same constants the app writes through, so it cannot drift.
- The listing itself contains no meeting content, speaker name or embedding.
- An export contains meetings, notes and settings. **It contains no Voice Fingerprint unless the user separately and explicitly chose to include one**, off by default, with a plain statement of why that data is treated differently.
- Import states what it will overwrite before overwriting it, and either migrates or refuses across versions — never partially applies.
- Neither direction uses the network.

**Notes:**
- §9.1 governs. An export is the first capability in the product's life that lets a Voice Fingerprint leave the machine that recorded it, which is why the opt-in is separate from the export itself rather than a line item within it.
- `[NOTE FOR PM]` Whether a fingerprint may be exported at all is a product decision, not an implementation default. It is deliberately left open here.

#### FR-76: Uninstalling removes everything, and the documentation says what everything is
A user who removes Minutes is left with nothing of it.

**Consequences (testable):**
- The login-item launch agent is removed. It lives outside the app bundle, survives deleting it, and otherwise keeps trying to start an application that no longer exists.
- The documented list, the uninstall mechanism's own list, and the footprint listing of FR-75 are derived from one source and agree.
- The documentation names the permission-reset commands, since macOS retains consent records after an app is gone.
- Removing the application without removing the meetings remains possible and remains the default. An uninstall is not destructive of the user's data unless they asked for that.

---

### 4.12 The Note Is the User's File

**Description:** Everything in §4.7 assumes Minutes owns the Note. It does not.
The Note lives in a folder the user chose, next to their other documents, and the
user will rename it, move it and edit it — because that is what one does with a
Markdown file in one's own folder. This section makes the app survive that.
Realizes UJ-3, and closes the gap §4.7 left open.

**Why it exists:** observation, not inference. The user renamed a Note in Finder
to a name that described the meeting, and the app reported the Note as missing,
offered one remedy that would have orphaned the renamed file permanently, showed
the renamed file nowhere, and then deleted the Meeting on a confirmation that
named a file it did not touch. The recording is not recoverable. Measured account:
`planning-artifacts/spikes/investigation-note-linkage-2026-09-03.md`.

**Functional Requirements:**

#### FR-77: A Note says which Meeting it belongs to
A Note carries the Meeting's identity in its own frontmatter, so the file is
self-describing and the link does not depend on the filename.

**Consequences (testable):**
- Frontmatter carries the Meeting's ID. A Note moved to another folder, renamed, or read a year later still says what it is.
- Notes written before this requirement existed are still identifiable: `started_at` is already in every one of them, and it is sufficient. Measured on the fifteen Notes on the author's machine — all fifteen carry it, to the second, with no two Meetings within a second of each other.
- No existing Note is rewritten to add the stamp. Files the user already has are left exactly as they are; the stamp appears when the Note is next written for its own reasons.
- The identity is a value the app wrote. A Markdown file Minutes did not write carries no such stamp and is never claimed as a Note.

#### FR-78: A renamed or moved Note is found again, not declared missing
When the recorded file is not where the record says, Minutes looks for it before
saying anything.

**Consequences (testable):**
- Reconciliation reads only frontmatter identity — Meeting ID, falling back to `started_at`. It never reads a Note's body, and nothing from a Note's content becomes app state.
- A single unambiguous match relinks silently and the Note is not reported as missing. The user renamed a file; being asked to confirm their own action is noise, and being told the file is gone is false.
- Two files claiming one Meeting is reported, never guessed. The app says which files, and the user picks.
- Reconciliation runs only when an existence check has failed. A library with no broken link reads nothing.
- A positive identification is written to the record. Absence never is: a Note that cannot be found leaves the record untouched, because a transient filesystem condition must not become a permanent claim.
- Reconciliation never creates, moves, renames or deletes a file. It only changes which existing file the record points at.

#### FR-79: The user can point a Meeting at a Note file
An explicit action to attach a Meeting to a file, for when the app's own search
cannot answer it.

**Consequences (testable):**
- Available wherever a Note Link is unresolved, and also on a Meeting whose Note is present — a user may want to point at a different file.
- The user chooses a Markdown file. Choosing it makes it this Meeting's Note; the file's contents are not modified by the act of choosing.
- If the chosen file's frontmatter identifies a *different* Meeting, the app says which one and asks for confirmation. It does not refuse — the user may be repairing something the app cannot see — and it does not stay silent, because linking one file to two Meetings means the next rewrite destroys one of them.
- Choosing a file the app did not write is allowed and the file is not stamped, moved or reformatted on linking. The next rewrite of that Meeting would replace its contents, so the app says so before the link is made.

#### FR-80: Once the user names the file, their name wins
The app stops correcting a filename the user chose.

**Consequences (testable):**
- The record remembers the name Minutes last wrote. When the name on disk differs, the file is user-named.
- A user-named file is never renamed by the app, including on a title change (FR-35 as amended).
- The user-chosen name is shown where the app shows the Note, so the app displays the user's name for the file rather than one only the app knows.
- Adopting the file's name as the Meeting's *title* is **not** part of this. It would mean reading content back into state, and a filename carries a date prefix and a slug rather than a title. The user renames a Meeting in the app, which already works. Recorded as a deferral with its reason, not an oversight.

#### FR-81: A Note changed outside Minutes is not silently overwritten
The app can tell that a Note has been edited elsewhere, and asks rather than
discarding the edit.

**Consequences (testable):**
- The app records a fingerprint of what it last wrote. Before overwriting, it compares; equal means the app's own output and it proceeds without a word.
- Different means the file has been changed outside Minutes. The app does not write. It says what it found and offers exactly two outcomes: keep the file as it is, or replace it with a freshly rendered Note.
- The choice is per Note and is not remembered as a preference. A user who kept one hand-edited Note has not decided anything about the next one.
- Merging is out of scope and stays out. The Note is a projection; there is no mechanism that could reconcile a paragraph a human wrote with a transcript the app renders, and pretending otherwise would produce a file neither party recognises.
- This closes a consequence the architecture has always carried and never surfaced: "a user editing a Note by hand will have those edits overwritten, and this must be stated in the UI." It was stated nowhere.

#### FR-82: A Note whose Meeting is gone is shown, not hidden
Files Minutes wrote and no longer links to are visible in the app.

**Consequences (testable):**
- The Library reports how many files in the Notes Folder Minutes wrote and no Meeting claims, and lists them on request with the date and title from their own frontmatter.
- Each can be revealed in Finder, opened, or dismissed from the list. Dismissing changes the listing only; it never touches the file.
- They are not re-imported as Meetings. A Note cannot be parsed back into a Meeting, and a half-Meeting with a transcript and no audio would be a second kind of record for the rest of the product to special-case.
- Files Minutes did not write are not listed at all. The user's folder is theirs; an app that enumerates a user's unrelated documents has overstepped.

#### FR-83: Managing Notes never costs the user a Note
The safety property that binds this section together.

**Consequences (testable):**
- No action in this section deletes or overwrites a file the user has changed without the user having said so in a dialog that names the file.
- A rewrite whose link is broken finds the existing file first, and creates a new one only when no file claims the Meeting.
- Every destructive path in the Library goes to the Trash, so every mistake in this section is recoverable by dragging one item back.

---

### 4.13 A Recording the App Cannot Vouch For

**Description:** Every requirement before this one assumes that if audio was
captured, the audio is usable. For three days that was false and nothing said so.
This section makes a recording's *fidelity* something the app checks, states, and
refuses to build on.

**Why it exists:** measured, not hypothesised. **Seven of sixteen recordings** on
the author's machine held a system stream declaring 16 kHz whose real rate was
8 kHz or 5.3 kHz — two or three times too fast. Speech at that speed is still
speech-like, so transcription did not fail; it produced fluent, confidently
formatted, entirely invented dialogue for the remote participant, and the title,
tags and summary were then derived from the fabrication. Every affected recording
had a Bluetooth headset as the *input* device; every microphone stream was
correct. The raw samples were intact, so all seven were recovered — but nothing in
the product had noticed, and the app's own capture-evidence check (FR-67) passed
each one, because a stream at three times speed is full of signal.

**Functional Requirements:**

#### FR-84: The capture rate is checked against the clock, while recording
A declared sample rate is a claim the app verifies rather than trusts.

**Consequences (testable):**
- While a Session runs, each stream compares the input frames it has consumed against the time it has been running, and against the rate its format declares.
- A disagreement beyond a stated tolerance is **corrected where the observed rate is one a real device uses**, so the recording comes out right. Nothing is written to the file until the rate has settled, so a corrected recording has no compressed opening.
- Where the observed rate is *not* one a real device uses, the app does not guess: the declared rate stands, the recording is marked untrustworthy (FR-85) and nothing is derived from it (FR-86). Guessing there would resample a different defect into this one.
- Either way the record carries **both** rates and the correction, if any. A record that hid its own correction would make this defect invisible again one layer down.
- The user is told **during the Session** when a disagreement cannot be corrected. *(Amended 2026-09-03: the first implementation of this requirement raised the event and nothing subscribed to it, so it only surfaced at stop. A requirement whose code does not implement it is worse than an unwritten one, because the document says it is done.)*
- The check runs during the Session, not only at the end: a two-hour meeting is too expensive to discover afterwards.
- There is a settling period before the first comparison, because the first buffers arrive irregularly. Its length is stated where it is defined, and it is not a setting.
- A correct recording never triggers it. Verified against the nine recordings on this machine that were correct, whose ratios sit at 1.00–1.03.

#### FR-85: A stream that disagrees with the clock is marked untrustworthy
The record says which stream cannot be relied on, and why.

**Consequences (testable):**
- The Meeting record carries, per stream, whether it passed and the two rates involved. It is stored, not derived on read — a fact about a recording that happened, not a display state.
- Trust is per stream. In every observed case the microphone was correct and the system stream was not, so a single per-Meeting flag would be wrong in both directions.
- The check is derived from values the writer already holds and is never gated on a preference.
- This is the second half of FR-67's capture evidence: *did it capture anything* and *is what it captured at the rate it claims* are different questions, and a recording must pass both.

#### FR-86: No title, tag or summary comes from a transcript the app cannot vouch for
The app does not name a meeting after invented text.

**Consequences (testable):**
- A Meeting whose stream failed FR-85 gets no Metadata derived from that stream's text.
- The transcript that exists is still written. The samples are the user's, and discarding them would be worse than labelling them.
- Where one stream passed and the other did not, Metadata may still come from the one that passed, and the Note says that is what happened.
- This is the requirement that addresses *why the defect looked fine*: a broken recording arrived with a confident name and a plausible shape, and the provenance field said `heuristic`, which was true and told the reader nothing.

#### FR-87: The app says which recordings it cannot vouch for
An untrustworthy recording is visible without opening it.

**Consequences (testable):**
- The Library marks such a Meeting, and its detail pane states which stream, both rates, and what that means for the transcript.
- The Note carries the same statement, because in six months the Note is all there is.
- The wording names the likely cause where the app knows it — a Bluetooth input device was present in all seven observed cases — without asserting it as certain.
- Nothing is hidden or auto-deleted. The user decides what to do with a recording the app has flagged.

#### FR-88: An existing recording can be re-checked and repaired
A recording already on disk can be assessed and, where the samples are intact, recovered.

**Consequences (testable):**
- The app can evaluate recordings made before this check existed and report which fail it.
- Where a stream's true rate is recoverable from its own sample count and the Session's duration, the app can repair the declared rate and re-run the pipeline from the retained audio.
- Repair changes only what is wrong. The samples are not resampled, re-encoded or discarded, and the original declared rate is recorded so the change is reversible.
- Nothing is repaired without the user asking. `[ASSUMPTION: the seven affected recordings on the author's machine were repaired by hand on 2026-09-03, before this requirement existed. The requirement is what makes that repeatable for a colleague.]`

### 4.14 Transcription the App Can Measure

**Description:** Everything before this section treats transcription quality as
whatever the chosen model happens to produce. This section makes it something
the app *measures*, and fixes the largest defect that measurement found.

**Why it exists:** measured, not hypothesised, and the measurement came first.
A harness (FR-93) was built before any change was made, against the AMI Meeting
Corpus — three real four-person meetings, 67 minutes, ~7,900 reference words,
in two microphone conditions that match the two Streams Minutes records. It
immediately found two things.

The first was in the user's own library, not the corpus. **Of twelve recordings
holding both Streams, three had the microphone recording the far end** through
the speakers (cross-correlation 0.771, 0.574, 0.349 against ≤0.025 for the other
nine). On the worst, **57.6% of freshly transcribed Mic Stream words duplicated
a System Stream Utterance**, the Diarizer reported **six people in the room**,
and the user was **never identified at all**. Muting the echo-dominated frames
and re-transcribing removed **91% of the duplication**.

The second was that the app's own accuracy claims had nothing behind them. The
model list showed a five-point accuracy rating for fourteen models; not one had
ever been measured. When they were, the ranking **swung by up to 8 points
depending on which meeting was used**, and the model most likely to be adopted
on reputation (Canary-1B-v2) came 8.5 points *behind* the current default at 22×
the cost. Reputation and estimates both failed; only the harness didn't.

**What this section deliberately does not do:** cancel the echo (measured
impossible — see the addendum), change the default model (the per-session swing
is larger than the difference between models), or normalise far-field audio
(a real 2-point gain with no reliable gate).

#### FR-89: Detect that the microphone recorded the System Stream
Minutes determines, per Session, whether and where the Mic Stream contains a delayed copy of the System Stream.

**Consequences (testable):**
- A verdict is produced for every Session holding both Streams, and recorded on the Meeting.
- Detection is by correlation between the Mic Stream and the delay-aligned System Stream. The delay is estimated, not assumed, and a delay estimate that is not physically plausible is reported as a failure to detect rather than used.
- A recording made on headphones is not flagged. Measured: nine of twelve real recordings sit at or below 0.025 cross-correlation and must all come back clean.
- The verdict distinguishes *how much* was affected, not merely whether: 47% of mic-active frames on the worst recording against 6% on the mildest.
- Detection never inspects transcript text. Text similarity was used to *validate* the signal test (88–89% agreement) and is not the mechanism; a detector that needed a transcript could not run before transcription.

#### FR-90: Exclude the Echo before transcription and before Diarization
Mic Stream audio identified as Echo does not reach the Transcription Model or the Diarizer.

**Consequences (testable):**
- Exclusion happens upstream of both stages, not as a post-hoc pass over Utterances.
- After exclusion, no Mic Stream Utterance substantially repeats a time-overlapping System Stream Utterance (FR-23 as amended).
- The In-Room Speaker count is computed from the retained audio only, so the far end cannot become an attendee (FR-21 as amended).
- Excluded audio is muted, not deleted: the recording on disk is unchanged and the exclusion is recomputable. The user's audio is never edited to fix the app's problem.
- Measured target, from the validation run: duplication on a severely affected recording falls from 57.6% to 11.6% of mic words.

#### FR-91: Never exclude what cannot be Echo
Mic Stream audio recorded while the System Stream is silent is always retained, and speech concurrent with the far end but uncorrelated with it is retained as Double-talk.

**Consequences (testable):**
- With no System Stream, or a silent one, nothing is ever excluded — 40% of mic activity on the worst recording falls in this category and is not at risk under any threshold.
- Concurrent-but-uncorrelated speech is retained. The user talking over the far end is the case this requirement exists to protect.
- The cost of exclusion is measured and stated rather than assumed: the current test loses **10.7% of unique Mic Stream words** on the worst recording. That figure is a release criterion, not a footnote — a change that worsens it is a regression even if it removes more Echo.

#### FR-92: The Meeting says the recording was affected, and by how much
A Meeting whose Mic Stream contained Echo records that fact, and the user can see it.

**Consequences (testable):**
- The Meeting record carries the verdict, the estimated delay, and the proportion of Mic Stream audio excluded.
- The user is told in plain language what it means for the Note — that the far end was also picked up by the microphone and has been counted once, not twice.
- A recording processed before this existed is not silently presented as clean; an unknown verdict reads as unknown.
- The advice is actionable: headphones prevent it, which is why the nine clean recordings are clean.

#### FR-93: Transcription accuracy is measurable, repeatably, from a terminal
Minutes ships a way to measure transcription accuracy against a reference corpus, and its results are what accuracy claims cite.

**Consequences (testable):**
- One command transcribes a given audio file through the shipping code path and emits machine-readable Utterances, so the harness measures the product rather than a copy of it.
- Word error rate is reported alongside a **content-word** error rate and **proper-noun recall**. Raw WER alone is the wrong target: the most-deleted words at the baseline were `yeah`, `ok` and `right` — a quarter of all errors, and words FR-31 already strips deliberately.
- A repetition measure is reported, as a model-independent signature of the fabrication failure of §4.13.
- Results are aggregated by pooling errors over pooled reference words across sessions, never by averaging per-session percentages.
- Neither corpus audio nor results are written into the repository (§9.1).
- The harness must be able to contradict the project: it has already retracted one conclusion drawn from a single session and rejected a model that was going to be adopted on reputation.

#### FR-94: Verify the input rate against the audio clock, not the wall clock
The rate check of FR-84 uses the timestamps the audio device supplies rather than elapsed wall-clock time.

**Consequences (testable):**
- The frame count is compared against the device's own sample-time counter, taken at the same instant, so the comparison needs no tolerance for scheduling jitter.
- A discontinuity in the device's sample time — samples the app never received — is detected as such, which the current wall-clock check cannot see at all.
- The 12% tolerance and 3-second settling window of FR-84 shrink or disappear, and the value that replaces them is derived rather than tuned.
- The check still refuses to act on a rate that is not one a real device uses (FR-85 unchanged).

#### FR-95: An Utterance carries the engine's confidence
Where the Transcription Model reports a confidence, it is carried through to the Meeting record.

**Consequences (testable):**
- Confidence survives the port boundary rather than being discarded at the adapter.
- A Meeting whose Transcript is largely low-confidence is distinguishable from one that is not, without re-running transcription.
- Metadata derivation can consult it (§4.13's gate becomes evidence-based rather than binary).
- A model that reports no confidence yields absent, not zero. Absent means unknown.

#### FR-96: An interval the engine could not transcribe is a recorded gap
Audio the Transcription Model returned nothing usable for is recorded as a gap rather than silently omitted.

**Consequences (testable):**
- The Transcript can state that a span of audio produced no usable text, with its start and end.
- A gap is distinguishable from silence: one is speech the app failed on, the other is nothing to transcribe.
- A Note derived from a Transcript with substantial gaps says so, so a summary is not read as complete when it is not.

## 5. Non-Goals (Explicit)

These exist to stop the "let me also add the nearby thing" failure mode at epic, story and code level.

- **Not a cloud service.** No account, no server, no sync, no telemetry, no crash reporting. There is no back end to add later without breaking the product's only real claim.
- **Not a team product.** No sharing, no multi-user, no shared archive. One person, one machine.
- **Not live transcription in v1.** Transcription is batch, after the Session ends. Streaming is a v2 direction, and designing v1 around it would compromise the simpler, more reliable batch path.
- **Not automatic recording.** Detection offers; the user decides. Minutes never records without an explicit click, even for a Watched App it has seen a hundred times. This is a deliberate refusal of a convenience.
- **Not voice identification of real people from cold.** Speaker Profiles (FR-25) learn from a name the user typed, and Voice Enrolment (FR-62) learns one voice from the person who owns it. The app never attempts to identify a person it was not told about, and enrolling one's own voice is the narrowest possible version of being told.
- **Not a tunable voice-matching engine.** No exposed threshold, no voice-activity parameters, no speaker count to set. The product exposes outcomes and corrections; the mechanism stays inside (FR-65).
- **Not an automatic editor of who belongs in a meeting.** The app will not decide that an in-room voice was a bystander and drop it from the Note. A conference room full of participants is the normal case, and the user's per-Meeting Exclude control is the whole answer.
- **Not a meeting platform integration.** No calendar reading, no attendee lists, no CRM export, no Jira tickets from action items.
- **Not a general audio recorder or transcription utility.** No importing existing audio files, no dictation mode.
- **Not distributed software.** No App Store, no notarization, no auto-update, no installer. It is built and run on one machine.
- **Not multi-platform.** macOS on Apple Silicon only. No iOS companion, no Intel support, no Windows.
- **Not a summariser of anything but meetings.** The Metadata prompt is tuned for conversation; it is not a general document tool.

## 6. MVP Scope

### 6.1 In Scope

- Menu bar app, three states, start/stop, status, Library and Settings access (§4.1)
- Dual-stream Capture with Mic-only degradation, device-change survival, incremental writes (§4.2)
- Detection of Slack and Teams audio-input activity, debounced Prompt, auto-stop, per-app suppression (§4.3)
- On-device Whisper transcription, model selection, download with progress, failure retry (§4.4)
- Structural Local Speaker attribution, on-device Diarization of both Streams, merged Transcript, renaming, Speaker Profiles, and Voice Enrolment of the user's own voice (§4.5)
- On-device Metadata via LLM Backend with Heuristic Backend fallback; decisions and action items; provenance recorded (§4.6)
- One Markdown Note per Meeting with YAML frontmatter, user-chosen Notes Folder, in-place rewrite on edit (§4.7)
- Library: list, read, edit, retry, delete (§4.8), and repair the link to a Note the user renamed, moved or edited (§4.12)
- Settings and first-run: permissions, folder, model, detection, retention, launch at login (§4.9)

### 6.2 Out of Scope for MVP

- **Live/streaming transcription** — deferred to v2. Batch is simpler and more reliable, and the value is 95% present without it.
- ~~**Voiceprint enrolment** ("record 10 seconds of Mikkel")~~ — **reversed in increment 4, for the user's own voice only.** The original reasoning was that FR-25 learns passively from renames. That reasoning holds for other people and **fails for the user**: passive learning needs a correct label to start from, and several voices on one microphone provide none — there is nothing to rename that is known to be you. Enrolling *everyone* remains out of scope and remains correctly deferred; enrolling *one person, the user*, is a different requirement that was deferred with it by accident. FR-62 through FR-65 bring that one case into scope. Recording a sample of a colleague is still v2, and nothing in FR-62 builds toward it.
- **Zoom, Google Meet, Discord, browser calls as named Watched Apps** — generic input-device detection may happen to cover some; they are not targets and not tested. `[NOTE FOR PM]` Chrome is installed on the target machine, so browser-based calls are plausibly common; if Detection proves solid for Slack and Teams, adding Chrome is cheap and worth revisiting.
- **Cross-meeting search and question answering** — v3 direction; needs a corpus first.
- **Export formats other than Markdown** — Markdown is the point.
- **Localisation** — English UI. Transcription language follows whatever the model supports.
- **Notarization, signing with a Developer ID, distribution** — see §12; no certificate exists.
- ~~**Recovery UI for crash-orphaned Sessions**~~ — **brought into scope in increment 2.** The original reasoning (FR-9 keeps the audio; manual recovery is acceptable) understated the symptom: an interrupted Session showed a progress spinner forever, because the Library inferred "in progress" from the record's stage rather than from whether work was running. It read as a hang, not as something awaiting a manual step. Resume-on-launch, an explicit *Interrupted* state and a *Finish transcription* action are now built. FR-39's retry surface generalises to cover it, so no new FR was needed — but the scope line was wrong and is corrected here rather than left to contradict the code.

### 6.3 Build Order (walking skeleton first)

*Added in review. 48 FRs is defensible per-requirement but sits badly against the user's own framing — "small, and focused" — and against SM-C2. Without an explicit order, downstream epics treat all 48 as equal and nothing works end-to-end until everything does. Tiers below are a **build sequence, not a scope cut**: everything in §6.1 remains in scope.*

**Tier 0 — Walking skeleton.** The thinnest path that proves the whole chain: click record, talk, get a Markdown file with speakers. Nothing here is optional, and nothing outside it should start until this runs.
`FR-1, FR-2, FR-3, FR-6, FR-10, FR-16, FR-21, FR-23, FR-26, FR-28, FR-31, FR-32, FR-33`

**Tier 1 — The product as asked.** The features the user actually named — detection with a prompt, model choice, diarization — plus the setup surface that makes them usable and the resilience that stops a lost meeting.
`FR-7, FR-9, FR-11, FR-12, FR-13, FR-14, FR-17, FR-18, FR-19, FR-22, FR-30, FR-34, FR-41, FR-42, FR-46, FR-47`

**Tier 2 — Makes it livable.** Everything that turns a working pipeline into something that survives a working day and a month of use.
`FR-4, FR-5, FR-8, FR-15, FR-20, FR-24, FR-29, FR-35, FR-36, FR-37, FR-38, FR-39, FR-40, FR-43, FR-44, FR-45`

**Tier 3 — Earns its place last.** Genuinely valuable, genuinely deferrable, and each degrades gracefully if dropped.
`FR-25` (Speaker Profiles — highest technical uncertainty, see §13 Q4), `FR-27` (LLM Backend — the Heuristic Backend already satisfies FR-26 on this machine), `FR-48` (re-run onboarding).

A Tier-0 build that works beats a Tier-2 build that half-works, and the tiers are ordered so that stopping after any tier leaves a coherent product.

**Tier 4 — Increment 2, from first use.** Tiers 0-3 are built and shipping. These come from the user operating that build, so they are ordered by what was actually costing them something rather than by dependency.

1. `FR-53` (verify the Note exists) and `FR-54` (refresh the Library) — a list that disagrees with the folder undermines trust in every other feature, and both defects behind these were real.
2. `FR-40` amended (discoverable, multi-select delete) — the user could not find deletion at all.
3. `FR-51` (curate remembered voices) — makes FR-25 correctable, which is also what makes §13 Q4 answerable by observation.
4. `FR-49` (menu bar timer) and ~~`FR-50` (animated indicator)~~ — small, visible, and independent of everything above. FR-50 shipped here and was **withdrawn in increment 4** after use; FR-49 stands.
5. `FR-52` (Backend visible and selectable) — closes the question the user asked; no dependency, so it can move if measurement (§13 Q11) changes the shape.

**Tier 5 — Increment 3, summarisation as a chosen capability.** Ordered so the honest-by-default change lands first and the expensive, contested one lands last. A stop after any step leaves a coherent product.

1. `FR-55` (no summary unless something real produced it) plus the `FR-26` amendment — independent of every other item here, improves the product immediately, and removes a misleading artefact the user is reading today. **Ship this even if nothing else in Tier 5 is built.**
2. `FR-56`, `FR-57`, `FR-58` (the pane, precedence, prerequisites) — the surface and its honesty rules. FR-58 must precede any download work: it is what stops a multi-gigabyte fetch on a machine that cannot run the result.
3. `FR-60`'s local half and `FR-61` (progress, measured duration, never block the Note) — the local model path made usable and safe.
4. `FR-59` and `FR-60`'s remote half — the key, per-Meeting consent, cost display. Last on purpose: it is the only part that transmits anything, carries the reviewer's unresolved consent finding, and is worth building only if the local path proves insufficient.

**Tier 6 — Increment 4, knowing which voice is yours.** Four real meetings produced the evidence for this tier, and one of them produced the defect that forced it. Ordered so that the measurement precedes the mechanism and the mechanism precedes the surface.

1. `FR-65`'s calibration — the threshold, measured before anything is built on it. Already done (`spikes/calibration-speaker-threshold-2026-09-01.md`), and it is what turns the rest of this tier from a hope into a specification. **Nothing here should have been built before this.**
2. `FR-62` (record a sample, store a fingerprint) — standalone, opt-in, and useful the moment it exists because the fingerprint is what everything else reads.
3. `FR-63` (identify the user among in-room voices) — the point of the tier. Depends on 1 and 2 and on nothing else.
4. `FR-64` and `FR-65`'s surface (visible, deletable, disclosed) — the honesty half. Small, and the increment is not shippable without it: a stored fingerprint the user cannot see or delete would breach §9.1.

## 7. Success Metrics

Stakes are personal-utility, so these are deliberately few and mostly binary. The honest overall test: **three weeks after it is built, is it still enabled at login?**

**Primary**

- **SM-1: Detection hit rate** *(provisional)* — proportion of Slack huddles and Teams calls that produce a Detection Prompt within 15 s. Target ≥ 90%, **pending §13 Q8**: this rests on `kAudioProcessPropertyIsRunningInput`, which the addendum records as documented-unreliable. Measure before treating 90% as an acceptance gate. Validates FR-11, FR-12.
- **SM-2: Attribution trustworthiness** — Local Speaker attribution correct in 100% of Meetings *where it is claimed at all*; Remote Speaker segments correct often enough that renaming ≤ 3 labels fixes a whole Meeting. Validates FR-21, FR-22, FR-24. **Amended in increment 4:** the metric used to rest entirely on structure, so any failure was a bug by construction. It now has two paths — structural certainty (one voice on the microphone) and an enrolment match (FR-63) — and the second one *can* be wrong. So the metric splits: a claim must be right when made, and a refusal to claim is not a failure. Counting a Meeting where the app honestly said "unidentified" as a miss would reward the guessing this increment removed.
- **SM-3: Output usable unedited** — proportion of Notes that are useful with no manual clean-up. Target ≥ 90%. Validates FR-31 through FR-33.
- **SM-4: Still installed** — the app is still running at login three weeks after first use. Binary. Validates the product.

**Secondary**

- **SM-5: Transcription latency** — 30-minute Session transcribed in under 5 minutes with the default model. Validates FR-16.
- **SM-6: Zero egress** — no outbound network connection after models are cached, verified by monitoring rather than asserted. Validates NFR-6.
- **SM-7: Day-long stability** — a full working day in the menu bar across sleep/wake and device changes with no restart. Validates FR-8, FR-9, NFR-4.

**Counter-metrics (do not optimize)**

- **SM-C1: Prompt frequency** — Detection Prompts per day must stay low enough not to become noise. Counterbalances SM-1: chasing detection rate by loosening the debounce or widening Watched Apps turns the product into a nag, which is the failure mode most likely to get it uninstalled. Prefer a missed huddle to a spurious prompt.
- **SM-C2: Feature count** — surface area must stay small. Counterbalances SM-3 and SM-4: the temptation to improve usefulness by adding panes, settings and integrations is the mechanism by which small tools rot. Any new setting should replace one.
- **SM-C3: Transcription quality chased at any cost** — do not optimize accuracy by defaulting to the largest model. Counterbalances SM-5 and SM-3: a default that takes 25 minutes to process a 30-minute call will not be used, and an unused accurate transcript is worth less than a used adequate one.

## 8. Cross-Cutting NFRs

- **NFR-1: On-device by default; egress only by explicit, per-use consent.** All inference — transcription, Diarization, Metadata — executes locally unless the user has deliberately configured a Remote Summarisation Backend and consented for that Meeting. Audio and Diarization never leave the device under any configuration. Model downloads and, when configured, Remote Summarisation requests are the only permitted network activity; both are user-initiated.

  **Amended in increment 3.** This previously read "No audio, Transcript, or Metadata is transmitted anywhere, ever." That absolute is retired deliberately and in the open, because FR-59 makes a Transcript transmissible. Three parts of it survive as invariants and are *not* negotiable: audio never leaves the device; Speaker Profiles never leave the device (§9.1); and nothing leaves without the user having both configured it and consented to it. The default configuration transmits nothing, and a build with no key entered is still literally zero-egress.
- **NFR-2: Apple Silicon, macOS 15+.** Targets Apple Silicon; deployment target no lower than macOS 14.4 for audio-capture permission reasons, and 15.0+ preferred. Intel is unsupported.
- **NFR-3: Negligible idle cost.** While Idle, CPU use is effectively zero apart from Detection polling, which itself must be cheap enough not to affect battery life measurably.
- **NFR-4: Bounded memory.** Memory during Capture is flat with respect to Session duration. Peak memory during transcription is bounded by the chosen model and does not risk system pressure on a 24 GB machine; two models never load concurrently (FR-20).
- **NFR-5: Failure is visible and non-destructive.** No failure path silently discards audio, a Transcript, or a Note. Every failure surfaces a reason and leaves the underlying data recoverable.
- **NFR-6: Verifiable egress.** The egress claim must be verifiable by an outside observer with a network monitor, not merely asserted in documentation. **Amended in increment 3:** the claim being verified is now conditional rather than absolute, which makes it *harder* to state and therefore more important to state precisely. With no Remote Backend configured, a network monitor must observe zero traffic outside user-initiated model downloads. With one configured, it must observe traffic only to the configured endpoint, only when a Meeting was sent, and never carrying audio.
- **NFR-7: Accessible enough to trust.** Session state is conveyed by shape as well as colour (FR-2). Settings and Library are keyboard-navigable and legible at default system font sizes in light and dark mode.
- **NFR-8: Plain-text durability.** Notes remain fully useful if the app is deleted. No proprietary index, database or sidecar is required to read a Note.

## 9. Constraints and Guardrails

### 9.1 Privacy

- Recording other people carries an ethical and, in some jurisdictions, legal obligation to disclose. The app does not and cannot enforce consent, but it must not obscure that recording is happening: FR-2's unambiguous Recording state and FR-12's explicit opt-in are the product's contribution. `[NOTE FOR PM]` A "recording in progress" reminder is a plausible v2 addition; it is not an MVP requirement.
- Detection reads audio-device metadata only. It must never read audio content to decide whether a meeting is happening (FR-10). This is an invariant, and any future change that reads audio while Idle breaks the product's premise.
- Retained audio is the largest privacy liability on disk. FR-44 makes retention explicit and FR-40 makes deletion real.
- Speaker Profiles are biometric-adjacent data. They stay local, are never transmitted, and must be deletable.
- **The Enrolled Voice (FR-62) is the most biometric-adjacent thing the product holds**, because it is a fingerprint of a named person deliberately recorded for identification. Four rules bind it, and none is negotiable: nothing is stored until the user records a sample; the sample audio is destroyed as soon as the fingerprint is derived, so what persists is a vector and not a recording of anyone's voice; the fingerprint never leaves the machine under any configuration, including a configured Remote Backend; and one control deletes it. `[NOTE FOR PM]` "Biometric-adjacent" is the honest word rather than "biometric": a 256-number embedding is not a recording and cannot be played back, but it identifies a person, and treating it as ordinary preference data would be wrong.
- Enrolment records only the Mic Stream. It cannot capture the far end of a call, so it cannot become a way to sample a colleague's voice without them being in the room.
- **Meeting content must not reach the repository through prose either.** *Added increment 7.* The structural guarantee (`Scripts/check-no-user-data.sh`) keeps audio, records and embeddings out by path and by shape, and it works. It cannot see a real meeting title quoted in a design document or borrowed for a UI fixture, and by the time this was noticed the repository was public and two committed files carried real titles — one review sentence and the `--uishot` fixtures. A meeting title is meeting content. Planning documents substitute titles and filenames, keeping only the property the evidence rests on; fixtures use invented words; and the guard grows a local-only check that can see this class, because the check needs the user's library to know what a real title looks like and CI does not have it.

### 9.2 Cost

- Zero run-time cost is a design constraint, not an outcome — it is what makes a tool with no business model sustainable. **Amended in increment 3:** it remains the constraint on every path the app ships enabled. A Remote Summarisation Backend has a per-use cost, so it is off by default, must never become the default, and FR-60 requires the cost be shown before it is incurred. A user who never enters a key never pays anything.
- Disk is the only real resource cost: models (hundreds of MB to ~1.5 GB) plus retained audio. Both must be visible and clearable (FR-44).

### 9.3 Honesty of derived content

Generated Metadata must never be presented as fact when it is inference — FR-30's provenance field and FR-29's timestamp references exist so a reader can check derived content against the record — and no section is ever padded with invented content: an absent decision list is the correct output for a meeting with no decisions.

**Amended in increment 8, after the strongest possible counter-example.** The rules above govern how derived content is *labelled*, and every one of them was satisfied while the product produced three days of invented dialogue: the provenance field correctly said `heuristic`, the timestamps were real, no section was padded. What none of them covered is derived content resting on an *input the app cannot vouch for* — a different failure, because labelling cannot fix it. A summary honestly marked as keyphrase extraction from a fabricated transcript is not honest output. So this guardrail gains a floor beneath its labelling rules: **the app does not derive content from audio that failed its evidence check** (FR-86), and it says which recording it cannot vouch for (FR-87). Honesty about provenance is not a substitute for honesty about fidelity.

## 10. Information Architecture and Visual Design

*Included because the user asked for "a small, clean UI" and then named a concrete reference — FluidVoice — for how model setup should feel. This section fixes the shape so UX and implementation do not diverge; it constrains layout and hierarchy, not pixels.*

### 10.1 Surfaces

There are exactly two surfaces. Adding a third is a scope violation.

1. **The menu bar item** — the primary surface. Session state and start/stop. Used many times a day (§4.1).
2. **One window with a grouped sidebar** — setup, settings and the Library. Used rarely, mostly once (§4.8, §4.9).

### 10.2 Sidebar groups

Grouped headings over a flat list, following the reference:

- **Setup** — Setup Checklist (FR-46), Test Playground (FR-47), Voice Enrolment (FR-62), re-run onboarding (FR-48).
- **Transcription** — Transcription Model selection and download (FR-17, FR-18).
- **Meetings** — the Library (§4.8).
- **Detection** — Watched Apps and suppression (FR-43).
- **General** — Notes Folder, Local Speaker Label, audio retention, launch at login, remembered voices including the Enrolled Voice (FR-34, FR-21, FR-44, FR-45, FR-51, FR-64).

### 10.3 Checklist row anatomy

The Setup Checklist row is the one component worth specifying precisely, because it is what the user pointed at:

| Slot | Content |
|---|---|
| Leading indicator | A satisfied glyph when done; the row's ordinal when outstanding |
| Title | What the item is, in three or four words |
| Subtitle | One line on *why* it is needed — never omitted, never longer than a line |
| Trailing control | A dim, non-interactive "Done" indicator when satisfied; a labelled action button when outstanding |

Satisfied rows are de-emphasised — reduced contrast on text and indicator — so the eye lands on outstanding work. Optional rows are labelled as optional in the title and never render as errors.

### 10.4 Visual conventions

- **System-native.** Standard macOS controls, system fonts, system materials. No custom chrome, no bespoke control library. This is what keeps a small tool cheap to maintain (SM-C2).
- **One accent colour**, used for the primary action in a pane and for the Recording state. Everything else is system greys. The reference uses a single teal accent this way, and the restraint is the point.
- **Cards group related content** on a subtly recessed background; headings sit outside the card.
- **Light and dark mode both first-class** (NFR-7).
- **Menu bar icon** is a template image so macOS tints it correctly, except where the Recording state's colour is load-bearing — and there, shape carries the same information for colour-blind users and greyscale menu bars (FR-2).
- **Copy is plain and specific.** "Record this meeting?" not "Meeting detected". Explain *why* a permission is needed at the moment it is asked for. No exclamation marks, no cheerfulness.

### 10.5 Deliberate omissions

No dashboard, no statistics, no usage graphs, no changelog pane, no feedback form, no in-app update prompts. The reference product has several of these; they belong to a product with users, and this one has one user. Named here so their absence reads as a decision.

## 11. Performance Budgets

Targets on the reference machine (Apple M5, 24 GB, macOS 26.6):

| Budget | Target |
|---|---|
| Icon state change after underlying transition | < 500 ms |
| Start Recording → audio actually captured | < 2 s |
| Detection of input-device acquisition or release | < 15 s |
| Auto-stop after triggering app releases input | < 30 s |
| Transcription, 30-min Session, default model | < 5 min |
| Heuristic Backend Metadata, 2-hour Transcript | < 2 s |
| Library list responsive at | ≥ 500 Meetings |
| Max supported Session length | ≥ 3 hours |
| Idle CPU | negligible; no Idle animation |
| Retained audio, per hour of Meeting, both Streams | ≤ 250 MB · **measured 230 MB** |
| Editing a Meeting's title or a Speaker Label | must not re-render the Transcript · **added increment 4** |

Model-specific transcription throughput must be **measured on the target machine, not estimated**, and the model picker's speed guidance should derive from those measurements.

**Audio storage budget, added in increment 3.** There was no budget here, and the omission cost real disk: the writer stored the capture format straight through — 48 kHz float32, stereo for the System Stream — at 532 KB/s across both Streams, 1.96 GB per hour, 1.5 GB for a 45-minute Meeting. With FR-44 retention on by default that grows without bound.

Nothing consumed the extra resolution. Both transcription engines and the Diarizer resample to 16 kHz mono before doing anything, so 6× the data was being stored in order to be discarded on every read. Streams are now written at **16 kHz mono, 16-bit** — the rate Whisper and Parakeet were trained on, and the standard depth for speech. Measured: 64 KB/s, **8.4× smaller**, and a 45-minute Meeting drops from 1.47 GB to 176 MB.

The budget is stated as a target so that a future format change has something to violate rather than a silence to slip through.

**Voice enrolment, added in increment 4, and now measured.** The target was "under 10 seconds to derive a fingerprint from a 25-second sample", stated as a target because nothing had been run. It has now been run against real audio on this machine:

| Measurement | Figure |
| --- | --- |
| Embedding an 8.4-second recording, fresh process | **0.30 s** |
| Embedding a 2032-second recording, models warm | **8.5 s** |
| Voices reported for a mic stream the Diarizer had found 5 voices in | **5** — exact agreement |

So a 25-second enrolment sample costs well under a second, and the 10-second target is met with two orders of magnitude to spare. *(The 25-second figure itself is a short linear extrapolation from the two measurements above, not a reading — no 25-second sample exists yet.)* Comparing an Enrolled Voice against a Meeting's in-room voices remains a handful of 256-element dot products and is free at any Meeting length; that one is arithmetic and never needed measuring. Storage is negligible and worth stating only so it is not wondered about: one fingerprint is 256 single-precision floats — about 1 KB as JSON, and it replaces no audio because the audio is deleted.

## 12. Platform, Permissions and Signing

*This section exists because the product's largest delivery risk is not a feature — it is macOS consent mechanics, and no template cluster names it.*

- **Two separate permissions are required**, with asymmetric ergonomics. Microphone access has a normal request API and a queryable state. System-audio capture has **neither** — there is no public API to request it or to query it. Its state can only be inferred from whether Capture succeeds and yields non-silent audio. FR-42 is written around that limitation, and the UI must not fake certainty.
- **Consent is bound to the app's code signature.** macOS records the app's *designated requirement* when consent is granted and re-checks it on every access. Ad-hoc signed code has a requirement, but — in Apple's own words (TN3127) — it "is tied to that specific version of the code", so **rebuilding invalidates previously granted consent**. The user-facing consequence is a re-grant after every rebuild, and a documented reset command.
- **Amended in increment 5: this stops being an accepted condition.** It was tolerable while the only user was the author, who rebuilds deliberately and knows the reset command. It is not tolerable once anyone else installs the app, because every update silently costs them their microphone and system-audio consent. FR-73 requires that consent survive an update, which requires a Developer ID certificate: that requirement checks the Apple anchor, the bundle identifier and the Team ID rather than a binary hash, so it is satisfied by a later build and even by a renewed certificate. The bundle identifier is therefore fixed permanently, and signing moves from ad-hoc to Developer ID with notarization (§12 continues to forbid bypassing Gatekeeper rather than satisfying it).
- **Truly unsigned builds never receive the permission prompt at all.** Signing — even ad-hoc — is therefore part of the build, not an optional packaging step.
- **App Sandbox must be disabled** for v1; audio taps behave unreliably under sandbox. Hardened Runtime stays on. This forecloses App Store distribution, which §5 already excludes.
- The app must be installed at a **stable path** so consent is not additionally invalidated by moving the bundle. `[ASSUMPTION: path stability matters for consent. TN3127 describes the designated-requirement check purely in terms of code identity and does not mention filesystem location; the well-documented path-sensitive mechanism is Gatekeeper's app translocation, which is related but distinct. Installing to /Applications avoids translocation and remains the right practice, but the specific claim that moving the bundle invalidates consent is not something this project has verified or found an Apple source for.]`

## 13. Open Questions

1. **Actual transcription throughput per model on M5.** Drives the default model choice and the model picker's guidance. Must be measured during implementation. Blocks nothing; informs FR-17.
2. **Diarization accuracy on real huddle audio with 3+ remote speakers**, and whether speaker count should be left automatic or estimated. Informs FR-22.
3. **Is diarizing the System Stream alone materially better than diarizing a mixed stream?** The architecture assumes yes (it is also structurally cleaner). Worth one comparison once real audio exists.
4. ~~**Does voice-embedding similarity work well enough across separate recordings** to make Speaker Profiles (FR-25) trustworthy?~~ **Answered 2026-09-01 for in-room voices, narrowed for Remote Speakers.** Measured on four real Meetings: the same in-room voice landed 0.058–0.248 apart across independent recordings, different in-room voices in one Meeting 0.596 and above — a factor-of-2.4 gap with nothing in it. For Remote Speakers the populations touch (same up to 0.248, different from 0.254) and no threshold separates them, so remote matching stays a correctable inference. The threshold moved from 0.45 to 0.35 on that evidence. See `spikes/calibration-speaker-threshold-2026-09-01.md` and FR-65.
5. **On-device foundation model context limit**, and therefore the chunking threshold for long Transcripts. Informs FR-27.
6. **Does ad-hoc-signed consent survive rebuilds** more often than theory suggests? Determines whether "stable install path + re-grant note" is adequate UX or whether obtaining a certificate becomes a prerequisite.
7. **Does the aggregate device need rebuilding when the default output device changes** mid-Session? Directly determines the FR-8 implementation.
8. **Auto-stop reliability** — if input-release detection proves unreliable, FR-14 needs a fallback (an inactivity timeout, or a maximum Session length).

Raised by increment 2:

9. **How much menu bar width is acceptable for the FR-49 timer?** A running clock next to the icon competes with every other menu bar item on a laptop display. Informs FR-49; may need a shorter format, or an option to show it only past a threshold.
10. ~~**Does the FR-50 pulse survive NFR-3 over a two-hour Session?**~~ **Retired 2026-09-01, unanswered and moot.** FR-50 is withdrawn, so there is no repeating animation to measure. Worth noting what it cost to leave open: the question was raised in increment 2 and never measured, and the feature it guarded was removed for a reason that had nothing to do with cost.
11. **Should FR-52's Backend choice be per-Meeting rather than global?** A global toggle is simpler and matches the ask; retrying one Meeting with the other Backend is the plausible next want. Deferred, not decided.
12. ~~**Is FR-53's check cheap enough to run on every Library appearance**, or does it need to be tied to FR-54's explicit refresh?~~ **Answered 2026-09-03 by mechanism rather than by measurement.** The existence check is one `stat` per complete Meeting and stays on every reload. The expensive part — reading the head of every file in the Notes Folder — is what FR-78 introduces, and it runs *only when a check has already failed*. A library with no broken links never reads a single file, so the cost is zero in the case that is true almost always, and proportional to the folder only in the case where the user is waiting for an answer anyway.

Raised by increment 3:

13. **Is a 4-bit local model in the 3-6 GB class actually good enough at meeting summarisation?** Unanswered, and unanswerable until the Metal toolchain is installed — the spike could not generate a single token. This is the question the whole increment rests on: if the answer is no, FR-59's remote path stops being optional. Informs FR-56's curated list and FR-60's measured figures.
14. **What is the peak resident memory for a 9B 4-bit model plus KV cache on a two-hour Transcript**, and does NFR-4 hold on 24 GB? Determines the largest model the curated list may offer, and whether long Transcripts need the FR-27 chunking contract regardless of Backend.
15. **Which local model family?** The spike found `Qwen3.5`, `Qwen3.6` and `Qwen3.8` conversions all present on `mlx-community`, with download counts favouring older Llama and Qwen builds. The list must be built from a live query (FR-56), but the *curation* still needs a judgement, and that judgement needs Q13's measurement first.
16. **Does the Metal toolchain prerequisite survive distribution?** It is a build-time dependency here. Whether a user of a built app needs it too depends on the metallib being correctly bundled as a resource — which the current build script does not do. Informs FR-58 and the build pipeline.
17. **Which remote endpoint, if any?** Left open deliberately. If your employer has an approved vendor under a data processing agreement, that is the answer and it changes FR-59's consent copy. If not, the honest answer may be that FR-59 should not ship at all.

Raised by increment 4:

18. **Does a fingerprint from a deliberate 20–30 second sample behave like one derived from a whole Meeting?** Every figure in the calibration comes from Meeting-derived centroids. An enrolment sample is shorter but cleaner — one speaker, no crosstalk, a known device — which should help, and the two shortest samples in the data (11 words and 1 word) were visibly unreliable, which is why 20–30 seconds and not 5. **Half of this is now answered.** The *cost* is measured (§11: 0.30 s for an 8.4-second recording in a fresh process), and the embedder's voice count agrees exactly with the Diarizer's on a five-voice room, which is what FR-62's multi-voice refusal depends on. The *quality* half — whether a 25-second sample's centroid lands as close to the same person's Meeting centroids as two Meeting centroids land to each other — still needs one real enrolment followed by one real meeting. Informs FR-62's duration and FR-65's threshold.
19. **Does an Enrolled Voice recorded on one input device match a Meeting recorded on another?** The calibration's four Meetings all used the same device. AirPods and the built-in microphone colour a voice differently, and the spike already found the app had been recording through AirPods without recording *that* it had. FR-63 may need the device recorded alongside the fingerprint, or a second sample per device. Informs FR-62.
20. **How often does the ambiguity rule fire in practice, and is refusing the right call when it does?** FR-63 claims nothing when two in-room voices are both close to the Enrolled Voice. The measurement says that should be rare (in-room voices sat ≥ 0.596 apart), but a Diarization split of the user's own voice would produce exactly that shape, and then the honest refusal costs the user the feature. Worth counting before changing.
Raised by increment 7:

22. **Is `started_at` a sufficient identity key for Notes written before FR-77?** It is sufficient on this machine — fifteen Notes, all stamped to the second, no two Meetings within a second. It stops being sufficient for anyone who records two Meetings starting in the same second, which a scripted or automated start could do. The fallback is only ever consulted for a Note with no Meeting ID, so the population shrinks to zero over time; the question is whether that is fast enough to leave alone. Informs FR-78.
23. **Should the Notes Folder be watched, so a Finder rename is noticed without a refresh?** Reconciliation on reload plus the explicit refresh (FR-54) makes the state correct but briefly stale — a renamed Note reads as missing until something reloads. A folder watcher fixes the staleness and adds a live subsystem, a permission-adjacent API and a class of event storm to reason about. Deliberately ranked last: the correctness is in FR-78, and only the latency is in the watcher.
24. **What should happen to an Unclaimed Note when the user says "dismiss"?** Currently: forgotten from the listing, file untouched, and it returns if the app forgets that it forgot. The alternative — a marker in the file — means writing to a file whose Meeting no longer exists, which is worse. Informs FR-82.

21. **Does §9.1's "the audio is destroyed" survive the implementation of re-recording?** Re-recording replaces a fingerprint, and the obvious lazy implementation keeps the previous sample around "just in case". It must not. This is a code-review item as much as an open question, and it is listed because the failure would be invisible.


**Q19 (increment 9): does the English-only model deserve to be the default?**
Pooled over three AMI sessions it is 2.3 points better on close mics and tied
far-field, but the per-session swing is ±8 points — larger than the effect.
*Revisit when* the harness has nine or more sessions spanning native and
non-native English. Owner: whoever next touches `ModelCatalog`.

**Q20 (increment 9): what distinguishes a far-field recording from a close one?**
Normalisation is worth ~2 points far-field and costs ~2 close, so the gate is
the whole question, and integrated loudness does not answer it (the corpus and
the user's library both overlap heavily). *Revisit when* a reverberation or
direct-to-reverberant measure has been trialled. Until then FR-93's harness
measures the two conditions separately rather than pretending one setting fits.

**Q21 (increment 9): why does session variance dominate model choice?**
The hardest session for every engine measured (27–35% WER against 15–19% on the
easiest) is AMI's non-native-speaker set. If accent is the driver it bears
directly on this product, whose meetings are not held in first-language English.
*Revisit when* a non-native-heavy session set can be scored separately.

## 14. Assumptions Index

Every inference made without user confirmation. The user was unavailable for this run, so this list is unusually long and should be read as the review surface.

- **§0, product name** — "Minutes" was chosen; the user supplied no name. Held in one constant.
- **§10, information architecture** — *not* an assumption. The user supplied FluidVoice as an explicit reference for how model setup should feel, mid-run. The sidebar shape, Setup Checklist row anatomy and Test Playground derive from that directive. What *is* inferred is the specific sidebar grouping and the decision to fold the Library into the same window rather than keep two windows.
- **§2, persona** — the primary user is Niklas himself, working in a Slack-and-Teams company. Inferred from the request and from the apps installed on the machine.
- **§2.3 UJ-1** — the user wants auto-stop when a detected meeting ends. Requested behaviour was "prompt to start"; stopping was not specified. Auto-stop is inferred from the same motivation (not having to remember), and FR-14 deliberately restricts it to detected Sessions only.
- **§3, dual-stream as a Glossary-level concept** — elevating "two Streams" into the vocabulary is a design commitment, not a user request. It is what makes FR-21 possible.
- **§4.3, Watched Apps** — Slack and Teams only, matching the request exactly. Chrome was *not* included despite being installed.
- **§4.5, FR-25 Speaker Profiles** — the user asked to "try and figure out speakers". Persisting names across meetings goes beyond the literal ask; it is inferred from the ask being about *usefulness* rather than about labels. Flagged as the first cut candidate.
- **§4.6, two Backends** — the user said "models should run local" and asked for title and tags. The dual-backend design is a response to the verified fact that Apple Intelligence is off on the target machine; an LLM-only design would ship an app that cannot title a meeting there.
- **§4.6, summary/decisions/action items** — the user asked for "the title, tags etc.". The "etc." is interpreted as summary, decisions and action items. This is the largest interpretive leap in the PRD.
- **§4.8, Library** — a browsing UI was not requested. It is inferred as necessary because FR-24 renaming and FR-39 retry need a surface, and the request did ask for "a small, clean UI".
- **§4.9, FR-44 retention** — audio retention as a user choice was not requested; inferred from FR-19 retry needing audio and from privacy hygiene requiring an off switch.
- **§4.9, FR-45 launch at login** — inferred from SM-4; a menu bar tool that must be launched manually will not survive.

**Increment 2.** These carry materially less inference than the list above, because each one came from the user operating the built app rather than from reading the original request. What remains inferred:

- ~~**§4.1, FR-50 animation character**~~ — "animate the red dot slightly" was the ask, and that it should be a slow pulse rather than a blink or a spinner was this PRD's reading of "slightly". **Resolved by use in increment 4, against the assumption:** the user withdrew the animation entirely and kept the solid dot. Left in the index because an assumption that turned out wrong is more informative than one that turned out right.
- **§4.5, FR-51 rename semantics** — that renaming a remembered voice does not retroactively relabel past Meetings. Not requested either way; chosen because the alternative rewrites Notes the user may have edited by hand.
- **§4.5, FR-51 provenance fields** — that sample count and last-matched date are the useful things to show. Inferred from what makes a match judgeable, not from the request.
- **§4.6, FR-52 pin-the-Heuristic-Backend** — the user asked what performs summarisation and where its settings are. That the answer should include an override, rather than only an explanation, is inferred from a deterministic summary being sometimes preferable.
- **§4.8, FR-40 multi-select delete** — "mainly deleting them" was the ask. Multi-select is inferred from the plural and from the state the user is actually in (several test recordings), not stated.

**Increment 3.** The direction here was explicit — *"Lets not rely on apple intelligence for this. But keep it as a possibitly. We should add a settings page for this intellingene for summarisation similar to the model selection for transcription. We could allow local download, or the key."* — so the assumptions are about shape, not intent. A spike replaced several would-be assumptions with measurements; those are in the spike report, not here.

- **§4.6, FR-55 gating scope** — that keyphrase extraction keeps producing *titles and tags* while losing the *summary*. The instruction said "raw transcript and title setting etc. for the basic", which reads as keeping the cheap useful parts; tags were not mentioned either way. Chosen because the observed title quality is adequate and the observed summary quality is not.
- **§4.10, FR-56 three families** — that Apple's model, a downloadable local model and a remote key are the right three entries. The first two were named by the user; grouping them as one comparable list rather than three separate settings is inferred from "similar to the model selection for transcription".
- **§4.10, FR-59 consent granularity** — that consent is per-Meeting rather than a single global switch. Not requested; inferred from the reviewer's finding that a Transcript contains other people's speech, and deliberately more restrictive than the user asked for.
- **§4.10, FR-60 cost display** — that showing an estimate before sending is required rather than optional. Inferred from §9.2 naming zero cost as a constraint; the alternative is discovering spend after the fact.
- **§8, NFR-1 amendment wording** — that audio and Speaker Profiles remain absolute never-transmit invariants while Transcript text becomes conditional. The user asked for a key option and said nothing about what may travel; this is the narrowest amendment that permits the feature.
- **§4.9, FR-47 Test Playground scope** — that the playground should report per-Stream audio presence and measured throughput (rather than merely showing transcribed text as the reference product does) is inferred. It is justified by §12: there is no API to query system-audio permission, so this is the only way the user can confirm the app can do its job.
- **§6.2** — Zoom/Meet/Discord excluded because the user named only Slack and Teams.
- **§7** — all metric targets are set by inference. None was given.
- **§10** — every performance budget is inferred from what "small and focused" implies on this hardware. They are stated to be falsifiable, not because they were specified.
- **§12** — that ad-hoc signing is acceptable, rather than obtaining an Apple Developer certificate, is an assumption about the user's willingness. If a certificate is available, most of §11's pain disappears.

**Increment 4.** The direction was unusually complete — opt-in, deletable, local-only, one threshold and no dial, plain maths on the sound, no auto-exclusion — so most of what would normally be inferred was specified. And one figure that would previously have been an assumption is now a measurement, which is the difference between this increment and the three before it. What remains inferred:

- **§4.5, FR-62 sample length** — that 20–30 seconds is the right ask. The instruction said "~20–30 seconds", so the range is given; landing on a specific value inside it is inferred from the two visibly-unreliable short samples in the calibration data rather than from a measurement of enrolment itself.
- **§4.5, FR-63 ambiguity rule** — that two in-room voices both close to the Enrolled Voice should produce *no* identification rather than the nearer one. Not requested. Chosen because it is the AD-11-consistent answer — a claim the data does not support is the failure mode the whole increment exists to remove — and because the cost of refusing is one rename while the cost of a wrong claim is a colleague's words under the user's name. Logged as §13 Q20 because the trade-off deserves counting.
- **§4.5, FR-62 re-record replaces rather than averages** — not stated either way. Chosen because a re-record is most plausibly a correction of a bad first sample, and averaging a correction into the thing it corrects preserves the error.
- **§4.5, FR-64 the Enrolled Voice applies no name** — that the user's display name keeps coming from the existing setting rather than from the Profile. Inferred from there being one obvious place for it already; two places to edit one name is the defect this avoids.
- **§4.9, the row is last in the checklist** — that Voice Enrolment sits after "Test your setup" rather than before it. Inferred: prominence comes from being in the primary checklist at all, and renumbering a shipped row to make room would disturb a surface the user already knows.
- **§11, enrolment performance budgets** — both figures are targets, not measurements, and are labelled as such. The comparison cost is arithmetic and safe; the fingerprint-derivation cost is not, and §13 Q18 owns it.
