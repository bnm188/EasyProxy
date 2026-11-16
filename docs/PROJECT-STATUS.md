# EasyProxy 项目状态（PROJECT-STATUS）

- 最后更新：2026-11-17（UTC+8，随报告 008 更新）
- 更新依据：`docs/reports/008-2026-11-17-kwrt-firmware-compat.md`（Kwrt 固件识别修复，提交 `5b84c2b`）；前序 `007`（0.7.0 发布后复核）、`006`（0.7.0 正式发布，构建提交 `4863cd7`）、`005`（验收遗留清理）、`004`（Stage 9 P1 修复与发布门禁）；缺陷清单原始来源 `001`
- 盘点基准：`main@4863cd7bdadfef2cc9e55465eeece838283546c0`（2026-11-17 02:09 +0800，即 Release `v0.7.0` 的构建提交）
- 配套文件：`docs/DEVELOPMENT-PLAN.md`（路线与阶段）、`docs/reports/README.md`（报告制度）
- 约定：每完成一个阶段必须更新本文件；**本文件只写有证据的状态**，推断单独标注

---

## 1. 一句话结论

0.7.0 是“能装、能校验、能跑”的可用底座（内核已升到 sing-box 1.14.4，并首次真实发布）（真实内核接受配置、真实起服、代理端口实测 200、资产 SHA256 全部对上），但**不是完整产品**：唯一 SSH 管理入口不存在、无缝切换没有、10 平台只有 3 个、10 分组只是按名字自动分桶。

Stage 9 之后（2026-11-17）：首个发布链缺口已收口——P1 缺陷 D1/D2/D3 修复、ACL 收窄、下载校验缺失即拒装、升级前备份/磁盘/固件检查与失败回滚、tag-only 且同版本不可覆盖的发布、CI 用真实 sing-box 且 SKIP 计为失败。

本轮验收遗留清理（2026-11-17，报告 005）：D9 从"exec 限 3 个路径"进一步收紧到**只允许 `/usr/sbin/easyproxy` 一个固定入口**（面板不再 `fs.exec('/bin/sh', …)`，流量采样与订阅导入改为 CLI 固定动词 `traffic`/`subscribe`，参数在 CLI 内校验），新增权限边界与越权注入回归；测试计数改为唯一来源 `tests/run-all.sh`（12 套件**实测 574 通过 / 0 失败 / 0 SKIP**，未覆盖项单列）；发布制度补齐版本号递增、真 Release、IPK + SHA256 门槛、中文三节说明、保留最新 20 个并清理最旧。

本轮正式发版（2026-11-17，报告 006）：sing-box 从 1.10.7 升到 **1.14.4**（`SagerNet/sing-box` 最新非 prerelease，`2026-10-24T01:04:25Z`），按 1.14 新 schema 改写 `dns.servers`、补 `route.default_domain_resolver`、清掉 tproxy 入站被 1.13 删除的三个字段并把 `sniff` 改成路由动作、直连 DNS 不再写 `detour`；dae 复核最新仍为 **2.1.2** 保持不变；`PKG_VERSION=0.7.0`，**真实创建 Release `v0.7.0`**（id 447407341），12 项资产从 Release 实下后逐个复核，**11/11 SHA256 通过**。

本轮安装器兼容性修复（2026-11-17，报告 008）：从 Kwrt 官方镜像实下 rootfs 取证（`DISTRIB_ID='Kwrt'`、`DISTRIB_RELEASE='25.12-SNAPSHOT'`、**无 `VERSION_ID`**、包管理器仍是 `opkg`）后，把 Kwrt 纳入安装器固件识别：基线 ≥21.02 放行，<21.02 与版本无法解析都明确拒绝并给理由，未知固件仍拦截；同时补 LuCI 缺失提示与“该架构没有内核包”提示。测试 578 → **591 项**（`tests/run-all.sh` 实测 591 通过 / 0 失败），沙箱验证，**真机未验**（用户报错的 Kwrt 设备未参与实测）。

**仍未解决**：无 `easyproxy-manager.sh`、无无缝切换、平台与分组未落地、dae 只有框架、真机 0 台；每套件用例数下限未做。Stage 9 本轮判**完成**（发布端到端已真实走通；欠一条：`build.yml` 的 tag 原生发布路径未实跑，见报告 006 遗留问题 1）。

