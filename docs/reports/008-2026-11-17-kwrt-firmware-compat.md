# 008 · Kwrt 固件识别与安装兼容性修复（2026-11-17）

- 任务目标：修掉用户在 Kwrt 固件上执行 SSH 安装时遇到的 `error: firmware: Kwrt is not OpenWrt/ImmortalWrt; this build targets 21.02 or newer`。要求**基于现有 `scripts/install.sh` 修复、不重写安装器**：查明 Kwrt 的真实系统标识/版本/架构/包管理器，确认与目标 OpenWrt 基线兼容后把 Kwrt 纳入识别范围；不删检查、不默认跳过、未知固件仍拦截；不可兼容的 Kwrt 版本必须给出明确理由；补 Kwrt 识别测试与安装器回归测试；更新 README 安装说明。
- 对应阶段：Stage 9（安装/升级链路）内的兼容性补丁，不改变阶段判定
- 代码提交：`5b84c2b`（`fix(installer): recognise Kwrt firmware, its opkg baseline and arch limits`）
- 执行环境：vm（Linux/Bash），工作树 `/tmp/ep11-check`，基线 `main@e7827ee`
- 声明口径：全部结论来自**本次实跑的沙箱测试**与**实下的 Kwrt 镜像**；**真机未验**（用户报错的 Kwrt 设备本轮没有参与实测）

---

## 0. 取证：Kwrt 到底是什么

镜像与校验（本次实下）：

| 项 | 实测值 |
|---|---|
| 镜像 URL | `https://dl.openwrt.ai/releases/targets/ramips/mt7621/kwrt-10.08.2026-ramips-mt7621-zyxel_wsm20-rootfs.tar.gz` |
| 字节数 | 34 348 319 |
| SHA256 | `86d8ebd28944e4ef715dc541c8ca73a3249f6c762ffe7279d55ad82b3a8ce79d` |
| 本地路径 | `/tmp/kwrt/kwrt.tar.gz` |

`tar -xzOf` 读出的 `/etc/openwrt_release`（逐字）：

```
DISTRIB_ID='Kwrt'
DISTRIB_RELEASE='25.12-SNAPSHOT'
DISTRIB_REVISION='10.11.2026'
DISTRIB_TARGET='ramips/mt7621'
DISTRIB_ARCH='mipsel_24kc'
DISTRIB_DESCRIPTION='Kwrt 25.12-SNAPSHOT 10.11.2026'
DISTRIB_TAINTS='busybox override'
```

关键事实（每一条都有镜像内文件支撑）：

| 事实 | 证据 |
|---|---|
| `DISTRIB_ID='Kwrt'` | 上述 `/etc/openwrt_release` |
| **没有 `VERSION_ID` 行** | 同上；旧 `check_firmware()` 只读 `VERSION_ID`，这正是旧逻辑必然误拒的根因 |
| `/etc/os-release` 是 **0 字节空文件** | `tar -xzOf … ./etc/os-release \| wc -c` → `0` |
| 包管理器仍是 **opkg** | 镜像内有 `./bin/opkg`、`./etc/opkg.conf`、`./etc/opkg/distfeeds.conf`、`./usr/lib/opkg/status`；`tar -tzf \| grep -cE './bin/opkg$\|./etc/apk'` → `1`（只有 opkg），`./etc/apk` 与 `apk` 二进制均无 |
| feeds 指向 25.12 | `distfeeds.conf`：`src/gz kwrt_core https://dl.openwrt.ai/releases/25.12/targets/ramips/mt7621/6.12.112`，`kwrt_base/packages/luci/routing` 在 `https://dl.openwrt.ai/releases/25.12/packages/mipsel_24kc/…` |
| LuCI 与面板依赖满足 | `./usr/share/luci/menu.d/luci-base.json`、`./www/luci-static/`、`./usr/share/rpcd/acl.d/` 均在；`luci-base` `Version: 27.283.74525~63652b2`；`libc` `1.2.5-r5`（musl） |
| 安装路径不冲突 | 面板要写 `/www/luci-static/resources/view/easyproxy`、`/usr/share/luci/menu.d/`、`/usr/share/rpcd/acl.d/`、`/usr/sbin/`、`/etc/config/`、`/usr/lib/easyproxy/`，Kwrt 这些目录都存在 |

结论：Kwrt 是**基于 OpenWrt 的衍生固件**（`dl.openwrt.ai` 构建），不是自有内核的独立发行版；它的 25.12 基线**仍用 opkg**（与官方 OpenWrt 25.12 起改用 apk 不同），所以 `--ipk` 路径对它成立。

