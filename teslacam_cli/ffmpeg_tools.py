from __future__ import annotations

import json
import os
import platform
import shutil
from functools import lru_cache
from pathlib import Path
from typing import Dict, Optional, Sequence

from .concat_safety import ffconcat_path as _safe_ffconcat_path
from .models import Dimensions, EncoderPlan
from .probe_cache import RunProbeCache
from .process_tools import LimitedProcessTimeout, executable_regular_file, run_limited_process

DEFAULT_DURATION_SECONDS = 60.0
DEFAULT_FPS = 36.027
DEFAULT_FFPROBE_TIMEOUT_SECONDS = 20.0
DEFAULT_TOOL_QUERY_TIMEOUT_SECONDS = 15.0


class ToolResolutionError(RuntimeError):
    pass


class FfmpegRuntimeError(RuntimeError):
    pass


class MediaProbe:
    def __init__(
        self,
        probe_cache: Optional[RunProbeCache] = None,
        ffprobe_timeout_seconds: Optional[float] = DEFAULT_FFPROBE_TIMEOUT_SECONDS,
    ) -> None:
        self.probe_cache = probe_cache
        self.ffprobe_timeout_seconds = ffprobe_timeout_seconds

    def duration(self, ffprobe: Path, media_path: Path) -> float:
        return self._with_cache(
            ffprobe,
            media_path,
            "duration",
            lambda: probe_duration(ffprobe, media_path, timeout_seconds=self.ffprobe_timeout_seconds),
        )

    def dimensions(self, ffprobe: Path, media_path: Path) -> Optional[Dimensions]:
        return self._with_cache(
            ffprobe,
            media_path,
            "dimensions",
            lambda: probe_dimensions(ffprobe, media_path, timeout_seconds=self.ffprobe_timeout_seconds),
        )

    def fps(self, ffprobe: Path, media_path: Path) -> float:
        return self._with_cache(
            ffprobe,
            media_path,
            "fps",
            lambda: probe_fps(ffprobe, media_path, timeout_seconds=self.ffprobe_timeout_seconds),
        )

    def has_video_stream(self, ffprobe: Path, media_path: Path) -> bool:
        return self._with_cache(
            ffprobe,
            media_path,
            "has_video_stream",
            lambda: probe_has_video_stream(ffprobe, media_path, timeout_seconds=self.ffprobe_timeout_seconds),
        )

    def choose_encoder(self, ffmpeg: Path, mode: str, x265_preset: str) -> EncoderPlan:
        return choose_encoder(ffmpeg, mode, x265_preset)

    def _with_cache(self, ffprobe: Path, media_path: Path, operation: str, compute):
        if self.probe_cache is None:
            return compute()
        return self.probe_cache.get_or_compute(ffprobe, media_path, operation, compute)


class FfmpegRunner:
    def __init__(self, timeout_seconds: Optional[float] = None) -> None:
        self.timeout_seconds = timeout_seconds

    def run(self, args: Sequence[str], cwd: Optional[Path] = None) -> None:
        run_command(args, cwd=cwd, timeout_seconds=self.timeout_seconds)


@lru_cache(maxsize=8)
def _encoders_text(ffmpeg_path: str, timeout_seconds: Optional[float]) -> str:
    try:
        result = run_limited_process(
            [ffmpeg_path, "-hide_banner", "-encoders"],
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=4 * 1024 * 1024,
            stderr_limit_bytes=128 * 1024,
        )
    except LimitedProcessTimeout as exc:
        raise FfmpegRuntimeError(str(exc)) from exc
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise FfmpegRuntimeError(f"Failed to query ffmpeg encoders: {stderr}")
    return result.stdout


