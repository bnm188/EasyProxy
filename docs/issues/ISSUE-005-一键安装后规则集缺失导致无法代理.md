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

## 取证（已补齐核查，2026-11-18 真机实测）

| 项 | 结果 |
|---|---|
| `status` 原文 | 见上四行，原样保留 |
| `/etc/easyproxy/ruleset` | **目录存在但为空**（`drwx------ root root`，目录内 0 个文件）—— status 报的 `missing` 指「没有规则文件」，**不是目录不存在** |
| 安装器是否自动拉取 | **不拉**：一键安装全程无任何 ruleset 动作，装完即为空 |
| `easyproxy ruleset update` | `geosite-cn.srs` 57617 B、`geoip-cn.srs` 34259 B，`rule sets updated in /etc/easyproxy/ruleset` |
| `easyproxy ruleset verify` | `[ok] geosite-cn.srs` / `[ok] geoip-cn.srs` / `ruleset: 2 ok, 0 fail` |
| 拉取后再查 `status` | `Rule sets: ready (/etc/easyproxy/ruleset)`、`Routing: split (China direct, others proxied)` |
| `easyproxy config generate` | 生成 2262 B；`rule_set` 出现 3 处；`{"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"}`；`{"type":"local","tag":"geosite-cn","format":"binary","path":"/etc/easyproxy/ruleset/geosite-cn.srs"}` |
| 内核只读校验 | `/opt/open-box/bin/sing-box check -c /etc/easyproxy/sing-box.json` → **rc=0**，`Engine validation: passed` |

## 定性（结论已收敛）

**不是机制坏了，是漏了一步。** 手动 `ruleset update` 之后，规则集 → 状态 → 配置 → 内核校验四环全部正常，路由立刻从 `direct only` 变成 `split`。

因此本条只需要：**安装器装完自动拉一次规则集 + 明确提示**，不需要改动路由或内核逻辑。修复成本低，收益高（直接决定用户第一眼能不能用）。

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