需求对照结论：**满足 6 / 部分 7 / 未满足 3**（16 项为验收基准，逐条见审计报告第 3 节与本文件第 3 节）。

---

## 2. 代码与发布现状

| 检查项 | 实测 |
|---|---|
| 代码规模 | 报告 005 时点 63 文件、shell 7 853 行、JS 1 020 行；`0.7.0` 改动为 11 文件 +140/−50 行，**行数未重新统计**（不沿用旧数当现值） |
| 最大单文件 | `scripts/install.sh` **1 136 行** |
| HEAD | `4863cd7bdadfef2cc9e55465eeece838283546c0`（2026-11-17 02:09 +0800，构建提交；其后仅删除一次性发布文件与文档提交） |
| 版本号 | `PKG_VERSION:=0.7.0` / `PKG_RELEASE 1`；`EP_VERSION=0.7.0` |
| tag `v0.7.0` | 由 `gh release create --target 4863cd7…` 创建，**指向构建提交**（R2 对本版本成立） |
| 历史 tag `v0.6.0` | `68f9ddd`，与资产构建提交不一致（历史遗留，未重做） |
| Release `v0.7.0` | id 447407341，`draft=false`、`prerelease=false`、作者 `github-actions[bot]`，发布 `2026-11-16T18:09:55Z`（=11-17 02:09:55 +0800）；12 项资产 |
| 历史 Release `v0.6.0` | id 446714911，07:19:13Z 发布；`immutable=false`；**本轮未动**（未删、未改、未覆盖） |
| 资产（`v0.7.0`） | 12 项：3×sing-box 1.14.4、3×dae 2.1.2、2×ipk、1×apk、1×rootfs、`SHA256SUMS`、`KERNEL-VERSIONS` |
| 资产性质 | **历史事实**：审计时点（22:2x）之前每次 push `main` 由 CI 用 `--clobber` 重建覆盖；`f4f8c93` 起 workflow 改为 tag-only、同版本重复发布直接失败，`main` 不再重建 Release 资产 |
| 资产校验（`v0.7.0`，11-17 02:13–02:14 +0800 实下） | `sha256sum -c SHA256SUMS` **11/11 OK**；`sing-box_1.14.4_x86_64.ipk` 解包后二进制自报 `sing-box version 1.14.4`（`go1.26.10 linux/amd64`） |
| 资产可变实证（审计时点） | 同一 `v0.6.0` 资产：作者 21:50 记录 x86_64 ipk 48.8 KB / rootfs 48.1 KB；22:2x 实测 51 064 B / 50 335 B —— 同一 URL 不同时点字节不同 |
| 是否有未提交改动 | 无（代码、报告与文档均直接落在 `main`） |

---

## 3. 16 项需求完成度

| 判定 | 需求 |
|---|---|
| **满足（6）** | #9 配置备份恢复、#11 国内直连锁死 + 内网绕过、#12 升级回滚兼容磁盘（Stage 9：升级前配置备份 + 磁盘/固件检查 + 面板包失败回滚，**沙箱验证**）、#14 CI/测试报告/发布（Stage 9：真内核 check、SKIP 计失败、tag-only）、#15 不覆盖旧版本（Stage 9：同版本重复发布直接失败）、#16 分阶段推进不重复造轮子 |
| **部分（7）** | #1 一键安装（校验缺失即拒装已补，仍无统一入口）、#2 10 分组、#4 测速优选、#6 内核切换（dae 已挡在面板外，仍无切换能力）、#7 节点/订阅导入、#8 订阅管理页、#13 测试体系（12 套件 591 项，每套件用例数下限未做） |
| **未满足（3）** | #3 10 平台分流、#5 无缝切换、#10 唯一 SSH 入口 `easyproxy-manager.sh`（实测 404） |

口径说明：#12 #14 #15 的上调只看本次有证据的部分（沙箱测试 / CI run #123 / workflow 逻辑），真机与 Release 现状的缺口写在第 8、9 节，不并入“满足”。

---

## 4. 模块完成度

