#!/bin/bash
# Keep the authoring corpus in source; ship only its runtime assets and licenses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:?destination bundle required}"
[[ "$DESTINATION" = /*.app/Contents/Resources/SceneStockAssets.bundle ]] || exit 2
[[ ! -L "$DESTINATION" ]] || exit 2
mkdir -p "$DESTINATION"
/usr/bin/rsync -a --delete --delete-excluded \
  --exclude='.mimosa' --exclude='.DS_Store' \
  --exclude='/assets/effects/*/preview/' --exclude='/assets/presets/*/preview/' \
  --exclude='/assets/materials/particle/***_preview.gif' \
  "$ROOT/MyWallpaperX/Resources/SceneStockAssets.bundle/" "$DESTINATION/"
