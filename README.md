# flclash-vpn-fix

> **一句话**：HyperOS / MIUI 上 FlClash 建不起 VPN 时，这个 KernelSU 模块替你把它修好 —— 开机自动纠正被 MIUI 改坏的 appop，并持续守着不放。

[![Platform](https://img.shields.io/badge/platform-KernelSU%20%7C%20Magisk-blue)](#安装)
[![Android](https://img.shields.io/badge/Android-14%2B-green)](#根因)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

---

## 这是什么

一个**只做一件事**的 root 模块：把 `com.follow.clash`（FlClash）的
`FOREGROUND_SERVICE_SPECIAL_USE` **appop** 维持在 `allow`。

因为 HyperOS/MIUI 会把这个 appop 设成 `ignore`，而 Android 14+ 判断前台服务
类型时**看的是 appop、不是权限**，后果是：

```
FlClash 启动 VpnService
  └─ 以 specialUse 类型转前台服务
       └─ SecurityException: requires [FOREGROUND_SERVICE_SPECIAL_USE]
            └─ 服务被立即 destroy
                 └─ establish() 从未执行 → 没有 tun0 → 流量不被接管
```

表现就是：**FlClash 界面上 VPN 开关是开的、计时器在走，但什么都代理不了。**

## 谁需要它

- 用 HyperOS / MIUI，FlClash 死活起不来 VPN
- 手动 `cmd appops set ... allow` 能修好，但**重启后又坏**（或被 MIUI 改回去）
- 不想每次开机都手动敲命令

## 安装

**方式一（管理器）**：下载本仓库 zip，在 KernelSU / Magisk 管理器里刷入，重启。

**方式二（命令行）**：

```sh
adb push flclash-vpn-fix.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/flclash-vpn-fix.zip'
# 重启生效
```

## 它做什么 / 不做什么

| 做 | 不做 |
|---|---|
| 开机尽早把 appop 设回 `allow` | 不挂载任何文件 |
| 开机完成后再补一次（防 MIUI 覆盖） | 不修改系统分区 |
| 每 120s 巡检，漂移即自愈 | 不动 FlClash 的配置/订阅 |
| 每次写入后 `get` 校验，失败重试 8 次 | 不改其它 App 的任何权限 |

## 验证是否生效

```sh
su -c 'cmd appops get com.follow.clash FOREGROUND_SERVICE_SPECIAL_USE'
# => FOREGROUND_SERVICE_SPECIAL_USE: allow

su -c 'ip -o link show | grep tun0'
# => tun0: <POINTOPOINT,UP,LOWER_UP>

su -c 'dumpsys connectivity | grep "VPN CONNECTED"'
# => ni{VPN CONNECTED extra: VPN:com.follow.clash}
```

## 根因详解

Android 14+ 的**前台服务类型（FGS type）校验走 appop，而不是 permission**。

HyperOS 把 `com.follow.clash` 的这个 appop 设成了 `ignore`：

```
FOREGROUND_SERVICE_SPECIAL_USE: ignore
```

### 为什么极其难查

`dumpsys package com.follow.clash` 里该权限显示 **`granted=true`**，看着完全正常：

```
install permissions:
  android.permission.FOREGROUND_SERVICE_SPECIAL_USE: granted=true
```

但它是 `normal`（安装期）权限 —— 想手动授权会撞墙：

```
$ pm grant com.follow.clash android.permission.FOREGROUND_SERVICE_SPECIAL_USE
SecurityException: ... is not a changeable permission type
```

**真正的开关在 appop 层，只有 `cmd appops get` 看得见。**
这是本模块存在的唯一理由。

## ⚠ 开发本模块踩到的坑

### 坑一：权限表会骗人

见上。`dumpsys package` 说 `granted=true`，框架照样拒绝。
**排查 FGS 问题一律先看 `cmd appops get`。**

### 坑二：脚本日志不能放 `/data/adb/modules/`

只要进程的 stdout/stderr 指向该目录，`cmd appops` 就失败：

```
cmd: Failure calling service appops: Failed transaction (2147483646)
```

对照实验（同一脚本、同一变量、**仅换 LOG 路径**）：

| LOG 路径 | 结果 |
|---|---|
| `/data/local/tmp/` | `set rc=0` ✅ |
| `/data/adb/modules/flclash_vpn_fix/` | `set rc=2` ❌ Failed transaction |

推测是 KernelSU 模块目录的 mount namespace 与 system_server 不一致，
binder 传 fd 时解析失败。**故日志固定在 `/data/local/tmp/`。**

> 注意：这跟"后台运行"无关 —— 已实测脱离 adb 会话的后台进程
> 写 `/data/local/tmp` 完全正常，写模块目录则必失败。

## 日志与 pid

- 日志：`/data/local/tmp/flclash_vpn_fix.log`
- pid：`/data/local/tmp/flclash_vpn_fix.pid`

## 卸载

在管理器里移除模块（会触发 `uninstall.sh` 停掉守护），或：

```sh
su -c 'rm -rf /data/adb/modules/flclash_vpn_fix'
# 重启
```

卸载**不会**还原 appop（保留可用状态）。想恢复 HyperOS 原行为，
取消 `uninstall.sh` 里那行注释。

## 测试环境

| 项 | 值 |
|---|---|
| 设备 | Redmi K20 Pro (raphael) |
| 系统 | Android 16 / HyperOS |
| Root | KernelSU 3.2.5 + Hybrid Mount 元模块 |
| FlClash | 0.8.96 (targetSdk 36) |

## License

MIT
