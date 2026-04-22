# Teslacam Domain Contract

This contract pins the behavior that must stay aligned between the native macOS app and the Python CLI. The app remains the shipping macOS export path. The CLI remains portable and dependency-light.

## Clip file discovery

Source inputs are treated as untrusted media trees. Recursive scans consider regular `.mp4` and `.mov` files whose basename matches:

```text
YYYY-MM-DD_HH-MM-SS-CAMERA.(mp4|mov)
```

The timestamp is parsed with `yyyy-MM-dd_HH-mm-ss` / `%Y-%m-%d_%H-%M-%S` in the local timezone used by the process. Files with malformed timestamps, unknown camera tokens, unsupported extensions, or hidden path components are ignored. Hidden path components are any relative path segment beginning with `.`.

## Camera normalization

Camera tokens are lowercased, hyphens are converted to underscores, repeated underscores are collapsed, and trailing numeric suffixes are removed. The canonical camera values are:

```text
front, back, left_repeater, right_repeater, left, right, left_pillar, right_pillar
```

Accepted aliases include `fwd` and `forward` for `front`; `rear` and `rear_camera` for `back`; `left_rear` for `left_repeater`; and `right_rear` for `right_repeater`. Tokens containing both side and `pillar` map to pillar cameras. Tokens containing both side and `repeat` map to repeater cameras.

## Duplicate policy

A duplicate file is a file with the same timestamp and normalized camera as another indexed file.

`merge-by-time` / `mergeByTime` produces one clip set per timestamp and keeps the lexicographically earliest path for duplicate timestamp-camera pairs.

`prefer-newest` / `preferNewest` produces one clip set per timestamp and keeps the file with the greatest modification time for duplicate timestamp-camera pairs. Modification-time ties fall back to the lexicographically earliest path.

`keep-all` / `keepAll` keeps the first timestamp set as the primary set. If a later file has a camera that is missing from the primary set, it is added to the primary set. If a later file duplicates an existing timestamp-camera pair, it creates an additional one-camera clip set for that duplicate file.

Duplicate timestamp count is the number of timestamps with at least one duplicate timestamp-camera pair, not the number of duplicate files.

## Clip grouping and sort order

Clip sets are sorted by start time, then timestamp string, then deterministic file paths. A clip set duration is the maximum duration among its cameras. If media probing cannot establish a duration, the app uses its native fallback and the CLI uses the scan-only manifest without probing.

## Layout selection

The canonical camera order is:

```text
front, back, left_repeater, right_repeater, left, right, left_pillar, right_pillar
```

`legacy4` / forced 4-camera uses `front, back, left_repeater, right_repeater` in a two-by-two layout.

`sixcam` / forced 6-camera uses `front, back, left, right, left_pillar, right_pillar` in a centered three-by-three layout with empty top-left, top-right, bottom-centre cells.

`auto` chooses the 6-camera layout when any of `left`, `right`, `left_pillar`, or `right_pillar` are present. Otherwise it chooses the 4-camera layout.

## Output naming and conflicts

Default CLI output names use:

```text
teslacam_MODE_START_to_END.mp4
```

where `START` and `END` are contract timestamps. A directory output argument receives the default filename. A non-`.mp4` CLI output path is normalized to `.mp4`.

Output conflicts are handled by policy:

`unique` appends `-2`, `-3`, and so on before the extension.

`overwrite` uses the requested path and lets the export path replace the file.

`error` fails before export work starts.

## Dry-run manifest

Dry-run manifests are JSON objects with `schema_version: 1`. They are intended for fixture parity checks and user-visible preflight output. They include scan summary, duplicate counts, selected range, selected clip sets, layout, dimensions, output path, duplicate policy, and output conflict policy.

Both Swift and Python implementations must keep the fixture cases under `fixtures/domain/cases` passing before domain behavior changes are accepted.
