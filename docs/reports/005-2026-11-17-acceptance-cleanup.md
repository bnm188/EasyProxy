# 005 · 004 验收遗留清理：ACL 越权收口、测试计数可信、发布制度补全（2026-11-17）

- 任务目标：只处理 004 验收后发现的问题，不开新大功能——
  1. LuCI/rpcd ACL 越权：`app.js` 仍 `fs.exec('/bin/sh', …)`，要改为专用受限 RPC 或固定功能入口，并排查同类风险、补权限边界与越权测试；
  2. 统一 `docs/PROJECT-STATUS.md` 与 `docs/DEVELOPMENT-PLAN.md` 对 Stage 9 的口径（不做整份重写）；
  3. 加强自动测试可靠性：数量必须来自实际执行，未执行标 SKIP，缺关键测试标未覆盖，并补 ACL / 安装升级回滚 / 国内直连 / 内网绕过的回归；
  4. 完善发布制度：保留自动编译；正式版本必须新版本号 + 新 tag、真建 GitHub Release、提供可下载 IPK 与 SHA256、中文三节说明不留空、正式 Release 最多留最新 20 个并清理最旧 tag 与资产、删除前确认不误删在用稳定版、不许覆盖旧资产；
  5. 提交本报告（不覆盖 004）、记录 Commit SHA 与 Actions 结果、更新两份文档、列出遗留项。
- 对应阶段：Stage 9（发布体系合规）——本报告提交后仍为**部分完成、待确认**
- 时间：2026-11-17（UTC+8）；代码提交区间见第 10 节
- 事实基准：`main@769f0e6261544b5c5a1de1ab34fe3991a7dda46b`（2026-11-17 00:55 +0800）
- 执行限制：不跳阶段、不擅自发布正式稳定版、不覆盖旧报告与旧版本、不把模拟测试说成真机测试

---

## 1. 修改的文件及路径

| # | 文件 | 变更类型 | 说明 |
|---|---|---|---|
| 1 | `package/easyproxy/files/www/luci-static/resources/easyproxy/app.js` | 修改 | 面板不再 `fs.exec('/bin/sh', …)`：流量采样改走 `run(['traffic'])`，订阅导入改走 `run(['subscribe', url, prefix])`（874 行） |
| 2 | `package/easyproxy/files/usr/sbin/easyproxy` | 修改 | 新增固定动词 `traffic` / `subscribe` 与对应校验（1075 行） |
| 3 | `package/easyproxy/files/usr/share/rpcd/acl.d/luci-app-easyproxy.json` | 修改 | write.file 的 exec 只剩 `/usr/sbin/easyproxy`（29 行） |
| 4 | `package/easyproxy/files/usr/lib/easyproxy/subscribe.sh` | 修改 | 收 URL 后先做 `http://` / `https://` 协议校验（73 行） |
| 5 | `.github/workflows/build.yml` | 修改 | 测试改调 `tests/run-all.sh`；发布前校验版本号/tag/资产/说明；新增清理步骤（297 行、16 个业务步骤） |
| 6 | `tests/run-all.sh` | 新增 | 唯一计数来源：遍历 `EXPECTED` 清单，只累加各套件自打印的结果行（117 行） |
| 7 | `tests/test-security.sh` | 新增 | 权限边界 / 越权注入 / 路由锁三组，33 项（321 行） |
| 8 | `tests/test-release.sh` | 新增 | 发布说明生成与保留策略，36 项（198 行） |
| 9 | `tests/test-regressions.sh` | 修改 | D9 断言改为“只允许 `/usr/sbin/easyproxy`”并显式拒绝 `/bin/sh`；三条工作流断言改指 `run-all.sh`，新增一条；30 → 31 项（323 行） |
| 10 | `scripts/release-notes.sh` | 新增 | 从提交生成中文三节说明（76 行） |
| 11 | `scripts/release-gc.sh` | 新增 | 算出“保留/删除”计划，自身不删（114 行） |
| 12 | `docs/DEVELOPMENT-PLAN.md` | 修改 | 第 3 节改为“Stage 9 · 部分完成，待确认”、第 4 节改为 Stage 10 起 |
| 13 | `docs/PROJECT-STATUS.md` | 修改 | 就地改口径：Stage 9 部分完成、574 项/12 套件、D9 两步修复 + 新增 D17、新增 R8 |
| 14 | `docs/reports/005-…md`、`docs/reports/README.md` | 新增 / 修改 | 本报告与索引行（同一个 commit） |

