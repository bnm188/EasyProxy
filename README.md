# EasyProxy

EasyProxy is a modular proxy-management package for ImmortalWrt, with a Chinese
LuCI management panel.

## Current stage — Stage 4: split routing and DNS

Stage 4 turns the generated config into a real split-routing setup: Chinese
domains and addresses go out through `direct`, everything else falls through to
the node group, and DNS is split the same way.

| Layer | What exists now |
|---|---|
| UCI config | `/etc/config/easyproxy` (global, routing, engine, node sections) |
| Config generation | `easyproxy config generate` → sing-box JSON from `config node` sections, validated by `sing-box check` |
| Split routing | `route.rules`: private IPs + CN rule sets → `direct`; `route.final` → `proxy` |
| Rule sets | downloaded once by `config generate` into `rule_set_dir`, then referenced as **local** files |
| DNS | `dns-local` (domestic, `detour: direct`) + `dns-remote` (DoH, `detour: proxy`); CN names resolve domestically |
| Runtime | `easyproxy run` (foreground wrapper) supervised by procd with respawn |
| CLI | `status`, `validate`, `engine`, `config generate`, `start`, `stop`, `restart`, `run`, `log` |
| LuCI panel | `服务 → EasyProxy → 运行总览` shows runtime, split mode, rule-set state and config state |

Stage 4 covers the **sing-box** engine only. Selecting `dae` is accepted by the
CLI, but `start` refuses it explicitly instead of pretending to run something.
Transparent proxying (firewall/route table takeover) is deliberately *not* part
of this stage — see the roadmap.

### Why rule sets are local files

A `type: remote` rule set makes the engine download on startup, and a failed
download is fatal: `start service: initialize rule-set` kills the whole process,
so the router cannot start the proxy at boot without internet (verified against
sing-box 1.10.7). EasyProxy therefore fetches the two `.srs` files during
`config generate`, stores them under `rule_set_dir`, and emits
`{"type": "local", "path": ...}`.

| Situation | Behaviour |
|---|---|
| files present and fresh | split routing active |
| files missing, download succeeds | split routing active, files cached locally |
| files missing, download fails | **warning**, generator still succeeds, split degrades to full proxy (only the private-IP rule survives) |
| `china_policy='proxy'` | no CN rule at all, everything goes through the node group |
| no enabled nodes | `route.final` and `dns.final` fall back to `direct` / `dns-local` |

The engine start path (`easyproxy run`, and the procd `start_service`) never
hits the network: downloads only happen in `config generate` / `easyproxy start`.

### Generated config shape

```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "dns-local",  "address": "223.5.5.5", "detour": "direct" },
      { "tag": "dns-remote", "address": "https://1.1.1.1/dns-query", "detour": "proxy" }
    ],
    "rules": [
      { "domain_suffix": [".cn"], "server": "dns-local" },
      { "rule_set": ["geosite-cn"], "server": "dns-local" },
      { "ip_is_private": true, "server": "dns-local" }
    ],
    "final": "dns-remote"
  },
  "inbounds": [ { "type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 7890 } ],
  "outbounds": [
    /* one per enabled node */,
    { "type": "urltest", "tag": "proxy", "outbounds": ["hk-01"], "url": "http://www.gstatic.com/generate_204", "interval": "5m", "tolerance": 50 },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "ip_is_private": true, "outbound": "direct" },
      { "rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct" }
    ],
    "rule_set": [
      { "type": "local", "tag": "geosite-cn", "format": "binary", "path": "/etc/easyproxy/ruleset/geosite-cn.srs" },
      { "type": "local", "tag": "geoip-cn", "format": "binary", "path": "/etc/easyproxy/ruleset/geoip-cn.srs" }
    ],
    "final": "proxy"
  }
}
```

### Routing options

| UCI option | Default | Meaning |
|---|---|---|
| `routing.china_policy` | `direct` | `direct` = CN traffic bypasses the proxy |
| `routing.proxy_policy` | `proxy` | group used for non-CN traffic and remote DNS |
| `routing.fail_closed` | `1` | record only in this stage |
| `routing.rule_set_dir` | `/etc/easyproxy/ruleset` | where the `.srs` files live |
| `routing.geosite_cn_url` | SagerNet `geosite-cn.srs` | domain rule-set source |
| `routing.geoip_cn_url` | SagerNet `geoip-cn.srs` | address rule-set source |
| `routing.rule_set_update_days` | `7` | refresh a cached file older than this |
| `routing.dns_local_server` | `223.5.5.5` | domestic resolver |
| `routing.dns_remote_server` | `https://1.1.1.1/dns-query` | remote DoH resolver |

### Runtime model

```
/etc/config/easyproxy            (nodes, engine, routing, DNS options)
        ↓ ep_rule_set_ensure     (download .srs into rule_set_dir, cached)
        ↓ ep_config_build
/etc/easyproxy/sing-box.json     (validated with `sing-box check`)
        ↓ easyproxy run
sing-box (child process)         ← procd supervises the wrapper, respawns on exit
        ↓ /var/run/easyproxy/easyproxy.pid  (pid + start timestamp)
easyproxy status --json          (pid, uptime, config state, split state)
```

### Node schema

Every `config node` section becomes one sing-box outbound. Enabled nodes are put
behind a latency-tested `proxy` group (`urltest`, 5m interval):

```sh
uci add easyproxy node
uci set easyproxy.@node[-1].name='hk-01'
uci set easyproxy.@node[-1].type='shadowsocks'    # shadowsocks | vmess | trojan | socks | http
uci set easyproxy.@node[-1].server='203.0.113.10'
uci set easyproxy.@node[-1].port='8388'
uci set easyproxy.@node[-1].method='aes-256-gcm'
uci set easyproxy.@node[-1].password='secret'
uci commit easyproxy
```