---

## 1. 修改的文件及路径

| # | 文件 | 类型 | 说明 |
|---|---|---|---|
| 1 | `scripts/install.sh` | 修改 | `check_firmware()` 纳入 Kwrt 并按基线判定；新增 `check_luci()`、`check_arch()`；安装/升级两处调用 |
| 2 | `tests/test-regressions.sh` | 修改 | 新增 D7d（Kwrt 识别 13 项断言）；沙箱 `opkg` stub 支持 `EP_TEST_ARCH` 以模拟非 x86_64 架构 |
| 3 | `README.md` | 修改 | 适用固件、安装步骤、测试计数、新增「Kwrt 固件」小节 |
| 4 | `docs/PROJECT-STATUS.md` | 修改 | 补本轮结论与 591 项测试口径 |
| 5 | `docs/reports/008-2026-11-17-kwrt-firmware-compat.md` | 新增 | 本报告 |
| 6 | `docs/reports/README.md` | 修改 | 第 7 节索引追加 008 行 |
| 7 | `.github/workflows/kwrt-fix-once.yml`、`.github/workflows/kwrt-fix-once-2.yml` | **删除** | 一次性补丁工作流，任务完成后在提交 `5b84c2b` 里自删 |

---

## 2. 每个文件的具体修改

### 2.1 `scripts/install.sh`：`check_firmware()`（原 711–747 行区域）

- 固件家族判定：原来只接受 `ImmortalWrt|OpenWrt|LEDE|immortalwrt|openwrt`，其它一律 `die`。现在增加 `Kwrt|kwrt|KWRT` 一支，标记为 `derivative=1`；**未知固件分支的拦截逻辑与原文案未改**（仍 `die "firmware: … is not OpenWrt/ImmortalWrt; this build targets 21.02 or newer (EP_SKIP_COMPAT=1 forces the install)"`）。
- 版本来源：读 `VERSION_ID`；Kwrt 分支在 `VERSION_ID` 缺失时依次退回 **`DISTRIB_RELEASE`**（真实镜像为 `25.12-SNAPSHOT`）、再退回 `DISTRIB_DESCRIPTION`（并去掉开头的 `Kwrt` 前缀，避免输出 `Kwrt Kwrt …`）。
- 基线解析：用 `grep -oE '(1[2-9]|2[0-9]|3[0-9])\.[0-9][0-9]'` 取首个 `NN.mm` 令牌，因此 `25.12-SNAPSHOT` 与 `Kwrt 25.12-SNAPSHOT 10.11.2026` 都能解析，而构建日期 `10.11.2026` 不会被误当版本（年份段从 12 起）。
- 判定：解析不出基线 → **拒绝**，文案写明 `states no OpenWrt baseline … needs 21.02 or newer`（不再像旧逻辑那样因缺 `VERSION_ID` 只打印 "cannot be checked" 就放行）；基线 < 21.02 → 拒绝并写明 `older than 21.02`；`EP_SKIP_COMPAT=1` 时上述两处退化为 `info` 强制放行。
- 放行日志：Kwrt 输出 `firmware: Kwrt 25.12-SNAPSHOT (OpenWrt 25.12 derivative)`，官方固件仍是 `firmware: <id> <ver>`。

### 2.2 `scripts/install.sh`：新增 `check_luci()`

`$ROOT/usr/share/luci/menu.d` 或 `$ROOT/usr/lib/lua/luci` 缺失时打印：

```
luci: <root>/usr/share/luci/menu.d is missing; the easyproxy menu appears only after luci-base is installed
```

不阻断安装（`opkg` 会按 `Depends: uci, luci-base` 拉依赖；离线/无源时至少让用户知道菜单为什么不见了）。

### 2.3 `scripts/install.sh`：新增 `check_arch()`

用 `host_ipk_arch()`（即 opkg 自报架构）判定：`x86_64` / `aarch64*` / `armv7*` / `armv6*` 之外，打印：

```
arch: mipsel_24kc is outside x86_64/aarch64/armv7; the panel installs, but this build carries no kernel for that architecture
```

**不阻断面板安装**：面板发的是 `_all.ipk`（架构无关），实测 `install-scripts` 里"无匹配架构仍装 `_all.ipk`"的既有行为必须保留；内核包缺失由内核步骤自己报错。

### 2.4 `scripts/install.sh`：两处调用点

