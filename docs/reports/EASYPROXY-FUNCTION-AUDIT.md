# EasyProxy 功能审计报告

审计对象：EasyProxy 0.8.8（LuCI 面板 + 命令行 + 内核运行时）
审计时间：2026-11-17
审计方式：**真实运行取证**，不是读代码、不是跑单元测试、不是看 CI 绿灯。

---

## 一、审计口径（先说清楚什么叫"实现"）

本报告的判定标准，只有一条：**能不能看到它在跑并产生副作用**。

| 状态 | 定义 | 必须有的证据 |
|---|---|---|
| **A** | 真正实现 | 在本报告列出的环境里实际执行过，有命令输出 / 生成物 / 端口 / 网络结果 |
| **B** | 代码实现，未经真实运行验证 | 代码路径完整、入口存在，但本次审计环境不具备验证条件（无 nftables / 无 procd / 无真机） |
| **C** | 部分实现或仅界面 | 界面有、按钮有，但后端缺环节（无落点、无回写、无法启用） |
| **D** | 没有实现 | 只有占位、只有注释、只有"开发中"字样 |

明确不采用的判定依据：

- 按钮存在 → 不算实现
- 函数存在 → 不算实现
- 配置文件存在 → 不算实现
- GitHub Actions 编译成功 → 不算实现
- 单元测试通过 → 只作旁证，**不作结论**

---

## 二、审计环境与限制（必须先读，影响所有结论的置信度）

| 环境 | 用途 | 能力 | 局限 |
|---|---|---|---|
| 本地审计沙箱 | 主力取证 | x86_64 Linux，EasyProxy CLI 真实执行，uci 用真实键值存储，引擎用**真 sing-box 1.14.4 二进制**（`/tmp/ep-assets/kx/usr/bin/sing-box`），可以真的起进程、真的监听端口、真的走 HTTP | 不是 OpenWrt：没有 nftables、没有 procd、没有 rpcd、没有 /etc/config 目录、非 root |
| 真机 Kwrt 25.12-SNAPSHOT x86_64（10.10.10.13） | 装机与面板验证 | 真实 OpenWrt 环境，真实 opkg、真实 LuCI、真实 nftables | 审计方无 SSH 通道，全部依赖操作者回贴，只能覆盖"已发生的动作" |

因此：**凡标注 A 且属于"内核 / 节点 / 订阅 / 规则 / 配置生成 / 更新检查"的项，证据来自真 sing-box 在本地沙箱的真实运行，不是纯静态检查；凡涉及 nftables、procd、rpcd 的项，本环境无法产出 A 级证据，一律降为 B。**

---

## 三、真实取证记录（原始输出，可复现）

全部命令在沙箱内执行，`EP` 指向包内 `usr/sbin/easyproxy`。

### 3.1 节点导入（三种协议）

```
$ easyproxy node add "ss://<base64(aes-256-gcm:pw1)>@203.0.113.10:8388#香港-hk01"
Imported @node[0] as 香港-hk01
$ easyproxy node add "vmess://<base64 JSON>"
Imported @node[1] as us-01
$ easyproxy node add "vless://<uuid>@203.0.113.30:443?security=tls&sni=us.example.com#tiktok-jp09"
Imported @node[2] as tiktok-jp09
```

### 3.2 地区分组

```
NODE            TYPE          SERVER:PORT            REGION  GROUP
香港-hk01       shadowsocks   203.0.113.10:8388      香港    auto-hk
us-01           vmess         203.0.113.20:443       美国    auto-us
tiktok-jp09     vless         203.0.113.30:443       日本    auto-jp
```

### 3.3 配置生成 + 平台分流 + 真内核校验

```
$ easyproxy config generate
Default route: proxy
Routing mode: split (China direct, others proxied)
Engine validation: passed

配置内容检查：
platform hits: 15        ← youtube/netflix/tiktok 域名真实写进内核配置
outbounds: shadowsocks, vmess, vless, urltest ×3, selector, direct
dns keys: servers, rules, final

$ sing-box check -c <生成的配置>
check rc=0               ← 真内核认可
```

