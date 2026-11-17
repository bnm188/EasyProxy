# EasyProxy

**OpenWrt / ImmortalWrt 上的中文代理管理系统。装一次，导入订阅就能用。**

![version](https://img.shields.io/badge/version-0.8.5-blue)
![tests](https://img.shields.io/badge/tests-672%20passed-brightgreen)
![firmware](https://img.shields.io/badge/firmware-OpenWrt%20%7C%20ImmortalWrt%20%7C%20Kwrt-informational)
![license](https://img.shields.io/badge/license-MIT-green)

一条命令装好「面板 + sing-box + dae」，之后在 LuCI 的 **服务 → EasyProxy** 里全程中文操作；不开网页时，SSH 里 `easyproxy-manager.sh` 有十项菜单，含上不了网时的「紧急恢复直连」。

三条原则写死在代码里，不是开关：**国外走代理要顺、国内流量不进内核、内网设备完全不受影响。**

---

## 能做什么

| 能力 | 说明 |
|---|---|
| 一键安装 | 面板 + sing-box + dae 一次装完；每个下载先过 `SHA256SUMS`，错架构直接拒绝 |
| 节点 | 7 种分享链接导入、批量导入、导出、订阅拉取（URL 不写 UCI、不进日志） |
| 分流 | 大陆直连（锁死不可改），其余走代理；DNS 国内 / 国外分离 |
| 透明代理 | 整个 LAN 无感走代理；nft 全在自有命名空间，一条命令回滚，不碰 fw4 |
| 入口旁路 | 国内地址表命中即在 tproxy 之前 `return`；表坏了保留旧表，面板可一键恢复直连 |
| 维护 | 备份 / 恢复 / 重置、规则集更新校验、`doctor` 自检、日志轮转、干净卸载 |
| 升级 | 三组件各自升级；内核起不来自动回滚旧二进制 |

---

## 快速开始（路由器 SSH 里执行）

**一条命令进菜单**：安装 / 升级 / 状态 / 检查环境 / 卸载，都在里面。

```sh
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh
```

```
  EasyProxy 一键入口
  ─────────────────────────────
  1) 安装       面板 + sing-box + dae
  2) 升级       三组件各自升级
  3) 状态       已装组件与版本
  4) 检查环境   只读诊断，不改系统
  5) 卸载       保留配置并先备份
  0) 退出
```

**不想进菜单，直接点名执行**（同一行命令，最后两个字换成动作）：

```sh
# 进菜单（不带参数）
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh

# 直接装
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh -s install

# 升级 / 看状态 / 检查环境 / 卸载
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh -s upgrade
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh -s status
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh -s check
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh -s uninstall
```

**「检查环境」查什么**：固件类型、包管理器（opkg / apk）、CPU 架构能否对上发布包、`sha256sum` `tar` `nft` `wget`、nftables 能否建表、根分区剩余空间、是否已装过。只读，不改任何系统状态，最后给一句「能装 / 有阻塞项」。

**进阶参数**（直接调用底层安装器时用）：`--ipk` / `--apk` / `--rootfs` 指定包形式，`--no-dae` 跳过 dae，`upgrade --only dae` 只升一个组件，`--help` 离线看用法。

## 面板

LuCI「服务 → EasyProxy」共 10 个中文页面：总览、节点、订阅、分流、透明代理、DNS、内核、维护、日志、关于。总览页直接把状态做成卡片，包括「入口旁路（国内不进内核）」的运行状态、地址表条数、判定口径，以及一键「恢复直连」。

---

## 兼容

| 项 | 支持 |
|---|---|
| 固件 | ImmortalWrt、OpenWrt（`opkg` 与 `apk` 都支持）、Kwrt（`dl.openwrt.ai`，21.02 及以上基线） |
| 架构 | `x86_64`、`aarch64_cortex-a53`、`arm_cortex-a7_neon-vfpv4` |
| 内核 | sing-box `1.14.4`、dae `2.1.2`，按架构分包，可分别升级 / 卸载 |
| 兜底 | 没有匹配包管理器时，用 `rootfs.tar.gz` 直接解到 `/` |

---

## 已知限制（0.8.3）

- **换节点会断连**：改配置 + 重载，没有 clash API 热切换 → 计划 0.8.3。
- **平台分流只有三个开关**：YouTube / Netflix / TikTok，且共用同一个 `proxy` 组 → 计划 0.8.5。
- **dae 只装不用**：适配器标记开发中，`easyproxy start` 会拒绝它 → 计划 0.8.9。
- **未上真机**：透明代理、`cn_ipv4` 集合的加载时间与内存占用目前只在沙箱验证 → 计划 0.8.8。

---

## 测试

14 套 **672 项**，`tests/run-all.sh` 是唯一计数来源；CI 会下载并校验 pinned sing-box，用真实内核跑 `check`，失败即停、不会发布。

```sh
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/run-all.sh
```

---

## 发布与资产

每个 Release 带着：EasyProxy 的 `apk` / `ipk`（`all` 与 `x86_64`）/ `rootfs.tar.gz`、三架构的 `sing-box` 与 `dae` 内核包、`SHA256SUMS`、`KERNEL-VERSIONS`。安装器按 `SHA256SUMS` 逐项校验，内核包永不强制架构。

发版规则：**版本号即命令**——`PKG_VERSION` 高于最新 Release 就自动构建、自动发布、自动回查资产并验 SHA256；提交带 `[no-release]` 可豁免；同版本重复发布直接失败，不覆盖旧资产。

---

## 路线图（版本即里程碑）

| 版本 | 里程碑 |
|---|---|
| 0.8.2 | 入口旁路：国内流量不进内核 ✅ |
| 0.8.3 | 面板一键更新（SHA256 校验 + 自动回滚）、日志真正落盘并 600、客户诊断按编号归档每天上传 ✅ ｜ 无缝热切换（clash API）待做 |
| 0.8.4 | 引擎接口 v2 + dae 条件化加载 |
| 0.8.5 | 十个平台分流 + 可绑定地区组 |
| 0.8.6 | 架构矩阵扩展 |
| 0.8.7 | 生态第一步：profile 导出 + 扫码导入 |
| 0.8.8 | 真机验收 + 面板升级 |
| 0.8.9 | dae 真正启动 |

进度见 [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md)，细项见 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)，历次报告见 [`docs/reports/`](docs/reports/)。

---

MIT，见 [LICENSE](LICENSE)。
