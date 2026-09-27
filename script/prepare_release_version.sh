#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <marketing-version> [published-build-version]" >&2
  exit 64
fi

MARKETING_VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Notes are reviewed together with the version change. This command only
# prepares files; staging, committing, pushing and publishing remain explicit.
git diff --exit-code -- MyWallpaperX.xcodeproj/project.pbxproj
git diff --cached --exit-code -- MyWallpaperX.xcodeproj/project.pbxproj
python3 script/validate_release_notes.py "$MARKETING_VERSION" --check-tags
BUILD_VERSION="$(python3 - "${2:-0}" <<'PYTHON'
from pathlib import Path
import sys
from script.release_version import PROJECT, project_version
published = sys.argv[1]
if not published.isascii() or not published.isdecimal():
    raise SystemExit("Published build version must be numeric")
_, current = project_version(Path(PROJECT).read_text())
print(max(current, int(published)) + 1)
PYTHON
)"
script/update_project_version.sh "$MARKETING_VERSION" "$BUILD_VERSION"
printf 'Prepared version %s (%s). Review and commit the project and docs/releases/%s.md together.\n' \
  "$MARKETING_VERSION" "$BUILD_VERSION" "$MARKETING_VERSION"
