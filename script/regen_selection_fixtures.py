#!/usr/bin/env python3
"""Regenerate the ``expected_selection`` block in every domain fixture.

This is the one-time generator that produces the locked-in
``expected_selection`` manifests under ``fixtures/domain/cases/*.json``.
Re-run it whenever the selection contract changes (the
``selected_sets_manifest`` shape or ``select_clip_sets`` behaviour),
then commit the updated fixtures.

A stub ``MediaProbe`` pretends every clip is exactly 60 s long so the
fixture data does not depend on ``ffprobe`` being installed nor on real
mp4 bytes.

Usage::

    source .cache/venv/bin/activate
    python3 script/regen_selection_fixtures.py
"""
from __future__ import annotations

import json
import os
from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Dict

from teslacam_cli.composer import select_clip_sets
from teslacam_cli.domain_contract import selected_sets_manifest
from teslacam_cli.models import DuplicatePolicy
from teslacam_cli.scanner import scan_source

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_DIR = REPO_ROOT / "fixtures" / "domain" / "cases"

# Stand-in ffprobe path. The stub probe never actually invokes it; it only
# satisfies the type signature on ``select_clip_sets``.
STUB_FFPROBE = Path("/usr/bin/ffprobe")
STUB_DURATION_SECONDS = 60.0


class StubMediaProbe:
    """Deterministic probe used by both the generator and the parity test.

    Every clip is exactly 60 s long, every clip has a video stream, and
    dimensions/fps are unused for selection — left as defaults so the
    contract output stays stable across machines.
    """

    def duration(self, ffprobe: Path, media_path: Path) -> float:  # noqa: ARG002 — interface match
        return STUB_DURATION_SECONDS

    def has_video_stream(self, ffprobe: Path, media_path: Path) -> bool:  # noqa: ARG002
        return True

    def dimensions(self, ffprobe: Path, media_path: Path):  # noqa: ARG002
        return None

    def fps(self, ffprobe: Path, media_path: Path) -> float:  # noqa: ARG002
        return 36.027


def materialize_case(case: Dict[str, Any], source: Path) -> None:
    """Write the fixture's declared file tree under ``source``.

    Mirrors the helper in ``tests/test_domain_contract.py`` so the
    generator and the test stay in lockstep.
    """
    for entry in case["files"]:
        path = source / entry["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"fixture")
        if "mtime" in entry:
            os.utime(path, (entry["mtime"], entry["mtime"]))


def empty_selection_manifest() -> Dict[str, Any]:
    return {"clip_set_count": 0, "rendered_duration": 0.0, "clip_sets": []}


def build_selection_manifest_for_policy(
    case: Dict[str, Any], policy: DuplicatePolicy
) -> Dict[str, Any]:
    """Run the full scan → select pipeline against a materialized fixture."""
    with TemporaryDirectory() as temp_dir:
        source = Path(temp_dir)
        materialize_case(case, source)
        try:
            scan = scan_source(source, duplicate_policy=policy)
        except RuntimeError:
            # ``scan_source`` raises when no clips were found. The contract
            # surface for that case is an empty selection — keep the fixture
            # readable and avoid leaking implementation-specific exceptions.
            return empty_selection_manifest()
        if not scan.clip_sets:
            return empty_selection_manifest()
        first = scan.clip_sets[0].start_time
        last = scan.clip_sets[-1].start_time + timedelta(seconds=STUB_DURATION_SECONDS)
        selected = select_clip_sets(
            scan.clip_sets,
            first,
            last,
            STUB_FFPROBE,
            media_probe=StubMediaProbe(),
        )
        return selected_sets_manifest(selected, source)


def main() -> int:
    cases = sorted(FIXTURE_DIR.glob("*.json"))
    if not cases:
        print(f"No fixtures found under {FIXTURE_DIR}")
        return 1
    for fixture_path in cases:
        case = json.loads(fixture_path.read_text(encoding="utf-8"))
        case["expected_selection"] = {
            policy.value: build_selection_manifest_for_policy(case, policy)
            for policy in DuplicatePolicy
        }
        rendered = json.dumps(case, indent=2, sort_keys=True) + "\n"
        fixture_path.write_text(rendered, encoding="utf-8")
        print(f"updated {fixture_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
