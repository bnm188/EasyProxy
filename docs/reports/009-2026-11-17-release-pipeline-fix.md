# 009 · 发布流程修复：为什么以前只跑 Actions 不发 Release（2026-11-17）

- 任务目标：用户本轮明确要求"以后每个独立开发任务必须有明确的版本交付"——编译安装包、生成 SHA256、用未使用过的新版本号、打 Tag、**真正创建 GitHub Release** 并上传 IPK/SHA256/说明、写 `docs/reports/` 报告、最后实查 Releases 页面确认版本/Tag/资产/下载地址有效。先查清"为什么以前经常跳过 Publish GitHub Release"并修好自动发布流程，再继续 Kwrt x86_64 安装兼容性修复，最后交付真实 Release。
- 对应阶段：Stage 9（发布体系合规）
- 执行环境：vm（Linux/Bash），工作树 `/tmp/ep11-check`，基线 `main@31c4ecf`
- 声明口径：全部结论来自本次实跑的沙箱测试、实查的 Actions/Release 页面与实下的 Release 资产；**真机未验**

---

## 1. 结论先行：发布被跳过的三层原因

| 层 | 原因 | 证据 |
|---|---|---|
| 触发层 | 发布步骤的门是 `if: startsWith(github.ref, 'refs/tags/v')`，只有 `v*` tag 触发才发布；日常开发推的是 `main`，所以每次构建都只产出 Artifact | 旧 `build.yml` 的发布/清理步骤 gate；run #159（`31c4ecf`）success 但无 Release |
| 令牌层 | Actions 内的 `GITHUB_TOKEN` **不能**推 tag/提交去触发新的工作流（GitHub 防递归），也**不能**派发带输入的 `workflow_dispatch`：`gh workflow run build.yml -f version=0.8.0` 返回 `HTTP 422: Unexpected inputs provided: ["version"]`，因为当时的工作流还没有这个 input | 见第 3 节，run 43952447831 的失败日志（通过 Issue 取回） |
| 权限层 | `GITHUB_TOKEN` 推送的提交**修改了 `.github/workflows/*`**（`build.yml`）时，GitHub 直接拒绝：`refusing to allow a GitHub App to create or update workflow .github/workflows/build.yml without workflows permission` | 同上，issue #6/#7 的日志正文 |

一句话：**"Actions 成功 ≠ Release 成功"不是流程不严，而是这条发布路径在架构上就走不到终点**——tag 没人推、令牌不能自己派发、令牌改不了工作流文件。所以以前每次都是"跑完 Actions、留下 Artifact、然后结束"。

## 2. 修法：把"发布意图"从 tag 唯一来源改成三路统一

`build.yml` 新增 `Resolve the release intent`（`id: intent`）步骤，一次性解析出 `TAG`，之后发布、发布后自检、清理三步**共用同一个 `steps.intent.outputs.tag`**：

1. 手工 push 的 `v*` tag → `TAG=$GITHUB_REF_NAME`；
2. 手动 `workflow_dispatch` 且给了 `inputs.version` → `TAG=v<inputs.version>`；
3. 仓库里存在 `.release-request` 文件 → `TAG=v<文件内容>`。

第 3 条是关键：**连接器 `push_files` 是以 bnm188 身份推送的真实 push，会真正触发 `build.yml`**（run #159 已证明），而 `GITHUB_TOKEN` 的推送不会。所以自动化发布改用"提交一个 `.release-request` 标记文件"来请求发布，绕开"令牌不能派发、不能打 tag"这两个死结。

同时新增 `Verify the published release and its download links`：`gh release view` 回查 tag/非 draft/资产数/必需资产，`gh release download` 把资产实下后 `sha256sum -c SHA256SUMS`，再对每个资产用 `curl -fIL` 打 `https://github.com/<repo>/releases/download/<tag>/<name>` 断言 200。发布后自检失败 = 任务失败，不再出现"说发了其实没发"。

## 3. 三次真实失败的留证（不删、不改写成成功）

