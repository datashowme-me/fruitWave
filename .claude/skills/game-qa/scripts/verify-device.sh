#!/bin/zsh
# game-qa Gate checkpoint: build + unit tests + on-device deploy/launch.
# Usage: scripts/verify-device.sh [--skip-tests] [device-identifier]
# Evidence is archived under Docs/Evidence/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app ]] && ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app
fi

SKIP_TESTS=0
DEVICE=""
for arg in "$@"; do
  if [[ "$arg" == "--skip-tests" ]]; then
    SKIP_TESTS=1
  else
    DEVICE="$arg"
  fi
done

echo "== 1/3 build =="
bash "$ROOT/.claude/skills/tvos-game-development/scripts/build.sh"

if [[ $SKIP_TESTS -eq 0 ]]; then
  echo "== 2/3 unit tests (tvOS simulator) =="
  SIM="Apple TV 4K (3rd generation)"
  xcrun simctl boot "$SIM" >/dev/null 2>&1 || true
  xcodebuild -project FruitWave.xcodeproj -scheme FruitWave \
    -destination "platform=tvOS Simulator,name=$SIM" \
    -derivedDataPath .build/xcode \
    test
fi

echo "== 3/3 device deploy + launch =="
bash "$ROOT/.claude/skills/tvos-game-development/scripts/deploy.sh" "$DEVICE"

echo "== done: fill the Docs/M1-Verification.md rows for this stage =="
