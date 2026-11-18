# 代理内核管理

对应清单第 3 类 7 项：sing-box 配置生成 / 启停 / 运行状态检测 / 节点连接测试 /
dae 内核切换框架 / dae 标记为开发中 / 双内核切换接口预留。

## 命令

```
easyproxy engine            # 当前选中的内核、二进制、状态
easyproxy engine list       # 内核注册表：sing-box:stable, dae:dev
easyproxy engine health     # 八项体检，任一项 FAIL 则退出码非 0
easyproxy engine health --json
easyproxy engine version    # 打印内核二进制自己的版本行
easyproxy node test         # 逐个节点做 TCP 探测，给出毫秒延迟
easyproxy node test --json  # latency_ms 为数字或 null
```

## 内核注册表

| 内核 | 标识 | 稳定度 | 说明 |
|---|---|---|---|
| sing-box | `sing-box` | `stable` | 当前唯一可运行的实现 |
| dae | `dae` | `dev` | 只有框架，`dae_run` 打印「开发中 (dev)」并返回 2 |

`main.engine=dae` 时，`easyproxy start`、`easyproxy run`、`easyproxy config generate`
都会拒绝执行并说明原因（退出码 2），不会留下半个进程或半份配置。

## health 的八项

```
enabled     main.enabled=1
engine      main.engine=sing-box (stable)
adapter     适配器文件存在
binary      二进制存在且可执行，并打印版本
config      配置文件存在；不足 512 字节时只 warn
runtime     进程号在跑，且 pid 与监听端口一致
listen      监听端口处于 LISTEN（读 /proc/net/tcp{,6}）
```

`--json` 输出 `{"ok":true/false,"checks":[{"name","status","detail"}...]}`，
status 取 `ok|warn|fail`。脚本据此判断，不必解析文本。

端口检测读 `/proc/net/tcp` 与 `/proc/net/tcp6`，状态 `0A` 即 LISTEN，不依赖
`ss`/`netstat`（很多精简固件没有这两个命令）。

## 节点连接测试

`easyproxy node test` 对每个 enabled 节点做一次 TCP 连接：

- 优先用 `nc -z -w<probe_timeout>`（`routing.probe_timeout`，默认 3 秒）；
- 没有 `nc` 时退化为 `curl --connect-timeout`，且只把 curl 的退出码 7（连不上）
  视为不可达，其它退出码不算结论；
- 全部节点都不可达时退出码非 0，方便脚本告警。

## 双内核切换的接口

每个内核一个适配器文件 `usr/lib/easyproxy/adapters/<engine>.sh`，必须提供六件套：

```
<prefix>_binary     二进制路径
<prefix>_config     配置文件路径
<prefix>_available  是否可用（1/0）
<prefix>_version    版本行
<prefix>_validate   生成配置后的自检
<prefix>_check      是否接受当前配置
<prefix>_run        前台运行（procd 调用）
```

`ep_adapter_path` 用 `EP_LIB_DIR`（默认 `/usr/lib/easyproxy`）拼路径，测试可整体
搬到沙箱里跑。要接第三个内核，只需加一个适配器文件并在 `ep_engine_list` 注册。

## 内核独立发包

内核二进制不再塞进 `easyproxy` 主包。主包是 shell 脚本、`PKGARCH:=all`，内核是
按架构编译的 ELF，两者混在一起有两个后果：一个 `all` 包里可能装着 amd64 二进制
被装到 ARM 路由器上，以及每改一行脚本都要重传几十兆。

于是拆成两个包：

| 包 | 内容 | 架构 | 版本 |
|---|---|---|---|
| `easyproxy` | 脚本 + 配置 + 面板，约 79 KB | `all` | 0.8.14-N（`PKG_RELEASE` 递增） |
| `sing-box` | 只有引擎二进制，装在 `/usr/bin/sing-box` | 具体架构，不能是 `all` | 跟随引擎自身，如 `1.14.4-ob45` |

主包声明 `DEPENDS:=+sing-box`，装主包时引擎自动带下来；升级主包只拉 79 KB。

### 构建

```
sh scripts/make-kernel-ipk.sh sing-box x86_64 dist      # 上游下载 + sha256 校验
EP_SRC=/path/to/musl-sing-box sh scripts/make-kernel-ipk.sh sing-box x86_64 dist
```

两条路：默认从上游 Release 下载并核对内置 sha256；`EP_SRC` 则打包本机已有的二进制
（版本号从二进制自己读，`-openbox-45` 归一成 `-ob45`，因为 opkg 把最后一个 `-`
切成 version 和 release）。

### 一条真机踩过的坑：glibc 版在 musl 固件上装得上、跑不起来

