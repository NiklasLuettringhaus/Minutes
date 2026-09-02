#!/bin/bash
# Refuse to let user data into the repository.
#
# Minutes keeps everything it knows about you outside the repo, in
# ~/Library/Application Support/Minutes/ and your chosen notes folder. That
# separation is the product's central privacy claim, so it is enforced here
# rather than remembered: one script, run by both the pre-commit hook (staged
# files) and CI (the whole tree), so the two cannot drift apart.
#
#   ./Scripts/check-no-user-data.sh            # every tracked file
#   ./Scripts/check-no-user-data.sh --staged   # only what is about to commit
set -uo pipefail

MODE="${1:-tree}"
FAIL=0
MAX_BYTES=$((5 * 1024 * 1024))

# A 256-dimensional voice embedding, as written by SpeakerDirectory and by
# every meeting's centroids.json. Matched by shape, not by key name.
EMBEDDING_RE='\[[[:space:]]*-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?([[:space:]]*,[[:space:]]*-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?){31,}'

if [ "$MODE" = "--staged" ]; then
  FILES=$(git diff --cached --name-only --diff-filter=ACMR)
else
  FILES=$(git ls-files)
fi

[ -z "$FILES" ] && { echo "no files to check"; exit 0; }

reject() { echo "  REJECTED  $1"; echo "            $2"; FAIL=1; }

while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")

  # Recorded audio. Nothing in this repo should ever carry a waveform.
  case "$base" in
    *.wav|*.m4a|*.caf|*.aiff|*.aif|*.mp3|*.flac)
      reject "$f" "recorded audio — meeting audio stays in ~/Library/Application Support/Minutes/" ;;
  esac

  # The app's own on-disk state.
  case "$base" in
    meeting.json)   reject "$f" "a Meeting record (transcript, speakers, timings)" ;;
    centroids.json) reject "$f" "per-speaker voice centroids — biometric-adjacent (PRD 9.1)" ;;
    speakers.json)  reject "$f" "the speaker directory, including any enrolled voice fingerprint" ;;
    settings.json)  reject "$f" "user settings" ;;
    dev.niklas.minutes.plist) reject "$f" "the app's preferences domain" ;;
  esac

  # A path that looks lifted out of the app's storage.
  case "$f" in
    *Application?Support/Minutes/*|*Minutes/Meetings/*)
      reject "$f" "a path inside the app's user-data directory" ;;
  esac

  [ -f "$f" ] || continue

  # Size. Audio and models are the only things here that get large; a big blob
  # is worth a human look even when the name looks innocent.
  bytes=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$bytes" -gt "$MAX_BYTES" ]; then
    reject "$f" "$((bytes / 1024 / 1024)) MB — too large to be source; models and audio are downloaded, never committed"
  fi

  # A stored voice embedding, whatever the file is called and whatever key
  # holds it. Keying on the *shape* rather than the name is deliberate: the
  # first version of this check looked for "vector" and let a renamed
  # speakers.json (whose key is "centroid") straight through. A run of 32+
  # floats in one array is an embedding; no source file in this repo has one.
  if grep -qE "$EMBEDDING_RE" "$f" 2>/dev/null; then
    reject "$f" "contains a run of 32+ floats — that is the shape of a voice embedding"
  fi
done <<< "$FILES"

if [ "$FAIL" -ne 0 ]; then
  cat >&2 <<'MSG'

User data must not enter this repository.

Meetings, voices and settings live only on the machine that recorded them:
  ~/Library/Application Support/Minutes/    meetings, speakers.json, models
  your chosen notes folder                  the Markdown notes

If you need a case for a test, write a fixture. Fixtures can be harsher than
reality and they can exist before the meeting does.
MSG
  exit 1
fi

echo "no user data in $( [ "$MODE" = "--staged" ] && echo "the staged changes" || echo "the tree" ) — $(echo "$FILES" | wc -l | tr -d ' ') files checked"
