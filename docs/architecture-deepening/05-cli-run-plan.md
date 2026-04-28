# CLI Run Plan

Goal: make CLI planning pure and rendering an Adapter.

Read first:
- `teslacam_cli/cli.py`
- `teslacam_cli/composer.py`
- `teslacam_cli/ffmpeg_tools.py`
- `teslacam_cli/domain_contract.py`
- `teslacam_cli/models.py`
- `tests/test_cli.py`
- `tests/test_integration.py`

Problem:
- `main` resolves tools, scans, picks defaults, creates output paths, creates workdir, probes, chooses encoder, prints, emits dry-run, and renders.
- Dry-run still performs render-adjacent side effects.
- `ffmpeg_tools` subprocess calls are imported functions, so tests patch internals instead of using a clean Seam.

Target shape:
- `RunPlanBuilder` turns args plus source into a pure `RunPlan`.
- `MediaProbe` Interface owns duration, dimensions, fps, encoder query.
- `FfmpegRunner` Adapter owns subprocess execution.
- `CliPresenter` owns human text.
- `main` becomes parse -> plan -> present -> optional render.

Steps:
1. Add `RunOptions` separate from `RunConfig`; it contains raw args and policies.
2. Add `RunPlanBuilder` with no printing and no rendering.
3. Move `dataset_range`, selection, layout, dimensions, fps, encoder choice into planning.
4. Make output conflict resolution pure except directory creation; create dirs only before render/write.
5. Add `MediaProbe` protocol-like class with real ffprobe Adapter and fake test Adapter.
6. Make dry-run use `RunPlan` and write manifest without creating workdir.
7. Move print output into `CliPresenter`.

Tests:
- Unit test `RunPlanBuilder` with fake probe.
- Unit test dry-run does not create workdir.
- Unit test output conflict `unique`, `overwrite`, `error`.
- Keep integration tests for real ffmpeg.
- Run `python3 -m unittest discover tests`.

Guardrails:
- Keep Python dependencies empty.
- Keep wrappers as launch Adapters.
- Do not make CLI the mac app shipping export path.

