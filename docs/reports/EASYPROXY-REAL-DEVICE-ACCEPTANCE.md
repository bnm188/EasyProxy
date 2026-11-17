# EasyProxy 真机验收报告（0.8.9 基线）

真机：Kwrt 25.12-SNAPSHOT x86_64（i7-8086K / 1950MB / 面板 http://10.10.10.13/cgi-bin/luci/admin/services/easyproxy）
内核：sing-box 1.14.4-openbox-45（/opt/open-box/bin/sing-box）
被测包：easyproxy_0.8.9-1_x86_64.ipk，sha256 5d7dd6e34f3486ddd779447c0b92445e89af865e6665ba5fa65ace899fd76b3b
实测日志：Windows 侧 acc1..acc11.log（经 paramiko 下发 sh 到路由器执行）

## 24 项验收结果

| # | 项目 | 状态 | 证据 |
|---|---|---|---|
| 1 | ipk 安装与校验 | PASS | sha256 与 CDN 一致；`Installing easyproxy (0.8.9-1)` / `Configuring easyproxy.` |
| 2 | 面板与菜单资源 | PASS | 未登录 403（正常）；app.js 51034B 可取；menu.d / acl.d 就位 |
| 3 | ubus 桥（10 个方法） | PASS | `ubus call easyproxy run '{"payload":"[\"status\"]"}'` 全部 code=0 返回真实数据 |
| 4 | 节点导入 / 启停 / 导出 / 删除 | PASS | 去重识别已存在；disable→enabled=0；export 长链接；`Deleted @node[1]` |
| 5 | 订阅导入 | PASS | 真实 HTTP 源：`imported: 3, skipped: 0, failed: 0` |
| 6 | 订阅幂等与每日任务 | PASS | 二次导入 `imported: 0, skipped: 3`；cron `37 4 * * * ... subscribe --update` 写入并在重启后存活 |
| 7 | 节点测速 | 部分 | 可达/不可达判定正确（reachable 1/1、失效节点 0/1）；延迟显示精度不足（latency_ms 0） |
| 8 | 配置生成与校验 | PASS | 8 个出站 tag、2267B；`validate` 输出 `Configuration values are valid.` |
| 9 | 引擎启停与出网 | PASS | stop→start→7890 LISTEN→`outbound/shadowsocks[日本Z01]` 日志、youtube 200 |
| 10 | dae 内核 | 诚实降级 | 真机无 /usr/bin/dae，`start` 明确拒绝并说明 dev 状态 |
| 11 | 国内直连分流 | PASS | baidu/taobao 200，日志 `outbound/direct` |
| 12 | 平台分流 | PASS | YouTube 200 / Netflix 302 / TikTok 200；domain_suffix 覆盖 yt/netflix/tiktok |
| 13 | DNS 分流 | PASS | 百度解析国内 IP；dns-local 223.5.5.5；53 端口监听 |
| 14 | 透明代理 | 部分 | apply/幂等/remove 均 rc=0；nft 表、fwmark 1、table 100、local default dev lo、7891 LISTEN、audit 全 ok；从 LAN 侧真 tproxy 命中未取得日志证据（见遗留） |
| 15 | 规则管理 | PASS | add domain-suffix rc=0；按规格 del 成功；不匹配报 `no rule matches` rc=1 |
| 16 | 规则集 | PASS | geosite-cn 57617B / geoip-cn 34259B，rc=0 |
| 17 | 备份 / 恢复 | PASS | 备份 tar.gz 生成；改 listen_port 后 restore 复原；.before-restore 留存 |
| 18 | 恢复默认 / 重置 | PASS | engine=sing-box、binary 自愈到 /opt/open-box/bin/sing-box、config generate rc=0、doctor 前 5 项全 ok |
| 19 | 更新检查 | PASS | `current: 0.8.9 / latest: 0.8.8 / already up to date` |
| 20 | 更新与回滚 | 部分 | 0.8.7→`update apply` 触发归档后**误判校验失败自动回滚**（缺陷已修，见下）；归档与 rollback 通路本身 PASS |
| 21 | 流量统计 | PASS | 两次采样 rx 222796326→222802261→222802456 递进 |
| 22 | 日志 / 诊断包 | PASS | 真实 sing-box 记录；diag 20653B |
| 23 | 重启自动恢复 | PASS | reboot 后 83s：0.8.9、enabled=1、引擎自动起（pid 3910 up 52s）、7890 监听、直连 200、cron 存活、doctor 全 ok |
| 24 | 节点失效 / 网络中断 | PASS | 端口改 1 后 `unreachable 0/1`；start 不崩；经代理失败、直连 200；恢复端口后代理恢复 |

## 本轮真机新发现并已修复的缺陷

### 1. 更新校验自匹配（致命，阻断全部升级）
`update_verify_install` 从 `usr/sbin/easyproxy` 里用 sed 提取 `EP_VERSION="..."`，但该文件自身没有 EP_VERSION 定义——sed 匹配到的是它自己那一行，得到 `\([^`，于是任何真实升级都判"校验失败"并自动回滚。
真机证据：0.8.7 → `update: installed \([^, expected 0.8.8` → `rolling back to 0.8.7`。
修复：改从 `usr/lib/easyproxy/common.sh`（版本号唯一真源）读取，并加数字格式校验。
测试：test-release.sh 新增 3 条断言，RED（2 失败）→ GREEN（49 通过 0 失败）。

## 已撤销的误判（如实记录）

- **"坏配置下 start 假成功"**：早前用 `ps w | grep` 判定进程数得到 0，原因是 busybox ps 截断长命令行。改用 /proc/*/cmdline 精确统计后：坏配置被 `config generate` 覆盖为合法配置，sing-box 实际启动（pid 62802）、7890 监听、出网正常。不是缺陷。
- **"[14] apply 返回 rc=1"**：根因是先前引擎未运行导致提前拒绝，且脚本顺序把 stop 输出误当 apply 结果。有节点 + 引擎运行时 apply1/apply2 均 rc=0。

## 必须知晓的操作风险（已实测）

- `opkg install --force-reinstall` 会重置 `/etc/config/easyproxy`（本次即因此清空节点表，旧配置被留成 `easyproxy-opkg`）。正常升级请用 `easyproxy update apply` 或 `opkg install <新版本 ipk>`（不带 --force-reinstall）。
- `config reset` 会把 `main.enabled` 回 0 并清空节点表，属既有语义，已在医生输出与文档中说明。

## 遗留（本轮未取得证据，如实列出）

1. **[14] 透明代理的端到端捕获证据**：nft 规则、路由表、7891 监听、audit 全通过，且从 Windows（同 LAN）经 br-lan 访问 google204/ipify 成功；但清空日志后 sing-box 未再写入新日志，未取得 `inbound/tproxy[tproxy-in]` 命中记录。下一步：不清空日志，用 `nft` counter 计 prerouting 命中数 + 从 LAN 客户端发起，再回读。
2. **[7] 测速延迟精度**：`latency_ms` 恒为 0，需改用 curl `%{time_connect}`。
3. **[20] 升级成功路径**：修复后需出新包并在真机复验 0.8.9→新版本 的成功升级（本轮只验证到"归档 + 回滚"通路）。
4. **D 级 #33 面板内 SSH 远程管理**：仍未实现，属范围外，未在面板提供入口。
5. **直连/代理 IP 相同**：该路由器同时运行第三方 Open-Box 实例且本地可直连 Google，出口 IP 无法用于区分；代理生效证据以 sing-box 自身 `outbound/shadowsocks[日本Z01]` 日志与 7890 端口归属为准。
