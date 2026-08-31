---
name: Minutes
description: A native macOS menu bar utility that inherits Apple's visual system and adds only what recording state and setup progress genuinely require.
status: final
created: 2026-08-31
updated: 2026-08-31
sources:
  - ../../prds/prd-meeting-recorder-2026-08-31/prd.md
  - ../../prds/prd-meeting-recorder-2026-08-31/addendum.md
colors:
  # --- Platform-owned. Do NOT hardcode; resolve from the system at render time. ---
  surface-window:      { note: 'SwiftUI Color(nsColor: .windowBackgroundColor) — adapts light/dark' }
  surface-card:        { note: 'Material.regular / Color(nsColor: .controlBackgroundColor) — the recessed card ground' }
  surface-sidebar:     { note: 'SwiftUI .sidebar list style default — do not override' }
  text-primary:        { note: 'Color.primary' }
  text-secondary:      { note: 'Color.secondary — subtitles, timestamps, de-emphasised checklist rows' }
  separator:           { note: 'Color(nsColor: .separatorColor)' }
  control-accent:      { note: "Color.accentColor — the USER'S system accent. Standard controls keep it; do not repaint them with brand teal." }
  # --- Literal. Semantics the system does not provide. Only three. ---
  state-recording:     '#E5484D'
  state-transcribing:  '#F5A524'
  state-blocked:       '#B26A00'   # added increment 3 — a capability the machine cannot do yet, and the egress marker. Deliberately NOT state-recording (reserved) and darker than state-transcribing so the two never read as the same signal.
  brand-accent:        '#12A594'
  brand-accent-hover:  '#0E8C7D'
typography:
  # Platform-owned type ramp. macOS text styles, resolved by the system so Dynamic Type and
  # accessibility sizes work for free (see EXPERIENCE.md § Accessibility Floor).
  pane-title:     { note: 'macOS .largeTitle — "Getting Started", "Meetings"' }
  pane-subtitle:  { note: 'macOS .body, Color.secondary — the one-line under a pane title' }
  card-heading:   { note: 'macOS .headline — "Quick Setup", "Test Playground"' }
  row-title:      { note: 'macOS .body, medium weight — checklist row and model row titles' }
  row-subtitle:   { note: 'macOS .caption, Color.secondary — the one-line why' }
  control-label:  { note: 'macOS .body — buttons, menu items' }
  metric:         { note: 'macOS .caption, monospaced digits — elapsed time, durations, timestamps, file sizes' }
  transcript:     { note: 'macOS .body — transcript text; NOT monospaced, it is prose' }
  transcript-ts:  { note: 'macOS .caption, monospaced digits, Color.secondary — transcript timestamps' }
  mono-inline:    { note: 'macOS .caption, monospaced — a model identifier or a shell command shown inline. Added increment 3: PRD FR-58 requires a remedy be specific enough to paste.' }
rounded:
  sm: '4px'
  md: '6px'
  lg: '10px'
  full: '9999px'
  DEFAULT: '6px'
spacing:
  '1': '2px'
  '2': '4px'
  '3': '8px'
  '4': '12px'
  '5': '16px'
  '6': '20px'
  '7': '24px'
  '8': '32px'
  # The numeric scale was referenced by checklist-row and others from the start but
  # never declared. Written down in increment 3 rather than left implicit.
  1: '2px'
  2: '4px'
  3: '8px'
  4: '12px'
  5: '16px'
  8: '32px'
  card-padding: '16px'
  card-gap: '16px'
  row-gap: '8px'
  pane-margin: '20px'
