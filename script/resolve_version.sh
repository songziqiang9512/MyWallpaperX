#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-development}" in
  --release|release|development) ;;
  *) echo "Usage: $0 [--release]" >&2; exit 64 ;;
esac
python3 "$ROOT_DIR/script/release_version.py"