### 3.4 内核真实启动 + 真实出网

```
$ sing-box run -c <配置副本，cache_file 改到 /tmp>
LISTEN 0 4096 127.0.0.1:7890 0.0.0.0:*      ← 端口真实监听
$ curl -x http://127.0.0.1:7890 https://www.gstatic.com/generate_204
http_code=204                                ← 代理链路真实通
日志：outbound/vmess[us-01]: outbound connection to www.gstatic.com:80
```

> 注：配置里 `experimental.cache_file` 写死 `/etc/easyproxy/cache.db`，该目录不存在时内核直接 FATAL 退出。真机由安装脚本 `mkdir -p /etc/easyproxy` 保证存在（scripts/install.sh:118），所以真机不受影响；但这是**硬依赖**，任何清理 `/etc/easyproxy` 的操作都会让内核起不来。

### 3.5 订阅拉取（真实 HTTP，两种格式）

```
$ easyproxy subscribe http://127.0.0.1:18080/list.txt     # 明文每行一条
imported: 2, failed: 0
$ easyproxy subscribe http://127.0.0.1:18080/b64list      # 整体 base64（v2ray 机场格式）
imported: 2, failed: 0
```

### 3.6 规则管理

```
$ easyproxy rule add domain:example.net:proxy
$ easyproxy rule add ip:1.2.3.4:direct
$ easyproxy rule list
#   TYPE     VALUE          OUTBOUND
1   domain   example.net    proxy
2   ip       1.2.3.4        direct
```

### 3.7 更新检查（真实 GitHub API）

```
$ easyproxy update check
current: 0.8.8
latest:  0.8.8
already up to date
```

### 3.8 失败取证（这些是缺陷，不是通过）

```
$ easyproxy config generate        # 两次导入同一订阅后
Config generation failed: engine rejected the generated config:
FATAL decode config: duplicate outbound/endpoint tag: sub-us2
```

```
$ easyproxy node test              # 三个 TEST-NET 不可达地址
香港-hk01   203.0.113.10:8388   reachable   3019 ms
us-01       203.0.113.20:443    reachable   3018 ms
tiktok-jp09 203.0.113.30:443    reachable   3017 ms
Reachable: 3/3                    ← 全是假的
```

```
$ easyproxy traffic --json
{"ok":false,"iface":"br-lan","rx":0,"tx":0}
```

---

## 四、逐项功能审计表

列说明：**页面** = LuCI 菜单页；**前端** = `www/luci-static/resources/view/easyproxy/*.js` 或 `easyproxy/app.js`；**后台** = `usr/sbin/easyproxy` / `usr/lib/easyproxy/*.sh`；**入口** = 实际执行的东西。

### 4.1 节点（nodes.js / pageNodes）

| # | 功能 | 页面 | 前端 | 后台 | 实际执行入口 | 实现情况 | 状态 | 测试方法 | 测试结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | ss / vmess / vless 链接导入 | 节点管理 | nodes.js → app.js:pageNodes(473) `run(['node','import'/'...'])` | node.sh `ep_node_parse`、easyproxy `cmd_node_add` | `easyproxy node add <link>` | 三种协议解析真实，uci 落点正确 | **A** | 沙箱内导入三条并读 uci | 3/3 成功，type/server/method/端口正确 | `ss://` 的 **base64url**（`-` `_`、无 padding）仍失败：`ss userinfo is not base64`（node.sh:173 + `ep_b64_decode`只认标准 base64） |
| 2 | 从文件批量导入 | 节点管理 | app.js:485 `run(['node','import',path])` | 同上 | `easyproxy node import <file>` | 路径真实，逐行调用 add | **B** | 未在沙箱跑文件导入 | — | 未验证 |
| 3 | 删除节点 | 节点管理 | app.js:447 `run(['node','del', section])` | `cmd_node_del` → uci delete | `easyproxy node del <name>` | 真实删除，uci 段消失 | **A** | 沙箱删除 sub-hk2 | 节点从列表消失 | 同名节点会被一次全删（按名称匹配） |
| 4 | 导出分享链接 | 节点管理 | 无按钮 | node.sh `cmd_node_export` | `easyproxy node export` | 命令行有，**面板无入口** | **C** | 读前端代码 | 面板不存在该按钮 | 界面缺失 |
| 5 | 启用 / 停用节点 | 节点管理 | app.js:433 仅**显示** span「启用/停用」 | uci `enabled` 字段被 config 生成读取 | 无写入口 | 只能看，不能改 | **C** | 读前端 | 无 switch、无 uci 写入调用 | 面板无法启用停用一个节点 |
| 6 | 节点测速 | 节点管理 | app.js:435 `cliJson(['node','test'])` | common.sh `ep_tcp_probe`（nc 优先，curl 兜底） | `easyproxy node test` | 有实现，但**判定错误** | **C** | 对三个不可路由地址实测 | 3/3 报 `reachable 301x ms`（实为 3 秒超时） | curl 分支只把退出码 7 当不可达，**超时(28)被判可达**，延迟=超时值 |
| 7 | 一键测速（全部/单个） | 节点管理 | app.js:494 / 435 | 同 #6 | 同 #6 | 同 #6 | **C** | 同 #6 | 同 #6 | 同 #6 |