未删除任何文件。

---

## 2. 每个文件的具体修改

### 2.1 `app.js`（越权面）

- 改前（两处）：`fs.exec('/bin/sh', ['/usr/lib/easyproxy/traffic.sh', iface])`、`fs.exec('/bin/sh', ['/usr/lib/easyproxy/subscribe.sh', url, name])` —— LuCI 侧只要 ACL 给了 `/bin/sh` 的 exec，就等于把通用 shell 交给任何持有该 ACL 的会话。
- 改后：`run(['traffic'])` 与 `run(['subscribe', url].concat(name ? [name] : []))`，`run()` 固定执行 `var BIN = '/usr/sbin/easyproxy'`。
- 新增 6–11 行注释，写明“ACL 不能给通用 shell”，避免下次改回去；同时该注释是静态检查要剥离的对象（见 2.6）。

### 2.2 `usr/sbin/easyproxy`（固定入口 + 参数校验）

- `usage()` 增加 `traffic [iface]`、`subscribe <url> [prefix]`。
- 新增 `cmd_traffic()`：网卡名先过 `[A-Za-z0-9_.:-]` 白名单，再调 `EP_TRAFFIC_LIB`（默认 `/usr/lib/easyproxy/traffic.sh`）。
- 新增 `cmd_subscribe()`：只接受 `http://` / `https://`，前缀过 `[A-Za-z0-9_.-]` 白名单，再调 `EP_SUBSCRIBE_LIB`。
- 分发 `case` 增加 `traffic)`、`subscribe)`；未知动词仍 `usage >&2; exit 2`。
- 关键点：CLI 本身是白名单 `case`，无 `eval`、无 `sh -c`，所以“ACL 只给这一个入口”才成立；如果 CLI 有转发任意命令的能力，这个收窄就是假的。

### 2.3 `luci-app-easyproxy.json`（ACL）

- 改前：`write.file` 含 `/bin/sh`、`traffic.sh`、`subscribe.sh` 三条 exec。
- 改后：exec 只剩 `/usr/sbin/easyproxy`；`read` 保留只读白名单（`/etc/config/easyproxy`、`/etc/easyproxy/*`、`/var/log/easyproxy.log`、`/proc/net/dev` 等）；`list` 不再授出。

### 2.4 `subscribe.sh`（纵深防御）

- 取到 `url` 后立即：`case "$url" in http://*|https://*) ;; *) 报错并 exit 2 ;; esac`。
- 理由：即使有人以 root 直接从 shell 调这个脚本，也不能被 `file://` / `gopher://` 之类借 curl 读本地文件或打内网。

### 2.5 `build.yml`（发布制度）

- 测试步骤改为：`EP_SING_BOX_BIN=/opt/easyproxy-ci/sing-box EP_TEST_LOG_DIR=test-logs sh tests/run-all.sh`，不再自己循环跑套件；计数与 SKIP 门禁都交给 `run-all.sh`。
- 发布步骤（`if: startsWith(github.ref, 'refs/tags/v')`）新增硬门槛：
  - tag 必须等于 `v$PKG_VERSION`；
  - `gh release view` 已存在即失败（同版本不可覆盖）；
  - 版本号必须**大于**最新 Release（`sort -V` 比较）；
  - `dist/*.ipk` 必须存在，`dist/SHA256SUMS` 必须存在且逐个 ipk 都被覆盖；
  - 说明必须非空，且“修复了什么问题 / 修改了什么功能 / 优化了什么内容”三节各至少一条 `- ` 条目；
  - `gh release create` 附带 `dist/easyproxy* dist/sing-box_* dist/dae_* dist/SHA256SUMS dist/KERNEL-VERSIONS`。
- 新增独立步骤 `Prune old releases (keep the newest 20)`：拉 `releases?per_page=100` → `release-gc.sh --keep 20 --protect "$GITHUB_REF_NAME"` → 只对 `DELETE` 行执行 `gh release delete --yes` + `git push origin --delete <tag>`，失败打 `::error`。

### 2.6 `tests/run-all.sh`（唯一计数来源）

