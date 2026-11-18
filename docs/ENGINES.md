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

## 尚未做完

- mihomo 二进制（61 MB）目前是手工放到 `/usr/bin/mihomo`，**还没有独立 opkg 包**。
  `scripts/make-kernel-ipk.sh` 只认 sing-box 和 dae，要加一个 mihomo 分支。
- geodata 也没进包，现在靠从测试残留里复制。
- Clash API 的 `/connections`、`/traffic` 还没接进 `easyproxy status` 与面板。
- `engine use` 的切换事务（先 validate 再停旧、失败回滚）未做，现在靠人工切。