### 4.2 订阅（subscription.js / pageSubscription）

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 8 | 拉取并导入订阅 | 订阅管理 | app.js:515 `run(['subscribe', url])` | subscribe.sh（curl/wget → 判 base64 → 逐行 add） | `easyproxy subscribe <url>` | 真实下载 + 真实导入 | **A** | 本地 HTTP 服务，明文与整体 base64 各一次 | 各 `imported: 2, failed: 0` | 无去重：同一订阅拉两次 → 同名节点 → 见 #9 |
| 9 | 订阅更新（定时/增量） | 订阅管理 | 无 | 无 | 无 | **不存在** | **D** | 读前端与后台 | 无 cron、无 update 命令 | 订阅只能手动整份重拉，且重复会污染节点表 |
| 10 | 订阅去重 | — | 无 | 无 | 无 | **不存在** | **D** | 实测两次导入 | 出现重复 `sub-hk2`/`sub-us2` | **直接导致配置生成失败**（见 #17） |

### 4.3 分流与 DNS（split.js / dns.js）

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 11 | YouTube 独立分流 | 智能分流 | app.js:556 switch + saveUci `routing.platform_youtube` | config.sh:250 `ep_platform_rule_line youtube ...` | `config generate` 写进 route.rules | 真实落点 | **A** | 生成配置后扫域名 | 15 条平台域名命中配置 | 开关写 uci 真实，但需点「保存并重生成」才生效 |
| 12 | Netflix 独立分流 | 智能分流 | app.js:557 | config.sh:252 | 同上 | 真实落点 | **A** | 同上 | 命中 nflx*.net / netflix.* | 同 #11 |
| 13 | TikTok 独立分流 | 智能分流 | app.js:558 | config.sh:255 | 同上 | 真实落点 | **A** | 同上 | 命中 tiktok*.com / byteoversea / muscdn | 同 #11 |
| 14 | 大陆直连（锁定） | 智能分流 | 只读 tile | config.sh + validate 锁死 `china_policy=direct` | `config generate` | 真实，且不可改 | **A** | 生成配置 | `Routing mode: split (China direct…)`、validate 拒绝 proxy | 规则集缺失时整机直连（fail-closed），需在真机确认规则集能下载 |
| 15 | DNS 分流 / 国内直连 | DNS 设置 | app.js:655 saveUci + `config generate` | config.sh 生成 dns 段 | `config generate` | 真实 | **A** | 生成配置 | `dns: servers / rules / final` 齐全 | 未验证解析效果（需真机 + 真节点） |
| 16 | 内网保护 | 智能分流 | 只读 | config.sh 私有网段 + lan 集合 | 生成配置 | 真实 | **A** | 生成配置 | 私有网段规则在 route 中 | 不可关闭（设计如此） |

