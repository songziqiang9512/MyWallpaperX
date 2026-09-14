#!/bin/bash
# SK1.2/SK7.2：确定性发布 Steam helper（osx-arm64，锁定依赖）。
#
# 用法：script/publish-steam-helper.sh
# 产物：SteamService/bin/publish/SteamService（原生 apphost 可执行 + dll/依赖）。
# 开发注入：export MWX_STEAM_HELPER_COMMAND=<SteamService/bin/publish/SteamService>
# 包内嵌与签名/公证属 SK7.2 发行门；本脚本只负责确定性构建。

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISH_DIR="$REPO_ROOT/SteamService/bin/publish"
DOTNET="${DOTNET:-$HOME/.dotnet/dotnet}"

cd "$REPO_ROOT/SteamService"
"$DOTNET" restore --locked-mode
"$DOTNET" publish -c Release -r osx-arm64 --no-restore -o "$PUBLISH_DIR"

echo "发布产物位于：$PUBLISH_DIR/SteamService"
echo "开发注入：export MWX_STEAM_HELPER_COMMAND=$PUBLISH_DIR/SteamService"