`do_install()` 与升级路径在 `check_firmware` 之后插入 `check_luci`、`check_arch`（各自后接原有 `check_disk_space`）。

### 2.5 `tests/test-regressions.sh`

- 沙箱 `opkg` stub 的 `print-architecture` 改为输出 `${EP_TEST_ARCH:-x86_64}`，`run_installer` 追加透传 `EP_TEST_ARCH`（否则无法在 x86 主机上模拟 mipsel 设备）。
- 新增 **D7d Kwrt 固件识别**（13 项断言，断言用的 `openwrt_release` 逐字取自真实镜像）：
  1. `25.12-SNAPSHOT` 放行（rc=0）
  2. 放行日志含 `Kwrt 25.12`
  3. `23.05.5` 放行（rc=0）
  4. `19.07.10` 拒绝（rc≠0）
  5. 拒绝理由含 `21.02`
  6. 只有 `SNAPSHOT` 且描述只有 `Kwrt` 时拒绝（rc≠0）
  7. 该拒绝理由点名 `Kwrt`
  8. `EP_SKIP_COMPAT=1` 可强制（rc=0）
  9. 缺 LuCI 时输出 `luci:`
  10. 有 LuCI（`mkdir usr/share/luci/menu.d`）时不再输出 `luci:`
  11. `mipsel_24kc` 仍能装面板（rc=0）
  12. 提示点名 `mipsel_24kc`
  13. 提示写明 `no kernel for that architecture`

### 2.6 `README.md`

- 首行能力声明：适用固件加 Kwrt（注明需 OpenWrt 21.02 以上基线）；测试计数 578 → 591。
- 安装步骤第 1 条改写：官方固件认 `VERSION_ID`、Kwrt 认 `DISTRIB_RELEASE`，两者都必须解析出 ≥21.02 的基线。
- 新增「### Kwrt 固件」小节：实测值表（`DISTRIB_ID` / `DISTRIB_RELEASE` / 无 `VERSION_ID` / opkg / LuCI）+ 五条判定规则（放行、低于 21.02 拒绝、解析不出拒绝、架构提示、`EP_SKIP_COMPAT=1`）。

### 2.7 `docs/PROJECT-STATUS.md`

更新"最后更新/更新依据"，新增本轮段落（含 591 项口径与"真机未验"），测试计数三处 578→591（regressions 33→46）。

---

## 3. 新增功能

1. Kwrt 固件识别（`DISTRIB_ID='Kwrt'`），并按其真实字段（`DISTRIB_RELEASE`，无 `VERSION_ID`）判定 OpenWrt 基线。
2. 基线不可确认时的显式拒绝（替换旧的"缺 `VERSION_ID` 就只提示并放行"）。
3. LuCI 缺失提示（面板装上但菜单不出现时给出原因）。
4. 非 x86_64/aarch64/armv7 架构的显式提示（"面板能装、内核没有"）。

---

## 4. 未实现 / 仍未覆盖

- **真机验证**：没有在任何 Kwrt 设备上真装；全部结论是沙箱 + 镜像取证。
- **其它 Kwrt 分支未取证**：只实下并验证了 `ramips/mt7621` 的 `25.12-SNAPSHOT` 一支；Kwrt 若存在 23.05/24.10 命名的构建，其 `DISTRIB_RELEASE` 具体取值未实下核对（代码层面的判定规则是按"能解析出 `NN.mm`"设计，但**未经真实镜像验证**）。
- **opkg 依赖解析未在 Kwrt feeds 上实跑**：`Depends: uci, luci-base` 在 Kwrt 上是否总能解析到，只验证了镜像内已预装 `luci-base`，未验证联网 `opkg install` 的真实结果。
- **内核包仍只有三架构**：Kwrt 的 `mipsel_24kc` 等目标没有对应内核包，本构建不提供。

---

## 5. 删除的文件及理由

| 文件 | 理由 |
|---|---|
| `.github/workflows/kwrt-fix-once.yml` | 一次性补丁工作流（把 15 254 字节的补丁 `git apply` 进仓库后自删）；随代码提交 `5b84c2b` 一同删除，仓库不保留一次性工作流 |
| `.github/workflows/kwrt-fix-once-2.yml` | 同上；该文件用于修正第一版工作流内 base64 载荷的一个字符错误（`SL7BX/`→`SL7BW/`），修正后与前者在同一提交内自删 |

---

## 6. 执行的测试

