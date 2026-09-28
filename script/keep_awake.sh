#!/bin/sh
# MyWallpaperX 防睡眠/防锁屏管理器。
# 机制：launchd 用户级 LaunchAgent 托管 /usr/bin/caffeinate（KeepAlive 在崩溃或
# 12 小时断言超时后自动重启），断言覆盖显示睡眠/闲置睡眠/系统睡眠/磁盘闲置/用户活跃。
# caffeinate 进程挂靠 launchd，不随终端或代理会话退出而消失。
# 用法：sh script/keep_awake.sh start|status|stop|restart
# 停止：stop 只卸载本次加载；plist 保留时下次登录 RunAtLoad 会自动复活，
#       跨登录彻底移除需再删除 ~/Library/LaunchAgents/com.mywallpaperx.keep-awake.plist。
# 注意：已加载状态下直接编辑 script/keep-awake.plist，kickstart 不会重读 plist，
#       需执行 restart 才生效。

set -u

LABEL="com.mywallpaperx.keep-awake"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_PLIST="$SCRIPT_DIR/keep-awake.plist"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

is_loaded() {
    launchctl print "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1
}

managed_pid() {
    launchctl print "$GUI_DOMAIN/$LABEL" 2>/dev/null |
        sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\).*/\1/p' | head -1
}

managed_process_alive() {
    _mpid=$(managed_pid)
    [ -n "$_mpid" ] && kill -0 "$_mpid" 2>/dev/null
}

assertions_held() {
    pmset -g assertions 2>/dev/null | grep -q 'caffeinate'
}

wait_until_healthy() {
    _i=0
    while [ "$_i" -lt 20 ]; do
        if managed_process_alive && assertions_held; then
            return 0
        fi
        sleep 0.5
        _i=$((_i + 1))
    done
    return 1
}

do_start() {
    if [ ! -f "$SRC_PLIST" ]; then
        echo "keep_awake: missing $SRC_PLIST" >&2
        return 1
    fi
    mkdir -p "$HOME/Library/LaunchAgents"
    _tmp_plist="$PLIST.tmp.$$"
    cp "$SRC_PLIST" "$_tmp_plist" && mv -f "$_tmp_plist" "$PLIST"
    if is_loaded; then
        launchctl kickstart -k "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true
    elif ! launchctl bootstrap "$GUI_DOMAIN" "$PLIST" >/dev/null 2>&1; then
        echo "keep_awake: launchctl bootstrap failed" >&2
        return 1
    fi
    if wait_until_healthy; then
        echo "keep_awake: active (launchd label=$LABEL, pid=$(managed_pid), caffeinate assertions held)"
        return 0
    fi
    echo "keep_awake: start failed — loaded=$(is_loaded && echo yes || echo no) managed process=$(managed_process_alive && echo alive || echo dead)" >&2
    pmset -g assertions 2>/dev/null | grep caffeinate ||
        echo "keep_awake: no caffeinate assertions visible" >&2
    return 1
}

do_status() {
    if is_loaded && managed_process_alive && assertions_held; then
        echo "keep_awake: active (pid=$(managed_pid))"
        pmset -g assertions 2>/dev/null | grep caffeinate | sed 's/^/  /'
        return 0
    fi
    echo "keep_awake: inactive (loaded=$(is_loaded && echo yes || echo no), managed process=$(managed_process_alive && echo alive || echo dead))"
    return 1
}

do_stop() {
    if is_loaded; then
        if ! launchctl bootout "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1; then
            echo "keep_awake: launchctl bootout failed" >&2
            return 1
        fi
    fi
    _i=0
    while [ "$_i" -lt 10 ]; do
        if ! is_loaded && ! managed_process_alive; then
            echo "keep_awake: stopped (plist kept at $PLIST — delete that file to prevent resurrect at next login)"
            return 0
        fi
        sleep 0.5
        _i=$((_i + 1))
    done
    echo "keep_awake: stop failed — agent still loaded or managed caffeinate still running" >&2
    return 1
}

if [ $# -gt 1 ]; then
    echo "usage: sh $0 start|status|stop|restart" >&2
    exit 2
fi

case "${1:-status}" in
    start) do_start ;;
    status) do_status ;;
    stop) do_stop ;;
    restart) do_stop; do_start ;;
    *) echo "usage: sh $0 start|status|stop|restart" >&2; exit 2 ;;
esac
