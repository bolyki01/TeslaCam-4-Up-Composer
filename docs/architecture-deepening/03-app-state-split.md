# App State Split

Goal: turn the wide app state into feature Modules with better Locality.

Read first:
- `TeslaCam/AppState.swift`
- `TeslaCam/ContentView.swift`
- `TeslaCam/Main.swift`
- `TeslaCam/PlaybackController.swift`
- `TeslaCam/PlatformFileAccess.swift`
- `TeslaCamUITests/TeslaCamUITests.swift`

Problem:
- `AppState` Interface exposes indexing, timeline, playback, telemetry, bookmarks, export planning, debug launch, and errors.
- Views observe the whole state, so small changes ripple.
- UI tests depend on text and incidental structure.
- Security-scoped access and persistence sit beside timeline math.

Target shape:
- `SourceStore`: source URLs, bookmarks, security scope, reload.
- `IndexingStore`: scan state, duplicate summary, health summary.
- `TimelineStore`: coverage, gaps, trim range, selection helpers.
- `PlaybackStore`: current segment, seek, play/pause, telemetry loading.
- `ExportStore`: export settings, output naming, request/plan creation.
- `AppState` becomes orchestration glue during migration.

Steps:
1. Extract pure `TimelineStore` first; keep public methods on `AppState` forwarding to it.
2. Move output naming and `makeExportRequest` into `ExportStore`.
3. Move source bookmark and security scope into `SourceStore`.
4. Move duplicate resolver and health summary into `IndexingStore`.
5. Move telemetry load and overlay formatting into `PlaybackStore`.
6. Change views to observe only the Store they need.
7. Keep old `AppState` properties as compatibility shims until views are migrated.

Tests:
- Existing timeline unit tests move to `TimelineStore`.
- Add output naming tests against `ExportStore`.
- Add source normalization/bookmark tests with a fake persistence Adapter.
- Add playback tests with deterministic clock Adapter.
- Repair UI tests to use stable accessibility identifiers, not visible copy.

Guardrails:
- Split by user workflow, not by framework type.
- Do not rewrite the UI while moving state.
- Keep sample and blank launch modes.
- Keep native and CLI docs aligned only where behavior changes.