状态：**可用** = 实跑有证据；**部分** = 主链可用有缺口；**框架** = 接口在能力不在；**未实现** = 无。

| # | 模块 | 状态 | 证据 | 缺口 |
|---|---|---|---|---|
| 1 | LuCI 中文面板（10 页） | 部分 | 10 视图 + 874 行 `app.js`，数据全走 `easyproxy <cmd> --json` | D1/D2 已修（报告 004）；dae 入口已挡（D3）；面板不再 `exec /bin/sh`、ACL 只放行固定 CLI（报告 005）；无节点编辑表单；ACL 收窄未在真实 rpcd 渲染 |
| 2 | sing-box 内核 | 可用 | **1.14.4** 真内核 `check` 通过、起服、socks5/http 代理实测 204 | tproxy 真机转发未验证；小 flash 空间未测 |
| 3 | dae 内核 | 框架 | 6 动词齐全但 `dae_run` 返回 2，`start` 拒绝 | 无配置生成/运行时分流；面板已 disabled 且保存即拒绝（D3 已修）；18.4 MB 白装 |
| 4 | 节点管理 | 可用 | 7 种分享链接、导入/批量/导出/删除、失败定位 | 无编辑；README 声称的 ssr 不支持（D12）；无到期/流量 |
| 5 | 智能分组 | 部分 | 地区分桶（hk/tw/jp/sg/us/uk/de/kr/ru/other）+ 每桶 `urltest` + `selector` | 动态桶非固定 10 组；无权重、无手动归组、无按组测速、无选组 UI |
| 6 | 平台分流 | 部分（3/10） | youtube/netflix/tiktok 内联域名 → `proxy`，仅 split 生效时下发 | 缺 7 个平台、不能绑地区组、无卡片页 |
| 7 | 测速与优选 | 部分 | 内核 `urltest`（5m/50ms）+ `node test` TCP 握手 | 无带宽/丢包/稳定性；UDP 协议必然误报（D13） |
| 8 | 无缝切换 | 未实现 | 无 `clash_api`/`external_controller`、无 `node select`、无切换按钮 | 换节点必断流 |
| 9 | DNS 分流 | 可用 | `dns-local`(223.5.5.5/direct)、`dns-remote`(DoH/proxy)、私网→`.cn`→final | 无 DoH 超时回退实测、无泄漏检测 |
| 10 | 国内直连锁死 | 可用 | validate/`config generate` 双拒绝 `china_policy=proxy`；`fail_closed=1` | 无（按设计锁死） |
| 11 | 内网绕过 | 可用 | bypass 集合含 `10.0.0.0/8`、`10.10.10.10/32`、路由器自身/LAN；`ip_is_private` 直连；节点 /32 防环 | 真机 nft set 未核对 |
| 12 | 安装/升级/卸载 | 部分 | 三组件、ipk/apk/rootfs 三模式、架构自适应、SHA256（缺失即拒装）、坏包重试、内核备份回滚；Stage 9 补：安装/升级前磁盘检查、固件兼容检查、升级前 UCI 配置备份、面板包失败快照回滚 | 无统一入口；磁盘/兼容/回滚只在沙箱验证，真机未验 |

---

## 5. 三条安全锁（逐条复核仍在代码里）

