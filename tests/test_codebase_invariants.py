"""Tripwire tests for codebase-wide invariants.

These tests scan the shipping Python source tree for patterns that
have a documented sacred-rule reason to stay absent. They are cheap
(pure file walks; no subprocess) and they are the one place a
regression of "we accidentally introduced shell injection" or
"someone called eval on an untrusted string" surfaces immediately.

The Swift side has its own equivalent guard documented in
``docs/improvement/security-audit-2026-05-09.md`` (G3 process-spawn
audit). Those are git-grep checks; this module's job is the Python
half.

Each forbidden pattern carries a justification comment so a future
maintainer can decide whether to delete the rule or update the test
when behaviour legitimately needs to change.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
SHIPPING_ROOT = REPO_ROOT / "teslacam_cli"


def _shipping_python_files() -> Iterable[Path]:
    """Every .py file under teslacam_cli/, recursively."""
    yield from sorted(SHIPPING_ROOT.rglob("*.py"))


def _grep_lines(pattern: re.Pattern[str], paths: Iterable[Path]) -> list[tuple[Path, int, str]]:
    hits: list[tuple[Path, int, str]] = []
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for index, line in enumerate(text.splitlines(), start=1):
            if pattern.search(line):
                hits.append((path, index, line.rstrip()))
    return hits


def _format_hits(hits: list[tuple[Path, int, str]]) -> str:
    return "\n".join(f"  {path.relative_to(REPO_ROOT)}:{line}: {body}" for path, line, body in hits)


class ForbiddenPatternTests(unittest.TestCase):
    """Patterns that must never appear in the shipping CLI source.

    Each test pins one rule. If a pattern legitimately has to come
    back (e.g. a documented exception), update the matching rule
    here in the same commit.
    """

    def test_shell_true_is_never_used_in_subprocess_calls(self):
        # Justification: every subprocess invocation in
        # teslacam_cli/process_tools.py builds an argv list and passes
        # it to subprocess.Popen WITHOUT shell=True. Reintroducing
        # shell=True would let user-controlled paths reach shell
        # metacharacters (sacred rule G3).
        pattern = re.compile(r"\bshell\s*=\s*True\b")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(hits, [], f"shell=True must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_os_system_is_never_used(self):
        # Justification: same reasoning as shell=True; os.system
        # invokes /bin/sh -c with the input string and inherits
        # injection risk.
        pattern = re.compile(r"\bos\.system\(")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(hits, [], f"os.system() must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_dynamic_eval_and_exec_are_never_used(self):
        # Justification: the CLI never needs to evaluate user-supplied
        # code; eval / exec on any string risks remote code execution
        # if the input ever flows from a TeslaCam-derived path or env
        # var. Limit to the literal call form `eval(` / `exec(` so
        # words like "evaluate" and "execute" in comments are fine.
        eval_pattern = re.compile(r"(?<![A-Za-z_])eval\(")
        exec_pattern = re.compile(r"(?<![A-Za-z_])exec\(")
        hits = _grep_lines(eval_pattern, _shipping_python_files()) + _grep_lines(
            exec_pattern, _shipping_python_files()
        )
        self.assertEqual(hits, [], f"eval()/exec() must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_dynamic_import_is_never_used(self):
        # Justification: regular `import` statements flow through the
        # well-known module resolution path; __import__ on a runtime
        # string is suspicious in CLI code that does not need plugin
        # loading. If we ever add a real plugin system, document it
        # and update this rule.
        pattern = re.compile(r"(?<![A-Za-z_])__import__\(")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(hits, [], f"__import__() must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_break_system_packages_is_never_committed(self):
        # Justification: --break-system-packages bypasses PEP 668
        # protection and is a developer convenience for Linux-managed
        # Python installs. It must never be committed to shipping
        # source — it would leak into pip install commands the CLI
        # might construct (none today, but the rule is cheap to keep).
        pattern = re.compile(r"--break-system-packages")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(
            hits,
            [],
            f"--break-system-packages must not appear in shipping CLI source:\n{_format_hits(hits)}",
        )


class TestSurfaceTests(unittest.TestCase):
    """Sanity checks on the test surface itself.

    These guard against the tripwire pattern silently passing because
    the file walk found nothing — e.g. if the path constants drift to
    point at an empty directory.
    """

    def test_shipping_root_exists_and_has_python_files(self):
        self.assertTrue(SHIPPING_ROOT.is_dir(), f"{SHIPPING_ROOT} must be a directory")
        files = list(_shipping_python_files())
        self.assertGreaterEqual(len(files), 5, "expected at least a handful of .py files under teslacam_cli/")

    def test_grep_helper_actually_finds_real_lines(self):
        # If `_grep_lines` quietly returns [] for everything, the
        # forbidden-pattern tests would pass vacuously. Pin one
        # known-present token (the relative-import form used across
        # the shipping CLI) to prove the walker reads files for real.
        pattern = re.compile(r"^from \.")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertGreater(
            len(hits),
            0,
            "_grep_lines must surface real matches; failing here means the walker is broken",
        )


if __name__ == "__main__":
    unittest.main()
