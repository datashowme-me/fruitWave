#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "usage: $0 <asset-directory> <fruit-slug>"
  exit 64
fi

asset_directory=$1
fruit_slug=$2
whole_asset="$asset_directory/${fruit_slug}_whole.usdz"
sliced_asset="$asset_directory/${fruit_slug}_sliced.usdz"
metadata="$asset_directory/${fruit_slug}.json"

for required_file in "$whole_asset" "$sliced_asset" "$metadata"; do
  if [[ ! -f "$required_file" ]]; then
    print -u2 "missing deliverable: $required_file"
    exit 66
  fi
done

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun usdchecker "$whole_asset"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun usdchecker "$sliced_asset"

scene_dump=$(mktemp -t "${fruit_slug}-sliced.XXXXXX.usda")
trap 'rm -f "$scene_dump"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun usdcat "$sliced_asset" > "$scene_dump"

for entity_name in "${fruit_slug}_half_left" "${fruit_slug}_half_right"; do
  if ! rg -q "def (Xform|Scope|Mesh) \"${entity_name}\"" "$scene_dump"; then
    print -u2 "missing sliced entity: $entity_name"
    exit 65
  fi
done

print "FRUIT_USDZ_VALID fruit=$fruit_slug"
