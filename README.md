# Teslacam

Teslacam ships two developer surfaces from one repo:

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

```sh
./teslacam-cli
python3 teslacam.py
```

## Domain parity and dry runs

The app and CLI share a fixture-backed domain contract for timestamp parsing, camera normalization, duplicate handling, layout selection, and output conflict naming. See `docs/domain-contract.md`. Shared fixtures live under `fixtures/domain/cases`.

The CLI can emit a machine-readable dry-run manifest without rendering:

```sh
teslacam-cli /path/to/TeslaCam --dry-run-json manifest.json
teslacam-cli /path/to/TeslaCam --dry-run-json -
```

## Notes

- The App Store app does not bundle `ffmpeg`.
- Native export is the shipping app path.
- `_legacy/` is non-canonical and should not drive new work.
