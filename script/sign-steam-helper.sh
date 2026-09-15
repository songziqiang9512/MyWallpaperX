#!/bin/bash
# Sign each native dependency first, then the .NET apphost with MAP_JIT.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="${1:?helper directory required}"
IDENTITY="${2:?signing identity required}"
[[ -x "$HELPER_DIR/SteamService" && -f "$HELPER_DIR/libcoreclr.dylib" ]] || exit 1
TIMESTAMP=(--timestamp=none)
SIGN_OPTIONS=runtime
# Ad-hoc code has no Team ID for library validation. Keep this local path
# unhardened; real identities retain runtime with same-team native dependencies.
if [[ "$IDENTITY" == - ]]; then SIGN_OPTIONS=0; fi
if [[ "$IDENTITY" != - ]]; then TIMESTAMP=(--timestamp); fi
while IFS= read -r -d '' binary; do
  [[ "$binary" != "$HELPER_DIR/SteamService" ]] || continue
  if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    /usr/bin/codesign --force "${TIMESTAMP[@]}" --options "$SIGN_OPTIONS" --sign "$IDENTITY" "$binary"
  fi
done < <(/usr/bin/find "$HELPER_DIR" -type f -print0)
/usr/bin/codesign --force "${TIMESTAMP[@]}" --options "$SIGN_OPTIONS" --sign "$IDENTITY" \
  --entitlements "$REPOSITORY_ROOT/SteamService/SteamService.entitlements" "$HELPER_DIR/SteamService"
/usr/bin/codesign --verify --strict "$HELPER_DIR/SteamService"
