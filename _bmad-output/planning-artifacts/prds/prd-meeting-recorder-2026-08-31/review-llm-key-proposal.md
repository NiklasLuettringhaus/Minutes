---
title: Review — gate summaries on a real LLM, with a user-supplied key
status: final
created: 2026-08-31
reviewer: bmad-review (adversarial, edge-case-hunter)
verdict: split the proposal — accept one half, defer the other
---

# Review: "only enable summaries if we can actually use an LLM"

## The proposal as reviewed

1. Stop producing a summary unless a real LLM is doing it.
2. A **basic** tier: raw transcript, plus title settings, without LLM-derived content.
3. The user may supply an **LLM API key** to get summaries, better titles, and so on.

Content class: a requirements-change proposal — a document that defines behaviour. Lenses run: **adversarial** (always applies) and **edge-case-hunter** (specs with behaviour to trace). Verification-gap was skipped: there is no code for this yet. The editorial lenses were skipped: the task is to vet an idea, not to copy-edit a document.

## Verdict

**Half of this is clearly right and should ship. The other half is the most expensive way to get what you want, and it breaks the product's foundational claim to do it.**

Point 1 is a good instinct that the PRD already argues for. Points 2 and 3 conflate two independent decisions: *when does a summary appear* and *where does the intelligence come from*. Separate them, and the answer changes.

## The finding that should decide this

**You already own the LLM. It is already implemented. It is switched off, not absent.**

- `FoundationModelsBackend` was built in increment 1 (story 7.1, FR-27), is unit-tested, and is wired into the pipeline with guided generation into a typed structure.
- Runtime availability on this machine reports:

  ```
  SystemLanguageModel.default.availability
    = unavailable(appleIntelligenceNotEnabled)
  ```

  That reason matters. It is **not** `deviceNotEligible` and **not** `modelNotReady`.
- The hardware is an **Apple M5 MacBook Pro with 24 GB**, comfortably eligible.
- `com.apple.CloudSubscriptionFeatures.optIn` contains `"opted_out_buddy" = 1` — Apple Intelligence was **declined during Setup Assistant**.

So the sequence of events is: the app was built with an LLM backend; that backend checked availability at run time, correctly found the feature switched off, and fell back to keyphrase extraction exactly as designed; you then read the keyphrase output, correctly judged it not worth having, and proposed buying an LLM.

Turning on Apple Intelligence in System Settings gets you a real LLM summary with **no new code, no key, no recurring cost, and no data leaving the Mac**. Do that before deciding anything else in this proposal.

## Your judgement of the output is correct

The complaint is well-founded, and it is worth being precise about *which* part is bad. Here is a real summary from your notes folder:

> Okay, let's talk about the pricing page redesign. The preaching page is confusing customers, conversion dropped 12% last quarter. So we decided to simplify the pricing page down to three tiers. Can you also check the mobile pricing page layout?

That is not a summary. It is four sentences copied out of the transcript, in order, at 80% of the transcript's own length. For a 30-second recording it is nearly the whole thing. It also says "preaching page" — because Whisper misheard "pricing page", which points at a separate finding below.

The **titles**, by contrast, are fine: "Pricing Page", "Page Redesigned Together". So "better titles" is solving a problem you do not have, while "summaries" is solving one you do.

## Adversarial findings

### 1. NFR-1 and NFR-6 are contradicted, not amended

- **Where:** PRD §8, NFR-1 and NFR-6
- **Problem:** NFR-1 reads "No audio, Transcript, or Metadata is transmitted anywhere, ever." NFR-6 requires the zero-egress claim be "verifiable by an outside observer with a network monitor". A user-supplied key makes the app fail NFR-6 by construction — a network monitor will show transcripts leaving.
- **Fix:** Either retire NFR-1 and NFR-6 explicitly, in writing, with the brief's thesis alongside them; or keep the LLM local. Do not leave them standing while shipping code that violates them.
- **If unaddressed:** The product's strongest claim becomes false, and it stays written down as though it were true.

### 2. The transcript is not the user's alone to send

- **Where:** proposal point 3
- **Problem:** The payload is other people's speech, verbatim, named, timestamped and attributed. Your own company all-hands had 37 participants. None of them agreed to have their words sent to an API vendor.
- **Fix:** If this ships, sending must be per-meeting and opt-in, with the participant list shown at the moment of sending — never a global default that applies to every future meeting.
- **If unaddressed:** One settings toggle silently exports every colleague's words from then on.

### 3. This creates a compliance exposure at a company, not just a personal preference

- **Where:** proposal point 3; PRD §9.1
- **Problem:** Voice, name and content together are personal data. Sending them to a US LLM provider makes that provider a processor, which needs a legal basis and a data processing agreement. An individual employee cannot establish either on colleagues' behalf.
- **Fix:** Default off. Say this plainly in the settings pane. Recommend the local path for work meetings. If the company has an approved vendor with a DPA in place, use that one and say so.
- **If unaddressed:** A personal productivity tool quietly becomes a company data-protection problem.

