# IPv4 / IPv6 网络支持与重启恢复（第 2 类）

对应清单第二大类「IPv4 / IPv6 网络支持」六项。设计前提不变：LAN 直连、fail_closed、内网保护三条锁定仍然优先，任何一条被触及的实现都不接受。

## 1. 完善 IPv4 透明代理规则

| 规则 | 作用 |
|---|---|
| `iifname != "br-lan" return` | 只接管 LAN 入口，WAN 回包与路由器自身发起的流量不进内核 |
| `ip daddr @bypass_ipv4 return` | 内网、保留段、节点服务器、运营商排除项一律直连 |
| `ip frag-off & 0x1fff != 0 return` | 非首片分片没有 L4 头，tproxy 无法处理，直接放行（否则内核侧直接丢包） |
| `tcp dport <listen_port> return` | 面板/mixed 入口的回流不被二次接管 |
| `meta l4proto tcp/udp tproxy to :<port> meta mark set <mark> accept` | 真正接管并打标，交给策略路由 |
| 集合 `bypass_ipv4`（`flags interval`） | 归一化后的互不重叠区间，嵌套条目以 `# covered by` 注释保留可审计性 |

新增的分片规则是这一项的实际缺口：旧版把碎片交给 tproxy，非首片在内核侧无法解析端口，属于「规则不完善」。

## 2. IPv6 分流支持

sing-box 侧的 `ip_is_private` 同时匹配 v4 与 v6，因此内网 v6 仍然直连；`route.rules` 的 CN 规则集按域匹配，不区分地址族。本包此前的问题不是「引擎不会分」，而是「IPv6 处在无人声明状态」：既没接管，也没说明。现在状态是显式的：

- `transparent.ipv6_policy=direct`（默认）：IPv6 完全不接管，内网与公网 v6 都直连；`easyproxy status` 打印 `IPv6: not captured, direct (ipv6_policy=direct)`，JSON 给 `ipv6_policy` / `ipv6_state`。
- `transparent.ipv6_policy=block`：见第 4 项。

## 3. IPv6 内网地址绕过

`table ip6 easyproxy` 的 `bypass_ipv6` 集合固定包含：

```
::1/128            回环
fe80::/10          链路本地（ND、SLAAC）
fc00::/7           ULA，家用 IPv6 LAN 的默认选择
ff00::/8           组播
<LAN 接口的 on-link 前缀>  例如 2001:db8:aa::1/64
```

LAN 前缀来自 `ip -6 addr show dev <lan iface>`，按前缀（而不是 /128）进入集合，所以整段 LAN 在 block 策略下依然可达。集合同样做归一化：ULA 与 link-local 前缀会以 `# covered by fc00::/7: fd00:aa::1/64` 形式写成注释，不会被 nft 以 "File exists" 拒绝。

IPv6 没有做 128 位整数运算：地址被展开成 32 位十六进制字符串，前缀包含关系退化为字符串前缀比较，四个常量段直接按首字节分类。这样 busybox awk 就能跑，不引入 python 依赖。

## 4. IPv6 未支持时的安全阻断 / 明确禁用

二选一，由 UCI 显式决定，没有隐式默认行为：

| `ipv6_policy` | 行为 | 适用 |
|---|---|---|
| `direct`（默认） | 不接管、不阻断，IPv6 直连 | 接受「IPv6 不走代理」 |
| `block` | LAN 入口的 IPv6，除 bypass 集合外全部 `drop` | 要求「要么走代理、要么不通」，杜绝 v6 绕过代理 |

`block` 只作用于 `iifname != <LAN> return` 之后的 LAN 入口流量，路由器自身与 WAN 侧不受影响；回环、link-local、ULA、组播、LAN on-link 前缀全部先放行，所以内网设备互联、RA/ND、管理面板都不受影响。

`easyproxy transparent audit` 会在策略与实际不一致时直接判失败（`ipv6_policy=block` 但没有 ip6 表，或 `direct` 但残留 ip6 表）。

## 5. 策略路由、流量标记与防火墙规则检查

`easyproxy transparent audit [--json]` 是这一项的落地形式，逐项比对 live 状态与 UCI：

```
ok    enabled   transparent.enabled=1
ok    nft       nft is available
ok    ruleset   /etc/easyproxy/nftables.conf targets tproxy port 7891
ok    ruleset   ruleset sets fwmark 1
ok    bypass    LAN and reserved ranges return before the mark is honoured
ok    table     ip table easyproxy is loaded
ok    rule      policy rule fwmark 0x1 -> table 100 exists
ok    route     route table 100 has local default dev lo
ok    engine    the proxy engine is running
ok/warn/fail  ipv6  ...
```

任一项 `fail` 时退出码为 1，可直接嵌进开机自检或监控脚本。它覆盖的正是「标记值改了但规则没重建」「表被 flush」「策略规则的 table 号漂移」这类只在现场才暴露的问题。

## 6. 重启后网络规则正确恢复

三层保障：

1. **init.d**：`START=95`，`start_service` 在引擎进入 `running` 后（最多等 10 秒）才 `ep_transparent_apply`；新增 `boot()` 明确走同一路径，`reload_service` 重建配置并重新应用，不从残留状态推断。
2. **hotplug**：`/etc/hotplug.d/iface/95-easyproxy` 在任意接口 `ifup`（PPPoE 重拨、网线插拔、LAN 重建）时重新 apply；引擎未运行则跳过，避免无监听的黑洞规则。
3. **可验证**：`easyproxy transparent audit` 给出「重启后是否真的恢复了」的机器可判结论，而不是靠 `nft list` 肉眼比对。

`apply` 本身幂等：先补齐策略路由，再删除旧表，最后 `nft -f` 加载新表；任何一步失败都 `ep_transparent_routing_down` 回滚，不留半套规则。
