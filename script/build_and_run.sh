#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
if [[ -n "${TESLACAM_BUILD_ENV:-}" && -f "$TESLACAM_BUILD_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$TESLACAM_BUILD_ENV"
else
  source /Users/bolyki/dev/source/build-env.sh
fi

DERIVED_DATA="${TESLACAM_DERIVED_DATA:-${XCODE_DERIVED_DATA_PATH:-/Users/bolyki/dev/library/derived-data}/Teslacam}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/TeslaCam.app"

pkill -x TeslaCam || true

xcodebuild \
  -project TeslaCam.xcodeproj \
  -scheme TeslaCam \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

open -n "$APP_PATH"
