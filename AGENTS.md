# AGENTS.md

Read in this order:

- [README](./README.md)
- [Runbook](./RUNBOOK.md)
- [Domain contract](./docs/domain-contract.md) for shared Swift/Python behavior
- [pyproject.toml](./pyproject.toml)
- `TeslaCam.xcodeproj`
- `.github/workflows/` when CI behavior matters

The previously referenced parent files `/Users/bolyki/dev/source/AGENTS.md`
and `/Users/bolyki/dev/source/AGENT_INDEX.md` are not present in this checkout.
Do not stop for them; use this file as the repo guide.

## Repo map

- `TeslaCam/` - SwiftUI macOS app, native export, playback, telemetry, resources.
- `TeslaCamTests/`, `TeslaCamUITests/` - native test targets.
- `teslacam_cli/` - dependency-light Python CLI package.
- `tests/` - Python `unittest` suite.
- `fixtures/domain/cases/` - shared Swift/Python domain fixtures.
- `script/` - local build, test, fixture, and hook helpers.
- `tools/` - local utilities.
- `_legacy/` - reference only.

## Commands

- Setup CLI package when needed: `python3 -m pip install -e .`
- Primary CLI: `./teslacam-cli`
- CLI adapters: `python3 teslacam.py`, `./teslacam.sh`
- Full Python tests: `python3 -m unittest discover tests`
- Focused Python tests: `python3 -m unittest tests.test_domain_contract`
- Native macOS lane: `script/test_native.sh`
- Build and run app: `script/build_and_run.sh`
- Regenerate domain fixtures: `python3 script/regen_fixtures.py`
- Whitespace check: `git diff --check`

No dedicated lint, format, or Python typecheck config is present. Do not invent
one. Use `git diff --check`, `unittest`, and the native build/test lane as the
available checks.

Native commands require either `TESLACAM_BUILD_ENV` or
`/Users/bolyki/dev/source/build-env.sh`. If neither exists, report that setup
blocker instead of trying ad hoc `xcodebuild` commands.

Rules:

- Keep the macOS app and Python CLI docs aligned.
- Treat generated exports, build output, and work directories as derived.
- Use `/Users/bolyki/dev/source/build-env.sh` before native Swift builds, or point `TESLACAM_BUILD_ENV` at a compatible local override.
- Leave `TeslaCam/Resources/LICENSES.md` and other vendor or runtime assets alone unless the task is about licensing or packaging.
- Native export is the shipping app path. Do not reintroduce a CLI-only export assumption into the mac app.
- `_legacy/` stays reference-only unless the task explicitly targets it.
- `teslacam_legacy_macos.sh` is reference only.
- Keep CLI planning pure; rendering and human output stay behind adapters.
- Keep domain behavior aligned across `docs/domain-contract.md`, fixtures, Python, and Swift tests.
- Do not use `--break-system-packages`; prefer a virtual environment or repo-local cache.
- Preserve dirty worktree changes you did not make.

## Telemetry

- Do not add Sentry or external crash telemetry. Keep diagnostics local unless a repo runbook says otherwise.

## Done when

- You inspected current repo state and relevant docs/scripts before editing.
- Commands used in your answer are present in this repo or its CI/scripts.
- App/CLI behavior stays unchanged unless the task explicitly asks otherwise.
- Shared behavior changes update the domain contract, fixtures, and both test surfaces.
- Relevant verification ran, or the exact blocker is listed.
- Generated files, build output, vendor assets, and `_legacy/` stay untouched unless in scope.
