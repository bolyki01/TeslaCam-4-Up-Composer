# TeslaCam

TeslaCam is a macOS app for browsing and exporting Tesla Sentry/Dashcam footage. It auto-indexes a TeslaCam folder, plays all cameras in sync, and exports full-resolution HEVC composites.

## Features
- Auto-detects camera count (4 or 6) per folder
- Synchronized multi-cam playback
- Live seek
- Timestamp overlays
- Export range to HEVC at 1:1 quality
- Export progress + detailed log

## Requirements
- Apple Silicon Mac
- macOS with Metal + AVFoundation
- Xcode (for building from source)

## Build & Run
Open `TeslaCam.xcodeproj` in Xcode and run the `TeslaCam` scheme.

Or from the command line:
```bash
xcodebuild -project TeslaCam.xcodeproj -scheme TeslaCam -destination 'platform=macOS' build
open /path/to/Build/Products/Debug/TeslaCam.app
```

## Usage
1. Launch the app and pick a TeslaCam folder when prompted.
2. Use the full-width seeker to scrub.
3. Set an export range via `Range`.
4. Click `Export` to render HEVC output.

## CLI Export
You can also run a bash/zsh-friendly interactive wrapper from the repo root:

```bash
./teslacam.sh
```

The CLI flow is:
1. Enter the folder containing TeslaCam videos.
2. Enter export start date/time in `DD/MM/YYYY-HH:MM:SS`.
3. Enter export end date/time in `DD/MM/YYYY-HH:MM:SS`.
4. Enter an extraction directory, or press Enter to use `<source-folder>/output`.

Example date/time:

```text
01/04/2026-18:30:00
```

Notes:
- The CLI uses the bundled `ffmpeg`/`ffprobe`, so it can run on a bare macOS install.
- It exports visually high-quality `ProRes HQ` output by default.
- It currently reuses the existing 4-up / 6-up compositor scripts, so it does not yet burn telemetry overlays into the exported video.

## Export Notes
- Output is HEVC at max quality.
- Export log is written to:
  `~/Library/Caches/TeslaCam/export.log`

## Project Layout
- `TeslaCam/` — app source
- `TeslaCam/Resources/` — scripts + bundled ffmpeg
- `TeslaCamTests/` — tests
- `TeslaCamUITests/` — UI tests

## License
See `TeslaCam/Resources/LICENSES.md` for third-party licenses.