### 4.4 内核（engines.js / overview.js）

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 17 | 配置生成 | 多页触发 | app.js:365/575/656 `run(['config','generate'])` | config.sh `ep_config_build` + 适配器 | `easyproxy config generate` | 真实，且**调用内核自校验** | **A** | 沙箱生成 + 真内核 check | 正常节点集：`Engine validation: passed`、`check rc=0` | **同名节点直接失败**：`duplicate outbound/endpoint tag` → 整份配置不可用 → 代理起不来 |
| 18 | sing-box 启动 | 运行总览 | app.js:359 `run(['restart'])` | `cmd_start`：校验 enabled/engine/binary → 生成配置 → 起进程 | `easyproxy start` | 真实（代码路径完整，本地以真内核直接起） | **A**（本地内核）/ **B**（经 procd 的真机路径） | 真内核 run + ss + curl | 7890 监听、HTTP 204 | 依赖 `/etc/easyproxy` 目录；procd 拉起未在本环境验证 |
| 19 | 停止 / 重启 | 运行总览 | app.js:359/969 | `cmd_stop`（先撤透明代理再 kill）、`cmd_restart` | `easyproxy stop/restart` | 代码真实 | **B** | 读代码 | — | 未实测（本环境无 init.d/procd） |
| 20 | 内核切换 | 内核管理 | app.js:624 `saveEngine` | `main.engine` + `ep_engine_stability` | `easyproxy engine` | 只有 sing-box 可选 | **C** | 读前端 + CLI | 选 dae 被前端直接拦下 | 实质是单内核系统 |
| 21 | 内核故障恢复 | 运行总览 | 无独立入口 | init.d + procd respawn | `/etc/init.d/easyproxy` | 代码存在 | **B** | 读代码 | — | 未验证：配置坏掉时是否会无限重启 |
| 22 | 内核健康检查 | 内核管理 | app.js:638 `run(['engine','health'])` | common.sh `ep_engine_health` | `easyproxy engine health` | 真实（binary/config/runtime/port 四项） | **B** | 未跑（需真机运行时） | — | 值得在真机跑一次作为验收项 |
| 23 | 内核版本读取 | 内核管理 | app.js:633 | `ep_engine_version` | `easyproxy engine version` | 真实 | **A** | 沙箱 | 输出 `sing-box version 1.14.4` | — |

### 4.5 dae

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 24 | dae 内核运行 | 内核管理 | app.js:94 直接拒绝 | adapters/dae.sh **FRAME ONLY**、`ep_engine_dev_reason` | 无 | **没有实现**，只有骨架 + 明确的"开发中" | **D** | 读适配器 + CLI | `easyproxy start` 对 dae 返回 2 并打印开发中原因 | 发布页/README 若暗示支持 dae，属**过度承诺**，需修文案 |

### 4.6 规则（rules.js）

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 25 | 自定义规则增删查 | 规则管理 | app.js:681/711 `run(['rule',...])` | `cmd_rule_add/del/list` → uci | `easyproxy rule ...` | 真实 | **A** | 沙箱 add 两条 + list | 列表正确显示两条 | 序号从 0 起，面板显示从 1 起，删除时按 index 需注意（实测 `rule del 0` 报 `no rule #0`） |
| 26 | 规则写进内核配置 | 规则管理 → 生成 | `config generate` | config.sh 把 uci 规则转 route.rules | 同上 | 真实，但受 #17 阻断 | **B** | 同 #17 | 配置生成失败时规则无法验证落点 | 修掉重名问题后需复验 |
| 27 | 规则集更新 | 规则管理 | app.js:718 `run(['ruleset','update'])` | `cmd_ruleset_update` 下载 srs | `easyproxy ruleset update` | 代码真实 | **B** | 未跑（需外网 + 真机路径） | — | 需在真机验证：下载失败时 fail-closed 是否真的只直连 |
| 28 | 规则集完整性检查 | 规则管理 | app.js:723 | `cmd_ruleset_verify` | `easyproxy ruleset verify` | 代码真实 | **B** | 未跑 | — | 同 #27 |

