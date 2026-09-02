#!/bin/bash
# Renders the app's panes to PNG so a layout defect is findable from a terminal.
#
# Why this exists: every other check in this project runs from a terminal, and the
# one that could not was the one that kept breaking. Two increments shipped layout
# defects that 149 passing tests said nothing about — a speaker row that collapsed
# to one character per line, and chips that painted themselves unreadable on a
# selected row. Both were obvious in a picture and invisible from a shell, so the
# user found them instead of the build.
#
# Screen capture was tried first and does not work here: osascript has no
# assistive access on this machine and `screencapture` blocks on a permission
# prompt. ImageRenderer needs neither, because an app rendering its own view tree
# is not capturing anyone's screen — and it can render the *hard* cases on demand
# (sixteen speakers, a 40-character name, a 320pt column) without recording
# sixteen meetings first.
#
#   ./Scripts/uishot.sh              # renders to ./ui-shots
#   ./Scripts/uishot.sh /tmp/shots   # renders somewhere else
#   ./Scripts/uishot.sh --open       # renders, then opens the folder
#
# What it does NOT prove: that the running app looks like this. ImageRenderer
# walks the same view tree AppKit does, so a layout bug reproduces faithfully,
# but it resolves no focus state, runs no animation, and cannot draw a Button, a
# ProgressView or a Picker — those render as a yellow "unsupported" glyph, which
# is a limitation of the renderer and not a defect in the app. It answers "does
# this layout hold at this width", not "is the app correct".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPEN=0
OUT="$ROOT/ui-shots"
for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    -*)     echo "unknown flag: $arg" >&2; exit 2 ;;
    *)      OUT="$arg" ;;
  esac
done

cd "$ROOT"
echo "==> swift build (debug)"
swift build 2>&1 | tail -1
BIN="$(swift build --show-bin-path)/Minutes"
[ -x "$BIN" ] || { echo "!! binary not found at $BIN" >&2; exit 1; }

rm -rf "$OUT"
"$BIN" --uishot "$OUT"

if [ "$OPEN" = "1" ]; then open "$OUT"; fi
