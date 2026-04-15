# Release Checklist

## Product

- app opens on onboarding from cold launch
- choose-folder flow indexes clips and reaches the loaded timeline
- true-time gaps show in the timeline and preview as no-recording
- `From`, `Export Video`, and `To` align and match size
- HW4 names `left`, `right`, `left_pillar`, `right_pillar` parse and export in centered 3x3 layout

## Mac App Store

- Apple Silicon only
- macOS 26 deployment target for app and tests
- app sandbox stays on
- open/save panels work from a cold launch
- app icon and bundle metadata are present and correct

## Export

- native export is the only shipping app path
- cancel, retry, and reveal-file flows work
- hidden-camera warnings match actual missing cameras
- composite export is rendered output, not passthrough

## Logs

- indexing logs show source, cameras, profile, and gap count
- seek logs show clip loads vs gap loads
- export logs show phase changes and failure reason
- Debug builds show recent in-app debug events for fast triage

## Tests

- run `script/test_native.sh`
- run `python3 -m unittest tests.test_scanner tests.test_layouts tests.test_timing`
- run `python3 -m unittest tests.test_integration` when ffmpeg fixtures are available
