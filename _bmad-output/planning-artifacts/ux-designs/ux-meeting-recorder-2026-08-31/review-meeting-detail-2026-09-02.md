---
title: UX review — the meeting detail pane, and a tool to see it with
date: 2026-09-02
intent: validate
subject: the Speakers section of the meeting detail, from the user's screenshot and from rendered shots
lens: built-UI conformance, run for the first time against images rather than inference
verdict: two critical layout defects, one critical behavioural defect found after the first fixes shipped, one missing capability; all fixed, layout verified in images and behaviour verified in tests
---

# UX review: the meeting detail pane

The user's words: *"stuff is squeezed together and I am not sure what buttons to
click."* Both halves are fair, they name two different defects, and the second one
had been sitting in the code since increment 2 without anyone noticing.

## What changed about how this review was done

Every previous UI review in this project ended with the same admission: *I cannot
see the app.* `osascript` has no assistive access on this machine and
`screencapture` blocks on a permission prompt, so findings were grounded in the
user's screenshots and in source reading, and fixes were reasoned rather than
observed.

**That is now fixed.** `--uishot` renders the panes with `ImageRenderer`, which
needs no screen-recording permission because an app rendering its own view tree is
not capturing anyone's screen. Every finding below was seen, and every fix below
was verified by looking at the result.

The tool earned its place three times in its first hour:

1. It found that `ScrollView` and `List` do not render under `ImageRenderer` —
   the first run produced one blank image and one "unsupported" glyph. Fixed with
   `ShotScroll`, a documented render mode.
2. It found its own alignment bug: a bare `VStack` centres its children, so the
   pane titles rendered clipped on the left.
3. It found a defect the user's screenshot could not show, because the user's
   window is not that narrow — see F4.

**What it cannot do**, stated because a tool that overclaims is worse than no
tool: it cannot draw a `Button`, a `Picker` or a `ProgressView`. Those render as a
yellow "unsupported" glyph. So a shot proves a *layout* holds at a *width*; it
does not prove the app is correct, and it says nothing about focus, animation or
the real window. It also renders fixtures, not the user's data — deliberately,
because fixtures can be harsher than reality and can exist before the meeting does.

## Findings

### F1 — CRITICAL. Sixteen speakers × two lines, with the same sentence eight times

The Speakers section on a real fourteen-speaker meeting was **1100pt of a 1441pt
pane** — you scrolled past all of it to reach the transcript. Rendered, the cause
is obvious in a way it was not in the source:

- One row per speaker, each **two lines** tall.
- **"heard through MacBook Pro Microphone" repeated eight times**, once per in-room
  speaker, identical every time.
- A basis sentence on **every** row, where on most rows it restated what the row
  above already said.

The repetition was mine, from increment 4: I joined the basis note, the inferred
caption and the device into one provenance line per row, which fixed a collapse
defect and created a density one.

**Fix — group by place, and state the device once per group.** Place is the
structural fact (AD-11), so it is also the honest way to group, and it turns eight
identical device lines into one:

```
In the room with you · MacBook Pro Microphone
  [Me]                     2 lines   Rename  Exclude
    recognised from your recorded voice (distance 0.14 — lower is closer)
  [In-room 1]              1 line    Rename  Exclude
  [In-room 2]              1 line    Rename  Exclude
On the call · system audio — Microsoft Teams
  [~Speaker 1]             1 line    Rename  Exclude
    recognised automatically — check it is right
```

One line per speaker. The provenance sentence survives **only where the app is
making a claim** — the enrolment match, an inferred name, an unplaceable voice, an
exclusion — which is four rows out of sixteen instead of sixteen out of sixteen.
Verified: the section is now scannable at 460pt and at 320pt.

### F2 — CRITICAL. Twenty-eight buttons that did not look like buttons

`Rename` and `Exclude` were `.buttonStyle(.borderless)`, which renders a button as
plain text. On a fourteen-speaker meeting that is 28 controls indistinguishable
from the four other pieces of grey text on the same row.

This is exactly what the user reported, and it is worth being precise about the
failure: the buttons were not hidden, they were *disguised*. DESIGN.md has a rule
for the one control in a checklist row (`{components.button-row-action}`, bordered
and tinted) and no rule at all for a control in a list row, so the list row got
whatever was typed first.

**Fix.** `.bordered` at `.controlSize(.small)`. Verified: they read as controls in
every shot. `Save`/`Cancel` in the edit state get the same treatment, and `Save`
is `.borderedProminent` so the default action is obvious — previously those two
collapsed to `...` at narrow widths, which is visible in the user's own screenshot.

### F3 — HIGH, and the user asked for it directly. Renaming was only possible at the top

> *"renaming should be possible within the script not just the speaker list at the
> top."*

Correct, and the reason is worth writing into the spine rather than just fixing:
**the transcript is where you recognise a voice.** You read a line, you know who
said it — and the fix was in a list above, which by then has scrolled away and
where the speaker is an anonymous label again with no words attached.

**Fix.** Every speaker chip in the transcript is now a button that opens a small
rename popover in place. The popover states what the rename does — *"applies to
every line they spoke in this meeting, and Minutes will recognise the voice next
time"* — because a user clicking one line could reasonably expect it to affect
only that line, and FR-24 renames the label.

### F4 — MEDIUM, and only findable with the tool. The row overflowed instead of adapting