### 4.7 透明代理 / 绕过

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 29 | 透明代理开启/关闭 | 连接设置 | app.js:370 `run(['transparent','apply'/'remove'])` | transparent.sh（nftables + 策略路由 + tproxy） | `easyproxy transparent apply` | 代码完整，本环境**无 nft** | **B** | 本机 `command -v nft` 为空 | 无法取证 | 必须在真机验收：nft 规则、mark、IPv6 策略、audit 三方一致 |
| 30 | 入口绕过（国内流量不进内核） | 连接设置 | app.js:398 `bypass restore` | bypass.sh | `easyproxy bypass on/off` | 代码完整 | **B** | 同上 | — | 同上 |
| 31 | 透明代理审计 | 无面板入口 | — | `cmd_transparent audit` | `easyproxy transparent audit` | CLI 真实 | **B** | 未跑 | — | 面板应加一个"审计"按钮，否则用户无法自检 |

### 4.8 安装 / 运维 / 更新

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 32 | SSH 一键安装 | 无（终端） | — | scripts/easyproxy.sh + install.sh + make-ipk.sh | `wget -qO- <短链> \| sh` | 真实，已在真机跑通 0.8.3→0.8.8 | **A** | 真机安装 4 次 + 沙箱 install 测试 | 真机 opkg 安装成功、面板可开 | 真机按钮无响应问题未定性（见 #40） |
| 33 | 远程管理（面板内 SSH） | 无 | 无 | 无 | 无 | **不存在** | **D** | 读前端菜单 | 11 个页面中无 SSH 管理页 | 需求若真实存在，属未实现 |
| 34 | 配置备份 | 备份恢复 | app.js:876 `run(['config','backup'])` | `cmd_config_backup`（tar 配置 + 规则集） | `easyproxy config backup` | 代码真实 | **B** | 沙箱缺 `/etc/config`，报 `no config at /etc/config/easyproxy` | 未验证 | 备份文件无下载入口，只能留在路由器上 |
| 35 | 配置恢复 | 备份恢复 | app.js:865/885 | `cmd_config_restore`（保留 .before-restore） | `easyproxy config restore` | 代码真实 | **B** | 未验证（同上） | — | 需真机验：恢复后配置与内核是否同步重启 |
| 36 | 恢复默认配置 | 备份恢复 | app.js:899 | `cmd_config_reset` 从 `/usr/share/easyproxy/easyproxy.default` | `easyproxy config reset` | 代码真实 | **B** | 沙箱缺 default 文件报错 | 未验证 | 真机需确认 ipk 确实装入该文件 |
| 37 | 一键更新检查 | 更新升级 | app.js:809 `cliJson(['update','check'])` | `cmd_update_check`（releases.atom 优先） | `easyproxy update check` | 真实联网 | **A** | 真实调 GitHub | `current 0.8.8 / latest 0.8.8 / already up to date` | api 限流已规避（走 atom） |
| 38 | 一键更新应用 | 更新升级 | app.js:824 | `cmd_update_apply`：下载 → 校验 sha → 安装 → 复验 | `easyproxy update apply` | 代码真实 | **B** | 未跑（会改真实系统） | — | 必须在真机验收一次完整升级 |
| 39 | 失败回滚 | 更新升级 | app.js:840 | `cmd_update_rollback` | `easyproxy update rollback` | 代码真实 | **B** | 未跑 | — | 需构造失败场景验证 |
| 40 | 面板按钮连通（前端→CLI） | 全部页面 | app.js `run()` = `fs.exec(BIN, ...)` | rpcd ACL `acl.d/luci-app-easyproxy.json` | ubus `file exec` | 代码存在，**真机实测全部按钮无响应** | **C** | 真机点击 + 计划中的 Console 取证 | 用户报告「所有按钮都不行」，根因未定位 | ACL 未生效（rpcd 未重启）或前端报错，二选一，尚无证据 |

### 4.9 日志 / 状态 / 诊断

