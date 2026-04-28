# Camera Layout Plan

Goal: make camera layout one deep Module used by index, preview, export, and CLI parity.

Read first:
- `docs/domain-contract.md`
- `TeslaCam/Models.swift`
- `TeslaCam/Indexer.swift`
- `TeslaCam/AppState.swift`
- `TeslaCam/NativeExportController.swift`
- `TeslaCam/MetalRenderer.swift`
- `teslacam_cli/layouts.py`
- `tests/test_layouts.py`

Problem:
- HW3/HW4/mixed rules repeat in scan, export, preview, and Python layout.
- `useSixCam` leaks a layout decision into export request creation.
- Mixed camera behavior is underspecified.
- Deleting one layout helper leaves the same complexity elsewhere.

Target shape:
- `CameraLayoutPlan` owns profile detection, expected cameras, render order, grid cells, canvas size, hidden camera behavior, and fallback rules.
- Swift and Python keep language-specific Implementations, both driven by the contract fixtures.
- Export and preview consume layout plans, not raw camera heuristics.

Steps:
1. Define contract terms: profile, visible cameras, expected cameras, render order, grid, tile size, canvas.
2. Add fixture cases for HW3, HW4, mixed, single camera, hidden cameras, forced 4-camera, forced 6-camera.
3. Implement Swift `CameraLayoutPlan` with pure inputs: detected cameras, enabled cameras, natural sizes, requested profile.
4. Make export use the plan for canvas and bounds.
5. Make preview renderer use the same camera order and tile placement.
6. Make Python layout tests compare the same fixture layout output.
7. Remove direct HW3/HW4 grid decisions from callers once parity passes.

Tests:
- Swift unit tests for plan output and mixed cases.
- Python layout fixture tests.
- Native HW4 export dimension test stays.
- Add preview order test without Metal where possible.

Guardrails:
- Do not hide missing cameras silently; export black tiles stay intentional.
- Do not change existing 4-up or 6-up canvas behavior without fixture changes.
- Keep camera vocabulary in the domain contract.

