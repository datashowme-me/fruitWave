#!/bin/zsh
# Per-fruit device acceptance: instrumented launch, 22s runtime, evidence pull.
# Usage: fruit-acceptance-loop.sh <fruit-slug> [<fruit-slug> ...]
# Evidence lands in Docs/Evidence/<slug>-acceptance/ (launch log + snapshots + app log).
set -u
export DEVELOPER_DIR=/Applications/Xcode.app
DEVICE=00008110-001A295A2144801E

for FRUIT in "$@"; do
  DIR="Docs/Evidence/${FRUIT}-acceptance"
  mkdir -p "$DIR"
  echo "=== ${FRUIT}: launch $(date +%H:%M:%S) ==="
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
    -e "{\"FW_ASSET_LAB\":\"1\",\"FW_SNAPSHOTS\":\"1\",\"FW_FRUIT\":\"${FRUIT}\"}" \
    com.example.FruitWave > "$DIR/launch.log" 2>&1
  grep -q "Launched application" "$DIR/launch.log" && echo "launch OK" || { echo "LAUNCH FAILED"; tail -5 "$DIR/launch.log"; continue; }
  sleep 22
  for f in "evidence_${FRUIT}_whole.png" "evidence_${FRUIT}_sliced.png" "evidence_${FRUIT}.log"; do
    if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
      --domain-identifier com.example.FruitWave --source "Library/Caches/$f" \
      --destination "$DIR/$f" >/dev/null 2>&1; then
      echo "pulled $f"
    else
      echo "MISSING $f"
    fi
  done
done
echo "=== batch done $(date +%H:%M:%S) ==="
