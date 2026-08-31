---
title: "Product Brief: Minutes — local-first meeting recorder for macOS"
status: draft
created: 2026-08-31
updated: 2026-08-31
owner: Niklas
mode: headless (-A)
---

# Product Brief: Minutes — local-first meeting recorder for macOS

> Working name, chosen for lack of a stated one: **Minutes** — meeting minutes, and the handful of them this costs you. Trivially renamable; it appears in one constant.

## Executive Summary

Meetings are where decisions get made and where they get lost. The tools that fix this — Granola, Otter, Fireflies, Teams' own recap — all solve it the same way: your voice and your colleagues' voices leave your machine, land on someone else's servers, and get processed there. For anyone working under a DPA, discussing unreleased product, or simply unwilling to post their working day to a vendor, that trade is a non-starter. So the meeting goes unrecorded and the notes get taken badly by hand, or not at all.

Minutes is a small macOS menu bar app that records a meeting, transcribes it, works out who said what, gives the result a title and tags, and writes one Markdown file to a folder you choose. Every model runs on the machine. There is no account, no server, no network call at run time. It is deliberately not a meeting-intelligence platform: no dashboards, no CRM sync, no team workspace. One icon in the menu bar, one folder of Markdown files, and a small settings window for choosing how good the transcription should be.

Two choices keep it from being a toy. It knows a meeting has started — when Slack opens a huddle or Teams joins a call, a notification asks whether to record, so capturing a meeting costs a click instead of a memory. And it captures the microphone and the system output as two separate streams, so "you" is never confused with "them": the hardest part of speaker attribution is solved by construction rather than by a model guessing.

## The Problem

Niklas sits in back-to-back Slack huddles and Teams calls. What actually happens today:

- **Notes compete with participation.** Typing while listening means doing both at 70%. The person taking notes is the person contributing least.
- **The good stuff evaporates.** A decision made at minute 34 of a huddle exists only in the memory of whoever was paying attention. A week later there is disagreement about what was agreed.
- **The obvious fixes are blocked.** Cloud notetakers mean shipping colleague and customer audio to a third party. That is a procurement conversation, a DPA review, and often a "no" — and it is a bad instinct to normalise regardless.
- **Teams' own recap is not portable.** It lives inside Teams, covers only Teams, and produces something you cannot grep, diff, or drop into a notes repo.
- **Recording is a chore you forget.** Anything requiring "remember to hit record before you start talking" gets used for the first week and then not at all.

The cost is not dramatic, it is cumulative: re-litigated decisions, action items nobody owns, and a working week that leaves no searchable trace.

## The Solution

A menu bar icon with three states — idle, recording, transcribing — and this much surface area:

- **Click to start, click to stop.** The icon changes colour so recording status is never in doubt. Nothing else is required to capture a meeting.
- **It offers, you accept.** When a Slack huddle or Teams call starts, a notification asks "Record this?". One click. Decline and it stays quiet; decline repeatedly for an app and it learns to stop asking.
- **Transcription runs on-device.** Whisper via CoreML on the Neural Engine. A small settings window lists the model sizes with their honest trade-off — speed against accuracy, disk cost stated — and downloads the one chosen.
- **Speakers come out labelled.** The microphone stream is you, by definition. The system-audio stream is everyone else, split into `Speaker 1`, `Speaker 2` by on-device diarization, renameable after the fact — and once named, remembered for next time.
- **The output is one Markdown file.** YAML frontmatter carrying title, date, duration, participants, tags and model used; then a summary, decisions and action items if they can be found; then the timestamped, speaker-attributed transcript. Written to a folder of the user's choosing, so Obsidian, a notes repo, or plain Spotlight all work without integration.

Title and tags are derived on-device too — from Apple's Foundation Models when Apple Intelligence is switched on, and from a deterministic local extractor when it is not, so the feature never silently disappears.

## What Makes This Different

Honest version: none of these components are novel, and the moat is not technical.

