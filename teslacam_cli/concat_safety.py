from __future__ import annotations

from pathlib import Path


class UnsafeConcatPath(RuntimeError):
    pass


def validate_ffconcat_path(path: Path) -> None:
    text = str(path)
    if "\n" in text or "\r" in text:
        raise UnsafeConcatPath("Media paths containing newlines are not supported for ffmpeg concat lists.")


def ffconcat_path(path: Path) -> str:
    validate_ffconcat_path(path)
    text = str(path.resolve()).replace("\\", "/")
    return text.replace("'", r"'\\''")