### 4. Two independent decisions are fused into one

- **Where:** general
- **Problem:** "Gate the summary on a real LLM" and "get the LLM by API key" are separable. The first is clearly right. The second is one of three ways to satisfy it, and the only one with these costs.
- **Fix:** Decide them separately. See the options table.
- **If unaddressed:** Accepting the good half drags in the contentious half for no reason.

### 5. FR-26 becomes unsatisfiable as written

- **Where:** PRD §4.6, FR-26
- **Problem:** FR-26 requires every Meeting to receive a title, a tag set **and** a summary, and states no Meeting is ever left untitled. A basic tier with no summary contradicts it.
- **Fix:** Amend FR-26 so the summary and tags are conditional while the title guarantee survives. Also define what "title setting" means — a manual title, a heuristic title, or a filename template? The proposal says "title setting" without saying which.
- **If unaddressed:** The PRD and the build disagree about whether a meeting can exist without a summary, and the next person to read either one is misled.

### 6. "Better titles" targets the component that is already working

- **Where:** proposal point 3
- **Problem:** Heuristic titles are adequate; heuristic *summaries* and *tags* are not. `preaching-page` as a tag is the visible failure, not `Pricing Page` as a title.
- **Fix:** Scope the LLM to the summary, decisions, action items and tags. Leave title generation alone until it is measured against a real alternative.
- **If unaddressed:** Recurring per-token spend to regenerate output that was already fine.

### 7. The quality ceiling is the transcript, not the summariser

- **Where:** general
- **Problem:** "Preaching page" is a Whisper transcription error. An LLM will write a fluent, confident summary **of the wrong words** — and fluency makes the error harder to catch than the current clumsy extract does.
- **Fix:** Before attributing the weakness to summarisation, re-run a meeting with a stronger transcription model. `large-v3-turbo` is downloaded, and Parakeet is available. Compare word error rate on the same audio first.
- **If unaddressed:** Money and egress spent on a problem whose cause is upstream, and the remaining errors get harder to notice.

### 8. No cost model, against a PRD that names zero cost as a constraint

- **Where:** PRD §9.2
- **Problem:** §9.2 states zero run-time cost is "a design constraint, not an outcome — it is what makes a tool with no business model sustainable." A 60-minute meeting is roughly 8-10k words, call it 12k tokens in and a few hundred out. Several meetings a day is a real recurring bill.
- **Fix:** If this ships, show an estimated token count and cost *before* sending, plus a running monthly total. And renegotiate §9.2 in writing rather than silently breaking it.
- **If unaddressed:** Unbounded silent spend, and a stated constraint quietly abandoned.

### 9. Key storage is unspecified, in an ad-hoc-signed app

- **Where:** proposal point 3
- **Problem:** An API key in `UserDefaults` is plain text readable by any process running as you. This app is ad-hoc signed with no stable identity, which weakens Keychain ACLs too.
- **Fix:** Keychain only, `kSecAttrAccessibleWhenUnlocked`. Never `UserDefaults`, never the notes folder, never a log line. Never echo it back into the UI after saving.
- **If unaddressed:** A credential leak out of a note-taking tool.

### 10. Provenance stops being checkable

- **Where:** PRD §4.6 FR-30, §9.3; note frontmatter
- **Problem:** Every note currently ends its frontmatter with `generated_by: Minutes (local, on-device)`. With a cloud backend that line is false, and FR-30's promise that "a reader can tell whether a summary came from a language model or from keyphrase extraction" now has three answers, not two.
- **Fix:** Extend `MetadataBackendKind` with the provider **and** model identifier, and make the `generated_by` line conditional per note. Old notes must keep saying what was true when they were written.
- **If unaddressed:** Notes assert on-device generation regardless of what happened, and §9.3 — the honesty section — is the thing that breaks.

### 11. No offline or failure path is stated

- **Where:** proposal point 3; PRD §8 NFR-5
- **Problem:** Meetings happen on planes, on captive-portal wifi, and on expired keys. NFR-5 requires that no failure path silently discards a note.
- **Fix:** State it: on unreachable API, 401, 429, quota exhaustion or timeout, the note is still written with heuristic metadata, and the failure is recorded on the meeting. Never block the note on a network call.
- **If unaddressed:** A network error costs the user their meeting notes, which is the one outcome the whole app exists to prevent.

### 12. "If we can actually use an LLM" needs a definition

- **Where:** proposal point 1
- **Problem:** "Can use" collapses three distinct states: no backend available at all; a backend configured but unreachable right now; a backend working. Each needs different UI and a different fallback.
- **Fix:** Define the gate as those three states explicitly before building the conditional summary.
- **If unaddressed:** The gate is implemented against whichever state the developer happened to think of.

