# EasyProxy

**面向 OpenWrt / ImmortalWrt 的中文代理管理系统——装一次，导入订阅就能用。**

![version](https://img.shields.io/badge/version-0.8.2-blue)
![tests](https://img.shields.io/badge/tests-672%20passed-brightgreen)
![firmware](https://img.shields.io/badge/firmware-OpenWrt%20%7C%20ImmortalWrt%20%7C%20Kwrt-informational)
![arch](https://img.shields.io/badge/arch-x86__64%20%7C%20aarch64%20%7C%20armv7-lightgrey)
![license](https://img.shields.io/badge/license-MIT-green)

一条 SSH 命令装好「面板 + sing-box + dae」三件套，之后在 LuCI 的 **服务 → EasyProxy** 里，用全中文面板管节点、分流、透明代理、内核和维护；不想开网页时，SSH 里还有 `easyproxy-manager.sh` 的十项菜单，包括上不了网时的「紧急恢复直连」。

| 项目 | 现状 |
|---|---|
| 当前版本 | **0.8.2**（Release `v0.8.2`，12 个资产，全部通过 SHA256 校验） |
| 适用固件 | ImmortalWrt、OpenWrt（`opkg` 与 `apk` 都支持，也可 rootfs 直接展开）、Kwrt（`dl.openwrt.ai` 构建，OpenWrt 21.02 及以上基线） |
| 内核 | sing-box **1.14.4** + dae **2.1.2**，按架构分包，可分别升级、分别卸载 |
| 架构 | `x86_64`、`aarch64_cortex-a53`、`arm_cortex-a7_neon-vfpv4` |
| 面板 | 10 个中文页面，含总览状态卡与「入口旁路」一键恢复 |
| 测试 | **14 套 672 项**，CI 下载并校验 pinned sing-box 后用真实内核跑 `check` |
| 发版 | 版本号涨了自动构建、自动发 Release、自动回查资产，不需要手工点按钮 |

三条设计原则贯穿全部代码：**国外走代理要流畅、国内流量不进内核、内网设备完全不受影响**。

## 一、现在能做什么 / 还不能做什么

这一节比功能列表重要：**能做的有代码和实测支撑，不能做的也写清楚**，避免装完发现“说好的功能没有”。

### 能用的

| 能力 | 说明 |
|---|---|
| 一键装三件套 | 面板 + sing-box + dae 一次装完；每个下载都过 `SHA256SUMS`，拒绝错架构包，失败按失败报（不会打印成功） |
| 节点管理 | 7 种分享链接导入、批量导入、导出、删除；订阅链接拉取（URL 不写 UCI、不进日志） |
| 分流 | 大陆直连（锁死，不可改）、其余走代理；DNS 国内/国外分离 |
| 透明代理 | 整个 LAN 无感走代理；nft 对象全在自有命名空间，一条命令回滚，不碰 fw4 |
| 维护 | 配置备份/恢复/重置、规则集更新/校验、`doctor` 11 项自检、日志轮转、干净卸载 |
| 升级 | 三组件各自独立升级；内核升级后不能运行会自动回滚旧二进制 |
| 入口旁路（国内不进内核） | 下发 `set cn_ipv4`（interval 集合），命中即在 tproxy 之前 `return`；表下载走 tmp→校验→mv，失败不覆盖旧表；面板与菜单都能一键「恢复直连」 |
| 统一管理入口 | `easyproxy-manager.sh` 十项菜单：安装/升级/启停/体检/日志/节点/订阅/备份/卸载/紧急恢复直连 |
| 内核切换基础 | 已装 dae，适配器接口在（但见下方“还不能”） |

### 还不能的（0.7.0 明确不支持）

| 缺什么 | 现状 | 计划 |
|---|---|---|
| 无缝切换 | 换节点 = 改配置 + 重载，连接会断；还没有 clash API 热切换 | 0.8.3（M2） |
| 10 个平台分流 | 只有 YouTube / Netflix / TikTok 三个开关，且共用同一个 `proxy` 组 | 0.8.5（M4） |
| 10 个固定分组 | 是按节点名关键词自动分地区桶（hk/tw/jp/sg/us/uk/de/kr/ru/other），不能手动归组、不能选组 | 0.8.3~0.8.5（M2~M4） |
| dae 真正可用 | 只装不用：适配器标记“开发中”，`easyproxy start` 会拒绝它 | 0.8.9（M8） |
| `ssr://` 链接 | **不支持**，会返回 `unsupported share link scheme: ssr` | — |
| 带宽/丢包测速 | `node test` 只做一次 TCP 握手，QUIC 协议（hysteria2/tuic）会误报不可达 | 0.8.3~0.8.5（M2~M4） |
| 真机验收记录 | 透明代理、tproxy 转发、LuCI 渲染、`cn_ipv4` 集合的加载时间与内存占用只在沙箱验证过 | 0.8.8（M7） |
| 发布不可变 | **脚本层已实现**：同版本重复发布直接失败、不覆盖旧资产、发布后回查并校验 SHA256；平台级 Immutable releases 开关需在仓库 Settings 手动打开 | 脚本完成，开关待确认 |

进度与证据见 [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md)，路线见 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)，历次工作报告见 [`docs/reports/`](docs/reports/)。

---

## 二、三条安全锁（写死在生成器里，不是开关）

| 锁 | 行为 |
|---|---|
| 大陆永远直连 | `routing.china_policy='proxy'` 会被**拒绝**：`config generate` 直接失败并提示改成 `direct`。没有任何开关能把大陆流量送进代理 |
| `fail_closed` 常在 | 大陆规则集缺失**且**下载失败时，生成**纯直连**配置（`route.final` / `dns.final` = `direct`）并返回非 0，绝不退化成全局代理 |
| 内网永不出路由器 | `10.10.10.10`、`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、所有节点服务器地址、`transparent.exclude`、路由器自身 LAN 地址，全在 bypass 集合或直连规则里；LAN 流量是被路由的，不是被抓包的，永远不进内核 |

读法：规则集坏了，你丢的是国外网站，不是内网。`easyproxy doctor` 会把这两把锁报告成 `ok`。`install.sh` 从不写这些字段，只装二进制并把 UCI 指向它们。

---

## 三、一条命令安装（路由器 SSH 里执行）

```sh
# 装面板 + sing-box + dae
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh

# 看当前装了什么
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s status

# 三件套一起升级（逐组件打印旧版本 → 新版本，内核坏了回滚）
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s upgrade

# 卸载（默认保留配置并先打备份；加 --purge 连配置一起删）
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
```

`opkg` 与 `apk` 固件都支持，Kwrt 也在识别范围内（见下节）；`api.github.com` 被限流时会按 `PKG_VERSION` 拼出资产地址；命令可重复执行。想先看再跑：

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh
sh /tmp/install.sh
```

### 安装参数

| 命令 | 作用 |
|---|---|
| `sh install.sh` | 面板 + sing-box + dae |
| `sh install.sh upgrade` | 三组件升级，先打印版本表 |
| `sh install.sh upgrade --only dae` | 只升级某一个组件（`package` / `sing-box` / `dae`） |
| `sh install.sh status` | 三组件的已装版本 |
| `sh install.sh --ipk` / `--apk` / `--rootfs` | 强制指定包装形式 |
| `sh install.sh --no-sing-box` / `--no-dae` / `--no-engine` | 只装其中一部分 |
| `sh install.sh --help` | 用法，不联网 |

安装器会做这些事：

1. 检测固件：`ImmortalWrt` / `OpenWrt` 认 `VERSION_ID`，Kwrt 认 `DISTRIB_RELEASE`（它的镜像没有 `VERSION_ID`），两者都必须能解析出 OpenWrt 基线且不低于 21.02；包管理器（`opkg` / `apk`）两者都没有且没加 `--rootfs` 就停止；
2. 从最新 Release 挑匹配本机架构的资产（opkg 优先架构包，拿不到再退 `_all.ipk`；若这个 opkg 根本不认 `Architecture: all`，就用 `--force-architecture` 装 `_all.ipk` —— 只对面板生效，内核包永不强制；连强制也被拒（如报 `Malformed package file`）时，改用已校验的 `-rootfs.tar.gz` 归档装面板，退出码仍为 0 并在日志里写明走了归档）；
3. **每个下载都先过 `SHA256SUMS`**，校验不过最多重下 3 次（CDN 边缘可能给旧对象），仍不过就失败；
4. 按「面板 → sing-box → dae」顺序安装，各自来自自己的 Release 资产；没有现成资产时用脚本内固定 sha256 的上游包，解开确认是真正的 ELF 再落到 `/usr/bin/`；
5. 把装了什么记进 `/etc/easyproxy/owned/`，以后卸载只删这些，用户自己装的 sing-box/dae 不会被碰；
6. 把 `easyproxy.sing_box.binary` / `easyproxy.dae.binary` 指向它们，`main.engine` 为空时才补值；启用服务并重启 `rpcd` 让菜单出现；
7. 对两个内核各跑一次 `version`，打印分组件小结，任何一个没装好就退出非 0。

### Kwrt 固件

Kwrt（`dl.openwrt.ai` 上的构建）是基于 OpenWrt 的衍生固件，安装器把它和 ImmortalWrt、OpenWrt 一样当作受支持对象，但判定依据不同：

| 项 | 实测值（取自 `kwrt-10.08.2026-ramips-mt7621-…-rootfs.tar.gz` 的 `/etc/openwrt_release`） |
|---|---|
| `DISTRIB_ID` | `Kwrt` |
| `DISTRIB_RELEASE` | `25.12-SNAPSHOT` |
| `VERSION_ID` | **没有这一行**，所以版本只能从 `DISTRIB_RELEASE` / `DISTRIB_DESCRIPTION` 取 |
| 包管理器 | `opkg`（镜像里有 `/bin/opkg`、`/etc/opkg/distfeeds.conf`，没有 `apk`；即使 25.12 基线也没换 apk） |
| LuCI | 自带 `luci-base`、`/usr/share/luci/menu.d`、`/usr/share/rpcd/acl.d`，面板依赖满足 |

- 基线 ≥ 21.02：放行，日志写明 `firmware: Kwrt 25.12-SNAPSHOT (OpenWrt 25.12 derivative)`；
- 基线 < 21.02（例如 19.07）：拒绝并写明低于 21.02；
- 版本号解析不出来（如只有 `SNAPSHOT`）：拒绝并说明无法确认基线，不再默默放过；
- 架构不在 `x86_64` / `aarch64` / `armv7`（例如 `mipsel_24kc`）：`_all.ipk` 面板照装（必要时 `--force-architecture`，再不行走 rootfs 归档），但会明确提示这个构建没有该架构的内核包；
- opkg 拒绝 `all` 且发布里没有该架构 ipk（旧版会直接报 `no installable ipk for arch` 停住）：现在不再停住 —— 面板是纯脚本包，强制架构或用归档都能装；内核仍然只按架构给，不能跑的不硬装；
- 确认过版本仍要强装：`EP_SKIP_COMPAT=1`（日志会标注是强制安装）。

### 装完还不能直接用（重要）

安装**不会**替你建节点、开开关。默认是 `enabled=0`、`engine=none`、零节点，所以装完要三步：

```sh
easyproxy node add 'ss://...'          # 或用面板「节点」页导入
uci set easyproxy.main.engine='sing-box'
uci set easyproxy.main.enabled='1'
uci commit easyproxy
easyproxy config generate              # 首次会下载规则集，写出并用 sing-box check 校验
/etc/init.d/easyproxy enable
/etc/init.d/easyproxy start
easyproxy status
```

要让整个 LAN 走代理，再开透明抓包：

```sh
uci set easyproxy.transparent.enabled='1'
uci set easyproxy.transparent.lan_interfaces="$(uci get network.lan.device 2>/dev/null || echo br-lan)"
uci commit easyproxy
easyproxy restart                      # 重新生成配置（加 tproxy 入站）并应用抓包
easyproxy transparent status
```

想撤掉抓包、不影响其他配置：

```sh
easyproxy transparent remove
uci set easyproxy.transparent.enabled='0'
uci commit easyproxy
easyproxy restart
```

---

## 四、面板

菜单在 LuCI「服务 → EasyProxy」，10 个页面：

| 页面 | 内容 |
|---|---|
| 总览 | 运行状态、流量曲线、节点数、分流/抓包状态 |
| 节点 | 列表、增删、导入、测速 |
| 订阅 | 填订阅地址拉取（一次性导入） |
| 分流 | 平台开关、自定义规则 |
| 内核 | 内核选择与健康检查 |
| DNS | 解析方式与服务器 |
| 规则 | 规则集状态与更新 |
| 日志 | 运行日志与轮转 |
| 备份 | 配置备份/恢复/重置 |
| 设置 | 主要 UCI 选项 |

面板所有数据都来自 `easyproxy <命令> --json`，不直接读文件，也不解析日志。

---

## 五、分流与 DNS

- `route.rules`：私网 IP + 大陆规则集（geosite-cn / geoip-cn）→ `direct`；`route.final` → `proxy`。
- DNS：`dns-local`（223.5.5.5，走 direct）与 `dns-remote`（DoH，走 proxy）分离；`.cn`、geosite-cn、私网走本地解析，其余走远端。
- 规则集用**本地文件**（`type: local`），不用 `type: remote`。原因很实际：remote 型规则集在引擎启动时下载，下载失败会让整个进程 `initialize rule-set` 直接退出，路由器断网时反而起不来（对 1.14.4 实测确认）。

规则集缺失时的行为：

| 情况 | 行为 |
|---|---|
| 文件在且没过期 | 分流正常 |
| 文件缺，下载成功 | 分流正常，文件缓存到本地 |
| 文件缺，下载失败 | `fail_closed` 生效：生成全直连配置，`config generate` 退出非 0，不会漏成全局代理 |
| 没有启用的节点 | `route.final` / `dns.final` 退回 `direct` / `dns-local` |

---

## 六、透明代理

抓包需要的对象全在自有命名空间，不碰 fw4：

| 对象 | 名字 | 为什么 |
|---|---|---|
| nft 表 | `table ip easyproxy` | 不碰 fw4 的表，删它不会破坏路由器防火墙 |
| 链 | `prerouting`（`mangle` 优先级） | 在路由决策前截获 LAN 入站 |
| 集合 | `bypass_ipv4` | 私网段 + 所有节点服务器地址 + `transparent.exclude` |
| 策略规则 | `fwmark <mark> lookup <table>` | 把打了标记的包交回本机协议栈 |
| 路由表 | `local default dev lo` | 标记包的去向 |
| 生成文件 | `/etc/easyproxy/nftables.conf` | 实际装载的内容，可 `nft -f` 重放或排查 |

以下任一条件成立时，`easyproxy transparent apply` **拒绝执行且什么都不改**（因为每一条都会让 LAN 黑洞）：

| 拒绝条件 | 原因 |
|---|---|
| `transparent.enabled=0` | 功能没开 |
| 没有启用的节点 | 抓了也没地方去 |
| `nft` 缺失或不可执行 | 没有工具装载规则 |
| 引擎没在跑 | 有 tproxy 规则却没有监听者，包直接丢 |

回滚只需删表和删规则：`easyproxy transparent remove`（`easyproxy stop` 和 init 的 `stop_service` 也会自动调用）。它不需要知道防火墙原来长什么样。

内核要求：tproxy 监听需要 `CAP_NET_ADMIN`（`IP_TRANSPARENT`）。路由器上 procd 以 root 跑引擎，满足；非特权容器里 sing-box 会报 `configure tproxy TCP listener: operation not permitted`（已实测），说明配置是对的、环境不能抓。`sing-box check` 只校验语法，查不出这种情况。

---

## 七、节点与订阅

每个 `config node` 段对应一个 sing-box 出站；启用的节点放进一个延迟测试组（`urltest`，5 分钟一轮，50 ms 容差）。

```sh
uci add easyproxy node
uci set easyproxy.@node[-1].name='hk-01'
uci set easyproxy.@node[-1].type='shadowsocks'    # shadowsocks | vmess | trojan | socks | http
uci set easyproxy.@node[-1].server='203.0.113.10'
uci set easyproxy.@node[-1].port='8388'
uci set easyproxy.@node[-1].method='aes-256-gcm'
uci set easyproxy.@node[-1].password='secret'
uci commit easyproxy
```

各类型必填：`shadowsocks` 要 `method`+`password`；`vmess` 要 `uuid`（可选 `alter_id`）；`trojan` 要 `password`；`socks`/`http` 的账号密码可选。`tls`+`sni` 用于 `trojan`、`vmess`、`hysteria2`、`tuic`（后两者必须 `tls=1`，手写时漏了会让整份配置生成失败）。任一节点缺字段，生成会指名该节点并中止，不会产出一份跑不起来的配置。

分享链接更快：

```sh
easyproxy node add '<链接>'    # ss:// vmess:// vless:// trojan:// hysteria2:// tuic:// socks://
easyproxy node import <文件>   # 批量
easyproxy node export          # 原样导出
/usr/lib/easyproxy/subscribe.sh <订阅地址>   # 拉订阅，URL 不落 UCI、不进日志
```

---

## 八、常用命令

| 命令 | 作用 |
|---|---|
| `easyproxy status [--json]` | 运行状态、配置状态、分流/抓包状态 |
| `easyproxy config generate` | 取规则集、生成并校验 `sing-box.json` |
| `easyproxy start` / `stop` / `restart` | 启停（`stop` 会先撤抓包） |
| `easyproxy engine list\|health\|version` | 内核注册表与健康检查 |
| `easyproxy node list\|add\|import\|export\|del\|test` | 节点操作 |
| `easyproxy ruleset update\|verify` | 规则集更新/校验 |
| `easyproxy doctor [--json]` | 11 项自检 |
| `easyproxy log rotate` | 日志轮转 |
| `easyproxy config backup\|restore\|reset` | 备份/恢复/重置 |
| `easyproxy transparent apply\|remove\|status\|audit` | 抓包 |
| `easyproxy uninstall-clean` | 只删 EasyProxy 自己的 nft 对象 |

---

## 九、主要配置项

分流：

| 选项 | 默认 | 含义 |
|---|---|---|
| `routing.china_policy` | `direct` | 锁死：大陆流量永远不走代理，写 `proxy` 会被拒 |
| `routing.proxy_policy` | `proxy` | 非大陆流量与远端 DNS 使用的组 |
| `routing.fail_closed` | `1` | 锁死：规则集缺失时全直连，没有全局代理兜底 |
| `routing.rule_set_dir` | `/etc/easyproxy/ruleset` | `.srs` 文件位置 |
| `routing.rule_set_update_days` | `7` | 缓存超过多少天就重下 |
| `routing.dns_local_server` | `223.5.5.5` | 国内解析器 |
| `routing.dns_remote_server` | `https://1.1.1.1/dns-query` | 远端 DoH |

透明代理：

| 选项 | 默认 | 含义 |
|---|---|---|
| `transparent.enabled` | `0` | 总开关，为 1 且引擎在跑才抓包 |
| `transparent.tproxy_port` | `7891` | tproxy 监听端口，必须与生成的配置一致 |
| `transparent.fwmark` | `1` | nft 打标记、策略规则匹配 |
| `transparent.route_table` | `100` | 存放 `local default dev lo` 的表 |
| `transparent.lan_interfaces` | `br-lan` | 被截获的入站接口，空格分隔 |
| `transparent.exclude` | 空 | 额外保持直连的地址/CIDR |
| `transparent.ipv6_policy` | `direct` | `direct` 或 `block`：IPv6 不会被静默抓包 |

---

## 十、生成的配置长什么样

```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "dns-local",  "address": "223.5.5.5", "detour": "direct" },
      { "tag": "dns-remote", "address": "https://1.1.1.1/dns-query", "detour": "proxy" }
    ],
    "rules": [
      { "domain_suffix": [".cn"], "server": "dns-local" },
      { "rule_set": ["geosite-cn"], "server": "dns-local" },
      { "ip_is_private": true, "server": "dns-local" }
    ],
    "final": "dns-remote"
  },
  "inbounds": [
    { "type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 7890 },
    { "type": "tproxy", "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": 7891,
      "sniff": true, "sniff_override_destination": true, "udp_timeout": "5m" }
  ],
  "outbounds": [
    { "type": "urltest", "tag": "proxy", "outbounds": ["hk-01"], "url": "http://www.gstatic.com/generate_204", "interval": "5m", "tolerance": 50 },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "auto_detect_interface": true,
    "rules": [
      { "ip_is_private": true, "outbound": "direct" },
      { "rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct" }
    ],
    "rule_set": [
      { "type": "local", "tag": "geosite-cn", "format": "binary", "path": "/etc/easyproxy/ruleset/geosite-cn.srs" },
      { "type": "local", "tag": "geoip-cn", "format": "binary", "path": "/etc/easyproxy/ruleset/geoip-cn.srs" }
    ],
    "final": "proxy"
  }
}
```

（示例省略了每个节点自己的出站；tproxy 入站只在 `transparent.enabled=1` 且有节点时出现。）

---

## 十一、目录结构

```
package/easyproxy/
├── Makefile
└── files/
    ├── etc/config/easyproxy
    ├── etc/init.d/easyproxy
    ├── etc/hotplug.d/iface/95-easyproxy
    ├── usr/sbin/easyproxy
    ├── usr/lib/easyproxy/{common,config,transparent,node,maint,traffic,subscribe}.sh
    ├── usr/lib/easyproxy/adapters/{dae.sh,sing-box.sh}
    ├── usr/share/easyproxy/easyproxy.default
    ├── usr/share/luci/menu.d/luci-app-easyproxy.json
    ├── usr/share/rpcd/acl.d/luci-app-easyproxy.json
    ├── www/luci-static/resources/easyproxy/app.js
    └── www/luci-static/resources/view/easyproxy/*.js   （10 个视图）
scripts/
├── make-ipk.sh          # 从 package/easyproxy 打 ipk（all / x86_64 / …）
├── make-kernel-ipk.sh   # 打 sing-box_<ver>_<arch>.ipk / dae_<ver>_<arch>.ipk
├── install.sh           # 一键安装：面板 + 两内核，含 upgrade / status
└── uninstall.sh         # 一键卸载：备份、--purge、--keep-kernels
tests/                   # 14 套 672 项
docs/
├── PROJECT-STATUS.md    # 真实完成度
├── DEVELOPMENT-PLAN.md  # 阶段路线
├── reports/             # 每次工作的独立报告（NNN-日期-任务）
└── router-install-test.md  # 真机验收清单（尚未有验收记录）
```

---

## 十二、测试与 CI

全部套件都能在任意 Linux 上跑，不需要 OpenWrt、不需要真内核（沙箱里生成 stub 版 `sing-box`）；`tests/run-all.sh` 是唯一计数来源：

```sh
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/run-all.sh
```

| 套件 | 项数 |
|---|---|
| `test-install-scripts.sh` | 126 |
| `test-transparent.sh` | 87 |
| `test-nodes.sh` | 61 |
| `test-regressions.sh` | 47 |
| `test-engine.sh` | 45 |
| `test-release.sh` | 45 |
| `test-maintenance.sh` | 44 |
| `test-bypass.sh` | 41 |
| `test-ipk-layout.sh` | 40 |
| `test-security.sh` | 33 |
| `test-routing.sh` | 32 |
| `test-manager.sh` | 30 |
| `test-cli.sh` | 21 |
| `test-runtime.sh` | 20 |
| **合计** | **672** |

CI（`.github/workflows/build.yml`）的顺序是：下载并校验 pinned `sing-box 1.14.4` → 用真实内核跑整套测试（失败即停，绝不发布）→ 下载官方 ImmortalWrt SDK（25.12.2，x86-64，pin sha256）→ 编译原生包 → 打 opkg / apk 三形态 → 用上游归档打三架构 sing-box 与 dae 内核包 → 写 `KERNEL-VERSIONS` → `SHA256SUMS` → 发布 → 回查 Release。

**CI 的真内核校验（如实写）**：`EP_SING_BOX_BIN` 只注入四个配置相关套件，不通过 `$GITHUB_ENV` 全局下发；归档先过 pinned SHA256，下载或校验失败整次构建变红，不会降级成「跳过」。完整结果：**672 通过 / 0 失败 / 0 跳过**。

## 十三、发布资产

| 资产 | 用途 |
|---|---|
| `easyproxy_0.8.2-1_all.ipk` | 任意 opkg 固件，架构无关 |
| `easyproxy_0.8.2-1_x86_64.ipk` | 拒绝 `Architecture: all` 的 opkg 固件（x86_64） |
| `easyproxy-0.8.2-r1.apk` | 用 `apk` 的 ImmortalWrt 25.x 镜像 |
| `easyproxy-0.8.2-rootfs.tar.gz` | 没有匹配包管理器时直接解到 `/` |
| `sing-box_1.14.4_<arch>.ipk` | sing-box 内核，按架构分包 |
| `dae_2.1.2_<arch>.ipk` | dae 内核（二进制 + `/usr/share/dae` 路由数据） |
| `SHA256SUMS` | 上面的 sha256，安装器逐项校验 |
| `KERNEL-VERSIONS` | 本版本固定了哪些内核版本与架构 |

内核不能塞进 `_all.ipk`：那个包架构无关，塞了 amd64 二进制就会装到 ARM 路由器上。三个包也意味着三者可以分别升级、分别卸载。

**发布机制（版本号即发版命令）**：`build.yml` 先把「这次发不发、发哪个 tag」定下来——手工 push 的 `v*` tag、手动运行填的版本号、或者**版本号判定**：`PKG_VERSION` 比最新 Release 新就自己发版，相等或更低只构建。提交说明里带 `[no-release]` 可以豁免一次。并发用 job 级 `concurrency` 串行，同一 ref 不会两个构建同时发版；已存在同名 Release 直接失败、不 `--clobber`；发布后回查 tag / 非 draft / 资产数 / 必需资产，把资产实下后 `sha256sum -c SHA256SUMS`，再对每个下载链接断言 200，任一条不过这次构建就是红的。

`v0.8.2` 是这套机制下的一次完整发布：12 项资产，下载后 12/12 通过 `sha256sum -c`。

本地构建：

```sh
sh scripts/make-ipk.sh package/easyproxy dist all
sh scripts/make-ipk.sh package/easyproxy dist x86_64
sh scripts/make-kernel-ipk.sh sing-box x86_64 dist
sh scripts/make-kernel-ipk.sh dae x86_64 dist
```

---

## 十四、开发与报告制度

每次开发、修 bug、跑测试、编译，都必须留一份独立报告在 [`docs/reports/`](docs/reports/)，规则见 [`docs/reports/README.md`](docs/reports/README.md)，核心是：

- 编号连续（`NNN-YYYY-MM-DD-任务名.md`），只增不减、不覆盖、不删除；
- 报告必填 14 项：目标、文件、逐文件改动、新增功能、未实现功能、删除理由、测试、测试结果、编译、产物、Commit SHA、遗留、下一步、阶段判定；
- 没跑测试不写通过，没真跑不写可用，没产物不写交付；失败记录必须保留；
- 先提交代码，再提交报告，报告里写代码提交的 SHA。

现状与路线：`docs/PROJECT-STATUS.md`、`docs/DEVELOPMENT-PLAN.md`。最近一次全量审计见 `docs/reports/001-2026-11-16-audit.md`。

---

## 十五、路线图（版本即里程碑）

版本号由维护者策划、连续递增，每一档只做一件事：

| 版本 | 里程碑 | 状态 |
|---|---|---|
| 0.8.2 | M1 入口旁路：国内流量不进内核（`cn_ipv4` 集合 + tproxy 之前 `return`） | 已发布（沙箱验证，待真机验收） |
| 0.8.3 | M2 无缝热切换：clash API，换节点不断连 | 未开始 |
| 0.8.4 | M3 引擎接口 v2 + dae 条件化加载 | 未开始 |
| 0.8.5 | M4 十个平台分流 + 可绑定地区组 | 未开始 |
| 0.8.6 | M5 架构矩阵扩展 | 未开始 |
| 0.8.7 | M6 生态第一步：profile 导出 + 扫码导入 | 未开始 |
| 0.8.8 | M7 真机验收 + 面板升级 | 未开始 |
| 0.8.9 | M8 dae 真正启动 | 未开始 |

已完成的底座：0.5.x 打包与面板、0.6.0 十页面板与维护 CLI、0.7.0 发布合规、0.8.0/0.8.1 安装器与安全锁、0.8.2 入口旁路。进度与证据见 [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md)，路线细项见 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)。

## 十六、许可证

MIT，见 `LICENSE`。
