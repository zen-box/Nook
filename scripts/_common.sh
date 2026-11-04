#!/usr/bin/env bash
# Shared helpers for the Nook build scripts. Source it; do not run it directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/build/logs"
mkdir -p "$LOG_DIR"

PROJECT_PATH="ios/Nook.xcodeproj"
SCHEME="Nook"

log() {
  printf '==> %s\n' "$*" >&2
}

require_project() {
  if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "error: $PROJECT_PATH not found. Run scripts/generate-project.sh first." >&2
    exit 1
  fi
}

# Pipe xcodebuild output through xcbeautify when it is installed (it is on Codemagic).
pretty() {
  if command -v xcbeautify >/dev/null 2>&1; then
    xcbeautify "$@"
  else
    cat
  fi
}
