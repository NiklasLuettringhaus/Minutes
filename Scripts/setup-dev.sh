#!/bin/bash
# One-time setup for a fresh clone.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks
echo "pre-commit hook enabled (blocks meeting data, voices and settings)"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "!! Xcode command line tools not found: xcode-select --install" >&2
fi

swift --version | head -1
echo
echo "Build and install:  ./Scripts/build-app.sh"
echo "Test:               swift test"
echo "Check UI layout:    ./Scripts/uishot.sh --open"