@lru_cache(maxsize=256)
def _probe_json(
    ffprobe_path: str,
    media_path: str,
    entries: str,
    timeout_seconds: Optional[float],
) -> Dict[str, object]:
    try:
        result = run_limited_process(
            [
                ffprobe_path,
                "-v",
                "error",
                "-of",
                "json",
                "-show_entries",
                entries,
                media_path,
            ],
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=1_048_576,
            stderr_limit_bytes=65_536,
        )
    except LimitedProcessTimeout:
        return {}
    if result.returncode != 0 or result.stdout_truncated:
        return {}
    try:
        return json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        return {}


def _candidate_tools(explicit: Optional[str], env_var: str, default_name: str, repo_root: Path) -> Sequence[Path]:
    candidates = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    env_value = os.environ.get(env_var)
    if env_value:
        candidates.append(Path(env_value).expanduser())

    if platform.system() == "Darwin":
        bundled = repo_root / "TeslaCam" / "Resources" / "ffmpeg_bin" / default_name
        candidates.append(bundled)

    which_path = shutil.which(default_name)
    if which_path:
        candidates.append(Path(which_path))

    if platform.system() == "Windows":
        exe_name = f"{default_name}.exe"
        which_path_exe = shutil.which(exe_name)
        if which_path_exe:
            candidates.append(Path(which_path_exe))

    unique: list[Path] = []
    seen = set()
    for candidate in candidates:
        key = str(candidate.resolve()) if candidate.exists() else str(candidate)
        if key in seen:
            continue
        seen.add(key)
        unique.append(candidate)
    return unique


def _resolve_one_tool(explicit: Optional[str], env_var: str, default_name: str, repo_root: Path) -> Path:
    for candidate in _candidate_tools(explicit, env_var, default_name, repo_root):
        if executable_regular_file(candidate):
            return candidate.resolve()
    searched = ", ".join(str(item) for item in _candidate_tools(explicit, env_var, default_name, repo_root)) or "none"
    raise ToolResolutionError(
        f"Could not resolve {default_name}. Searched: {searched}. Install ffmpeg/ffprobe or pass --{default_name}."
    )


def resolve_tools(repo_root: Path, ffmpeg_arg: Optional[str], ffprobe_arg: Optional[str]) -> tuple[Path, Path]:
    ffmpeg = _resolve_one_tool(ffmpeg_arg, "TESLACAM_FFMPEG", "ffmpeg", repo_root)
    ffprobe = _resolve_one_tool(ffprobe_arg, "TESLACAM_FFPROBE", "ffprobe", repo_root)
    return ffmpeg, ffprobe


def probe_dimensions(
    ffprobe: Path,
    media_path: Path,
    timeout_seconds: Optional[float] = DEFAULT_FFPROBE_TIMEOUT_SECONDS,
) -> Optional[Dimensions]:
    payload = _probe_json(str(ffprobe), str(media_path), "stream=width,height", timeout_seconds)
    streams = payload.get("streams") if isinstance(payload, dict) else None
    if not isinstance(streams, list) or not streams:
        return None
    stream = streams[0]
    if not isinstance(stream, dict):
        return None
    width = stream.get("width")
    height = stream.get("height")
    if not isinstance(width, int) or not isinstance(height, int):
        return None
    if width <= 0 or height <= 0:
        return None
    return Dimensions(width=width, height=height)


def probe_has_video_stream(
    ffprobe: Path,
    media_path: Path,
    timeout_seconds: Optional[float] = DEFAULT_FFPROBE_TIMEOUT_SECONDS,
) -> bool:
    payload = _probe_json(str(ffprobe), str(media_path), "stream=codec_type,width,height", timeout_seconds)
    streams = payload.get("streams") if isinstance(payload, dict) else None
    if not isinstance(streams, list):
        return False
    for stream in streams:
        if not isinstance(stream, dict):
            continue
        codec_type = stream.get("codec_type")
        width = stream.get("width")
        height = stream.get("height")
        if codec_type == "video":
            if isinstance(width, int) and isinstance(height, int):
                return width > 0 and height > 0
            return True
    return False


