#!/bin/bash
# Explicit account gate. Python owns JSON, Guard event dispatch, redacted output and deadline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
exec python3.12 "$REPO_ROOT/script/steam_auth_gate.py" "$@"