- **The differentiator is the boundary.** Local-only is the entire product position. Every competitor is cloud-first because cloud-first is how you build a business on meeting data; that is exactly why this niche stays open for a tool with no business model.
- **The dual-stream trick is a real edge.** Competitors receive one mixed audio stream and must infer every speaker from it. Capturing mic and system output separately makes "who is the user" a fact rather than a prediction, and reduces diarization to the easier remaining problem. This is available because the app runs on the endpoint instead of joining as a bot.
- **Detection instead of discipline.** Watching which processes hold the audio device is a small, unglamorous mechanism that removes the main reason these tools go unused.
- **Small is a feature.** No account, no onboarding, no sync. It can stay useful for years because there is very little of it to rot.

What this is *not*: better transcription than a large cloud model, and not a substitute for a team-wide meeting platform. Whisper on-device is good, not state of the art, and a 2-hour meeting takes real minutes to process.

## Who This Serves

**Primary: Niklas, and people whose job looks like his.** Works in a Slack-and-Teams company, in enough meetings that notes are a real tax, technical enough to install an unsigned app and grant permissions, and constrained — by policy or preference — from using cloud notetakers. Success for them: at the end of the day there is a folder of Markdown files they did not have to think about, and they were fully present in the meetings.

**Secondary, not designed for:** consultants under client NDAs, and engineers who already keep a plain-text notes repo. They matter only as a check that the design is not over-fitted to one person.

**Explicitly not served:** teams wanting shared meeting archives, anyone on Intel Macs, anyone who needs a recording of a meeting they did not attend.

## Success Criteria

The tool has to earn a permanent place in the menu bar. Concretely, on the target machine:

| Signal | Target |
|---|---|
| Meetings recorded without deliberate effort | Detection prompt appears for ≥90% of Slack huddles and Teams calls, within 15s of the call starting |
| Attribution is trustworthy | "Me" vs "others" correct essentially always (structural); remote speaker segments correct often enough that renaming a handful of labels fixes a whole meeting |
| It does not get in the way | Idle CPU negligible; recording overhead small enough to be unnoticeable on a call; transcription of a 30-minute meeting completes in single-digit minutes with the default model |
| The output is actually used | Files are readable without editing and land somewhere already grepped — no manual clean-up pass before they are useful |
| It stays running | Survives sleep/wake, device changes (AirPods mid-call), and a full day in the menu bar without a restart |
| Nothing leaves the machine | Zero outbound connections after models are downloaded — verifiable, not asserted |

The honest overall test: three weeks after it is built, is it still enabled at login?

## Scope

**In, for v1:**
- Menu bar control with visible idle / recording / transcribing states
- Dual-stream capture: microphone + system audio via CoreAudio process taps
- On-device Whisper transcription with a model picker and in-app model download
- On-device speaker diarization of the remote stream; speaker renaming that persists
- Auto-detection of Slack huddles and Teams calls, with a notification prompt and per-app "stop asking"
- On-device title, tags and summary; Foundation Models when available, deterministic extractor otherwise
- One Markdown file per meeting with YAML frontmatter, to a user-chosen folder
- A small library view to find, open and rename past meetings
- Settings: model, output folder, detection toggles, audio retention

**Explicitly out, for v1:**
- Live/streaming transcription during the call (batch after the meeting ends)
- Any cloud service, account, sync or telemetry
- Real-name speaker identification from voice (no enrolled voiceprints — labels are manual)
- Zoom, Meet, Discord and browser-based calls as *named* detections — generic mic-in-use detection may cover them, they are not targets
- iOS, Intel Macs, Windows
- Calendar integration, CRM export, team sharing, PDF/DOCX export
- App Store distribution and notarization

**Known and accepted rough edges:** no Apple Developer certificate exists on this machine, so the app is ad-hoc signed and macOS will re-ask for audio permission whenever it is rebuilt. Apple Intelligence is currently off on this machine, so the LLM-quality titles will not appear until it is enabled — the fallback covers it meanwhile.

## Vision

If it works, the direction is inward rather than outward — more useful per meeting, not more meetings-per-team.

Nearest term: live transcription so the transcript exists as the meeting happens, and voiceprint enrolment so `Speaker 2` resolves to a colleague's actual name on its own. After that, the notes become a corpus: ask questions across every meeting you have had, entirely locally, and get an answer with citations back to timestamps. The end state is a personal, permanent record of your working conversations, searchable for years, that never required trusting anyone else with it.

Deliberately never: a team product, a subscription, or a service with a server.
