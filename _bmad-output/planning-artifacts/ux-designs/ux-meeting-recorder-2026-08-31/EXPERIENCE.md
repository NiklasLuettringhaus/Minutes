---
name: Minutes — Experience
description: Information architecture, states, interactions and flows for a macOS menu bar meeting recorder. Peer contract to DESIGN.md; visual identity lives there.
status: final
created: 2026-08-31
updated: 2026-08-31
design_reference: ./DESIGN.md
sources:
  - ../../prds/prd-meeting-recorder-2026-08-31/prd.md
  - ../../prds/prd-meeting-recorder-2026-08-31/addendum.md
  - ../../briefs/brief-meeting-recorder-2026-08-31/addendum.md
---

# Minutes — Experience

## Foundation

**Form factor:** macOS desktop, Apple Silicon, macOS 15+. Not responsive; not multi-surface.

**UI system:** SwiftUI on AppKit, using stock components — `MenuBarExtra`, `NavigationSplitView`, `Form`, `List`, `UNUserNotificationCenter`. There is no third-party UI library and no custom control library. Both spines inherit macOS platform behaviour; this document specifies only the behavioural delta from stock. Visual identity is `./DESIGN.md`, which owns every colour, type and spacing decision referenced here as `{token}`.

**Two surfaces, and only two** (PRD §10.1):

1. **Menu bar item** — the primary surface. Seen dozens of times a day, interacted with twice. Carries Session state and start/stop.
2. **Main window** — one window, sidebar-navigated. Setup, settings, and the Meetings library. Opened during setup, then rarely.

A third surface is a scope violation. Notifications are not a surface; they are a system affordance this product borrows.

**Interaction budget.** The product's core loop must cost **one click** (accept a Detection Prompt) or **two** (menu → Start Recording). Everything else in the product may cost whatever it costs, because it happens once.

## Information Architecture

### Menu bar menu

Contents are state-dependent and never exceed 8 items (PRD FR-5).

| State | Items |
|---|---|
| **Idle** | `Start Recording` · ─── · `Meetings…` · `Settings…` · ─── · `Quit Minutes` |
| **Recording** | *status line:* `Recording — 12:04` (disabled, `{typography.metric}`) · *stream line:* `Mic + System audio` or `Mic only ⚠` (disabled) · `Stop Recording` · ─── · `Meetings…` · `Settings…` · ─── · `Quit Minutes` |
| **Transcribing** | *status line:* `Transcribing "Weekly sync"…` (disabled) · `Start Recording` · ─── · `Meetings…` · `Settings…` · ─── · `Quit Minutes` |

Rules: `Start Recording` and `Stop Recording` are never both present (PRD FR-3). Status lines are disabled items, not headers, so they are readable by VoiceOver in menu order. Transcribing does not block a new Session — it queues (PRD FR-20).

### Main window sidebar

Grouped headings over a flat list, following the reference (PRD §10.2):

```
SETUP
  Getting Started        → checklist, playground, re-run onboarding
CONFIGURE
  Transcription          → model selection + download
  Detection              → watched apps, suppression, master toggle
  General                → notes folder, your name, retention, launch at login
ACTIVITY
  Meetings               → the library
```

Default destination on first launch is **Getting Started**. Default destination thereafter is **Meetings** — after setup, the library is what a returning user wants. Selection persists across launches.

Each destination is one scrollable pane: a title, a one-line subtitle, then a vertical stack of `{components.card}`s with headings outside them.

### Surface closure

Every PRD requirement resolves to a surface, and every surface has a flow that lands there:

| Need | Surface | Flow |
|---|---|---|
| Start/stop a recording | Menu bar menu | KF-2 |
| Know whether it is recording | Menu bar icon | all flows |
| Be offered a detected meeting | Notification | KF-1 |
| Get set up | Getting Started | KF-4 |
| Confirm it actually works | Getting Started → Test Playground | KF-4 |
| Choose transcription quality | Transcription | KF-4 |
| Stop being asked about an app | Notification action, or Detection | KF-1 |
| Read a past meeting | Meetings → detail | KF-3 |
| Fix a speaker name | Meetings → detail | KF-3 |
| Retry a failure | Meetings → row action | KF-5 |
| Reclaim disk | General | — |

## Voice and Tone

Plain, specific, and never cheerful. The user is a professional using a utility; the copy's job is to be unambiguous and then get out of the way.

**Rules**

