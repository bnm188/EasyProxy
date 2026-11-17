# ISSUE-001 一键安装装到了旧版本 ipk（Release 残留旧资产 + 选包取第一个）

- 状态：待修复（已定方案 B）
- 发现时间：2026-11-18
- 发现方式：真机干净环境（Vmware 里的 Kwrt 25.12-SNAPSHOT，x86_64）跑一键安装
- 严重度：高（所有用户一键安装拿到的都是带缺陷的旧包）

## 现象

真机执行一键安装（`sh /tmp/ep.sh install`）后：

```
downloading easyproxy_0.8.11-1_x86_64.ipk
sha256 ok: easyproxy_0.8.11-1_x86_64.ipk
installing with opkg
...
components:
  easyproxy  0.8.11-1  (/usr/sbin/easyproxy)
```

`/usr/sbin/easyproxy version` 返回 `0.8.11`，但仓库代码已经是 `0.8.12`。

## 排除掉的可能

| 怀疑点 | 实测 | 结论 |
|---|---|---|
| 仓库版本没升 | `package/easyproxy/Makefile` `PKG_VERSION:=0.8.12`；`common.sh` `EP_VERSION="0.8.12"` | 不是 |
| GitHub latest 指向错了 | API `releases/latest` → `tag_name: v0.8.12`，`draft:false`、`prerelease:false` | 不是 |
| raw Makefile 兜底版本旧 | raw 上 `PKG_VERSION:=0.8.12` | 不是 |

## 根因

v0.8.12 这个 Release 的资产列表里，**同时挂着 0.8.11 的 ipk**：

```
https://github.com/bnm188/EasyProxy/releases/download/v0.8.12/dae_2.1.2_aarch64_cortex-a53.ipk
https://github.com/bnm188/EasyProxy/releases/download/v0.8.12/dae_2.1.2_x86_64.ipk
https://github.com/bnm188/EasyProxy/releases/download/v0.8.12/easyproxy_0.8.11-1_x86_64.ipk   ← 残留
https://github.com/bnm188/EasyProxy/releases/download/v0.8.12/easyproxy_0.8.12-1_all.ipk
https://github.com/bnm188/EasyProxy/releases/download/v0.8.12/easyproxy_0.8.12-1_x86_64.ipk
```

而 `scripts/install.sh` 选包用的是「正则匹配 + `head -1`」：

```sh
# scripts/install.sh:1126
[ -n "$arch" ] && url="$(asset_from_api "easyproxy_[0-9][0-9a-zA-Z._-]*_${arch}\.ipk$" || true)"
```

`asset_from_api()` 内部 `grep -E "$pattern" | head -1`，不比较版本号。0.8.11 在 JSON 里排在 0.8.12 前面，于是被选中。

同源问题还存在于 `release_component_version()`（第 385 行，升级判定用）——它也是 `head -1`，会拿到旧版本号。

残留资产怎么来的：发布 v0.8.12 时发布脚本用通配把 `dist/` 里上一次构建的 ipk 一起上传了。

## 影响面

- 所有一键安装用户装到 0.8.11（该版本已知缺陷：升级时 `--exclude` 被 busybox 忽略，升级会覆盖用户配置）
- 升级路径拿到的目标版本号也可能是旧的，导致"已是最新"误判

## 修复方案（用户选定 B）

1. `scripts/install.sh` 新增 `asset_newest_from_api()`：同一 pattern 匹配到多个资产时，解析文件名里的版本号做数值比较，取最大版本
2. easyproxy 的四处选包调用（1126 / 1128 / 1138 / 1152）和 `release_component_version()` 的 easyproxy 分支改用该函数
3. 发布流程另开一条待办：发布前清空 `dist/`，只上传本次构建产物（避免再次残留）

## 需要同步处理的遗留资产

v0.8.12 Release 里的 `easyproxy_0.8.11-1_x86_64.ipk` 仍在线上。方案 A（删除该资产）用户本轮未采纳，代码侧修复后不会再被选中，但资产本身仍存在。

## 当前状态（2026-11-18）

代码修复**已完成并验证，但未提交、未推送，线上仍是有缺陷的旧逻辑**。

### 已落地的改动（仅本机工作树）

`scripts/install.sh`：

1. 新增 `asset_newest_from_api()` —— 同一 pattern 匹配到多个资产时，解析文件名里的版本号做数值比较，返回最大版本，不依赖 JSON 中的出现顺序
2. 四处 easyproxy 选包调用改用它：`_${arch}.ipk` 分支、`_all.ipk` 分支、架构退回避让分支、下载失败后改用备用 `_all` 包
3. `release_component_version()` 的 easyproxy 分支也改为取最大版本（原来同样 `head -1`，升级时会拿旧版本号导致"已是最新"误判）

`tests/test-install-scripts.sh`：

- 新增 fixture `api-stale.json`（0.9.8 在前、0.9.9 在后，复刻真实 API 返回顺序）与 `SHA256SUMS.stale`
- 新增 3 条断言：安装仍成功、下载的是 0.9.9、不得下载 0.9.8

### 验证证据

- TDD 先 RED：`FAIL 下载的是版本号最大的 0.9.9` / `FAIL 不应下载旧包 0.9.8`，`182 通过 2 失败`
- 改完 GREEN：`test-install-scripts` **184 通过 0 失败**
- 全量回归：16 个套件 **869 通过 0 失败**，SKIP 仍为 test-engine / test-routing / test-runtime / test-transparent

### 待执行（本轮按用户要求暂停，不做）

| # | 动作 | 影响 |
|---|---|---|
| 1 | `git commit` + `git push` 到 main | 入口脚本按 `raw.githubusercontent.com/.../main/scripts` 取 install.sh，**推送即生效，不需要发新版 Release** |
| 2 | 删除 v0.8.12 Release 里的 `easyproxy_0.8.11-1_x86_64.ipk` 资产 | 清掉线上残留，双保险 |
| 3 | 真机重跑一次一键安装复验 | 确认装到 0.8.12 而不是 0.8.11 |
| 4 | 发布流程加"发布前清空 dist/" | 防止再次残留，属另一条待办 |

**注意**：第 1 项一旦执行，线上行为立刻改变，不只是代码存档。
