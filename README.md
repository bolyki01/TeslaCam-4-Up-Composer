# Teslacam

Teslacam ships two developer surfaces from one repo:

Built by [Magrathean UK](https://magrathean.uk).

- a native macOS app for browsing and exporting TeslaCam footage on Apple Silicon Macs
- a separate cross-platform Python CLI for scripted or interactive exports on macOS, Linux, and Windows

The native app uses the shipping Swift export path. The CLI keeps the portable ffmpeg-based workflow.

## Canonical docs

- [Agent guide](./AGENTS.md)
- [Runbook](./RUNBOOK.md)

## Repo map

- `TeslaCam/` - macOS app source, native export, playback, telemetry, and resources
- `TeslaCamTests/` and `TeslaCamUITests/` - native test coverage
- `teslacam_cli/` - Python CLI package
- `tests/` - CLI unit and integration tests
- `script/test_native.sh` - native build-and-test lane
- `tools/TeslaCamOverlayGenerator.swift` - local utility built on the app parser
- `_legacy/` - old path, kept as reference only
- `TeslaCam/Resources/LICENSES.md` - kept third-party license asset

## Requirements

- Python 3.9+
- `ffmpeg` and `ffprobe`
- `libx265` support for lossless or CRF 6 HEVC CLI export
- Xcode on macOS for the native app

## Quick start

Primary CLI:

```sh
./teslacam-cli
```

Compatibility adapters to the same Python module:

```sh
python3 teslacam.py
./teslacam.sh
```

## Domain parity and dry runs

The app and CLI share a fixture-backed domain contract for timestamp parsing, camera normalization, duplicate handling, layout selection, and output conflict naming. See `docs/domain-contract.md`. Shared fixtures live under `fixtures/domain/cases`.

The CLI can emit a machine-readable dry-run manifest without rendering:

```sh
teslacam-cli /path/to/TeslaCam --dry-run-json manifest.json
teslacam-cli /path/to/TeslaCam --dry-run-json -
```

## Architecture

- Domain behavior is fixture-backed and documented in `docs/domain-contract.md`.
- The CLI builds a pure run plan, then hands rendering and user output to adapters.
- The native app builds a validated export plan, runs preflight, and keeps export status observable.
- Camera layout is a shared contract: index, preview, native export, and CLI dry runs must agree.
- App state is split around timeline, export, playback, and UI-facing state so tests can cover logic without driving the full app.

## Notes

- The App Store app does not bundle `ffmpeg`.
- Native export is the shipping app path.
- `./teslacam-cli` is the primary CLI command; wrappers are compatibility adapters.
- `_legacy/` is non-canonical and should not drive new work.