1. `china_policy=proxy` 被 `config.sh` 拒绝 → 中国大陆永远直连，没有开关能绕过。
2. `fail_closed=1` → CN 规则集缺失时生成纯直连配置并返回非 0，绝不退化成全局代理。
3. 内网直连：`10.10.10.10`、`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、路由器本机与 LAN 全部在 bypass/direct，LAN 流量不进内核。

---

## 6. 已实测证据

| 证据 | 结果 |
|---|---|
| 12 套测试（Linux + dash + python3，`main@e7827ee` 的克隆 + 报告 008 改动；唯一计数来源 `tests/run-all.sh`） | **591 通过 / 0 失败 / 0 SKIP**（cli 21 / engine 45 / install-scripts 126 / ipk-layout 40 / maintenance 44 / nodes 61 / regressions 46 / routing 32 / runtime 20 / release 36 / security 33 / transparent 87） |
| 真实 `sing-box 1.14.4` 校验 + 起服 | routing 真实内核 check 通过（含 dns 与 rule_set）；沙箱起服后 `curl -x http://127.0.0.1:7890 http://www.gstatic.com/generate_204` 返回 **204**（沙箱需把 `cache_file` 覆写到 `/tmp`，D11 未修） |
| 权限边界（静态 + 注入） | security 33 项、regressions 的 D9 断言：ACL 只授予 `/usr/sbin/easyproxy` 的 exec，`/bin/sh`、通配符、`/etc/config` 直接写、`list` 均被拒；CLI 对网卡名/URL/前缀做校验；**真实 rpcd 渲染未验证**（环境无 rpcd） |
| CI（GitHub Actions） | run #123（`1ed6f6e`）success；发布通道前 4 次失败各有留证（日志丢失 / 补丁应用 / `GITHUB_TOKEN` 无 workflows 权限 / sed 转义），第 5 次由 `4863cd7` 触发**成功并产出 Release `v0.7.0`**（18:09:55Z）；该次 run 的 ID 与日志正文未取到（`api.github.com` 直连 403 rate limit、Actions 日志需登录），不假称读过日志 |
| 端到端起服 | `Engine validation: passed` → `sing-box started (0.11s)` → socks5/http 代理均 HTTP 200 |
| 资产校验 | 4 包 + `KERNEL-VERSIONS` OK（审计时点） |
| 真机 | **0 台**，tproxy 转发/nft/LuCI 渲染/opkg 安装/升级回滚均未验 |
| shellcheck | **未跑**（环境无该工具，CI 也无） |

---

## 7. 已知代码缺陷（详见审计报告第 6 节，均带复现）

| 编号 | 级别 | 位置 | 影响 | 状态 |
|---|---|---|---|---|
| D1 | P1 | `traffic.sh:24` 原 `tx="$10"` | POSIX 展开成 `lo0`，总览发送速率恒坏 | **已修复**（`4b3ffea`，`tx="${10}"`，回归断言 D1） |
| D2 | P1 | `app.js:266` 原调 `herrCard`（只有 `errCard`） | 状态读取失败时抛 ReferenceError，错误卡片不显示 | **已修复**（`f5774ba`，改用 `errCard`） |
| D3 | P1 | `app.js:544-556` 原允许存 dae 到 `main.engine` | 保存后 generate/start 拒绝，一键把可用服务变不可用 | **已修复**（`f5774ba`，option disabled + `saveEngine` 拦截） |
| D4 | P2 | `config.sh:108-120` hysteria2/tuic 手写节点缺 `tls=1` | 整份配置生成失败（链接导入路径正常） | 未修复 |
| D5 | P2 | `install.sh:299-320` 原校验缺失即 `return 0` | 未校验安装，与声明冲突 | **已修复**（`e9ca749`，三条路径改 `die … unverified`） |
| D6 | P2 | `build.yml:171-225` 原 `--clobber` 覆盖同 tag | 发布不可复现 | **已修复**（`f4f8c93`，tag-only + 已发布即失败 + 无 `--clobber`） |
| D7 | P2 | `install.sh:851-958` | 无升级前备份、无磁盘/兼容检查、面板包无回滚 | **已修复**（`e9ca749`，沙箱验证） |
| D8 | P2 | `test-routing.sh:230` | CI 跳过真实内核校验却计为通过 | **已修复**（`2feefb5` + `f4f8c93`：SKIP 文案 + CI 门禁） |
| D9 | P2 | ACL `ubus file exec` 全量放开 | 委派账号可执行任意命令 | **已修复（两步）**（`4b3ffea` 先收窄到 3 个路径并去掉 `list`；`f5bf862`+`faedfae` 进一步只放行 `/usr/sbin/easyproxy`，`/bin/sh` 显式拒绝） |
| D10 | P3 | 配置 0644 | 节点密码/UUID 可被本机其他用户读取 | 未修复 |
| D11 | P3 | 自定义 `cache_file` 目录不建 | 内核启动 FATAL（默认路径不触发） | 未修复 |
| D12 | P3 | 原 README 称支持 `ssr://` | 实测 `unsupported share link scheme: ssr` | 文档已修正（报告 003），**代码仍无 ssr** |
| D13 | P3 | `node test` 仅 TCP 探测 | hysteria2/tuic 必然 unreachable | 未修复 |
| D14 | P3 | 默认 `enabled=0`、无节点 | 装完不可用，需三步手工 | 未修复 |
| D15 | P3 | 无 `easyproxy-manager.sh` | HTTP 404，唯一入口缺失 | 未修复（第二阶段） |
| D16 | P4 | 无 lint、1 136 行安装器、文档阶段口径不一 | 可维护性/一致性 | **部分**：`docs/DEVELOPMENT-PLAN.md` 与本节口径已统一（报告 005）；无 lint 工具、安装器未拆分 |
| D17 | P1 | `app.js` 原 `fs.exec('/bin/sh', ...)`：流量采样带网卡名、订阅导入带 url 与前缀 | 任何持有 LuCI ACL 的普通用户可借通用 shell 执行任意系统命令（参数未校验） | **已修复**（`f5bf862` 面板不再调 `/bin/sh`；`8b26259` 新增 CLI 固定动词 `traffic`/`subscribe` 并在 CLI 内校验网卡名/协议/前缀；`faedfae` ACL 只放行 `/usr/sbin/easyproxy`，`subscribe.sh` 另做 http(s) 协议校验）；**真实 rpcd 渲染未验证** |

