#!/bin/bash
# Package the current tag as a release archive, and publish it.
#
#   git tag v0.1.0 && ./Scripts/make-release.sh
#
# Refuses to run on a dirty tree or an untagged commit, because a release whose
# version cannot be traced to a commit is worse than no release (AD-33).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"

[ -z "$(git status --porcelain)" ] || { echo "!! working tree is dirty" >&2; exit 1; }
TAG="$(git describe --tags --exact-match 2>/dev/null)" || {
  echo "!! HEAD is not an exact tag. Tag it first: git tag v0.1.0" >&2; exit 1; }
echo "==> releasing $TAG"

# Never ship a release carrying user data, even by accident.
./Scripts/check-no-user-data.sh >/dev/null

INSTALL=0 ./Scripts/build-app.sh >/dev/null
APP="$ROOT/.build/stage.noindex/Minutes.app"
[ -d "$APP" ] || { echo "!! build produced no bundle" >&2; exit 1; }

BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "v$BUILT" = "$TAG" ] || { echo "!! bundle says $BUILT but the tag is $TAG" >&2; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"
ZIP="$DIST/Minutes-$BUILT.zip"
echo "==> archiving"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | sed "s|$DIST/||" > "$ZIP.sha256"

echo "==> $(basename "$ZIP")  $(du -h "$ZIP" | cut -f1)"
cat "$ZIP.sha256" | sed 's/^/    /'
lipo -archs "$APP/Contents/MacOS/Minutes" | sed 's/^/    arch: /'
codesign --verify --strict "$APP" && echo "    signature verifies"

if command -v gh >/dev/null 2>&1; then
  echo "==> publishing to GitHub"
  gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
     --title "$TAG" --notes-file "$ROOT/dist/notes.md" 2>/dev/null \
  || gh release create "$TAG" "$ZIP" "$ZIP.sha256" --title "$TAG" --generate-notes \
  || echo "!! gh could not publish; upload $ZIP and $ZIP.sha256 manually"
else
  echo "==> gh not installed; upload these two files to the $TAG release:"
  echo "    $ZIP"
  echo "    $ZIP.sha256"
fi
