#!/usr/bin/env bash
# Generate ios/Nook.xcodeproj from ios/project.yml with the pinned XcodeGen,
# and record tool versions in build/logs/versions.txt.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

xcodegen_bin="$(bash scripts/install-xcodegen.sh)"

log "Generating Xcode project"
"$xcodegen_bin" generate --spec ios/project.yml

{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  sw_vers 2>/dev/null || true
  xcodebuild -version 2>/dev/null || true
  swift --version 2>&1 | head -n 1 || true
  echo "xcodegen: $("$xcodegen_bin" --version)"
} > "$LOG_DIR/versions.txt"
cat "$LOG_DIR/versions.txt"
