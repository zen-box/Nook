#!/usr/bin/env bash
# Run the app's unit and UI tests on an iOS Simulator and collect the results.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
require_project

DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"
RESULT_DIR="build/test-results"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"

log "Testing $SCHEME on: $DESTINATION"
set +e
xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath build/ios-tests \
  -resultBundlePath "$RESULT_DIR/Nook.xcresult" \
  2>&1 | tee "$LOG_DIR/ios-tests.log" | pretty --report junit --report-path "$RESULT_DIR" --junit-report-filename junit.xml
status=$?
set -e

if [[ -d "$RESULT_DIR/Nook.xcresult" ]]; then
  (cd "$RESULT_DIR" && zip -qry Nook.xcresult.zip Nook.xcresult)
fi
exit "$status"