def probe_duration(
    ffprobe: Path,
    media_path: Path,
    timeout_seconds: Optional[float] = DEFAULT_FFPROBE_TIMEOUT_SECONDS,
) -> float:
    payload = _probe_json(str(ffprobe), str(media_path), "format=duration", timeout_seconds)
    fmt = payload.get("format") if isinstance(payload, dict) else None
    if not isinstance(fmt, dict):
        return DEFAULT_DURATION_SECONDS
    value = fmt.get("duration")
    try:
        duration = float(value)
    except (TypeError, ValueError):
        return DEFAULT_DURATION_SECONDS
    return duration if duration > 0.0 else DEFAULT_DURATION_SECONDS


def probe_fps(
    ffprobe: Path,
    media_path: Path,
    timeout_seconds: Optional[float] = DEFAULT_FFPROBE_TIMEOUT_SECONDS,
) -> float:
    payload = _probe_json(str(ffprobe), str(media_path), "stream=avg_frame_rate,r_frame_rate", timeout_seconds)
    streams = payload.get("streams") if isinstance(payload, dict) else None
    if not isinstance(streams, list) or not streams:
        return DEFAULT_FPS
    stream = streams[0] if isinstance(streams[0], dict) else {}
    for key in ("avg_frame_rate", "r_frame_rate"):
        value = stream.get(key)
        fps = _parse_rate(value)
        if fps is not None and fps > 0:
            return fps
    return DEFAULT_FPS


def _parse_rate(value: object) -> Optional[float]:
    if not isinstance(value, str) or not value:
        return None
    if "/" in value:
        left, right = value.split("/", 1)
        try:
            numerator = float(left)
            denominator = float(right)
        except ValueError:
            return None
        if denominator == 0:
            return None
        return numerator / denominator
    try:
        return float(value)
    except ValueError:
        return None


def choose_encoder(
    ffmpeg: Path,
    mode: str,
    x265_preset: str,
    timeout_seconds: Optional[float] = DEFAULT_TOOL_QUERY_TIMEOUT_SECONDS,
) -> EncoderPlan:
    encoders = _encoders_text(str(ffmpeg), timeout_seconds)
    if "libx265" not in encoders:
        raise ToolResolutionError(
            "This ffmpeg build does not include libx265. Lossless/near-lossless HEVC requires libx265."
        )

    if mode == "lossless":
        return EncoderPlan(
            mode="lossless",
            label="hevc_lossless",
            output_extension="mp4",
            args=[
                "-c:v",
                "libx265",
                "-preset",
                x265_preset,
                "-x265-params",
                "lossless=1:repeat-headers=1:log-level=error",
                "-tag:v",
                "hvc1",
                "-pix_fmt",
                "yuv420p",
                "-threads",
                "0",
            ],
        )
    if mode == "quality":
        return EncoderPlan(
            mode="quality",
            label="hevc_quality",
            output_extension="mp4",
            args=[
                "-c:v",
                "libx265",
                "-preset",
                x265_preset,
                "-crf",
                "6",
                "-x265-params",
                "log-level=error",
                "-tag:v",
                "hvc1",
                "-pix_fmt",
                "yuv420p",
                "-threads",
                "0",
            ],
        )
    raise ValueError(f"Unsupported encoder mode: {mode}")


def run_command(args: Sequence[str], cwd: Optional[Path] = None, timeout_seconds: Optional[float] = None) -> None:
    try:
        result = run_limited_process(
            list(args),
            cwd=cwd,
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=65_536,
            stderr_limit_bytes=262_144,
        )
    except LimitedProcessTimeout as exc:
        raise FfmpegRuntimeError(str(exc)) from exc
    if result.returncode != 0:
        joined = " ".join(str(item) for item in args)
        stderr = (result.stderr or "").strip()
        if result.stderr_truncated:
            stderr += " [stderr truncated]"
        raise FfmpegRuntimeError(f"Command failed with exit code {result.returncode}: {joined}\n{stderr}".strip())


def ffconcat_path(path: Path) -> str:
    return _safe_ffconcat_path(path)
