#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MyWallpaperX"
SCHEME="MyWallpaperX"
CONFIGURATION="Debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MyWallpaperX.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/.codex/DerivedData"
BUILD_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$BUILD_APP_PATH/Contents/MacOS/$APP_NAME"
LOG_PREDICATE="process == \"$APP_NAME\""

build_app() {
  python3 "$ROOT_DIR/script/governance/check_code_health.py" --check --base-ref HEAD
  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
}

kill_app() {
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$BUILD_APP_PATH"
}

kill_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "$LOG_PREDICATE"
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.lowtechguys.MyWallpaperX\""
    ;;
  --verify|verify)
    open_app
    /bin/sleep 2
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
