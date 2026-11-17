# 007 · 0.7.0 发布后独立复核与勘误（2026-11-17）

- 任务目标：对已发布的 `v0.7.0` 做**不依赖 Actions Artifact 的独立复核**——从 Release 重新下载全部资产并自算 SHA256、校验包内二进制、在干净树上复跑全量测试、核对 CI 与 Release 元数据；同时清理发布过程中误入 `main` 的残留文件，并对报告 006 的一处事实性错误出具勘误。
- 对应阶段：Stage 9（发布体系合规）——发布后的独立复核，不改变阶段判定
- 开始/结束时间：2026-11-17 02:50–03:00（UTC+8）
- 复核基准：`main@75d1e928c9199372b8ccf349c6e61dc9aa3c66ce`（本轮改动前），Release `v0.7.0`（id 447407341），tag `v0.7.0` → `4863cd7bdadfef2cc9e55465eeece838283546c0`
- 执行限制：不改动已发布资产、不移动 tag、不覆盖任何历史报告、不做无证据的声明

---

## 1. 修改的文件及路径

| # | 文件 | 变更类型 | 说明 |
|---|---|---|---|
| 1 | `runlog.txt` | **删除** | 发布脚本误入 `main` 的 4 行运行日志（删除提交 `a8e5c4e`） |
| 2 | `docs/reports/007-2026-11-17-post-release-verification.md` | 新增 | 本报告 |
| 3 | `docs/reports/README.md` | 修改 | 第 7 节索引追加 007 行 |
| 4 | `docs/reports/006-2026-11-17-release-0.7.0.md` | 修改 | 头部追加一行勘误指向（按报告制度第 1 节“写错了就追加勘误并在原报告头部加一行指向勘误”） |
| 5 | `.github/workflows/docs-070-once.yml` | **删除** | 已用尽的一次性文档工作流（自检“docs already applied”后立即退出），删除提交 `df3cf02` |

本轮**没有改动任何代码、配置、构建脚本**，因此不产生代码提交；第 1、5 项删除提交属于仓库清理，不是功能变更。

## 2. 每个文件的具体修改

### 2.1 `runlog.txt`（删除）

- 改前：仓库根目录存在 4 行文本（`[1/9] guard`、`[2/9] download the reviewed patch`、`/tmp/release.patch: OK`、`[3/9] apply the patch and commit`），由一次性发布脚本 `tee` 写入，随提交 `1518343923fd4f454206d45a965a4faf1158b626` 进入 `main`。
- 改后：从 `main` 删除（提交 `a8e5c4e3795b6c6def781a2f3d84a1d07accf3d1`）。
- 为什么改：它是运行日志，不属于源码或文档；报告 006 第 1 节第 11 行与第 5 节已写明“临时误入后已删除”，但实际未删，文件与报告口径冲突，必须让仓库实际状态追上书面口径。

### 2.2 `docs/reports/README.md`（追加索引行）

- 改前：索引表最后一行是 006。
- 改后：追加 007 行，注明“发布后独立复核 + `runlog.txt` 清理 + 006 勘误”，代码提交列写 `a8e5c4e`。
- 为什么改：报告制度第 2 节要求每份报告在同一提交内补索引行。

### 2.3 `docs/reports/006-…release-0.7.0.md`（头部追加勘误指向）

- 改前：标题行后直接进入正文元信息，没有勘误指向。
- 改后：标题行下追加一条引用块`> **勘误（2026-11-17，报告 007）**：…`，指向本报告。
- 为什么改：报告制度第 1 节明确要求；006 正文的历史记录保持原样（不改写旧结论、不删失败记录）。
- 做法：为避免整篇重打引入差异，本次由一个一次性工作流在仓库内用脚本在指定行插入该行并自删（提交 `cbd54a9` 推入工作流，提交 `0850a7d` 完成插入与自删），`git diff` 复核结果为 **+2 行 / −29 行（仅工作流删除）**。

### 2.4 `.github/workflows/docs-070-once.yml`（删除）

- 改前：一次性文档补丁工作流，`on: push: branches: [main]`，脚本开头判 `docs/reports/006…md` 已存在即 `exit 0`。
- 改后：删除（提交 `df3cf02`）。
- 为什么改：它的用途（把 006 与 0.7.0 口径文档推上 `main`）已经完成，留在仓库里会让每次 push 都无谓启动一次空转 job，属发布通道残留。

## 3. 新增功能

- 无新增功能。本轮为复核与清理，不改变产品行为。

## 4. 未实现 / 仍缺的功能

