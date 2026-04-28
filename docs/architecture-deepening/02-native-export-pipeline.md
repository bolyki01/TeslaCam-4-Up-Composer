# Native Export Pipeline

Goal: make export reliable, fast, and testable through a small ExportPlan Interface.

Read first:
- `docs/superpowers/specs/2026-04-26-fast-native-export-design.md`
- `TeslaCam/NativeExportController.swift`
- `TeslaCam/Models.swift`
- `TeslaCam/AppState.swift`
- `TeslaCamTests/TeslaCamTests.swift`

Problem:
- `NativeExportController` owns UI state, preflight, security scope, temp dirs, logging, frame selection, composition, and writing.
- The render Implementation uses per-frame image generation and synchronous waits.
- Tests must drive a large Module instead of a focused Interface.
- `ExportRequest` is a bag of invariants: dates, seconds, cameras, partial counts, layout choice.

Target shape:
- `ExportPlan` is the validated Interface for export work.
- `ExportPreflight` owns write access, disk checks, encoder ceilings, and warnings.
- `NativeRenderPipeline` owns AVFoundation composition and writing.
- `ExportJobStore` owns snapshots, log events, history, retry, cancel state.
- File access and clock behavior sit behind small Adapters only where tests need variation.

Steps:
1. Add `ExportPlan` built from `ExportRequest`; validate non-empty sets, trim dates, enabled cameras, and canvas size.
2. Move preflight checks into `ExportPreflight`; keep messages stable for UI.
3. Move `TimelineFrameLayout` and size probing out of the controller or behind a layout Module.
4. Replace per-frame `AVAssetImageGenerator` export with composition/reader/writer pipeline from the approved spec.
5. Replace `runOnMain` with normal main-queue publishing.
6. Make log events structured at the source, then render text for UI.
7. Keep `NativeExportController.export(request:)` as the compatibility shell until callers migrate.

Tests:
- Unit test `ExportPlan` validation with empty range, hidden cameras, HW4 canvas, ProRes escape hatch.
- Unit test preflight for bad output, low disk through Adapter, and HEVC size ceiling.
- Unit test layout invariants: canvas size, tile size, HW3, HW4, mixed.
- Integration test a tiny HW4 export and assert output dimensions.
- Run native unit tests before UI tests.

Guardrails:
- Do not reintroduce CLI-only export into mac app.
- Do not downscale source tiles.
- Keep current presets and output extensions stable.
- Preserve cancel, retry, reveal output, reveal log.

