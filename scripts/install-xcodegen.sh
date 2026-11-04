#!/usr/bin/env bash
# Install the pinned XcodeGen release and print the path of its binary on stdout.
# Logs go to stderr so callers can capture the path:  xcodegen="$(bash scripts/install-xcodegen.sh)"

set -euo pipefail

VERSION="2.46.0"
SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"

if [[ -n "${XCODEGEN_VERSION:-}" && "${XCODEGEN_VERSION}" != "$VERSION" ]]; then
  echo "error: XCODEGEN_VERSION=${XCODEGEN_VERSION}, but this script pins ${VERSION}. Update VERSION and SHA256 together." >&2
  exit 1
fi

TOOLS_DIR="${NOOK_TOOLS_DIR:-$HOME/.nook-tools}"
INSTALL_DIR="$TOOLS_DIR/xcodegen-$VERSION"
BIN="$INSTALL_DIR/xcodegen/bin/xcodegen"

if [[ ! -x "$BIN" ]]; then
  echo "==> Installing XcodeGen $VERSION" >&2
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 -o "$tmp/xcodegen.zip" "$URL"

  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$tmp/xcodegen.zip" | awk '{print $1}')"
  else
    actual="$(sha256sum "$tmp/xcodegen.zip" | awk '{print $1}')"
  fi
  if [[ "$actual" != "$SHA256" ]]; then
    echo "error: XcodeGen checksum mismatch (expected $SHA256, got $actual)" >&2
    exit 1
  fi

  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  unzip -q "$tmp/xcodegen.zip" -d "$INSTALL_DIR"
  chmod +x "$BIN"
fi

echo "==> XcodeGen: $("$BIN" --version)" >&2

if [[ -n "${CM_ENV:-}" ]]; then
  echo "PATH=$(dirname "$BIN"):$PATH" >> "$CM_ENV"
fi

echo "$BIN"
