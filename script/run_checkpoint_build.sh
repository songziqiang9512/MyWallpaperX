#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKPOINT_LOCK_DIR="/private/tmp/mywallpaperx-checkpoint-build.lock"
CHECKPOINT_LOCK_OWNER="$CHECKPOINT_LOCK_DIR/owner.pid"
CHECKPOINT_DERIVED_DATA=""

release_checkpoint_resources() {
  local result=$?
  trap - EXIT HUP INT TERM
  if [[ -n "$CHECKPOINT_DERIVED_DATA" && "$CHECKPOINT_DERIVED_DATA" == /private/tmp/mywallpaperx-checkpoint-build.* ]]; then
    /bin/rm -rf -- "$CHECKPOINT_DERIVED_DATA"
  fi
  if [[ -f "$CHECKPOINT_LOCK_OWNER" ]] && [[ "$(<"$CHECKPOINT_LOCK_OWNER")" == "$$" ]]; then
    /bin/rm -f -- "$CHECKPOINT_LOCK_OWNER"
    /bin/rmdir "$CHECKPOINT_LOCK_DIR" 2>/dev/null || true
  fi
  exit "$result"
}

acquire_checkpoint_lock() {
  if /bin/mkdir "$CHECKPOINT_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$CHECKPOINT_LOCK_OWNER"
    return
  fi

  local owner_pid=""
  if [[ -f "$CHECKPOINT_LOCK_OWNER" ]]; then
    owner_pid="$(<"$CHECKPOINT_LOCK_OWNER")"
  fi
  if [[ "$owner_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$owner_pid" 2>/dev/null; then
    echo "checkpoint build blocked: active owner pid $owner_pid" >&2
    exit 2
  fi

  /bin/rm -f -- "$CHECKPOINT_LOCK_OWNER"
  /bin/rmdir "$CHECKPOINT_LOCK_DIR" 2>/dev/null || true
  if ! /bin/mkdir "$CHECKPOINT_LOCK_DIR" 2>/dev/null; then
    echo "checkpoint build blocked: lock acquisition raced" >&2
    exit 2
  fi
  printf '%s\n' "$$" > "$CHECKPOINT_LOCK_OWNER"
}

trap release_checkpoint_resources EXIT HUP INT TERM
acquire_checkpoint_lock
CHECKPOINT_DERIVED_DATA="$(/usr/bin/mktemp -d /private/tmp/mywallpaperx-checkpoint-build.XXXXXX)"

/usr/bin/xcodebuild \
  -project "$REPOSITORY_ROOT/MyWallpaperX.xcodeproj" \
  -scheme MyWallpaperX \
  -configuration Debug \
  -derivedDataPath "$CHECKPOINT_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build
