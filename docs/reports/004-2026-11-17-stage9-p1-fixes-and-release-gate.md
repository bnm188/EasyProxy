# 004 · 第一阶段（Stage 9）：P1 缺陷修复、ACL 收窄、安装/升级安全与发布门禁（2026-11-17）

- 任务目标：落实第一阶段验收项——修 D1/D2/D3 等 P1 缺陷、收窄 ACL、下载校验缺失时拒装、升级前备份 + 磁盘 + 固件兼容 + 失败回滚、GitHub Actions 同版本 Release 覆盖、CI 必须用真实 sing-box 且跳过不算通过；不跳阶段、不虚报、不发正式稳定版、能修的不重写。
- 对应阶段：Stage 9（见 `docs/DEVELOPMENT-PLAN.md`）
- 开始/结束时间：2026-11-16 23:05 ~ 2026-11-17 00:10（UTC+8）
- 事实基准：`main@1ed6f6e3f5cd5883ca64bdf1903abd424f083b09`（2026-11-17 00:02:18 +0800）

---

## 1. 修改的文件及路径

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `package/easyproxy/files/usr/lib/easyproxy/traffic.sh` | 修改 | D1：`tx="$1" + "0"` → `tx="${10}"`（36 行） |
| `package/easyproxy/files/www/luci-static/resources/easyproxy/app.js` | 修改 | D2 错误卡片 + D3 dae 引擎不可选（870 行） |
| `package/easyproxy/files/usr/share/rpcd/acl.d/luci-app-easyproxy.json` | 修改 | D9：ACL 收窄（31 行） |
| `scripts/install.sh` | 修改 | D5 拒装、D7 备份/磁盘/兼容/回滚（999 → 1136 行） |
| `.github/workflows/build.yml` | 修改 | D6 同版本不覆盖、D8 真内核 + SKIP 门禁（→ 290 行） |
| `tests/test-routing.sh` | 修改 | 跳过真实 check 时输出 `SKIP`，不再计为通过（235 行） |
| `tests/test-regressions.sh` | 新增 | Stage 9 回归套件（313 行，30 项断言） |
| `docs/reports/004-…md`、`docs/reports/README.md`、`docs/PROJECT-STATUS.md` | 新增/修改 | 本报告与索引、项目状态（本次提交） |

---

## 2. 每个文件的具体修改

### `package/easyproxy/files/usr/lib/easyproxy/traffic.sh`

- 改前：`tx="$10"`
- 改后：`tx="${10}"`
- 为什么改：D1。POSIX 下 `$10` 被解析为 `$1` 拼接字面量 `0`，第 10 个参数是网卡名 `lo` 时得到 `lo0`。修复前实测输出 `{"ok":true,"iface":"lo","rx":2221586,"tx":lo0}`（应为 `2221586`），面板“发送速率”恒为坏值。改为 `${10}` 后取到第 10 字段（`/proc/net/dev` 的 tx 列）。

### `package/easyproxy/files/www/luci-static/resources/easyproxy/app.js`

- 改前：总览错误分支调用 `herrCard(...)`（该函数不存在，只有 `errCard`，第 81 行）；内核选择直接写 UCI，dae 可选。
- 改后：错误分支改用 `errCard`；新增顶层 `function saveEngine(pick)`（第 89 行），`pick === 'dae'` 时 `notify('dae 适配器开发中，暂不可选：请继续使用 sing-box', 'error')` 并拒绍保存（第 91 行）；dae 的 `<option>` 带 `disabled: 'disabled'`；保存按钮改为 `return saveEngine(valOf('ep-engine'))`。
- 为什么改：D2 状态读取失败时抛 `ReferenceError`，错误卡片永久不显示（P1）；D3 保存 dae 后 `generate`/`start` 都拒绍，一键把可用服务变不可用（P1）。dae 适配器仍是 `dev`（`dae_run` 返回 2），面板先挡住入口，能力不变。

### `package/easyproxy/files/usr/share/rpcd/acl.d/luci-app-easyproxy.json`

- 改前：`ubus file` 的 `read`/`write` 带 `list` 与 `exec`，exec 覆盖整棵路径。
- 改后：`read` 只留 `ubus file=["read"]` + 路径白名单；只有 `write` 段保留 `exec`，且仅 `/bin/sh`、`/usr/lib/easyproxy/traffic.sh`、`/usr/lib/easyproxy/subscribe.sh`；去掉 `list` 与 `/etc/config/easyproxy` 的 file 写权限（配置写仍走 CLI）。
- 为什么改：D9。原 ACL 等于把“在任意路径执行任意命令”授予委派账号，越权面远超面板实际需要。

### `scripts/install.sh`

