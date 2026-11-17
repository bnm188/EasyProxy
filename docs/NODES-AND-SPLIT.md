# 节点导入、自动分组与智能分流

对应清单第 4 类 10 项：节点导入与管理 / 延迟测试 / 自动分组 / 自动选择可用节点 /
国内 DIRECT / 国外 PROXY / YouTube 分流 / Netflix 分流 / TikTok 分流 /
自定义规则和分流策略。

## 节点导入

```
easyproxy node add 'ss://YWVzLTI1Ni1nY206cHc=@203.0.113.10:8388#香港-01'
easyproxy node import /tmp/nodes.txt     # 一行一个链接，# 开头为注释
easyproxy node list                      # 文本表：名字/类型/服务器/地区/分组
easyproxy node list --json
easyproxy node export                    # 全部导出成分享链接
easyproxy node export hk-01              # 单个导出
easyproxy node del hk-01                 # 按名字、服务器地址或 section 删除
```

支持的链接：`ss://`、`vmess://`、`vless://`、`trojan://`、`hysteria2://`（`hy2://`）、
`tuic://`、`socks5://`、`http(s)://`。

解析只用 busybox 工具：`base64`（缺失时退 `openssl base64`）、`awk`、`sed`，
不依赖 python/jq。中文节点名走百分号解码，`LC_ALL=C` 保证按字节还原，不会被
locale 二次编码成乱码。解析失败会把原因写进 stderr（例如
`unsupported share link scheme: ftp`、`vmess link is missing add/port/id`），
不会写进半个空节点。

节点写进 UCI（`uci add` 分配 section，不用固定下标），所以升级和备份都不会冲突。

## 自动分组与自动选路

节点按名字里的地区关键字分组，中英文都认：

| 分组 tag | 触发关键字（节选） |
|---|---|
| `auto-hk` | hk、hongkong、香港 |
| `auto-tw` | tw、taiwan、台湾 |
| `auto-jp` | jp、japan、东京、日本、大阪 |
| `auto-sg` | sg、singapore、新加坡 |
| `auto-us` | us、united states、美国、洛杉矶 |
| `auto-uk` / `auto-de` / `auto-kr` / `auto-ru` | 英国 / 德国 / 韩国 / 俄罗斯 |
| `auto-other` | 其它 |

生成配置时：

- 每个地区一个 `urltest` 出站（`auto-hk` 等），组内按 5 分钟间隔自动挑最快的节点，
  这就是「自动选择可用节点」；
- 前面再加一个 `selector`，tag 固定叫 `proxy`，选项是各地区组，默认第一个区。
  `route.final` 只指向 `proxy`，所以换组不用重写规则。
- 没有名字的 section（`@node[3]` 这种）不会被当成地区关键字去匹配，统一进 `other`。

## 分流规则顺序

```
1 ip_is_private            direct   内网永远直连
2 节点服务器 IP            direct   防止节点流量自己绕回代理（环路）
3 自定义规则               ...      你自己的顺序，最先命中
4 YouTube / Netflix / TikTok proxy   平台分流，可单独关
5 geosite-cn + geoip-cn    direct   国内直连（硬锁，不可绕过）
6 final                    proxy    其余走节点组
```

平台分流排在 CN 规则之前，否则一个被国内规则集收录的 CDN 域名会把 YouTube
拽回直连。规则集缺失时（`fail_closed` 锁生效）平台规则和自定义规则都会整段不生成，
避免它们把流量偷偷送回 `proxy`。

三个平台开关：`routing.platform_youtube` / `platform_netflix` / `platform_tiktok`，
默认都是 1，置 0 即该平台回落直连。

内置域名（免下载规则集）：

- YouTube：`youtube.com`、`youtu.be`、`googlevideo.com`、`ytimg.com`、
  `youtube-nocookie.com`、`yt3.ggpht.com`
- Netflix：`netflix.com`、`netflix.net`、`nflxext.com`、`nflximg.com`、
  `nflximg.net`、`nflxso.net`、`nflxvideo.net`
- TikTok：`tiktok.com`、`tiktokv.com`、`tiktokcdn.com`、`byteoversea.com`、
  `ibytedtos.com`、`muscdn.com`

## 自定义规则

```
easyproxy rule add domain-suffix:example.org:proxy
easyproxy rule add domain:ads.test:block
easyproxy rule add ip-cidr:198.18.0.0/15:direct
easyproxy rule add domain-keyword:tracker:block
easyproxy rule list          # 带序号
easyproxy rule del 2         # 按序号删
```

- 类型：`domain`、`domain-suffix`（`suffix`）、`domain-keyword`（`keyword`）、
  `ip` / `ip-cidr`
- 出站：`direct`、`proxy`、`block`（`block` 会自动补一个 `block` 出站）
- 全部存进 `routing.custom_rules`，一条 UCI 字符串，备份 `/etc/config/easyproxy` 即带走
- 出站不是这三个之一、或字段不足三段时直接拒绝，不会静默丢弃

## 为什么平台规则用内联域名而不是规则集

规则集要先生成/下载，`fail_closed` 锁生效时反而无法分流；内联域名在任何时候都能
直接生效，且 sing-box 的 `domain_suffix` 匹配开销很小。需要更完整的覆盖时，
把对应 `geosite-*` 规则集加进 `route.rule_set` 即可，顺序不变。
