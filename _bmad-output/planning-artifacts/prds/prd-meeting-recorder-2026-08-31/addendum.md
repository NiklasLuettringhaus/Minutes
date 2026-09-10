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

---

## 6. Increment 2 — mechanism notes (for architecture, not the PRD)

Added 2026-08-31 alongside FR-49 to FR-54. The PRD states the capabilities; this is the technical-how the architecture spine will need, plus the evidence behind each one.

### 6.1 What the two reconciliation defects actually were

Both were found by the user, and both are the same class of mistake: a permissive read hiding a disagreement.

**Records silently dropped.** `Meeting` used Swift's synthesised `Codable`, carrying a comment asserting that property defaults would fill missing keys. They do not — a missing key throws `keyNotFound` regardless of the default. Adding one field (`multipleInRoom`) made every record written before it undecodable, and the store's listing used `try?`, so five Meetings disappeared from the UI while intact on disk. The lesson for FR-54's last consequence: **a listing must report what it cannot read.** The fix was an explicit decoder in which only identity is required.

**Notes claimed but absent.** Seven Meetings held `stage: written` and a `noteFilename` while two files existed in the Notes Folder. The writes had been discarded by a development sandbox; the pipeline recorded success because the write call returned. FR-53 exists because the record's claim and the filesystem are independent facts, and nothing was comparing them.

### 6.2 FR-53 — how the check should work

- Compare `noteFilename` against the Notes Folder *currently in effect*. Never resolve against a remembered path: a user who moves the folder has not broken their history.
- The check is a display state derived on read, not a field written back into the record. Writing "note missing" into `meeting.json` would make a transient condition permanent.
- Rewriting regenerates the Note from `meeting.json` through the existing writer. No re-transcription, no re-diarization, and no parsing of any surviving Note — AD-9 holds: the Note is a projection, and the record is the source of truth.
- Deliberately **not** automatic. A Note deleted on purpose must stay deleted, so rewriting is a user action on a visible broken row.

### 6.3 FR-54 — refresh scope

Refresh re-reads the store and the folder; it does not touch models, permissions or audio. The one subtlety is that it must not become the only path to correctness: state that only updates on an explicit refresh is state the user has to know to distrust. Treat the button as a repair tool for out-of-band changes (Finder deletions), with the normal in-app paths still updating themselves.

### 6.4 FR-49 / FR-50 — cost is the whole design constraint

`MenuBarExtra`'s label is re-rendered by the system, so both a per-second timer and a continuous pulse are recurring work in the one component NFR-3 singles out. Two consequences:

- The timer should be driven by a single coalesced tick, not by an animation-driven clock, and it must stop dead when Recording ends rather than idle at 1 Hz.
- The pulse should be expressed as a bounded, slow opacity or scale cycle. §13 Q10 exists because this was never measured over a long Session; if it costs more than NFR-3 allows, the pulse degrades to a discrete two-frame indicator, which still satisfies "animate slightly".

Neither may become the *carrier* of the Recording state — FR-2's silhouette-and-tint rule stands, so both remain confirmation for a state that is already legible without them (NFR-7, and greyscale menu bars).

### 6.5 FR-52 — what the setting is actually selecting

There is no model to configure, no key, and nothing to download; the choice is only *which of two local backends runs*, and one of them is unavailable on this machine. The pane's honest content on the target Mac is: Apple Intelligence is disabled, so titles, summaries, decisions and action items come from deterministic keyphrase extraction. Verified at runtime, not assumed:

```
SystemLanguageModel.default.availability
  = unavailable(appleIntelligenceNotEnabled)
```

That is why §9.3 applies here rather than §9.2: this is a truthfulness requirement, not a cost one. The risk to avoid is a settings pane whose mere existence implies a configurable LLM.

### 6.6 FR-51 — the data already exists

Speaker Profiles already persist a name, a centroid, a sample count and a last-updated date, and the directory already exposes lookup, remember, forget-one and forget-all. FR-51 is therefore almost entirely a surface: the capability was built and left unreachable behind a single destructive "Forget all". Worth noting as a pattern — the previous increment shipped three features (delete, retry, rename) whose only entry point was a context menu the user never found.

---

## Increment 9: rejected alternatives, with the measurements that rejected them

Kept here rather than in the PRD because each is a mechanism decision, and
because the next person to have these ideas deserves the numbers rather than a
flat "no".

