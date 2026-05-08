# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack

Two surfaces, one repo:

- **Native macOS app** — Swift / SwiftUI (`TeslaCam.xcodeproj`, sources in `TeslaCam/`). Shipping export path. Uses AVFoundation + Metal renderer + native HEVC/ProRes export. Recent in-progress work extends to an iPad target (`IPadMain.swift`, `MetalPlayerView_iPad.swift`, `TeslaCam_iPad.entitlements`).
- **Python CLI** — `teslacam_cli/` package, `pyproject.toml`, no Python runtime deps. Requires `ffmpeg` / `ffprobe`, plus `libx265` for HEVC presets. Cross-platform (macOS / Linux / Windows).

## Build & test

Native (canonical lane — runs unit + UI tests):

```bash
script/test_native.sh
```

It sources `$TESLACAM_BUILD_ENV` (defaulting to `/Users/bolyki/dev/source/build-env.sh`), then `xcodebuild build-for-testing` + `test-without-building` against `TeslaCamTests` and `TeslaCamUITests`. A bare `xcodebuild ... build` works for compile-only.

Python CLI (this project uses `unittest`, **not pytest**):

```bash
pip install -e . --break-system-packages          # editable install, exposes teslacam-cli
python3 -m unittest discover tests                # full suite
python3 -m unittest tests.test_domain_contract    # single module
python3 -m unittest tests.test_cli.SomeCase.test_x  # single test
```

The integration test (`tests.test_integration`) requires working `ffmpeg`. CLI entry: `teslacam_cli.cli:main`. From repo root, `./teslacam-cli` is the primary command; `teslacam.py` and `teslacam.sh` are compatibility adapters to the same module.

Dry-run manifest (no rendering, used for parity checks):

```bash
teslacam-cli /absolute/path/to/TeslaCam --dry-run-json manifest.json
```

## Domain contract — the load-bearing invariant

`docs/domain-contract.md` + JSON cases under `fixtures/domain/cases/` are the source of truth for behavior shared between the app and CLI: clip filename parsing (`YYYY-MM-DD_HH-MM-SS-CAMERA.{mp4,mov}`), camera token normalization, duplicate policies (`merge-by-time` / `prefer-newest` / `keep-all`), layout selection (`auto` / `legacy4` / `sixcam`), and output conflict policy (`unique` / `overwrite` / `error`). Both Swift (`TeslaCam/Indexer.swift`, `TeslaCam/Models.swift`) and Python (`teslacam_cli/scanner.py`, `teslacam_cli/domain_contract.py`, `teslacam_cli/layouts.py`) must keep the fixture cases green. When you change shared behavior, update the contract doc and the fixtures together.

Canonical cameras: `front, back, left_repeater, right_repeater, left, right, left_pillar, right_pillar`. Auto layout picks 6-cam when any HW4 camera (`left`/`right`/`*_pillar`) is present, else 4-cam. Missing expected cameras render as black; present cameras outside the chosen profile are listed as "hidden", not silently regridded.

## Architecture invariants

- **Native export is the shipping app path.** Do not reintroduce CLI-only / ffmpeg-only export assumptions into the mac app — the App Store build does not bundle ffmpeg. Native presets are intent labels (Evidence HEVC, Fast Review HEVC, Social 25 MB HEVC, Proxy HEVC, Master ProRes) backed by `NativeExportController.swift`.
- **CLI planning stays pure.** `teslacam_cli/cli.py` builds a `RunPlan`; rendering and human output go through adapters (`composer.py`, `ffmpeg_tools.py`, render reporters). Don't fold I/O back into planning.
- **App state is split.** `AppState.swift` separates timeline / export / playback / UI-facing state so logic is testable without driving the full app. `ExportPlan` in `NativeExportController.swift` validates before any preflight or render.
- **Camera-track cuts** layer over the base grid in native preview/export only. The portable CLI does not currently apply them.
- **HW3/HW4 mixed inputs** use the 6-cam centered grid and record HW3 repeaters as hidden — never silently change the grid.

## Project rules (from AGENTS.md)

- Keep macOS app and Python CLI docs aligned — `README.md`, `RUNBOOK.md`, `docs/domain-contract.md`.
- `_legacy/` and `teslacam_legacy_macos.sh` are reference only. Do not modify unless the task explicitly targets them.
- `TeslaCam/Resources/LICENSES.md` and `TeslaCam/Resources/ffmpeg_bin/` are vendor/runtime assets — touch only for licensing or packaging tasks.
- **No Sentry / external crash telemetry.** Keep diagnostics local. (The repo-level instruction overrides the global Sentry MCP guidance for this project.)

## Debug env vars

- `TESLACAM_DEBUG_SOURCE=/abs/path/to/TeslaCam` — inject a source folder in Debug builds (skips onboarding).
- `TESLACAM_UI_TEST_MODE=blank` — empty onboarding for UI tests.
- `TESLACAM_UI_TEST_MODE=sample` — sample timeline for UI tests.
- `TESLACAM_BUILD_ENV=/path/to/build-env.sh` — override the sourced build env for `script/test_native.sh`.
- In the running app, the **Show Log** action surfaces recent debug events for triage after a failed/cancelled export.
