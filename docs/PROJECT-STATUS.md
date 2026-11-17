# EasyProxy 项目总进度

更新日期：2026-11-18
当前版本：**0.8.13**（已发布，2 资产：ipk + SHA256SUMS）
真机：Kwrt 25.12-SNAPSHOT / x86_64 / LuCI 27.307.53063，面板 `http://10.10.10.13/cgi-bin/luci/admin/services/easyproxy`

本文件只回答一个问题：**哪些功能是真的能用，哪些只是"代码里在"。**
历史版本的验收与审计记录已按要求清除，本文件从 0.8.13 重新起算；活缺陷见 [`docs/issues/`](issues/INDEX.md)。

---

## 一、0.8.13 修掉的三件事（均有实现与验证）

| 问题 | 根因 | 处理 |
|---|---|---|
| 面板整页 NetworkError | 新版 LuCI（27.x）不再发布 `/luci-static/resources/ubus.js`，改用 `rpc.js`，而 `app.js` 写死 `'require ubus'` → 404 → 内容区整页失败 | 新增随包发布的 `easyproxy/ubus.js`，`app.js` 改为 `'require easyproxy.ubus as ubus'`；真机 `ubus.js` 由 404 变 200 |
| 一键安装装到旧版本 | 发布里残留上一次的 ipk 时，`asset_from_api()` 用 `grep + head -1` 取到旧的 | 新增 `asset_newest_from_api()`，按文件名版本号取最大；`release_component_version()` 同步 |
| 发布夹带旧包 | `dist/*.ipk` 一直被 git 跟踪，发版时整目录上传 | `git rm --cached` 并写入 `.gitignore` |

真机验证（0.8.12 → 0.8.13 实装）：`opkg` 升级成功、`easyproxy version` = 0.8.13、
`/luci-static/resources/easyproxy/ubus.js` 200、`ubus call easyproxy run {"payload":["version"]}`
→ `{"code":0,"stdout":"0.8.13\n","stderr":""}`。

---

## 二、当前仍然存在的缺陷（未修）

| 项 | 严重度 | 说明 |
|---|---|---|
| 同名节点导致配置生成失败 | P0 | 拉两次订阅即复现，`duplicate outbound tag`，全站断网 |
| `ss://` base64url 链接 | P0 | 报 `ss userinfo is not base64`，主流机场格式导不进 |
| 节点测速超时误判可达 | P1 | 死地址也报 `reachable 3019 ms` |
| 订阅去重 / 定时更新 | P1 | 无去重、无 cron、无增量 |
| 面板节点启用 / 停用 | P1 | 只显示状态 |
| 节点导出分享链接 | P2 | CLI 有 `node export`，面板无按钮 |
| dae 内核 | P2 | 适配器标"开发中"，`easyproxy start` 会拒绝 |
| 远程 SSH 管理 | P2 | 面板无此功能 |
| 流量统计 | P2 | 接口写死 `br-lan`，取不到时静默画 0 |

---

## 三、代码在、但缺真机证据的部分

以下在沙箱可跑通，真机尚未逐项留证：透明代理开关与入口绕过（需 nftables）、内核停止/重启/故障自动恢复（需 procd）、规则集更新、配置备份/恢复/重置、日志轮转、一键更新应用与失败回滚、节点测速的 nc 分支、从文件批量导入。

**判据**：没有真机输出，不写"已实现"。

---

## 四、版本与发布现状

- 线上只保留 **v0.8.13** 一个 Release 与一个 tag，0.8.12 及以下全部清除
- 发版规则：`PKG_VERSION` 高于最新 Release 即自动构建发布；同号重复发布直接失败，不覆盖旧资产
- 测试：**873 通过 / 0 失败**（16 套件，4 套因缺真内核 SKIP），`tests/run-all.sh` 是唯一计数来源
- 构建产物一律不入库（`dist/*.ipk` 已忽略）

---

## 五、下一阶段顺序

1. 同名节点去重（P0，会断网）
2. `ss://` base64url 解析（P0，用户第一眼就撞）
3. 测速判定修正（P1）
4. 订阅去重 + 节点启停开关（P1）
5. 逐项补真机证据

新增功能继续暂停，直到 P0 两项关闭。