- 遍历 `EXPECTED` 清单（12 个套件），逐个运行并解析它自己打印的 `结果：N 通过，M 失败`：
  - 没有结果行 → 记“未覆盖”，不计通过；
  - 输出里出现 `  SKIP  ` → 失败；
  - 退出码与失败数矛盾 → 失败。
- 内核注入规则：只有 `test-routing|test-runtime|test-transparent|test-engine` 拿到 `EP_SING_BOX_BIN`，其余 `env -u EP_SING_BOX_BIN`。
- 末尾打印“未覆盖的验证面：真机安装/升级/回滚、真实 rpcd 渲染 ACL、shellcheck（环境未安装）”。

### 2.7 `test-security.sh`（33 项）

- A 组 权限边界：ACL 的 exec 集合必须等于 `/usr/sbin/easyproxy`；不得含 `/bin/sh`、通配符、`/etc/config` 写权限；`list` 不得授出。
- B 组 越权注入：CLI 对网卡名、URL、前缀的非法输入必须拒绝，且**失败原因**必须是对应报错（不是“未知命令也恰好返回 2”）。
- C 组 路由锁：`china_policy=proxy` 仍被拒、`fail_closed` 仍生效、内网 bypass 仍在。

### 2.8 `test-release.sh`（36 项）

- `release-notes.sh`：三节归类（`fix*`/`修复` → 修复了什么问题；`feat*`/`新增` → 修改了什么功能；其余 → 优化了什么内容）、每节最多 8 条、某节为空写“- 本次没有…类改动”、空提交区间直接 exit 1。
- `release-gc.sh`：草稿不删且不计数 → 最新不删 → 有下载记录不删 → `--protect` 不删 → 超限才删；**保护优先、允许超限**。

---

## 3. 新增功能

1. CLI 固定动词 `traffic [iface]`、`subscribe <url> [prefix]`，参数在 CLI 内白名单校验。
2. 聚合测试运行器 `tests/run-all.sh`：唯一计数来源 + SKIP 即失败 + 未覆盖清单。
3. 安全套件 `tests/test-security.sh`（33 项）、发布套件 `tests/test-release.sh`（36 项）。
4. 发布说明生成器 `scripts/release-notes.sh`、发布保留策略 `scripts/release-gc.sh`。
5. 发布工作流硬门槛：版本递增、真 Release、IPK + SHA256、中文三节说明、保留最新 20 并清理最旧（带保护）。
6. `subscribe.sh` 协议白名单（纵深防御）。

---

## 4. 尚未实现 / 尚未验证

| 项 | 状态 | 事实 |
|---|---|---|
| 正式 Release | **没做** | 本轮未打 tag、未动 `v0.6.0`、`PKG_VERSION` 仍 0.6.0；发布制度只落在脚本与工作流层，没有真实跑过一次发布 |
| 保留 20 个的删除动作 | **没真跑过** | 本轮无新版本，`release-gc.sh` 只在测试里验证过计划输出 |
| ACL 真实生效 | **未验证** | 环境无 rpcd、无设备，只有 JSON 解析与源码静态断言 |
| 每套件用例数下限（R3） | **没做** | 现在只做到套件级完整性（缺套件 / 无结果行 / 结果矛盾 / SKIP） |
| 真机安装升级回滚 | **未验证** | 真机 0 台 |
| shellcheck | **未跑** | 环境无该工具，CI 也无 |

---

## 5. 删除的文件

无。本轮只新增与修改；历史报告、历史 tag、历史 Release 一律保留。

---

## 6. 执行的测试

- 环境：Linux VM（dash + python3 3.x + node），真实内核 `/tmp/sing-box-1.10.7-linux-amd64/sing-box`（31 797 383 B，`sing-box version 1.10.7`）。
- 命令（本地全量）：`EP_SING_BOX_BIN=/tmp/sing-box-1.10.7-linux-amd64/sing-box EP_TEST_LOG_DIR=/tmp/ep10-logs3 sh tests/run-all.sh`
- 单套件：`sh tests/test-security.sh`、`sh tests/test-release.sh`、`sh tests/test-regressions.sh` 等 12 个。
- 静态：`sh -n` 全部改动脚本、`node --check app.js`、`python3 -c 'json.load(...)'` 校验 ACL、`yaml.safe_load` 校验工作流。
- 逐字节核对：每笔推送后 `git pull` 再 `diff` 远端与本地。

