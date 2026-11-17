# ISSUE-003 安装器汇总把已采纳的 sing-box 判成 not installed

- 状态：待修复（未改代码）
- 发现时间：2026-11-18
- 发现方式：真机共存安装（Open-Box 正在运行）后，对比安装器汇总与 `easyproxy status` 两处输出
- 严重度：高（用户据此会误判"内核没装上、安装失败"）

## 现象

一键安装过程中，脚本明显**已经采纳**了系统里现成的 sing-box，但最后汇总却报它没装：

```
sing-box: found a working static binary at /opt/open-box/bin/sing-box (sing-box version 1.14.4-openbox-45)
sing-box: adopting it instead of downloading (it keeps belonging to whatever installed it)
sing-box: uci points at /opt/open-box/bin/sing-box
...
components:
  easyproxy  0.8.13-1  (/usr/sbin/easyproxy)
  sing-box   not installed  (/usr/bin/sing-box)
  dae        not installed  (/usr/bin/dae)  [adapter 开发中]
```

## 取证（同一次安装、同一台机、同一个二进制）

| 输出源 | 原文 / 结果 |
|---|---|
| 安装器汇总 | `sing-box   not installed  (/usr/bin/sing-box)` |
| 安装过程 | `adopting it instead of downloading`、`uci points at /opt/open-box/bin/sing-box` |
| `uci get easyproxy.sing_box.binary` | `/opt/open-box/bin/sing-box` |
| `uci show easyproxy \| grep engine` | `easyproxy.sing_box.binary='/opt/open-box/bin/sing-box'` |
| `easyproxy status` | `Binary: /opt/open-box/bin/sing-box (available)` |
| `ls -l /usr/bin/sing-box` | `No such file or directory` |

**同一个二进制，同一次会话里两条命令给出相反结论**：`status` 说 available，安装器汇总说 not installed。

## 根因

安装器汇总段用的是**写死的 `/usr/bin/sing-box` 路径**做存在性判断，没有走 uci 里的 `easyproxy.sing_box.binary`。

`easyproxy status` 走的是 uci 里的实际路径，所以判对。两条判定路径不一致，导致采纳外部二进制后必然出现这个矛盾。

## 影响面

- 任何"系统里已有 sing-box、被采纳"的场景都会触发：预装 Open-Box / PassWall / 其他带内核的固件
- 一键安装最后以 `error:` 结束，用户看到的是失败，而不是"面板已装好、内核用现成的"
- 面板「内核管理」页若同样按固定路径判断，会显示错误状态（**本条尚未在面板上核实**）

## 修复方向（未实施，仅记录）

1. 汇总与 `status` **复用同一个判定函数**：读 `easyproxy.sing_box.binary` → 文件存在且可执行 → available
2. 汇总里显示的路径应当是实际生效路径（`/opt/open-box/bin/sing-box`），不是模板路径
3. 补断言：采纳外部二进制后，汇总必须显示该路径并标记 available

## 关联

- 与 ISSUE-001（安装取到旧 ipk）无关，是独立缺陷
- 与 ISSUE-004 在同一次安装里共同导致安装器以 `error` 退出，但两者要分开修