- 改前 → 改后（逐处）：
  - `verify_download`（第 299 行起）三处 `return 0` → `die`：无 `sha256sum`（304）、发布没有 `SHA256SUMS`（308）、取不到 `SHA256SUMS`（311）全部 `refusing to install … unverified`；第 314 行补“版本没有校验值也拒装”。
  - 新增 `fetch_pinned`（346 行）：按文件内 pin 的 sha256 校验上游内核归档。
  - 新增 `check_disk_space`（694 行）：`EP_MIN_FREE_KB` 默认 65536 KB，`df -Pk` 检 `$TMP` 与 `$ROOT`，不足即 `die`。
  - 新增 `check_firmware`（714 行）：读 `$ROOT/etc/openwrt_release`，接受 ImmortalWrt/OpenWrt/LEDE 且 ≥ 21.02；`EP_SKIP_COMPAT=1` 放行；文件缺失只 info 不阻断（老固件常见）。
  - 新增 `backup_config`（948 行）：升级前把 UCI 配置打包到 `$STATE/backup/config-<UTC>.tar.gz`。
  - 新增 `snapshot_package`（981）/`restore_package`（997）：按 `$ROOT` 前缀重写 opkg 文件列表后 tar 备份，失败时 `tar -xzf -C /` 还原。
  - `install_package` 的“无合适包管理器”由 `die` 改为 info + `return 1`，`do_install` 用 `install_package || die`；`upgrade_package` 改为 snapshot → install → 失败 restore。
  - `do_install` 开头调 `check_firmware`/`check_disk_space`；`do_upgrade` 在停服务前调三者。
- 为什么改：D5（声明“校验后安装”，实际校验缺失仍继续装）、D7（无升级前备份、无磁盘/兼容检查、面板包无回滚）。只加分支、不改既有主流程；`snapshot_package` 按 `$ROOT` 重写是因为沙箱里 opkg 列表是绝对路径，直接打包会指向真实根目录。

### `.github/workflows/build.yml`

- 改前：push `main` 即用 `gh release upload --clobber` 重建并覆盖 `v0.6.0` 资产，Release 说明每次被 `gh release edit` 重写；CI 不下载真实内核；测试里的跳过没有被拦住。
- 改后：
  - 新增 “Install the pinned sing-box used by the tests”：下载官方 `sing-box-1.10.7-linux-amd64.tar.gz`，`sha256sum -c` 比对 `1951a0785c8b4e1e21e0640227a49528ca772aec3d680061652e3d6b687e00fe`，解包到 `/opt/easyproxy-ci/sing-box` 并 `version` 自检。
  - 测试步骤：内核只注入 routing/runtime/transparent/engine 四套，其余套件用 `env -u EP_SING_BOX_BIN` 运行；失败套件打 `::error` 并 `cat` 全日志；`grep -q '  SKIP  '` 命中即 `::error` 并最终 `exit 1`；日志作为 artifact 上传。
  - 发布步骤：`if: startsWith(github.ref, 'refs/tags/v')`；tag 与 `PKG_VERSION` 必须一致；`gh release view` 已存在则 `::error … is already released` 退出；删掉 `--clobber` 与 `gh release edit`，只保留 `gh release create`。
- 为什么改：D6（同版本号资产可变、不可复现）、D8（跳过被计为通过）、R1/R2（tag 与资产对齐）。CI 必须用真内核，否则“配置检查通过”是桩的结论。

### `tests/test-routing.sh`

- 改前：第 230 行无真内核时静默通过。
- 改后：`say "  SKIP  未提供真实 sing-box（EP_SING_BOX_BIN），真实 check 未执行，不计为通过"`。
- 为什么改：D8。跳过必须是可见的 `SKIP`，且由 CI 判定为失败。

### `tests/test-regressions.sh`（新增）

- 30 项断言，覆盖 D1（tx/rx 与 `/proc/net/dev` 对照）、D2（`herrCard` 不再出现、`errCard` 有定义、`node --check`）、D3（dae option disabled、拦截提示、`saveEngine` 集中保存）、D9（解析 ACL JSON 校验 exec 白名单/无通配/无 config 写）、D5（缺 `SHA256SUMS` 非 0 退出 + 写明 refusing + 未交给 opkg）、D7a（磁盘不足非 0 + 报 disk）、D7b（RandomOS 拒绍、ImmortalWrt 25.12.2 通过）、D7c（配置被备份、失败后 CLI 与库文件回滚）、D6/D8（无 `--clobber`、无 `release edit`、tag-only、重复发布即失败、真内核下载+校验、内核路径交给套件、不泄漏到 `$GITHUB_ENV`、安装类套件 `env -u`、SKIP 即红）。
- 为什么新增：本阶段所有行为都要有可复跑的守卫，且必须先看到失败。

---

## 3. 新增功能

