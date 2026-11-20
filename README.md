# EasyProxy

**OpenWrt / ImmortalWrt 上的中文代理管理系统。装一次，导入订阅就能用。**

![version](https://img.shields.io/badge/version-0.8.15-blue)
![tests](https://img.shields.io/badge/tests-873%20passed-brightgreen)
![firmware](https://img.shields.io/badge/firmware-OpenWrt%20%7C%20ImmortalWrt%20%7C%20Kwrt-informational)
![license](https://img.shields.io/badge/license-MIT-green)

一条命令装好「面板 + sing-box + dae」（`scripts/easyproxy.sh`），之后在 LuCI 的 **服务 → EasyProxy** 里全程中文操作；不开网页时，SSH 里 `easyproxy-manager.sh` 提供菜单，含上不了网时的「紧急恢复直连」。

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

**一条命令装好面板 + sing-box + dae**（交互菜单，选 `1` 安装）：

```sh
wget -qO- https://aka.doubaocdn.com/s/0ixKj9iVdJ | sh
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

装完直接打开 `http://<路由器IP>/cgi-bin/luci/admin/services/easyproxy`（LuCI 里的「服务 → EasyProxy」），不用再敲别的命令。入口脚本本身不写系统状态，安装和卸载都交给 `install.sh` / `uninstall.sh`；每个下载先过 `SHA256SUMS`，架构不匹配直接拒绝。

**只想单独装面板 ipk**（当前 0.8.13，73802 B，sha256 `7ea7e3a2…dcaf52`）：

```sh
wget -qO /tmp/easyproxy.ipk https://aka.doubaocdn.com/s/exVGSA1fvc && opkg install /tmp/easyproxy.ipk
```

## 面板

LuCI「服务 → EasyProxy」共 5 类页面：**概览**（运行状态、规则集、站点延时、快捷启停）、**代理**（节点、订阅、分流策略）、**连接**（总开关、监听、透明代理、IPv6）、**DNS**（解析上游与规则管理）、**设置**（日志级别、内核、日志、备份、版本更新）。面板为浅色玻璃视觉：卡片半透明磨砂、圆角 20px、胶囊按钮，系统开启「降低透明度」时自动退回纯白。

---

## 兼容

| 项 | 支持 |
|---|---|
| 固件 | ImmortalWrt、OpenWrt（`opkg` 与 `apk` 都支持）、Kwrt（`dl.openwrt.ai`，21.02 及以上基线） |
| 架构 | `x86_64`、`aarch64_cortex-a53`、`arm_cortex-a7_neon-vfpv4` |
| 内核 | sing-box `1.14.4`、dae `2.1.2`，按架构分包，可分别升级 / 卸载 |
| 兜底 | 没有匹配包管理器时，用 `rootfs.tar.gz` 直接解到 `/` |

---

## 已知限制（0.8.13）

- **同名节点会让整站断网**：同一节点导入两次即 `duplicate outbound tag`，配置生成失败 → 待修。
- **`ss://` base64url 链接导不进**：报 `ss userinfo is not base64`，部分机场格式受影响 → 待修。
- **测速会把死地址判成可达**：超时也报 `reachable` → 待修。
- **dae 只装不用**：适配器标记开发中，`easyproxy start` 会拒绝它。
- **换节点会断连**：改配置 + 重载，没有 clash API 热切换。
- **平台分流只有三个开关**：YouTube / Netflix / TikTok。

---

## 测试

16 套 **873 项**，`tests/run-all.sh` 是唯一计数来源；CI 会下载并校验 pinned sing-box，用真实内核跑 `check`，失败即停、不会发布。

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
| 0.8.13 | 面板随包自带 ubus 客户端，修复新版 LuCI 上整页 NetworkError ✅ ｜ 一键安装按版本号取最新 ipk ✅ ｜ 构建产物移出版本控制 ✅ |
| 0.8.14 | 同名节点去重（断网级缺陷） |
| 0.8.15 | `ss://` base64url 解析、测速判定修正 |
| 0.8.16 | 订阅去重 + 节点启停开关 |

进度见 [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md)，活缺陷见 [`docs/issues/`](docs/issues/)，新增报告见 [`docs/reports/`](docs/reports/)。

---

MIT，见 [LICENSE](LICENSE)。
