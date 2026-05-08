# Repo Hygiene

Goal: remove navigation noise and make active paths obvious to AI agents.

Read first:
- `AGENTS.md`
- `README.md`
- `RUNBOOK.md`
- `.gitignore`
- `TeslaCam.xcodeproj/project.pbxproj`
- `TeslaCam/Exporter.swift`
- `TeslaCam/Resources/teslacam_*.sh`
- `teslacam.py`
- `teslacam-cli`
- `teslacam.sh`
- `teslacam_legacy_macos.sh`

Problem:
- Derived build output appears in the worktree and search results.
- Legacy export code shadows the native export path.
- Multiple entrypoints make the CLI Interface unclear.
- CI shape is thin compared with local lanes.

Target shape:
- Active source paths are easy to find.
- Legacy material is quarantined as reference-only.
- Generated output is ignored and cleaned.
- CLI entrypoints are documented as Adapters to the same Module.
- Test lanes are named and reproducible.

Steps:
1. Add ignore rules for local Xcode build folders such as `build-dd/` and other derived roots used here. **Done** — `.gitignore` covers `DerivedData/`, `DerivedData-*/`, `build-dd/`, `*.xcresult/`, `*.dSYM`, and the SwiftPM build dirs.
2. Move or mark legacy export code so search does not confuse it with shipping export. **Done** — `_legacy/Exporter.swift` is the only `ExportController` hit outside the shipping path, and `_legacy/` is documented as reference-only in `AGENTS.md`, `README.md`, and `CLAUDE.md`.
3. Keep vendor binaries and license assets untouched unless packaging/licensing is the task. **Honored.**
4. Pick one primary CLI command in docs; list other wrappers as compatibility Adapters. **Done** — `RUNBOOK.md` and `README.md` both name `./teslacam-cli` as the primary command and call out `teslacam.py` / `teslacam.sh` as adapters.
5. Add a small test lane doc: Python, native unit, native UI, contract fixtures. **Done** — `RUNBOOK.md` lists the Python lanes and `script/test_native.sh` for the native unit + UI lane; `CLAUDE.md` summarizes the lanes for agents.
6. Add CI follow-up plan after local lanes are stable. **Done** — `.github/workflows/python-tests.yml` covers the Python lanes on Ubuntu (Python 3.10 + 3.12, ffmpeg installed); `.github/workflows/native-tests.yml` runs `TeslaCamTests` on `macos-15` with code signing disabled. UI tests stay out of CI for now (slow + flaky) and run via `script/test_native.sh` locally.

Tests:
- `git status --short` should not show generated build output after clean.
- `rg "ExportController"` should not point agents at a shipping Module.
- `python3 -m unittest discover tests`
- `script/test_native.sh` once UI tests are repaired

Guardrails:
- Never delete `_legacy/` reference material unless asked.
- Do not alter `TeslaCam/Resources/LICENSES.md`.
- Do not stage generated output.
- Preserve dirty user work.

