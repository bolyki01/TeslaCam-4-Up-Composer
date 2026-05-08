import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from teslacam_cli.cli import default_output_filename, unique_output_path
from teslacam_cli.domain_contract import dry_run_manifest, manifest_json, scan_manifest
from teslacam_cli.layouts import build_camera_layout_plan, build_layout, fill_missing_dimensions
from teslacam_cli.models import Camera, Dimensions, DuplicatePolicy, LayoutKind, OutputConflictPolicy, SelectedSet
from teslacam_cli.scanner import scan_source

FIXTURE_DIR = Path(__file__).resolve().parent.parent / "fixtures" / "domain" / "cases"


class DomainFixtureParityTests(unittest.TestCase):
    def test_shared_scan_fixtures_match_python_manifest_for_all_duplicate_policies(self):
        cases = sorted(FIXTURE_DIR.glob("*.json"))
        self.assertGreaterEqual(len(cases), 4)
        for fixture_path in cases:
            with self.subTest(fixture=fixture_path.name):
                case = json.loads(fixture_path.read_text(encoding="utf-8"))
                with TemporaryDirectory() as temp_dir:
                    source = Path(temp_dir)
                    _materialize_case(case, source)
                    for policy in DuplicatePolicy:
                        with self.subTest(policy=policy.value):
                            result = scan_source(source, duplicate_policy=policy)
                            manifest = scan_manifest(result, source)
                            manifest.pop("schema_version")
                            manifest.pop("type")
                            self.assertEqual(manifest, case["expected_scan"][policy.value])

    def test_shared_layout_fixtures_round_trip_through_scan_then_layout_for_all_profiles(self):
        from teslacam_cli.domain_contract import layout_manifest
        cases = sorted(FIXTURE_DIR.glob("*.json"))
        self.assertGreaterEqual(len(cases), 4)
        for fixture_path in cases:
            with self.subTest(fixture=fixture_path.name):
                case = json.loads(fixture_path.read_text(encoding="utf-8"))
                self.assertIn("expected_layout", case, f"{fixture_path.name} missing expected_layout")
                self.assertEqual(set(case["expected_layout"]), {"auto", "legacy4", "sixcam"})
                with TemporaryDirectory() as temp_dir:
                    source = Path(temp_dir)
                    _materialize_case(case, source)
                    scan = scan_source(source, duplicate_policy=DuplicatePolicy.MERGE_BY_TIME)
                    for profile in ("auto", "legacy4", "sixcam"):
                        with self.subTest(profile=profile):
                            layout = build_camera_layout_plan(
                                profile=profile,
                                available_cameras=scan.cameras,
                                probed_dimensions={},
                            )
                            self.assertEqual(layout_manifest(layout), case["expected_layout"][profile])

    def test_default_output_filename_matches_contract_format(self):
        from datetime import datetime
        start = datetime(2026, 1, 1, 0, 0, 0)
        end = datetime(2026, 1, 1, 0, 5, 30)
        self.assertEqual(
            default_output_filename("lossless", start, end),
            "teslacam_lossless_2026-01-01_00-00-00_to_2026-01-01_00-05-30.mp4",
        )
        self.assertEqual(
            default_output_filename("fast", start, end),
            "teslacam_fast_2026-01-01_00-00-00_to_2026-01-01_00-05-30.mp4",
        )

    def test_unique_output_path_appends_dash_counter(self):
        with TemporaryDirectory() as temp_dir:
            base = Path(temp_dir) / "teslacam_lossless_a_to_b.mp4"
            base.write_bytes(b"")
            self.assertEqual(unique_output_path(base).name, "teslacam_lossless_a_to_b-2.mp4")
            (base.parent / "teslacam_lossless_a_to_b-2.mp4").write_bytes(b"")
            self.assertEqual(unique_output_path(base).name, "teslacam_lossless_a_to_b-3.mp4")

    def test_dry_run_manifest_is_machine_readable_and_contains_export_contract(self):
        with TemporaryDirectory() as temp_dir:
            source = Path(temp_dir)
            front = source / "2026-01-01_00-00-00-front.mp4"
            back = source / "2026-01-01_00-00-00-rear.mp4"
            front.write_bytes(b"front")
            back.write_bytes(b"back")

            result = scan_source(source)
            selected = [
                SelectedSet(
                    clip_set=result.clip_sets[0],
                    duration=60.0,
                    trim_start=5.0,
                    trim_end=30.0,
                )
            ]
            dimensions = fill_missing_dimensions(
                LayoutKind.FOUR_UP,
                {
                    Camera.FRONT: Dimensions(width=1280, height=960),
                    Camera.BACK: Dimensions(width=1280, height=960),
                },
            )
            layout = build_layout(LayoutKind.FOUR_UP, dimensions)
            manifest = dry_run_manifest(
                source_dir=source,
                output_file=source / "output.mp4",
                start_time=result.clip_sets[0].start_time,
                end_time=result.clip_sets[0].start_time,
                profile="legacy4",
                mode="lossless",
                duplicate_policy=DuplicatePolicy.MERGE_BY_TIME,
                output_conflict=OutputConflictPolicy.UNIQUE,
                scan_result=result,
                selected_sets=selected,
                layout=layout,
                dimensions=dimensions,
                fps=30.0,
                encoder_label="x265 lossless HEVC",
            )

        payload = json.loads(manifest_json(manifest))
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["type"], "teslacam.dry-run")
        self.assertEqual(payload["duplicate_policy"], "merge-by-time")
        self.assertEqual(payload["output_conflict"], "unique")
        self.assertEqual(payload["scan"]["clip_set_count"], 1)
        self.assertEqual(payload["selection"]["rendered_duration"], 25.0)
        self.assertEqual(payload["layout"]["kind"], "4up")


def _materialize_case(case: dict, source: Path) -> None:
    for entry in case["files"]:
        path = source / entry["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"fixture")
        if "mtime" in entry:
            os.utime(path, (entry["mtime"], entry["mtime"]))




if __name__ == "__main__":
    unittest.main()
