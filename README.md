# EasyProxy

EasyProxy is a modular proxy-management package for ImmortalWrt, with a Chinese
LuCI management panel.

## Current stage — Stage 2: real data on the panel

Stage 2 keeps the guarded core scaffold and adds a **read-only LuCI overview fed
by real data**:

| Layer | What exists now |
|---|---|
| UCI config | `/etc/config/easyproxy` (global, routing, engine defaults) |
| CLI | `easyproxy status [--json]`, `validate [--json]`, `engine`, `start`, `stop` |
| Backend data | `easyproxy status --json` — one JSON line, read by the panel via `rpcd file.exec` |
| LuCI panel | `服务 → EasyProxy → 运行总览` (sidebar + cards + policy panel) |
| init | refuses to start, because there is still **no proxy runtime** |

The panel no longer shows invented numbers. Every value on it comes from
`easyproxy status --json` (and `easyproxy validate --json` for the configuration
check block). Traffic charts and node lists are explicitly marked as
"not collected yet" instead of being faked.

### `easyproxy status --json`

```json
{
  "ok": true,
  "package": "easyproxy",
  "version": "0.2.0",
  "stage": 2,
  "enabled": 0,
  "engine": "none",
  "binary": "",
  "binary_ok": 0,
  "china_policy": "direct",
  "proxy_policy": "proxy",
  "fail_closed": 1,
  "nodes": 0,
  "runtime": "not_implemented",
  "config_file": "/etc/config/easyproxy",
  "generated": "2026-11-16T04:36:24Z"
}
```

| Field | Meaning |
|---|---|
| `enabled` | `1` when `easyproxy.main.enabled=1` |
| `engine` | `none` / `dae` / `sing-box` |
| `binary` / `binary_ok` | engine binary path and whether it is executable |
| `china_policy` / `proxy_policy` / `fail_closed` | real routing options from UCI |
| `nodes` | number of `config node` sections in UCI (named or anonymous) |
| `runtime` | `not_implemented` until the proxy process is supervised |

### Data path

```
/etc/config/easyproxy
        ↓ (uci)
/usr/sbin/easyproxy status --json
        ↓ (rpcd file.exec, ACL: luci-app-easyproxy)
/view/easyproxy/overview.js  →  cards, policy panel, config check
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
    ├── usr/lib/easyproxy/adapters/{dae.sh,sing-box.sh}
    ├── usr/share/luci/menu.d/luci-app-easyproxy.json
    ├── usr/share/rpcd/acl.d/luci-app-easyproxy.json
    └── www/luci-static/resources/view/easyproxy/overview.js
```

## Build

`.github/workflows/build.yml` downloads the official ImmortalWrt SDK
(25.12.2, x86-64), copies `package/easyproxy` into it and builds
`easyproxy_*` packages, then uploads the `easyproxy-immortalwrt-25.12.2-x86_64`
artifact. Runs on push/PR to `main`, on `workflow_dispatch`, and on `v*` tags.

## Install

```sh
opkg install --force-reinstall /tmp/easyproxy_*.ipk
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```

For apk-based images: `apk add --allow-untrusted /tmp/easyproxy_*.apk`.

Then open `服务 → EasyProxy` in LuCI. The panel is read-only; values change when
you edit `/etc/config/easyproxy` with `uci`.

## Roadmap

| Stage | Scope |
|---|---|
| 1 | Packaging fix so the panel appears in LuCI |
| **2 (current)** | Panel reads real status/validation data |
| 3 | init semantics + sing-box runtime (process supervision, config generation) |
| 4 | Firewall/DNS split routing (China direct, others proxy) |
| 5 | Operable panel: nodes, subscriptions, logs |

## License

MIT — see `LICENSE`.