---

## 8. 发布与工程风险

| 编号 | 问题 | 影响 | 状态与处理方向 |
|---|---|---|---|
| R1 | `0.6.0` 资产可变：原每次 push `main` 用 `--clobber` 重建覆盖，`immutable=false` | 同一版本号不同时点字节不同、外部 pin 的 sha 立即失效、无法复现 | **机制已修且本轮实证**：`v0.7.0` 由一次构建产出、`gh release create` 一次性写入，未覆盖任何已有资产；`v0.6.0` 保持原样（历史 `immutable=false` 无法回填） |
| R2 | tag 与资产构建提交不一致 | 从 tag 源码构建得不到对应资产 | **本版本已闭合**：`v0.7.0` 的 tag 指向构建提交 `4863cd7`（`KERNEL-VERSIONS` 内也记了同一 SHA）；历史 `v0.6.0` 仍不一致（未重做）。**欠一条**：`build.yml`「打 tag 就自己发布」的原生路径本轮未实跑（发布由一次性工作流 `gh release create --target` 完成） |
| R3 | 测试门禁不校验套件完整性（历史上有套件被截断仍绿灯） | 可能“少测而通过” | **部分**：`tests/run-all.sh` 只累加各套件自打印的 `结果：N 通过，M 失败`，缺套件/无结果行/退出码与失败数矛盾/出现 `SKIP` 都判失败，并单列“未覆盖的验证面”；**每套件用例数下限未做** |
| R4 | 同一 URL 的 CDN 边缘会回旧对象 | 安装器可能拿到旧包 | 已有“校验失败重下 3 次”兜住；根因在 CDN |
| R5 | 安装说明仍写旧手动流程 | 误导用户 | 随后续阶段文档统一 |
| R6 | 无真机验收记录 | 透明抓包/升级回滚/LuCI 全部只在 stub 与沙箱验证 | 最后阶段（设备到位后） |
| R7 | 本地离线包副本过期（旧 `SHA256SUMS` 仅 4 条） | 离线装到旧版本且无内核 | 以 Release 为唯一发包源 |
| R8 | 「保留最新 20 个 Release」 | 真删时可能误删在用稳定版 | 本轮发布后 `release-gc.sh --keep 20 --protect v0.7.0` **真实跑过一次**：现只有 2 个 Release，规划为 0 行 DELETE，未删任何东西；真正的删除路径仍未被数据触发，所以仍算「验证过逻辑、未验证过删除」 |

---

## 9. 当前阶段判定

