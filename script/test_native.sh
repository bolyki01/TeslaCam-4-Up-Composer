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

DERIVED_DATA="${TESLACAM_DERIVED_DATA:-${XCODE_DERIVED_DATA_PATH:-/Users/bolyki/dev/library/derived-data}/Teslacam-tests}"

xcodebuild \
  -project TeslaCam.xcodeproj \
  -scheme TeslaCam \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  build-for-testing

xcodebuild \
  -project TeslaCam.xcodeproj \
  -scheme TeslaCam \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:TeslaCamTests \
  test-without-building

xcodebuild \
  -project TeslaCam.xcodeproj \
  -scheme TeslaCam \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:TeslaCamUITests \
  test-without-building
