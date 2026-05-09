# Loop log

One line per loop iteration: `HH:MM | task-id | result | perf-delta | commit-sha`.

Append-only. Read the last 5 entries before picking the next task.

07:06 | A1 | done | n/a (correctness lock) | a3b18ba
07:13 | A2 | done | n/a (correctness lock) | 6467a8a
07:18 | A7 | done | n/a (correctness lock + 3 new fixtures) | 0866e90
07:26 | D3 | done | actionable error UX (tail=40 lines + filter graph) | d3c27e4
07:32 | D2 | done | parallel ffprobe (4 workers, ~4x on probe phase) | e2ff83d
07:34 | D7 | done | unicode round-trip locked | a92343d
07:34 | H3+J4 | clean (audit) | n/a | 3914e39
07:36 | D6 | clean (audit) | n/a — pathlib everywhere, no os.path.join / sep concat | --
07:40 | F2 | done | parser regression coverage (60 pinned edge cases) | 13e160d
07:42 | G2+G3 | clean (audit) | n/a — bookmark pairing + no shell injection | 0a51872
07:43 | G4 | clean (audit) | n/a — minimum entitlements only | 546fb4a
07:47 | F3 | done | sandbox revoke + partial-survivor SourceStore tests | a9c7cd0
07:49 | H1 | done | regen workflow documented in domain-contract.md | 13291cf
07:49 | F7 | clean (audit) | n/a — both CIs pick up parity tests via discover / target | --
08:01 | H4 | done | opt-in pre-commit hook + RUNBOOK section | 5cddd85
08:01 | H5 | clean (audit) | n/a — MACOSX_DEPLOYMENT_TARGET=26.0 only in pbxproj, no script overrides | --
08:01 | H6 | clean (audit) | n/a — zero shipping-code references to _legacy/ | --