- **Say what will happen, not how you feel about it.** "Record this meeting?" not "Meeting detected!" — the second announces, the first asks, and asking is what the product does.
- **Every permission ask states the reason at the moment of asking**, in one line. "Minutes needs your microphone to record your side of the conversation." Never a generic "for full functionality".
- **No exclamation marks. No emoji. No first-person plural.** Not "We're all set!" — "Setup complete."
- **Name the thing that failed and the next action.** Not "An error occurred." → "Transcription failed — the model file may be incomplete. Re-download the model, then retry from Meetings."
- **Never claim certainty the system cannot provide.** System-audio capture state is *inferred*, so the copy says so: "Last recording captured system audio" — not "Permission granted" (PRD FR-42).
- **Absence is stated, not padded.** A meeting with no decisions omits the section. The UI never writes "No decisions found!" in a card.
- **Numbers over adjectives.** "About 6 minutes for a 30-minute meeting on this Mac" beats "Fast".

**Terminology is fixed by the PRD Glossary and used verbatim in the UI.** The user sees *Meeting*, *Transcript*, *Speaker*, *Note*, *Notes Folder*, *Transcription Model*. The UI never says "recording" for a Meeting or "session" to the user — *Session* is an internal term and must not leak into copy.

## Component Patterns

Behavioural specs. Visual specs are in `DESIGN.md § Components`.

### Checklist row (`{components.checklist-row}`)

The borrowed pattern (PRD FR-46, §10.3). Behaviour:

- **State is derived live, never stored.** Each row recomputes from actual system state on pane appearance and on window focus. A permission revoked in System Settings shows as outstanding again without an app restart (PRD FR-46). There is no "setup completed" flag.
- **Satisfied rows are inert** — the trailing `{components.pill-done}` is not focusable and not clickable. A satisfied row is still readable by VoiceOver, announced as "<title>, done".
- **Outstanding rows carry exactly one action**, which either performs the fix in place (request a permission, choose a folder) or navigates to the pane that does (Transcription for a missing model). Navigation selects the destination in the sidebar rather than opening a sheet.
- **Optional rows** are titled "… (Optional)" and never render as an error or block the "setup complete" state.
- Rows never reorder as they are satisfied. Position is stable so the list does not shuffle under the cursor.

The rows, in order:

| # | Row | Required | Satisfied when | Action when outstanding |
|---|---|---|---|---|
| 1 | Transcription model ready | yes | selected model is fully downloaded | `Choose Model →` (→ Transcription) |
| 2 | Microphone access | yes | `AVCaptureDevice` authorization is `.authorized` | `Grant Access` (requests in place) |
| 3 | System audio capture | no* | last capture attempt produced non-silent system audio | `Run Test →` (→ Playground) |
| 4 | Notes folder chosen | yes | a writable folder is set | `Choose Folder…` (opens picker) |
| 5 | Test your setup (Optional) | no | a Test Playground run has succeeded | `Run Test →` |

\* Row 3 is *not required* because PRD FR-7 degrades to Mic-only rather than failing. Its subtitle must say so: "Without this, Minutes records only your side of the conversation." This row is the one place the product's hardest constraint becomes visible to the user, and it must read as a trade-off, not a failure.

### Test Playground (PRD FR-47)

The product's only diagnostic, and the reason the pattern was worth borrowing. macOS exposes no API to query system-audio permission, so this is how a user learns whether the app can do its job.

- One primary control: `Start Test`. Runs a fixed short capture (5 seconds), then transcribes.
- While running: a `{components.state-banner}` recording variant, a countdown, and a live level meter **per Stream** — the two meters are the diagnostic, and a flat System meter is the answer to "is system audio working".
- On completion, reports four things: the Transcript text; **per-Stream audio presence** (Mic ✓ / System ✓ or ✗); the model that ran; and **measured wall-clock transcription time with an extrapolation** ("2.1 s for 5 s of audio — roughly 6 min for a 30-min meeting"). That extrapolation is what makes the model picker honest (PRD §13 Q1).
- Failures are staged and named: no mic audio · no system audio · model missing · transcription failed. Never one generic error (PRD FR-47).
- A test run produces no Meeting and writes no Note. It must not appear in Meetings.
- Available any time, not only during first run. The user should reach for it after granting a permission or changing devices.
- Playing audio during the test is required for the System meter to move. The pane says so *before* the user starts: "Play something — a video, music — so Minutes can check it hears system audio."

### Model row (Transcription pane, PRD FR-17, FR-18)

