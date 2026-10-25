#!/bin/bash
# Keep the authoring corpus in source; ship only its runtime assets and licenses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:?destination bundle required}"
[[ "$DESTINATION" = /*.app/Contents/Resources/SceneStockAssets.bundle ]] || exit 2
[[ ! -L "$DESTINATION" ]] || exit 2
mkdir -p "$DESTINATION"
# A failed refresh must not leave a successful inventory from an older copy.
/bin/rm -f "$DESTINATION/SceneStockIndex.json"
/usr/bin/rsync -a --delete --delete-excluded \
  --exclude='.mimosa' --exclude='.DS_Store' \
  --exclude='/assets/effects/*/preview/' --exclude='/assets/presets/*/preview/' \
  --exclude='/assets/materials/particle/***_preview.gif' \
  "$ROOT/MyWallpaperX/Resources/SceneStockAssets.bundle/" "$DESTINATION/"

# Use the runtime index kernel on the final filtered assets. This helper and
# its native module cache are build intermediates, never App resources.
STOCK_WORK_BASE="${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$STOCK_WORK_BASE"
STOCK_WORK="$(/usr/bin/mktemp -d "$STOCK_WORK_BASE/mwx-stock-index.XXXXXX")"
trap '/bin/rm -rf -- "$STOCK_WORK"' EXIT
xcrun --sdk macosx swiftc -parse-as-library -O -whole-module-optimization \
  "$ROOT/MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift" \
  "$ROOT/script/generate-scene-stock-index.swift" \
  -module-cache-path "$STOCK_WORK/modules" \
  -o "$STOCK_WORK/generate-scene-stock-index"
"$STOCK_WORK/generate-scene-stock-index" \
  "$DESTINATION/assets" "$DESTINATION/SceneStockIndex.json"
