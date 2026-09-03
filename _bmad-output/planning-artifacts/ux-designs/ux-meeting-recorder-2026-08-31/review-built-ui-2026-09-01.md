---
title: UX review — the built UI against its own spines
date: 2026-09-01
intent: validate
subject: the shipped app, as photographed by the user, reviewed against DESIGN.md + EXPERIENCE.md
lens: built-UI conformance (ad-hoc), plus the rubric walker's token / component / shape categories
verdict: two critical defects, one of them introduced by increment 4; two high; and three places where the spine was silent rather than the code wrong
---

# UX review: the built UI

The user supplied two screenshots and two words of diagnosis — *"the colors not
working"* and *"a little confusing layout"*. Both are right, and both turn out to
name something more specific than they look.

## How this was run, and what it cannot see

The review lens is **built-UI conformance**: read the screenshots, find what
differs from the spines, and decide per finding whether the *code* violates the
spine or the *spine* was silent. That distinction is the whole value here — a
defect and an unwritten rule need opposite fixes, and three of the seven findings
below are the second kind.

Run inline, not as subagents. And one limitation matters more than that:

> **I cannot see the running app.** `osascript` has no assistive access on this
> machine and `screencapture` blocks on a permission prompt, so every finding is
> grounded in the two screenshots plus the source, and every *fix* below is
> reasoned rather than observed. Two of them — the card surface and the row
> re-layout — need one look to confirm. That is stated per finding rather than
> implied.

## Findings

### F1 — CRITICAL. The Speakers row collapses to one character per line

`Sources/Minutes/UI/MeetingsPane.swift`, `speakerBlock`.

In the first screenshot's right pane, the Speakers section reads:

```
your        Re     Ex-    6
mi-         na     clu-   lin
cro-        me     de     es
phon
e
held
a
sin-
gle
voic
e, so
this
is
cer-
tain
```

Every text has been squeezed to its minimum width, and the speaker chips have
become tall vertical capsules. The pane is unusable.

**Cause.** The row is a single `HStack` holding, in the non-editing case: the
chip, a Rename button, an optional "recognised automatically" caption, an optional
basis note, a `Spacer`, an Include/Exclude button, a line count, and the device
name. Eight children, two of them unconstrained prose. SwiftUI has no width to
give them, so it takes width from everything.

**This is mine, and it is increment 4's.** The layout was already over-full, but
the extra caption only rendered when a speaker was `isInferred` — rare. Story
10.7 added `basisNote(for:)`, which returns a sentence for `.structural`,
`.enrolmentMatch` *and* `.inRoomUnplaceable` — i.e. for almost every speaker in
almost every meeting. A latent cramped row became an always-broken one.

**Fix.** Two lines: chip · Rename · Spacer · Exclude · line count on the first;
the provenance sentence as a subtitle on the second. That is not an invention —
it is exactly the anatomy this spine already declares for
`{components.voice-row}` ("title over one-line subtitle"), which increment 4 wrote
for the General pane and then failed to apply to the pane it had just changed.

*Confidence: high on the cause, high on the fix. Needs one look.*

### F2 — CRITICAL. Chips inside a selected row keep their own tint and stop being legible

This is "the colors not working", precisely.

In the first screenshot the selected row carries the
system blue selection fill. The chips inside it do not know that:

| Chip | Renders as | Result |
|---|---|---|
| `In-room 2`, `In-room 3` | `{colors.ink-amber}` on blue | illegible |
| `Speaker 1` | `{colors.text-secondary}` on blue | washed out |
| `Me` | `{colors.brand-accent}` on blue | low contrast |

**The spine is at fault here, not only the code.** `{components.speaker-chip}`
defines three treatments by *place* and says nothing about the chip appearing
inside a selected row. EXPERIENCE.md's *Meetings list and detail* says rows carry
speaker chips and likewise says nothing. So there was no rule to violate — which
is why this shipped.

Two things are true at once and the spine has to say both: the chip's place tint
is load-bearing (it encodes the product's structural claim, per DESIGN.md's own
Components note), and a selection fill owns the foreground of everything inside
it. When those collide, selection wins, because an illegible chip conveys nothing
at all.

**Fix.** DESIGN.md gains a `selected` treatment on `{components.speaker-chip}`:
inside a selected row the chip drops its place tint for the selection's own
foreground, keeping its glyph and its `~` prefix so place and inference survive
without colour. The code threads a flag down from the row.

*Confidence: high. The mechanism is visible in the screenshot.*

### F3 — HIGH. Cards have no visible boundary

In the second screenshot there are three cards — *Running now*, *Which one to
use*, *What this is not* — and no discernible edge or tonal step between any of
them and the window. The pane reads as one undifferentiated column of prose,
which is half of "confusing layout".

**The spine's premise has failed.** DESIGN.md commits to tonal separation and
then forbids the alternative:

> *Cards have `{rounded.lg}` corners and **no border** — a stroke plus a tonal
> step is belt-and-braces and reads as heavier than macOS does.*

That reasoning is sound *when the tonal step is perceptible*. Here
`{colors.surface-card}` (`controlBackgroundColor`) against
`{colors.surface-window}` (`windowBackgroundColor`) produces no visible step in
the detail column on this OS version. A don't-rule whose premise is false is not
a rule; it is an unexamined assumption, and it has cost the pane its only
grouping mechanism.

