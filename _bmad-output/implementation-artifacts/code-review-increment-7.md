---
title: Code review — increment 7, the Note is the user's file
date: 2026-09-03
epic: 14 (11 stories) + Story 13.5
state: implemented, self-reviewed, 242 tests passing
---

# Code review: increment 7

Reviewed against `PLAN-increment-7.md`, the spine (AD-39 … AD-43, AD-9 and AD-18
as amended) and PRD §4.12. What follows is the honest account: what the plan got
wrong, what the tests caught, and what is still unproven.

## Two design errors the tests caught, and what they were

### 1. Ownership was decided from the record, not from the file — CRITICAL

`NoteWriter` asked `meeting.noteIsUserNamed` to decide whether it might rename the
file. That reads the *record*, which only knows what the last reconciliation
stored. The writer, meanwhile, had just been handed a destination resolved from
the folder this instant.

The consequence, from a test that failed on the first run: resolve to the user's
renamed file, write to it — and the app renamed it straight back to its own
derived name. **The exact defect the story exists to prevent, reintroduced by the
fix for it**, and only visible because the test asserted the folder contents
rather than the return value.

The rule now takes the name as an argument (`Meeting.appOwnsNoteName(_:)`), so the
caller with the more current information supplies it. A rule whose outcome depends
on whether a reload has happened yet is not a rule.

### 2. The record's path was hardcoded, which made the migration branch untestable

AD-41's pre-digest signal compares the Note's modification time with the record's.
The first implementation derived the record's path from the default Application
Support location — so under a temp-rooted store the file was not found, the check
concluded "no evidence of an edit", and a test would have **passed while proving
nothing.**

It is an injected closure now (`NoteWriter.recordModifiedAt`). Both branches are
tested, including the later-mtime one that never fires in the happy path — which
is the branch that ships broken otherwise.

### 3. The reported state and the writer's state disagreed for legacy records — CRITICAL, found live

Found by installing the build and running `--doctor` against the real library
after renaming a note by hand. The doctor said **"named by you: 1"**. The writer,
asked the same question, would have said the name was its own and renamed the
file back.

Two causes, and both are the same mistake in different clothes:

- **A record from before increment 7 has no `noteFilenameWritten`,** so nothing
  could tell whose name the file carried. `NoteLinkService` treated "unknown" as
  the user's; `Meeting.appOwnsNoteName` treated it as the app's. Fixed by
  backfilling the written name at the two moments the answer is knowable — a
  healthy link means the recorded name is the app's, and a relink means the name
  being *replaced* is the app's.
- **The state was read back off a stale in-memory copy** after `persist` had
  written to the store. Fixed by computing it before the write, from the copy in
  hand.

This is the third time in this increment that a rule read the record when it
should have read what was in front of it. Worth stating as a pattern rather than
three separate fixes: **where a value has just changed, the caller holding the new
value owns the answer** — and a test that asserts a returned state rather than the
filesystem will not catch the difference.

Pinned by `LegacyNoteNameMigrationTests`, both branches.

## What the tests pin, and why each one exists

59 new tests. The ones that carry weight:

| Test | The rule it stops from being reverted |
| --- | --- |
| `testALibraryWithNoBrokenLinkReadsNothing` | **Zero folder reads when nothing is broken.** A counting fake asserts `locate` was called 0 times. This is the whole answer to PRD §13 Q12, and increment 6's lesson was that a rule stated only in a comment gets reverted with every test green. |
| `testRewritingAfterAFinderRenameDoesNotCreateASecondNote` | The F1 regression, red before the fix. Asserts the folder holds one note, under the user's name. |
| `testAHandEditedNoteIsNotOverwritten` | F7. The user's paragraph survives. |
| `testAnOldShapedRecordDoesNotReadAsEdited` | The trap: comparing against a fresh render instead of a digest would report every old note as edited, because the renderer changed in four increments. |
| `testResolvingChangesNothingOnDisk` | AD-39's inertness — every name, size and mtime either side of a resolution. |
| `testAMarkdownFileMinutesDidNotWriteIsInvisible` | AD-43. The user's own documents are not the app's to enumerate. |
| `testAbsenceAndAmbiguityPersistNothing` | A transient filesystem condition cannot become a claim in `meeting.json`. |
| `UnlinkAllowlistTests` | AD-42 is one tidy-up away from being undone. Every `removeItem` in `Sources/` is enumerated with its reason; a new one fails. Two of the seven are **required** to unlink rather than trash — trashing an enrolment sample would keep the recording AD-32 exists to destroy. |
| `testTheTypeCannotCarryContent` | AD-9's identity/content line, by reflection over `NoteIdentity`'s fields. Fails if someone adds a content field. |
| `testRevealAndOpenAreAbsentWhenNoFileWasFound` | The reported "file not found", as a value rather than a rendered menu. |