- Rows are radio-selection, one active. The active model is unambiguous (a selected state, not merely a checkmark in a list).
- Each row states: name, size on disk, and a speed/accuracy character **derived from measurement where a Test Playground run exists**, and from a static estimate otherwise — labelled as such. The product does not present an estimate as a measurement.
- A model not present shows `Download` with `{components.progress-download}` inline during download — determinate, with bytes and percentage.
- Selecting an undownloaded model starts its download and makes it active on completion, not before.
- A cached model shows a `Downloaded` marker and a `Remove` action, with the disk figure.
- The pane states once, plainly: "Downloading a model is the only time Minutes uses the network."
- An interrupted download leaves no partial model that could later load as valid (PRD FR-18). The row returns to the un-downloaded state and says the download was interrupted.

### Meetings list and detail (PRD §4.8)

- Reverse-chronological rows: title, date, duration `{typography.metric}`, and `{components.speaker-chip}`s.
- A row carries its own state: transcribing (with progress), failed (with `Retry`), or complete.
- Detail is a read pane: metadata, then summary/decisions/actions if present, then the Transcript.
- Transcript rendering groups consecutive Utterances from one Speaker under a single label rather than repeating it per line (PRD FR-33).
- Speaker rename is inline on the chip in the detail header — click the chip, type, commit. It is not buried in a sheet or a settings pane, because PRD FR-24 is a frequent action.
- Rename commits on Return or focus loss; Escape cancels. It rewrites the Note in place and, if the label was a Remote Speaker, updates the Speaker Profile (PRD FR-25).
- Row actions: `Reveal in Finder`, `Open in Editor`, `Retry` (failed only), `Delete…`.

### Detection Prompt (notification, PRD FR-12)

- Body names the application: "Slack is using your microphone. Record this meeting?"
- Actions: **Record** (primary) · **Not now** · **Never for Slack**.
- The third action is what keeps the feature from becoming a nag, and it must be on the notification itself rather than only in Settings (PRD FR-15).
- Ignoring it is a decline. It expires on the system's own schedule and starts nothing (PRD FR-12).
- One prompt per detected meeting. A declined meeting is not re-prompted while the same input session continues.

## State Patterns

### Session state machine

`Idle → Recording → Transcribing → Idle`, with two branches off Recording.

| State | Menu bar icon | Menu | Window banner |
|---|---|---|---|
| **Idle** | `waveform`, template tint, no animation | `Start Recording` | none |
| **Recording** | `record.circle.fill` @ `{colors.state-recording}` | elapsed time, stream status, `Stop Recording` | recording variant with elapsed time |
| **Recording (degraded)** | same as Recording | `Mic only ⚠` on the stream line | degraded variant: "Recording your microphone only — system audio isn't being captured." |
| **Transcribing** | `ellipsis.circle` @ `{colors.state-transcribing}` | which Meeting, `Start Recording` available | transcribing variant with progress |
| **Transcription failed** | back to Idle | Idle menu | failure surfaces in Meetings, not the menu bar |

Transitions must be honest about timing: the icon turns Recording only when audio is **actually being captured**, not when the click happens (PRD FR-3). If tap creation takes a moment, the icon waits.

### Degradation, never silence

Three degradations, each of which must be visible (PRD NFR-5, FR-7):

1. **System audio unavailable** → record Mic-only, say so in the menu, in the window banner, and in the Note's frontmatter.
2. **Diarization unavailable or failed** → the whole System Stream becomes one `Speaker` label rather than failing the Meeting (PRD FR-22). The Note records it.
3. **LLM Backend unavailable** → the Heuristic Backend runs. The Note names the backend that ran (PRD FR-30). This is **not** surfaced as a warning — it is the expected path on this machine, and treating it as an error would be dishonest.

### Empty, loading, error

- **Meetings, empty:** one line of text and nothing else — "No meetings yet. Click the menu bar icon to record one." No illustration, no mascot.
- **Loading:** panes render their structure immediately with content filling in. No full-pane spinners; the window must never appear to hang.
- **Errors:** stated in place, in the pane that owns the thing that failed, with the next action as a button. Never a modal alert for anything the user did not just initiate.
- **A destructive action confirms and enumerates.** Deleting a Meeting names exactly what is removed — Note file, audio, or both — before removing it (PRD FR-40).

## Interaction Primitives

- **Menu bar click** — opens the menu. Left-click only; no distinct right-click menu, because two menus on one icon is a discoverability trap.
- **Single-click** activates in lists; no double-click-to-open. Selection and activation are the same gesture in a list this shallow.
- **Return** commits an inline edit; **Escape** cancels it and restores the prior value.
- **No drag and drop** anywhere. No custom gestures. No hover-only affordances — anything actionable is visible without hovering.
- **Global hotkey:** none in v1. It is a real convenience but it is a new permission surface and a conflict-resolution UI, and PRD §5 keeps the surface small. Logged as a v2 candidate.
- **Window behaviour:** closing the window does not quit the app (it is menu-bar-resident). Reopening restores the last sidebar selection. Only one window ever exists (PRD FR-5).
- **Notification actions** perform without bringing the app forward. Clicking `Record` starts the Session and does not steal focus from the meeting the user is in — this matters, because the user is mid-conversation.