components:
  menubar-icon:
    size: '18px'
    idle:         { glyph: 'waveform', tint: '{colors.control-accent}', rendering: 'template — system tints it' }
    recording:    { glyph: 'record.circle.fill', tint: '{colors.state-recording}', rendering: 'palette — colour is load-bearing' }
    transcribing: { glyph: 'ellipsis.circle', tint: '{colors.state-transcribing}', rendering: 'palette' }
    note: 'Silhouettes must differ, not only tint — PRD FR-2 / NFR-7. Never animate while Idle (PRD NFR-3).'
  card:
    background: '{colors.surface-card}'
    radius: '{rounded.lg}'
    padding: '{spacing.card-padding}'
    heading-placement: 'outside and above the card, never inside it'
    border: 'none — separation comes from the tonal step, not a stroke'
  checklist-row:
    min-height: '44px'
    padding: '{spacing.4} {spacing.card-padding}'
    leading-indicator:  { satisfied: 'checkmark.circle.fill @ {colors.brand-accent}', outstanding: 'ordinal numeral in a {rounded.full} {colors.separator} ring' }
    title:    '{typography.row-title}'
    subtitle: '{typography.row-subtitle}'
    trailing-satisfied:   '{components.pill-done}'
    trailing-outstanding: '{components.button-row-action}'
    satisfied-treatment: 'title drops to {colors.text-secondary}, whole row to ~55% opacity'
    separator: '{colors.separator} hairline between rows, inset to text origin, none after the last'
  pill-done:
    label: 'Done'
    icon: 'checkmark'
    background: '{colors.brand-accent}' 
    opacity: '0.15'
    foreground: '{colors.brand-accent}'
    radius: '{rounded.full}'
    padding: '{spacing.2} {spacing.4}'
    interactive: false
    note: 'Reads as a status badge, never as a button. No hover state, not focusable.'
  button-row-action:
    style: 'bordered, tinted'
    tint: '{colors.brand-accent}'
    label-suffix: '→'
    radius: '{rounded.md}'
    note: 'The only interactive control in an outstanding checklist row.'
  button-primary:
    style: 'borderedProminent'
    tint: '{colors.brand-accent}'
    radius: '{rounded.md}'
    note: 'One per pane, maximum. "Start Test", "Download".'
  backend-row:
    min-height: '44px'
    padding: '{spacing.4} {spacing.card-padding}'
    selection: 'radio, one active; the active row is unambiguously selected, not merely check-marked'
    title:    '{typography.row-title}'
    subtitle: '{typography.row-subtitle}'
    technical-id: '{typography.mono-inline} @ {colors.text-secondary}'
    separator: '{colors.separator} hairline between rows, inset to text origin, none after the last'
    note: 'Anatomy is intentionally identical to the Transcription pane model row (behavioural spec in EXPERIENCE.md § "Model row") — PRD FR-56 asked for the pane to be "similar to the model selection for transcription". Divergence is a defect unless the underlying thing differs; the one intended divergence is the Blocked readiness state.'
    family-heading: '{typography.card-heading}, one per family: "On this Mac, built in" / "On this Mac, downloaded" / "Somewhere else"'
    readiness:
      ready:       { label: 'Ready',        treatment: '{components.pill-done}' }
      download:    { label: 'Download',     treatment: '{components.button-row-action}' }
      needs-key:   { label: 'Needs a key',  treatment: '{components.button-row-action}' }
      blocked:     { label: 'Blocked',      treatment: '{components.blocked-note} — no action control at all' }
    order: 'purpose in plain language, then provider, then technical id, then cost (disk size or per-meeting estimate), then readiness'
  blocked-note:
    background: 'none'
    foreground: '{colors.text-secondary}'
    glyph: 'exclamationmark.triangle — {colors.state-blocked}'
    body: '{typography.row-subtitle} — states the prerequisite AND the remedy'
    remedy: '{typography.mono-inline} when the remedy is a command'
    note: 'Occupies the trailing slot where a button would be, so the reader meets the reason before reaching for an action. Never focusable, never selectable — a blocked capability must not be choosable (PRD FR-58).'
  egress-marker:
    applies-to: 'the "Somewhere else" family heading and the key-entry card only'
    treatment: '{colors.state-blocked} left rule at 2px, no fill'
    note: 'The single visual signal in the product that means "this leaves your Mac". Used nowhere else, so it never becomes decoration. Deliberately not {colors.state-recording} — that colour means Recording and nothing else.'
  progress-download:
    style: 'determinate linear'
    tint: '{colors.brand-accent}'
    note: 'Determinate only — PRD FR-18 forbids an indeterminate spinner for downloads.'
  state-banner:
    radius: '{rounded.md}'
    padding: '{spacing.3} {spacing.4}'
    recording:    { background: '{colors.state-recording}',    opacity: '0.12', foreground: '{colors.state-recording}' }
    transcribing: { background: '{colors.state-transcribing}', opacity: '0.12', foreground: '{colors.state-transcribing}' }
    degraded:     { background: '{colors.state-transcribing}', opacity: '0.12', foreground: '{colors.state-transcribing}', icon: 'exclamationmark.triangle' }
  speaker-chip:
    radius: '{rounded.full}'
    padding: '{spacing.1} {spacing.3}'
    local:    { background: '{colors.brand-accent}', opacity: '0.15', foreground: '{colors.brand-accent}' }
    remote:   { background: '{colors.separator}', foreground: '{colors.text-secondary}' }
    inferred: { suffix: 'a small "~" prefix on the name', note: 'PRD FR-25 requires an auto-applied name be recognisable as inferred.' }
