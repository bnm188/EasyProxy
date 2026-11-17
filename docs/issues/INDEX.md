# EasyProxy 问题归档

本目录记录真机实测发现的问题。一条问题一个文件，状态分四档：

- `待修复` —— 已确认、已定位，等排期
- `修复中` —— 正在改
- `已修复` —— 已改并有验证证据
- `不修` —— 确认不是缺陷，或环境问题

## 索引

| 编号 | 问题 | 严重度 | 状态 |
|---|---|---|---|
| [ISSUE-001](ISSUE-001-一键安装取到旧版本ipk.md) | 一键安装装到旧版本 ipk（Release 残留旧资产 + 选包取第一个） | 高 | 修复已就绪并验证，未提交、未推送（线上仍是旧逻辑） |
| [ISSUE-002](ISSUE-002-面板NetworkError缺ubus.js.md) | 面板整页 NetworkError：app.js 依赖固件已删除的 ubus.js | 高 | 待修复（0.8.11 / 0.8.12 均复现） |

## 本轮真机安装实测中同时观察到的其他缺陷（待补编号）

以下三条尚未单独建档，先记在这里避免丢失：

1. **dae 的 ipk 被 opkg 判为 Malformed** —— `pkg_init_from_file: Malformed package file ... dae_2.1.2_x86_64.ipk`，我们产出的 ipk 是 gzip-tar 而部分固件 opkg 只认 `!<arch>`，需要按目标固件选择打包格式
2. **dae 的备用 tar.xz 解不开** —— `cannot extract dae-linux-x86_64.tar.xz (this firmware may lack xz support)`，需改用无 xz 依赖的备用渠道或提前探测 xz 能力
3. **sing-box 采纳外部二进制后状态自相矛盾** —— 安装器采纳 `/opt/open-box/bin/sing-box` 成功、uci 也已指向该路径，但汇总仍报 `sing-box not installed (/usr/bin/sing-box)`，校验路径与实际路径不一致

另有一条发布流程问题：

4. **发布脚本通配上传** —— 发布 v0.8.12 时把 `dist/` 里 0.8.11 的 ipk 一起传了，是 ISSUE-001 的诱因，需在发布流程里先清空 `dist/`