**Fix.** Amend the spine rather than work around it: the no-border rule holds
*while* the tonal step is perceptible, and where it is not, a hairline in
`{colors.separator}` is the correct fallback — that being what macOS itself does
in list and form contexts. Implement a slightly stronger fill plus that hairline.

*Confidence: high that the boundary is invisible — it is plainly absent in the
screenshot. Lower that my specific replacement is enough, because I cannot see the
result. This is the finding most in need of one look.*

### F4 — HIGH. Three competing left edges down every pane

Also "confusing layout", and the more mechanical half of it. Measured from the
source rather than the screenshot:

| Element | Left offset from the pane margin | Why |
|---|---|---|
| Pane title / subtitle | 0 | `PaneScaffold` |
| Section heading | **+2** | `SectionHeading` has `.padding(.horizontal, 2)` |
| Card body text | **+16** | `Card` has `{spacing.card-padding}` |
| Icon-led card text | **+48** | +16 card, +20 icon column, +12 gap |

Four edges, and two of them differ by 2pt — close enough to read as
misalignment rather than as hierarchy. In the second screenshot *Summaries* starts
left of *Running now*, which starts far left of *Keyphrase extraction*, while the
radio buttons in the very next card start at a fourth position.

**The spine is silent.** DESIGN.md fixes heading *placement* ("outside and above
the card, never inside it") and never fixes the left-edge *relationship*, so the
implementation drifted into four.

**Fix.** Two edges, stated in the spine: the pane margin for titles and section
headings, and the card padding for card content. Drop `SectionHeading`'s stray
2pt, and give icon-led rows a shared text column so two cards on one pane start
their text at the same x.

*Confidence: high — this one is arithmetic from the source, not inference from
pixels.*

### F5 — MEDIUM. The same fact stated twice, forty lines apart

Summaries card 1: *"Apple Intelligence is switched off on this Mac, so there is no
language model to use."*
Summaries card 2: *"The language model is not available on this Mac right now, so
keyphrase extraction is what actually runs."*

Both are true and one is redundant. EXPERIENCE.md's Voice and Tone requires copy
be unambiguous and then get out of the way; saying the same thing twice on one
pane invites the reader to look for the difference.

FR-57's actual requirement is narrower and better: the pane must say which backend
runs *next*, which differs from the selection only when the selection is
unavailable. The second sentence should be that — a consequence of the choice
above it — not a restatement of the state above it.

*Confidence: high. Both strings are in the source.*

### F6 — MEDIUM, and a judgement rather than a defect. "What this is not" dominates the pane

Four bullets of negation, and the largest block on the pane. It exists for a good
reason recorded in the source: the *absence* of settings is what made the user
suspect something hidden, so the absence is stated explicitly.

**Not changed.** This is the user's own copy answering the user's own question,
and shortening it is an opinion about tone, not a conformance finding. Flagged so
it is a decision rather than an oversight: it could compress to two lines without
losing a fact, if the pane feels heavy after F3 and F4 land.

### F7 — MEDIUM. The detail header wraps mid-phrase

`Tuesday 1 September, 10:59` breaks across two lines with `33:52` and `Reveal
note` beside it. Same family as F1 — an `HStack` of items with no width priority —
and cheap to fix in the same pass.

*Confidence: high.*

## Not findings, but worth recording

- **The meeting titles are single words.** *Die*, *What*, *New*, *Channel*. That
  is keyphrase extraction doing what FR-26 permits and §9.3 tolerates — a title is
  guaranteed, its quality is not — and it is the strongest argument yet for Epic
  9's local model. Not a UI defect; the pane is rendering exactly what it was
  given.
- **The list rows work.** Overflow (`+2`, `+5`) is handled, dividers are visible,
  the multi-select footer reads clearly. Whatever is wrong with the chips inside a
  *selected* row, the unselected rows are correct.
- **`if true {`** — a dead conditional wrapping the Rename button in
  `speakerBlock`. Removed while fixing F1.

## What this says about the process

Increment 4 shipped a critical layout regression into the pane it was editing,
and 149 tests said nothing. That is not a gap in the tests — SwiftUI layout is
not unit-testable, and pretending otherwise would be worse. It is a gap in the
*loop*: every check in this project can be run from a terminal, and the one thing
that cannot is the one thing that broke.

The honest conclusion is not "write layout tests". It is that a pane whose row
gains a new child needs a human to look at it once, and increment 4 had no such
step because the machine was busy recording all afternoon. Worth recording in the
handoff as a standing condition rather than as this increment's bad luck.

## Spine changes this review produces

| Spine | Change | Kind |
|---|---|---|
| `DESIGN.md` | `{components.speaker-chip}` gains a `selected` treatment | rule that was missing (F2) |
| `DESIGN.md` | Elevation & Depth: the no-border rule holds while the tonal step is perceptible; a hairline is the stated fallback | premise corrected (F3) |
| `DESIGN.md` | Layout & Spacing: two left edges, named | rule that was missing (F4) |
| `EXPERIENCE.md` | Meetings detail: the speaker row is title-over-subtitle, not one line | conformance restated (F1) |
| `EXPERIENCE.md` | Summaries: the second sentence states the consequence of the selection, never the state already stated | copy rule (F5) |