| # | 动作 | 结果 | 原因（取自日志） |
|---|---|---|---|
| 1 | 一次性工作流 `rel009-fix-once.yml`（`31c4ecf`） | run 43952447831 **failure**，且 main 未产生新提交 | 推 tag/改工作流的令牌权限问题与派发问题并存；当时匿名读不到日志，本轮用"工作流把日志写进 Issue"的方式补齐证据 |
| 2 | 诊断工作流 `diag9.yml`（`112fb85`） | success；issue #6 正文 | `git push` 可用（`4f88f30..0949907`）；`gh workflow run build.yml -f version=0.8.0` → **HTTP 422 `Unexpected inputs provided: ["version"]`** |
| 3 | 一次性工作流 `c1once.yml`（`112fb85`） | run failure；issue #7 正文 | 补丁 7 文件 **clean apply**、提交成功，但 `git push` 被拒：**`refusing to allow a GitHub App to create or update workflow .github/workflows/build.yml without workflows permission`** |
| 4 | 代码半区一次性工作流 `p1once.yml`（`02179c3`） | success，落地 `83493fe` | 该补丁**不含任何 `.github/workflows/*`**，因此令牌推送合法 → 证明"令牌能推普通文件、不能推工作流文件" |

失败的 run 没有被删除，也没有被描述成成功；`rel009-fix-once.yml`、`diag9.yml`、`c1once.yml` 三个一次性工作流随后由 `p1once` 之外的路径清理（见第 5 节）。

## 4. 版本号与备份修复（与发布同批交付）

| 文件 | 修改 |
|---|---|
| `package/easyproxy/Makefile` | `PKG_VERSION:=` 0.7.0 → **0.8.0**（0.6.0/0.7.0 已发布，0.8.0 未使用过） |
| `package/easyproxy/files/usr/lib/easyproxy/common.sh` | `EP_VERSION="0.7.0"` → **`"0.8.0"`** |
| `scripts/install.sh` | `backup_config()` 不再把 tar 归档直接写进被归档的 `$STATE/backup`：先写 `$STATE/../.ep-backup-$stamp.tar.gz`、`--exclude="$dir"`、再 `mv` 进 backup 目录 |
| `tests/test-cli.sh` | 期望版本同步为 0.8.0 |
| `tests/test-regressions.sh` | 新增断言"备份归档可读，且里面真的有 UCI 配置" |
| `tests/test-release.sh` | 新增 9 条发布流程断言（统一发布意图、`.release-request`、tag 仍可发布、手动版本号、回查 Release、下载资产、SHA256SUMS 校验、`curl -fIL` 逐资产、不留 `continue-on-error`） |

`backup_config()` 的修复依据是**一次真实失败**：全量跑时 `test-regressions` 出现 `FAIL 升级前把 UCI 配置打包备份`（日志 `/tmp/rel009-logs/test-regressions.log` 第 50 行，目录里只剩 `package-*.tar.gz`），判断是 tar 在被写入的目录内部归档自身触发 `file changed as we read it` 退出 1。**必须如实说明**：该修复没有干净的"红→绿"证据——新加的归档完整性断言在修复前后都通过（旧代码只是偶发失败），所以这条改动属于"由失败日志驱动的加固"，不是被新测试逼出来的修复。

## 5. 执行了哪些测试、实际结果

| 时点 | 命令 | 结果 |
|---|---|---|
| 修 `build.yml` 断言前 | `sh tests/test-release.sh` | 4 项红（手动触发、必须给版本号、下载资产、逐资产校验） |
| 改完 gate 后 | `sh tests/test-release.sh` | 43 通过 / 0 失败 |
| gate 改成 intent 后（旧 build.yml 存在时） | `test-release` / `test-regressions` | **38 通过 / 7 失败**、46/1——这些都是"工作流文件尚未落地"导致的预期红，落地后转绿（见下） |
| 最终全量 | `EP_SING_BOX_BIN=… sh tests/run-all.sh` | **601 通过 / 0 失败 / 0 SKIP**（cli 21 / engine 45 / install-scripts 126 / ipk-layout 40 / maintenance 44 / nodes 61 / regressions 47 / routing 32 / runtime 20 / release 45 / security 33 / transparent 87） |
| 备份修复复跑 | `sh tests/test-regressions.sh` ×5 | 47 通过 / 0 失败（5/5） |
| 补丁落地前校验 | 在 `main@0949907` 的干净树 `git apply` | 7 文件 clean apply；`build.yml` 与本地 `sha256 6545a6f7…` 一致；该树全量 **601 通过 / 0 失败** |

