---
title: Code review — Minutes
date: 2026-08-31
reviewer: adversarial self-review (headless run)
scope: Sources/Minutes (43 stories implemented)
verdict: 5 defects found and fixed; no known open defects
---

# Code review — Minutes

Reviewed with a bias toward the failure modes this product cannot tolerate: a
recording that silently produces nothing, a crash during the 2-second detection
poll, and data loss at stop. All five findings below were fixed and committed.

## Findings

### 1. Data race on `AVAudioFile` at stop — **high**

`StreamFileWriter.stop()` set `running = false` and then called `drainOnce()`
itself, while the drain thread could still be inside `drainOnce()`. Two threads
writing one `AVAudioFile` concurrently.

*Fix:* `stop()` now waits for the drain thread to finish (bounded, 3 s) before
touching the file, so it is the sole owner when it flushes.

*Why it mattered:* corrupt or truncated audio at the end of every recording,
intermittently — the worst class of bug for this product, because the user only
discovers it when the transcript is already wrong.

### 2. Tail of every recording truncated — **high**

`stop()` called `drainOnce()` exactly once, which drains at most
`8192 × channels` samples. Anything beyond that was discarded.

*Fix:* flush in a loop until the ring buffer is empty, with a no-progress guard.

### 3. Dictionary mutated while iterating its keys view — **high**

`DetectionService.poll()` did `for id in firstSeen.keys { firstSeen.removeValue(forKey: id) }`.
That is undefined behaviour in Swift and can crash. It ran every 2 seconds for
the life of the app.

*Fix:* snapshot the released keys with `filter` before mutating.

### 4. Whisper hallucinations reaching the Note — **medium**

A real verification run produced a phantom `Me: "Thank you."` from a microphone
nobody had spoken into. Whisper emits stock phrases with high confidence over
silence, and the effect here is worse than a wrong word: it **invents a
participant**, which undermines the product's central claim about attribution.

*Fix:* two filters — segments whose `noSpeechProb` is high and text short are
dropped, and segments whose *entire* text is a known hallucination phrase are
dropped. Matched whole-segment only, so real speech containing "thank you"
survives. Covered by regression tests.

### 5. Models downloaded into `~/Documents` — **medium**

WhisperKit defaults `downloadBase` to `~/Documents/huggingface/`. Two
consequences: 766 MB landed in the user's Documents folder, and
`ModelCatalog.isDownloaded()` was checking Application Support — so the setup
checklist's "Transcription model ready" row would have been **permanently
outstanding** even with the model present.

*Fix:* set `downloadBase` explicitly for both WhisperKit and SpeakerKit, and
migrate any existing download rather than re-fetching 600 MB. The path is now
ours, so the checklist is correct by construction rather than by matching a
library implementation detail.

*Note:* this is exactly the class of bug the Test Playground was designed to
surface, and it was found by running the real thing rather than by reading code.

### 6. Invalid comparator — **low**

`ModelCatalog`'s sort returned `true` when both elements were the default model,
which is not a strict weak ordering.

*Fix:* rewritten as a proper ordering.

## Verified by execution, not inspection

- **Full pipeline** end to end inside the signed bundle: dual-stream capture →
  transcription → diarization → attribution → metadata → Markdown note.
- **Both streams captured**, with non-zero system-audio levels (peak 0.36).
- **Diarization correct on all six lines** of a scripted two-voice meeting, twice,
  with two different models.
- **Decision and action-item extraction** with correct first-person owner
  attribution and timestamps.
- **33 unit tests** over the deterministic core.
- **Model migration** verified: 766 MB relocated, Documents left clean.

## Not verified — needs a human at the machine

These are implemented and compile, but cannot be exercised autonomously:

1. **Detection against a real Slack huddle or Teams call.** The CoreAudio
   enumeration and prefix matching are verified; `IsRunningInput` flipping during
   an actual call is not. This is PRD open question 8 and the largest remaining
   unknown.
