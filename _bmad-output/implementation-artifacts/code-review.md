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
