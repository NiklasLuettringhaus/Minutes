---
title: Investigation — a renamed Note is a lost Note
date: 2026-09-03
intent: characterise a user-reported defect before planning a fix
subject: the link between a Meeting record and its Note file, and every action that depends on it
lens: architecture conformance + built-UI conformance, against the user's real notes folder
verdict: seven defects, one of them already destroyed a meeting; the identity mechanism is the root cause of five. Three were reproduced by running the real code, not deduced from it
---

# Investigation: a renamed Note is a lost Note

The user's words: *"When I delete a file in finder it says 'file not found' or
something. but does not give me the option to attach a file to it, or repoint it
to it. Also i actually did not delete it but just renamed it. The program now
thinks its deleted and does not surface the now renamed one in the UI."*

Every clause is a separate defect, and the last one has already cost a meeting.

## What happened, reconstructed from the disk

Measured at 10:23 on 2026-09-03, against the live Application Support directory
and the live `~/Documents/Minutes` folder. No file was modified.

**Meeting titles and note filenames in this document are substituted.** The
repository is public, and a meeting title is meeting content, which PRD §9.1 keeps
on this Mac. Every substitute preserves the property the evidence rests on — a
space inside the filename stem, which `NoteWriter.slug()` cannot produce — and
nothing else about the real names is recorded here or anywhere else in the
repository. The same convention applies to the epic, the spines and the plan.

| Measurement | Figure |
| --- | --- |
| Meeting records under Application Support | **14** |
| `.md` files in the Notes Folder | **15** |
| Records whose stored `noteFilename` is absent from the folder | **0** |
| Note files that no record claims | **1** |
| Notes modified after their record was last written (hand-edited) | **0** |

The one unclaimed file is `2026-09-03 0930 Morning -standup.md`. Its frontmatter
says:

```
title: "Actually"
started_at: 2026-09-03T07:30:38Z
duration: "13:21"
detected_from: "Slack"
```

Three facts follow from that, and together they are the whole story:

1. **The app gave this meeting a one-word auto-title** taken from something
   somebody said early on, which described nothing. The user renamed the *file* to
   what the meeting actually was.
2. **`NoteWriter` cannot have produced that filename.** `slug()` splits the title
   on spaces and rejoins with `-`, so a space can never survive into the stem.
   `Morning -standup` contains one. The rename happened in Finder, by hand.
3. **There is no Meeting record for `2026-09-03T07:30:38Z`.** The directory is
   gone, `~/.Trash` is empty, and `MeetingStore.delete` calls
   `FileManager.removeItem`, which does not use the Trash. **The recording and the
   stored transcript for that meeting are unrecoverable.** The Markdown survived
   only by accident — see F5.

So: the user renamed a note to something meaningful, the app declared the note
missing, offered one remedy that was the wrong one, never showed them the file
they had renamed, and then deleted the meeting permanently on a confirmation that
named a file it did not touch.

## The root cause

`Meeting.noteFilename` is a `String`, and it is the **only** link between a
Meeting and its Note. Nothing in the note file identifies the meeting it came
from — `started_at` is in the frontmatter, but no code has ever read it, because
AD-9 says the app never parses a Note back into state.

The consequence is that the link is a **name**, and a name is the one property of
a file the user is most likely to change. The app's model is *"this is my output,
filed where I put it"*; the user's model is *"this is my document, in my folder,
named what I want"*. The user's model is the correct one — it is their folder —
and the app has no mechanism that can survive it.

## Findings

### F1 — CRITICAL. "Rewrite note" on a renamed Note creates a duplicate and orphans the original

`NoteWriter.write` with a stored filename that is absent from disk:

- `filename = meeting.noteFilename` (the old name)
- the rename branch is skipped, because `existing == wanted` when the title has
  not changed
- `atomicWrite(data, to: dest)` **creates a new file at the old name**

Result: two files. The user's renamed file, carrying whatever they had done to it,
and a fresh app-written one. The record links to the fresh one, so the renamed
file becomes permanently invisible to the app — the state this investigation is
about, now reachable *by clicking the button the app offers as the fix.*

The remedy the app presents for a broken link is the one action that makes the
break permanent.

**Reproduced, not deduced.** Run against the real `NoteWriter` in a temporary
folder — write, rename the file as the user did, rewrite:

```
REPRO: app wrote      -> 2026-09-03 0930 Actually.md
REPRO: rewrite wrote  -> 2026-09-03 0930 Actually.md
REPRO: folder now holds 2 notes: ["2026-09-03 0930 Actually.md",
                                  "2026-09-03 0930 Morning -standup.md"]
```

### F2 — CRITICAL. "Reveal in Finder" and "Open in Editor" are offered for a file that is not there

`MeetingsPane.rowContent`, the row context menu:

```swift
if let f = m.noteFilename, let folder = prefs.notesFolder() {
    Button("Reveal in Finder") { … }
    Button("Open in Editor")  { NSWorkspace.shared.open(folder.appendingPathComponent(f)) }
}
```

The condition is *a filename is recorded*, not *a file exists*. `NSWorkspace.open`
on an absent path produces the system's own alert, which is the **"file not
found"** the user reported. The detail pane already splits these two cases — and
has a comment saying why: *"offering 'Reveal note' for a file that is not there
sends the user to an empty Finder window."* The context menu never got the fix.

Two surfaces, one rule, one of them applying it.

### F3 — HIGH, and the user asked for it in as many words. There is no way to re-point a Meeting at a file

> *"does not give me the option to attach a file to it, or repoint it to it"*

Correct: there is no such action anywhere in the app. `noteFilename` is written
only by the pipeline and by `NoteWriter`. Nothing else can set it, so a link that
breaks can only be replaced by a new write (F1) — never repaired.

