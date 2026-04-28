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
1. Add ignore rules for local Xcode build folders such as `build-dd/` and other derived roots used here.
2. Move or mark legacy export code so search does not confuse it with shipping export.
3. Keep vendor binaries and license assets untouched unless packaging/licensing is the task.
4. Pick one primary CLI command in docs; list other wrappers as compatibility Adapters.
5. Add a small test lane doc: Python, native unit, native UI, contract fixtures.
6. Add CI follow-up plan after local lanes are stable.

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

