#!/bin/bash
# Story 1.1 / AD-16 — build, assemble and ad-hoc sign Minutes.app.
#
# Signing is part of the build, not packaging: TCC consent binds to the code
# signature, and a truly unsigned binary never receives the audio permission
# prompt at all. Ad-hoc identity is the binary hash, so consent is invalidated
# whenever the binary changes — expect to re-grant after a rebuild.
set -euo pipefail

CONFIG="${CONFIG:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Minutes.app"

echo "==> swift build ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Minutes"
[ -x "$BIN" ] || { echo "!! binary not found at $BIN" >&2; exit 1; }

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Minutes"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc signing (hardened runtime)"
codesign --force --sign - \
  --options runtime \
  --entitlements "$ROOT/Scripts/Minutes.entitlements" \
  --timestamp=none \
  "$APP"

codesign --verify --strict "$APP"
echo "==> signature"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|Signature|flags' || true

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\""
echo ""
echo "If recording stops working after a rebuild, macOS revoked consent because the"
echo "signature changed. Reset with:"
echo "  tccutil reset SystemAudioCaptureRequests dev.niklas.minutes"
echo "  tccutil reset Microphone dev.niklas.minutes"
