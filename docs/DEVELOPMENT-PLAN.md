# EasyProxy 开发路线（DEVELOPMENT-PLAN）

- 最后更新：2026-11-16 23:10（UTC+8）
- 依据：2026-11-16 全量审计（`docs/reports/001-2026-11-16-audit.md`）与 `docs/PROJECT-STATUS.md`
- 纪律：一次只做一个阶段；阶段完成写报告、更新状态、**等待确认**后再进入下一阶段

---

## 1. 阶段的定义

- 一个阶段 = 一组可独立验收的能力，必须同时有：代码 + 测试 + 报告 + 状态更新。
- 阶段 DoD（完成定义）统一为：
  1. 功能代码合并到 `main`
  2. 对应测试实跑并留下结果（失败的也留）
  3. 该阶段报告 `docs/reports/NNN-…md` 已提交
  4. `docs/PROJECT-STATUS.md` 已更新
  5. 若涉及发布：产物可在 Release/Artifacts 取到且有校验
- 未满足任一条 → 该阶段状态写“部分完成”，不得写“完成”。

---

## 2. 已完成阶段（Stage 1~7）

| 阶段 | 内容 | 状态 | 证据 | 缺口 |
|---|---|---|---|---|
| Stage 1 | 受保护核心骨架：UCI 配置与校验、CLI status/validate、init 集成、dae/sing-box 适配器接口 | 完成 | 代码 + 测试 | — |
| Stage 2 | sing-box 运行时适配：配置生成、启动、真实 `check` | 完成 | 真实内核 check 通过、起服 | 真机转发未验 |
| Stage 3 | LuCI 面板与 CLI 数据层（`--json`） | 完成 | 10 视图 + 858 行 `app.js` | 未真机渲染 |
| Stage 4 | 分流与 DNS：三平台规则、CN 直连锁死、DNS 分流 | 完成 | `test-routing.sh` 32 项 | 仅 3/10 平台 |
| Stage 5 | 透明抓包（TPROXY）：nft 表、ip rule、可逆回滚 | 完成（沙箱） | `test-transparent.sh` 84→85 项 | 真机未验 |
| Stage 6 | 维护能力：备份恢复、诊断、日志、规则集更新 | 完成 | `test-maintenance.sh` 44 项 | — |
| Stage 7 | 编译/安装/升级/卸载：三组件、ipk/apk/rootfs、SHA256、内核回滚 | 部分完成 | 471 项测试、真实资产端到端 `EXIT=0` | 面板回滚、升级前备份、磁盘/兼容检查、统一入口 |

> Stage 7 判“部分完成”的原因：安装与内核回滚已验；**面板包升级失败无回滚、升级前不备份配置、无磁盘空间与固件兼容检查、无唯一管理入口**，四项均在审计中实测缺失。

---

## 3. 当前阶段：Stage 8 · 文档与报告制度

- 目标：建立 `docs/reports/` 连续编号报告制度、`docs/DEVELOPMENT-PLAN.md`、`docs/PROJECT-STATUS.md` 三件套，并让历史报告（001 审计）符合编号规则。
- 交付：`docs/reports/README.md`（制度 + 模板 + 索引）、`docs/reports/001-…`（审计归档）、`docs/reports/002-…`（本阶段报告）、状态与路线文档。
- DoD：制度文档可执行（含 14 项必填与真实性约束）、历史报告已编号、状态文档只含实测结论。
- 状态：**已交付，待确认**。

---

## 4. 后续阶段

### Stage 9 · 发布体系合规（P0）

- 目标：发布不可变、可复现，CI 真正校验配置。
- 内容：
  1. `build.yml` 改为 `on: push: tags: v*` 触发发布；`main` 只出 Artifacts，不再发 Release
  2. 移除 `gh release upload --clobber` 与对已存在 tag 的 `release edit`
  3. CI 下载 pinned sing-box，导出 `EP_SING_BOX_BIN`，真实 check 不再 skip（D8）
  4. skip 计为 skip、不计数；套件用例数下限断言（R3）
  5. 上传测试报告文件作为构建产物
  6. 新版本用新 tag；旧 tag/Release 不删除、不覆盖
- 验收：推一个 `main` 后 Release 无变化；打 `v0.7.0` tag 后资产与 tag 提交一致、`SHA256SUMS` 覆盖全部资产；CI 日志出现“真实 sing-box check 通过”；Artifacts 里有测试报告。
- 风险：修改发布流程后首个 tag 发布可能不顺，需预演一次 prerelease。