### F4 — HIGH. A note the app no longer claims exists nowhere in the UI

There is no surface that lists the Notes Folder. `missingNoteIDs` walks the
*records* and asks the filesystem about each one; nothing ever walks the *folder*
and asks the records about each file. So a file the app wrote and then lost track
of is invisible, which is exactly what the user observed and exactly what has
happened to the 09:30 meeting.

### F5 — HIGH. "Also delete notes" names a file it will not delete

`SessionCoordinator.delete(meetingIDs:alsoNote:)` builds the note URL from the
stored filename and passes it to `try? fm.removeItem`. On a broken link that path
does not exist and the `try?` swallows it. Meanwhile the confirmation dialog has
already said:

> "The recording, the transcript and **2026-09-03 0930 Actually.md** will be
> permanently deleted."

naming a file that is not there, and not naming the one that is. EXPERIENCE.md's
rule — *"A destructive action confirms and enumerates. Deleting a Meeting names
exactly what is removed"* — is violated whenever the link is broken.

**Reproduced** by running the same path the coordinator takes:

```
REPRO: dialog would name '2026-09-03 0930 Actually.md';
       files left after delete: ["2026-09-03 0930 Morning -standup.md"]
```

The failure direction was lucky this time: the user's renamed file survived
*because* the delete could not find it. Reverse the case — a user who renames
note A to the name the app holds for meeting B — and the same code deletes the
wrong file.

### F6 — HIGH. Deletion is unrecoverable, and has already taken a meeting

`try fm.removeItem(at: directory(for: id))`. No Trash, no undo, no confirmation
beyond the one dialog. `~/.Trash` is empty, so the 09:30 recording is gone. One
call to `trashItem(at:resultingItemURL:)` would have made it a drag back out of
the Trash.

Worth stating plainly because the whole product is built on *not losing things*:
this is the only place in the app where a user gesture destroys audio with no
route back, and the audio it destroys is the input that cannot be regenerated.

### F7 — MEDIUM, latent. A hand-edited Note is silently overwritten

Any rename, retitle or exclusion calls `rewriteNote`, which renders from the
record and atomically replaces the file. A user's additions are gone with no
warning and no trace.

Measured: **0 of 15 notes** currently show signs of hand-editing, so this has not
fired yet on the user's disk. It is listed anyway because the user renaming files
*in Finder* is direct evidence that they regard these as their own documents, and
the next thing someone does to their own document is edit it.

**Reproduced** — a paragraph added to a Note by hand, then any retitle:

```
REPRO: hand-edited paragraph survived rewrite: false
```

No dialog, no warning, no trace. The full suite (183 tests) passes either side of
this, which is the point: nothing in the project pins the behaviour, because
nothing had noticed it.

The spine already knows about this. AD-9's Rule ends: *"a user editing a Note by
hand will have those edits overwritten if the Meeting is edited in-app, **and this
must be stated in the UI**."* It is stated nowhere in the UI. And the spine's
Deferred list says *"Notes Folder conflict policy for hand-edited Notes … out of
scope for v1"* — a deferral that was reasonable when notes were only ever written
by the app, and is not reasonable now that the user has started filing them.

### Not findings

- **The "Note missing" badge and banner are correct and well-written.** FR-53
  works exactly as specified; the specification is what turned out to be
  incomplete. The badge tells the truth — the file at that path is not there.
- **AD-9 is not the problem and should not be relaxed.** Two owners of meeting
  data is a real failure mode and the projection model prevents it. What is
  missing is a distinction AD-9 never had to draw: reading a file's *identity* is
  not reading its *content*.
- **The Notes Folder is not watched (no FSEvents anywhere in `Sources/`).** State
  refreshes on reload. That makes the badge briefly stale after a Finder rename,
  which is a lesser issue than everything above and is listed as such.

## What the fix has to be, at the architectural level

The link must stop being a filename.

1. **Stamp identity into the file.** `minutes_id: <meeting id>` in the
   frontmatter. The file then carries its own provenance, and a rename cannot
   break the link because the link is no longer the name.
2. **Read identity, never content.** A frontmatter reader that returns
   `(minutesID, startedAt)` and nothing else. This is the AD-9 amendment: identity
   in, content never.
3. **Migration is already free.** All 15 existing notes carry `started_at` to the
   second, and no two meetings on this machine started within a second of each
   other. So `started_at` is a sufficient fallback key for every note written
   before the stamp exists — measured, not assumed.
4. **Reconcile only when a link is broken.** Zero cost in the normal case, which
   answers PRD §13 Q12 ("is FR-53's check cheap enough to run on every appearance")
   with a mechanism rather than a measurement: the scan is triggered by a failed
   existence check, not by a reload.
5. **A found file wins; an absent file changes nothing.** Relinking writes the
   discovered filename to the record, because *this file is this meeting's note* is
   a durable fact. Absence stays a display state, never a mutation — which is the
   rule `AppState.missingNotes` already documents.
6. **Once the user names a file, the app stops renaming it.** AD-18 currently
   makes the derived name authoritative on a title change. That must invert when
   the name on disk is not the name the app last wrote: the user's choice wins,
   and the app follows the file.


## Verification method

F1, F5 and F7 were reproduced by driving the real `NoteWriter` and the real delete
path from a temporary test against a temporary folder, then removing the test —
the suite is back at its baseline of **183 tests, 6 skipped, 0 failures**. Nothing
in the user's own folder was written to at any point in this investigation: the
reconciliation figures come from reads only.

F2, F3, F4 and F6 are established from the code and the disk directly and need no
reproduction. F2 and F3 are the absence of a condition and the absence of an
action; F4 is the absence of a surface; F6's evidence is a Meeting directory that
does not exist and a Trash that is empty.
