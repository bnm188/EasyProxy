# 报告 010 · Kwrt 安装失败修复：opkg 不认 `all` 时仍能装上面板

- 日期：2026-11-17（UTC+8）
- 任务类型：缺陷修复 + 正式版本发布
- 版本：`0.8.2`（`PKG_VERSION:=0.8.2`，此前未发布过）
- 代码提交：`30c0b0a4797a18712efe96005e0d480acfbcbc3e`
- Tag：`v0.8.2` → `30c0b0a4797a18712efe96005e0d480acfbcbc3e`
- Release：<https://github.com/bnm188/EasyProxy/releases/tag/v0.8.2>（id 448177542，12 项资产）
- CI：run #199（<https://github.com/bnm188/EasyProxy/actions/runs/44023055587>），20 个步骤全绿，含发布与发布后自检

---

## 1. 任务名称与目标

用户真机（Kwrt 25.12-SNAPSHOT）执行 `all.sh | sh` 时失败，原样输出：

```
all.sh | sh
firmware: Kwrt 25.12-SNAPSHOT (OpenWrt 25.12 derivative)
arch: arch is outside x86_64/aarch64/armv7; the panel installs, but this build carries no kernel for that architecture
disk: /tmp has 998396 KB free (need 65536 KB)
disk: / has 568304 KB free (need 65536 KB)
error: no installable ipk for arch: this opkg does not accept 'all' and the release has no _arch.ipk (nothing was installed)

Collected errors:
 * pkg_init_from_file: Malformed package file /tmp/upload.ipk.

Collected errors:
 * pkg_init_from_file: Malformed package file ./easyproxy_0.8.0-1_all.ipk.
```

目标：

1. 该固件的 opkg 只接受自身架构、拒绝 `Architecture: all`，导致安装器在 `install_package()` 里直接 `die`，**面板一个文件都没装**。把这条路径改成能装上，而不是把检查删掉。
2. 用户在设备上手工 `opkg install ./easyproxy_0.8.0-1_all.ipk` 又报 `Malformed package file`。要让安装器在“包被 opkg 判为 malformed”时也有确定的出路。
3. 不得牺牲既有安全边界：下载仍必须过 `SHA256SUMS`、未知固件仍拦截、**内核包永不强装**、真失败不能被包装成成功。
4. 按项目制度交付真实版本：新版本号 + Tag + 真 Release + 资产 SHA256 复核 + 本报告 + 状态文档。

---

## 2. 修改的文件及路径

| 文件 | 变更 |
|---|---|
| `scripts/install.sh` | 1267 行（原 1217 行）：`install_pkg()` 增加 force 参数；`install_package()` 的 ipk 分支改为“强制架构 → 归档兜底”；抽出可复用的 `install_rootfs()` |
| `package/easyproxy/files/usr/lib/easyproxy/bypass.sh` | 1 行：`printf "%%s"` → `printf "%s"` |
| `tests/test-install-scripts.sh` | 658 行（原 623 行）：改写“拒绝安装”用例为“仍然装上”，新增归档回退用例与 malformed 回退用例，opkg stub 增加 `EP_TEST_OPKG_REJECT` 旋钮 |
| `tests/test-release.sh` | 7 行：`.release-request` 断言随该机制被移除改为 `PKG_VERSION` 即发版命令 |
| `README.md` | 两处安装说明：说明 `--force-architecture` 只用于面板、归档兜底、内核不硬装 |
| `.github/workflows/apply081.yml`、`.github/workflows/d9d.yml` | 删除（见第 6 节） |

提交 `30c0b0a` 的 `--stat`：

```
 .../easyproxy/files/usr/lib/easyproxy/bypass.sh    |   2 +-
 scripts/install.sh                                 |  84 +++++++++++++++++-----
 tests/test-install-scripts.sh                      |  45 ++++++++++--
 tests/test-release.sh                              |   7 +-
 4 files changed, 114 insertions(+), 24 deletions(-)
```

---

## 3. 每个文件改了什么（逐条）

### 3.1 `scripts/install.sh`

**(a) `install_pkg()` 增加第三个参数 `force`**

```sh
install_pkg() {
	local pm file force
	pm="$1"; file="$2"; force="${3:-0}"
	case "$pm" in
		opkg)
			if [ "$force" = 1 ]; then
				opkg install --force-architecture "$file"
			else
				opkg install "$file"
			fi ;;
		apk) apk add --allow-untrusted "$file" ;;
```

默认 `force=0`，因此所有既有调用点（含 `install_kernel()` 的 `install_pkg "$pm" "$file"`）行为不变：**内核包路径拿不到 force**。