---

# Minutes — Design

## Brand & Style

Minutes should look like it came with the operating system. It is a utility a person sees for four seconds at a time, forty times a day, and then configures once and forgets — so the design's job is legibility and restraint, not personality. The posture is **system-native, quiet, and slightly clinical**: standard controls, system materials, system type, generous whitespace, no custom chrome, no illustration, no marketing surface anywhere in the product.

This is a deliberate refusal. A local-first tool with one user cannot amortise a bespoke design system, and every custom control is a thing that breaks on the next macOS release. PRD SM-C2 names surface-area growth as the mechanism by which small tools rot; inheriting Apple's visual system is how that is resisted visually.

Where the product does spend visual budget, it spends it on exactly two things: **is it recording right now**, and **what is still not set up**. Everything else recedes.

The one borrowed idea is from FluidVoice, which the user named directly: setup as a checklist of rows that each explain themselves and each carry their own state, with satisfied rows fading into the background. That pattern is adopted closely. What is not adopted is the rest of that product's surface — no stats chip, no changelog pane, no feedback form. Those belong to a product with users.

## Colors

**Almost every colour here is the system's, not ours.** `{colors.surface-window}`, `{colors.surface-card}`, `{colors.text-primary}`, `{colors.text-secondary}`, and `{colors.separator}` resolve from AppKit semantic colours at render time. This is what makes light mode, dark mode, increased contrast, and any future macOS appearance work without a single conditional in our code.

`{colors.control-accent}` is **the user's own system accent colour**, not ours. Standard controls — checkboxes, focus rings, selection highlights, sidebar selection — keep it. Repainting them teal would be the exact species of over-design this product is avoiding.

Three literal colours exist, each because the system provides no semantic equivalent and the meaning is non-negotiable:

