#!/bin/bash
# SK2.1 账号门：通过 helper IPC 路线验证真实认证流（SK7.1 验收复用）。
# 兼容 macOS 自带 bash 3.2：不用 coproc，用 FIFO 做双向管道。
#
# 用法：
#   script/steam-auth-gate.sh password            # 密码+邮箱/手机验证码 → online
#   script/steam-auth-gate.sh qr                  # 二维码：终端打印挑战链接，手机扫码确认
#   script/steam-auth-gate.sh wrong-password <用户名>   # 错误密码 → typed 失败（单次尝试）
#   script/steam-auth-gate.sh restore <用户名> <refreshToken文件>  # 静默恢复
#
# 注意：
# - stdout 会打印协议帧；login 成功结果含 refresh token（private 包装内），
#   不要把输出贴给任何人。
# - helper 路径：SteamService/bin/publish/SteamService（先跑
#   script/publish-steam-helper.sh）。

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${STEAM_HELPER:-$REPO_ROOT/SteamService/bin/publish/SteamService}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"

MODE="${1:-}"
if [[ ! -x "$HELPER" ]]; then
    echo "helper 不存在：$HELPER（先运行 script/publish-steam-helper.sh）" >&2
    exit 2
fi

TMPDIR_GATE="$(mktemp -d /tmp/mwx-auth-gate.XXXXXX)"
FIFO_IN="$TMPDIR_GATE/in"
FIFO_OUT="$TMPDIR_GATE/out"
mkfifo "$FIFO_IN" "$FIFO_OUT"

"$HELPER" < "$FIFO_IN" > "$FIFO_OUT" &
HELPER_PID=$!
exec 3>"$FIFO_IN"
exec 4<"$FIFO_OUT"

cleanup() {
    printf '{"v":1,"type":"request","requestId":"gate-stop","command":"shutdown"}\n' >&3 2>/dev/null || true
    sleep 1
    kill "$HELPER_PID" 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    exec 4>&- 2>/dev/null || true
    rm -rf "$TMPDIR_GATE"
}
trap cleanup EXIT

send() { printf '%s\n' "$1" >&3; }

# 用户输入先过 JSON 转义（反斜杠/引号），防破坏协议帧。
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# 逐行转发 helper 输出；出现匹配片段时返回 0。
read_until() {
    local pattern="$1" line
    while IFS= read -r line <&4; do
        printf '%s\n' "$line"
        case "$line" in
            *"$pattern"*) return 0 ;;
        esac
    done
    return 1
}

case "$MODE" in
    password)
        read -r -p "Steam 用户名: " USERNAME
        read -r -s -p "Steam 密码(不回显): " PASSWORD; echo
        # 凭据只在本进程内存中转义后拼入协议帧，不落任何文件或日志。
        send "{\"v\":1,\"type\":\"request\",\"requestId\":\"gate-login\",\"command\":\"loginPassword\",\"payload\":{\"username\":\"$(json_escape "$USERNAME")\"},\"private\":{\"password\":\"$(json_escape "$PASSWORD")\"}}"
        unset PASSWORD
        echo "== 等待 Guard 验证码事件 ==" >&2
        if read_until '"awaitingEmailCode"' || read_until '"awaitingDeviceCode"' || read_until '"awaitingDeviceConfirmation"'; then
            read -r -p "验证码: " CODE
            CODE="$(json_escape "$CODE")"
            send "{\"v\":1,\"type\":\"request\",\"requestId\":\"gate-code\",\"command\":\"submitChallenge\",\"payload\":{\"code\":\"$CODE\"}}"
        fi
        echo "== 等待终态 ==" >&2
        read_until '"type":"result","requestId":"gate-login"'
        ;;
    qr)
        echo "== 等待二维码挑战链接（用手机 Steam 扫码确认）==" >&2
        send '{"v":1,"type":"request","requestId":"gate-qr","command":"loginQR"}'
        read_until '"qrChallenge"' || true
        echo "== 等待扫码确认后的终态 ==" >&2
        read_until '"type":"result","requestId":"gate-qr"'
        ;;
    wrong-password)
        USERNAME="$(json_escape "${2:?usage: $0 wrong-password <用户名>}")"
        send "{\"v\":1,\"type\":\"request\",\"requestId\":\"gate-wrong\",\"command\":\"loginPassword\",\"payload\":{\"username\":\"$USERNAME\"},\"private\":{\"password\":\"definitely-not-the-password-9x7\"}}"
        echo "== 期望 typed 失败（单次尝试，不重试）==" >&2
        read_until '"type":"result","requestId":"gate-wrong"'
        ;;
    restore)
        USERNAME="$(json_escape "${2:?usage: $0 restore <用户名> <token文件>}")"
        TOKEN_FILE="${3:?usage: $0 restore <用户名> <token文件>}"
        TOKEN="$(json_escape "$(cat "$TOKEN_FILE")")"
        send "{\"v\":1,\"type\":\"request\",\"requestId\":\"gate-restore\",\"command\":\"restoreSession\",\"payload\":{\"accountName\":\"$USERNAME\"},\"private\":{\"refreshToken\":\"$TOKEN\"}}"
        echo "== 等待恢复终态 ==" >&2
        read_until '"type":"result","requestId":"gate-restore"'
        ;;
    *)
        echo "用法：$0 {password|qr|wrong-password <用户名>|restore <用户名> <token文件>}" >&2
        exit 2
        ;;
esac