上游 `linux-amd64` 是 glibc 构建。在 Kwrt（musl）上 `opkg install` 成功，执行时
报 `cannot execute: required file not found` —— 二进制指定的动态链接器是 glibc 的
`/lib64/ld-linux-x86-64.so.2`，而这台机器只有 `/lib/ld-musl-x86_64.so.1`。所以
musl 固件必须用 `EP_SRC` 打包一个 musl 构建的内核，不能直接用上游包。

另一个坑是容器格式：`opkg` 拒收 27 MB 的 `ar` 布局包（`pkg_init_from_file:
Malformed package file`），同一内容改成 gzip tar 布局就正常安装。两个打包脚本
现在都用 gzip tar。

---

# mihomo（第二内核，0.8.14-5 接入）

## 为什么是 mihomo

sing-box 是主线，不动。mihomo 补的是 sing-box 缺的两块：Clash 订阅格式的解析
能力，以及 Clash API（`127.0.0.1:9090`）提供的连接级可观测性，正好压在 P1~P3
的「连接与监控」「节点中心」。dae 因为依赖固件的 BPF 支持，收益只在低配 ARM，
延后。

## 结构

同一份 UCI 节点模型，两个 writer：

| 层 | sing-box | mihomo |
|---|---|---|
| 配置生成 | `usr/lib/easyproxy/config.sh`（`ep_config_build`，JSON） | `usr/lib/easyproxy/mihomo.sh`（`ep_mihomo_config_build`，Clash YAML） |
| 进程契约 | `adapters/sing-box.sh` | `adapters/mihomo.sh`（同样六个动词） |
| 校验 | `sing-box check -c` | `mihomo -t -f` |
| 版本 | `sing-box version` | `mihomo -v` |
| 入站 | 7890 mixed（仅回环） | 7890 mixed（`bind-address: 127.0.0.1`） |

所有「按引擎分支」的事情集中在三个函数里：

- `ep_engine_verb <engine> <verb>` —— source 适配器后调用 `<prefix>_<verb>`，没有
  适配器时返回 127（调用方据此区分「还没实现」和「失败」，并对 127 回退旧路径）
- `ep_engine_config_generate <engine> <path>` —— 唯一的配置生成入口
- `ep_config_state` —— 校验走 `validate` 动词，不再硬编码 `check -c`

## geodata 必须预置

mihomo 首次启动如果 `-d` 目录里没有 `geoip.metadb`，会联网下载
（真机实测 4.7 秒，断网环境直接卡住）。所以：

1. 包内预置 `/etc/easyproxy/mihomo/geoip.metadb`（约 8.4 MB）
2. 生成器写死 `geo-auto-update: false` 与 `geodata-loader: memconservative`

首次 `GEOIP,CN` 规则触发时 MMDB 才真正加载，实测约 5 秒，这段时间内代理请求会
超时 —— 属正常现象，不是故障。

## 真机验收（Kwrt 25.12 / x86_64 / 10.10.10.13）

```
opkg install --force-reinstall easyproxy_0.8.14-6_x86_64.ipk
uci set easyproxy.main.engine=mihomo && uci commit easyproxy
/etc/init.d/easyproxy start
curl -x http://127.0.0.1:7890 https://www.google.com/generate_204   # 204
curl http://127.0.0.1:9090/version                                  # {"meta":true,...}
```

切回 sing-box 同样 204，主线未被破坏。

## 踩过的两个坑

**`match` 分支里的 `[ -n "$x" ] && printf`** —— 条件为假时该语句返回 1，如果它正好是
case 分支的最后一条命令，整个 `ep_mihomo_node` 就返回失败，一个字段齐全的节点被
判成坏节点。可选字段一律写成 `if ... then ... fi`，分支末尾显式 `return 0`。

**配置生成入口漏改** —— `cmd_start` 和 `/etc/init.d/easyproxy` 曾经直接调
`ep_config_build`（sing-box 专用）。engine 切成 mihomo 后，sing-box 的 JSON 被写进
`mihomo.yaml`，而 `"$binary" check -c` 里的 `check` 被 mihomo 当成参数，留下一个
长驻进程占着 7890，面板显示 running、实际代理不通。现在两处都走
`ep_engine_config_generate`，`tests/test-engine.sh` 里有断言守着「CLI 和 init 脚本
不得直接调用 `ep_config_build`」。

## 独立内核包

mihomo 和 sing-box 一样单独发包，互不牵连：

```
sh scripts/make-kernel-ipk.sh mihomo x86_64 dist
EP_SRC=/path/to/mihomo EP_META=/path/to/geoip.metadb \
  sh scripts/make-kernel-ipk.sh mihomo x86_64 dist
```

