# EasyProxy

EasyProxy is a modular proxy-management package for ImmortalWrt, with a Chinese
LuCI management panel.

## Current stage — Stage 3: real runtime

Stage 3 leaves the scaffolding behind and manages an actual proxy process:

| Layer | What exists now |
|---|---|
| UCI config | `/etc/config/easyproxy` (global, routing, engine, node sections) |
| Config generation | `easyproxy config generate` → sing-box JSON from `config node` sections, validated by `sing-box check` |
| Runtime | `easyproxy run` (foreground wrapper) supervised by procd with respawn |
| CLI | `status`, `validate`, `engine`, `config generate`, `start`, `stop`, `restart`, `run`, `log` |
| LuCI panel | `服务 → EasyProxy → 运行总览` shows live runtime state, pid, uptime and config state |

Stage 3 covers the **sing-box** engine only. Selecting `dae` is accepted by the
CLI, but `start` refuses it explicitly instead of pretending to run something.
Split routing (China direct, everything else proxied) is still Stage 4: today the
generated config exposes a mixed inbound on `127.0.0.1:7890` for clients that can
use it, and routes everything through the `proxy` group.

### Runtime model

```
/etc/config/easyproxy          (nodes, engine, listen options)
        ↓ ep_config_build
/etc/easyproxy/sing-box.json   (validated with `sing-box check`)
        ↓ easyproxy run
sing-box (child process)       ← procd supervises the wrapper, respawns on exit
        ↓ /var/run/easyproxy/easyproxy.pid  (pid + start timestamp)
easyproxy status --json        (pid, uptime, config state)
```

`easyproxy run` is what procd executes. It generates the config, writes the pid
file, starts the engine and waits for it. If the engine dies, the wrapper returns
its exit code, so procd restarts the instance.

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
  "version": "0.3.0",
  "stage": 3,
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
| `config_state` | `ok` / `invalid` / `missing`, verified with `sing-box check` |
| `nodes` / `nodes_enabled` | total node sections and how many are enabled |
| `enabled` / `engine` / `binary_ok` | real UCI values |

### Data path

```
/etc/config/easyproxy
        ↓ (uci)
/usr/sbin/easyproxy status --json
        ↓ (rpcd file.exec, ACL: luci-app-easyproxy)
/view/easyproxy/overview.js  →  cards, runtime block, config check
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
└── test-runtime.sh  # config generation + start/stop lifecycle
```

## Tests

Both suites run on any Linux shell, without OpenWrt and without a real engine
(a stub `sing-box` is generated inside a temp sandbox):

```sh
sh tests/test-cli.sh
sh tests/test-runtime.sh
# additionally validate the generated config against a real binary:
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/test-runtime.sh
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
easyproxy config generate       # writes and validates /etc/easyproxy/sing-box.json
/etc/init.d/easyproxy enable
/etc/init.d/easyproxy start
easyproxy status
```

To roll back: `easyproxy stop` and `uci set easyproxy.main.enabled='0'`. No
firewall, DNS or route table changes are made in Stage 3, so nothing else is
affected.

## Roadmap

| Stage | Scope |
|---|---|
| 1 | Packaging fix so the panel appears in LuCI |
| 2 | Panel reads real status/validation data |
| **3 (current)** | sing-box config generation + procd-supervised runtime |
| 4 | Firewall/DNS split routing (China direct, others proxy) |
| 5 | Operable panel: nodes, subscriptions, logs |

## License

MIT — see `LICENSE`.
