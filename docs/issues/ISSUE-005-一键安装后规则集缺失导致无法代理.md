# ISSUE-005 一键安装完成后规则集缺失，路由退化为 direct only

- 状态：待修复（未改代码）
- 发现时间：2026-11-18
- 发现方式：真机共存安装后执行 `easyproxy status`
- 严重度：高（装完看起来正常，实际一点流量都代理不了）

## 现象

安装成功、节点还在、面板 200，但 `easyproxy status` 直接给出了红灯结论：

```
Nodes: 1
Rule sets: missing (/etc/easyproxy/ruleset)
Routing: direct only (rule sets missing: nothing is proxied, foreign sites unreachable)
LAN: always direct (private ranges, router addresses, local domains excluded)
Transparent: disabled
```

关键两句：

- `Rule sets: missing (/etc/easyproxy/ruleset)`
- `Routing: direct only (rule sets missing: nothing is proxied, foreign sites unreachable)`

## 判读

`Routing: direct only` 不是"暂时降级"，是**所有出网都被判定为直连**，所以：

- 国内网站正常（本来就直连）
- **国外网站全部不可达**（本该走代理的部分没有规则可依据）

也就是：装完 → 面板能开 → 节点显示 1 个 → 用户以为好了 → 实际打不开任何国外站点。

## 取证状态（诚实标注）

| 项 | 状态 |
|---|---|
| `status` 原文输出 | **已取证**（上面四行即原样） |
| `/etc/easyproxy/ruleset` 目录是否真的不存在 | **未核实**（本轮未单独查该路径，只依据 status 结论） |
| 规则集是否本应由安装器自动拉取 | **未核实**（需查 `install.sh` 与 `rules` 子命令的默认行为） |

这条在归档里先按"现象 + status 原文"落档，实施修复前必须补齐后两项核查，不得凭推测写结论。

## 影响面

- 干净环境首次安装、升级安装之后都会出现（只要没手动拉过规则集）
- 这是"第一印象"级别的缺陷：用户第一次装完打不开网页，会直接判软件不可用
- 与 ISSUE-003 叠加时更难判断——一个说内核没装，一个说路由直连，用户会彻底放弃

## 修复方向（未实施，仅记录）

1. 安装结束自动拉一次规则集，失败时明确提示重试命令
2. 面板总览把 `Rule sets: missing` 做成显眼告警卡片 + 一键拉取按钮
3. 首次安装的收尾输出里，明确写"还需要做的一步"，而不是让用户自己发现
4. 补断言：空规则集时 status 必须报 direct only（现状已满足），且安装器必须尝试拉取

## 关联

- 与 ISSUE-003 同次安装同时出现，叠加后严重误导用户
- 与规则更新、DNS 分流能力相关，修复时应一并检查