2. **Visual correctness of every pane**, including the menu bar icon states.
3. **Output-device change mid-recording** (AirPods connecting).
4. **A 3-hour session.**
5. **FoundationModels backend** — Apple Intelligence is off on this machine, so
   the LLM path returns unavailable by design and the heuristic backend runs.
6. **Speaker Profiles across meetings** — the centroid primitive is wired and the
   maths is unit-tested, but the 0.45 threshold is uncalibrated against real
   voices. Deliberately conservative: a wrong automatic name is worse than an
   anonymous one.

---

# Code Review — Epic 8 (increment 2)

**Date:** 2026-08-31 · **Scope:** FR-49 to FR-54 and the FR-40 amendment · **Stories:** 8.1-8.6

Reviewed inline against the six stories' acceptance criteria and constraints. 67 tests pass (15 new). Findings below are the ones that survived checking; each was fixed before commit unless marked otherwise.

## Findings

**1. Sticky destructive option — fixed.**
`deleteNoteToo` moved from per-invocation state to a toolbar checkbox, so it persisted across selections. A user who ticked "also delete notes" once would have it silently applied to every later deletion. The confirmation always states the consequence, so this was not silent *at the moment of deletion* — but it widened a destructive default without the user revisiting it. Now reset after each confirmed delete.

**2. `Reveal note` on a file that does not exist — fixed as part of 8.1.**
The detail pane offered "Reveal note" whenever `noteFilename` was set, which for the five meetings with absent notes would have opened an empty Finder window. Split into "Reveal note" and "Rewrite note" on the FR-53 condition.

**3. Right-click delete outside the selection — handled.**
With multi-select, right-clicking an unselected row and choosing Delete is ambiguous: does it act on the row or the selection? It now replaces the selection with that row, matching Finder. Worth restating because the alternative — deleting a multi-row selection the user cannot see from the row they clicked — is the dangerous reading.

## Verified against real state

The two defects that motivated stories 8.1 and 8.2 are reproduced and now visible rather than silent:

```
notes on disk: 3
meetings whose note is absent: 5
    20260831-115827-wbbx -> 2026-08-31 1158 Meeting-31-August-11-58.md
    20260831-133820-00gq -> 2026-08-31 1338 Pricing-Page.md
    20260831-134017-anb2 -> 2026-08-31 1340 Pricing-Page.md
    20260831-134640-669r -> 2026-08-31 1346 Pricing-Page.md
    20260831-135902-7fen -> 2026-08-31 1359 Page-Redesigned-Together.md
```

Those five now render as **Note missing** with a **Rewrite note** action, instead of claiming to be complete. `--doctor` reports 8 readable, 0 unreadable.

Also observed during the run: the interrupted 15:29 recording resumed on launch and completed to `2026-08-31 1529 Forever-And-Ever.md`, exercising the resume path added just before this epic.

## Not verified — needs the user's eyes

**FR-49's menu bar text.** `MenuBarExtra`'s label is given an `HStack { Image; Text }`. This is the idiomatic construction and is widely used, but SwiftUI's menu bar label supports a restricted view set and I cannot see the menu bar from here. If the timer does not appear next to the icon while recording, the fallback is to composite the icon and the time into a single `NSImage`, resolving `NSColor.labelColor` against the current menu bar appearance on each redraw. Recorded as a known unknown rather than asserted as working.

**§13 Q10 — pulse cost over a long Session.** The 0.5s tick publishes `AppState`, re-rendering the label (and the menu, when open) at 2 Hz for the whole Session. Bounded and stoppable by construction, and unit-tested for shape, but not profiled over two hours. If it breaches NFR-3 the epic's own constraint applies: degrade to a discrete two-frame indicator.

## Requirements still resting on the same evidence as before

`FR-51` makes §13 Q4 (does voice matching hold up across recordings?) answerable by observation for the first time — the profile set is now inspectable, with sample counts. The 0.45 threshold remains uncalibrated; that has not changed.
