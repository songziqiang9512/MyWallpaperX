#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKPOINT_LOCK_DIR="/private/tmp/mywallpaperx-checkpoint-build.lock"
CHECKPOINT_LOCK_FILE="/private/tmp/mywallpaperx-checkpoint-build.flock"
CHECKPOINT_DERIVED_DATA=""
CHECKPOINT_OWNED_TEMPORARY=""
CHECKPOINT_CACHE_ROOT=""
CHECKPOINT_BUILDER="$(command -v xcodebuild)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache-dir)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--cache-dir requires a directory" >&2; exit 2
      fi
      CHECKPOINT_CACHE_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: script/run_checkpoint_build.sh [--cache-dir DIR]"
      echo "Default: isolated cold build, removed at exit. --cache-dir retains keyed DerivedData for explicit incremental reuse."
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

release_checkpoint_resources() {
  local result=$?
  trap - EXIT HUP INT TERM
  if [[ -n "$CHECKPOINT_OWNED_TEMPORARY" ]]; then
    /bin/rm -rf -- "$CHECKPOINT_OWNED_TEMPORARY"
  fi
  exit "$result"
}

acquire_checkpoint_lock() {
  # Never delete this inode: flock ownership is released by the OS, including
  # process failure. A directory from an older script version is conservative
  # evidence of another owner, even before that owner publishes its PID.
  if [[ -e "$CHECKPOINT_LOCK_DIR" ]]; then
    echo "checkpoint build blocked: legacy lock exists at $CHECKPOINT_LOCK_DIR" >&2
    exit 2
  fi
  exec 9>> "$CHECKPOINT_LOCK_FILE"
  python3.12 -B - <<'PYLOCK'
import fcntl
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    import sys
    print('checkpoint build blocked: active file-lock owner', file=sys.stderr)
    raise SystemExit(2)
PYLOCK
}

trap release_checkpoint_resources EXIT HUP INT TERM
acquire_checkpoint_lock
if [[ -n "$CHECKPOINT_CACHE_ROOT" ]]; then
  # Resolve before creating anything: caches cannot become a source/sample writer.
  CHECKPOINT_CACHE_ROOT="$(python3.12 -B - "$CHECKPOINT_CACHE_ROOT" "$REPOSITORY_ROOT" <<'PYCACHE'
from pathlib import Path
import sys
root = Path(sys.argv[1]).expanduser().resolve()
repository = Path(sys.argv[2]).resolve()
samples = (Path.home() / 'Movies/MyWallpaperX/创意工坊/Scene').resolve()
if root == samples or root.is_relative_to(samples):
    raise SystemExit('checkpoint cache cannot be inside the real Scene sample root')
if root == repository or (root.is_relative_to(repository) and not root.is_relative_to(repository / '.build-cache')):
    raise SystemExit('in-repository checkpoint cache must be under .build-cache')
print(root)
PYCACHE
)"
  CHECKPOINT_TOOLCHAIN="$("$CHECKPOINT_BUILDER" -version)"
  CHECKPOINT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
  CHECKPOINT_CACHE_KEY="$(printf '%s\n' "$REPOSITORY_ROOT" "$CHECKPOINT_BUILDER" "$CHECKPOINT_TOOLCHAIN" "$CHECKPOINT_SDK" "Debug:CODE_SIGNING_ALLOWED=NO" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-24)"
  CHECKPOINT_DERIVED_DATA="$CHECKPOINT_CACHE_ROOT/$CHECKPOINT_CACHE_KEY"
  if [[ -L "$CHECKPOINT_DERIVED_DATA" ]]; then
    echo "checkpoint cache key directory cannot be a symlink: $CHECKPOINT_DERIVED_DATA" >&2
    exit 2
  fi
  /bin/mkdir -p "$CHECKPOINT_DERIVED_DATA"
  echo "checkpoint cache retained: $CHECKPOINT_DERIVED_DATA"
else
  CHECKPOINT_OWNED_TEMPORARY="$(/usr/bin/mktemp -d /private/tmp/mywallpaperx-checkpoint-build.XXXXXX)"
  CHECKPOINT_DERIVED_DATA="$CHECKPOINT_OWNED_TEMPORARY"
  echo "checkpoint isolated build: $CHECKPOINT_DERIVED_DATA"
fi

"$CHECKPOINT_BUILDER" \
  -project "$REPOSITORY_ROOT/MyWallpaperX.xcodeproj" \
  -scheme MyWallpaperX \
  -configuration Debug \
  -derivedDataPath "$CHECKPOINT_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build
