#!/system/bin/sh
###############################################################
# FlClash VPN Fix — 开机应用 + 漂移守护
#
# 背景：Android 14+ 的前台服务类型（FGS type）校验走的是 appop，
#   不是 permission。HyperOS 把 com.follow.clash 的
#   FOREGROUND_SERVICE_SPECIAL_USE 置为 ignore，于是 VpnService 以
#   specialUse 启动前台服务时抛 SecurityException 并被立即 destroy
#   —— establish() 从未执行，tun0 不存在，流量不被 VPN 接管。
#   （注意：dumpsys package 里该权限仍显示 granted=true，因为它是
#    normal/install 权限，只看权限表会被误导。）
#
# 【关键坑·实测】
#   日志/输出绝对不能落在 /data/adb/modules/ 下！
#   只要进程的 stdout/stderr 指向该目录，cmd appops 就会报
#      cmd: Failure calling service appops: Failed transaction (2147483646)
#   把输出改到 /data/local/tmp/ 后立刻恢复正常（同脚本、同变量、
#   仅换 LOG 路径，一次成功一次失败，已对照复现）。
#   推测是 KernelSU 模块目录的 mount namespace 与 system_server 不一致，
#   binder 传 fd 时解析失败。故本脚本 LOG 放 /data/local/tmp。
###############################################################

MODDIR=${0%/*}
LOG=/data/local/tmp/flclash_vpn_fix.log
PIDFILE=/data/local/tmp/flclash_vpn_fix.pid
PKG=com.follow.clash
OP=FOREGROUND_SERVICE_SPECIAL_USE
INTERVAL=120

# 已在运行则不重复启动
if [ -f "$PIDFILE" ]; then
    OLD=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
        exit 0
    fi
fi

(
    exec </dev/null
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

    # 应用修复：设置 + 校验 + 重试（防瞬时失败）
    apply() {
        i=0
        while [ "$i" -lt 8 ]; do
            cmd appops set "$PKG" "$OP" allow >>"$LOG" 2>&1
            cur=$(cmd appops get "$PKG" "$OP" 2>/dev/null | head -n1)
            case "$cur" in
                *allow*) log "apply ok -> $cur"; return 0 ;;
            esac
            i=$((i + 1))
            log "apply attempt $i failed (state: $cur), retrying"
            sleep 5
        done
        log "apply FAILED after $i attempts"
        return 1
    }

    log "guard start (pid $$)"

    # ① 尽早应用：轮询 appops 服务，一可用就写，
    #    抢在 FlClash 自启（及它尝试建 VPN）之前把 appop 摆正。
    i=0
    while [ "$i" -lt 150 ]; do
        cmd appops get "$PKG" "$OP" >/dev/null 2>&1 && break
        sleep 2
        i=$((i + 1))
    done
    apply

    # ② 等开机完成后再补一次：MIUI 安全中心可能开机后才写它的 appop 状态，
    #    会把 ① 的成果覆盖掉。
    n=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$n" -lt 200 ]; do
        sleep 3
        n=$((n + 1))
    done
    sleep 20
    apply

    # 漂移守护：被改回非 allow 就重新纠正
    while true; do
        sleep "$INTERVAL"
        state=$(cmd appops get "$PKG" "$OP" 2>/dev/null | head -n1)
        case "$state" in
            *allow*)
                ;;
            *)
                log "drift detected [$state] -> reapplying"
                apply
                ;;
        esac
    done
) >>"$LOG" 2>&1 &

echo $! > "$PIDFILE"
