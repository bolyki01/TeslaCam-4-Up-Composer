# Security audit — 2026-05-09

Snapshot of two queue items from phase G during the autonomous improvement
loop. Both clean today; re-run the commands below before the next pass if
relevant code changes.

## G2 — security-scoped bookmark lifecycle

Every `startAccessingSecurityScopedResource()` site in the macOS app pairs
with a `stopAccessing*` on every exit path.

```bash
git grep -nE 'startAccessingSecurityScopedResource' -- 'TeslaCam/*.swift'
git grep -nE 'stopAccessingSecurityScopedResource'  -- 'TeslaCam/*.swift'
```

**Sites and pairing:**

| Owner | Begin | End | Notes |
|---|---|---|---|
| `SourceStore.activateSecurityScope(for:)` | line 114 | `deactivateSecurityScope()` line 120 | `activateSecurityScope` calls `deactivateSecurityScope` first (idempotent reset); only URLs that successfully started are remembered, so each end is exactly the URLs that succeeded. |
| `FileManagerExportPreflightFileAccess.canWrite(to:)` | `beginSecurityScope` lines 167 / 170 (returns whichever URL succeeded, falls through to nil) | `defer { scopeURL?.stopAccessingSecurityScopedResource() }` line 124 | The `defer` block runs on every exit including `do/catch` paths, so write-test scope is always released. |
| `NativeExportController.beginOutputScope(for:)` | lines 812 / 817 | `endOutputScope()` line 822 (called from line 334 cleanup, 614 cancel, 767 finish, and internal 811 to make begin idempotent). | Only one of `outputURL` / parent successfully starts; `activeOutputScopeURL` records exactly that URL. The internal `endOutputScope()` at the start of `beginOutputScope` ensures a leftover scope from a prior run gets released even if no new run completes. |

No paths leak a started scope.

## G3 — process spawn / ffmpeg-path injection

The macOS app spawns no subprocesses. The Python CLI spawns ffmpeg/ffprobe
through `subprocess.Popen` with an argv list (never `shell=True`); the
binary path is resolved from a structured candidate list before launch.

```bash
git grep -nE '(Process\(\)|NSTask|posix_spawn|launchPath|executableURL)' -- 'TeslaCam/*.swift'
git grep -nE '(subprocess\.|Popen|os\.system|os\.exec|os\.spawn)' -- 'teslacam_cli/*.py'
git grep -n 'TESLACAM_FFMPEG\|TESLACAM_FFPROBE\|_resolve_one_tool\|resolve_tools' -- 'teslacam_cli/*.py'
```

**macOS app:**

- The only process-shaped match is `TeslaCam/Main.swift:158 app.run()` —
  that's `NSApplication.run()`, not a subprocess. Confirmed.
- No `Process()`, `NSTask`, `posix_spawn`, `launchPath`, or
  `executableURL` hits. The shipping app cannot shell out.

**Python CLI:**

- `teslacam_cli/process_tools.py:35` is the single `subprocess.Popen`
  call, wrapped by `run_limited_process`. Always invoked with an argv
  list, never `shell=True`.
- ffmpeg/ffprobe paths flow through `ffmpeg_tools.resolve_tools` →
  `_resolve_one_tool` → `_candidate_tools`, in this priority:
  1. explicit `--ffmpeg` / `--ffprobe` CLI argument (user-provided path),
     `expanduser`'d into a `Path`
  2. `TESLACAM_FFMPEG` / `TESLACAM_FFPROBE` env var
  3. repo-bundled `TeslaCam/Resources/ffmpeg_bin/{ffmpeg,ffprobe}` on macOS
  4. `shutil.which(default_name)` (PATH lookup)
  5. `shutil.which("ffmpeg.exe")` on Windows
- The first candidate that satisfies `executable_regular_file()` wins.
  No string interpolation of user input into shell commands; argv-list
  invocation prevents argument injection.

**Tests:** `tests/test_integration.py` legitimately uses `subprocess.run`
to drive integration cases (gated on `shutil.which("ffmpeg")` so the
suite skips when ffmpeg is unavailable).

## G4 — hardened-runtime entitlements audit

Both entitlement files (`TeslaCam/TeslaCam.entitlements` and
`TeslaCam/TeslaCam_iPad.entitlements`) carry exactly two keys:

- `com.apple.security.app-sandbox` = `true` — required for App Store
  distribution. Always exercised: the app runs sandboxed.
- `com.apple.security.files.user-selected.read-write` = `true` —
  required by the App Store sandbox to open user-picked TeslaCam folders
  and write export output. Exercised at every source-folder pick via
  `NSOpenPanel` (then handled by `SourceStore`'s security-scoped bookmark
  flow) and at every export destination pick via `NSSavePanel` (then
  handled by `NativeExportController.beginOutputScope`).

No additional entitlements (no Apple Events, no network client, no
camera/microphone, no Mac App Sandbox temporary exceptions). The
permission surface is the minimum required by sandbox + user-picked file
access; nothing is over-granted.

```bash
ls TeslaCam/*.entitlements
for f in TeslaCam/*.entitlements; do echo "=== $f ==="; cat "$f"; echo; done
```

Re-open G4 if a new entitlement key gets added; the new key needs a
matching exercise site in the codebase, otherwise drop it.

## G5 — logging discipline (privacy redaction in unified log)

Pattern checked:

```bash
git grep -nE '\b(print\(|NSLog|os_log\b|Logger|debugPrint)' -- 'TeslaCam/*.swift'
git grep -nE '\bprint\(' -- 'teslacam_cli/*.py'
```

**Swift findings:**

- Zero `print(` / `NSLog` / `debugPrint` in shipping Swift source. The
  app routes diagnostics through a single `Logger(subsystem:
  "com.magrathean.TeslaCam", category: "debug")` inside
  `DebugLogSink.record(_:category:)` (TeslaCam/Models.swift:946).
- One actionable finding **(fixed in this loop)**: the message
  interpolation was `\(message, privacy: .public)`. Category is a fixed
  identifier (legitimately public for filtering), but message content
  is dynamic and may carry user-facing file paths (export destinations,
  source-folder URLs). Public privacy means those paths surface in
  Console.app / sysdiagnose without a debugger attached.
- Fix: tightened to `\(message, privacy: .private)`. Category stays
  `.public`. The in-app `Show Log` is unaffected — it reads the
  in-memory `events` array, not the redacted unified-log copy. This
  matches sacred rule 7: diagnostics stay local; `Show Log` is the
  user-facing surface.

**Python findings:**

- The CLI's `print()` calls in `teslacam_cli/cli.py` are all
  user-facing CLI output (progress, prompts, errors, summaries) —
  intended terminal interaction, not a long-lived log. The `--ffmpeg
  failed: ...` channel is `print(..., file=sys.stderr)` on line 351.
  Not a logging-discipline concern.

## Re-running the audit

```bash
# G2 — bookmark lifecycle pairing
git grep -nE 'startAccessingSecurityScopedResource' -- 'TeslaCam/*.swift'
git grep -nE 'stopAccessingSecurityScopedResource'  -- 'TeslaCam/*.swift'

# G3 — process spawn surface
git grep -nE '(Process\(\)|NSTask|posix_spawn|launchPath|executableURL)' -- 'TeslaCam/*.swift'
git grep -nE '(subprocess\.|Popen|os\.system|os\.exec|os\.spawn)' -- 'teslacam_cli/*.py'
```

Re-open G2 / G3 in the queue if either grep reveals new sites that don't
fit the patterns above.
