#!/usr/bin/env bash
# Run the Flutter toolchain in a Linux container.
#
# Why: on this Apple-Silicon host the native Dart VM hangs at code-signing
# validation (ADR 0005). Docker's Linux userland has no macOS AMFI layer, so
# `flutter analyze` / `flutter test` run cleanly here.
#
# Usage:  ./tool/flutter.sh test
#         ./tool/flutter.sh analyze
#         ./tool/flutter.sh pub get
#
# NOTE: iOS build/run is NOT possible in the container (needs macOS + Xcode).
set -euo pipefail

IMAGE="ghcr.io/cirruslabs/flutter:stable"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Cache pub packages across runs on a named volume for speed.
PUB_CACHE_VOL="playzy_pub_cache"

# Allocate a TTY only when attached to one, so this works both interactively
# and as a non-TTY automation/CI gate. A plain string (not an array) keeps this
# safe under `set -u` on macOS's bash 3.2, where empty-array expansion errors.
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
  TTY_FLAG="-it"
fi

# shellcheck disable=SC2086 # intentional word-split: expands to nothing when empty
exec docker run --rm ${TTY_FLAG} \
  -v "${APP_DIR}:/app" \
  -v "${PUB_CACHE_VOL}:/root/.pub-cache" \
  -w /app \
  "${IMAGE}" \
  flutter "$@"
