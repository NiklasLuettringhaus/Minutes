---
title: Spike — a downloadable local LLM for summarisation
date: 2026-08-31
status: complete
verdict: feasible, with one hard prerequisite that is not currently met
---

# Spike: local LLM for summarisation (MLX)

Run before writing requirements, because "allow local download" is only a requirement if it works on this machine. Everything below was executed, not read about.

## Verdict

**Feasible.** The runtime compiles, links, downloads models and reports progress on this machine. **One hard prerequisite is missing** and must be installed before any of it can run.

## The blocker

```
$ xcodebuild -showComponent MetalToolchain
Build Version: 17F109
Status: uninstalled
```

At runtime this surfaces as:

```
MLX error: Failed to load the default metallib. library not found
  at .../mlx-swift/Source/Cmlx/mlx-c/mlx/c/stream.cpp:115
```

`mlx-swift` ships **no prebuilt metallib** — `Source/Cmlx/mlx-generated/` holds shader *sources*, compiled at build time by the Metal compiler. Xcode 26.6 is installed and `xcrun -f metal` resolves, but `xcrun -f metallib` does not, because the Metal Toolchain is a separately downloadable component.

**Fix, one command (multi-GB download, user's call):**

```
xcodebuild -downloadComponent MetalToolchain
```

Until that is installed, the local-LLM option cannot run at all — not slowly, not degraded. It is a build-time prerequisite, not a runtime fallback.

## Second consequence: the app bundle needs the metallib

Once built, `mlx.metallib` is an SPM resource bundle, and `Scripts/build-app.sh` currently copies no resource bundles into `Minutes.app` — only `Info.plist` and `AppIcon.icns`. The build script must copy `*.bundle` from the build products directory into `Minutes.app/Contents/Resources/`, or the shipped app hits the same error the spike did even on a machine where the build succeeded.

## What was verified working

| Fact | Evidence |
| --- | --- |
| `ml-explore/mlx-swift` current release | `0.31.6` (via `git ls-remote --tags`, sorted with `sort -V`) |
| `ml-explore/mlx-swift-examples` current release | `2.29.1` |
| Products needed | `MLXLLM`, `MLXLMCommon` |
| Compiles under this toolchain | Yes — 485 modules, 82s cold, `swift-tools-version: 6.0` with `.swiftLanguageMode(.v5)`, macOS 26.6 |
| Transitive additions | `swift-transformers` 1.0.x, `GzipSwift` 6.0.1 |
| Conflict with existing deps | None. `Package.resolved` currently pins only `argmax-oss-swift`, `fluidaudio`, `swift-argument-parser` — argmax vendors its own dependencies, so there is no `swift-transformers` version to collide with |
| Download into our own directory | Yes — `HubApi(downloadBase:)` honoured `~/Library/Application Support/Minutes/models/llm`, so FR-18's storage rules extend cleanly |
| Download progress reporting | Yes — the `progressHandler` fired continuously, 10% → 100%. A real progress bar is possible, unlike the Whisper path where progress is coarse |
| Model load and generate API | `LLMModelFactory.shared.loadContainer(hub:configuration:progressHandler:)` → `container.perform { ctx in ... }` → `ctx.processor.prepare(input: .init(prompt:))` → `MLXLMCommon.generate(input:parameters:context:)` returning an `AsyncStream` whose items carry `.chunk`. Streaming output is available, which matters for a progress indication on a long transcript |
| Built-in model registry | `LLMModelFactory.shared.modelRegistry.models` enumerates known configurations, e.g. `mlx-community/Llama-3.2-3B-Instruct-4bit`, `mlx-community/Qwen3-4B-4bit` — usable as a curated starting list the way `WhisperKit.recommendedModels()` is |

**Not verified:** actual generation quality or speed, because the Metal blocker prevented a single token from being produced. Any throughput or quality claim in the PRD must be marked unmeasured until the toolchain is installed and a real meeting is summarised.

## Candidate models, real sizes

Fetched from the Hugging Face API, not estimated. Download counts included as a crude proxy for "is this a maintained, widely used conversion".

| Model | Weights | Downloads |
| --- | --- | --- |
| `mlx-community/Qwen3.5-2B-MLX-8bit` | 2.66 GB | 1,946 |
| `mlx-community/Qwen3.5-4B-MLX-4bit` | 3.03 GB | 27,655 |
| `mlx-community/Llama-3.1-8B-Instruct-4bit` | 4.52 GB | 185,139 |
| `mlx-community/Qwen3.5-9B-MLX-4bit` | 5.95 GB | 26,474 |
| `mlx-community/Qwen3-14B-4bit` | 8.31 GB | 82,455 |

Note for the model catalogue: the ecosystem has moved past what I would have assumed. `Qwen3.5`, `Qwen3.6` and `Qwen3.8` families all exist on `mlx-community` now, so the curated list must be built from a live query at implementation time rather than from a hardcoded guess — exactly the mistake made with the Whisper model IDs in increment 1.

## Memory implication

NFR-4 says two models never load concurrently and peak memory must not risk pressure on a 24 GB machine. Summarisation runs *after* transcription in the pipeline, so the constraint is satisfiable — but the pipeline must unload the transcription model before loading the LLM, which is an explicit sequencing requirement rather than an accident. A 4-bit 9B model is roughly 6 GB resident plus KV cache that grows with transcript length; a two-hour meeting is the case to bound.

## Recommendation for the requirements

1. Treat the Metal Toolchain as a **setup prerequisite with its own checklist row**, detected at run time, with the exact command to fix it. It is the same shape as the Apple Intelligence row: a capability the app cannot install for the user, and must therefore explain rather than hide.
2. Build the curated local-model list from a live registry query, never a hardcoded list.
3. Do not state throughput or quality numbers until measured. The Test Playground pattern from FR-47 is the right place to measure them.
