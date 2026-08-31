# PRD Quality Review — Minutes (local-first macOS meeting recorder)

Reviewer: rubric walker, run headless 2026-08-31 against `assets/prd-validation-checklist.md`.
Subject: `prd.md` (48 FRs, 14 sections) + `../briefs/brief-.../addendum.md`.

## Overall verdict

This PRD is implementable and unusually well grounded in verified platform facts — the permission, signing and CoreAudio constraints that normally surface in week two are already load-bearing on the requirements, which is where the document earns its keep. Two things put it at risk: **assumption density is high enough that a fair reading is "one person's coherent guess at another person's product"**, and **48 FRs contradicts the user's own word "small"** unless build order is made explicit. Neither blocks a build, both need to be named rather than smoothed over.

## Decision-readiness — adequate

Decisions are stated as decisions, not hedged: local-only is declared subordinate-to-nothing (§1), Detection is declared unreliable-by-nature with the false-positive cost accepted (FR-12 note), the dual-Backend Metadata design is justified by a *verified* fact about the target machine rather than by defensiveness (§4.6). Trade-offs name what was given up — SM-C1 explicitly prefers a missed huddle to a spurious prompt, SM-C3 explicitly refuses to default to the largest model. That is the good half.

The weak half is that almost every decision was made *for* the user rather than *with* them, and the PRD is honest about this only in §14, at the very end. A reader hitting §4.6's summary/decisions/action-items scope has no way to know it is an interpretation of the word "etc." until 400 lines later. The inline `[ASSUMPTION]` tags added at seven load-bearing sites partly fix this.

### Findings
- **high** Assumption density inappropriate for a green-light PRD (§14) — 17 indexed assumptions and 8 inline tags on a document whose next step is code. The rubric treats this as a blocker at build-authorisation stakes. *Fix:* cannot be fixed by writing; requires the user. Mitigation applied: every assumption is indexed and the largest interpretive leaps are tagged inline, so review is a 5-minute scan of §14 rather than a re-read. Escalate §14 explicitly when the user returns.
- **medium** SM-1's 90% detection target may be unachievable and is stated as if settled (§7) — it rests on `kAudioProcessPropertyIsRunningInput`, which the addendum records as documented-unreliable. *Fix:* mark SM-1 provisional pending the measurement in §13 Q8; do not let a story treat 90% as an acceptance gate.

## Substance over theater — strong