The allowlist test has a second half that is easy to miss the point of:
`testTheAllowlistHasNoStaleEntries` fails if an allowlist entry no longer has such
a call. Without it the list rots into cover for a real regression.

## Measured on real data

`MINUTES_REAL_NOTES=1 swift test --filter NoteIdentityRealNotesTests`, read-only:

| Measurement | Figure |
| --- | --- |
| Notes the app wrote, all identifiable with no `minutes_id` yet | **16 of 16** |
| Files the user wrote by hand, correctly ignored | **2** |
| Meetings whose Note the locator finds | **15 of 15** |
| Ambiguities in the real folder | **0** |
| Closest two meeting start times | **77 s** — the `started_at` fallback holds with margin |
| Notes modified after their record | **0**, so all adopt their digest baseline cleanly |
| Unclaimed notes found | **1** — the file whose meeting was deleted, which no surface mentioned before |

## What the rendered shots found

`./Scripts/uishot.sh`, 37 images. One real defect, in a component that has shipped
since increment 2:

**`StateBanner` truncated its sentence instead of wrapping.** At 320pt the
note-not-found copy rendered as *"Minutes looked in your notes folder and cou…"* —
a banner whose entire purpose is a sentence, cut off mid-word. Fixed with
`fixedSize(horizontal: false, vertical: true)`. It would have shipped: no test
looks at a banner's layout, and the default window is wide enough to hide it.

A second, smaller one: the user's filename truncated at the tail, eating the
`.md`. Middle truncation now, matching the ambiguity list.

## Not proven, and needing a human

1. ~~**No note has been renamed in Finder while the built app was running.**~~
   **Done, and it found a defect.** The build was installed and `--doctor` was
   extended to report Note-link state, so the live mechanism is observable from a
   terminal. Against the real library, with one note renamed by hand:

   | | before the rename | after |
   | --- | --- | --- |
   | linked | 15 | **15** |
   | not found | 0 | **0** |
   | named by you | 0 | **1** |

   The record ends up holding both names — the user's on disk, the app's as the
   thing divergence is measured against — and the note's bytes are unchanged
   (verified by sha256 either side). The file and the record were then restored to
   their original state. This run is what surfaced review finding 3 above.
2. **`Locate note…` has never opened.** `NSOpenPanel` needs a window server;
   `NotePicker` exists precisely so the decisions around it are testable while the
   panel itself is not. The three confirmation branches are unrun.
3. **The Trash has never been used from the running app.** `MeetingStore.delete`
   is tested and returns the resulting URL, but nobody has deleted a meeting in
   the UI and dragged it back.
4. **The conflict banner has never been seen in the app** — only rendered.

## Deliberately not done

- **The FSEvents watcher.** PRD §13 Q23. A rename is noticed on the next reload,
  so the state is correct and briefly stale. AD-39 owns the correctness; a watcher
  would own only the latency.
- **Adopting a filename as a title.** FR-80 records the reason rather than leaving
  it looking like an oversight.
- **Anything about the sample-rate defect** the user documented in their notes
  folder. It is more serious than this increment and it is untouched. See the
  investigation's closing section, including the admission that AD-36's capture
  evidence should have caught it and does not.

## One thing I would flag to a reviewer

`SessionCoordinator.replaceNoteWithFreshRender` takes the destructive branch by
*adopting the file's current bytes and then rewriting* — two deliberate calls
rather than a `force` flag on `NoteWriting.write`. That is a judgement: a flag
would be shorter and would also put a documented way to bypass AD-41 into the
port, where a later caller could reach it by accident. If a reviewer disagrees,
the argument is in the method's comment rather than only in this file.