**(b) 删掉 `die "no installable ipk ..."`**

原逻辑（旧 855 行）：`opkg_accepts_all` 为 0 且 API 里没有 `_<arch>.ipk` → 直接失败退出。改为：

- 先 `asset_from_api '_all\.ipk$'`，拿不到再 `asset_url '\.ipk$'`（Makefile 版本拼 `_all.ipk`）；
- 置 `force_panel=1`；
- 下载照旧走 `fetch_verified`（`SHA256SUMS` 必须对上）+ `check_package_file`（`!<arch>` 魔数）；
- 安装前打印一条 warning，点名架构和 `--force-architecture` 的原因。

**(c) 安装失败的分流**

```sh
pmout="$work/pm.out"
if install_pkg "$pm" "$file" "$force_panel" > "$pmout" 2>&1; then
	:
else
	cat "$pmout"
	refused=0
	[ "$force_panel" = 1 ] && refused=1
	grep -qi 'malformed package file\|invalid package file\|unknown package arch' "$pmout" && refused=1
	if [ "$MODE" = "ipk" ] && [ "$refused" = 1 ]; then
		info "the package manager refused ...; falling back to the rootfs archive"
		install_rootfs || return 1
	else
		info "the package manager refused ...; nothing was installed"
		return 1
	fi
fi
```

关键取舍：**只有“包被拒”（架构不符 / opkg 判 malformed）才改走归档**。升级过程中 opkg 装到一半失败不属于“被拒”，仍返回 1，`upgrade_package()` 才可能做 `restore_package()` 回滚。这是本轮第一次改法的回归——最初的版本对所有失败都回退归档，导致 `test-regressions` 的 “失败后 CLI 二进制被回滚” 与 “被删除的库文件被回滚” 两条由绿转红，被测试当场抓住后改成了现在这条范围更窄的规则。

**(d) 抽出 `install_rootfs()`**

`--rootfs` 分支与新的兜底路径共用同一段：`fetch_verified` 校验 tar.gz（`SHA256SUMS`）→ `tar -xzf -C "$ROOT"` → `chmod 755` 两个入口文件。

### 3.2 `package/easyproxy/files/usr/lib/easyproxy/bypass.sh`

`ep_bypass_elements()` 里的 awk 写成 `printf "%%s"`，输出的是字面量 `%s` 而不是 CIDR 条目。两个后果：`ep_bypass_elements` 拼出来的集合元素全是 `%s`；渲染进 nft 的 `elements = { %s }` 为空壳，入口放行规则实际不生效。改为 `printf "%s"`。

这是 0.8.1 之后混进 `main` 但**从未发布**的 bypass 功能里的真实缺陷，被 `tests/test-bypass.sh` 的两条断言（“元素以逗号拼接”“集合带真实元素”）在发版前拦住。

### 3.3 `tests/test-install-scripts.sh`

按 TDD 先写红：新契约的四条断言在未改 `install.sh` 时全红（`结果：124 通过，6 失败`），失败原因正是“没有调用 `--force-architecture`”“没有下载 rootfs 归档”。

新增/改写后的用例：

1. `opkg 不收 all 时仍然装上面板（退出码 0）` —— 原用例是“拒绝安装”，属于旧契约，改写。
2. `面板包用 --force-architecture 安装` —— 断言 `pm.log` 里有该标志。
3. `安装器说明了为什么强制架构` —— 断言输出里出现 `force-architecture`。
4. `内核包从不使用 --force-architecture` —— 断言带该标志的行里没有 `sing-box`/`dae`。
5. `opkg 拒绝强制架构后改用 rootfs 归档（退出码 0）` + `回退时说明了走 rootfs 归档` + `回退时下载了 rootfs 归档`。
6. `opkg 判 ipk 为 Malformed 时改用 rootfs 归档（退出码 0）` + `回退时说明改走 rootfs 归档`。

opkg stub 新增旋钮：`EP_TEST_OPKG_REJECT` 非空时，`install` 分支打印 `Collected errors: * pkg_init_from_file: Malformed package file <file>.` 并 `exit 1`。

### 3.4 `tests/test-release.sh`

断言 `grep -q '.release-request'` 已失效：该文件机制在 `6aeb4e2` 被“版本号即发版命令”取代（`PKG_VERSION` 高于最新 Release 时自动发布）。断言的契约随之改为：

- 工作流读 `PKG_VERSION`；
- 工作流与最新 Release 比较后才发布。

这不是放宽标准，而是旧断言对应的机制已被有意移除。

