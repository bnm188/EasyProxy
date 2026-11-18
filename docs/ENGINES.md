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