## Accessibility Floor

Behavioural; visual contrast is `DESIGN.md`'s.

- **Colour is never the only signal.** The three Session states differ in silhouette as well as tint (PRD FR-2, NFR-7). The stream-status line spells out "Mic only" rather than relying on the warning tint.
- **Full keyboard navigation.** Every pane is reachable and operable by keyboard: sidebar via arrow keys, panes via Tab, buttons via Space/Return. Focus order follows visual order. No control is mouse-only.
- **VoiceOver labels that state meaning, not appearance.** The menu bar item announces "Minutes, recording, 12 minutes 4 seconds" — not "red icon". Checklist rows announce title, done-or-outstanding, and the subtitle. `{components.pill-done}` is announced as status, not as a button.
- **Live regions for state changes.** Session start/stop and transcription completion are announced.
- **Text scales.** All type uses macOS text styles (`DESIGN.md § Typography`), so accessibility text sizes work. Panes must remain usable at the largest setting — which means no fixed-height rows containing text.
- **Increase Contrast and Reduce Transparency are honoured** by using system materials rather than custom translucency.
- **Reduce Motion:** there is almost no motion to reduce. Progress indicators remain, state transitions do not animate.
- **No timed interactions.** The Detection Prompt expires on the system's schedule, and letting it expire is a safe default (decline). Nothing else is time-limited.

## Permission Choreography

*Invented section. This product's UX is dominated by two macOS permissions with wildly different ergonomics, and getting the sequence wrong is the difference between a working app and a silently broken one (PRD §12).*

Three principles:

1. **Ask at the moment of need, with the reason.** Microphone permission is requested during Getting Started because the app is useless without it. System-audio permission cannot be requested at all — it is triggered by the first capture attempt — so the product must *forecast* it: Getting Started states, before any recording happens, that macOS will ask on the first recording and what declining costs.
2. **Never claim certainty the platform does not offer.** Microphone state is queryable and is stated as fact. System-audio state is **inferred from whether the last capture produced non-silent audio** and must always be phrased as observation: "Last recording captured system audio." The Test Playground exists to generate that observation on demand.
3. **Make re-granting discoverable, because it will happen.** The app is ad-hoc signed, so consent is invalidated whenever the binary changes (PRD §12). This is the single most likely cause of "it stopped working". Therefore:
   - The System audio checklist row flips back to outstanding as soon as a capture yields silence.
   - Its outstanding subtitle names the real cause in plain words: "macOS revokes this when Minutes is rebuilt."
   - The Detection pane and the row both offer a copyable reset command and a link to the relevant System Settings pane (PRD FR-42).

**First-recording sequence** — the one moment the two permissions collide:

1. User starts a Session (menu, or accepting a Prompt).
2. Mic capture begins immediately. Icon → Recording.
3. System tap creation fires the macOS system-audio prompt. **The Session is already recording** — the user is mid-meeting and must not be blocked by a dialog.
4. If granted, the System Stream joins. If declined or ignored, the Session continues Mic-only and the degraded banner appears.
5. Either way, the Session completes and produces a Note. The Note records which Streams were captured.

Never block the start of a recording on a permission dialog. A meeting is happening; capturing half of it beats capturing none.

## Key Flows

### KF-1. Niklas is offered a huddle he would have forgotten to record *(PRD UJ-1)*

1. **Entry:** Minutes Idle in the menu bar; Niklas at his desk. He joins a Slack huddle.
2. Within ~15 s of Slack taking the microphone, a notification: *"Slack is using your microphone. Record this meeting?"* — `Record` · `Not now` · `Never for Slack`.
3. He clicks `Record`. Focus stays in Slack. Icon → Recording red within 2 s.
4. He talks for 22 minutes and does not think about Minutes again.
5. Slack releases the mic. Within 30 s the Session stops on its own. Icon → Transcribing amber.
6. **Climax:** a notification names the finished meeting — *"'Pricing page copy' saved — 22 min, 3 speakers"* — and the file is in his notes folder, titled, tagged and speaker-attributed. He did one click for the whole artifact.
7. **Resolution:** icon back to Idle. **Edge case:** ignoring the notification records nothing; silence is a decline, never a default yes.

### KF-2. Niklas records something Minutes cannot detect *(PRD UJ-2)*