Per type: `shadowsocks` needs `method` + `password`; `vmess` needs `uuid`
(optional `alter_id`); `trojan` needs `password`; `socks`/`http` accept optional
`username`/`password`. `tls` + `sni` apply to `trojan` and `vmess`. Any node can
be skipped with `enabled '0'`. A node missing a required field aborts generation
with the section named, rather than emitting a config that would fail later.

### `easyproxy status --json`

```json
{
  "ok": true,
  "package": "easyproxy",
  "version": "0.4.0",
  "stage": 4,
  "enabled": 1,
  "engine": "sing-box",
  "binary": "/usr/bin/sing-box",
  "binary_ok": 1,
  "china_policy": "direct",
  "proxy_policy": "proxy",
  "fail_closed": 1,
  "nodes": 2,
  "nodes_enabled": 2,
  "runtime": "running",
  "runtime_pid": 1234,
  "runtime_uptime": 87,
  "china_rule": 1,
  "route_rules": 2,
  "dns_mode": "split",
  "rule_set_state": "ready",
  "config_state": "ok",
  "config_path": "/etc/easyproxy/sing-box.json",
  "config_file": "/etc/config/easyproxy",
  "generated": "2026-11-16T05:20:00Z"
}
```

| Field | Meaning |
|---|---|
| `runtime` | `running` / `stopped`, read from the pid file, not from a flag |
| `runtime_pid` / `runtime_uptime` | wrapper pid and seconds since it started (`0` when stopped) |
| `china_rule` | `1` when the CN direct rule is generated, `0` when traffic is fully proxied |
| `route_rules` | number of `route.rules` entries (`1` = private IP only, `2` = private IP + CN) |
| `dns_mode` | `split` (domestic + remote resolvers) or `local` (single resolver) |
| `rule_set_state` | `ready` / `missing`, from the `.srs` files on disk |
| `config_state` | `ok` / `invalid` / `missing`, verified with `sing-box check` |
| `nodes` / `nodes_enabled` | total node sections and how many are enabled |

### Data path

```
/etc/config/easyproxy
        ↓ (uci)
/usr/sbin/easyproxy status --json
        ↓ (rpcd file.exec, ACL: luci-app-easyproxy)
/view/easyproxy/overview.js  →  cards, split mode, rule-set state, config check
```

## Layout

```
package/easyproxy/
├── Makefile
└── files/
    ├── etc/config/easyproxy
    ├── etc/init.d/easyproxy
    ├── usr/sbin/easyproxy
    ├── usr/lib/easyproxy/common.sh
    ├── usr/lib/easyproxy/config.sh
    ├── usr/lib/easyproxy/adapters/{dae.sh,sing-box.sh}
    ├── usr/share/luci/menu.d/luci-app-easyproxy.json
    ├── usr/share/rpcd/acl.d/luci-app-easyproxy.json
    └── www/luci-static/resources/view/easyproxy/overview.js
tests/
├── test-cli.sh      # CLI surface (status/validate/engine/start guard)
├── test-runtime.sh  # config generation + start/stop lifecycle
└── test-routing.sh  # split routing, DNS block, rule-set handling
```

## Tests

All suites run on any Linux shell, without OpenWrt and without a real engine
(a stub `sing-box` is generated inside a temp sandbox; the routing suite compiles
its own rule-set fixtures with the real binary when one is supplied):

```sh
sh tests/test-cli.sh
sh tests/test-runtime.sh
sh tests/test-routing.sh
# additionally validate the generated config against a real binary:
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/test-runtime.sh
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/test-routing.sh
```

## Build

`.github/workflows/build.yml` downloads the official ImmortalWrt SDK
(25.12.2, x86-64), copies `package/easyproxy` into it and builds
`easyproxy_*` packages, then uploads the `easyproxy-immortalwrt-25.12.2-x86_64`
artifact. Runs on push/PR to `main`, on `workflow_dispatch`, and on `v*` tags.

## Install

```sh
opkg install --force-reinstall /tmp/easyproxy_*.ipk
opkg install sing-box           # or drop a static binary and set easyproxy.sing_box.binary
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```

For apk-based images: `apk add --allow-untrusted /tmp/easyproxy_*.apk`.

Then configure and start it from the shell:

```sh
uci set easyproxy.main.engine='sing-box'
uci set easyproxy.main.enabled='1'
uci commit easyproxy
easyproxy config generate       # downloads rule sets, writes and validates the config
/etc/init.d/easyproxy enable
/etc/init.d/easyproxy start
easyproxy status
```

`config generate` needs network access the first time so the two `.srs` files
can be cached. On a router without internet, copy `geosite-cn.srs` and
`geoip-cn.srs` to `/etc/easyproxy/ruleset/` by hand and run it again — otherwise
the split degrades to full proxy and `status` reports `rule_set_state: missing`.

To roll back: `easyproxy stop` and `uci set easyproxy.main.enabled='0'`. No
firewall table or system-wide DNS is touched, so a client that is not pointed at
`127.0.0.1:7890` is unaffected.

## Roadmap

| Stage | Scope |
|---|---|
| 1 | Packaging fix so the panel appears in LuCI |
| 2 | Panel reads real status/validation data |
| 3 | sing-box config generation + procd-supervised runtime |
| **4 (current)** | Split routing + DNS (China direct, others proxied), local rule sets |
| 5 | Transparent proxy: nftables/route takeover so LAN traffic is captured |
| 6 | Operable panel: nodes, subscriptions, logs |

Transparent proxying was moved behind the split because it rewrites firewall
rules on the user's router; it is the one change that is not cheap to undo, so it
gets its own stage with its own rollback path.

## License

MIT — see `LICENSE`.