产出 `dist/mihomo_1.19.34_x86_64.ipk`（约 26 MB，内含 61 MB 二进制与 8.4 MB
geodata）。包内落两个文件：

| 路径 | 内容 |
|---|---|
| `/usr/bin/mihomo` | statically linked，musl 可直接跑 |
| `/etc/easyproxy/mihomo/geoip.metadb` | geodata，避免首次启动联网下载 |

上游资产的命名三种架构不一致：amd64 有 v1/v2/v3 三档微架构分级（`v1` 是最兼容
的那档，也是唯一能保证所有 x86_64 机器跑得动的），arm64 与 armv7 则不带这段前缀。
脚本按 `$UARCH` 分别拼，sha256 三档都 pin 了。

`EP_META` 不传时从 `MetaCubeX/meta-rules-dat` 的 `latest` 拉 —— 那个 tag 会随上游
更新翻滚，没法 pin sha，脚本改为校验「体积 > 5 MB」，明显截断的包直接拒收。

主包**不**把 mihomo 写进 `DEPENDS`：为 26 MB 的引擎强制拉依赖，只用 sing-box 的
用户没必要付这个代价。装不装由用户决定，`easyproxy engine list` 的 `available`
字段会如实反映二进制在不在。

真机干净安装验收（0.8.14-6 + mihomo 包）：

```
rm -f /usr/bin/mihomo; rm -rf /etc/easyproxy/mihomo    # 清掉之前手工放的文件
opkg install /tmp/mihomo_1.19.34_x86_64.ipk            # opkg list-installed 认得
uci set easyproxy.main.engine=mihomo && uci commit easyproxy
/etc/init.d/easyproxy start
curl -x http://127.0.0.1:7890 https://www.google.com/generate_204   # 204, 0.58s
```

日志确认 `Load MMDB file: /etc/easyproxy/mihomo/geoip.metadb` —— 用的是包内那份，
没有联网下载。

## Clash API 接进面板（0.8.14-9）

mihomo 的 `external-controller` 是唯一能拿到「连接级」信息的地方：哪条连接、来自谁、
实际走了哪个出站、多少字节、开了多久。sing-box 没有等价接口，所以这一段只对
mihomo 生效，面板在别的引擎下会明说「当前引擎没有连接接口」，而不是摆一张空表。

### 读取层

`usr/lib/easyproxy/clash.sh`：

| 函数 | 作用 |
|---|---|
| `ep_clash_controller` | 读 `mihomo.controller`，缺省 `127.0.0.1:9090` |
| `ep_clash_applicable` | 只有 `main.engine=mihomo` 时返回 0 |
| `ep_clash_get` | `curl -fsS -m 2`；`mihomo.secret` 非空才加 `Authorization: Bearer` |
| `ep_clash_snapshot` | 输出 `api / count / up / down / memory`，不可达返回 `absent` |
| `ep_clash_connections` | 把 `/connections` 按 `},{"` 切行，输出六列 TSV |

设备上没有 `jq`（busybox 环境），解析全部走 `grep -o` + `cut`/`sed`。这决定了下面
四个坑的形态。

### 四个真机才暴露的坑

**1. `--json` 被参数循环吃掉。**
顶层 `for arg in "$@"` 把 `--json` 收进 `JSON=1`，`SUB` 于是为空，分发那行
`cmd_connections "$SUB"` 传了空串，子命令永远走文本分支 —— 面板 `JSON.parse` 拿到的
是一张表。`connections --json` 现在显式判断 `$JSON` 再分发，`tests/test-engine.sh`
有两条断言守着（必须是 `{"ok":false` 开头的对象、且不能出现 `HOST` 表头）。

**2. 连接时长凭空老 8 小时。**
Clash 的 `start` 是 `2026-11-18T02:54:44.897905728Z`，末尾的 Z 是 UTC。原实现拿
`date +%H`（本地 CST）去减，每条连接都「已经开了 28804 秒」。现在按末尾有没有 Z
决定用不用 `date -u`：带 Z 用 UTC，不带 Z 视为本地墙钟。测试里两种时间戳各有断言，
fixture 也必须用 `date -u` 构造，否则测的是「本地对本地」这个假通过。

**3. NODE 列显示 `PROXY` 而不是节点名。**
真机的 `chains` 是 `["11","PROXY"]` —— mihomo 从里往外写：**首项**才是真正承载这条
流量的出站，末项是最外层的选择器组。原来取末项，等于把选择器名当节点名。
`awk -F, '{print $1}'`，注释里写清这个顺序，免得下次又有人「顺手改成 $NF」。

