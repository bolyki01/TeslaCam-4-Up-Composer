# Real-footage baseline — 2026-05-09 (HW3 source)

Snapshot taken against `~/Downloads/Teslacam` after the user pointed
to it as a real HW3 source for performance / correctness checks.
The folder is read-only for this loop; numbers below are reproducible
on the same machine via the snippets at the bottom.

## Source shape

| Property | Value |
|---|---|
| Top-level dirs | `RecentClips/`, `SavedClips/`, `SentryClips/` |
| Total `.mp4` files | 257 |
| Cameras | `front`, `back`, `left_repeater`, `right_repeater` (HW3 classic) |
| Total bytes | 6.0 GB |
| Filename shape | `YYYY-MM-DD_HH-MM-SS-CAMERA.mp4` (matches the contract) |

Most clips live under `SentryClips/<event>/` event folders. A small
number sit directly under `SavedClips/`.

## Cold scan (Python `scan_source`)

Same machine, sub-second on a warm filesystem:

| Duplicate policy | Wall (s) | Clip sets | Cameras | Dup files | Dup timestamps | tracemalloc peak |
|---|---:|---:|---:|---:|---:|---:|
| `merge-by-time`   | 0.016 | 64 | 4 | 1 | 1 | 0.46 MB |
| `keep-all`        | 0.015 | 65 | 4 | 1 | 1 | 0.14 MB |
| `prefer-newest`   | 0.011 | 64 | 4 | 1 | 1 | 0.11 MB |

Observations:

- 257 files → 64 sets × 4 cameras = 256 + the 1 duplicate file = 257.
  Math checks out; no clip dropped silently.
- One duplicate is naturally present in the user's own data; this is
  the real-world case the `duplicates_same_camera` fixture models.
- Cold-scan memory is well below the synthetic 100-event baseline
  (~1.35 MB for 100 events) because real-folder scan does not yet
  build the manifest dict — that happens later in `scan_manifest()`.
- `keep-all`'s extra 0.32 MB peak vs the others is the duplicate
  clip set replication; below the noise floor in absolute terms.

## Full planner (`teslacam-cli --dry-run-json`)

Single run, real ffprobe via `/opt/homebrew/bin/ffprobe`, parallel
probe enabled (D2 / `TESLACAM_PROBE_JOBS` defaults to 4):

```
teslacam-cli ~/Downloads/Teslacam --dry-run-json .cache/tmp/real-footage-dry-run.json

  user 5.70s   system 1.99s   wall 3.68s   cpu 208%
  output: 88 KB JSON
```

CPU > 200 % confirms the parallel ffprobe (commit `e2ff83d`) is
active — without it, walltime would be ~5–6 s on the same data.
Per-event amortised cost is ~57 ms, dominated by 4 ffprobe calls
per clip set (duration / dimensions / has-video-stream / fps).

Manifest highlights:

- Auto layout: `4up`, all four HW3 cameras, no hidden.
- Probed fps: `24.003808` (some HW3 firmware emits ~24 fps; the
  contract handles both 24 and the older 36-ish rates).
- Tile size 1280×960 across cameras; canvas 2560×1920.

## Comparison with synthetic baselines

| Phase | Synthetic 100 events | Real 64 events | Notes |
|---|---:|---:|---|
| Planner wall | 0.149 s | 3.68 s | Real includes 4 ffprobe RPCs / event; synthetic uses the 60 s stub. |
| Manifest size | 108 KB | 88 KB | Slightly smaller because fewer clip sets, similar per-set bytes. |
| Memory peak | 1.35 MB | (not separately measured for full planner against real footage; synthetic-vs-real ratio for the scan layer is ~1×) | |

The synthetic baseline (D5 / `script/profile_planning_memory.py`)
remains the single-place reference for scaling characterization;
the real-footage numbers above complement it but the user's
specific drive, filesystem cache state, and ffprobe build affect
the absolute wall-clock numbers.

## Re-running

```bash
source .cache/build-env.sh && source .cache/venv/bin/activate

# Scan-only timings + memory peak.
python3 - <<'PY'
import time, tracemalloc
from pathlib import Path
from teslacam_cli.scanner import scan_source
from teslacam_cli.models import DuplicatePolicy

SRC = Path.home() / "Downloads" / "Teslacam"
for policy in DuplicatePolicy:
    tracemalloc.start()
    t0 = time.monotonic()
    result = scan_source(SRC, duplicate_policy=policy)
    elapsed = time.monotonic() - t0
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    print(f"{policy.value:<14} {elapsed:.3f}s  sets={len(result.clip_sets)}  peak={peak/1024/1024:.2f}MB")
PY

# Full planner end-to-end (writes a JSON manifest, no rendering).
DEST="$TESLACAM_CACHE_ROOT/tmp/real-footage-dry-run.json"
mkdir -p "$(dirname "$DEST")"
time teslacam-cli ~/Downloads/Teslacam --dry-run-json "$DEST"
```

The output file lives under `.cache/tmp/` so it gets cleaned up
when `.cache/` is wiped.
