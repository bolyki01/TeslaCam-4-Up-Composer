# Loop log

One line per loop iteration: `HH:MM | task-id | result | perf-delta | commit-sha`.

Append-only. Read the last 5 entries before picking the next task.

07:06 | A1 | done | n/a (correctness lock) | a3b18ba
07:13 | A2 | done | n/a (correctness lock) | 6467a8a
07:18 | A7 | done | n/a (correctness lock + 3 new fixtures) | 0866e90
07:26 | D3 | done | actionable error UX (tail=40 lines + filter graph) | d3c27e4