**4. `memory` 恒为 0。**
`/connections` 返回 `"memory":0`，是平台没有上报，不是面板算错。CLI 保留 0 原样，
面板显示 `—`，不显示 `0 B` —— 一个永远为 0 的仪表比一个破折号更误导。

### CLI 与面板

```
easyproxy connections           # 文本表格
easyproxy connections --json    # {"ok":true,"engine":"mihomo","connections":[...]}
easyproxy status --json         # 多出 clash_api / connections / conn_up / conn_down / conn_memory
```

`conn_up` / `conn_down` 是 Clash 的累计计数，**引擎重启即归零**，所以面板文案写的是
「本会话」，不冒充「今日流量」—— 今日流量仍旧走节点口径的 `traffic`。

面板 `pageLive` 每 3 秒并发拉一次 `connections` 与 `status`，原地替换表格与 KPI，并用
`document.body.contains(wrap)` 判断视图是否已经被 LuCI 拆掉，拆掉就 `clearInterval`，
否则每进一次这个页面就多留一个定时器。

### 真机结果（0.8.14-9 / -10）

```
easyproxy connections
HOST                     SOURCE       NODE   UP     DOWN       ELAPSED
speed.cloudflare.com     127.0.0.1    11     1778   6325650    4s
```

造流量必须限速：不限速时 30 MB 两秒下完，连接已关闭，`/connections` 自然返回空数组，
看起来像是解析坏了。`curl --limit-rate 200k` 拉 10 MB 才能稳定拿到一条活连接。

## mihomo 的分流规则（0.8.14-12）

面板「智能分流」页把三个平台开关和自定义规则写进 UCI，sing-box writer 一直读它们，
mihomo writer 从前只有 `GEOIP,CN,DIRECT` + `MATCH,PROXY`：**开关点了、规则存了，实际
不生效**。0.8.14-12 把这段接上，规则顺序与 sing-box 一致：

```
内网五段 CIDR（192.168/10/172.16/127/100.64）→ 自定义 → 平台三组 → GEOIP,CN → MATCH,PROXY
```

三个必须记住的点：

1. **不能复用 `ep_route_mode()`**。它靠 `geosite-cn.srs` / `geoip-cn.srs` 是否就位来判
   split，而 mihomo 用的是包内 `geoip.metadb`，根本不读那两个文件。复用会把「有节点但没
   下过 srs」的机器判成 direct——面板看着健康，实际一个字节都没代理。mihomo 侧自己判断：
   有 enabled 节点就走 split。
2. **平台规则必须排在 `GEOIP,CN` 前面**。youtube / netflix 的 CDN 段落进 CN 段是常事，
   geo 规则在前会把它们判成直连，开关也就白开了。
3. **摘要要跟着改**。`config generate` 的 `Routing mode:` 读 `EP_ROUTE_MODE`，mihomo
   生成器不设置它，于是打印 "direct only (nothing is proxied)"，与刚落盘的 YAML 自相
   矛盾——这正是最容易骗过人的那种「看着正常」。现在 mihomo 成功后写 `EP_ROUTE_MODE=split`。

`ep_node_server_cidrs()` 的节点旁路在 mihomo 下不需要：出站连节点不走 rules。

真机证据（0.8.14-12，Kwrt x86_64，mihomo 1.19.34）：

```
direct_cn     220.200.54.136        # 不过代理
proxy_cn      220.200.54.136        # 经 7890 访问 ip.3322.net，GEOIP,CN 判定直连
proxy_foreign 103.151.173.95        # 经 7890 访问 api.ipify.org，走节点出口
google204=204  youtube=200  baidu_via_7890=200
```

对比出口 IP 是验证分流唯一可信的办法。`curl -x 7890 <国内域名>` 返回 200 什么都说明不了
——被代理也能 200。

测试：`test-engine.sh` 加了 8 条（平台规则进 YAML、内网排在 GEOIP 前、自定义
domain-suffix / block→REJECT / IP-CIDR 带 no-resolve、关 YouTube 不影响 Netflix、
摘要不误报 direct only）。变异检查：注释掉 `ep_mihomo_platform_rules` 会红 3 条。

## 尚未做完

- Clash API 的 `/traffic`、`/memory` 还没接；`/connections` 已接（见上一节）。
- `engine use` 的切换事务（先 validate 再停旧、失败回滚）未做，现在靠人工切。
- mihomo 的 DNS 段仍是 `redir-host` + 仅本地 nameserver：`dns_remote_server`、
  fallback、防泄漏、缓存都还没有，与 sing-box 侧不等价。
- 平台开关目前只能整体走 PROXY，没有 url-test / fallback 组，也就没有自动选最快和
  故障剔除的载体。
