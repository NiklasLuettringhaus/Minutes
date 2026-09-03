---
title: Implementation plan — increment 7, the Note is the user's file
date: 2026-09-03
epic: 14 (11 stories)
requirements: FR-77 … FR-83, plus amended FR-35, FR-40, FR-53, FR-54
architecture: AD-39 … AD-43, plus amended AD-9 and AD-18
driving input: planning-artifacts/spikes/investigation-note-linkage-2026-09-03.md
state: planned, not built
---

# Implementation plan: increment 7

Eleven stories, in the order the epic states. **Story 14.1 first because it has no
dependencies and the loss it prevents has already happened**; everything after it
is in dependency order.

## The shape of the change

Three new types, two extended, five surfaces touched.

```
Core/
  NoteIdentity.swift          NEW  Foundation only. Frontmatter → (meetingID, startedAt). Nothing else.
Services/Ports/Ports.swift    EDIT NoteLocating; NoteWriting.write returns a result, not a String
Adapters/Persistence/
  NoteLocator.swift           NEW  Scans the folder, matches by identity, returns located/ambiguous/notFound
  NoteWriter.swift            EDIT Stamps minutes_id; digests what it wrote; refuses to overwrite bytes it did not write
  MeetingStore.swift          EDIT trashItem; a resolveNote path
Core/Meeting.swift            EDIT +noteFilenameWritten, +noteDigest (decodeIfPresent, AD-21 convention)
Services/
  NoteLinkService.swift       NEW  Reconciliation policy: when to look, what to persist, what to publish
  AppState.swift              EDIT missingNotes → noteLinks; +unclaimedNotes
  SessionCoordinator.swift    EDIT locate / adopt / keep-or-replace intents
  Pipeline.swift              EDIT writeStage persists filename + digest in one update
UI/
  MeetingsPane.swift          EDIT row menu, detail banner, filename display, delete dialog, unclaimed footer
  DesignTokens.swift          EDIT DecisionBanner beside StateBanner
```

## Story by story

### 14.1 — Deleting a Meeting can be undone *(T2, no dependencies)*

`MeetingStore.delete(id:alsoDeleteNote:)` and `deleteAudio(id:)`:

```swift
try fm.trashItem(at: directory(for: id), resultingItemURL: nil)
```

`removeItem` → `trashItem` in exactly those two methods, and the swallowed
`try?` on the Note becomes a reported failure. **No fallback to unlinking**: a
volume without a Trash means the delete does not happen, because an undoable
delete is the whole point.

`MinutesError` gains `.deleteFailed(String)` with a remedy of `.revealInFinder`
if that remedy exists by then, otherwise no remedy — the increment-6 rule
applies, a reason without a remedy is honest and a wrong remedy is not.

**Test:** a temp-rooted `MeetingStore`, delete, assert the directory is gone from
its parent *and* present under the volume's `.Trash`. `trashItem`'s
`resultingItemURL` gives the path to assert on, so this is a real assertion
rather than a proxy.

**Grep guard:** a test that scans `Sources/` for `removeItem` and fails on any
call outside the temp/staged-write allowlist. Without it the next person restores
the bug in a line of cleanup code — the same reasoning as `CorePurityTests`.

### 14.2 — A Note says which Meeting it belongs to *(T6)*

`Core/NoteIdentity.swift`, Foundation only, pinned by `CorePurityTests`:

```swift
struct NoteIdentity: Equatable, Sendable {
    let meetingID: String?
    let startedAt: Date?
    let writtenByMinutes: Bool

    /// Reads the frontmatter block and nothing after it. Returns nil when the
    /// file does not open with `---`, so an arbitrary Markdown document is
    /// rejected rather than scanned.
    static func parse(frontmatterOf text: String) -> NoteIdentity?
    func matches(_ m: Meeting) -> Bool     // ID first, then startedAt ±1s
}
```

Three keys are read: `minutes_id`, `started_at`, `generated_by`. **The type cannot
carry a title, a summary or an utterance** — that is how AD-9's identity/content
line is enforced, and it is why this is a struct with three fields rather than a
`[String: String]`.

`NoteWriter.frontmatter` gains `minutes_id: <id>` as the first line after `title`.

**Why ±1 second:** the frontmatter's ISO string is `.withInternetDateTime`, which
is second-precision; `Meeting.startedAt` is not. Measured on the real notes:
`2026-09-03T07:30:38Z` against a record holding sub-second precision.

**Test on real data:** `NoteIdentityRealNotesTests`, gated behind an env var like
the calibration tests, reads `~/Documents/Minutes` and asserts every file parses
and every one matches exactly one Meeting or none. It read 15 files at planning
time; it must not fail because the user has 40 by then, so it asserts a property,
not a count.

### 14.3 — Finding a Note that moved *(T6)*

Port:

```swift
enum NoteLocation: Equatable, Sendable {
    case located(URL)
    case ambiguous([URL])
    case notFound
}

protocol NoteLocating: Sendable {
    func locate(meeting: Meeting, in folder: URL) throws -> NoteLocation
    func unclaimed(meetings: [Meeting], in folder: URL) throws -> [UnclaimedNote]
}
```

