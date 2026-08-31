---
title: "Addendum: Minutes PRD — depth for downstream"
status: final
created: 2026-08-31
updated: 2026-08-31
consumers: [bmad-ux, bmad-architecture, bmad-create-epics-and-stories]
---

# Addendum: depth for downstream

## 1. Technical context lives upstream

The verified platform research is **not duplicated here**. Architecture must read:

`_bmad-output/planning-artifacts/briefs/brief-meeting-recorder-2026-08-31/addendum.md`

It carries: host facts; the argmax-oss-swift decision with the verified `v1.1.0` tag; the full CoreAudio process-tap call sequence; the seven silent-failure traps; the Detection API reliability caveats; permission/TCC/signing mechanics; and the FoundationModels availability finding. All of it was verified on 2026-08-31 against the target machine or primary sources.

## 2. UI reference: FluidVoice (user-supplied, mid-run)

The user supplied a FluidVoice screenshot mid-run with: *"I like the way fluid voice sets up the models. Do something similar."* This is a **directive, not an inference** — UX and implementation should treat it as a requirement source. What was observed and what was taken from it:

| Observed in reference | Adopted? | Where |
|---|---|---|
| Single window, grouped sidebar (`Configure` / `Use` / `Activity` / `Help`) with section headings over a flat list | Yes — groups renamed to fit this product | §10.2 |
| "Quick Setup" card: ordered rows, each with state icon, title, one-line explanation, right-aligned control | Yes — the core of the directive | FR-46, §10.3 |
| Satisfied rows show a dim non-interactive "Done" pill and recede visually; outstanding rows show an ordinal and a live action button | Yes, verbatim as a pattern | §10.3 |
| Optional step marked "(Optional)" in its title, never rendered as an error | Yes | FR-46 |
| "Run Onboarding Again" affordance | Yes | FR-48 (Tier 3) |
| "Test Playground" card — record, see transcription, prove the setup | Yes, and **extended** | FR-47 |
| Single accent colour for the primary action, system greys elsewhere | Yes | §10.4 |
| Cards on a recessed background, headings outside the card | Yes | §10.4 |
| Top-right stats chip ("Today"), theme toggle, bug/feedback icon | **No** | §10.5 |
| `History`, `Stats`, `Change logs`, `Feedback` sidebar items | **No** | §10.5 |
| `Command Mode`, `File Transcription`, `Custom Dictionary`, word-boost | **No** — different product (dictation, not meetings) | §5 Non-Goals |

**Where this product must diverge, and why.** FluidVoice is a dictation tool: its playground shows transcribed text because text-into-app *is* the product. Minutes has a harder problem the reference does not — macOS exposes **no API to query system-audio-capture permission** (§12). So FR-47 extends the playground beyond "show the text": it must report **per-Stream audio presence** (did the mic produce sound? did the system tap produce sound?) and **measured transcription time**. That turns the reference's confidence-building demo into this product's only reliable permission diagnostic, and simultaneously answers §13 Q1 (real throughput on this machine) as a side effect of ordinary use.

## 3. Rejected alternatives

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| System audio capture | CoreAudio process taps | ScreenCaptureKit | SCK requires Screen Recording permission and shows the capture indicator, for an audio-only job |
| System audio capture | CoreAudio process taps | Virtual audio device (BlackHole etc.) | Requires a kernel/driver install and reroutes the user's real audio; unacceptable for a small tool |
| Transcription | WhisperKit (CoreML/ANE) | whisper.cpp | C API needing a Swift wrapper, no bundled diarization, weaker ANE use |
| Diarization | SpeakerKit (same package) | pyannote via Python | Would drag a Python runtime into a menu bar app |
| Diarization | SpeakerKit (same package) | Hand-rolled embedding + clustering | Weeks of work to underperform pyannote v4 |
| Speaker attribution | Dual-stream, structural for the Local Speaker | Diarize one mixed stream | Makes "who is the user" a prediction instead of a fact; strictly worse and no simpler |
| Metadata | FoundationModels **+** deterministic fallback | FoundationModels only | Apple Intelligence is off on the target machine — an FM-only build cannot title a meeting there |
| Metadata | FoundationModels **+** deterministic fallback | Bundled llama.cpp + small GGUF | Another ~1 GB download and a second inference stack for a job the heuristic does adequately |
| Output | Markdown files on disk | SQLite index / app-owned store | NFR-8: Notes must stay useful after the app is deleted |
| Windows | One window, sidebar | Separate Settings and Library windows | Directive in §2 collapsed these; fewer surfaces, same content |
| Detection signal | Per-process input activity | `kAudioDevicePropertyDeviceIsRunningSomewhere` | Always reports inactive for Bluetooth mics; AirPods are the common case |
| Detection signal | Poll **and** listen | Listeners only | `kAudioProcessPropertyIsRunningInput` listeners are documented as not always firing |

## 4. Deferred with rationale

- **FR-25 Speaker Profiles → first cut candidate.** Depends on voice-embedding similarity holding across separate recordings (§13 Q4). Degrades to per-Meeting manual renaming, which is still useful.
- **Live transcription → v2.** Batch is simpler and captures ~95% of the value. Designing v1 around streaming would compromise the reliable path.
- **Voiceprint enrolment → v2.** FR-25 learns passively from renames instead of asking the user to record samples.
- **Chrome as a Watched App → revisit.** Installed on the target machine, so browser calls are plausibly common. Cheap to add once Detection is proven for Slack and Teams. Deliberately excluded from v1 because the user named only Slack and Teams.
- **Crash-recovery UI → v2.** FR-9 requires the audio survive on disk; a polished recovery flow does not.

## 5. What the user has not seen

The user was away for this entire run. On return, the review surface in priority order:

1. **§14 Assumptions Index** — 17 entries. The largest interpretive leap is reading "the title, tags etc." as also meaning summary, decisions and action items (§4.6).
2. **§6.3 Build Order** — whether Tier 3 should simply be cut rather than deferred.
3. **§5 Non-Goals** — anything wrongly excluded, particularly Chrome and live transcription.
4. **§12 Platform, Permissions and Signing** — whether an Apple Developer certificate is obtainable, which would remove most of this section's pain.
5. **The product name** — "Minutes" was invented; it lives in one constant.