- **dae 适配器仍未可用**：`dae_run` 返回 2、`start` 拒绝，面板已禁用；`dae_2.1.2_*.ipk` 只是内核包，不代表引擎可用。
- **`build.yml` 的“打 tag 自动发布”原生路径仍未实跑**：0.7.0 的 Release 由一次性受控工作流调用 `gh release create --target` 创建（见 006 第 10 节遗留 1），本轮同样未跑。
- `easyproxy-manager.sh` 唯一 SSH 入口、无缝切换、10 平台分流、真机验收全部未做（Stage 10/11/12/15）。
- 测试未覆盖面不变：真机安装/升级/回滚、真实 rpcd 渲染 ACL、shellcheck（环境未安装）。

## 5. 删除的文件及理由

| 文件 | 理由 |
|---|---|
| `runlog.txt` | 一次性发布脚本的运行日志，误入 `main`；非源码、非文档，留在仓库根目录会污染 `git ls-files`，且与 006 的书面口径矛盾。删除提交 `a8e5c4e`。 |
| `.github/workflows/docs-070-once.yml` | 一次性文档补丁工作流，用途已完成且自检即退出；留着只会空转。删除提交 `df3cf02`。 |

`v0.6.0` 与 `v0.7.0` 的 Release、tag、资产**一个都没有动**（只读复核）。

## 6. 执行的测试

| 套件/命令 | 环境 | 结果 | 关键输出 |
|---|---|---|---|
| 全量：`EP_SING_BOX_BIN=/tmp/kb/sing-box-1.14.4-linux-amd64/sing-box EP_TEST_LOG_DIR=/tmp/rel-verify sh tests/run-all.sh` | vm（Linux + dash + python3），干净树 `main@75d1e92` | **578 通过 / 0 失败 / 0 SKIP**（退出码 0） | cli 21 / engine 45 / install-scripts 126 / ipk-layout 40 / maintenance 44 / nodes 61 / regressions 33 / routing 32 / runtime 20 / release 36 / security 33 / transparent 87 |
| `sha256sum -c SHA256SUMS`（对 12 项从 Release 实下后的文件） | vm | **11/11 OK** | 见第 8 节表 |
| 内核包内二进制自检 | vm | 通过 | 解 `sing-box_1.14.4_x86_64.ipk` 得 `/usr/bin/sing-box`，执行 `version` 输出 `sing-box version 1.14.4`、`Environment: go1.26.10 linux/amd64`、`Revision: c005f35300ce76427dc285481ec5695f5b179cd2` |
| EasyProxy 包内版本自检 | vm | 通过 | 解 `easyproxy_0.7.0-1_x86_64.ipk`，`usr/lib/easyproxy/common.sh` 内 `EP_VERSION="0.7.0"` |
| Release 元数据核对 | GitHub API / 页面 | 通过 | 见第 8 节；仓库共 2 个 Release（`v0.7.0`、`v0.6.0`），均 `draft=false`、`prerelease=false` |
| CI 结论核对 | GitHub Actions 页面/API | 部分 | `4863cd7` 的 run 43925535711 结论 success（步骤除 Publish/Prune 外全部 success）；`daefd54` 的 run 43927482796 success；badge 现为 `passing`；`144a17a` 的 run 43925433671 为 failure（历史失败，006 已记录）。**未取到日志正文**（Actions 日志需登录，匿名 API 对 runs 详情间歇性限流），因此只断言页面上的结论，不声称读过日志正文 |

> 与 006 的口径差异：006 记录 578 项，本轮复跑同为 578 项，逐套件数字完全一致；本地曾出现过的 584 项来自一份未合并的本地实验（手写 Release Notes 优先分支 + 两条测试），**不属于 0.7.0 已发布代码**，不与发布口径混用。

## 7. 编译结果

- 是否成功：**本轮未编译**（vm 无 OpenWrt SDK，不在本地重建产线）。
- 已发布资产是 CI 构建产物，本轮只做下载后校验，不声称“本地编译通过”。

## 8. 产物（Release `v0.7.0` 复核结果）

- 地址：`https://github.com/bnm188/EasyProxy/releases/tag/v0.7.0`；id `447407341`；名称 `EasyProxy 0.7.0`；`draft=false`、`prerelease=false`；发布 `2026-11-16T18:09:55Z`（= 2026-11-17 02:09:55 +0800）；资产 12 项。
- 下载时间：2026-11-17 02:52–02:55 +0800，全部来自 `https://github.com/bnm188/EasyProxy/releases/download/v0.7.0/<资产名>`。