### 3.5 `README.md`

- 安装流程第 2 条补全：拿不到架构包退 `_all.ipk`；若 opkg 不认 `all` 用 `--force-architecture`（只面板）；连强制也被拒（如 malformed）改走 `-rootfs.tar.gz` 归档，退出码 0 且日志写明。
- Kwrt 小节补两条：架构不在三族时面板照装但提示没有该架构内核；opkg 拒绝 `all` 且无该架构 ipk 时不再报 `no installable ipk for arch` 停住。

---

## 4. 新增了哪些功能

1. **面板的强制架构安装路径**：`opkg install --force-architecture`，仅当 opkg 明确拒绝 `Architecture: all`、且发布侧没有该架构 ipk 时触发，仅用于 `_all.ipk` 面板包。
2. **发布归档兜底**：opkg 拒绝包（架构不符或 `Malformed package file`）时，安装器自动改用已 `SHA256SUMS` 校验的 `easyproxy-<ver>-rootfs.tar.gz` 解开到 `/`，退出码 0，并打印“包管理器拒绝了 X；改用归档”的说明。
3. **失败分流规则**：把“包被拒”和“装到一半失败”分开——前者走归档，后者如实失败，保证升级回滚语义不被掩盖。
4. **可诊断输出**：安装失败时把包管理器原始输出（如 `Collected errors:` 那几行）原样打印出来，不再只留一句“refused”。

---

## 5. 哪些功能还没有实现

1. **没有在真实 Kwrt 设备上复验**。本轮全部证据来自沙箱 stub（opkg/curl/uci/rpcd 都是桩）+ CI。用户那台 Kwrt 25.12-SNAPSHOT 没有再跑一次安装，`--force-architecture` 与归档兜底在真机上的表现**未验**。
2. **`Malformed package file` 的根因未定论**。已实测的 0.8.0/0.8.2 ipk 都是合法 `ar` 容器（`file` = `Debian binary package (format 2.0)`，`ar tv` 三成员 `debian-binary`/`control.tar.gz`/`data.tar.gz`，头为 `!<arch>`，发布资产与 `SHA256SUMS` 逐字节一致）。外部线索（OpenWrt 论坛 2023/2024 两帖）显示某些 opkg 实现偏好“gzip 包着三个成员”的口味、对 `ar` 报 malformed，但那是线索级证据，**没有在 Kwrt 上取样对照**。本轮只做到“被拒时有确定的替代路径（归档）”，没做到“让 opkg 一定吃得下这个 ipk”。
3. **该架构没有任何内核包**：Kwrt `riscv64`/`mipsel_24kc` 这类架构仍然只装面板，内核步骤会明确失败并提示“该架构没有内核包”。没有新增该架构的 sing-box/dae 内核包，也没有为此弱化检查。
4. **`.release-request` 机制删除后未补替代的“发布请求”入口**：现在只靠 `PKG_VERSION` 递增 + 真实 push（API 令牌推送不触发工作流）。文档提交不会触发发布，符合预期，但“令牌环境的发布”仍是人工 push。
5. dae 适配器仍未可用（`KERNEL-VERSIONS` 里写明“开发中”），本轮未改。

---

## 6. 删除了哪些文件及理由

| 文件 | 理由 |
|---|---|
| `.github/workflows/apply081.yml` | 上一轮的一次性工作流（“Apply 0.8.1 tree and request the release”）。0.8.1、0.8.2 已真实发布，它的使命结束；它持有 `contents: write`，留着等于仓库里放一把能改 `main` 的手枪 |
| `.github/workflows/d9d.yml` | 上一轮给报告 009 追加收尾段的一次性工作流。本轮 push 时它被再次触发并**两次失败**（run 44023053313 / 44023052155，均为 `push` 事件、`d9d.yml`），只会制造红叉；009 的正文已经完整（第 9、10 节在文件末尾） |

删除这两个文件不影响任何产品路径：`build.yml` 是唯一发布工作流。

---

## 7. 执行了哪些测试、每项实际结果

测试命令（本机，vm，`main@30c0b0a` 工作树）：

```
EP_SING_BOX_BIN=/tmp/sb/sing-box-1.14.4-linux-amd64/sing-box sh tests/run-all.sh
```

来自 git 之外的真实内核：从 `SagerNet/sing-box` v1.14.4 release 实下 `sing-box-1.14.4-linux-amd64.tar.gz` 解出，`sing-box version` 输出 `sing-box version 1.14.4`。