| # | 功能 | 页面 | 前端 | 后台 | 入口 | 实现情况 | 状态 | 测试方法 | 结果 | 遗留问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 41 | 运行状态总览 | 运行总览 | app.js:316 + `cliJson(['status'])` | `cmd_status_json` | `easyproxy status --json` | 真实 | **A** | 沙箱执行 | 输出 engine/nodes/route/tproxy/config 全部字段 | 需真机确认字段与实际一致 |
| 42 | 流量统计 | 运行总览 | app.js:261 `run(['traffic'])` + trafficChart | traffic.sh 读 `/proc/net/dev` | `easyproxy traffic` | 代码真实，默认口写死 `br-lan` | **C** | 沙箱执行 | `{"ok":false,"iface":"br-lan","rx":0,"tx":0}` | 接口不存在时返回 ok:false 但面板仍画 0 值曲线；应支持按 UCI 配置的接口名并在失败时显式报错 |
| 43 | 日志查看 / 轮转 | 日志中心 | app.js:738/739 | `cmd_log`、`cmd_log_rotate` | `easyproxy log` | 代码真实 | **B** | 未跑 | — | 需真机验证轮转阈值 |
| 44 | 完整诊断 | 日志中心 | app.js:745 `run(['doctor'])` | `cmd_doctor` | `easyproxy doctor` | 代码真实 | **B** | 未跑 | — | 真机验收项 |
| 45 | 诊断回传（坚果云） | 设置 | app.js:769 `run(['diag','--upload'])` | `diag_upload_webdav` + `/etc/easyproxy/diag.conf` | `easyproxy diag --upload` | 真实（WebDAV MKCOL/PUT 实测 201） | **A** | 真机 + 坚果云目录 | 通道打通；目录当前为空（设备尚未成功上传） | 设备端是否已写 diag.conf、cron 是否 15 天未确认 |
| 46 | 15 天自动上报 | 设置 | app.js:764 | cron `17 3 */15 * *` + 安装时自动 `--daily on` | `easyproxy diag --daily on` | 真实（0.8.8 新增） | **A** | 沙箱 + 真实 crontab 写入 | cron 行正确 | 旧版本升级后需重跑一次才变 15 天 |
| 47 | 仅清理自身规则 | 设置 | app.js:983 | `cmd_uninstall_clean` | `easyproxy uninstall-clean` | 代码真实 | **B** | 未跑（需 nft） | — | 真机验收项 |

---

## 五、统计

按 47 个审计点：

| 状态 | 数量 | 占比 |
|---|---|---|
| A（真实跑过并有证据） | 17 | 36% |
| B（代码在，未真实运行验证） | 18 | 38% |
| C（部分实现 / 仅界面 / 判定错误） | 8 | 17% |
| D（完全没实现） | 4 | 9% |

**可以对外宣称"能用"的功能实现率：17/47 ≈ 36%**（严格口径：有真实运行证据）。
**扣掉"环境限制导致的 B"之后的工程完成度：约 74%**（A+B，即代码链路齐全但真机未验收）。
**明确不存在或损坏的：21%**（C+D，其中 3 项是硬缺陷）。

区分"环境限制"和"真缺陷"很重要：18 项 B 里，大约 14 项只是因为本环境没有 nftables/procd/真机，代码链路是通的；另外 4 项（备份、恢复、重置、流量）有具体的可疑点，属于"可能真有问题"。

---

## 六、必须承认的硬缺陷（不是"未验证"，是"验证了并且坏了"）

1. **同名节点 → 整份配置生成失败 → 代理起不来**（#9/#17）
   实测：同一订阅拉两次即复现 `duplicate outbound/endpoint tag: sub-us2`。这不是边缘 case，用户点两次「拉取并导入」就中招，且失败发生在配置生成阶段，等于全站断网。

2. **节点测速把超时判成可达**（#6/#7）
   实测：三个不可路由地址全部 `reachable 3019 ms`。curl 分支只把退出码 7 当不可达，超时 28 当成成功并把超时时长当延迟。后果：用户会选到一个根本连不上的节点，面板还显示绿色。

3. **面板所有按钮无响应**（#40）
   真机实测，根因未定位。这是当前最阻塞的问题——所有 A 级后端能力在真机上都点不到。

4. **`ss://` base64url 链接导入失败**（#1）
   主流机场链接格式，直接报 `ss userinfo is not base64`。

