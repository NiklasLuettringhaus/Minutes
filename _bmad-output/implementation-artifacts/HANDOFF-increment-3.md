---
title: Handoff — increment 3, Summarisation Intelligence
date: 2026-08-31
state: planned, not implemented
---

# Handoff: increment 3 (Epic 9)

Planning is complete through sprint status. **No implementation code has been written.** This file exists so implementation can start from a cleared context without re-deriving anything.

## Read these, in this order

1. `_bmad-output/planning-artifacts/spikes/spike-local-llm-2026-08-31.md` — what was measured, and the blocker. **Read first; it changes what is worth building.**
2. `_bmad-output/planning-artifacts/prds/prd-meeting-recorder-2026-08-31/review-llm-key-proposal.md` — why the key is last and not first.
3. `_bmad-output/planning-artifacts/epics.md` § Epic 9 — the 7 stories with acceptance criteria.
4. `_bmad-output/planning-artifacts/architecture/architecture-meeting-recorder-2026-08-31/ARCHITECTURE-SPINE.md` — AD-22 … AD-27, and the amendments to AD-12 and AD-13.
5. `_bmad-output/planning-artifacts/prds/prd-meeting-recorder-2026-08-31/prd.md` § 4.10 and § 6.3 Tier 5.
6. `_bmad-output/planning-artifacts/ux-designs/ux-meeting-recorder-2026-08-31/EXPERIENCE.md` § Backend row, § Capability readiness, § KF-6, § KF-7.

## Blocked before a single line is worth writing

```
$ xcodebuild -showComponent MetalToolchain
Status: uninstalled
```

`mlx-swift` ships no prebuilt metallib; it compiles one at build time from `Source/Cmlx/mlx-generated`. Without the toolchain, MLX fails at runtime with `Failed to load the default metallib` and **cannot generate a single token**. The fix is one command and a multi-gigabyte download, and it is the user's to run:

```
xcodebuild -downloadComponent MetalToolchain
```

Stories 9.1, 9.2, 9.3, 9.4 and 9.6 can all be built without it. Story 9.5 cannot be *verified* without it.

## Build order (do not reorder)

| # | Story | Why here |
| --- | --- | --- |
| 1 | **9.1** no summary unless real | Standalone, zero dependencies, removes a misleading artefact today |
| 2 | **9.2** `Capability` type | The pane cannot be honest on top of a `Bool` |
| 3 | **9.3** precedence function | Pure, unit-testable, decides what the pane displays |
| 4 | **9.4** the Summaries pane | Needs 9.2 and 9.3 |
| 5 | **9.6** prerequisites | **Must precede 9.5** — it is what stops a 3 GB download on a machine that cannot run the result |
| 6 | **9.5** local model | The point of the increment |
| 7 | **9.7** remote key | Optional. Build only if 9.5's measured quality proves insufficient |

## Verified facts — do not re-research

| Fact | Value |
| --- | --- |
| Package | `https://github.com/ml-explore/mlx-swift-examples.git` exact `2.29.1` |
| Products | `MLXLLM`, `MLXLMCommon` |
| Transitive core | `mlx-swift` `0.31.6`, `swift-transformers` 1.0.x, `GzipSwift` 6.0.1 |
| Dependency conflicts | None. `Package.resolved` pins only argmax, fluidaudio, swift-argument-parser — argmax vendors its own |
| Compiles here | Yes: 485 modules, 82 s cold, `swift-tools-version: 6.0` + `.swiftLanguageMode(.v5)` |
| Download API | `HubApi(downloadBase:)` honours an explicit root — verified writing to `~/Library/Application Support/Minutes/models/llm` |
| Progress | `progressHandler` fires continuously (verified 10 → 100 %) — determinate progress is available, so a spinner is a regression |
| Generation API | `LLMModelFactory.shared.loadContainer(hub:configuration:progressHandler:)` → `container.perform { ctx in }` → `ctx.processor.prepare(input: .init(prompt:))` → `MLXLMCommon.generate(input:parameters:context:)` → `AsyncStream`, items carry `.chunk` |
| Registry | `LLMModelFactory.shared.modelRegistry.models` enumerates known configurations — the live source for AD-13 |
| Candidate sizes (fetched, not estimated) | `Qwen3.5-4B-MLX-4bit` 3.03 GB · `Llama-3.1-8B-Instruct-4bit` 4.52 GB · `Qwen3.5-9B-MLX-4bit` 5.95 GB · `Qwen3-14B-4bit` 8.31 GB |
| Apple backend status | `unavailable(appleIntelligenceNotEnabled)` — eligible M5/24 GB, declined at Setup Assistant (`opted_out_buddy = 1`) |

**Ecosystem warning:** `Qwen3.5`, `Qwen3.6` and `Qwen3.8` conversions all exist on `mlx-community` now. Any hardcoded model list will be wrong. Build it from the registry (AD-13).

## Two build-script changes required

Both in `Scripts/build-app.sh`, and neither is optional for story 9.5:

1. Copy SPM resource bundles (`*.bundle` from the build products directory) into `Minutes.app/Contents/Resources/`. The script currently copies only `Info.plist` and `AppIcon.icns`, so a shipped app would hit the metallib error even on a machine where the build succeeded.
2. Expect the binary to grow substantially — MLX links a large Metal backend.

## Unmeasured — do not assert

- **Summary quality from a 4-bit local model.** Zero tokens generated. PRD §13 Q13. This is the question the increment rests on.
- **Throughput.** Unknown. Use the FR-47 Test Playground pattern to measure rather than estimating.
- **Peak memory for a 9B model plus KV cache on a two-hour transcript.** NFR-4 and AD-26 depend on it. PRD §13 Q14.

## State of the working tree

Everything through increment 2 is built, installed at `/Applications/Minutes.app`, and running. 67 tests pass. `--doctor` reports the live state. Nothing in increment 3 is implemented.

Known outstanding from earlier increments, unchanged by this planning:

- FR-49's menu bar timer text has never been seen by a human — `MenuBarExtra` label rendering is unverified from a terminal.
- 5 of 8 meetings show *Note missing* (dev-sandbox artefacts). *Rewrite note* fixes each.
- The Speaker Profile 0.45 threshold is still uncalibrated.
