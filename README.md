# FlClash VPN Fix (HyperOS appop)

## 解决什么问题

HyperOS / MIUI 上 FlClash 建不起 VPN、流量不被接管。

## 根因

Android 14+ 的**前台服务类型（FGS type）校验走 appop，而不是 permission**。

HyperOS 把 `com.follow.clash` 的这个 appop 设成了 `ignore`：

```
FOREGROUND_SERVICE_SPECIAL_USE: ignore
```

于是 FlClash 的 `VpnService` 以 `specialUse` 类型启动前台服务时：

```
SecurityException: Starting FGS with type specialUse ... targetSDK=36
  requires permissions: [android.permission.FOREGROUND_SERVICE_SPECIAL_USE]
```

紧接着服务被销毁：

```
unbindService  ->  destroyService
```

`VpnService.Builder.establish()` 从未执行 → 没有 `tun0` → 流量不被接管。

### 为什么难查

`dumpsys package com.follow.clash` 里该权限显示 **`granted=true`**，看着完全正常。
因为它是 `normal`（安装期）权限，`pm grant` 会报
`not a changeable permission type`。**只有 `cmd appops get` 才看得到真实状态。**

## 本模块做什么

1. 开机完成后把 appop 设回 `allow`
2. 之后每 120 秒巡检，漂移即纠正（MIUI 可能在重启或其它时机改回去）

只调用 `cmd appops set`，**不挂载、不修改任何系统文件**。

## ⚠ 开发本模块踩到的坑（很重要）

**日志/输出绝对不能写在 `/data/adb/modules/` 下！**

只要进程的 stdout/stderr 指向该目录，`cmd appops` 就会失败：

```
cmd: Failure calling service appops: Failed transaction (2147483646)
```

对照实验（同一脚本、同一变量，仅换 LOG 路径）：

| LOG 路径 | 结果 |
|---|---|
| `/data/local/tmp/` | `set rc=0` ✅ |
| `/data/adb/modules/flclash_vpn_fix/` | `set rc=2` ❌ Failed transaction |

推测是 KernelSU 模块目录的 mount namespace 与 system_server 不一致，
binder 传 fd 时解析失败。**故日志固定在 `/data/local/tmp/`。**

> 注意：这跟"后台运行"无关 —— 脱离 adb 会话的后台进程写 `/data/local/tmp` 完全正常。

## 手动验证

```sh
su -c 'cmd appops get com.follow.clash FOREGROUND_SERVICE_SPECIAL_USE'
# => FOREGROUND_SERVICE_SPECIAL_USE: allow

su -c 'ip -o link show | grep tun0'
# => tun0: <POINTOPOINT,UP,LOWER_UP>

su -c 'dumpsys connectivity | grep "VPN CONNECTED"'
# => ni{VPN CONNECTED extra: VPN:com.follow.clash}
```

## 日志 / pid

- 日志：`/data/local/tmp/flclash_vpn_fix.log`
- pid：`/data/local/tmp/flclash_vpn_fix.pid`

## 卸载

在 KernelSU 管理器里移除模块（会触发 `uninstall.sh` 停掉守护进程），
或直接 `rm -rf /data/adb/modules/flclash_vpn_fix` 后重启。
