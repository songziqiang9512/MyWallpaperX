#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <marketing-version> <build-version>" >&2
  exit 64
fi

MARKETING_VERSION="$1"
BUILD_VERSION="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - "$MARKETING_VERSION" "$BUILD_VERSION" <<'PY'
from pathlib import Path
import re
import sys

marketing_version = sys.argv[1]
build_version = sys.argv[2]
if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", marketing_version):
    raise SystemExit("Marketing version must be numeric x.y.z")
if not re.fullmatch(r"[1-9][0-9]*", build_version):
    raise SystemExit("Build version must be a positive integer")
project_file = Path("MyWallpaperX.xcodeproj/project.pbxproj")
text = project_file.read_text()

text, marketing_count = re.subn(
    r"MARKETING_VERSION = [^;]+;",
    f"MARKETING_VERSION = {marketing_version};",
    text,
)
text, build_count = re.subn(
    r"CURRENT_PROJECT_VERSION = [^;]+;",
    f"CURRENT_PROJECT_VERSION = {build_version};",
    text,
)

if marketing_count == 0:
    raise SystemExit("MARKETING_VERSION not found in project.pbxproj")
if build_count == 0:
    raise SystemExit("CURRENT_PROJECT_VERSION not found in project.pbxproj")

project_file.write_text(text)
print(
    f"Updated project version to {marketing_version} ({build_version}) "
    f"in {marketing_count} marketing and {build_count} build settings."
)
PY