未覆盖（套件无法覆盖，必须写明）：真机安装/升级/回滚、真实 rpcd 渲染 ACL、shellcheck（环境未安装）。

## 6. 编译与产物

- 编译由 CI 在 `ubuntu-24.04` + ImmortalWrt 25.12.2 SDK 内完成（`make package/easyproxy/compile`），本轮本地**未**编译包；编译成功与否以 CI 结论为准，见第 7 节。
- 产物口径：EasyProxy apk + 2×ipk（`all`、`x86_64`）+ rootfs.tar.gz、3 架构 sing-box 1.14.4 ipk、3 架构 dae 2.1.2 ipk、`SHA256SUMS`、`KERNEL-VERSIONS`。

## 7. Release（实查结果，2026-11-17 05:31–05:34 +0800）

| 项 | 实测值 |
|---|---|
| Release 页 | `https://github.com/bnm188/EasyProxy/releases/tag/v0.8.0`（标题 `Release EasyProxy 0.8.0 · bnm188/EasyProxy`） |
| Tag | `v0.8.0` → **`e7840ab6b234a9639c76c2a9ba9a693a38374889`**（= 创建时的 `main` HEAD，`gh release create --target $GITHUB_SHA` 写入） |
| 资产 | **12 项**：`easyproxy_0.8.0-1_all.ipk`、`easyproxy_0.8.0-1_x86_64.ipk`、`easyproxy-0.8.0-r1.apk`、`easyproxy-0.8.0-rootfs.tar.gz`、`sing-box_1.14.4_{x86_64,aarch64_cortex-a53,arm_cortex-a7_neon-vfpv4}.ipk`、`dae_2.1.2_{同三架构}.ipk`、`SHA256SUMS`、`KERNEL-VERSIONS` |
| 资产实下校验 | 12 个文件全部从 Release URL 下载到 `/tmp/v080`，`sha256sum -c SHA256SUMS` → **11/11 OK**（`SHA256SUMS` 自身不在清单内） |
| 下载地址 | 直链返回 302 后跟随为 200；工作流里的 `curl -fIL` 逐资产断言 200（该步骤在 #165 内通过） |
| 中文说明 | 三节齐全（修复了什么问题 / 修改了什么功能 / 优化了什么内容），由 `scripts/release-notes.sh` 按 `v0.7.0..HEAD` 的提交生成 |
| 发布执行 | `main` 的 push 触发 `build.yml`（run **#165**，id `43960800316`，提交 `e7840ab`）→ 测试关 → 构建 → 发布 → **发布后自检**（回查 + 实下 + SHA256 + 逐资产 200）→ 清理；job conclusion **success** |
| 失败留证 | run **#163**（`8bcec5d`）failure：`release-notes: range v0.7.0..HEAD has no commit`（`actions/checkout` 默认 1 层历史，`v0.7.0..HEAD` 为空）；run **#164**（`cd0ee71`，诊断推送）failure：同一原因（当时 `build.yml` 还是浅取历史版本）。两次失败均未删改，修复是给 checkout 加 `fetch-depth: 0` + `fetch-tags: true`（提交 `e7840ab`），并在 `tests/test-release.sh` 补断言 |
| 旧版本 | `v0.6.0`、`v0.7.0` 未动、未覆盖、未删除 |

发布后的 `KERNEL-VERSIONS`（实下逐字）：