---

## 7. 每项测试的实际结果

### 7.1 本地全量（唯一计数来源 `run-all.sh`）

RC=0，末行 `574 通过，0 失败，0 SKIP`，12 套件：

| 套件 | 通过 | 失败 |
|---|---|---|
| cli | 21 | 0 |
| engine | 45 | 0 |
| install-scripts | 126 | 0 |
| ipk-layout | 40 | 0 |
| maintenance | 44 | 0 |
| nodes | 61 | 0 |
| regressions | 31 | 0 |
| routing | 32 | 0 |
| runtime | 20 | 0 |
| release | 36 | 0 |
| security | 33 | 0 |
| transparent | 85 | 0 |
| **合计** | **574** | **0** |

### 7.2 红绿证据（先失败后通过）

- `test-security.sh` 首轮 **23 通过 / 10 失败**（D2 组因 ACL 仍含 `/bin/sh`、`write.file` 仍有通配等而红）→ 实现后 **33 / 0**。
- 注入类用例最初“错因通过”：CLI 还没有 `traffic`/`subscribe` 时，未知命令也返回 2，断言只看退出码就误判为通过。补了“失败原因必须含 `invalid interface` / `http`”之后才成立。
- `test-release.sh` 首轮 **6 通过 / 8 失败** → 实现后 **36 / 0**。
- `test-regressions.sh` 在工作流改造后出现 2 失败（“没有 env -u EP_SING_BOX_BIN”、“没有 SKIP 门禁”）——因为门禁已从工作流迁到 `run-all.sh`；改成断言 `run-all.sh` 后回到 31 / 0。
- 中途失败证据保留：`/tmp/ep10-logs2/test-regressions.log`（2 失败现场）；RED 首轮：`/tmp/ep9-evidence/red.log`（24 失败）。

### 7.3 静态与结构

| 检查 | 结果 |
|---|---|
| `sh -n` 六个改动/新增 shell（`easyproxy`、`subscribe.sh`、`run-all.sh`、`release-notes.sh`、`release-gc.sh`、`test-*.sh`） | 全部通过 |
| `node --check app.js` | 通过 |
| ACL `json.load` | 通过，且 exec 集合 = `{/usr/sbin/easyproxy}` |
| `build.yml` `yaml.safe_load` | 通过，16 个业务步骤 |
| 远端逐字节核对（每次 push 后 `git pull` + `diff`） | 13 个文件最终全部 `SAME` |

### 7.4 CI（GitHub Actions）

- run：`https://github.com/bnm188/EasyProxy/actions/runs/43912864440`（提交 `769f0e6`）。
- 逐步结论（取自 commit checks 页）：**17 步 success、2 步 skipped、0 步 failed**。
  - `Install the pinned sing-box used by the tests` success（16:56:46→16:56:47Z）；
  - `Run package test suites with the real kernel` success（16:56:47→16:57:18Z，31 秒）；
  - `Build EasyProxy`（SDK 编译）success（16:57:51→16:58:06Z）；
  - `Publish GitHub release`、`Prune old releases` **skipped**（本次不是 tag，符合设计）。
- 未取到的东西要写清：CI 那一步的日志正文（哪个套件多少条）**没读到**——未登录状态取不到 step log（`.../logs/1` 返回 9 字节），所以 CI 侧只记录“步骤成功”，不替它报“CI 上 574 通过”。574 是本地实测数。
- 文档提交 `4e616b8` 触发的运行在写作时**仍在进行**（依赖安装中），本报告不假称它已绿。

---

## 8. 编译是否成功

- **本地未编译**：本机没有 OpenWrt SDK，也没跑 `make`，不声称本地编译通过。
- **CI 编译成功（有证据）**：`Build EasyProxy`（`make package/easyproxy/compile V=s -j2`）在 run 43912864440 中 success；`make-ipk.sh` 两个架构、`make-kernel-ipk.sh` 三架构 × 两内核的步骤也 success。

---

## 9. 生成的 IPK / 内核包 / 其他产物

