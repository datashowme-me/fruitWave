#!/bin/zsh
# Device-signed build, install and launch on the target Apple TV.
# Usage: scripts/deploy.sh [device-identifier]
#   device-identifier: uuid/udid/name accepted by devicectl
#   (default: auto-detect the first Apple TV in state "available (paired)").
# Evidence is appended to Docs/Evidence/deploy-<timestamp>.log.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

# The system default developer directory is CommandLineTools, whose
# xcodebuild still answers -version but cannot build tvOS apps. Always
# prefer the full Xcode when it is installed.
if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app
fi

if [[ $# -ge 1 ]]; then
  DEVICE="$1"
else
  # xcodebuild -destination needs the hardware UDID (ECID); the CoreDevice
  # identifier from `list devices` is not accepted. Prefer udid from the
  # JSON output, which both devicectl and xcodebuild understand.
  DEVICE="$(xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)["result"]["devices"]
except Exception:
    raise SystemExit(1)
for device in devices:
    if device.get("connectionProperties", {}).get("pairingState") == "paired":
        print(device.get("hardwareProperties", {}).get("udid", "") or device.get("identifier", ""))
        break
' 2>/dev/null)"
  if [[ -z "$DEVICE" ]]; then
    DEVICE="$(xcrun devicectl list devices 2>/dev/null \
      | awk '/Apple TV/ && /available \(paired\)/ {print $3; exit}')"
  fi
fi
if [[ -z "$DEVICE" ]]; then
  echo "error: no Apple TV available (paired). Wake the TV or pass an identifier." >&2
  exit 1
fi
echo "device: $DEVICE"

BUNDLE_ID=com.example.FruitWave

bash Scripts/bootstrap.sh

xcodebuild -project FruitWave.xcodeproj -scheme FruitWave \
  -destination "platform=tvOS,id=$DEVICE" \
  -derivedDataPath .build/xcode \
  build

# Prefer the device (appletvos) product; the simulator variant is not
# installable and `find` would list it first.
APP="$(find .build/xcode/Build/Products -maxdepth 3 -type d -name FruitWave.app -path '*appletvos*' | head -1)"
if [[ -z "$APP" ]]; then
  APP="$(find .build/xcode/Build/Products -maxdepth 3 -type d -name FruitWave.app | head -1)"
fi
if [[ -z "$APP" ]]; then
  echo "error: FruitWave.app not found under .build/xcode" >&2
  exit 1
fi
echo "app: $APP"

STAMP="$(date +%Y-%m-%d-%H%M%S)"
LOG="Docs/Evidence/deploy-$STAMP.log"
mkdir -p Docs/Evidence
{
  echo "=== deploy $STAMP ==="
  xcrun devicectl device info details --device "$DEVICE"
  echo "=== install ==="
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  echo "=== launch ==="
  # Flags must precede the bundle id: devicectl treats everything after it as
  # app arguments (verified on device: --terminate-existing after the id was
  # passed through as argv and never terminated anything).
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
} 2>&1 | tee "$LOG"
echo "evidence: $LOG"
