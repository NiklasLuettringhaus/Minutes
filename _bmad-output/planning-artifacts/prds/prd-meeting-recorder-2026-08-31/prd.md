---
title: Minutes — local-first meeting recorder for macOS
status: final
created: 2026-08-31
updated: 2026-08-31
owner: Niklas
mode: headless (-A)
inputs:
  - _bmad-output/planning-artifacts/briefs/brief-meeting-recorder-2026-08-31/brief.md
  - _bmad-output/planning-artifacts/briefs/brief-meeting-recorder-2026-08-31/addendum.md
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
- **Stream** — one of exactly two audio sources in a Capture: the **Mic Stream** (local microphone, attributed to the Local Speaker) or the **System Stream** (all other applications' audio output, containing Remote Speakers).
- **Local Speaker** — the person at the machine. Certain only when the Mic Stream held a single voice; default label `Me`.
- **In-Room Speaker** — a voice in the Mic Stream when it held more than one, i.e. someone physically with the user. Anonymous (`In-room 1`, `In-room 2`, …) until renamed; the app does not guess which one is the Local Speaker.
- **Remote Speaker** — a participant on the far end, present only in the System Stream. Anonymous (`Speaker 1`, `Speaker 2`, …) until renamed.
- **Place** — whether a voice was in the room or remote. Derived from which Stream carried it, so it is structural and never inferred — unlike identity.
- **Speaker Label** — the display name for a Local or Remote Speaker in a Note. User-editable.
- **Speaker Profile** — a persisted association between a voice and a Speaker Label, used to reapply a name in later Meetings.
- **Diarization** — splitting the System Stream into time segments per Remote Speaker.
- **Transcript** — the ordered list of Utterances for a Meeting.
- **Utterance** — one contiguous span of speech: start time, end time, text, and exactly one Speaker Label.
- **Transcription Model** — a selectable local Whisper model variant, with a size on disk and a speed/accuracy character.
- **Metadata** — the derived, non-transcript content of a Meeting: title, tags, summary, decisions, action items, and the name of the Metadata Backend that produced them.
- **Metadata Backend** — the component producing Metadata. Exactly one of **LLM Backend** (Apple on-device foundation model) or **Heuristic Backend** (deterministic local extraction). Never both for one Meeting.
- **Note** — the single Markdown file written for a Meeting: YAML frontmatter, then Metadata, then Transcript.
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

**Feature-specific NFRs:**
- Idle CPU use attributable to the menu bar component is negligible (see NFR-3); the icon must not animate while Idle.

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

#### FR-17: Select a Transcription Model
The user can choose among available Transcription Models. Realizes UJ-4.

**Consequences (testable):**
- The list states, per model, its relative speed, its relative accuracy, and its size on disk.
- The currently active model is unambiguous.
- The available list reflects what the transcription stack actually offers rather than a hardcoded list that can drift.
- A recommended default is pre-selected so a user can proceed without choosing.

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

**Description:** Speakers are resolved by combining a structural fact with a model. Everything in the Mic Stream is the Local Speaker, known with certainty. Everything in the System Stream is a Remote Speaker, split by Diarization into anonymous labels. The two are merged into one chronological Transcript. Anonymous labels are renameable, and a rename is remembered so the same voice arrives pre-named next time. Realizes UJ-3.

**Functional Requirements:**

#### FR-21: Attribute the Mic Stream to in-room voices
All Utterances derived from the Mic Stream are attributed to an in-room voice — the Local Speaker when the Mic Stream held a single voice, otherwise an anonymous In-Room Speaker.

*Revised 2026-08-31 on user correction: the microphone is not necessarily the user. In a meeting room it captures the user and whoever is beside them, and attributing all of it to the Local Speaker puts colleagues' words in the user's mouth.*

**Consequences (testable):**
- No Mic Stream Utterance is ever attributed to a Remote Speaker, and no System Stream Utterance is ever attributed to an in-room voice. This is structural and cannot be wrong.
- When the Mic Stream contains exactly one voice, it is the Local Speaker. This attribution cannot be wrong either.
- When the Mic Stream contains more than one voice, each becomes a distinct In-Room Speaker and **none is claimed to be the Local Speaker**.
- The Meeting records that the room held several people, and the Note discloses it.
- The Local Speaker Label defaults to `Me` and is user-editable in Settings.
- Naming an In-Room Speaker — including naming oneself — creates a Speaker Profile, so the same voice is recognised in later Meetings (FR-25).

#### FR-22: Diarize both Streams
Utterances are assigned speaker labels by on-device Diarization, run separately on each Stream: the System Stream yields Remote Speakers, and the Mic Stream yields the Local Speaker or In-Room Speakers per FR-21.

**Consequences (testable):**
- Diarization runs entirely on-device with no network access.
- Each Stream is diarized independently; a speaker found in one Stream is never merged with one found in the other.
- A Stream with a single speaker yields one label, not several.
- The number of Remote Speakers is determined from the audio; the user is not required to state it in advance.
- Diarization failure degrades to a single `Speaker` label for the whole System Stream rather than failing the Meeting.

#### FR-23: Merge Streams into one ordered Transcript
The Transcript interleaves Mic and System Stream Utterances in chronological order.

**Consequences (testable):**
- Utterances appear in ascending start-time order regardless of source Stream.
- Overlapping speech from both Streams is represented as separate Utterances, not merged or dropped — people talk over each other and the record should show it.
- Every Utterance in the Transcript carries exactly one Speaker Label.

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

**Notes:**
- `[NOTE FOR PM]` FR-25 is the highest-uncertainty requirement in the PRD: it depends on voice-embedding similarity across recordings holding up in practice. It is genuinely load-bearing for UJ-3's "he does not do this twice" promise, so it stays in scope — but it is the first candidate to cut to v2 if it proves unreliable, and cutting it degrades the product gracefully to manual renaming per Meeting.

---

### 4.6 Meeting Metadata

**Description:** Every Meeting gets a title, tags and a summary derived on-device from its Transcript, plus decisions and action items where they can be found. `[ASSUMPTION: the request named "the title, tags etc."; summary, decisions and action items are this PRD's reading of "etc." and are the largest interpretive leap in the document.]` Two Metadata Backends satisfy this: the LLM Backend uses Apple's on-device foundation model; the Heuristic Backend uses deterministic local extraction. The LLM Backend is preferred when available and the Heuristic Backend always works — including on the target machine today, where Apple Intelligence is switched off.

**Functional Requirements:**

#### FR-26: Derive Metadata for every Meeting
Every Meeting receives a title, a tag set, and a summary.

**Consequences (testable):**
- No Meeting is ever left untitled; a fallback title derived from date, time and detected application is always available.
- Tags are a small set (target 3-6), lowercase and consistent enough to be usable for filtering across Meetings.
- Metadata generation runs entirely on-device.

#### FR-27: Prefer the LLM Backend when available
When the on-device foundation model is available, it produces the Metadata.

**Consequences (testable):**
- Backend availability is checked at run time, not assumed at build time.
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

---

### 4.8 Library

**Description:** A pane in the main window (§4.9) listing past Meetings so the user can find one, read it, fix a Speaker Label, retry a failed transcription, or reveal the Note in Finder. `[ASSUMPTION: a browsing surface was not requested; it is inferred as necessary because renaming (FR-24) and retry (FR-39) need somewhere to live, and the request did ask for a small clean UI.]` It is a utility view over the Notes, not a second home for the data. Realizes UJ-3.

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

## 5. Non-Goals (Explicit)

These exist to stop the "let me also add the nearby thing" failure mode at epic, story and code level.

- **Not a cloud service.** No account, no server, no sync, no telemetry, no crash reporting. There is no back end to add later without breaking the product's only real claim.
- **Not a team product.** No sharing, no multi-user, no shared archive. One person, one machine.
- **Not live transcription in v1.** Transcription is batch, after the Session ends. Streaming is a v2 direction, and designing v1 around it would compromise the simpler, more reliable batch path.
- **Not automatic recording.** Detection offers; the user decides. Minutes never records without an explicit click, even for a Watched App it has seen a hundred times. This is a deliberate refusal of a convenience.
- **Not voice identification of real people from cold.** Speaker Profiles (FR-25) learn from a name the user typed; the app never attempts to identify a person it was not told about.
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
- Structural Local Speaker attribution, on-device Diarization of Remote Speakers, merged Transcript, renaming, Speaker Profiles (§4.5)
- On-device Metadata via LLM Backend with Heuristic Backend fallback; decisions and action items; provenance recorded (§4.6)
- One Markdown Note per Meeting with YAML frontmatter, user-chosen Notes Folder, in-place rewrite on edit (§4.7)
- Library: list, read, edit, retry, delete (§4.8)
- Settings and first-run: permissions, folder, model, detection, retention, launch at login (§4.9)

### 6.2 Out of Scope for MVP

- **Live/streaming transcription** — deferred to v2. Batch is simpler and more reliable, and the value is 95% present without it.
- **Voiceprint enrolment** ("record 10 seconds of Mikkel") — v2. FR-25 learns passively from renames instead.
- **Zoom, Google Meet, Discord, browser calls as named Watched Apps** — generic input-device detection may happen to cover some; they are not targets and not tested. `[NOTE FOR PM]` Chrome is installed on the target machine, so browser-based calls are plausibly common; if Detection proves solid for Slack and Teams, adding Chrome is cheap and worth revisiting.
- **Cross-meeting search and question answering** — v3 direction; needs a corpus first.
- **Export formats other than Markdown** — Markdown is the point.
- **Localisation** — English UI. Transcription language follows whatever the model supports.
- **Notarization, signing with a Developer ID, distribution** — see §12; no certificate exists.
- **Recovery UI for crash-orphaned Sessions** — FR-9 requires the audio survive on disk; a polished recovery flow does not. Manual recovery is acceptable for v1.

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

## 7. Success Metrics

Stakes are personal-utility, so these are deliberately few and mostly binary. The honest overall test: **three weeks after it is built, is it still enabled at login?**

**Primary**

- **SM-1: Detection hit rate** *(provisional)* — proportion of Slack huddles and Teams calls that produce a Detection Prompt within 15 s. Target ≥ 90%, **pending §13 Q8**: this rests on `kAudioProcessPropertyIsRunningInput`, which the addendum records as documented-unreliable. Measure before treating 90% as an acceptance gate. Validates FR-11, FR-12.
- **SM-2: Attribution trustworthiness** — Local Speaker attribution correct in 100% of Meetings (structural, so any failure is a bug); Remote Speaker segments correct often enough that renaming ≤ 3 labels fixes a whole Meeting. Validates FR-21, FR-22, FR-24.
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

- **NFR-1: On-device only.** All inference — transcription, Diarization, Metadata — executes locally. No audio, Transcript, or Metadata is transmitted anywhere, ever. Model downloads are the sole permitted network activity, are user-initiated, and target only the model repositories.
- **NFR-2: Apple Silicon, macOS 15+.** Targets Apple Silicon; deployment target no lower than macOS 14.4 for audio-capture permission reasons, and 15.0+ preferred. Intel is unsupported.
- **NFR-3: Negligible idle cost.** While Idle, CPU use is effectively zero apart from Detection polling, which itself must be cheap enough not to affect battery life measurably.
- **NFR-4: Bounded memory.** Memory during Capture is flat with respect to Session duration. Peak memory during transcription is bounded by the chosen model and does not risk system pressure on a 24 GB machine; two models never load concurrently (FR-20).
- **NFR-5: Failure is visible and non-destructive.** No failure path silently discards audio, a Transcript, or a Note. Every failure surfaces a reason and leaves the underlying data recoverable.
- **NFR-6: Verifiable egress.** The zero-egress claim must be verifiable by an outside observer with a network monitor, not merely asserted in documentation.
- **NFR-7: Accessible enough to trust.** Session state is conveyed by shape as well as colour (FR-2). Settings and Library are keyboard-navigable and legible at default system font sizes in light and dark mode.
- **NFR-8: Plain-text durability.** Notes remain fully useful if the app is deleted. No proprietary index, database or sidecar is required to read a Note.

## 9. Constraints and Guardrails

### 9.1 Privacy

- Recording other people carries an ethical and, in some jurisdictions, legal obligation to disclose. The app does not and cannot enforce consent, but it must not obscure that recording is happening: FR-2's unambiguous Recording state and FR-12's explicit opt-in are the product's contribution. `[NOTE FOR PM]` A "recording in progress" reminder is a plausible v2 addition; it is not an MVP requirement.
- Detection reads audio-device metadata only. It must never read audio content to decide whether a meeting is happening (FR-10). This is an invariant, and any future change that reads audio while Idle breaks the product's premise.
- Retained audio is the largest privacy liability on disk. FR-44 makes retention explicit and FR-40 makes deletion real.
- Speaker Profiles are biometric-adjacent data. They stay local, are never transmitted, and must be deletable.

### 9.2 Cost

- Zero run-time cost is a design constraint, not an outcome — it is what makes a tool with no business model sustainable.
- Disk is the only real resource cost: models (hundreds of MB to ~1.5 GB) plus retained audio. Both must be visible and clearable (FR-44).

### 9.3 Honesty of derived content

Generated Metadata must never be presented as fact when it is inference — FR-30's provenance field and FR-29's timestamp references exist so a reader can check derived content against the record — and no section is ever padded with invented content: an absent decision list is the correct output for a meeting with no decisions.

## 10. Information Architecture and Visual Design

*Included because the user asked for "a small, clean UI" and then named a concrete reference — FluidVoice — for how model setup should feel. This section fixes the shape so UX and implementation do not diverge; it constrains layout and hierarchy, not pixels.*

### 10.1 Surfaces

There are exactly two surfaces. Adding a third is a scope violation.

1. **The menu bar item** — the primary surface. Session state and start/stop. Used many times a day (§4.1).
2. **One window with a grouped sidebar** — setup, settings and the Library. Used rarely, mostly once (§4.8, §4.9).

### 10.2 Sidebar groups

Grouped headings over a flat list, following the reference:

- **Setup** — Setup Checklist (FR-46), Test Playground (FR-47), re-run onboarding (FR-48).
- **Transcription** — Transcription Model selection and download (FR-17, FR-18).
- **Meetings** — the Library (§4.8).
- **Detection** — Watched Apps and suppression (FR-43).
- **General** — Notes Folder, Local Speaker Label, audio retention, launch at login (FR-34, FR-21, FR-44, FR-45).

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

Model-specific transcription throughput must be **measured on the target machine, not estimated**, and the model picker's speed guidance should derive from those measurements.

## 12. Platform, Permissions and Signing

*This section exists because the product's largest delivery risk is not a feature — it is macOS consent mechanics, and no template cluster names it.*

- **Two separate permissions are required**, with asymmetric ergonomics. Microphone access has a normal request API and a queryable state. System-audio capture has **neither** — there is no public API to request it or to query it. Its state can only be inferred from whether Capture succeeds and yields non-silent audio. FR-42 is written around that limitation, and the UI must not fake certainty.
- **Consent is bound to the app's code signature.** No codesigning identity exists on the target machine, so the app is ad-hoc signed. Ad-hoc identity is derived from the binary hash, which means **rebuilding the app invalidates previously granted consent**. The user-facing consequence is a re-grant after rebuilds, and a documented reset command. This is an accepted condition of v1, and the single most likely cause of "it stopped working".
- **Truly unsigned builds never receive the permission prompt at all.** Signing — even ad-hoc — is therefore part of the build, not an optional packaging step.
- **App Sandbox must be disabled** for v1; audio taps behave unreliably under sandbox. Hardened Runtime stays on. This forecloses App Store distribution, which §5 already excludes.
- The app must be installed at a **stable path** so consent is not additionally invalidated by moving the bundle.

## 13. Open Questions

1. **Actual transcription throughput per model on M5.** Drives the default model choice and the model picker's guidance. Must be measured during implementation. Blocks nothing; informs FR-17.
2. **Diarization accuracy on real huddle audio with 3+ remote speakers**, and whether speaker count should be left automatic or estimated. Informs FR-22.
3. **Is diarizing the System Stream alone materially better than diarizing a mixed stream?** The architecture assumes yes (it is also structurally cleaner). Worth one comparison once real audio exists.
4. **Does voice-embedding similarity work well enough across separate recordings** to make Speaker Profiles (FR-25) trustworthy? This is the PRD's biggest technical unknown. If it fails, FR-25 drops to v2.
5. **On-device foundation model context limit**, and therefore the chunking threshold for long Transcripts. Informs FR-27.
6. **Does ad-hoc-signed consent survive rebuilds** more often than theory suggests? Determines whether "stable install path + re-grant note" is adequate UX or whether obtaining a certificate becomes a prerequisite.
7. **Does the aggregate device need rebuilding when the default output device changes** mid-Session? Directly determines the FR-8 implementation.
8. **Auto-stop reliability** — if input-release detection proves unreliable, FR-14 needs a fallback (an inactivity timeout, or a maximum Session length).

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
- **§4.9, FR-47 Test Playground scope** — that the playground should report per-Stream audio presence and measured throughput (rather than merely showing transcribed text as the reference product does) is inferred. It is justified by §12: there is no API to query system-audio permission, so this is the only way the user can confirm the app can do its job.
- **§6.2** — Zoom/Meet/Discord excluded because the user named only Slack and Teams.
- **§7** — all metric targets are set by inference. None was given.
- **§10** — every performance budget is inferred from what "small and focused" implies on this hardware. They are stated to be falsifiable, not because they were specified.
- **§12** — that ad-hoc signing is acceptable, rather than obtaining an Apple Developer certificate, is an assumption about the user's willingness. If a certificate is available, most of §11's pain disappears.