### Stage 10 · 唯一管理入口（P0）

- 目标：`easyproxy-manager.sh` 成为唯一 SSH 入口，9 项菜单。
- 内容：安装/重装、升级、卸载、状态、诊断、内核管理、配置备份恢复、规则集更新、面板入口。
- 约束：一脚本可在 `sh` 下运行；所有危险操作二次确认；与现有 `install.sh`/`uninstall.sh`/`maint.sh` 复用而非重写。
- 验收：路由器上 `sh easyproxy-manager.sh` 九个菜单项均可用；每项调用后状态正确；`docs/reports` 有报告。

### Stage 11 · 无缝切换（P0）

- 目标：换节点/换分组不重启内核、断流 < 1 s。
- 内容：sing-box 开 `experimental.clash_api.external_controller`（127.0.0.1 + secret）；CLI `node select`/`group select` 走 API；LuCI 切换按钮与当前选择显示；失败回滚。
- 验收：切换期间持续 `curl` 不中断超过 1 次；`sing-box` PID 不变；切换失败自动回滚。

### Stage 12 · 平台分流 10 个 + 可绑组（P0）

- 目标：10 个平台卡片，每个可指向具体 `auto-<region>` 组。
- 内容：补齐 ChatGPT/Disney+/Google/Telegram/游戏/全局等；`routing.platform_<name>_group`；移除硬编码 `10.10.10.10`。
- 验收：10 个开关逐一开启后配置 `check` 通过，规则顺序仍在 CN 规则集之前。

### Stage 13 · 测速升级 + 订阅管理（P1）

- 目标：测速能反映代理链路质量；订阅可多份、定时、看流量/到期。
- 内容：按协议探测（QUIC 走内核）；可选带宽测试；结果回写排序；多订阅 + cron 刷新 + 到期/流量展示。
- 验收：hysteria2/tuic 节点不再误报；定时任务在重启后仍生效。

### Stage 14 · P1/P2 缺陷修复（P0/P1）

- 目标：清掉审计里会直接影响用户的缺陷。
- 内容：D1（`traffic.sh` `${10}`）、D2（`errCard`）、D3（dae 拦截）、D4（TLS 强制）、D5（校验硬失败）、D7（升级备份/磁盘/兼容）、D9（ACL 收窄）、D10（配置 0600）；补 `traffic.sh` 输出断言与 JS 静态检查。
- 验收：每个缺陷有对应测试用例，修复前失败、修复后通过（报告里两段结果都留）。

### Stage 15 · 真机验收与稳定化（P0）

- 目标：至少一台 x86_64、一台 ARM 真机验收。
- 内容：按 `docs/router-install-test.md` Step 0–8，覆盖 `--ipk`/`--apk`/`--rootfs`、`install.sh upgrade`、坏内核回滚、tproxy 实际转发、LuCI 渲染。
- 验收：验收清单逐项打勾并附命令输出；失败项进报告遗留问题。

### Stage 16 · dae 决策（P2）

- 目标：dae 要么真正可用，要么正式下线（不留在“装但不用”的状态）。
- 内容：评估 dae 配置生成成本；若不做，则安装器不再默认装 dae，文档与 UI 去掉相关入口。
- 验收：决策记录进报告，代码与文档口径一致。

---

## 5. 顺序与依赖

```
Stage 9（发布合规）
   └─> Stage 10（唯一入口）
         └─> Stage 11（无缝切换）
               └─> Stage 12（10 平台）
                     └─> Stage 13（测速/订阅）
Stage 14（缺陷修复）可与 10/11 并行，但必须早于 Stage 15
Stage 15（真机验收）依赖 9~14 全部落地
Stage 16（dae 决策）在 15 之后
```

理由：发布不合规时，任何“新版本”都不可复现，后续阶段做了也无法交付；唯一入口与无缝切换是用户直接感知的两个硬需求；真机验收必须放在功能稳定之后，否则反复返工。

---

## 6. 阶段确认流程

1. 阶段代码与测试完成 → 提交代码，拿到 SHA
2. 写该阶段报告（`docs/reports/NNN-…md`），提交
3. 更新 `docs/PROJECT-STATUS.md`（完成度/证据/风险/阶段判定），提交
4. 向用户汇报：做了什么、证据是什么、没做到什么
5. **等待确认**；未确认不开始下一阶段
