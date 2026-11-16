# EasyProxy 开发进度报告（PROJECT-STATUS）

- 盘点时间：2026-11-16 21:50（UTC+8）
- 盘点基准：远端 `main` = `d08a22539c22ea1e32357131dd97fbeabe07f182`
- 当前版本号：`0.6.0`；Release：`v0.6.0`（id 446714911）
- 约定：**每完成一个开发阶段，必须更新本文件并提交到 `main`**。

---

## 1. 代码盘点：本地 / 未提交 / 已推送

| 检查项 | 实测结果 |
|---|---|
| 本机（Windows）项目目录里有源码树吗 | 没有。`new-chat-1\EasyProxy-0.6.0\` 只放已下载的发行包、`SHA256SUMS`（372B，只含 4 条）和安装说明 |
| 有没有未提交的本地改动 | 没有。源码工作区在云主机 `/tmp/ep20`，与 `git clone` 出来的 `/tmp/ep26`（HEAD=`d08a225`）逐文件 `diff` 为 0 |
| 本地是否落后远端 | 不是。`scripts/install.sh`、`tests/test-install-scripts.sh`、`README.md` 与远端均一致 |
| 有没有未推送的分支/提交 | 没有。所有改动直接推 `main`，无本地分支 |

证据：`git clone --depth 1` 后 `diff /tmp/ep20/scripts/install.sh /tmp/ep26/scripts/install.sh` 无输出；`diff` 两个 `test-install-scripts.sh` 无输出；clone 内跑 install 套件 `126 通过 0 失败`。

> 说明：本机（Windows）无 git/curl，源码撰写、编译、测试都在云主机完成，所以"本地"这个词在本项目里指云主机工作区；本机只保存发行包。

---

## 2. 最近提交清单（新 → 旧，只列本次 0.6.0 三组件相关部分）

| 提交 | 时间(UTC) | 改动文件 | 功能 |
|---|---|---|---|
| `d08a225` | 11-16 13:19 | `README.md` | 测试计数对齐（471 项 / install 126） |
| `fdbb612` | 11-16 13:17 | `tests/test-install-scripts.sh` | 整文重推完整 623 行套件（此前两次 push 把文件写截断成 90/93 行） |
| `9df452f` | 11-16 13:16 | `tests/test-install-scripts.sh` | 同上，仍然截断（问题提交，保留历史） |
| `268f905` | 11-16 13:15 | `scripts/install.sh`、`tests/test-install-scripts.sh` | 坏包重试：`fetch_verified` / `fetch_pinned` 最多 3 次；测试文件被截断 |
| `54beb6d` | 11-16 12:58 | `docs/router-install-test.md` | 真机验收加 Step 8（三组件与独立生命周期） |
| `5f851da` | 11-16 12:58 | `README.md` | Layout 树补齐四个脚本 |
| `d73f15d` | 11-16 12:56 | `README.md` | 修 Layout 树的占位乱码 |
| `4350953` | 11-16 12:55 | `README.md` | 三组件安装、升级/状态、内核资产说明 |
| `07454f2` | 11-16 12:54 | `.github/workflows/build.yml` | 逐架构构建 sing-box/dae ipk，发布 `KERNEL-VERSIONS` 与校验资产 |
| `c83c09a` | 11-16 12:52 | `tests/test-install-scripts.sh` | 三组件安装/内核升级回滚/卸载开关（119 项） |
| `ed7556d` | 11-16 12:50 | `scripts/install.sh` | 一键装面板+sing-box+dae，含 upgrade/status/rollback |
| `ad6ce56` | 11-16 12:49 | `scripts/make-kernel-ipk.sh` | 按架构打 sing-box/dae ipk |
| `955cc89` | 11-16 12:48 | `scripts/install.sh`、`scripts/uninstall.sh`、`scripts/make-kernel-ipk.sh` | 三组件安装器、卸载器（备份/`--purge`/`--keep-kernels`） |
| `5daeee9` / `ec24288` | 11-16 12:17/12:16 | `scripts/install.sh`、测试 | 内核随装、校验拒绝、`--no-engine` |
| `bed4757` | 11-16 11:53 | `.github/workflows/build.yml` | 重建时刷新 release 说明（写明构建提交） |
| `2c61640` / `caad5df` | 11-16 11:28/11:26 | `scripts/install.sh`、测试 | 按 opkg 自身架构列表选包、校验、拒绝坏包 |
| `b4ab1c1` | 11-16 11:10 | `README.md`、测试 | 测试计数、架构感知安装器、Stage 7 状态 |
| `4239ccd` / `f75e6a1` | 11-16 10:52/10:51 | `scripts/install.sh`、测试 | 优先架构匹配 ipk，404 回退 `_all` |
| `39248a2` | 11-16 10:20 | `Makefile`、`scripts/make-ipk.sh`、CI | 架构写进 ipk，同时出 `all`/`x86_64` 两版，CI 以测试为门禁 |
| `c176092` / `1a438bb` / `c83bb26` | 11-16 10:11~10:05 | `maint.sh`、`app.js`、`www/.../view/easyproxy/*.js` | 维护子命令、中文深色 10 视图面板、split 页语法修复 |
| `b6d4816` / `6d33ba7` / `3e8a4c7` / `c8cbcab` | 11-16 9:29~9:32 | `config.sh`、`common.sh`、`node.sh`、CLI | 地区延迟组+selector、vless/hysteria2/tuic、平台与自定义规则、分享链接导入导出、engine/node 子命令 |
| `486af6a` / `f69513d` / `79c1855` / `f93ecd9` | 11-16 7:40~7:43 | `config.sh`、`transparent.sh`、CLI | 锁死 `china_policy=direct`、`fail_closed=1`、保护路由器 LAN 地址与 `10.10.10.10`、bypass 集合不相交 |
| Stage 2~5（`12af47`…`24e50ae`） | 11-15~11-16 | 全部包文件 | 面板→CLI→配置生成→分流/DNS→透明抓包（TPROXY） |

---

## 3. 功能模块完成度（对照真实代码，不看测试数）

状态定义：**已完成**＝代码实现且能端到端跑到证据；**部分完成**＝主链可用但有明确缺口；**未完成**＝没有实现；**只有框架**＝接口/占位在、能力不在。

| # | 模块 | 状态 | 代码证据 | 明确缺口 |
|---|---|---|---|---|
| 1 | LuCI 中文管理面板 | 已完成（未真机渲染验证） | `www/luci-static/resources/view/easyproxy/` 10 个视图；`easyproxy/app.js` 858 行，全部数据走 `easyproxy <cmd> --json`；可写：节点增/删/导入、订阅导入、内核切换、平台分流开关、设置保存(uci.save)、启停/重载/配置生成/抓包开关/doctor、流量曲线 | 未在真实 rpcd+ACL 的 LuCI 里跑过；节点没有"编辑现有节点"表单（只能删了重加） |
| 2 | sing-box 内核 | 已完成（运行时未真机验证） | 安装器落 `/usr/bin/sing-box`（1.10.7）；`config generate` 用真二进制 `check`；procd 托管 `easyproxy run` | vm 无 CAP_NET_ADMIN，tproxy 实际转发未验证；小 flash 设备上 11MB 内核的余量未测 |
| 3 | dae 内核 | 只有框架 | `adapters/dae.sh` 六个动词齐全，但 `dae_run` 返回 2、`ep_engine_stability=dae:dev`，`easyproxy start` 直接拒绝并提示"开发中"；安装器只落二进制 + `/usr/share/dae` geodata，**不动** `main.engine` | 没有 dae 配置生成、没有运行时分流；dae 目前只装不用 |
| 4 | 节点管理 | 已完成 | `node.sh` 338 行：ss/ssr/vmess/vless/trojan/hysteria2/tuic/socks/http 8 类分享链接解析、批量导入、导出、删除；`node list/test`；`subscribe.sh` 拉订阅（URL 不写 UCI、不写日志） | 无节点健康度历史；无"节点到期/流量"解析（订阅只取节点） |
| 5 | 智能节点分组 | 部分完成 | `common.sh`：`ep_node_region` 按名称关键词分地区，`ep_node_regions` 去重；`config.sh` 每地区一个 `urltest`（interval 5m，tolerance 50），前面一个 `selector tag=proxy`，默认第一个地区 | 无分组权重/优先级；平台不能绑定到指定地区组；selector 不能运行时切换（见第 8 项） |
| 6 | YouTube / Netflix / TikTok 分流 | 部分完成 | `config.sh` `ep_platform_rules_json`：三平台 `domain_suffix` → `proxy`，UCI 开关 `routing.platform_youtube/netflix/tiktok` 默认开；规则排在 CN 规则集之前，且仅在 split=1 时下发（缺规则集时自动失效，避免重新打开代理口子） | 三个平台共用同一个 `proxy` selector，做不到"Netflix 固定走美区"；用的是内联域名表而非 geosite 规则集，冷门域名会漏 |
| 7 | 节点测速和自动优选 | 部分完成 | 自动优选＝内核 `urltest`（真延迟、5 分钟重测）；`easyproxy node test` = TCP connect 探测（`ep_tcp_probe`，3s 超时） | TCP 握手时间 ≠ 代理链路延迟；无带宽测速；无"探测结果写回排序给源站用" |
| 8 | 无缝切换 | 未完成（仅配置侧框架） | 配置里生成 `selector`，但没有 `experimental.clash_api.external_controller`，CLI 无 `node select` / `engine select` 类命令，LuCI 无切换按钮 | 换地区/换节点＝重写配置 + 重启服务，连接会断；这是 0.6.0 之后最该补的一块 |
| 9 | DNS 分流 | 已完成 | `config.sh` dns：`dns-local`(223.5.5.5, detour direct)、`dns-remote`(DoH, detour proxy)；规则顺序 私网 + `.lan/.local/.localdomain/.home.arpa/.internal` → `.cn` + geosite-cn → final；`split=0` 时回落单一解析器 | 未跑过真实 DoH 超时/回退场景；无 DNS 泄漏检测命令 |
| 10 | 国内 DIRECT 直连 | 已完成（且锁死） | `config.sh` `routing.china_policy` 只接受 `direct`，写 `proxy` 被 validate/`config generate` 拒绝并给出原因；CN 流量走 `geosite-cn`+`geoip-cn` → `direct`；`fail_closed=1` 锁死 | 无（这是安全锁，按要求不可配置） |
| 11 | 内网 10.10.10.10 绕过 | 已完成 | `transparent.sh:117` bypass 集合：`127.0.0.0/8, 169.254.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 192.0.0.0/24, 198.18.0.0/15, 240.0.0.0/4, 10.10.10.10/32`；config 侧 `ip_is_private` + 节点服务器地址 + 路由器 LAN 地址 → `direct` | 未在真机核对 nft set 实际装载内容（vm 无 nft） |
| 12 | 安装、升级、卸载和回滚 | 已完成（升级/回滚未真机端到端） | `install.sh` 999 行：三组件安装、`upgrade`（版本表/`--only`/坏内核回滚/`upgrade incomplete` 非 0）、`status`、`--apk/--ipk/--rootfs/--no-*`；`uninstall.sh`：先撤抓包→停服→卸包→只删 `owned/` 登记内核，备份默认写 `/root/easyproxy-backup-<日期>.tar.gz` | 安装已在真资产上跑通；**升级与回滚只被 stub 测试覆盖**，没在真实 Release 资产上跑过（vm 无 opkg/apk） |

### 三条安全锁（本次盘点逐条复核，均在代码里）

1. `china_policy=proxy` 被 `config.sh` 拒绝 → 中国大陆永远直连，没有开关能绕过。
2. `fail_closed=1` 锁死 → CN 规则集缺失时生成**纯直连**配置并返回非 0，绝不退化成全局代理。
3. 内网直连：`10.10.10.10`、`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、路由器本机与 LAN 全部在 bypass/direct，LAN 流量不进内核。

---

## 4. 最近一次成功编译的全部产物

当前 Release `v0.6.0` 的资产（GitHub 上传时间 **2026-11-16T13:28:32Z**，`KERNEL-VERSIONS` 里写明 `built from commit: 9df452fb…`）：

| 文件名 | 大小 | sha256 | 下载地址 |
|---|---|---|---|
| `easyproxy_0.6.0-1_all.ipk` | 48.8 KB | `4ac456893e25c0d5b249e7025a56514cd3648fd77bf0f7ddee0cc29ae1079386` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/easyproxy_0.6.0-1_all.ipk |
| `easyproxy_0.6.0-1_x86_64.ipk` | 48.8 KB | `45e2009ae8500d1d195ee2df54cd3ccc97b49f373cc4017d5f152c8050ecd9e8` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/easyproxy_0.6.0-1_x86_64.ipk |
| `easyproxy-0.6.0-r1.apk` | 50.8 KB | `13db5582034c3a1fc25a03a10cd1151cf5e95d992cd5b38631eb495d58559b6c` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/easyproxy-0.6.0-r1.apk |
| `easyproxy-0.6.0-rootfs.tar.gz` | 48.1 KB | `be169b84b6df1210c784a6fd7d1595756d997c0eec5f24593eb232ce9d834f41` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/easyproxy-0.6.0-rootfs.tar.gz |
| `sing-box_1.10.7_x86_64.ipk` | 11.2 MB | `4f50df35b2870dc9a281f31f3ea4df38965739557fac5b8e2660b7bcb55c1f15` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/sing-box_1.10.7_x86_64.ipk |
| `sing-box_1.10.7_aarch64_cortex-a53.ipk` | 10.3 MB | `c3a0265a51c11b690217d0b02a7bc98c742f883716fbcf2d76a9eb4cc01e6cbb` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/sing-box_1.10.7_aarch64_cortex-a53.ipk |
| `sing-box_1.10.7_arm_cortex-a7_neon-vfpv4.ipk` | 10.3 MB | `de94dd54662957bdfbec826a6be7dd3598bd7e77c52521ca250eb835a38d3d59` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/sing-box_1.10.7_arm_cortex-a7_neon-vfpv4.ipk |
| `dae_2.1.2_x86_64.ipk` | 18.4 MB | `e607af50991260ffba12aff6d87100f42d4452c93fdfc556c9c5eec646d7cef7` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/dae_2.1.2_x86_64.ipk |
| `dae_2.1.2_aarch64_cortex-a53.ipk` | 17 MB | `add5a2ad884f1dc02412ba72a4bb1bd36e613fe2731a6f8e77fd41f14a517710` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/dae_2.1.2_aarch64_cortex-a53.ipk |
| `dae_2.1.2_arm_cortex-a7_neon-vfpv4.ipk` | 17.5 MB | `01fff79689caa327eecaafca6e31de740ae91ce5d8e5dd8e26a83fb36eeab7f9` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/dae_2.1.2_arm_cortex-a7_neon-vfpv4.ipk |
| `KERNEL-VERSIONS` | 391 B | `723ae8242d30003af0d70b1627032800562ea9f1438be76116ff9b4aa6bb3aa6` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/KERNEL-VERSIONS |
| `SHA256SUMS` | 1.03 KB（11 条） | `61f40f70d277120ebe288444a5159326250c81e3adfb939f8d44e40aa4569119` | https://github.com/bnm188/EasyProxy/releases/download/v0.6.0/SHA256SUMS |

本次盘点实测校验（云主机 `/tmp/relnow`，刚下载）：

```
easyproxy-0.6.0-rootfs.tar.gz: OK
easyproxy_0.6.0-1_all.ipk: OK
sing-box_1.10.7_x86_64.ipk: OK
dae_2.1.2_x86_64.ipk: OK
```

CI Artifacts（需登录 GitHub 才能下载，默认保留 90 天）：`easyproxy-immortalwrt-25.12.2`，来自最新成功的 run **#105**（commit `d08a225`，2026-11-16，1m55s，`completed successfully`）。

CDN 直链（不经 Release 页面，路由器上可直接 wget）：

```
https://github.com/bnm188/EasyProxy/raw/main/scripts/install.sh
https://github.com/bnm188/EasyProxy/raw/main/scripts/uninstall.sh
```

本机保存路径（**已过期，见第 5 节 R7**）：`C:\Users\Administrator\Doubao\chats\2026-11-16\new-chat-1\EasyProxy-0.6.0\`，里面是 4 个包 + 只有 4 条的旧 `SHA256SUMS`（372B）+ 安装说明。

云主机路径：`/tmp/ep26`（当前 clone，= `d08a225`）、`/tmp/ep20`（主工作区）、`/tmp/relnow`（本次下载校验的资产）、`/tmp/e2e3`（本次端到端安装的沙箱 root）。

---

## 5. GitHub Actions 与 Releases 一致性核查（含不一致项）

| 检查 | 结果 |
|---|---|
| 最新 CI run | #105（`d08a225`）**成功**；#104（`fdbb612`）成功；#103（`9df452f`）成功，12m23s |
| Release 资产是哪个提交产的 | `KERNEL-VERSIONS` 与 release 说明都写 `built from commit: 9df452fb…`，即 **run #103**，不是 HEAD |
| tag `v0.6.0` 指向 | `68f9dddf`（11-16 07:17），**早于**内核资产上线，也早于 `d08a225` |
| `SHA256SUMS` 覆盖 | 11 条，= 3×sing-box + 3×dae + 3×easyproxy + rootfs + KERNEL-VERSIONS（`SHA256SUMS` 自身不列），本次抽验 4 个资产全部 OK |
| 是否一致 | **不完全一致**，见下面 R1/R2 |

### 风险与不一致清单（需在下阶段处理）

| 编号 | 问题 | 影响 | 处理建议 |
|---|---|---|---|
| R1 | Release 资产由 `9df452f` 构建，HEAD 是 `d08a225` | 二者之间只改了 tests/docs，二进制功能等价，但"资产≠HEAD"这件事会被误读成"新代码已发布" | 保持现状即可，下个版本用 tag 构建；本文件写明以资产自带 `KERNEL-VERSIONS` 为准 |
| R2 | tag `v0.6.0` → `68f9dddf`，与资产构建提交 `9df452f` 不同 | 想从源码复现该版本会拿到更早的代码 | 下个版本改为"tag 触发构建 + 资产回填到同一 tag" |
| R3 | run #103 在 `tests/test-install-scripts.sh` 被截断成 93 行的提交上**仍然绿灯** | 测试门禁不校验套件完整性，截断的套件可以"少测而通过" | CI 加断言数下限检查（例如要求输出 `126 通过`，或校验文件行数/用例数） |
| R4 | 同一 Release URL 的 CDN 边缘会返回不同字节的旧包（实测 49211B vs 50336B） | 安装器可能拿到旧对象 | 已在 `install.sh` 用"校验失败重下最多 3 次"兜住；根因在 GitHub CDN，无法在脚本外解决 |
| R5 | 本机 `EasyProxy-0.6.0-安装说明.txt` 仍是"手动 opkg install sing-box"流程 | 与实际"一键装三组件"矛盾，会误导 | 下阶段重写该说明（不属于代码重构） |
| R6 | 没有真实路由器验收记录 | 透明抓包、tproxy 转发、升级回滚、LuCI 渲染都只在 stub/沙箱验证 | 见第 7 节任务 1 |
| R7 | 本机 `EasyProxy-0.6.0\` 副本过期：rootfs sha `da631867…`（当前是 `be169b84…`），`SHA256SUMS` 只有 4 条，缺 6 个内核 ipk + `KERNEL-VERSIONS` | 拿本机包去装会装到旧版本、且没有内核 | 以 Release 页面为唯一发包源；需要离线包时重新从 Release 下载 |

---

## 6. 当前实际开发阶段

- **代码阶段**：Stage 7（编译/安装/卸载验证）已在 `0.6.0` 收口：三组件一键装、独立升级、一键升级含版本表与回滚、一键卸载可选保留配置/备份、SHA256 强校验、拒绝错架构、失败不报成功，CI 出主程序 + 两个内核包 + `SHA256SUMS` + `KERNEL-VERSIONS`。
- **发布状态**：`v0.6.0` 有资产、有校验、有说明；资产来自 `9df452f`，HEAD 只多 tests/docs。
- **验证阶段**：Dev 级验证完成（471 项套件；真实 Release 资产端到端 `--rootfs` 安装 `EXIT=0`，`sing-box 1.10.7` / `dae 2.1.2` 均可执行 `version`）；**真机（真实 ImmortalWrt 路由器）验收未开始**。
- **一句话结论**：0.6.0 是"可以装、可以升、可以卸、可以校验"的版本；但 dae 只装不用，无缝切换没有，平台分流不能绑定地区，且一切都还没在真路由器上跑过。

## 7. 下一步最应该完成的三个任务

1. **真机验收（最高优先级）**：按 `docs/router-install-test.md` Step 0–8 在一台 x86_64 或 ARM 路由器上跑一遍；额外必须覆盖 `--ipk` 与 `--apk` 各一次、`sh install.sh upgrade` 一次、故意喂坏内核包验证回滚一次。验收结果回填本文件第 6 节。
2. **无缝切换**：配置加 `experimental.clash_api.external_controller`（仅监听 127.0.0.1）+ secret；CLI 加 `easyproxy node select <region|section>`（走 clash API 切 selector，不重启内核）；LuCI 加切换按钮并显示当前选择；切换失败回滚到原选择。
3. **平台分流可绑定地区 + 测速升级**：`routing.platform_youtube_group` / `platform_netflix_group` / `platform_tiktok_group` 让平台指向具体 `auto-<region>` 组（缺省仍是 `proxy`）；`node test` 增加走真实代理链路的延迟测量（urltest 之外），并在 LuCI 里按延迟排序显示。

## 8. 判定铁律（本文件的读法）

- **测试通过 ≠ 功能实现**：471 项测试证明的是"脚本在这些场景下行为正确"，不证明内核在设备上真的转发流量。
- **内核 IPK 打包成功 ≠ 内核已集成**：`dae_2.1.2_*.ipk` 能装、能 `--version`，但 dae 适配器仍是 `dev`，`easyproxy start` 会拒绝它，运行时分流仍由 sing-box 承担。
- **代码提交 ≠ 新版本发布**：`main` 的 HEAD（`d08a225`）没有对应任何 Release 资产；当前资产来自 `9df452f`。
- **不删除旧版本**：`v0.6.0` 及其资产保留，后续版本只新增。
- 本阶段**不新建 Release**、**不做无关重构**。

## 9. 维护约定

- 每完成一个开发阶段：更新第 3 节完成度表、第 4 节产物表、第 5 节一致性表、第 6 节阶段结论、第 7 节三个任务，然后提交 `main`。
- 报告中的 sha256、提交号、run 号都必须来自本次实测或本次 API 返回，不沿用旧记录。
