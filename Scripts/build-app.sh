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
STAGE="$ROOT/.build/stage.noindex"
APP="$STAGE/Minutes.app"

echo "==> swift build ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Minutes"
[ -x "$BIN" ] || { echo "!! binary not found at $BIN" >&2; exit 1; }

echo "==> assembling bundle"
rm -rf "$STAGE"
mkdir -p "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Minutes"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Scripts/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
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

# Install to /Applications so Spotlight indexes it and it behaves like an app.
# A bundle living in a build directory with no icon is effectively unfindable —
# that is exactly how it got lost the first time.
if [ "${INSTALL:-1}" = "1" ]; then
  DEST="/Applications/Minutes.app"
  if [ -w /Applications ]; then
    echo "==> installing to $DEST"
    osascript -e 'quit app "Minutes"' 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # Re-sign in place: copying can disturb the signature, and TCC keys off it.
    codesign --force --sign - --options runtime \
      --entitlements "$ROOT/Scripts/Minutes.entitlements" --timestamp=none "$DEST" 2>/dev/null
    APP="$DEST"
    # Leave exactly one copy on the machine. Two bundles means two Spotlight
    # hits for the same app, which is confusing and was a real complaint.
    rm -rf "$STAGE"
    rm -rf "$ROOT/dist"
  else
    echo "!! /Applications not writable; the app is at $APP"
  fi
fi

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\""
echo ""
echo "If recording stops working after a rebuild, macOS revoked consent because the"
echo "signature changed. Reset with:"
echo "  tccutil reset SystemAudioCaptureRequests dev.niklas.minutes"
echo "  tccutil reset Microphone dev.niklas.minutes"