- **`{colors.state-recording}` (#E5484D)** — Recording, and only Recording. Red because it is the universal convention and because macOS's own capture indicator is warm; a user glancing at the menu bar must reach the right conclusion without thinking. It appears nowhere else in the product — not on destructive buttons, not on errors. Reserving it is what makes it legible.
- **`{colors.state-transcribing}` (#F5A524)** — work in progress: transcribing, and the degraded-capture warning. Amber reads as "busy / attention" without the alarm of red.
- **`{colors.brand-accent}` (#12A594)** — the teal from the reference. Used for the primary action in a pane, the satisfied checklist indicator, the Done pill, download progress, and the Local Speaker chip. It was chosen partly because the user liked it and partly for a structural reason: it is cold, so it can never be mistaken at a glance for the Recording state. A warm brand accent would have been a real usability bug in this specific product.

Errors use the system's own error presentation. We do not define an error colour, because inventing one that competes with `{colors.state-recording}` is how a red menu bar icon stops meaning "recording".

## Typography

Entirely platform-owned. Every role in the frontmatter is a macOS text style resolved by the system, which is what makes accessibility text sizes work with no effort on our part.

Three rules that are ours rather than Apple's:

1. **Numbers that change are monospaced-digit.** Elapsed recording time, transcript timestamps, durations, file sizes — `{typography.metric}` and `{typography.transcript-ts}`. A timer whose digits reflow while you watch it is unreadable.
2. **Transcript text is prose, not code.** `{typography.transcript}` is the standard body style. The temptation to set a transcript in a monospaced font must be resisted; it is a conversation, and it is read, not scanned for whitespace.
3. **Every checklist and model row has a subtitle, and it is one line.** `{typography.row-subtitle}` exists to explain *why*, and the type is sized so that two lines look wrong — which enforces the writing discipline in EXPERIENCE.md § Voice and Tone.

## Layout & Spacing

A 4px-derived scale (`{spacing.2}` = 4px through `{spacing.8}` = 32px), with four named tokens for the layouts that repeat: `{spacing.pane-margin}` (20px) around pane content, `{spacing.card-padding}` (16px) inside a card, `{spacing.card-gap}` (16px) between stacked cards, `{spacing.row-gap}` (8px) between rows within a card.

The window is a standard SwiftUI `NavigationSplitView`: a sidebar of grouped destinations and a detail pane. Sidebar width is the system default; it is not customised. Detail panes are a vertical stack of cards, each preceded by a heading that sits **outside** the card — the pattern in the reference, and it makes a pane scannable by heading alone.

Panes must fit a 13-inch laptop display without scrolling in their default state (PRD §4.9 feature NFR). Where content can grow unbounded — the Meetings list, a transcript — the pane scrolls and the surrounding chrome does not.

The menu bar menu is a plain `NSMenu`. It has no custom layout, and it holds at most 8 items in any state (PRD FR-5).

## Elevation & Depth

There are two depth levels and no shadows.

Separation is **tonal**: `{colors.surface-card}` sits one step off `{colors.surface-window}`, which is how macOS itself groups content in System Settings. Cards have `{rounded.lg}` corners and **no border** — a stroke plus a tonal step is belt-and-braces and reads as heavier than macOS does.

Shadows appear only where the system puts them: the window frame, menus, popovers. We add none. A drop shadow on a card inside a settings window is the single most reliable tell of a non-native Mac app.

## Shapes

Four radii. `{rounded.sm}` (4px) for small inline elements, `{rounded.md}` (6px, the default) for buttons and banners, `{rounded.lg}` (10px) for cards, `{rounded.full}` for pills and chips.

The logic: radius grows with the size of the thing, so curvature stays visually constant. Pills and chips go fully round to read as *status*, which is how the Done pill signals it is not a button — a 6px-radius "Done" would look pressable, and users would press it.

## Components

**`{components.menubar-icon}`** — the product's most-seen element. Three states whose **silhouettes differ**, not merely their tint: a waveform when Idle, a filled record dot when Recording, a waveform-with-ellipsis when Transcribing. This is a hard requirement (PRD FR-2, NFR-7): the icon must be readable in a greyscale menu bar and by a colour-blind user. Idle renders as a template image so macOS tints it to match the menu bar; Recording and Transcribing render as palette images because their colour carries meaning the system must not override. It never animates while Idle (PRD NFR-3).

**`{components.checklist-row}`** — the borrowed pattern, and the most specified component in the product. Anatomy left to right: leading indicator, then title over one-line subtitle, then a trailing control. A satisfied row shows `{components.pill-done}` and drops to roughly 55% opacity with its title in `{colors.text-secondary}`. An outstanding row shows its ordinal in a ring and a `{components.button-row-action}`. Rows are separated by a hairline inset to the text origin, with none after the last.

The de-emphasis is the whole point: a user opening Setup should see what is left to do, not a wall of green.

**`{components.pill-done}`** — deliberately not a button. Tinted background at low opacity, no border, no hover state, not focusable, fully round. If a user tries to click it, the design has failed.

**`{components.state-banner}`** — how Recording, Transcribing and degraded capture are announced inside the window. Tinted background at 12% opacity with matching foreground. The degraded variant carries a warning glyph because PRD FR-7 forbids silent degradation.

**`{components.speaker-chip}`** — the Local Speaker chip is brand-tinted, Remote Speakers are neutral grey. This single visual difference encodes the product's core structural claim: one of these labels is a fact, the others are inferences. An auto-applied name from a Speaker Profile is prefixed to mark it as inferred (PRD FR-25).

**`{components.backend-row}`** — the Summaries pane's row, and a deliberate copy of the Transcription pane's model row. The user's instruction was that this pane be "similar to the model selection for transcription", so shared anatomy is a requirement and not a convenience: a reader who has learned one row has learned both. It adds one thing the model row never needed — a `Blocked` readiness state — and groups rows under family headings so that *where the work happens* is legible before any individual row is read.

**`{components.blocked-note}`** — what sits where a button would sit, when the app cannot do the thing. It carries the prerequisite and the remedy, and it is not focusable, because a blocked capability must not be selectable. This component exists because of a specific failure: in increment 2 the app knew that Apple Intelligence was switched off, knew that was why summaries were weak, and said none of it — the user had to ask. A reason with no remedy is only half of it, so a remedy that is a command renders as one.

**`{components.egress-marker}`** — a 2px rule in `{colors.state-blocked}`, used on exactly two elements: the "Somewhere else" family heading and the key-entry card. It is the only mark in the product that means *this leaves your Mac*. Its scarcity is its meaning; the moment it appears anywhere else it stops working. Deliberately not `{colors.state-recording}`, which is reserved for Recording alone.

**`{components.progress-download}`** — determinate, always. PRD FR-18 explicitly forbids an indeterminate spinner for a model download, because a 600 MB download behind a spinner is indistinguishable from a hang.

## Do's and Don'ts

**Do**

- Resolve every grey, every text colour, and every background from AppKit semantic colours at render time.
- Let standard controls keep `{colors.control-accent}`, the user's own accent.
- Reserve `{colors.state-recording}` exclusively for Recording.
- Differentiate the three menu bar icon states by silhouette as well as tint.
- State a blocked capability's reason **and** its remedy, in the row itself. If the remedy is a command, show the command.
- Reserve `{components.egress-marker}` for the two elements that involve transmission, and nothing else.
- Mirror the Transcription model row's anatomy in the Summaries pane. A second visual language for the same job is a defect.
- Put card headings outside the card.
- Use monospaced digits for anything that ticks or counts.
- Give every checklist and model row a one-line reason it exists.
- Make download progress determinate.
- Test every pane in light mode, dark mode, and Increase Contrast before calling it done.

**Don't**

- Don't hardcode a hex value for anything the system provides — this is the rule that keeps dark mode free.
- Don't add shadows to cards, or borders on top of a tonal step.
- Don't use `{colors.state-recording}` for errors, destructive actions, or emphasis. It means one thing.
- Don't repaint standard controls with `{colors.brand-accent}`.
- Don't set transcript text in a monospaced font.
- Don't animate the menu bar icon while Idle.
- Don't let a checklist subtitle run to two lines. If it needs two, the copy is wrong.
- Don't give `{components.pill-done}` a hover state, a border, or focus.
- Don't introduce an illustration, an empty-state mascot, a gradient, or a marketing surface. There is no third surface (PRD §10.1).
- Don't add a stats, changelog, or feedback pane. The reference product has them; this one has one user (PRD §10.5).