全部在 vm、`/tmp/ep11-check`（`main@e7827ee` + 本报告改动）执行；12 套件经 `tests/run-all.sh` 汇总。

| 命令 | 说明 |
|---|---|
| `sh tests/test-regressions.sh` | 单独跑回归套件（含新增 D7d） |
| `EP_SING_BOX_BIN=/tmp/kb/sing-box-1.14.4-linux-amd64/sing-box EP_TEST_LOG_DIR=/tmp/kwrt-fix-logs4 sh tests/run-all.sh` | 用真实 sing-box 1.14.4 跑全量 |
| `env -i PATH=/usr/bin:/bin EP_ROOT=/tmp/kwrt-real sh scripts/install.sh --ipk --no-engine` | 用**真实镜像里取出的 `/etc/openwrt_release`** 验证识别结果 |

### 6.1 红→绿（先看到失败）

实现前先写 D7d，跑 `sh tests/test-regressions.sh`：

```
== D7d Kwrt 固件识别 ==
  FAIL  Kwrt 25.12-SNAPSHOT 被识别并放行
        rc=1 error: firmware: Kwrt is not OpenWrt/ImmortalWrt; this build targets 21.02 or newer (EP_SKIP_COMPAT=1 forces the install)
  FAIL  放行日志写明 Kwrt 与基线版本
  FAIL  Kwrt 23.05.5 同样放行
  PASS  Kwrt 19.07（低于 21.02）被拒绝（rc=1）
  ...
  FAIL  缺少 LuCI 时提示
```

即：4 项失败正是用户报错的现场复现（旧逻辑对 Kwrt 一律拒绝）。实现后同一套件 46 通过 / 0 失败。

> 注：当时 `19.07 被拒绝` 是"因为所有 Kwrt 都被拒"而偶然通过；实现后它靠的是"基线 < 21.02"这条真实理由（拒绝文案含 `21.02` 的断言同时通过）。

### 6.2 真实镜像识别

```
firmware: Kwrt 25.12-SNAPSHOT (OpenWrt 25.12 derivative)
luci: /tmp/kwrt-real/usr/share/luci/menu.d is missing; the easyproxy menu appears only after luci-base is installed
```

（第二行是因为 `EP_ROOT` 只放了 `etc/openwrt_release` 一个文件，没放 LuCI 目录；该提示行为与设计一致。）

### 6.3 全量结果

```
suite                      通过   失败   SKIP
test-cli                       21        0      0
test-engine                    45        0      0
test-install-scripts          126        0      0
test-ipk-layout                40        0      0
test-maintenance               44        0      0
test-nodes                     61        0      0
test-regressions               46        0      0
test-routing                   32        0      0
test-runtime                   20        0      0
test-release                   36        0      0
test-security                  33        0      0
test-transparent               87        0      0
合计：591 通过，0 失败
```

---

## 7. 失败与返工记录（如实保留）

按报告制度"失败必须留证"，本轮出现的失败全部记录：

| # | 现象 | 原因 | 处理 |
|---|---|---|---|
| 1 | 首次全量：`test-security` 1 项 `FAIL traffic 经固定入口的 tx 仍是第 10 列`（期望 14904160，实际 14904488） | **与本轮改动无关的既有竞态**：测试先读 `/proc/net/dev` 计数、再调 CLI 读一次，全量并行时接口计数已增长 | 单跑 `test-security` 连续 3 次 33/0；随后两次全量 588/0、591/0。**未改该测试**（超出本轮"只修固件识别与兼容性"的范围），作为遗留问题登记 |
| 2 | 中途全量：`test-install-scripts` 3 项 `FAIL`（"无匹配架构时仍能安装 / 退回 all 包 / 拒绝原因说明没有可装的包"） | 我第一版 `check_arch()` 写成**硬 `die`**，误伤了"面板 `_all.ipk` 架构无关、mipsel/riscv 也能装面板"的既有正确行为 | 改为提示而非阻断，保留既有行为；重跑该套件 126/0 |
| 3 | 一次性工作流 `kwrt-fix-once.yml` 第 2 次运行 **failed**（run 页可见） | 我把 7 668 字符 base64 载荷推上去时错了一个字符（`SL7BX/` 应为 `SL7BW/`），`gzip -d` 失败 | 新增 `kwrt-fix-once-2.yml` 定点修正该字符后再解码应用，成功；两个工作流在同一提交内自删 |

---

## 8. 编译结果