| 产物 | 本轮状态 |
|---|---|
| GitHub Release 资产 | **没有新增**（未发新版本），`v0.6.0` 未动 |
| CI 构建 artifact | 由 run 43912864440 产出并上传（`Upload build artifacts` success，`dist/*`：ipk、apk、rootfs、三架构 sing-box/dae、`SHA256SUMS`、`KERNEL-VERSIONS`）；保留 30 天，未发布为 Release |
| 本地 IPK | 未生成（本地不编译） |
| tag | 未打新 tag |

---

## 10. Commit SHA 与 Actions 结果

逐笔（新→旧），全部落在 `main`：

| # | Commit | 内容 | Actions |
|---|---|---|---|
| 1 | `f5bf862` | 面板不再调 `/bin/sh` | 绿（旧工作流） |
| 2 | `8b26259` | CLI 固定动词 `traffic` / `subscribe` | 绿（旧工作流） |
| 3 | `faedfae` | ACL 只放行固定 CLI + `subscribe.sh` 协议校验 | 绿（旧工作流） |
| 4 | `aa230be` | `subscribe.sh` 全文补全（修 #3 的截断） | 绿 |
| 5 | `65f6416` | 新增 `run-all.sh`、`release-notes.sh`、`release-gc.sh` | 绿（旧工作流） |
| 6 | `6286cb6` | 新增 `test-security.sh`（33 项） | 绿 |
| 7 | `9cf976f` | 修注释剥离正则 + 新增 `test-release.sh`（36 项） | 绿 |
| 8 | `050da3a` | 修 `release-gc.sh` 缺引号 | 绿 |
| 9 | `58b0fb0` | regressions 改指 `run-all.sh` + D9 新口径（31 项） | 绿 |
| 10 | `769f0e6` | 工作流：计数交 `run-all.sh`、发布门槛、清理 20 | **绿，run 43912864440，17 success / 2 skipped** |
| 11 | `4e616b8` | 本报告前的文档口径统一（STATUS + PLAN） | 写作时仍在运行 |
| 12 | 本报告提交 | 报告 005 + 索引 | 提交后由 CI 记录 |

---

## 11. 本次遗留问题

1. **没发过正式版本**：`PKG_VERSION` 仍是 0.6.0，没打新 tag；新门槛（版本递增、真 Release、IPK+SHA256、中文三节）只在代码与测试层验证，未端到端跑一次。
2. **ACL 只在静态层验证**：真实 rpcd 渲染后的授出范围没在设备上看过。
3. **R3 每套件用例数下限**：仍只做到套件级完整性，套件里少写几条断言不会被拦住。
4. **真机 0 台**：安装/升级/回滚、tproxy、LuCI 渲染全部未验。
5. **shellcheck 未跑**：环境无该工具。
6. **沿用 004 的遗留缺陷未动**：D4（hysteria2/tuic 缺 `tls=1`）、D10（配置 0644）、D11（`cache_file` 目录不建）、D12（无 ssr）、D13（`node test` 仅 TCP）、D14（装完默认不可用）、D16（无 lint、安装器 1 136 行）。
7. **推送通道的转录风险已发生 4 次**（诚实记录）：`subscribe.sh` 首次只推到前 30 行被截断、`test-security.sh` 块注释正则丢反斜杠、`release-gc.sh` 第 82 行丢引号、`usr/sbin/easyproxy` 缩进/空行差异。前三次整体重推修正，第四次以远端为准回拷本地；此后每次推送都 `git pull` + `diff` 逐字节核对，最终 13 个文件全部 `SAME`。
8. **统计口径变更要记住**：004 的“504 项”是 10 个套件手工相加；本轮起以 `tests/run-all.sh` 实际输出为准，12 套件 574 项。差异来自新增两个套件（security 33、release 36）与 regressions 30→31，不是同一批用例变多。

---

## 12. 下一步计划与阶段判定

- 阶段判定：**Stage 9 = 部分完成（待确认）**。DoD 逐条：代码已合并（满足）；测试实跑留证（满足，含失败痕迹）；报告 005 已提交（满足）；状态文档已更新（满足）；涉及发布——**未真实产出 Release（不满足）**。因此不写“完成”。
- 本轮到此停止，等独立验收；**不进 Stage 10**，不打正式 tag，不改 `v0.6.0`。
- 验收通过后的第一件事（Stage 10）：`easyproxy-manager.sh`（唯一入口），同时补 R3 用例数下限、D4、D10、D14。