- **代码阶段**：Stage 1~6 能力已落地；Stage 7（编译/安装/升级/卸载）已完成安装 + 内核回滚 + 校验链，Stage 9 补上**面板包回滚、升级前配置备份、磁盘/固件检查**；本轮把 LuCI 越权面从“执行 `/bin/sh`”收窄到**只允许固定 CLI 入口**；**统一入口 `easyproxy-manager.sh` 仍未存在**。
- **文档阶段**：Stage 8（报告制度与状态/路线基线）于 2026-11-16 建立；报告 001~005 已连号提交；`PROJECT-STATUS` 与 `DEVELOPMENT-PLAN` 的 Stage 9 口径已统一（均为“部分完成，待确认”）。
- **验证阶段**：Dev 级完成（12 套件 574 项 + 真内核 check + 端到端起服 + CI run #123 绿）；**真机 0 台**；ACL 只在静态断言与 JSON 解析层验证，**未在真实 rpcd 渲染**。
- **发布阶段**：**已端到端走通一次**——`0.7.0` 由 CI 真实构建、真实创建 GitHub Release `v0.7.0`，资产含 2 个 EasyProxy ipk + apk + rootfs + 3×sing-box 1.14.4 ipk + 3×dae 2.1.2 ipk + `SHA256SUMS` + `KERNEL-VERSIONS`，本地实下复核 11/11 通过；中文说明三节齐全。历史 `v0.6.0` 的 `immutable=false` 与 tag 不一致属历史事实，不回填、不重做。
- **阶段判定**：**Stage 9 = 完成（待 ChatGPT 独立验收）**。DoD 五条全部满足（代码合并、测试实跑留证 578/0/0、报告 006 已提交、状态文档已更新、产物可在 Release 取到且有校验）；欠项单列：`build.yml` 的 tag 原生发布路径未实跑、R3 每套件用例数下限未做、真机 0 台。
- **结论**：**0.7.0 = 可用底座 + 未完成产品**（内核已升级并首次真实发布）。需求 #3 #5 #10 属“没开始”，不是“做了一半”。

---

## 10. 下一步三件事

1. **确认 Stage 9 收口**：报告 006 与本文件第 9 节即收口材料；确认后再动第二阶段。本轮到此停止，等 ChatGPT 独立验收。
2. **下一次发版改回原生路径**：`git tag v0.x.y` + push tag，让 `build.yml` 自己的 tag 分支完成构建与发布（本轮用一次性工作流绕过了这一段）。
3. **Stage 10**：`easyproxy-manager.sh`（唯一入口、下载即用的中文菜单）；同时补 R3 每套件用例数下限、D4（hysteria2/tuic `tls=1`）、D10（配置 0600）、D14（装完可用）。
4. **Stage 11 + 12**：`clash_api` 无缝切换（含失败回滚）；再往后是十个业务分组与真实 dae。

---

## 11. 判定铁律

- **测试通过 ≠ 功能实现**：591 项证明脚本在 stub/沙箱场景下行为正确，不证明内核在设备上转发流量，也不证明安装器在真实 Kwrt 设备上装成功。
- **ACL 静态断言 ≠ 权限已生效**：security 套件读的是 ACL JSON 与 `app.js` 源码，真实 rpcd 渲染与授权后的实际调用未在设备上验证。
- **内核 IPK 打包成功 ≠ 内核已集成**：dae 能装能 `version`，但适配器是 `dev`，`start` 拒绝（面板已禁止选中）。
- **CI 一次绿 ≠ 发布链正确**：Stage 9 的 CI 前 7 次都是红的，红的原因是本阶段自己引入的缺陷；绿的那一次才算证据。
- **代码提交 ≠ 新版本发布**：`main` 上的提交只产出 artifact；`v0.7.0` 是 `gh release create --target` 建的一次性对象，同版本不可覆盖。
- **有 Release ≠ 发布路径已验**：本轮的 Release 不是 `build.yml` 的 tag 分支产出的，那条路仍未实跑。
- **没有产物 ≠ 已交付**：报告里没写清产物位置与校验的，视为未交付。
- **不删除旧版本**：历史 tag/Release/报告一律保留，只新增。

---

## 12. 维护约定

- 每完成一个阶段：更新第 2/4/7/8/9 节，并写该阶段报告（`docs/reports/NNN-…`）。
- 报告与状态文档里的 SHA、行号、字节数必须来自本次实测或本次 API 返回。
- 易变数据不固化，改记“抓取时间 + 当时结果”。
- 阶段收口后**等待确认**再进入下一阶段。
