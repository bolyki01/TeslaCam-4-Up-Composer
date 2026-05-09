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

## H5 — MACOSX_DEPLOYMENT_TARGET override audit

Pattern checked:

```bash
git grep -nE 'MACOSX_DEPLOYMENT_TARGET' -- '.github/*' 'script/*' 'TeslaCam.xcodeproj/*.pbxproj'
```

**Result:** the only setter is the Xcode project's six per-configuration
slots in `TeslaCam.xcodeproj/project.pbxproj` (Debug + Release ×
`TeslaCam` / `TeslaCamTests` / `TeslaCamUITests`), all = `26.0`. No
`MACOSX_DEPLOYMENT_TARGET` override anywhere under `script/` or
`.github/workflows/`. The CI `xcodebuild` invocation honors the
project setting — confirmed in plan note 06 step 6.

No commit required.

## H6 — `_legacy/` references in shipping code

Pattern checked:

```bash
git grep -nE '_legacy/' -- 'TeslaCam/*.swift' 'teslacam_cli/*.py' 'tests/*.py' \
                          'TeslaCamTests/*.swift' 'TeslaCamUITests/*.swift'
```

**Result:** zero hits. No shipping Swift or Python source references
`_legacy/`. The directory remains reference-only as documented in
`AGENTS.md` and `CLAUDE.md`.

No commit required.