| 资产 | 字节（本次实下） | 与 006 记录 | `sha256sum -c` |
|---|---|---|---|
| `easyproxy_0.7.0-1_all.ipk` | 53 210 | 一致 | OK |
| `easyproxy_0.7.0-1_x86_64.ipk` | 53 222 | 一致 | OK |
| `easyproxy-0.7.0-r1.apk` | 54 108 | 一致 | OK |
| `easyproxy-0.7.0-rootfs.tar.gz` | 52 420 | 一致 | OK |
| `sing-box_1.14.4_x86_64.ipk` | 27 557 868 | 一致 | OK |
| `sing-box_1.14.4_aarch64_cortex-a53.ipk` | 24 976 226 | 一致 | OK |
| `sing-box_1.14.4_arm_cortex-a7_neon-vfpv4.ipk` | 25 329 540 | 一致 | OK |
| `dae_2.1.2_x86_64.ipk` | 19 287 522 | 一致 | OK |
| `dae_2.1.2_aarch64_cortex-a53.ipk` | 17 858 972 | 一致 | OK |
| `dae_2.1.2_arm_cortex-a7_neon-vfpv4.ipk` | 18 367 586 | 一致 | OK |
| `KERNEL-VERSIONS` | 435 | 一致 | OK |
| `SHA256SUMS` | 1 054 | 一致 | 作为校验源，11 条逐一比对通过 |

`KERNEL-VERSIONS` 原文（本次实下）：

```
component   version   upstream
easyproxy   0.7.0     https://github.com/bnm188/EasyProxy
sing-box    1.14.4     SagerNet/sing-box v1.14.4
dae         2.1.2     daeuniverse/dae v2.1.2

architectures: x86_64, aarch64_cortex-a53, arm_cortex-a7_neon-vfpv4
kernel adapter: dae 适配器开发中，运行时分流仍由 sing-box 承担
built from commit: 4863cd7bdadfef2cc9e55465eeece838283546c0
built from ref: main (one-shot release run)
```

Release 说明正文（`get_release_by_tag` 返回，1 298 字符）确为中文三节：修复了什么问题 / 修改了什么功能 / 优化了什么内容，内容与本次实际变更（1.14 四处不兼容、三架构 SHA、dae 保持 2.1.2 且标注适配器开发中）对应。

## 9. 提交

- 代码提交：**本轮无代码提交**（未改任何代码/配置/构建脚本）。被复核的既有提交：`4863cd7bdadfef2cc9e55465eeece838283546c0`（构建/发布提交）、`75d1e928c9199372b8ccf349c6e61dc9aa3c66ce`（复核基线）。
- 清理提交：`a8e5c4e3795b6c6def781a2f3d84a1d07accf3d1`（删除 `runlog.txt`）、`df3cf0214e4cabff69a5ddf2a534286f0e005ceb`（删除一次性文档工作流）。
- 报告提交：见 GitHub 提交历史（本文即报告，与索引同一提交）。

## 10. 遗留问题

1. **`runlog.txt` 仍存在于 tag `v0.7.0` 指向的树**（`4863cd7`，文件于 `1518343` 引入）。tag 与已发资产不移动、不重写，故该文件在已发布版本的历史树里保留；`main` 上已删除。此项登记在册，不在本版本内修复。
2. **`build.yml` 的 tag 原生发布路径仍未实跑**（继 006 遗留 1）。
3. **CI 证据链仍有缺口**：`v0.7.0` 的发布 run 的日志正文未取到（Actions 日志需登录）；本轮只能引用页面步骤结论（Publish/Prune 为 skipped，其余 success）。
4. **`75d1e92` 未见对应 CI run**（该提交与 `daefd54` 的推送时间仅差 6 秒，可能被合并处理）。不据此判定其通过，状态以 badge（当前 `passing`）与上一条 run 为准。
5. **dae 适配器不可用**、真机 0 台、D4/D11/D12/D13/D14/D15/D16 等既有缺陷仍未修（沿用 001/004/005 记录）。
6. **R3（每套件用例数下限）**、`easyproxy-manager.sh`、无缝切换、10 平台分流未做。

## 11. 下一步计划

- 等 ChatGPT 对 0.7.0 与本复核做独立验收；验收通过前不进入 Stage 10。
- 验收通过后进 Stage 10：`easyproxy-manager.sh` 唯一入口，并顺带补 R3、D4、D10、D14。
- 下一次发版改用“`git tag` + `build.yml` 原生发布”，把本轮用一次性工作流绕过的那条路径跑通，并保留 run ID 与日志正文作为证据。
- 真机到位后按 `docs/router-install-test.md` 做 Stage 15 验收。

## 12. 阶段判定

- Stage 9 的 DoD 五条（见 006 第 12 节）在本轮复核后**仍然满足**，且证据从“报告自述”升级为“第三方路径重下 + 重算 + 重跑”：
  1. 代码在 `main` —— 满足；
  2. 测试实跑留证 —— 满足（本轮 578 通过 / 0 失败 / 0 SKIP，退出码 0）；
  3. 阶段报告已提交 —— 满足（006 + 本勘误 007）；
  4. `PROJECT-STATUS` 已更新 —— 满足（006 同一提交）；
  5. 发布产物可取且有校验 —— 满足（12 项资产、11/11 SHA256 本轮重新复核通过）。
- 本轮不改写 006 的历史结论，只补勘误指向；**Stage 9 状态维持“完成，待独立验收”**。