- 安装器：无校验值/无清单/取不到清单 → 拒装；安装与升级前检查剩余磁盘（默认 64 MB）；检查固件家族与版本（`EP_SKIP_COMPAT=1` 可放行）；升级前打包备份 `/etc/config/easyproxy`；面板包升级失败自动回滚到旧文件。
- 安装器：`fetch_pinned` 支持按文件内 pin 的 sha256 校验上游内核归档。
- 面板：dae 入口前置拦截（下拉 disabled + 保存即拒绍并提示），避免把可用服务写入不可用引擎。
- 发布工程：tag-only 发布；同版本重复发布直接失败；CI 用真内核跑配置检查；SKIP 视为失败；测试日志作为 artifact 上传。

## 4. 未实现 / 仍缺的功能

- D4（hysteria2/tuic 手写节点缺 `tls=1`）、D10（配置 0644）、D11（自定义 `cache_file` 目录不建）、D12（代码仍不支持 `ssr://`）、D13（`node test` 仅 TCP 探测）、D14（装完默认不可用）、D16（无 lint）——本阶段未修，保持原状。
- R3 只做到“跳过即红 + 失败即红”，**没有**做 `DEVELOPMENT-PLAN` 里写的“用例数下限”断言。
- ACL 收窄只做了静态断言与 JSON 解析，**未在真实 rpcd/ACL 环境渲染验证**。
- 面板包回滚之外的三个组件（sing-box/dae）回滚沿用既有的内核备份逻辑，本阶段未新增用例。
- 真机 0 台：tproxy/nft 转发、opkg 安装、升级回滚在设备上的行为仍未验收。

## 5. 删除的文件及理由

- 无删除。

## 6. 执行的测试

环境：Linux 云主机，`sh` = dash，python3 可用；真实内核 `/tmp/sing-box-1.10.7-linux-amd64/sing-box`（`sing-box version 1.10.7`，31 797 383 B）。内核只注入 routing/runtime/transparent/engine 四套。

| 套件/命令 | 环境 | 结果 | 关键输出 |
|---|---|---|---|
| `sh tests/test-regressions.sh`（修复前，RED） | 落库版 `641502f` 之后的代码 | **24 失败 / 4 通过** | D1：`期望 2221586，实际 '<无法解析>'，原始输出: {"ok":true,"iface":"lo","rx":2221586,"tx":lo0}`；D6/D8：`FAIL 工作流不再用 --clobber…`、`FAIL CI 把 SKIP 视为失败` |
| `sh tests/test-regressions.sh`（二次 RED，CI 修复前） | `1252a15` 的树 | **28 通过 / 2 失败** | `EP_SING_BOX_BIN 仍被写进 $GITHUB_ENV…`、`没有 env -u EP_SING_BOX_BIN` |
| `EP_SING_BOX_BIN=… sh tests/test-install-scripts.sh`（复现 CI） | 同上 | **15 项 FAIL**（与 CI 注释的 12 项同源） | `FAIL sing-box 落在 usr/bin` … `FAIL dae 失败时 sing-box 未装` |
| `env -u EP_SING_BOX_BIN sh tests/test-install-scripts.sh` | 同上 | 126 通过 / 0 失败 | 证明根因就是全局变量泄漏 |
| 10 套件串跑（`1ed6f6e` 的克隆，最终证据） | Linux 云主机 | **504 通过 / 0 失败 / 0 SKIP** | cli 21、engine 45、install-scripts 126、ipk-layout 40、maintenance 44、nodes 61、regressions 30、routing 32、runtime 20、transparent 85 |
| routing 的真内核断言 | 同上 | PASS | 第 32 行 `PASS  真实 sing-box check 通过（含 dns 与 rule_set）` |
| GitHub Actions run #116~#122（`f4f8c93`…`1252a15`） | GitHub ubuntu-24.04 | **7 次全部 failed** | #122 注释：`failing suites: test-install-scripts.sh`，明细 `FAIL sing-box 落在 usr/bin; FAIL sing-box 从官方 release 下载; …`（1m 6s ~ 1m 39s） |
| GitHub Actions run #123（`1ed6f6e`） | GitHub ubuntu-24.04 | **success**（2m 12s） | 只有 1 条 warning（Node.js 20 deprecated），无 error 注释 |

测试日志位置（本地，未进仓库）：`/tmp/ep9-evidence/red.log`（RED）、`/tmp/ep9-ev3-test-*.log`（`1ed6f6e` 的 10 份最终日志）。CI 侧的日志在每次 run 的 artifact `easyproxy-test-logs`。

## 7. 编译结果

- 是否成功：**成功**（CI run #123）。
- 日志要点：SDK `immortalwrt-sdk-25.12.2` 按 pin 的 sha256 校验通过后，`make package/easyproxy/compile V=s -j2` 成功，后续 `Package manual-install archive`、`Package ipk for opkg-based firmware`、`Build kernel packages`、`Collect packages`、`Write KERNEL-VERSIONS`、`Checksums` 全部执行完毕，job 结论 success。
- 本地未做 SDK 编译（本机无该 SDK 与交叉工具链），编译证据仅来自 CI，不写“本地编译通过”。

