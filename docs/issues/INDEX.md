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

## 0.8.13 之后仍然存在的缺陷（待补编号）

1. **同名节点导致配置生成失败** —— 拉两次订阅即 `duplicate outbound tag`，全站断网，P0
2. **`ss://` base64url 链接导不进** —— 报 `ss userinfo is not base64`，P0
3. **测速超时误判可达** —— 死地址也报 `reachable 3019 ms`，P1
4. **dae 的 ipk 被 opkg 判为 Malformed** —— 我们产出的是 gzip-tar，部分固件只认 `!<arch>`
5. **dae 的备用 tar.xz 解不开** —— 固件缺 xz 支持
6. **sing-box 采纳外部二进制后状态自相矛盾** —— uci 已指向 `/opt/open-box/bin/sing-box`，汇总仍报 not installed
7. **订阅去重 / 定时更新缺失**，**面板节点启停缺失**，**节点导出无按钮**

## 已闭环（无需再跟）

- 发布夹带旧包：`dist/*.ipk` 已 `git rm --cached` 并写入 `.gitignore`，本次发布只有一个资产
- 旧版本残留：0.8.12 及以下的 Release、tag、过程报告已全部清除，线上只剩 v0.8.13
