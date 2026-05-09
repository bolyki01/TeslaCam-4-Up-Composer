# CLI planning-phase memory baseline — 2026-05-09

`script/profile_planning_memory.py` measures peak memory of the
planning pipeline (scan → select → manifest assembly) across synthetic
dataset sizes, using the same 60s-stub MediaProbe the regen scripts +
parity tests use. No real `ffprobe` runs during the measurement.

## Numbers

| N events | wall (s) | tracemalloc peak (KB) | manifest JSON size (KB) | peak ÷ json |
|---------:|---------:|----------------------:|------------------------:|------------:|
| 10       | 0.021    | 545                   | 12                      | 45×         |
| 100      | 0.149    | 1,351                 | 108                     | 12×         |
| 1,000    | 1.581    | 11,423                | 1,066                   | 11×         |
| 10,000   | 17.356   | 92,090                | 10,646                  | 9×          |

Each row is one HW4 timestamp per minute × 6 cameras. The wall-clock
column scales roughly linearly with N. Peak memory likewise scales
linearly at ≈9 MB per 1,000 events once N is large enough to amortize
fixed overhead (the 45× ratio at N=10 is dominated by interpreter
constants).

## Interpretation

- For a typical interactive run (a single drive, dozens to hundreds of
  events) the planning phase touches well under 12 MB peak. Not a
  concern.
- For a full saved year of TeslaCam (~10–30k events) planning peak
  crosses ~100–280 MB. Still tractable on a laptop but worth keeping
  on the queue.
- The dominant memory consumer is the in-memory manifest dict. Python
  dicts run ≈9–11× the equivalent JSON byte size; the manifest
  doesn't keep clip bytes, just metadata. There is no hot leak — the
  curve is linear and the ratio is constant.

## When it would matter

The current `--dry-run-json -` writes the full manifest in one go via
`json.dumps`. For a 10k-event archive that's a 90 MB transient peak
plus the JSON encoder's own buffers. If a user complains about CLI
memory on a year-long archive, the bounded fix is:

1. Switch `write_manifest_json` to `json.JSONEncoder().iterencode(...)`
   streaming to disk
2. Build the per-section manifests lazily (generator → write line)
3. Clear the scan + selection lists once they've been serialized

That cuts peak from "9× JSON size" to "1× JSON size + serializer
overhead". Tracked under D5 follow-up — not urgent for typical use.

## Re-running

```bash
source .cache/build-env.sh && source .cache/venv/bin/activate
python3 script/profile_planning_memory.py
```

Idempotent. Report back to this file when the contract surface
changes (new manifest fields, switch to streaming serialization,
selection algorithm change).