- **是否成功：未执行编译**（原因：本轮只改 shell 脚本、测试与文档，未触碰 `package/easyproxy/Makefile`、未要求产出 IPK/apk；本地无 ImmortalWrt SDK 编译环境）。
- 语法检查：`sh -n scripts/install.sh` → 通过；`sh -n tests/test-regressions.sh` → 通过。
- CI：仓库 `build.yml` 会在 push `main` 时跑（构建 + 打包 + 校验），其结论以 Actions 页为准；**本轮不以 CI 结论代替本地测试结论**（CI 状态见第 9 节记录时点）。

---

## 9. 产物

- 本轮**没有**新的 IPK / apk / rootfs / 内核包产物（未编译、未发布新 Release）。
- 仓库产物：代码提交 `5b84c2b`（3 个文件实质修改 + 2 个一次性工作流删除），以及本报告与索引行。
- 远端核对：`git fetch` 后逐文件比对 `sha256sum`，`scripts/install.sh`、`tests/test-regressions.sh`、`README.md` 三个文件**本地与远端完全一致**（`4ce2f5aa…`、`18615d1b…`、`c8e4fb98…`）。

---

## 10. 提交

- 代码/文档提交：`5b84c2b`（`fix(installer): recognise Kwrt firmware, its opkg baseline and arch limits`），由一次性工作流在仓库内 `git apply` 后提交并推送，作者 `EasyProxy Bot`。
- 报告提交：本报告与 `docs/reports/README.md` 索引行、`docs/PROJECT-STATUS.md` 同一次提交；该提交 SHA 见 GitHub 提交历史（避免自引用）。

---

## 11. 遗留问题

1. **真机未验**：用户报错的那台 Kwrt 设备没有参与实测；沙箱通过 ≠ 设备上能装。
2. **只取证了一支 Kwrt**：`ramips/mt7621` + `25.12-SNAPSHOT`；Kwrt 其它分支（若存在 23.05/24.10 命名或纯 `SNAPSHOT`）的 `DISTRIB_RELEASE` 取值未实下核对。
3. **`test-security` 的 traffic 断言存在既有竞态**（全量并行时偶发 1 项失败），本轮未修，已留证。
4. **Kwrt 上的 opkg 联网依赖解析未实跑**：只确认镜像内已预装 `luci-base`。
5. **非三架构无内核**：`mipsel_24kc` 等只提示、不提供内核包。
6. 上一轮遗留仍在：`v0.7.0` tag 指向的树里仍有 `runlog.txt`（tag 不移动）；`build.yml` 的 tag 原生发布路径未实跑；dae 适配器不可用；ChatGPT 对 0.7.0 的独立验收仍无结论。

---

## 12. 下一步计划

1. 等用户在有 Kwrt 的设备上复跑安装命令，把 `scripts/install.sh` 的 `firmware:`/`luci:`/`arch:` 三行原样回传，作为真机证据补进后续报告。
2. 若需要扩大支持面，实下 Kwrt 其它分支镜像核对 `DISTRIB_RELEASE`，再决定是否细化"支持的 Kwrt 版本"清单。
3. 修 `test-security` 的 traffic 竞态（改成同一读取窗口或离线 fixture），避免全量偶发失败。
4. 回到既定路线：`easyproxy-manager.sh`（第二阶段）仍未开工。

---

## 13. 支持的 Kwrt 版本（本报告的可交付结论）

| 基线 | 行为 | 依据 |
|---|---|---|
| ≥ 21.02（如实测 `25.12-SNAPSHOT`、测试覆盖 `23.05.5`） | 放行，日志写明基线 | 真实镜像 + 沙箱测试 |
| < 21.02（如 `19.07.10`） | 拒绝，理由写明低于 21.02 | 沙箱测试 |
| 版本无法解析（如只有 `SNAPSHOT`） | 拒绝，理由写明无法确认基线 | 沙箱测试 |
| 任意版本 + `EP_SKIP_COMPAT=1` | 强制放行（日志标注） | 沙箱测试 |
| 架构不在 x86_64/aarch64/armv7 | 面板可装（`_all.ipk`），明确提示无内核包 | 沙箱测试 + 镜像 `DISTRIB_ARCH='mipsel_24kc'` |

---

## 14. 阶段判定

- Stage 9 的安装/升级链路能力**不变**（本轮是兼容性补丁），阶段判定维持"完成（待 ChatGPT 独立验收）"。
- 本报告不改变 `docs/DEVELOPMENT-PLAN.md` 的阶段划分；阶段推进仍需用户确认。