```
component   version   upstream
easyproxy   0.8.0     https://github.com/bnm188/EasyProxy
sing-box    1.14.4     SagerNet/sing-box v1.14.4
dae         2.1.2     daeuniverse/dae v2.1.2

architectures: x86_64, aarch64_cortex-a53, arm_cortex-a7_neon-vfpv4
kernel adapter: dae 适配器开发中，运行时分流仍由 sing-box 承担
built from commit: e7840ab6b234a9639c76c2a9ba9a693a38374889
built from ref: main
```

## 8. 本次提交

| 提交 | 内容 |
|---|---|
| `83493fe` | 代码半区：`PKG_VERSION`/`EP_VERSION` → 0.8.0、`backup_config()` 修复、三套测试同步（由一次性工作流 `p1once` 推送，因为令牌不能改工作流文件） |
| `8bcec5d` | `build.yml` 发布意图三路统一 + 发布后自检 + 清理 gate 同步；新增 `.release-request`（内容 `0.8.0`） |
| `e7840ab` | `build.yml` checkout 改全历史（`fetch-depth: 0`/`fetch-tags: true`），修 #163/#164 的说明为空 |
| 中间提交 | `112fb85`（`rel009-fix-once`，失败留证）、`4f88f30`/`0949907`（`diag9` 探针，日志见 issue #6）、`02179c3`（`c1once`，失败日志见 issue #7）、`cd0ee71`（`logs9`，取回 #163 失败日志） |

一次性工作流与其 Issue 记录：issue #6（推送/派发探测）、#7（补丁推送被 workflows 权限拒绝的原始日志）、#9（#163 的 release-notes 失败日志）。这些临时工作流随后由连接器删除，不留在 `main`。

## 9. 遗留问题（不粉饰）

1. **发布路径依赖"真实 push"**：自动化要发布，必须由持有 workflows 权限的身份推一个 `.release-request` 提交；`GITHUB_TOKEN` 自己既不能派发带输入的工作流，也不能改 `build.yml`。这是 GitHub 的硬约束，没有被绕过，只被换成了可行的路径。
2. **`.release-request` 不会自动消失**：发布后它仍留在仓库里，下一次 `main` 构建会以"version already released"直接失败。本轮由文档提交顺带删除；后续版本应当在发布成功后自动清理（需要令牌能推工作流外的文件 + 一次提交），**未实现**。
3. **并发构建会互撞**：`build.yml` 没有 concurrency group，同一时间多个 `main` push 会并行构建；两个带 `v0.8.0` 意图的 run 同时跑时，后完成的一个会因"已发布"失败（本轮 #164/#165 即如此，虽 #164 是另一个原因）。**未修**。
4. **发布说明被中间提交污染**：`v0.8.0` 的"优化了什么内容"里出现了 `one-shot workflow…`、`chore(diag): probe` 这类过程提交——说明按提交生成，真实但不美观。后续应加过滤规则（`chore(`/`chore:` 前缀不进说明）**未实现**。
5. **真机未验**：本轮没有在真实 Kwrt / ImmortalWrt 设备上安装 0.8.0；Kwrt x86_64 的用户侧安装兼容性在本轮仍只做到"识别与拦截逻辑正确 + 沙箱测试"。
6. `test-security` 的 traffic 断言既有竞态未修；`v0.7.0` tag 树内仍留 `runlog.txt`；dae 适配器仍不可用。
7. shellcheck 仍因环境未安装而未跑；真实 rpcd 渲染 ACL 未验。

## 10. 下一步计划

1. 落实第 9 节第 2、3、4 条：发布成功后自动清理 `.release-request`（或改成"发布记录文件"只认未发布的版本）、给 `build.yml` 加 `concurrency`、给 `release-notes.sh` 加过程提交过滤。
2. 回到 Kwrt x86_64 安装兼容性：在真实 Kwrt x86_64 上跑一次 `install.sh`（用户设备），确认 IPK 架构/依赖/LuCI 路径；不兼容版本给出更具体的原因提示。
3. 后续每个独立开发任务按本轮确立的流程交付：改代码 → 测试 → 编译 → SHA256 → 新版本号 → Tag → 真 Release → 报告 → 实查 Releases 页面。
