#!/usr/bin/env bash
# Workflow A (spec §13.3): Debug build of Nook.app for the iOS Simulator, used by App Preview.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_project

APP_PATH="build/ios-simulator/Build/Products/Debug-iphonesimulator/Nook.app"

log "Building $SCHEME for the iOS Simulator"
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ios-simulator \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$LOG_DIR/ios-simulator.log" | pretty

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH was not produced" >&2
  exit 1
fi

log "Built $APP_PATH"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" >&2 || true
lipo -info "$APP_PATH/Nook" >&2 || true
du -sh "$APP_PATH" >&2
