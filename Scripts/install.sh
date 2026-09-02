#!/bin/bash
# Download the latest release of Minutes and install it to /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/NiklasLuettringhaus/Minutes/main/Scripts/install.sh | bash
#
# WHAT THIS DOES THAT YOU SHOULD KNOW ABOUT:
# Minutes is signed, but not with an Apple Developer ID. macOS blocks such an
# app only when the file carries a quarantine flag, and quarantine is set by
# browsers, not by curl — so an app fetched by this script is not quarantined
# and opens normally. Measured, not assumed: a curl download has no quarantine
# attribute and launches; the same app with a browser's quarantine flag is
# blocked outright.
#
# The xattr call below is therefore defensive, and usually a no-op. It matters
# if you downloaded the zip yourself from the Releases page in a browser.
#
# What this does not fix: because the signature is ad-hoc, installing a new
# version revokes microphone and system-audio consent, and macOS will ask again.
set -euo pipefail

REPO="NiklasLuettringhaus/Minutes"
APP="/Applications/Minutes.app"
BUNDLE_ID="dev.niklas.minutes"

die() { printf '\n%s\n' "$1" >&2; exit 1; }

# --- requirements, checked before anything is written -----------------------
[ "$(uname -s)" = "Darwin" ] || die "Minutes is a macOS app."

if [ "$(uname -m)" != "arm64" ]; then
  die "Minutes needs an Apple Silicon Mac.
It transcribes on the Neural Engine, which Intel Macs do not have.
This is a hard requirement, not a performance note."
fi

OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$OS_MAJOR" -lt 15 ]; then
  die "Minutes needs macOS 15 or later. This Mac runs $(sw_vers -productVersion)."
fi

# --- find the latest release ------------------------------------------------
echo "==> looking up the latest release"
API="https://api.github.com/repos/$REPO/releases/latest"
JSON="$(curl -fsSL "$API")" || die "Could not reach GitHub."

TAG="$(printf '%s' "$JSON" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("tag_name",""))')"
URL="$(printf '%s' "$JSON" | /usr/bin/python3 -c '
import sys, json
d = json.load(sys.stdin)
for a in d.get("assets", []):
    if a["name"].endswith(".zip"):
        print(a["browser_download_url"]); break
')"
SUMURL="$(printf '%s' "$JSON" | /usr/bin/python3 -c '
import sys, json
d = json.load(sys.stdin)
for a in d.get("assets", []):
    if a["name"].endswith(".sha256"):
        print(a["browser_download_url"]); break
')"

[ -n "$TAG" ] || die "No release found for $REPO yet."
[ -n "$URL" ] || die "Release $TAG has no .zip asset."
echo "    $TAG"

# --- download ---------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "==> downloading"
curl -fsSL "$URL" -o "$TMP/Minutes.zip" || die "Download failed."

if [ -n "$SUMURL" ]; then
  echo "==> checking the download is intact"
  curl -fsSL "$SUMURL" -o "$TMP/Minutes.zip.sha256"
  WANT="$(awk '{print $1}' "$TMP/Minutes.zip.sha256")"
  GOT="$(shasum -a 256 "$TMP/Minutes.zip" | awk '{print $1}')"
  [ "$WANT" = "$GOT" ] || die "Checksum mismatch. Downloaded file does not match the release.
  expected $WANT
  got      $GOT"
  echo "    ok"
  # Worth being precise: the zip and its checksum come from the same place, so
  # this proves the download was not corrupted. It does not prove who built it.
else
  echo "    no checksum published for $TAG; skipping the integrity check"
fi

echo "==> unpacking"
/usr/bin/ditto -x -k "$TMP/Minutes.zip" "$TMP/out" || die "Could not unpack the archive."
SRC="$TMP/out/Minutes.app"
[ -d "$SRC" ] || die "The archive did not contain Minutes.app."

# --- the bypass, announced --------------------------------------------------
echo "==> clearing any quarantine flag (normally none: curl does not set one)"
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

# --- install ----------------------------------------------------------------
if pgrep -f "$APP/Contents/MacOS/Minutes" >/dev/null 2>&1; then
  echo "==> quitting the running copy"
  osascript -e 'quit app "Minutes"' 2>/dev/null || true
  sleep 2
fi

echo "==> installing to $APP"
[ -w /Applications ] || die "/Applications is not writable by $(whoami)."
rm -rf "$APP"
/bin/cp -R "$SRC" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"

cat <<DONE

Installed Minutes $VER to $APP

Open it:            open -a Minutes
Check the setup:    $APP/Contents/MacOS/Minutes --doctor

Two permissions are needed and macOS will ask for them the first time you
record. The system-audio one cannot be checked by any API, so Minutes gives you
a five-second test in Getting Started that reports, per stream, whether audio
actually arrived. Run it once.

One thing to expect: because the app is not signed with an Apple Developer ID,
installing a new version revokes those permissions and you will be asked again.
If recording ever stops working after an update, that is why:

  tccutil reset Microphone $BUNDLE_ID
  tccutil reset SystemAudioCaptureRequests $BUNDLE_ID

DONE
