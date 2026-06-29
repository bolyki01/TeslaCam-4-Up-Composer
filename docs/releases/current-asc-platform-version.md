# TeslaCam - App Store Connect Platform Version Information

Source: current ASC copy prepared for the 1.0 release. Plain text only.

## Version

- App: TeslaCam
- Platform: macOS and iOS/iPadOS
- macOS Bundle ID: `com.magrathean.TeslaCam`
- iOS Bundle ID: `com.magrathean.TeslaCam.iPad`
- Version Number: `1.0`
- Build Number: `1`
- App Store app id: not present in the current ASC app list yet
- Copyright: `2026 Magrathean UK Ltd.`

## Promotional Text

Limit: 170 characters

```text
Review TeslaCam footage fast. Drop in a folder, inspect every camera, scrub recorded time, and export evidence clips locally.
```

Characters: 123

## Description

Limit: 4000 characters

```text
TeslaCam is a local-first reviewer and exporter for TeslaCam and Sentry Mode footage.

Drop in a TeslaCam folder and the app builds a clean timeline from the camera clips it finds. Review four-camera HW3 footage or six-camera HW4 footage in a fixed grid, jump through recorded time, inspect embedded telemetry when available, and export the selected range.

WHY TESLACAM

Simple folder workflow. Choose or drop a TeslaCam, SavedClips, SentryClips, or RecentClips folder and let the app organize the clips.

One useful timeline. TeslaCam merges clips by time, skips dead gaps while seeking, and keeps the review surface focused on footage that exists.

Multi-camera review. HW3 footage appears as a 2x2 grid. HW4 footage appears as an adaptive six-camera grid.

Telemetry-aware. When Tesla embeds telemetry, the app shows speed, GPS, pedal, gear, brake, signal, heading, and G-force information alongside the footage.

Evidence exports. Export selected ranges as original camera tracks where possible or HEVC evidence clips with telemetry overlays when needed.

Local by design. Video processing happens on your device. No account, cloud upload, tracking service, or external telemetry pipeline is required.

WHAT YOU GET

Folder Import
Open a TeslaCam storage folder directly from local disk, removable storage, or Files.

Camera Grid
Review synchronized front, back, repeater, side, and pillar cameras in one view.

Timeline
Scrub through recorded footage without spending time on long empty periods between clips.

Clip Information
See clip time, selected range, camera coverage, and available vehicle telemetry.

Export
Export the selected snippet for review, insurance, evidence, or personal archive workflows.

REQUIREMENTS

- TeslaCam, SavedClips, SentryClips, or RecentClips media exported by a Tesla vehicle.
- Embedded telemetry is optional and depends on the source clips produced by the vehicle.

PRIVACY

TeslaCam processes user-selected video files locally. Recordings can contain people, vehicles, locations, and other personal data. You are responsible for lawful collection, retention, export, and sharing of footage.

TeslaCam is not affiliated with, endorsed by, or sponsored by Tesla, Inc.
```

Characters: 2125

## Keywords

Limit: 100 bytes

```text
tesla,teslacam,sentry,dashcam,ev,video,clip,export,telemetry,gps,hevc,camera,evidence
```

Bytes: 89

## What's New in This Version

Limit: 4000 characters

```text
TeslaCam 1.0 is the first App Store release.

- Drop in a TeslaCam, SavedClips, SentryClips, or RecentClips folder and build one usable timeline.
- Review HW3 four-camera footage and HW4 six-camera footage in a fixed grid.
- Scrub recorded time without wasting space on dead gaps between clips.
- Inspect GPS, speed, pedal, gear, brake, signal, heading, and G-force telemetry when Tesla embeds it.
- Export selected clips with the original camera tracks or evidence-ready HEVC with telemetry overlays.
```

Characters: 547

## URLs

- Marketing URL: `https://magrathean.uk/`
- Support URL: `https://magrathean.uk/`
- Privacy Policy URL: fill before submission
- EULA / Terms URL: fill before submission

## Screenshots and App Preview

- Ready iPhone screenshot: `/Users/bolyki/dev/source/Teslacam/.cache/appstore-screens-v1/ready/iphone/01-review-export-iphone.png`
- Ready iPad screenshot: `/Users/bolyki/dev/source/Teslacam/.cache/appstore-screens-v1/ready/ipad/01-review-export-ipad.png`
- macOS screenshots: user will capture manually.
- App Preview: none supplied.

Upload device types:

- iPhone screenshot: `IPHONE_69`
- iPad screenshot: `IPAD_PRO_3GEN_129`

## Routing App Coverage File

Not applicable. TeslaCam is not a Maps routing app and does not need a `.geojson` routing coverage file.

## Version Release Settings

Use manual release after App Review approval unless a different release date is selected in App Store Connect.

## Phased Release and Rating

- Phased Release for Automatic Updates: No for 1.0.
- Reset Overview Rating: No.

## App Review Information

Sign-in required: No.

Notes:

```text
TeslaCam is a local-first TeslaCam and Sentry Mode footage reviewer/exporter. It processes only user-selected video folders and does not require an account or network service.

To test without real TeslaCam footage, launch the app and use the built-in demo/sample mode. The demo opens a sample timeline with multi-camera layout, timeline controls, telemetry values, and export controls.

For real footage testing, choose a folder containing TeslaCam, SavedClips, SentryClips, or RecentClips MP4 files named with Tesla timestamp and camera names.

The app is not affiliated with, endorsed by, or sponsored by Tesla, Inc.
```

Contact:

- Email: `contact@magrathean.uk`
- Phone: fill in App Store Connect account contact phone

## ASC CLI Handoff

The installed CLI is `/opt/homebrew/bin/asc`.

Auth and app lookup:

```sh
/opt/homebrew/bin/asc auth status
/opt/homebrew/bin/asc apps list --output json
```

After the TeslaCam app record exists, set:

```sh
APP_ID="<teslacam-app-id>"
VERSION="1.0"
BUILD="1"
```

Inspect or create the version:

```sh
/opt/homebrew/bin/asc versions list --app "$APP_ID"
/opt/homebrew/bin/asc versions create --app "$APP_ID" --version "$VERSION" --platform IOS
```

Build number and upload:

```sh
/opt/homebrew/bin/asc builds next-build-number --app "$APP_ID" --version "$VERSION" --platform IOS
/opt/homebrew/bin/asc builds upload --app "$APP_ID" --ipa "/path/to/TeslaCam.ipa"
```

Screenshots:

```sh
/opt/homebrew/bin/asc screenshots upload --app "$APP_ID" --version "$VERSION" --path "/Users/bolyki/dev/source/Teslacam/.cache/appstore-screens-v1/ready/iphone" --device-type IPHONE_69
/opt/homebrew/bin/asc screenshots upload --app "$APP_ID" --version "$VERSION" --path "/Users/bolyki/dev/source/Teslacam/.cache/appstore-screens-v1/ready/ipad" --device-type IPAD_PRO_3GEN_129
```

Readiness:

```sh
/opt/homebrew/bin/asc validate --app "$APP_ID" --version "$VERSION" --platform IOS
```
