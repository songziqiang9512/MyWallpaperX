#!/bin/bash
# SK1.2/SK7.2：确定性发布 Steam helper（osx-arm64，锁定依赖）。
#
# 用法：script/publish-steam-helper.sh
# 产物：SteamService/bin/publish/SteamService（原生 apphost 可执行 + dll/依赖）。
# 开发注入：export MWX_STEAM_HELPER_COMMAND=<SteamService/bin/publish/SteamService>
# Xcode passes an exact helper output and per-build intermediate directory.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISH_DIR="${1:-$REPO_ROOT/SteamService/bin/publish}"
INTERMEDIATE_DIR="${2:-$REPO_ROOT/SteamService/obj}"
DOTNET="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$DOTNET" ]]; then DOTNET="$HOME/.dotnet/dotnet"; fi
[[ -x "$DOTNET" ]] || { echo "SteamService requires .NET SDK 8.0.401 to build" >&2; exit 1; }
[[ "$PUBLISH_DIR" = /* && "$INTERMEDIATE_DIR" = /* ]] || exit 2

# Only replace this script's generated product; never mirror over an unrelated directory.
if [[ -e "$PUBLISH_DIR" ]]; then
  [[ -d "$PUBLISH_DIR" && ! -L "$PUBLISH_DIR" ]] || exit 2
  if [[ -n "$(/bin/ls -A "$PUBLISH_DIR")" && ! -f "$PUBLISH_DIR/SteamService.deps.json" ]]; then
    echo "Refusing to replace a non-SteamService output: $PUBLISH_DIR" >&2; exit 2
  fi
fi
# Clean stale temp dirs from interrupted embeds: they live next to the
# output and would otherwise be copied/signed into the app bundle.
/usr/bin/find "$(dirname "$PUBLISH_DIR")" -maxdepth 1 -name '.mwx-steam-publish.*' \
  -exec /bin/rm -rf {} + 2>/dev/null || true
/bin/mkdir -p "$(dirname "$PUBLISH_DIR")"
FRESH_DIR="$(/usr/bin/mktemp -d "$(dirname "$PUBLISH_DIR")/.mwx-steam-publish.XXXXXX")"
trap '/bin/rm -rf -- "$FRESH_DIR"' EXIT
cd "$REPO_ROOT/SteamService"
# Xcode exports TARGETNAME; MSBuild imports it case-insensitively as TargetName.
# Freeze our assembly output as well as apphost identity at this boundary.
"$DOTNET" restore --locked-mode -p:TargetName=SteamService -p:BaseIntermediateOutputPath="$INTERMEDIATE_DIR/"
"$DOTNET" publish -c Release -r osx-arm64 --self-contained true --no-restore -p:TargetName=SteamService \
  -p:BaseIntermediateOutputPath="$INTERMEDIATE_DIR/" \
  -p:BaseOutputPath="$INTERMEDIATE_DIR/bin/" -o "$FRESH_DIR"
[[ -x "$FRESH_DIR/SteamService" && -f "$FRESH_DIR/SteamService.dll" && -f "$FRESH_DIR/libhostfxr.dylib" \
   && -f "$FRESH_DIR/libcoreclr.dylib" && -f "$FRESH_DIR/SteamKit2.dll" ]] || exit 1
# arm64 codesign treats every executable file inside Contents/ as nested code
# requiring a signature, and .NET PE assemblies cannot be signed. Strip the
# exec bit from non-Mach-O files so the outer app signature accepts them as
# resources; only real Mach-O binaries stay executable.
while IFS= read -r -d '' f; do
  if /usr/bin/file -b "$f" | /usr/bin/grep -q Mach-O; then
    /bin/chmod 755 "$f"
  else
    /bin/chmod 644 "$f"
  fi
done < <(/usr/bin/find "$FRESH_DIR" -type f -print0)
# arm64 requires every nested Mach-O to be signed. Use the build's own code
# signing identity when Xcode provides one, ad-hoc ("-") otherwise; local
# ad-hoc builds stay unhardened (no library validation on same-team deps).
HELPER_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
/bin/bash "$REPO_ROOT/script/sign-steam-helper.sh" "$FRESH_DIR" "$HELPER_SIGN_IDENTITY"

/bin/mkdir -p "$PUBLISH_DIR"
/usr/bin/rsync -a --delete "$FRESH_DIR/" "$PUBLISH_DIR/"

echo "发布产物位于：$PUBLISH_DIR/SteamService"
echo "开发注入：export MWX_STEAM_HELPER_COMMAND=$PUBLISH_DIR/SteamService"
