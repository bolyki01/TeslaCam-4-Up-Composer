from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg/ffprobe required")
class IntegrationTests(unittest.TestCase):
    def test_cli_dry_run_json_writes_manifest_without_render(self):
        repo_root = Path(__file__).resolve().parent.parent
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "clips"
            source.mkdir(parents=True)
            for camera in ["front", "rear", "left_repeater", "right_repeater"]:
                file_path = source / f"2026-01-01_00-00-00-{camera}.mp4"
                subprocess.run(
                    [
                        "ffmpeg",
                        "-y",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-f",
                        "lavfi",
                        "-i",
                        "testsrc=size=160x90:rate=10",
                        "-t",
                        "1",
                        "-c:v",
                        "libx264",
                        str(file_path),
                    ],
                    check=True,
                )
            manifest_path = root / "manifest.json"

            subprocess.run(
                [
                    sys.executable,
                    str(repo_root / "teslacam.py"),
                    str(source),
                    "--dry-run-json",
                    str(manifest_path),
                    "--start",
                    "2026-01-01 00:00:00",
                    "--end",
                    "2026-01-01 00:00:01",
                    "--profile",
                    "legacy4",
                ],
                check=True,
            )

            self.assertTrue(manifest_path.exists())
            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["type"], "teslacam.dry-run")
            self.assertEqual(payload["scan"]["clip_set_count"], 1)
            self.assertEqual(payload["selection"]["clip_set_count"], 1)

    def test_cli_composes_lossless_hevc_mp4(self):
        repo_root = Path(__file__).resolve().parent.parent
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "clips"
            source.mkdir(parents=True)
            for index, camera in enumerate(["front", "rear", "left_repeater", "right_repeater"]):
                file_path = source / f"2026-01-01_00-00-00-{camera}.mp4"
                subprocess.run(
                    [
                        "ffmpeg",
                        "-y",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-f",
                        "lavfi",
                        "-i",
                        f"testsrc=size=160x90:rate=10",
                        "-t",
                        "1",
                        "-c:v",
                        "libx264",
                        str(file_path),
                    ],
                    check=True,
                )
            output = root / "out.mp4"
            subprocess.run(
                [
                    sys.executable,
                    str(repo_root / "teslacam.py"),
                    str(source),
                    "--output",
                    str(output),
                    "--start",
                    "2026-01-01 00:00:00",
                    "--end",
                    "2026-01-01 00:00:01",
                    "--mode",
                    "lossless",
                    "--profile",
                    "legacy4",
                    "--loglevel",
                    "error",
                ],
                check=True,
            )
            self.assertTrue(output.exists())
            probe = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-select_streams",
                    "v:0",
                    "-show_entries",
                    "stream=codec_name,width,height",
                    "-of",
                    "default=nk=1:nw=1",
                    str(output),
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            fields = probe.stdout.strip().splitlines()
            self.assertEqual(fields[0], "hevc")
            self.assertEqual(fields[1], "320")
            self.assertEqual(fields[2], "180")

    def test_cli_substitutes_black_tile_for_corrupt_camera(self):
        repo_root = Path(__file__).resolve().parent.parent
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "clips"
            source.mkdir(parents=True)
            for camera in ["front", "rear", "left_repeater"]:
                file_path = source / f"2026-01-01_00-00-00-{camera}.mp4"
                subprocess.run(
                    [
                        "ffmpeg",
                        "-y",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-f",
                        "lavfi",
                        "-i",
                        f"testsrc=size=160x90:rate=10",
                        "-t",
                        "1",
                        "-c:v",
                        "libx264",
                        str(file_path),
                    ],
                    check=True,
                )
            (source / "2026-01-01_00-00-00-right_repeater.mp4").write_bytes(b"not-a-valid-mp4")
            output = root / "out_corrupt.mp4"
            subprocess.run(
                [
                    sys.executable,
                    str(repo_root / "teslacam.py"),
                    str(source),
                    "--output",
                    str(output),
                    "--start",
                    "2026-01-01 00:00:00",
                    "--end",
                    "2026-01-01 00:00:01",
                    "--mode",
                    "lossless",
                    "--profile",
                    "legacy4",
                    "--loglevel",
                    "error",
                ],
                check=True,
            )
            self.assertTrue(output.exists())
            probe = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-select_streams",
                    "v:0",
                    "-show_entries",
                    "stream=codec_name,width,height",
                    "-of",
                    "default=nk=1:nw=1",
                    str(output),
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            fields = probe.stdout.strip().splitlines()
            self.assertEqual(fields[0], "hevc")
            self.assertEqual(fields[1], "320")
            self.assertEqual(fields[2], "180")


if __name__ == "__main__":
    unittest.main()