At 320pt the redesigned row **overflowed its container** rather than wrapping —
chip, line count and two buttons need about 380pt. The user could not have
photographed this, because the detail column has a 560pt minimum, so it is below
the width the app can actually reach today.

Worth fixing anyway, and worth recording as the tool's first independent find: an
overflowing row is the same class of bug as the collapse it had just replaced, and
a minimum width is a constraint that changes.

**Fix.** `ViewThatFits`: one line where it fits, controls on a second line where
it does not. Verified at 320, 460 and 720.

### F5 — LOW. "1 lines"

Fifteen rows read "1 lines". Fixed; pluralisation is now correct, and the count
sits beside the chip rather than at the far right where it read as a fourth column.

## Not findings

- **The yellow glyphs in every shot are the renderer, not the app.**
  `ImageRenderer` cannot draw `Button`, `Picker` or `ProgressView`. Recorded here
  because anyone reading these images later will wonder.
- **"16 voices" on a fourteen-speaker meeting.** The fixture has sixteen labels
  including `In-room, unidentified` and `Me`, and the count is of labels, which is
  what the section lists. Correct, if briefly surprising.
- **The section is still long.** Sixteen speakers is sixteen rows and no layout
  removes that. It is now scannable rather than a wall, which is the achievable
  goal; hiding speakers behind a disclosure would trade one complaint for a worse
  one.

## What the previous review's fixes look like, now that they can be seen

Recorded because they were reasoned rather than observed, and one of them I was
explicitly unsure about:

| Previous finding | Verified? |
|---|---|
| Card boundary invisible (hairline added) | **Yes** — cards have a clear edge in every pane shot. This is the one I said needed a look. |
| Four left edges per pane | **Yes** — two edges, and the Summaries icon sits on its title's line. |
| Chips unreadable on a selected row | **Yes** — white on blue, with place glyphs, in `list-*.png`. |
| Chips collapsing to vertical ovals | **Yes** — and the real fix was not the one I shipped last time. See below. |

**The chip fix was incomplete last time and I did not know it.** I added
`fixedSize` to the *detail* speaker row and left the *list* chips alone, so the
user's latest screenshot still shows vertical ovals in the list. The complete fix
is two parts: `lineLimit(1)` plus `truncationMode(.tail)` inside the chip so it
refuses to be narrowed at all, and `FlowLayout` in the row so overflow wraps to a
second line instead of being distributed into the chips. Both verified.

## F6 — CRITICAL, reported after the fixes above shipped. The popover opened on the wrong row, slowly

*"Clicking rename speaker, makes the popup not appear on the actual row I pointed
it to and it was quite slow to pup up."*

Both symptoms, one cause, and it was in the fix for F3 — so F3 was half-right and
shipped a worse bug than the one it solved.

The popover was keyed by **speaker**: `isPresented: renaming == b.speaker`. A
speaker owns one block per *turn*, not one block per meeting, so clicking one chip
set that condition true on **every** block that speaker ever had. SwiftUI presented
all of them and drew the first in tree order, which is a row far above the one
clicked — exactly what the screenshot shows.

Measured on the user's own meeting rather than assumed: **708 blocks**, with
`In-room 4` (the chip in the screenshot) appearing **9 times** and `Speaker 2`
appearing **173 times**. Nine simultaneous popovers for one click.

The slowness has the same root. Every one of the 708 rows carried a `.popover`
modifier for a thing that can only be shown once, and `renaming` was part of
`TranscriptCard`'s `==`, so each click invalidated the card and re-laid-out all
708 paragraphs — each a `fixedSize` text forcing its own layout pass. The delay
was the transcript re-rendering, not the popover.

**Fix, in three parts:**

- **Key by block id, not speaker.** A block id is unique per block, so exactly one
  popover can be presented and it is the one pointed at.
- **Attach the `.popover` modifier only to the row being renamed.** One modifier
  in the tree instead of 708.
- **Split each paragraph into its own `Equatable` row** and drop `renaming` from
  the card's `==`. A click now re-renders the two rows whose state changed rather
  than all 708.

Four tests pin the condition that made the old keying wrong — that one speaker
legitimately owns many blocks — and the condition that makes the new keying right:
block ids are unique, and they survive the rename they trigger.

**What this says about the previous review.** F3 was verified as *"the popover
opens"* and not as *"the popover opens on the row you clicked, on a meeting with
708 paragraphs"*. The tool cannot render a popover, so the verification stopped at
the layout — and the defect lived in behaviour under repetition, which no single
rendered image would have caught. Worth recording plainly: the tool moved the line
between *reasoned* and *observed*; it did not move it to *proven*.

## Spine changes

| Spine | Change |
|---|---|
| `DESIGN.md` | `{components.speaker-chip}`: a chip is a fixed-size token — one line, truncating, never reflowing |
| `DESIGN.md` | New: a control in a list row is bordered, never borderless. Borderless is for a control that is already the only thing on its line. |
| `EXPERIENCE.md` | Meetings detail: speakers group by place, device named once per group, provenance only where a claim is made |
| `EXPERIENCE.md` | Meetings detail: renaming is available from any transcript line, and the affordance is the chip |
| `EXPERIENCE.md` | New under Interaction Primitives: a row of controls uses `ViewThatFits` rather than assuming a width |
| Both | The `--uishot` tool is named as the way a layout claim gets checked |
