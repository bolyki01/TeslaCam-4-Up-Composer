# Hygiene audit — 2026-05-09

Snapshot taken during the autonomous improvement loop. Two queue items
(H3 and J4) are confirmed clean today — re-run the commands below before
the next loop iteration if anything changes.

## H3 — `git ls-files` stray artifacts

Pattern checked:

```bash
git ls-files | grep -E '\.DS_Store|\.xcuserstate|\.xcuserdatad|build-dd|DerivedData|\.cache|__pycache__|\.pyc$|\.eggs|egg-info|\.swp$|\.bak$'
```

**Result:** zero matches. No `.DS_Store`, no `xcuserdatad`, no derived
data, no Python/SwiftPM build crumbs are tracked. The existing
`.gitignore` (with `.cache/` + `*.egg-info/` added during this loop) is
doing its job.

No commit required.

## J4 — `TODO` / `FIXME` / `HACK` / `XXX` triage in shipping code

Pattern checked:

```bash
git grep -nE '(TODO|FIXME|HACK|XXX)' -- \
  ':(exclude)_legacy/*' \
  ':(exclude)docs/*' \
  ':(exclude).cache/*' \
  ':(exclude)*.md'
```

**Result:** zero hits in shipping Swift / Python source.

The only matches in the repo today are:

- `TeslaCam/Resources/ffmpeg_bin/{ffmpeg,ffprobe}` — vendor binaries; the
  regex matches embedded ASCII strings, not source comments. Sacred-rule
  vendor-untouched applies.
- `teslacam_legacy_macos.sh:193` — the `XXXXXX` is a `mktemp` template
  (`mktemp -d ".../teslacam_cli.XXXXXX"`), not a TODO marker. The file
  is reference-only per AGENTS.md.

No commit required.

## Re-running the audit

If you (or the next loop iteration) want to re-confirm:

```bash
git ls-files | grep -E '\.DS_Store|\.xcuserstate|\.xcuserdatad|build-dd|DerivedData|\.cache|__pycache__|\.pyc$|\.eggs|egg-info|\.swp$|\.bak$' || echo "(clean)"

git grep -nE '(TODO|FIXME|HACK|XXX)' -- \
  ':(exclude)_legacy/*' \
  ':(exclude)docs/*' \
  ':(exclude).cache/*' \
  ':(exclude)*.md'
```

Re-open H3 / J4 in the queue if either command starts producing actionable
hits.
