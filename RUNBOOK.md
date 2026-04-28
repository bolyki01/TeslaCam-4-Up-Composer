# Runbook

## CLI

Primary command from the repo root:

```bash
./teslacam-cli
```

Compatibility adapters to the same Python module:

```bash
python3 teslacam.py
./teslacam.sh
```

Optional install:

```bash
pip install .
teslacam-cli
```

Useful Python lanes:

```bash
python3 -m unittest tests.test_scanner tests.test_layouts tests.test_timing tests.test_cli tests.test_domain_contract
python3 -m unittest discover tests
python3 -m unittest tests.test_integration
```

Domain dry-run comparison:

```bash
teslacam-cli /absolute/path/to/TeslaCam --dry-run-json manifest.json
```

The integration test expects working `ffmpeg` fixtures.

## Native macOS app

Use `script/test_native.sh` for the native lane. It resolves `TESLACAM_BUILD_ENV` first and falls back to `/Users/bolyki/dev/source/build-env.sh`, then runs build-for-testing plus the app and UI test targets.

```bash
script/test_native.sh
```

## Architecture checks

- Keep domain changes covered by shared fixtures and `docs/domain-contract.md`.
- Keep CLI planning pure; rendering and human output stay behind adapters.
- Keep native export behind validated plan plus preflight.
- Keep camera layout changes reflected in scan manifests, preview, native export, and CLI dry-run output.
- Keep derived build folders ignored and out of git.

## Debug flow

- `TESLACAM_DEBUG_SOURCE=/absolute/path/to/TeslaCam` injects a source in Debug builds.
- `TESLACAM_UI_TEST_MODE=blank` gives empty onboarding.
- `TESLACAM_UI_TEST_MODE=sample` gives a sample timeline.
- Use the in-app `Show Log` action after failed or cancelled exports.
- When gap or layout logic changes, verify true-time spacing, visible gap preview, duplicate handling, and HW4 camera detection.

## Release checks

- Cold launch starts on onboarding until a source folder is chosen.
- The loaded timeline shows exact range, export preset, duplicate policy, and per-camera controls.
- Existing-output exports choose a unique filename instead of clobbering.
- HW4 names `left`, `right`, `left_pillar`, and `right_pillar` map to the centered 3x3 layout.
- Native export stays the only shipping mac app path.
- Debug builds show recent debug events for fast triage.

## Guardrails

- `TeslaCam/Resources/LICENSES.md` and `TeslaCam/Resources/ffmpeg_bin/` are support assets, not dev notes.
- The CLI stays dependency-light and cross-platform.
- `./teslacam-cli` is the active CLI entrypoint; `teslacam.py` and `teslacam.sh` are adapters.
- `teslacam_legacy_macos.sh` is legacy reference only, not the native app export path.
- Keep app and CLI output behavior aligned for duplicate handling, time trimming, and layout selection.
