# Domain Contract Owner

Goal: make app and CLI domain behavior change in one place, with fixture proof.

Read first:
- `docs/domain-contract.md`
- `fixtures/domain/cases/*.json`
- `TeslaCam/Indexer.swift`
- `TeslaCam/Models.swift`
- `TeslaCamTests/TeslaCamTests.swift`
- `teslacam_cli/scanner.py`
- `teslacam_cli/layouts.py`
- `teslacam_cli/domain_contract.py`
- `tests/test_domain_contract.py`

Problem:
- The scan contract is fixture-backed, but layout, selection, output naming, and dry-run are not equally owned.
- Swift and Python each encode camera vocabulary and layout decisions.
- The contract Interface is partly a doc, partly test helpers, partly duplicated Implementation.

Target shape:
- A deep Contract Module owns camera vocabulary, timestamp rules, duplicate policy, layout selection, selection math, output conflict naming, and manifest shape.
- Swift and Python remain separate Implementations.
- Fixtures are the Interface. Callers learn the fixture schema, not internal rules.

Steps:
1. Extend fixture schema with `expected_layout`, `expected_selection`, and `expected_output`.
2. Add a Swift manifest builder for the same dry-run fields Python emits.
3. Add Swift tests that compare all fixture fields, not only scan fields.
4. Add Python tests for layout and output conflict against the same fixtures.
5. Move camera order and alias notes into one contract vocabulary section in `docs/domain-contract.md`.
6. Keep fixture data small: malformed names, hidden paths, duplicates, mixed HW3/HW4, directory output, file output, conflict suffix.

Tests:
- `python3 -m unittest tests.test_domain_contract`
- `python3 -m unittest discover tests`
- `script/test_native.sh` after native test expectations are repaired

Guardrails:
- Native export stays the shipping app path.
- CLI stays dependency-light.
- Do not move logic into `_legacy/`.
- Do not use fixtures as generated output; keep them hand-readable.

