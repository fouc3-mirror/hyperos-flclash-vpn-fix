#!/system/bin/sh
# 卸载时停止守护进程。不还原 appop（保留可用状态）。
# 如需恢复 HyperOS 原行为，把下面注释打开：
#   cmd appops set com.follow.clash FOREGROUND_SERVICE_SPECIAL_USE ignore

# 注意：pid 文件在 /data/local/tmp，不在模块目录（见 service.sh 顶部说明）
PIDFILE=/data/local/tmp/flclash_vpn_fix.pid

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$PID" ]; then
        kill "$PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi
