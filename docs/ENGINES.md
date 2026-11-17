# 代理内核管理（第 3 类）

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