### Acoustic echo cancellation — rejected

The obvious fix for §4.14's echo is to subtract the System Stream from the Mic
Stream. It cannot work on these recordings, and the reason is not filter length.

Upper bound on ERLE for **any** linear filter, from magnitude-squared coherence
(so it is independent of the filter), delay-compensated:

| analysis window | median bound | p90 |
|---|---|---|
| 128 ms | 8.7 dB | 11.3 dB |
| 512 ms | 9.9 dB | 14.8 dB |
| 2048 ms | 10.6 dB | 16.8 dB |

A least-squares FIR confirmed it empirically: 7.5 dB median at 512 taps, never
above 20 dB on any frame. A useful canceller needs 20–40 dB.

The Mic Stream is not a linear function of the System Stream here: the two are
captured on independent device clocks (so they drift against each other), the
speaker path is nonlinear, and the room's reverberation tail outlasts any window
tried. Detection survives all three — correlation only needs the relationship to
exist, not to be invertible — which is why FR-89 detects and FR-90 excludes.

*A note on how this number was obtained.* The first coherence run reported
1.6 dB, and on that basis "cancellation is impossible" was nearly written down
as a fact. That run had not compensated the 39 ms delay, and a 128 ms window
biases such a figure badly low. The corrected figure is ~10 dB. The conclusion
held; the number did not. A decisive-looking negative result is exactly the kind
that needs measuring twice.

### Canary-1B-v2 as the transcription engine — rejected

Reachable through the FluidAudio version already pinned, and the strongest model
available by reputation. Measured on AMI ES2004a against the current default:

| model | close mics | far-field | ×realtime |
|---|---|---|---|
| `parakeet-tdt-0.6b-v3` (current default) | 16.3% | 26.1% | 0.006 |
| `canary-1b-v2` | 24.8% | 35.3% | 0.132 |

8.5 points worse on close mics, 9.2 worse far-field, 22× the cost. It also
returns a bare `String` with no timings, so adopting it would have required a
segmentation stage to supply the timings Diarization and the Note depend on —
building that first and measuring afterwards is precisely the trap FR-93 exists
to prevent.

### Changing the default model — deferred, not rejected

Pooled over three sessions, the English-only Parakeet is **2.3 points better**
than the shipped default on close mics (20.3% vs 22.6% WER) and tied far-field.
That supports the catalogue's existing note and suggests the default is wrong.

It is not acted on because the per-session swing is larger than the effect:

| session | `parakeet-v3` | `parakeet-v2-en` |
|---|---|---|
| ES2004a | **16.3%** | 18.6% |
| IS1000a | 35.1% | **27.4%** |
| TS3003a | 15.7% | **14.5%** |

Three sessions cannot move a default that every user gets. The revisit condition
is explicit: nine or more sessions spanning native and non-native English, since
the hardest session (IS1000a) is AMI's non-native set and these meetings are not
held in first-language English either.

### Far-field level normalisation — deferred with a named blocker

Real, measured, and conditional (ES2004a, `parakeet-v3`):

| preprocessing | close mics | far-field |
|---|---|---|
| none | 16.3% | 26.1% |
| `loudnorm` to −16 LUFS | 18.4% (**+2.1**) | **24.0%** (−2.1) |
| `highpass 80 Hz` + `dynaudnorm` | 17.0% (**+0.6**) | **24.0%** (−2.0) |
| `dynaudnorm` | 17.5% (**+1.1**) | 24.7% (−1.4) |

It helps far-field by ~2 points and hurts close mics by ~1–2, so everything
rests on a gate — and the obvious gate does not work. Integrated loudness does
not separate the conditions: TS3003a's *close* mix is −43.8 LUFS, quieter than
IS1000a's *far-field* at −34.0, and the user's own library spreads from −18.7 to
−70.0 LUFS. A loudness-gated normaliser would misfire and cost 2 points when it
did. The blocker is the gate, and a gate keyed on reverberation rather than
level is a spike, not a task.

### Chunking long recordings — rejected as unnecessary

FluidVoice chunks at 20 minutes, citing a 24-minute model limit, and Minutes
does not chunk at all. Measured before copying: the longest real recording is
**57.3 minutes** and its Transcript's last Utterance lands at 57.3 minutes —
100% coverage, as do the 50.3 and 33.9 minute recordings. FluidAudio handles it
internally. A defect was nearly reported here that does not exist.