| 套件 | 通过 | 失败 | SKIP |
|---|---|---|---|
| test-bypass | 41 | 0 | 0 |
| test-cli | 21 | 0 | 0 |
| test-engine | 45 | 0 | 0 |
| test-install-scripts | 132 | 0 | 0 |
| test-manager | 30 | 0 | 0 |
| test-ipk-layout | 40 | 0 | 0 |
| test-maintenance | 44 | 0 | 0 |
| test-nodes | 61 | 0 | 0 |
| test-regressions | 47 | 0 | 0 |
| test-routing | 32 | 0 | 0 |
| test-runtime | 20 | 0 | 0 |
| test-release | 46 | 0 | 0 |
| test-security | 33 | 0 | 0 |
| test-transparent | 87 | 0 | 0 |
| **合计** | **679** | **0** | **0** |

失败与红态记录（不删）：

1. **改测试、未改实现时**（TDD 红）：`test-install-scripts` = `124 通过，6 失败`，失败项为 `opkg 不收 all 时仍然装上面板` / `面板包用 --force-architecture 安装` / `安装器说明了为什么强制架构` / `内核包从不使用 --force-architecture` / `opkg 拒绝强制架构后改用 rootfs 归档` / `回退时下载了 rootfs 归档`。
2. **实现第一版（所有失败都回退归档）后**：`test-regressions` = `45 通过，2 失败`（`失败后 CLI 二进制被回滚` 实际 `BIN-NEW-BROKEN`；`失败后被删除的库文件被回滚` 实际 `<缺失>`）。原因是归档兜底把“升级中途失败”也包成了成功，回滚没有触发。改为按“被拒”分流后回到 `47 通过，0 失败`。
3. **发版前基线**：`test-bypass` = `39 通过，2 失败`（`元素拼接格式不对`、`集合元素为空`）、`test-release` = `44 通过，1 失败`（`.release-request` 断言）、四套件 SKIP（无真实 sing-box）。前者是 `bypass.sh` 的 `printf "%%s"` 转义缺陷（本轮修复），后者是被移除机制的陈旧断言（本轮改契约），SKIP 靠真实内核下跑消除。

未覆盖、必须写明的验证面（`run-all.sh` 自己打印的那句）：真机安装/升级/回滚、真实 rpcd 渲染 ACL、shellcheck（环境没有 `shellcheck`）。本报告不把这三项算作通过。

CI 侧：run #199 的第 6 步 “Run package test suites with the real kernel” success（CI 里用的是固定的真实 sing-box），后续构建与发布步骤全部 success。

---

## 8. 编译是否成功

成功。CI run #199 的第 8~15 步（下载官方 ImmortalWrt 25.12.2 SDK → 编译 EasyProxy → 打包手动安装归档 → 打 ipk → 打三架构内核包 → 汇总 → 写 `KERNEL-VERSIONS` → 校验和）全部 `success`，日志：<https://github.com/bnm188/EasyProxy/actions/runs/44023055587>。

---

## 9. 生成了哪些 IPK、内核包或产物

Release `v0.8.2` 的 12 项资产（Release API 实测，尺寸为字节）：

| 资产 | 大小 |
|---|---|
| `easyproxy-0.8.2-r1.apk` | 57 644 |
| `easyproxy-0.8.2-rootfs.tar.gz` | 54 758 |
| `easyproxy_0.8.2-1_all.ipk` | 55 478 |
| `easyproxy_0.8.2-1_x86_64.ipk` | 55 490 |
| `sing-box_1.14.4_x86_64.ipk` | 27 557 866 |
| `sing-box_1.14.4_aarch64_cortex-a53.ipk` | 24 976 224 |
| `sing-box_1.14.4_arm_cortex-a7_neon-vfpv4.ipk` | 25 329 656 |
| `dae_2.1.2_x86_64.ipk` | 19 290 866 |
| `dae_2.1.2_aarch64_cortex-a53.ipk` | 17 853 480 |
| `dae_2.1.2_arm_cortex-a7_neon-vfpv4.ipk` | 18 371 730 |
| `KERNEL-VERSIONS` | 412 |
| `SHA256SUMS` | 1 054 |

`KERNEL-VERSIONS` 内容（原文）：

```
component   version   upstream
easyproxy   0.8.2     https://github.com/bnm188/EasyProxy
sing-box    1.14.4     SagerNet/sing-box v1.14.4
dae         2.1.2     daeuniverse/dae v2.1.2

architectures: x86_64, aarch64_cortex-a53, arm_cortex-a7_neon-vfpv4
kernel adapter: dae 适配器开发中，运行时分流仍由 sing-box 承担
built from commit: 30c0b0a4797a18712efe96005e0d480acfbcbc3e
built from ref: main
```