---

## 七、下一阶段优先修复的十个问题

按"影响面 × 修复成本"排序，前三条属于必须先做：

| 优先级 | 问题 | 影响 | 修复方向 | 预估 |
|---|---|---|---|---|
| **P0-1** | 面板按钮全部无响应 | 后端再强也用不上 | 先定性：真机 `easyproxy status` + `/etc/init.d/rpcd restart` + F12 Console；若是 ACL 则修 json 并强制重启 rpcd；若是 app.js 则修 `run()` | 半天内定性 |
| **P0-2** | 同名节点导致配置生成失败 | 点两次订阅即全站断网 | 导入时按 `server:port:method` 去重；生成时对 tag 做唯一化后缀；内核校验失败时回滚旧配置而不是留下坏配置 | 1 天 |
| **P1-3** | 测速超时误判可达 | 用户选到死节点 | `ep_tcp_probe` curl 分支改为：只有 rc=0 且耗时 < timeout 才算 reachable；rc=28 一律 unreachable；顺带支持 `-w %{time_connect}` | 半天 |
| **P1-4** | `ss://` base64url 不支持 | 主流链接导不进来 | `ep_b64_decode` 先做 `-`→`+`、`_`→`/` 转换并补 padding | 2 小时 |
| **P1-5** | 订阅无去重、无定时更新 | 节点表被污染 | 加 `subscribe --replace` 与 uci 记住上次订阅 URL + 每日 cron | 1 天 |
| **P1-6** | 节点启用/停用无面板入口 | 核心操作缺失 | 节点表加 switch，写 `@node[n].enabled` 并触发重生成 | 半天 |
| **P2-7** | dae 只有骨架 | 对外承诺与事实不符 | 要么把 README/发布说明明确写"dae 未支持"，要么排期实现 | 文案 5 分钟 / 实现不可估 |
| **P2-8** | 流量统计接口名写死 br-lan 且失败静默 | 面板画假曲线 | 从 UCI 取 LAN 接口名；ok:false 时前端显示错误而不是 0 | 半天 |
| **P2-9** | 透明代理 / 规则集 / 备份恢复全未真机验收 | 宣称可用但无证据 | 制定一份"真机验收清单"，逐项在 10.10.10.13 跑一次并留输出 | 1 天 |
| **P3-10** | `rule del 0` 与面板序号不一致、导出无入口、备份无下载、透明代理无审计按钮 | 易用性 | 统一 index 口径；补齐三个界面入口 | 1 天 |

---

## 八、审计方法的自我限制（必须写在报告里）

1. 本环境**没有 nftables、没有 procd、没有 rpcd**，所以透明代理、服务托管、面板 ACL 三条链路只能给 B，不能给 A。任何声称这三项"已验证"的说法都是不诚实的。
2. 沙箱不是 OpenWrt：uci 是等价的键值实现，不是真的 `uci` 二进制。uci 语义级行为（如 `uci commit` 原子性）未覆盖。
3. 真机侧的证据全部来自操作者回贴的截图/输出，审计方无法独立复现。
4. 本报告**没有**把单元测试结果当作功能证据；只在旁证时提及。
5. 本报告**未修改任何产品代码**。

---

## 九、后记：这次审计真正发现的规律

不是"某个函数没写"，而是**三类系统性错位**：

- **"能存" vs "能用"**：配置写进 uci 是真的，但写进去的配置能不能被内核接受，此前没人验证过（#17 的重名问题就是这样漏出来的）。
- **"有返回值" vs "返回值对"**：测速永远返回数字，但数字的含义是错的（#6）。凡是"永远成功"的实现都值得怀疑。
- **"界面上有" vs "后端可达"**：节点启用状态能看见但不能改，导出有命令但没按钮（#4/#5）。界面与能力不是同一张清单。

下一版验收标准建议改成一句话：**每个按钮点下去，必须能指出它改了哪个文件、起了哪个进程、开了哪个端口，并且能拿出一次真实执行的输出。** 做不到的，一律标 B，不进"已实现"清单。