### 13. FR-52 shipped hours ago and this proposal already contradicts it

- **Where:** PRD §4.6, FR-52
- **Problem:** FR-52 gives the user a two-way choice — auto, or pin the deterministic backend. Adding a third backend with a key makes the setting a three-way choice with an undefined precedence: Apple Intelligence on **and** a key present, which wins?
- **Fix:** Define precedence before adding the option. The defensible order is explicit user pin, then local model, then cloud.
- **If unaddressed:** Two settings that can disagree, and a summary whose origin depends on undocumented ordering.

### 14. A basic tier with no summary section is better than today, and that is worth saying out loud

- **Where:** proposal points 1-2
- **Problem:** This is a finding in the proposal's favour that the proposal undersells. §9.3 already requires that absence be represented honestly and never as invented content. An empty summary section is *more* compliant with the PRD than the current extract, which reads like a summary and is not one.
- **Fix:** Ship the gate on its own merits, immediately, independent of any LLM decision. It improves the product today.
- **If unaddressed:** A good change waits on an unrelated and much larger decision.

## Edge-case findings

Unhandled paths in the proposal as specified. Handled paths are omitted.

| Path | Missing handling |
| --- | --- |
| Key present but malformed or revoked | No stated behaviour. Must fall back and record the failure, not retry silently. |
| Quota exhausted partway through a queue of meetings | FR-20 processes serially; some meetings get LLM metadata and some do not, with no marker distinguishing them. |
| Key removed after notes were generated with it | Existing notes' provenance must remain truthful; nothing says it is preserved. |
| Apple Intelligence enabled *and* a key present | Precedence undefined. See adversarial finding 13. |
| FR-52 "pin heuristic" set *and* a key present | Two settings that contradict each other. |
| Empty transcript — the silent-recording and `[BLANK_AUDIO]` case, already observed | Sends a paid request containing nothing. Must short-circuit. |
| Transcript containing only your own voice | Still exports a recording of you talking to yourself; arguably fine, but unstated. |
| Zero-duration or one-second recording — already observed twice on this machine | Same as empty: no gate specified. |
| Meeting longer than the provider's context window | FR-27 defines chunk-and-combine for the local model; nothing says the cloud path reuses it, and cost scales with the chunking strategy. |
| Provider deprecates the model recorded in a note's frontmatter | The stored identifier becomes unresolvable, and provenance degrades to a string nobody can check. |
| Notes folder inside iCloud Drive | A second egress path exists that the privacy section never disclosed; adding a first one makes the omission worse. |
| A detection-triggered meeting the user accepted quickly | Consent to *record* is not consent to *transmit*; the prompt in FR-12 says nothing about sending. |
| Non-English meeting | The transcription model and the LLM have different language competence; no stated behaviour when they disagree. |

## Recommendation

Split the proposal into two decisions and take them in order.

### Decision A — gate the summary on a real LLM: **accept**

Ship it independently and soon. When no LLM is producing metadata, write the transcript, the heuristic title and the tags, and **omit the summary, decisions and action items sections entirely** rather than filling them with sentence extracts. §9.3 already asks for this. It makes the product more honest today, at no cost, whatever you decide about Decision B.

One amendment needed: FR-26 must be reworded so the title guarantee survives while the summary becomes conditional.

### Decision B — where the intelligence comes from

| Option | Quality | Egress | Recurring cost | Work | NFR-1 |
| --- | --- | --- | --- | --- | --- |
| **1. Enable Apple Intelligence** | Good | None | None | **Already built** | Intact |
| **2. Bundle a local model** (MLX, Qwen3-class 4-8B) | Good to very good | None | None | Moderate; 2-5 GB download | Intact |
| **3. User-supplied cloud key** | Best | **Every transcript** | Per meeting, forever | Large: consent, DPA, Keychain, cost UI, provenance, offline paths | **Broken** |

**Do option 1 today.** It is a switch in System Settings, the code path already exists and is tested, and it costs nothing. Then look at a real LLM summary of a real meeting and decide whether you still want anything more.

**Option 2 if option 1 disappoints.** It keeps every claim in the PRD true, works with Apple Intelligence off, and is a one-time download rather than a recurring bill.

**Option 3 only if both fail**, and then only with the fourteen findings above answered — particularly consent (2), compliance (3), provenance (10) and the offline path (11) — and with NFR-1, NFR-6 and §9.2 formally retired rather than quietly contradicted.

## What to do before any of this

Re-transcribe one meeting with `large-v3-turbo` and compare it against the `base` output you have been reading. "Preaching page" is not a summarisation failure, and if the transcript is wrong then every option in Decision B produces a confident, fluent, wrong summary. Fixing the input is cheaper than any of the three options and improves all of them.
