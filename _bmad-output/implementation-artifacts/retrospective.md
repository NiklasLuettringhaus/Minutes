---
title: Retrospective — Minutes, autonomous BMAD run
date: 2026-08-31
mode: headless (user away for the whole run)
verdict: accept with three items requiring the user
---

# Retrospective — autonomous BMAD run

## What the run produced

| Artifact | Substance |
|---|---|
| Product brief + addendum | Scope, thesis, and verified platform research |
| PRD | 48 FRs with testable consequences, 8 NFRs, build-order tiers, 17 indexed assumptions |
| UX spines | `DESIGN.md` (34 resolving tokens) + `EXPERIENCE.md` (5 key flows) + one key-screen mock |
| Architecture spine | 21 ADs, lint-clean, two reviewer passes |
| Epics | 7 epics, 43 stories, all 48 FRs covered exactly once (verified programmatically) |
| Sprint status | 43 stories tracked |
| Code | ~5,000 lines of Swift, 9 commits, 33 tests, a signed runnable `.app` |
| Reviews | Version-verification, adversarial, and code review — 5 defects found and fixed |

## What worked, and is worth repeating

**Spiking before writing the architecture was the single highest-value decision.**
Four spikes ran against real APIs before any AD was committed. They produced three
corrections to published documentation, one of which — `AudioDeviceCreateIOProcIDWithBlock`
deadlocking on a tap-backed aggregate device — would have been an unexplainable hang
discovered mid-build, with no crash log to work from. The architecture then encoded
each finding as a rule with the reason attached, so the build could not regress into it.

**Verifying by running, not by reading.** Two bugs were only findable by executing
the real thing: models landing in `~/Documents` (which also broke the setup
checklist's readiness check), and Whisper hallucinating `"Thank you."` over a silent
microphone — inventing a participant, which quietly undermines the product's core
attribution claim. Neither is visible in code review.

**The adversarial architecture pass earned its keep.** The original 17 ADs were
strong on OS boundaries — where the spikes had forced precision — and thin on
ownership of *persisted* state. Constructing two compliant-but-incompatible
components found four holes, the worst of which would have let a mic-only recording
be presented as a full one.

**The readiness gate was not a rubber stamp.** It caught that no story built the
main window and no story owned the meeting record — both hard dependencies for a
dozen later stories. Fixing them before the build cost minutes; after, it would
have meant reworking Epic 2 and Epic 5.

**Building the self-test as a product feature, not scaffolding.** The Test Playground
exists because macOS offers no API to query system-audio permission. Making it a
real feature meant the same code path could verify the build headlessly — which is
the only reason an autonomous run could confirm the pipeline at all.

## What went wrong, and what it cost

**I wrote a deadlock into my own test harness.** `sem.wait()` on the main thread
while the work was `@MainActor`. Cost one debugging cycle, and it is exactly the
same class of bug as the CoreAudio deadlock I had just spent four spike iterations
finding — I should have recognised it faster.

**I trusted a published guide over the SDK.** The article recommending the block-based
IOProc variant was recent, specific, and wrong. The architecture now says to prefer
SDK headers and working sample repos over web summaries; that rule was learned the
expensive way.

**I invented a product name.** "Kokoro" in the first draft, replaced with "Minutes"
during the review pass for being arbitrary and exotic for a utility. Reasonable to
name an unnamed thing, but it should have been flagged as a decision from the start
rather than presented as settled.

**Type-checker timeouts from over-chained expressions.** Three functions in the
heuristic backend had to be rewritten with explicit types. Self-inflicted; a habit
worth breaking.

**The interactive skills fought the mandate.** `bmad-create-epics-and-stories` and
`bmad-build` are menu-gated with mandatory human checkpoints and no headless mode.
Running "100% autonomously" meant auto-confirming those gates and, for the build,
working at epic-wave granularity rather than 43 separate spec-writing loops — which
would have consumed the day producing specs instead of code. That was a judgment
call, and it is logged rather than hidden.

## Action items

| # | Item | Owner | Condition |
|---|---|---|---|
| 1 | Join a real Slack huddle and confirm the Detection Prompt appears | Niklas | Blocks trusting detection at all; PRD open question 8 |
| 2 | Review PRD §14 (17 assumptions), especially reading "etc." as summary/decisions/actions | Niklas | Before any further building on the PRD |
| 3 | Decide whether an Apple Developer certificate is obtainable | Niklas | Would remove the rebuild-revokes-consent problem entirely |
| 4 | Calibrate the Speaker Profile threshold (currently 0.45, a guess) against real colleagues | Niklas + follow-up | After a week of real meetings |
| 5 | Look at every UI pane once — none has been seen by a human | Niklas | First launch |
| 6 | Add Chrome as a Watched App | follow-up | Only once detection is proven for Slack and Teams |
| 7 | Confirm audio survives an AirPods switch mid-recording | follow-up | PRD open question 7 |
| 8 | Turn on Apple Intelligence to light up the better metadata path | Niklas | Optional; heuristic backend covers it meanwhile |

## Honest assessment

The product's hard parts work: dual-stream capture, on-device transcription,
diarization that got 6/6 lines right across two models, and a Markdown file that is
useful without editing. The risk is concentrated in exactly one place — whether
detection fires during a real call — and in the gap between "compiles and is
covered by tests" and "a human has looked at it". Eleven of 43 stories are marked
`done` on evidence; the other 32 are marked `review` rather than `done`, which is
the accurate state and not a formality.
