#!/bin/zsh
# Build the FruitWave tvOS app.
# Usage: scripts/build.sh [destination]
#   destination  optional xcodebuild -destination string
#                (default: generic/platform=tvOS, no signing)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

# System default developer directory is CommandLineTools on this machine;
# use the full Xcode when the default cannot run xcodebuild.
if [[ -d /Applications/Xcode.app ]] && ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app
fi

DEST="${1:-generic/platform=tvOS}"

bash Scripts/bootstrap.sh
xcodebuild -project FruitWave.xcodeproj -scheme FruitWave \
  -destination "$DEST" \
  -derivedDataPath .build/xcode \
  build