## 8. 产物

| 产物 | 大小 | 位置 |
|---|---|---|
| `easyproxy-test-logs`（10 份套件日志） | 未统计 | CI run #123 的 Artifact |
| `easyproxy-immortalwrt-25.12.2`（dist/*：ipk、apk、rootfs、内核包、SHA256SUMS、KERNEL-VERSIONS） | 未统计（每次构建可变） | CI run #123 的 Artifact |
| Release | — | **未发布**：本次提交落在 `main`，发布步骤按 `refs/tags/v` 过滤未触发；`v0.6.0` Release 未改动、未打新 tag |

按制度的判定：产物已在 CI Artifact 可取，但**没有发布新版本**，因此不写“安装包已交付”。

## 9. 提交

本阶段代码提交（`main`，新→旧）：

| SHA | 内容 |
|---|---|
| `1ed6f6e` | CI：内核路径只给四套配置套件，其余 `env -u`；补 2 项回归断言 |
| `1252a15` | `install.sh` 恢复 `#!/bin/sh` |
| `08086d8` | `build.yml` KERNEL-VERSIONS 的 `sed` 恢复单反斜杠 |
| `e9ca749` | D5 + D7（install.sh） |
| `f5774ba` | D2 + D3（app.js） |
| `ef89792` | 新增 `tests/test-regressions.sh` |
| `2feefb5` | routing 跳过改为 `SKIP` |
| `f4f8c93` | D6 + D8 + CI build.yml |
| `4b3ffea` | D1（traffic.sh）+ D9（ACL） |

- 报告提交：见 GitHub 提交历史（本文与索引、状态文档同一次提交）。

## 10. 遗留问题

- **CI 红的历史必须留痕**：`f4f8c93` 起 7 次 run 全红，原因是我把 `EP_SING_BOX_BIN` 写进 `$GITHUB_ENV`，导致安装套件误判内核已存在、跳过下载，12 项断言失败；`1ed6f6e` 才修好。这不是环境问题，是本阶段引入的缺陷。
- `#115`（`4b3ffea`，旧 workflow）为什么是绿的：它没有新内核步骤，不能作为“新 workflow 可用”的证据。
- R3 的“用例数下限”未实现；目前只保证失败与 SKIP 会红，套件被截断仍可能不红。
- ACL 收窄未经真实 rpcd 渲染；`read` 白名单是否覆盖面板所有读路径，需要在设备上验证。
- `v0.6.0` Release 的 `immutable=false` 是仓库设置层面的事实，workflow 改动只阻止“再次覆盖”，不改变已发布资产的现有状态。
- 本阶段未修 D4/D10~D16；未做 shellcheck。
- 真机 0 台。

## 11. 下一步计划

1. 等确认后再进第二阶段：`easyproxy-manager.sh` 唯一入口（下载即可用的中文管理菜单）。
2. 进第二阶段前先补两件低成本的事：R3 的套件数量下限门禁；D4（hysteria2/tuic `tls=1`）与 D14（装完可用）。
3. 真机验收仍排在最后阶段，设备到位前不写“已验证”。

## 12. 阶段判定

本阶段 DoD 逐条：

| DoD 项 | 判定 | 依据 |
|---|---|---|
| 修 D1/D2/D3 等 P1 | **满足** | D1/D2/D3 已修并有回归断言；RED 24 失败 → 全绿 |
| ACL 收窄 | **满足（静态）** | 只读白名单 + exec 仅 3 个路径；未做真机渲染 |
| 下载校验缺失时拒装 | **满足** | 三条路径均 `die` + 断言“未交给 opkg” |
| 升级前备份/磁盘/固件兼容/失败回滚 | **满足（沙箱）** | D7a/D7b/D7c 断言通过；真机未验 |
| Actions 同版本 Release 覆盖 | **满足（工作流层面）** | tag-only + 已发布即失败 + 无 `--clobber`/`release edit`；已存在的 `v0.6.0` 未动 |
| CI 用真实 sing-box、跳过不算通过 | **满足** | run #123 绿；routing 断言 `PASS 真实 sing-box check 通过（含 dns 与 rule_set）`；SKIP 门禁在位 |
| 不虚报、不跳阶段、不发正式稳定版 | **满足** | 未打 tag、未动 Release；CI 7 次红如实记录 |

**结论：Stage 9 的六项验收在代码、测试、CI 三个层面都有证据，判为完成（范围限定为上表写法）；"真机验收" 与 "R3 数量下限" 仍是缺口，进入下一阶段前需先确认。**