`NoteLocator` reads the head of each candidate — **a bounded read, not the whole
file.** A 72 KB note exists already; reading 400 whole files to find one is the
cost this bounding removes:

```swift
let handle = try FileHandle(forReadingFrom: url)
defer { try? handle.close() }
let head = try handle.read(upToCount: 4096)
```

4096 bytes covers every real frontmatter block with room to spare — measured, the
longest of the fifteen on disk is **753 bytes** (a fourteen-speaker meeting, where the `participants`, `in_room` and `remote` lists
carry the length). A frontmatter that does not close within the head yields no
identity, which is correct: a file with 4 KB of frontmatter is not one of ours.

One level of subdirectory, because "moved it" often means "moved it into a
folder", and a bounded depth is the difference between a fix and a filesystem
crawl.

**The test that matters** asserts the locator is inert: capture every file's name,
size and `contentModificationDate` before and after a resolution and require them
identical. AD-39 says resolution creates, renames, moves and deletes nothing, and
that is the assertion which pins it.

### 14.4 — "Missing" means Minutes looked and did not find it *(T6)*

`Services/NoteLinkService.swift` owns the policy, so no view and no adapter
decides it:

```swift
@MainActor enum NoteLinkService {
    /// Called from AppStateBridge.reloadMeetings. Cheap when nothing is broken:
    /// one `stat` per complete Meeting, and no folder read at all unless one fails.
    static func reconcile(_ meetings: [Meeting], in folder: URL?) async -> [String: NoteLinkState]
}

enum NoteLinkState: Equatable {
    case linked(filename: String, userNamed: Bool)
    case ambiguous([URL])
    case notFound
}
```

`AppState.missingNotes: Set<String>` becomes `noteLinks: [String: NoteLinkState]`.
`missingNotes` stays as a computed property over it for one commit so the change
is reviewable, then goes.

A single match is persisted through `MeetingStore.update`; ambiguity and absence
persist nothing.

**The zero-cost claim needs a test, not a comment.** A counting fake conforming to
`NoteLocating` asserts `locate` was called **0 times** for a library whose links
are all intact, and exactly once for the one that is broken. Increment 6's lesson
applies directly: a rule that is only stated in a comment is a rule that gets
reverted with all tests green.

### 14.5 — Row and detail actions tell the truth *(T2)*

The reported bug. One helper, used by both surfaces:

```swift
extension NoteLinkState {
    var locatedURL: URL? { … }      // the ONLY thing Reveal/Open may be conditioned on
}
```

`MeetingsPane.rowContent`'s context menu changes its condition from *a filename is
recorded* to *a file was located*, and gains `Locate note…`. The detail pane's
`titleBlock` reads the same state instead of `app.missingNotes.contains`.

**Test:** a pure function `MeetingsPane.rowActions(for:) -> [RowAction]` returning
an enum, tested per state — the actions are then assertable without rendering a
menu, which is the same shape as increment 6's `FailureRemedyTests`.

### 14.6 — Pointing a Meeting at a file *(T6)*

`SessionCoordinator.locateNote(meetingID:) async` opens an `NSOpenPanel`
(`directoryURL` = the Notes Folder, and `allowedContentTypes` from
`UTType(filenameExtension: "md")` — **not** `UTType.markdown`, which does not
exist; compiled and checked, it resolves to `net.daringfireball.markdown` and
conforms to `.plainText`), then:

- the chosen file's identity names **this** Meeting → link, no dialog;
- it names **another** Meeting → name that Meeting, confirm;
- it carries **no** Minutes identity → say the next rewrite would replace the
  file's contents, confirm.

Linking writes `noteFilename` and, per 14.9, a digest of the file's **current**
bytes — so adopting a file the app did not write does not immediately count as a
conflict, and the app's first rewrite is the moment the user was warned about.

Sandbox is off (`Scripts/Minutes.entitlements`), so no new security-scoped
bookmark is needed for a file inside the already-granted folder.

### 14.7 — The name you gave the file is the name it keeps *(T6)*

`Meeting` gains `noteFilenameWritten: String?`, decoded with `decodeIfPresent`
(the Decodable-evolution convention; a plain default silently orphaned five real
recordings once).

```swift
var noteIsUserNamed: Bool {
    guard let f = noteFilename, let w = noteFilenameWritten else { return false }
    return f != w
}
```

**No `didUserRename` flag.** The comparison *is* the test, and a flag can fall out
of sync with the filesystem while a comparison cannot — AD-40.

`NoteWriter`'s rename branch gains `guard !meeting.noteIsUserNamed`. The detail
pane shows the filename in `Tok.monoInline` when user-named.

**Migration:** every existing record has `noteFilename` and no
`noteFilenameWritten`, which would read as "app-named" and is right — those files
*are* app-named. The first write after this change sets both.

### 14.8 — A rewrite finds the file before it writes one *(T2)*

`Pipeline.rewriteNote` resolves the link first and passes the located URL to
`NoteWriter`. `NoteWriter.write` stops deriving a destination from a stored
filename it has not checked.