下载与校验（本地实做，不是看 artifact）：把 11 个资产 + `SHA256SUMS` 全部从 `https://github.com/bnm188/EasyProxy/releases/download/v0.8.2/` 实下到 `/tmp/v082`，`sha256sum -c SHA256SUMS` → **11/11 OK**。逐资产 `curl -o /dev/null -w '%{http_code}' -L`：`easyproxy_0.8.2-1_all.ipk` / `easyproxy_0.8.2-1_x86_64.ipk` / `easyproxy-0.8.2-rootfs.tar.gz` / `SHA256SUMS` / `KERNEL-VERSIONS` / `sing-box_1.14.4_x86_64.ipk` 全部 `200`。

面板包与归档的实际 SHA256：

```
4dc92eecd33e2f01505f3466c451f8fa500dc82e09c97a27c35940fe17fe541c  easyproxy_0.8.2-1_all.ipk
4dc92eecd33e2f01505f3466c451f8fa500dc82e09c97a27c35940fe17fe541c  (SHA256SUMS 第 3 行)
cb93ed198661e2a13156a9680dcf9d4c51b9836171e136b974183f199e482d7f  easyproxy-0.8.2-rootfs.tar.gz
```

---

## 10. GitHub Commit SHA

- 代码提交：`30c0b0a4797a18712efe96005e0d480acfbcbc3e`（`fix(installer): Kwrt 等只认自身架构的 opkg 也能装上面板`）
- Tag `v0.8.2` → 同一 SHA（`GET /git/ref/tags/v0.8.2` 实测 `object.type=commit`）
- Release `v0.8.2` 的 `target_commitish` = 同一 SHA

---

## 11. 本次遗留问题

1. **真机未验**：修复只经沙箱测试与 CI，未在用户的 Kwrt 25.12-SNAPSHOT 设备上复跑。需要用户重跑 `all.sh | sh`，若仍失败，用新日志定位（现在安装器会把 opkg 的原始报错打出来）。
2. **`Malformed` 根因未定**：合法 `ar` 被某些 opkg 判 malformed 的现象有外部旁证，但未在 Kwrt 上取证；目前靠归档兜底绕过，而不是让 opkg 接受 ipk。
3. **0.8.2 一并发布了一批此前未发版的 bypass 功能**（SSH 菜单第 10 项、总览页 bypass 卡片、`bypass status|on|off|restore`、nft 入口放行）。它们在本轮测试里是绿的，但真机未验；`bypass.sh` 的 `printf` 缺陷正是在本轮发版前被测试拦下的。
4. **发布入口只剩“真 push + PKG_VERSION 递增”**：用 API 令牌推送的提交不会触发工作流（本轮是 `git push` 到 `main`），文档类提交不会发布；这不是缺陷，但需要在文档里保持说明，避免下一次又“只跑 Actions 不发 Release”。
5. **一次性工作流删除后，`main` 上仍可能有历史 run 的红叉**（`d9d.yml` 的 44023053313 / 44023052155），属于历史记录，不可删除，只能说明。
6. `PROJECT-STATUS` 里“HEAD = `e7840ab`、版本 0.8.0”的表述在本轮之前已滞后（0.8.1 曾发布但未同步文档）；本轮一并更新到 0.8.2。
7. 已知未覆盖验证面：真机安装/升级/回滚、真实 rpcd 渲染 ACL、`shellcheck`。
8. 用户在本对话里贴出过 GitHub PAT 明文，建议本轮结束后在 GitHub 设置里 revoke 并重新签发（本报告不复制该令牌内容）。

---

## 12. 下一步计划

1. 用户在 Kwrt 真机上重跑安装；把新输出（尤其 `warning: this opkg rejects Architecture: all ...` 与是否走到 `falling back to the rootfs archive`）回传，决定是否还需要“为 Kwrt 单独产该架构 ipk”或“gzip 口味 ipk”这类更深一层的修法。
2. 若真机确认强制架构可用：把“该架构 ipk”方案彻底搁置，只在文档里保留说明，避免资产膨胀。
3. 回到开发路线：Stage 10（唯一管理入口 `easyproxy-manager.sh`）尚未开始；Stage 11 无缝切换、Stage 12 十个业务分组、Stage 13 测速/订阅、Stage 16 dae 真实运行能力都未开始。
4. 每个阶段仍按本轮流程交付：改代码 → 测试（真内核）→ 构建 → SHA256 → 新版本号 → Tag → 真 Release → 报告 → 实查 Releases 页面。
