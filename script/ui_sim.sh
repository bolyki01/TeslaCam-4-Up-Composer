#!/usr/bin/env bash
# Drive the TeslaCam iPad app in the iOS Simulator against a small slice of real
# footage, for visual verification of UI changes that the macOS test host cannot
# exercise (the iPad event browser, telemetry-unavailable state, map, playback).
#
# The macOS app is sandboxed in the test host so it cannot read an arbitrary
# footage folder; the Simulator can, once footage is copied into the app's data
# container. This script automates boot -> build -> install -> inject -> launch
# and drops a full-resolution screenshot you can open to inspect the result.
#
# Usage:
#   script/ui_sim.sh [screenshot.png]
#
# Env overrides:
#   TESLACAM_SIM        simulator device name (default: "iPad Pro 11-inch (M5)")
#   TESLACAM_FOOTAGE    real TeslaCam dump to slice from (default: ~/Downloads/Teslacam)
#   TESLACAM_SAMPLE_EVENTS  number of SentryClips event folders to copy (default: 2)
#
# Note: the app is landscape-locked; the Simulator window shows it upright in
# landscape. `xcrun simctl io ... screenshot` may capture rotated depending on
# device orientation — prefer the Simulator window itself for true orientation.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIM="${TESLACAM_SIM:-iPad Pro 11-inch (M5)}"
FOOTAGE="${TESLACAM_FOOTAGE:-$HOME/Downloads/Teslacam}"
SAMPLE_EVENTS="${TESLACAM_SAMPLE_EVENTS:-2}"
SHOT="${1:-/tmp/teslacam_sim.png}"
BID="com.magrathean.TeslaCam.iPad"
SCHEME="TeslaCam iPad"

# Build env (derived-data path etc.) — same resolution as the native lane.
resolve_build_env() {
  if [[ -n "${TESLACAM_BUILD_ENV:-}" && -f "${TESLACAM_BUILD_ENV}" ]]; then
    printf '%s\n' "$TESLACAM_BUILD_ENV"; return 0
  fi
  if [[ -f "$ROOT/.cache/build-env.sh" ]]; then printf '%s\n' "$ROOT/.cache/build-env.sh"; return 0; fi
  if [[ -f "/Users/bolyki/dev/source/build-env.sh" ]]; then printf '%s\n' "/Users/bolyki/dev/source/build-env.sh"; return 0; fi
  return 1
}

if BUILD_ENV="$(resolve_build_env)"; then
  # shellcheck disable=SC1090
  source "$BUILD_ENV"
fi
DERIVED="${XCODE_DERIVED_DATA_PATH:-$ROOT/.cache/dd}"

echo "==> Booting simulator: $SIM"
xcrun simctl boot "$SIM" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true

echo "==> Building iPad target"
xcodebuild -project TeslaCam.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "platform=iOS Simulator,name=$SIM" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$(find "$DERIVED/Build/Products" -name "TeslaCam iPad.app" -path "*iphonesimulator*" | head -1)"
[[ -n "$APP" ]] || { echo "Could not locate built app under $DERIVED" >&2; exit 1; }

echo "==> Installing $APP"
xcrun simctl install "$SIM" "$APP" >/dev/null
xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
# Launch once so the data container exists.
xcrun simctl launch "$SIM" "$BID" >/dev/null 2>&1 || true

CONTAINER="$(xcrun simctl get_app_container "$SIM" "$BID" data)"
DEST="$CONTAINER/Documents/TeslaCamSample"

echo "==> Slicing $SAMPLE_EVENTS event(s) from $FOOTAGE into the container"
rm -rf "$DEST"; mkdir -p "$DEST/SentryClips"
if [[ -d "$FOOTAGE/SentryClips" ]]; then
  ls "$FOOTAGE/SentryClips" | head -"$SAMPLE_EVENTS" | while read -r ev; do
    cp -R "$FOOTAGE/SentryClips/$ev" "$DEST/SentryClips/"
  done
else
  echo "No SentryClips under $FOOTAGE — the app will open onboarding." >&2
fi
echo "    clips: $(find "$DEST" -name '*.mp4' | wc -l | tr -d ' ')  event.json: $(find "$DEST" -name 'event.json' | wc -l | tr -d ' ')"

echo "==> Relaunching with TESLACAM_DEBUG_SOURCE=$DEST"
xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
SIMCTL_CHILD_TESLACAM_DEBUG_SOURCE="$DEST" xcrun simctl launch "$SIM" "$BID" >/dev/null
sleep 6

xcrun simctl io "$SIM" screenshot "$SHOT" >/dev/null 2>&1 || true
echo "==> Screenshot: $SHOT"
echo "    Open Simulator.app to drive the UI (the app is landscape-locked)."
