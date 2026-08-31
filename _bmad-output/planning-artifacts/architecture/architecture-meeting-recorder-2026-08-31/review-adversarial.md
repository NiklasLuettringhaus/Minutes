# Reviewer: adversarial spine attack

Lens (from `finalize_reviewers`): *construct two units one level down that each obey every AD to the letter yet still build incompatibly.*

**Verdict: four real holes found, all closed with new ADs (AD-18…21).** The original 17 ADs covered the OS boundaries thoroughly — that is where the spikes forced precision — but were thin on **ownership of the Meeting record**, which is exactly where two independently-built stages diverge.

## Hole 1 — Two Notes for one Meeting *(closed by AD-18)*

**Attack.** `NoteWriter` derives `2026-08-31-1400-weekly-sync.md` from the title. Later the user renames the Meeting; `MeetingsPane` calls a regenerate path that derives `2026-08-31-1400-pricing-review.md`. Both obey AD-9 (the Note is a projection) and AD-10 (atomic writes). Result: two files, one Meeting, and FR-31's "no overwriting" rule satisfied while the user's folder is wrong.

**Why the spine allowed it.** AD-9 fixed ownership of *state* but said nothing about ownership of the *filename*. FR-35 says the behaviour must be "defined, not incidental" — the spine left it incidental.

## Hole 2 — Rename and merge are undefined *(closed by AD-19)*

**Attack.** Implementation A stores `Utterance.speaker: String` (the display name). Implementation B stores a label ID plus a name map. Both satisfy AD-11 and FR-23's "exactly one Speaker Label per Utterance". Under A, FR-24's merge — renaming two labels to the same name — is indistinguishable from two independent renames, and there is no way to undo the merge. Under A, a rename is also an O(n) rewrite of every Utterance, which collides with FR-24's "without re-running transcription".

**Why the spine allowed it.** AD-11 fixed *how attribution is decided* but not *how a label is represented*. That representation is precisely the shared-data shape two units can pick incompatibly.

## Hole 3 — Double or partial stage advancement *(closed by AD-20)*

**Attack.** The Diarize stage, on success, persists its output and sets `stage = .diarized`. The Pipeline, seeing a successful return, also sets `stage = .diarized` — harmless. But now the Metadata stage is written to set `stage = .metadata` *before* writing its output, and a crash between the two leaves a Meeting claiming a stage it never completed. Both obey AD-8's letter ("each stage writes its output and advances a single persisted stage field").

**Why the spine allowed it.** AD-8's phrasing let the *stage* do the advancing, making every stage author responsible for ordering a two-step commit correctly. Centralising it in the Pipeline removes the class of bug.

## Hole 4 — Field clobbering on the Meeting record *(closed by AD-21)*

**Attack.** Capture finishes and writes the record with `systemStreamCaptured: false`. Diarize finishes and writes the record it loaded *before* Capture's write, setting `diarizationFailed: false` and resetting `systemStreamCaptured` to its stale value. Metadata does the same with `backend`. Every write is atomic per AD-10 and every adapter obeys AD-7 (which governs `AppState`, not the Meeting record). The degradation flags AD-17 requires are silently lost — which is the single worst outcome for this product, because a Mic-only recording would be presented as a full one.

**Why the spine allowed it.** AD-7 named one owner for *application* state and the spine never named one for *persisted* state. This was the most serious of the four.

## Attacks that failed — the spine already holds

- **Two clocks.** AD-4 forces a single session clock and offsets-only below Meeting level; a second clock cannot be introduced without visibly violating it.
- **Adapter cross-talk.** The paradigm table plus the dependency diagram forbid adapter→adapter imports, so `WhisperKitTranscriber` cannot reach into `SystemTapCapture`.
- **Concurrent model loads.** AD-14's single serial executor is unambiguous.
- **Silent tap failure.** AD-1, AD-2 and AD-3 are specific enough that a compliant implementation cannot reach the deadlock or the zero-sample aggregate shapes.
- **LLM-only metadata.** AD-12 makes the deterministic backend the floor and the availability check mandatory.
- **Recording while Idle.** AD-6 states the invariant in terms a reviewer can check by inspection.
- **Losing audio on failure.** AD-8 plus AD-10 keep upstream work; a stage failure cannot discard it.