**The test reproduces the original defect exactly:** write a note, rename the file
on disk, call rewrite, assert the folder holds **one** note for that Meeting and
that it is the renamed one. **That test has been run against today's code and
fails** — today the folder holds two, and the second is the app's — so it is a
regression test with a known-red starting point rather than a hope.

### 14.9 — The app knows what it wrote *(T6)*

`Meeting` gains `noteDigest: String?`. `NoteWriter` computes SHA-256 of the exact
bytes it writes (CryptoKit, in the adapter — **not** in Core, which
`CorePurityTests` pins to Foundation).

`NoteWriting.write` returns a value rather than a `String`:

```swift
enum NoteWriteOutcome: Equatable {
    case written(filename: String, digest: String)
    case refusedChangedOnDisk(URL)
}
```

The refusal is a return value, not a thrown error: a conflict is an outcome the
caller must handle, and `throws` invites the `try?` that would discard it —
`rewriteNote` already logs and swallows.

`UI/DesignTokens.swift` gains `DecisionBanner` beside `StateBanner`: same tint and
glyph, sentence on its own line, two controls beneath, the non-destructive one
`.borderedProminent`.

**Migration, and the branch that must be tested:** no digest ⇒ compare the file's
`contentModificationDate` with the record's. Not later ⇒ adopt the current bytes
as the baseline. Later ⇒ raise a conflict. Measured: none of the 15 real notes is
modified after its record, so all 15 adopt cleanly. A test constructs the
later-mtime case, because the branch that never fires in the happy path is the one
that ships broken.

**The trap, stated because it is the plausible wrong implementation:** never
compare against a fresh render. The renderer changed in four increments — the
speaker index arrived in increment 4 — so re-rendering an increment-3 note
legitimately differs and would report every old note as edited. A test renders an
old-shaped record and asserts no conflict.

### 14.10 — The delete confirmation names the file it will delete *(T2)*

`MeetingsPane.deleteMessage` becomes async-resolved state computed when the alert
is raised, not a string built from `m.noteFilename`. It names resolved files,
counts resolved files, says "moved to the Trash", and when nothing resolves says
that instead.

**Test:** the reverse case. A note renamed to the filename another Meeting's
record holds must not be deleted as that Meeting's note. Today's code deletes by
path and would take the wrong file.

### 14.11 — A note whose meeting is gone is still visible *(T6)*

`NoteLocator.unclaimed(meetings:in:)` returns files carrying a Minutes identity
that no Meeting claims. A footer in `MeetingsPane`, expanding to rows in
`VoiceRow`'s anatomy. `Dismiss` writes an ID list into settings and touches no
file.

**Acceptance on real data:** `2026-09-03 0930 Morning -standup.md` appears in this
list on the author's machine. It is there now, its Meeting permanently deleted, and
no surface in the product mentions it.

## Risks, and what to do about each

| Risk | Response |
| --- | --- |
| **Reconciliation writes to records while the pipeline is writing to them** | Every write goes through `MeetingStore.update`, which is an actor and reads the freshest record (AD-21). No new lock; the existing one already covers it. |
| **A relink triggers a rewrite triggers a relink** | `NoteLinkService.reconcile` never writes a *file*, only a record field. Nothing in the write path reads that field to decide to write. Worth one test asserting a reconcile does not enqueue any pipeline work. |
| **The folder read is slow on a large folder** | Bounded read (4 KB), bounded depth (1), triggered only by a failed `stat`. The pathological case is a broken link in a 5000-file folder, and the user is waiting for an answer at that moment. If it needs a spinner, it needs a spinner. |
| **The digest baseline is adopted for a file the user had already edited** | Possible, and stated rather than hidden: the mtime signal cannot see an edit that preserved the timestamp. Measured to affect none of the 15 files here. AD-41 records the limit. |
| **`trashItem` fails on an external volume and the delete silently does nothing** | It reports. The dialog says the delete did not happen and why. Silence is the failure this increment exists to remove. |
| **Two Meetings starting in the same second break the `started_at` fallback** | Only consulted for notes with no `minutes_id`, so the population shrinks to zero. PRD §13 Q22. |

## Order of work, and what each commit leaves working

1. **14.1** — one commit, independently shippable, closes the data-loss hole.
2. **14.2 + 14.3** — the mechanism, no UI, all tests. Nothing in the app changes yet.
3. **14.4** — wires reconciliation in. The renamed note relinks; the badge stops lying.
4. **14.5 + 14.8 + 14.10** — the three destructive-or-misleading surfaces. Shippable together as "the app tells the truth about your files".
5. **14.6 + 14.7** — the user's control over naming and linking.
6. **14.9** — the digest and the decision banner. The largest single story.
7. **14.11** — the footer. Last because it is the only one nobody is currently harmed by.

## Verification that is not a unit test

- `./Scripts/uishot.sh` for the four Note Link states and the decision banner at 320 / 460 / 720pt. It cannot draw a `Button`, so it answers *does the layout hold*, not *is it correct*.
- **On real data, with the user's own folder, read-only first:** rename a note, refresh, confirm silent relink; rename it back; confirm the detail pane shows the name they chose.
- **The one thing no test can do:** delete a test meeting and drag it back out of the Trash.