No persona theater: one persona, named, who is the actual user, driving real decisions (§2.1's "stop having to remember" is what produces §4.3 in full). No innovation theater — §"What Makes This Different" in the brief opens by conceding the moat is not technical, and the PRD's differentiation claim is a boundary (local-only) plus one structural trick (dual-stream), both of which are real and both of which are load-bearing on FRs. NFRs carry product-specific thresholds, not adjectives: NFR-4 says memory is flat with respect to Session duration and two models never load concurrently, which is checkable.

§10.5 "Deliberate omissions" is the strongest anti-theater move in the document — it names the reference product's dashboard/stats/changelog panes and says they belong to a product with users, which this one does not have.

### Findings
- **low** §9.3 "Safety and Honesty" is thin relative to its heading — two bullets, both of which restate FR-29 and FR-30. *Fix:* either fold into §9.1 or drop the subsection; the requirements already carry it.

## Strategic coherence — strong

There is a thesis and the PRD bets on it: *the reason this niche is open is that local-only cannot support a business, and the reason it is now buildable is that the transcription, diarization and summarisation models all run on-device.* Features follow from it rather than from convenience — §4.2's dual-stream exists to make §4.5's attribution structural, and §4.6's dual-Backend exists because the thesis forbids a cloud fallback. Prioritisation is not "what's easy first".

Success metrics validate the thesis rather than measuring activity: SM-4 ("still installed after three weeks") is the right primary metric for a personal tool and is refreshingly unfakeable. All three counter-metrics are load-bearing, and SM-C2 (surface area) directly counterweights the document's own worst tendency.

### Findings
- **medium** The thesis is never stated as a thesis (§1) — it is inferable from the Vision's three paragraphs but never written in one sentence. *Fix:* one sentence in §1 naming the bet, so downstream readers inherit it instead of reconstructing it.

## Done-ness clarity — strong

The dimension the rubric says to be unforgiving on, and it holds. All 48 FRs carry a `Consequences (testable)` block; none has fewer than two bullets. Mechanical scan for vague language ("gracefully", "reasonable", "user-friendly", "appropriate", "seamless") returns one hit, in descriptive prose inside a `[NOTE FOR PM]`, not in an acceptance condition. Numbers are attached where numbers are checkable: 15 s detection, 30 s auto-stop, <5 min for a 30-min Session, <2 s for Heuristic Metadata on a 2-hour Transcript, ≥3 h Session, ≥500 Meetings.

Several FRs are notably well-specified because the platform forced precision: FR-42 requires the UI to present system-audio state as *inferred* and forbids claiming certainty macOS cannot provide, and FR-47 turns that same limitation into a testable capability. FR-10's "Detection reads metadata, never audio content" is stated as verifiable by inspection and framed as an invariant.

### Findings
- **medium** FR-22's "correct" is undefined (§4.5) — "a System Stream with a single speaker yields one Remote Speaker label" is testable, but the general accuracy expectation lives only in SM-2's soft "renaming ≤ 3 labels fixes a whole Meeting". *Fix:* acceptable as-is for v1 given §13 Q2 is unresolved, but the story must not claim a diarization accuracy figure that was never specified.
- **low** FR-20's "The queue survives nothing — it need not survive a quit" is a cute formulation that will read as an error to an implementer. *Fix:* state it plainly.

## Scope honesty — strong

§5 Non-Goals does real work — ten entries, several of which pre-empt exactly the drift a small tool suffers ("Not a general audio recorder", "Not a summariser of anything but meetings", "Not automatic recording", which explicitly refuses a convenience). §6.2 gives reasons, not just exclusions, and flags Chrome as a cheap revisit rather than silently omitting it. §10.5 extends the same discipline to UI surfaces. De-scoping is proposed openly: FR-25 is flagged in-place as the first cut candidate with its graceful degradation named.

§12 is the standout: a section invented because no template cluster covered the product's largest delivery risk, stating plainly that rebuilding invalidates consent and that this is the most likely cause of "it stopped working".

### Findings
- **high** 48 FRs is in tension with the user's own framing ("small, and focused") and with SM-C2 (§4, §7) — the count is defensible per-FR but the document never says which requirements constitute a working app versus which are completeness. Left as-is, epics/stories will treat all 48 as equal and the build will not converge in a day. *Fix:* add an explicit build-order / walking-skeleton designation before epics. **Applied — see §6.3.**

## Downstream usability — strong

Glossary present with 20 terms, all used in the body, no orphans. FR IDs 1–48 contiguous, no gaps, no duplicates; UJ-1–4 and NFR-1–8 likewise; all cross-references resolve. Sections survive extraction — FRs reference Glossary terms rather than "see above", so §4.5 pulled out alone still makes sense. Each UJ has a named protagonist carrying context inline, and each is a real scene rather than a restated JTBD.

The addendum split is correct: mechanism detail (the tap sequence, the trap list) sits there, and the PRD references it only where the mechanism is load-bearing on a requirement.

### Findings
- **low** §10.2 maps sidebar groups to FRs, which is traceability the rest of the PRD deliberately avoids (§4 preamble says "skip traceability matrices"). Harmless and useful here, but inconsistent.

## Shape fit — adequate

Correctly shaped as a chain-top PRD feeding UX → architecture → stories, and correctly heavy on FRs for that reason. UJ density (4) is right: this is a single-operator tool, so the rubric would flag more as overhead, but zero would lose the "it offers, you accept" behaviour that is the product's main interaction bet. Success metrics are operational rather than user-funnel, which fits.

### Findings
- **medium** Length overshoots its own stakes calibration (whole document) — §"Length scales with stakes" targets ~5–8 pages for an internal tool; this is roughly 12. The overshoot is concentrated in §4's consequence bullets, which is the useful part, but §9 and §10.4 contain prose that could be halved without information loss. *Fix:* accepted deliberately — the implementer and the reviewer are the same agent working from this document with no ability to ask questions, so precision is cheaper than brevity here. Noted rather than corrected.

## Mechanical notes

Verified programmatically:

- **ID continuity** — FR-1…48 contiguous, unique. UJ-1…4, NFR-1…8, SM-1…7 + SM-C1…C3 all present and unique. No unresolved cross-references.
- **Glossary drift** — 20 terms defined, 0 defined-but-unused. Capitalised Glossary terms used consistently as proper nouns throughout.
- **Assumptions Index roundtrip** — 8 inline `[ASSUMPTION]` tags, 17 index entries. **Deliberately asymmetric**: the index is a superset because the whole document is inference-heavy and tagging all 17 inline would bury the requirements. The seven highest-leverage inferences are tagged at their site. One index entry (§10) explicitly records that it is *not* an assumption but a user directive.
- **`[NOTE FOR PM]`** — 3, all at genuine tensions (FR-25 reliability, Chrome as Watched App, recording-disclosure reminder). None at a safe checkpoint.
- **UJ protagonists** — all 4 named (Niklas), context inline.
- **Section renumbering** after the mid-run insertion of §10 verified: all `§N` in-text references re-pointed, headings sequential 0–14.
