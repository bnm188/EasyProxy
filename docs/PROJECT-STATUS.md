# EasyProxy 项目状态（PROJECT-STATUS）

- 最后更新：2026-11-17（UTC+8）
- 更新依据：`docs/reports/005-2026-11-17-acceptance-cleanup.md`（本轮验收遗留清理，代码提交 `f5bf862`…`769f0e6`）；前序 `docs/reports/004-2026-11-17-stage9-p1-fixes-and-release-gate.md`（`4b3ffea`…`1ed6f6e`）；缺陷清单原始来源 `docs/reports/001-2026-11-16-audit.md`（`9a9d94f`）
- 盘点基准：`main@769f0e6261544b5c5a1de1ab34fe3991a7dda46b`（2026-11-17 00:55 +0800）
- 配套文件：`docs/DEVELOPMENT-PLAN.md`（路线与阶段）、`docs/reports/README.md`（报告制度）
- 约定：每完成一个阶段必须更新本文件；**本文件只写有证据的状态**，推断单独标注

---

## 1. 一句话结论

0.6.0 是“能装、能校验、能跑”的可用底座（真实内核接受配置、真实起服、代理端口实测 200、资产 SHA256 全部对上），但**不是完整产品**：唯一 SSH 管理入口不存在、无缝切换没有、10 平台只有 3 个、10 分组只是按名字自动分桶。

Stage 9 之后（2026-11-17）：首个发布链缺口已收口——P1 缺陷 D1/D2/D3 修复、ACL 收窄、下载校验缺失即拒装、升级前备份/磁盘/固件检查与失败回滚、tag-only 且同版本不可覆盖的发布、CI 用真实 sing-box 且 SKIP 计为失败。

本轮验收遗留清理（2026-11-17，报告 005）：D9 从"exec 限 3 个路径"进一步收紧到**只允许 `/usr/sbin/easyproxy` 一个固定入口**（面板不再 `fs.exec('/bin/sh', …)`，流量采样与订阅导入改为 CLI 固定动词 `traffic`/`subscribe`，参数在 CLI 内校验），新增权限边界与越权注入回归；测试计数改为唯一来源 `tests/run-all.sh`（12 套件**实测 574 通过 / 0 失败 / 0 SKIP**，未覆盖项单列）；发布制度补齐版本号递增、真 Release、IPK + SHA256 门槛、中文三节说明、保留最新 20 个并清理最旧。

**仍未解决**：无 `easyproxy-manager.sh`、无无缝切换、平台与分组未落地、dae 只有框架、真机 0 台；Stage 9 判**部分完成**（未用正式 tag 走通端到端发布、每套件用例数下限未做）。

需求对照结论：**满足 6 / 部分 7 / 未满足 3**（16 项为验收基准，逐条见审计报告第 3 节与本文件第 3 节）。

---

## 2. 代码与发布现状

| 检查项 | 实测 |
|---|---|
| 代码规模 | 62 文件；shell 7 853 行、JS 1 020 行；**149 提交**（`main@769f0e6`，报告 005 提交后为 63 文件） |
| 最大单文件 | `scripts/install.sh` **1 136 行** |
| HEAD | `769f0e6261544b5c5a1de1ab34fe3991a7dda46b`（2026-11-17 00:55 +0800） |
| tag `v0.6.0` | `68f9ddd`，落后 HEAD **92 个提交**（`git rev-list --count v0.6.0..HEAD`） |
| Release | `v0.6.0`，id 446714911，`prerelease=false`、**`immutable=false`**，发布 07:19:13Z，最后更新 13:55:44Z（本轮**未改动**、未打新 tag） |
| 资产 | 12 项：3×sing-box、3×dae、2×ipk、1×apk、1×rootfs、`SHA256SUMS`、`KERNEL-VERSIONS` |
| 资产性质 | **历史事实**：审计时点（22:2x）之前每次 push `main` 由 CI 用 `--clobber` 重建覆盖；`f4f8c93` 起 workflow 改为 tag-only、同版本重复发布直接失败，`main` 不再重建 Release 资产 |
| 资产校验（审计时点实测） | 4 包 + `KERNEL-VERSIONS` 全部 `OK`；`SHA256SUMS` 共 11 条 |
| 资产可变实证（审计时点） | 同一 `v0.6.0` 资产：作者 21:50 记录 x86_64 ipk 48.8 KB / rootfs 48.1 KB；22:2x 实测 51 064 B / 50 335 B —— 同一 URL 不同时点字节不同 |
| 是否有未提交改动 | 无（代码、报告与文档均直接落在 `main`） |

---

## 3. 16 项需求完成度

