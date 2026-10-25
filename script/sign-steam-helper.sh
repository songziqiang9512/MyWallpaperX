#!/bin/bash
# Normalize payload permissions and sign dependencies, then the apphost with MAP_JIT.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="${1:?helper directory required}"
IDENTITY="${2:?signing identity required}"
TIMESTAMP_POLICY="${3:-required}"
case "$TIMESTAMP_POLICY" in required|none) ;; *) echo "Invalid timestamp policy: $TIMESTAMP_POLICY" >&2; exit 2 ;; esac
[[ -x "$HELPER_DIR/SteamService" && -f "$HELPER_DIR/libcoreclr.dylib" ]] || exit 1
TIMESTAMP=(--timestamp=none)
SIGN_OPTIONS=runtime
# Ad-hoc code has no Team ID for library validation. Keep this local path
# unhardened; real identities retain runtime with same-team native dependencies.
if [[ "$IDENTITY" == - ]]; then SIGN_OPTIONS=0; fi
if [[ "$IDENTITY" != - && "$TIMESTAMP_POLICY" == required ]]; then TIMESTAMP=(--timestamp); fi
while IFS= read -r -d '' binary; do
  if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    /bin/chmod 755 "$binary"
    if [[ "$binary" != "$HELPER_DIR/SteamService" ]]; then
      /usr/bin/codesign --force "${TIMESTAMP[@]}" --options "$SIGN_OPTIONS" --sign "$IDENTITY" "$binary"
    fi
  else
    # Executable PE assemblies would be treated as unsigned nested code by
    # the outer app signature. Classify each file once and keep them resources.
    /bin/chmod 644 "$binary"
  fi
done < <(/usr/bin/find "$HELPER_DIR" -type f -print0)
/usr/bin/codesign --force "${TIMESTAMP[@]}" --options "$SIGN_OPTIONS" --sign "$IDENTITY" \
  --entitlements "$REPOSITORY_ROOT/SteamService/SteamService.entitlements" "$HELPER_DIR/SteamService"
/usr/bin/codesign --verify --strict "$HELPER_DIR/SteamService"
