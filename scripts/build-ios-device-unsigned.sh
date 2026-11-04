#!/usr/bin/env bash
# Workflow B (spec §13.3): unsigned Release build for iPhone, packaged as build/Nook-unsigned.ipa
# for re-signing on the user's side (万能签). No certificates or profiles are involved.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_project

APP_PATH="build/ios-device/Build/Products/Release-iphoneos/Nook.app"
IPA_PATH="build/Nook-unsigned.ipa"

log "Building $SCHEME for iOS devices (unsigned)"
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-device \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  2>&1 | tee "$LOG_DIR/ios-device.log" | pretty

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH was not produced" >&2
  exit 1
fi

log "Packaging $IPA_PATH"
rm -rf build/unsigned "$IPA_PATH"
mkdir -p build/unsigned/Payload
cp -R "$APP_PATH" build/unsigned/Payload/
(cd build/unsigned && zip -qry ../Nook-unsigned.ipa Payload)

lipo -info "$APP_PATH/Nook" >&2 || true
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" >&2 || true
ls -lh "$IPA_PATH" >&2
