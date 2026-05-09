# Churn analysis — 2026-05-09

`git log --since='3 months ago'` snapshot. High-churn files are queue
candidates for refactoring (likely under-tested or over-coupled). Re-run
the commands at the bottom monthly to track whether the planned
extractions actually relieve pressure.

## Top files by total commits since 2026-02-09

| Commits | File | Notes |
|---:|---|---|
| 21 | `docs/improvement/loop-log.md`           | Loop's own append-only log; expected |
| 12 | `TeslaCamTests/TeslaCamTests.swift`      | Test file; most churn is *adding* coverage |
| 12 | `TeslaCam/AppState.swift`                | **central state holder; split planned (plan 03)** |
| 9  | `TeslaCam/ContentView.swift`             | View layer; design pass shipped, churn should slow |
| 9  | `README.md`                              | Docs evolution |
| 8  | `TeslaCam/Models.swift`                  | Domain types; A1/A2 fixture work touches it |
| 8  | `TeslaCam/Main.swift`                    | App entry / settings UI |
| 7  | `teslacam_cli/composer.py`               | Pipeline center (D2 parallelism) |
| 7  | `teslacam_cli/cli.py`                    | CLI surface (entrypoint refactors) |
| 7  | `TeslaCam/NativeExportController.swift`  | **export controller; ExportJobStore split planned (plan 02)** |
| 7  | `TeslaCam.xcodeproj/project.pbxproj`     | Build config; targets + iPad work |
| 6  | `docs/architecture-deepening/06-repo-hygiene.md` | Plan note status updates |
| 6  | `docs/architecture-deepening/01-domain-contract-owner.md` | Plan note status updates |
| 5  | `tests/test_scanner.py`                  | Scanner test additions |
| 5  | `tests/test_domain_contract.py`          | Contract parity tests (A1/A2/A7/F2) |
| 5  | `teslacam_cli/scanner.py`                | Scanner refactors |
| 5  | `teslacam_cli/ffmpeg_tools.py`           | D3 error reporting + tool resolution |
| 5  | `docs/domain-contract.md`                | Contract doc evolution |
| 5  | `TeslaCam/Indexer.swift`                 | Native scan logic; Phase B candidate |
| 5  | `AGENTS.md`                              | Agent guide |

## Interpretation

- **`AppState.swift` and `NativeExportController.swift` are the right
  refactor targets.** Both already have plan notes; the churn data
  reinforces them. Extracting `IndexingStore`, `PlaybackStore`,
  `ExportProgressStore` (plan 03) and `ExportJobStore` (plan 02) is
  high-leverage: high-churn files become smaller per-store stores
  with focused responsibilities and unit tests.
- **`TeslaCamTests.swift` churn is healthy.** Most commits *add* tests
  (sandbox revoke, layout parity, scan parity, export plan validation).
  Splitting only matters if compile-time becomes painful.
- **`ContentView.swift` and `Models.swift` are at the edge.** If they
  keep climbing, consider splitting along the same store-extraction
  axis.
- The `.pbxproj` churn is structural (target additions, iPad scheme,
  CI tweaks) and cannot easily be reduced.

## Re-running

```bash
# Total churn since 3 months ago
git log --since='3 months ago' --pretty=format: --name-only \
  | grep -v '^$' | sort | uniq -c | sort -rn | head -20

# Fix-flavoured commits only (filtering: "fix", "bug", "regression",
# "crash", "broken")
git log --since='3 months ago' -i \
  --grep='fix\|bug\|regression\|crash\|broken' \
  --pretty=format: --name-only \
  | grep -v '^$' | sort | uniq -c | sort -rn | head -15
```

Compare against this snapshot quarterly.
