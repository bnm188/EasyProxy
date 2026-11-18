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

## 节点命名模板

机场订阅里的名字是随机的（`🇺🇸_US_美国_IPV4 (3)`、`🇯🇵_JP_日本_IPV4`），
同批次还有多个同地区节点，名字里没有可读的区分度。导入时统一重写成：

```
<机场> | <地区>-<线路>-<NN>          有机场名
<地区>-<NN>                          没有机场名
```

- `地区` 来自原来的国旗/国家关键字，落进 hk/tw/jp/sg/us/uk/de/kr/ru 之一，其余进「其他」
- `线路` 从原名抓 `IPLC` / `IEPL` / `BGP` / `家宽` / `专线`，抓不到就省略整段
- `NN` 按「该地区已存节点数 + 1」现算，两位数补零，所以删掉中间某个节点不会错位
- 只改 UCI 里的 `name`。生成配置时 `ep_mihomo_node` 会把 `name:` 覆写成 tag，
  raw 文件与文件名都不必跟着动

```
easyproxy node import-clash /tmp/sub.yaml 我的机场   # 导入即按模板命名
easyproxy node normalize 我的机场                     # 给已存节点批量改名
easyproxy node rename 我的机场                        # 同 normalize 的别名
```

`provider` 存在节点的 UCI 字段里，面板的「按机场分组」读的就是它。
不传机场名时节点没有 provider，只能按地区分组。

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

## 场景组（mihomo 侧）

mihomo 不再把一堆域名全塞给一个 `PROXY`，而是每个使用场景一个 `select` 组，
在面板「节点中心 → 策略组」里能逐个改出口，改完立刻生效：

| 组 | 覆盖 |
|---|---|
| `Youtube` | youtube.com / youtu.be / googlevideo.com / ytimg.com / yt3.ggpht.com |
| `Netflix` | netflix.com / nflxext.com / nflximg.net / nflxso.net / nflxvideo.net |
| `TikTok` | tiktok.com / tiktokv.com / tiktokcdn.com / byteoversea.com / muscdn.com |
| `AI` | openai / anthropic / gemini / aistudio / perplexity / poe / copilot |
| `Github` | github.com / githubusercontent / githubassets |
| `Google` | google.com / gstatic / googleapis / gmail / googleusercontent |
| `Microsoft` | microsoft.com / live.com / office / azure / bing |
| `Apple` | apple.com / icloud / mzstatic |
| `Games` | steam / epicgames / blizzard / riot / ea / ubisoft / nintendo / playstation |
| `Speed` | speedtest.net / speedtest.com / ookla |

每个组的成员顺序固定为：

```
所有-自动 → 自动-日本 → 自动-俄罗斯 → 自动-新加坡 → 自动-美国 → 自动-其他 → 自动-德国 → DIRECT
```

即「默认走全区自动测速，可一键换成某个地区，也可以一键直连」。成员里只放组不放
单机节点，节点上下线不用改场景组。默认选中第一项 `所有-自动`。

规则顺序按「谁会被谁抢」排：

```
Speed → Youtube → Netflix → TikTok → AI → Github → Microsoft → Apple → Games → Google
```

- `AI` 必须排在 `Google` 之前，否则 `gemini.google.com`、`aistudio.google.com`
  会先被 Google 组吃掉，AI 组形同虚设；
- `Youtube` 必须排在 `Google` 之前，否则 `googlevideo.com` 的 CDN 流量会落到 Google 组。

`youtube` / `netflix` / `tiktok` 三组仍受 `routing.platform_youtube` 等开关控制，
置 0 就不生成对应规则（该平台回落 `PROXY`）。

### 选择持久化

`select` 组的手动选择默认只存在内存里，进程重启就回落到第一项——面板显示
「Netflix 走 自动-日本」，实际流量却走 `所有-自动`。所以生成的配置里固定写入：

```yaml
store-selected: true
```

选择结果落在 `/etc/easyproxy/mihomo/cache.db`，重启后仍然保留。真机验证：
把 `Youtube` 设成 `自动-美国` → `easyproxy restart` → 复查仍是 `自动-美国`。

### 与 sing-box 的差异

sing-box 侧（`config.sh`）目前仍把三个平台规则指向 `PROXY`，没有场景组。
两引擎在「平台分流去哪里」这一点上行为不一致，以 mihomo 为准，sing-box
待同步。

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
