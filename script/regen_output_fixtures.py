#!/usr/bin/env python3
"""Regenerate the ``expected_output`` block in every domain fixture.

Mirrors the pattern in ``script/regen_selection_fixtures.py``:

- Materialize each fixture in a temp dir with a stub ``MediaProbe`` so
  every clip is exactly 60 s and the natural dataset range is
  deterministic.
- Compute the default output filename per mode using the same helpers
  the CLI uses (``cli.default_output_filename``).
- Exercise each ``OutputConflictPolicy`` in an isolated tempdir:
    * ``unique`` — cascade of three calls (no conflict, single conflict,
      double conflict) so the ``-2``/``-3`` suffix logic is locked.
    * ``overwrite`` — single call with a pre-existing file; the policy
      must return the same path.
    * ``error`` — single call with a pre-existing file; the policy must
      raise a ``RuntimeError`` whose message contains
      ``"Output file already exists"``.
- Write the resulting block back to the fixture, sort-keys-stable.

Re-run whenever ``apply_output_conflict_policy`` or
``unique_output_path`` change behavior, then commit the updated fixtures.

Usage::

    source .cache/venv/bin/activate
    python3 script/regen_output_fixtures.py
"""
from __future__ import annotations

import json
from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Dict, List

from teslacam_cli.cli import (
    apply_output_conflict_policy,
    dataset_range,
    default_output_filename,
)
from teslacam_cli.models import DuplicatePolicy, OutputConflictPolicy
from teslacam_cli.scanner import scan_source

# Reuse the stub probe so the contract output stays stable across machines.
import sys
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from regen_selection_fixtures import (  # noqa: E402  — sibling module, intentionally imported
    StubMediaProbe,
    STUB_FFPROBE,
    STUB_DURATION_SECONDS,
    materialize_case,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_DIR = REPO_ROOT / "fixtures" / "domain" / "cases"

ERROR_MESSAGE_FRAGMENT = "Output file already exists"


def _natural_range(case: Dict[str, Any]) -> Dict[str, Any]:
    """Return start/end of the fixture's dataset using the stub probe.

    Returns ``{"empty": True}`` when scan yielded no clips so the caller
    can record that the contract case is degenerate.
    """
    with TemporaryDirectory() as temp_dir:
        source = Path(temp_dir)
        materialize_case(case, source)
        try:
            scan = scan_source(source, duplicate_policy=DuplicatePolicy.MERGE_BY_TIME)
        except RuntimeError:
            return {"empty": True}
        if not scan.clip_sets:
            return {"empty": True}
        start, end = dataset_range(scan.clip_sets, STUB_FFPROBE, media_probe=StubMediaProbe())
        return {"empty": False, "start": start, "end": end}


def _unique_cascade(target_name: str) -> List[str]:
    """Run ``apply_output_conflict_policy(unique)`` three times in a fresh tempdir.

    Each iteration creates the resolved file so the next call hits the
    next conflict slot. Returns the list of resolved basenames.
    """
    resolved: List[str] = []
    with TemporaryDirectory() as out_dir:
        target = Path(out_dir) / target_name
        for _ in range(3):
            picked = apply_output_conflict_policy(target, OutputConflictPolicy.UNIQUE)
            resolved.append(picked.name)
            picked.touch()
    return resolved


def _overwrite_with_conflict(target_name: str) -> str:
    with TemporaryDirectory() as out_dir:
        target = Path(out_dir) / target_name
        target.touch()
        picked = apply_output_conflict_policy(target, OutputConflictPolicy.OVERWRITE)
        return picked.name


def _error_with_conflict(target_name: str) -> Dict[str, Any]:
    with TemporaryDirectory() as out_dir:
        target = Path(out_dir) / target_name
        target.touch()
        try:
            apply_output_conflict_policy(target, OutputConflictPolicy.ERROR)
        except RuntimeError as exc:
            assert ERROR_MESSAGE_FRAGMENT in str(exc), (
                f"error policy must surface a message containing {ERROR_MESSAGE_FRAGMENT!r}; "
                f"got: {exc!r}"
            )
            return {
                "raises": True,
                "exception_type": type(exc).__name__,
                "message_contains": ERROR_MESSAGE_FRAGMENT,
            }
    return {"raises": False, "exception_type": None, "message_contains": None}


def build_output_block(case: Dict[str, Any]) -> Dict[str, Any]:
    rng = _natural_range(case)
    if rng.get("empty"):
        return {"empty_dataset": True}

    start = rng["start"]
    end = rng["end"]
    defaults = {
        mode: default_output_filename(mode, start, end)
        for mode in ("lossless", "quality")
    }
    target = defaults["lossless"]
    return {
        "default_filename_by_mode": defaults,
        "unique_resolution": _unique_cascade(target),
        "overwrite_with_conflict": _overwrite_with_conflict(target),
        "error_with_conflict": _error_with_conflict(target),
    }


def main() -> int:
    cases = sorted(FIXTURE_DIR.glob("*.json"))
    if not cases:
        print(f"No fixtures found under {FIXTURE_DIR}")
        return 1
    for fixture_path in cases:
        case = json.loads(fixture_path.read_text(encoding="utf-8"))
        case["expected_output"] = build_output_block(case)
        rendered = json.dumps(case, indent=2, sort_keys=True) + "\n"
        fixture_path.write_text(rendered, encoding="utf-8")
        print(f"updated {fixture_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