| 判定 | 需求 |
|---|---|
| **满足（6）** | #9 配置备份恢复、#11 国内直连锁死 + 内网绕过、#12 升级回滚兼容磁盘（Stage 9：升级前配置备份 + 磁盘/固件检查 + 面板包失败回滚，**沙箱验证**）、#14 CI/测试报告/发布（Stage 9：真内核 check、SKIP 计失败、tag-only）、#15 不覆盖旧版本（Stage 9：同版本重复发布直接失败）、#16 分阶段推进不重复造轮子 |
| **部分（7）** | #1 一键安装（校验缺失即拒装已补，仍无统一入口）、#2 10 分组、#4 测速优选、#6 内核切换（dae 已挡在面板外，仍无切换能力）、#7 节点/订阅导入、#8 订阅管理页、#13 测试体系（12 套件 574 项，每套件用例数下限未做） |
| **未满足（3）** | #3 10 平台分流、#5 无缝切换、#10 唯一 SSH 入口 `easyproxy-manager.sh`（实测 404） |

口径说明：#12 #14 #15 的上调只看本次有证据的部分（沙箱测试 / CI run #123 / workflow 逻辑），真机与 Release 现状的缺口写在第 8、9 节，不并入“满足”。

---

## 4. 模块完成度

状态：**可用** = 实跑有证据；**部分** = 主链可用有缺口；**框架** = 接口在能力不在；**未实现** = 无。

| # | 模块 | 状态 | 证据 | 缺口 |
|---|---|---|---|---|
| 1 | LuCI 中文面板（10 页） | 部分 | 10 视图 + 874 行 `app.js`，数据全走 `easyproxy <cmd> --json` | D1/D2 已修（报告 004）；dae 入口已挡（D3）；面板不再 `exec /bin/sh`、ACL 只放行固定 CLI（报告 005）；无节点编辑表单；ACL 收窄未在真实 rpcd 渲染 |
| 2 | sing-box 内核 | 可用 | 真内核 `check` 通过、起服、socks5/http 代理实测 200 | tproxy 真机转发未验证；小 flash 空间未测 |
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
| 12 套测试（Linux + dash + python3，`main@769f0e6` 的克隆；唯一计数来源 `tests/run-all.sh`） | **574 通过 / 0 失败 / 0 SKIP**（cli 21 / engine 45 / install-scripts 126 / ipk-layout 40 / maintenance 44 / nodes 61 / regressions 31 / routing 32 / runtime 20 / release 36 / security 33 / transparent 85） |
| 真实 `sing-box 1.10.7` 校验 | routing 第 32 行 `PASS 真实 sing-box check 通过（含 dns 与 rule_set）`（内核只注入 routing/runtime/transparent/engine 四套） |
| 权限边界（静态 + 注入） | security 33 项、regressions 的 D9 断言：ACL 只授予 `/usr/sbin/easyproxy` 的 exec，`/bin/sh`、通配符、`/etc/config` 直接写、`list` 均被拒；CLI 对网卡名/URL/前缀做校验；**真实 rpcd 渲染未验证**（环境无 rpcd） |
| CI（GitHub Actions） | run **#123**（`1ed6f6e`）**success**，2m 12s，无 error 注释；run #116~#122 全部 **failed**（原因：内核路径被写进 `$GITHUB_ENV`，安装套件跳过下载，已修）；本轮 `769f0e6` 的 run 在本次盘点时**仍在运行**（步骤 1–4 success，第 5 步 `Run package test suites with the real kernel` 于 16:56:47Z 开始、未结束） |
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
| R1 | `0.6.0` 资产可变：原每次 push `main` 用 `--clobber` 重建覆盖，`immutable=false` | 同一版本号不同时点字节不同、外部 pin 的 sha 立即失效、无法复现 | **机制已修**（`f4f8c93`：tag-only、已发布即失败）；已存在的 `v0.6.0` 本身 `immutable=false`，本轮未改动 |
| R2 | tag `68f9ddd` ≠ 资产构建提交（原 `0f3c1c35`，当时差 64 提交；现 tag 落后 HEAD 92 提交） | 从 tag 源码构建得不到对应资产 | **机制已修**：新版本只会由 tag 构建并发布，`main` 只出 artifact；历史 `v0.6.0` 仍不一致（未重做） |
| R3 | 测试门禁不校验套件完整性（历史上有套件被截断仍绿灯） | 可能“少测而通过” | **部分**：`tests/run-all.sh` 只累加各套件自打印的 `结果：N 通过，M 失败`，缺套件/无结果行/退出码与失败数矛盾/出现 `SKIP` 都判失败，并单列“未覆盖的验证面”；**每套件用例数下限未做** |
| R4 | 同一 URL 的 CDN 边缘会回旧对象 | 安装器可能拿到旧包 | 已有“校验失败重下 3 次”兜住；根因在 CDN |
| R5 | 安装说明仍写旧手动流程 | 误导用户 | 随后续阶段文档统一 |
| R6 | 无真机验收记录 | 透明抓包/升级回滚/LuCI 全部只在 stub 与沙箱验证 | 最后阶段（设备到位后） |
| R7 | 本地离线包副本过期（旧 `SHA256SUMS` 仅 4 条） | 离线装到旧版本且无内核 | 以 Release 为唯一发包源 |
| R8 | “保留最新 20 个 Release”只在脚本与测试里验证过 | 真删时可能误删在用稳定版 | `scripts/release-gc.sh`：草稿不删且不计数 → 最新不删 → 有下载记录不删 → `--protect`（本次发布的 tag）不删 → 超限才删，且“保护优先、允许超限”，计划先打印再执行；**本轮未发新版本，删除逻辑尚未真实跑过** |