1. **Entry:** a call on a surface with no Watched App.
2. Menu bar → `Start Recording`. Icon → Recording.
3. Mid-call he switches to AirPods; recording continues, gap under 2 s (PRD FR-8).
4. Menu bar → `Stop Recording`. **Climax:** icon → Transcribing, then Idle, and the Note lands.
5. **Edge case:** a manually started Session is *never* auto-stopped, even if a Watched App releases the mic meanwhile (PRD FR-14).

### KF-3. Niklas names a colleague, once *(PRD UJ-3)*

1. **Entry:** Meetings pane, a completed meeting with `Me`, `Speaker 1`, `Speaker 2`.
2. He opens it, reads the first line attributed to `Speaker 2`, recognises the phrasing.
3. He clicks the `Speaker 2` chip in the detail header and types `Mikkel`, Return.
4. **Climax:** every `Speaker 2` line becomes `Mikkel`, the Note rewrites in place, and a Speaker Profile is stored.
5. **Resolution:** next week's standup arrives with that voice already labelled `~Mikkel` — the prefix marking it inferred, so a wrong match is visible.
6. **Edge case:** one person split across two labels is fixed by renaming both to `Mikkel`, which merges them (PRD FR-24).

### KF-4. Niklas sets it up once *(PRD UJ-4)*

1. **Entry:** first launch. Icon appears; the window opens on **Getting Started**.
2. Quick Setup shows five rows, four outstanding. Each says in one line why it exists.
3. `Grant Access` on Microphone → system prompt → row flips to `Done` and recedes.
4. `Choose Folder…` → picker → row satisfied.
5. `Choose Model →` navigates to Transcription. He takes the recommended default; it downloads with determinate progress and a byte count. Row satisfied.
6. Row 3 (System audio) is still outstanding and marked not-required, its subtitle explaining that macOS will ask on first recording and that declining means his side only.
7. **Climax:** he clicks `Run Test →`. The pane tells him to play something. Two level meters move. Five seconds later: the transcribed words, `Mic ✓ System ✓`, the model name, and *"2.1 s for 5 s of audio — roughly 6 min for a 30-min meeting."* He now knows it works, on his machine, with numbers.
8. **Resolution:** all rows satisfied, "Setup complete." He closes the window and does not open it for weeks.
9. **Edge case:** if the System meter stays flat, the result says `System ✗` with the reason and the reset command — the failure is diagnosed, not merely reported.

### KF-5. A transcription fails and nothing is lost *(PRD FR-19, FR-39)*

1. **Entry:** a Session stops; transcription fails (interrupted model download).
2. Icon returns to Idle. No modal — the user did not initiate this moment.
3. The Meetings row shows `Failed` with a reason and a `Retry` action.
4. **Climax:** he re-downloads the model in Transcription, hits `Retry`, and the Meeting transcribes from retained audio. Nothing was re-recorded.
5. **Edge case:** if audio retention was set to delete-after-Note, `Retry` is absent and the row says why (PRD FR-44).

## Open Questions

1. **Level-meter feasibility for the System Stream before permission is granted** — if a denied tap yields no callbacks at all, the meter cannot distinguish "denied" from "silent". KF-4 step 9 depends on telling those apart; the Playground copy may need to say "no system audio detected — either permission was declined or nothing was playing."
2. **Notification action reliability while another app is fullscreen** — Slack huddles are often fullscreen; if actionable notifications are suppressed in Do Not Disturb or fullscreen, KF-1 breaks and the menu bar becomes the only path. Needs a real test.
3. **Whether "Never for Slack" belongs on the notification** — it is the right place for it, but a mis-click is destructive to the feature's value. Possibly needs an undo affordance in Detection.
4. **Speaker chip inline rename in the detail header** assumes few enough speakers to fit. Behaviour above ~6 speakers is unspecified.

## Assumptions

- `[ASSUMPTION]` Default sidebar destination switches from Getting Started to Meetings after setup completes. Not specified in the PRD; inferred from what a returning user wants.
- `[ASSUMPTION]` The Test Playground capture is 5 seconds. Long enough to speak a sentence, short enough not to feel like a chore. Not specified.
- `[ASSUMPTION]` No global hotkey in v1. A real convenience deliberately deferred to keep the surface small (PRD SM-C2); logged as v2.
- `[ASSUMPTION]` Left-click only on the menu bar item, no right-click menu.
- `[ASSUMPTION]` The transcription-time extrapolation in the Playground is a linear scale from the 5-second sample. Crude, but honest if labelled "roughly", and far better than a static claim.
- `[ASSUMPTION]` Notifications, not an in-app HUD, for meeting-ready announcements. Consistent with a menu-bar-resident app that should not steal focus.
