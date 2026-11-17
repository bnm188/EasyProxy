# EasyProxy 问题归档

本目录记录真机实测发现的问题。一条问题一个文件，状态分四档：

- `待修复` —— 已确认、已定位，等排期
- `修复中` —— 正在改
- `已修复` —— 已改并有验证证据
- `不修` —— 确认不是缺陷，或环境问题

## 索引

| 编号 | 问题 | 严重度 | 状态 |
|---|---|---|---|
| [ISSUE-001](ISSUE-001-一键安装取到旧版本ipk.md) | 一键安装装到旧版本 ipk（Release 残留旧资产 + 选包取第一个） | 高 | **已修复并发布**（0.8.13；install.sh 按版本号取最新，`dist/*.ipk` 移出版本控制） |
| [ISSUE-002](ISSUE-002-面板NetworkError缺ubus.js.md) | 面板整页 NetworkError：app.js 依赖固件已删除的 ubus.js | 高 | **已修复并发布**（0.8.13；随包自带 `easyproxy.ubus`，真机 ubus.js 404→200） |
| [ISSUE-003](ISSUE-003-安装器汇总误判已采纳的sing-box为未安装.md) | 安装器汇总把已采纳的 sing-box 判成 not installed | 高 | `待修复`（真机复现：同一次安装，`status` 说 available，汇总说 not installed） |
| [ISSUE-004](ISSUE-004-dae的tar.xz在无xz固件上解压失败.md) | dae 的 tar.xz 在无 xz 固件上解压失败，未回落 ipk | 中 | `待修复`（真机原文：`cannot extract … (this firmware may lack xz support)`） |
| [ISSUE-005](ISSUE-005-一键安装后规则集缺失导致无法代理.md) | 一键安装后规则集缺失，路由退化为 direct only | 高 | `待修复`（真机 `status`：`Rule sets: missing` / `foreign sites unreachable`） |

## 0.8.13 之后仍然存在的缺陷（待补编号）

1. **同名节点导致配置生成失败** —— 拉两次订阅即 `duplicate outbound tag`，全站断网，P0
2. **`ss://` base64url 链接导不进** —— 报 `ss userinfo is not base64`，P0
3. **测速超时误判可达** —— 死地址也报 `reachable 3019 ms`，P1
4. **dae 的 ipk 被 opkg 判为 Malformed** —— 我们产出的是 gzip-tar，部分固件只认 `!<arch>`（与 ISSUE-004 是两个不同问题）
5. **订阅去重 / 定时更新缺失**，**面板节点启停缺失**，**节点导出无按钮**

## 2026-11-18 真机共存安装（Open-Box 运行中）留下的其他观察

- `ubus list` 在 `opkg remove easyproxy` 之后仍能看到 `easyproxy` 对象：rpcd 内存未刷新，卸载不彻底（不重启 rpcd 就一直残留）
- `easyproxy stop` 在未运行时输出 `EasyProxy is not running.`，行为正确
- 卸载后 `/www/luci-static/resources/view/easyproxy/` 目录保留但内容已清空（空目录残留）
- Open-Box 全程未被触碰：7853 / 7891 / 9095 / 7854 四个监听端口在安装与卸载前后完全一致

## 已闭环（无需再跟）

- 发布夹带旧包：`dist/*.ipk` 已 `git rm --cached` 并写入 `.gitignore`，本次发布只有一个资产
- 旧版本残留：0.8.12 及以下的 Release、tag、过程报告已全部清除，线上只剩 v0.8.13