---

## 9. 当前阶段判定

- **代码阶段**：Stage 1~6 能力已落地；Stage 7（编译/安装/升级/卸载）已完成安装 + 内核回滚 + 校验链，Stage 9 补上**面板包回滚、升级前配置备份、磁盘/固件检查**；本轮把 LuCI 越权面从“执行 `/bin/sh`”收窄到**只允许固定 CLI 入口**；**统一入口 `easyproxy-manager.sh` 仍未存在**。
- **文档阶段**：Stage 8（报告制度与状态/路线基线）于 2026-11-16 建立；报告 001~005 已连号提交；`PROJECT-STATUS` 与 `DEVELOPMENT-PLAN` 的 Stage 9 口径已统一（均为“部分完成，待确认”）。
- **验证阶段**：Dev 级完成（12 套件 574 项 + 真内核 check + 端到端起服 + CI run #123 绿）；**真机 0 台**；ACL 只在静态断言与 JSON 解析层验证，**未在真实 rpcd 渲染**。
- **发布阶段**：机制已改为 tag-only 且同版本不可覆盖，本轮再补“版本号必须递增、真建 Release、IPK + SHA256 门槛、中文三节说明、保留最新 20 并清理最旧”；历史 `v0.6.0` Release 仍 `immutable=false`、tag 与资产不一致，未重做，所以仍不能算“可复现正式版本”。
- **阶段判定**：**Stage 9 = 部分完成（待确认）**。缺口：未用正式 tag 走通一次端到端发布、每套件用例数下限未做、真机 0 台。
- **结论**：**0.6.0 = 可用底座 + 未完成产品**。需求 #3 #5 #10 属“没开始”，不是“做了一半”。

---

## 10. 下一步三件事

1. **确认 Stage 9 收口**：报告 005 与本文件第 9 节即收口材料；确认后再动第二阶段。本轮到此停止，等独立验收。
2. **Stage 10**：`easyproxy-manager.sh`（唯一入口、下载即用的中文菜单）；同时补 R3 每套件用例数下限、D4（hysteria2/tuic `tls=1`）、D10（配置 0600）、D14（装完可用）。
3. **Stage 11 + 12**：`clash_api` 无缝切换（含失败回滚）；再往后是十个业务分组与真实 dae。

---

## 11. 判定铁律

- **测试通过 ≠ 功能实现**：574 项证明脚本在 stub/沙箱场景下行为正确，不证明内核在设备上转发流量。
- **ACL 静态断言 ≠ 权限已生效**：security 套件读的是 ACL JSON 与 `app.js` 源码，真实 rpcd 渲染与授权后的实际调用未在设备上验证。
- **内核 IPK 打包成功 ≠ 内核已集成**：dae 能装能 `version`，但适配器是 `dev`，`start` 拒绝（面板已禁止选中）。
- **CI 一次绿 ≠ 发布链正确**：Stage 9 的 CI 前 7 次都是红的，红的原因是本阶段自己引入的缺陷；绿的那一次才算证据。
- **代码提交 ≠ 新版本发布**：`main` 上的提交只产出 artifact，Release 只能由 `v*` tag 创建且同版本不可覆盖。
- **没有产物 ≠ 已交付**：报告里没写清产物位置与校验的，视为未交付。
- **不删除旧版本**：历史 tag/Release/报告一律保留，只新增。

---

## 12. 维护约定

- 每完成一个阶段：更新第 2/4/7/8/9 节，并写该阶段报告（`docs/reports/NNN-…`）。
- 报告与状态文档里的 SHA、行号、字节数必须来自本次实测或本次 API 返回。
- 易变数据不固化，改记“抓取时间 + 当时结果”。
- 阶段收口后**等待确认**再进入下一阶段。
