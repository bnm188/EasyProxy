# EasyProxy

EasyProxy is a modular proxy-management package for ImmortalWrt, with a Chinese
LuCI management panel.

## Current stage — Stage 6: maintenance CLI and multi-page panel (0.6.0)

Version `0.6.0` is the first release meant to be installed and used on a real
router. On top of split routing and reversible transparent capture it adds engine
management, node/subscription import, a full maintenance CLI and a ten-page
Chinese dark LuCI panel. One SSH command now also installs the two proxy kernels,
sing-box and dae, so the panel is usable as soon as it comes up.

| Layer | What exists now |
|---|---|
| UCI config | `/etc/config/easyproxy` (main, routing, transparent, engine, nodes) |
| Config generation | `easyproxy config generate` → sing-box JSON, validated by `sing-box check` |
| Split routing | `route.rules`: private IPs + CN rule sets → `direct`; `route.final` → `proxy` |
| Rule sets | local `.srs` under `rule_set_dir`, refreshed by `easyproxy ruleset update` |
| Transparent capture | `table ip easyproxy` (TPROXY) / `table ip6 easyproxy`; `transparent apply|remove|status|audit` |
| Engines | registry `sing-box:stable`, `dae:dev`; `engine list|health|version`, `node test` |
| Nodes | 8 share-link formats, `node list|add|import|export|del|test`, subscription fetch |
| Maintenance | `config backup|restore|reset`, `ruleset update|verify`, `doctor [--json]`, `log rotate`, `uninstall-clean` |
| LuCI panel | `服务 → EasyProxy`, ten views: overview, nodes, subscription, split, engines, DNS, rules, logs, backup, settings |
| Installer | one command installs panel + sing-box + dae; `upgrade` and `status` per component |

### Install in one line (SSH on the router)

```sh
# install the panel, sing-box and dae in one go
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh

# what is installed right now
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s status

# upgrade all three components (old -> new version per component, rollback on failure)
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s upgrade

# uninstall (config is kept; append --purge to drop it as well)
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
```

Both commands work on opkg and apk firmware, fall back to a version-derived
asset URL when `api.github.com` is rate-limited, and are safe to re-run. See
[Install](#install) for every flag, and
[`docs/router-install-test.md`](docs/router-install-test.md) for the
step-by-step acceptance test on a real router.

### Three safety locks (not configurable)

These are compiled into the generator, not options a user can flip:

| Lock | Behaviour |
|---|---|
| Mainland China is always `direct` | `china_policy='proxy'` is **rejected**: `config generate` refuses and tells you to set `direct`. There is no switch that turns CN traffic into proxied traffic |
| `fail_closed` is always on | when the CN rule sets are missing *and* cannot be downloaded, the generator emits a **pure-direct config** (`route.final` / `dns.final` = `direct`) and returns a warning. It never degrades into a full-tunnel proxy |
| Intranet never leaves the router | `10.10.10.10`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, every node server address, `transparent.exclude` and the router's own LAN addresses are all in `bypass_ipv4` / the direct rule set. LAN traffic is routed, not captured: it never enters the engine |

Read it as: a broken or missing rule set costs you foreign websites, never your
LAN. `easyproxy doctor` reports both locks as `ok` when they hold. `install.sh`
never writes any of these fields: it only installs binaries and points UCI at
them.

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
| files missing, download fails | `fail_closed` takes over: the config is generated **all-direct** and `config generate` exits non-zero, so nothing falls through to the proxy |
| no enabled nodes | `route.final` and `dns.final` fall back to `direct` / `dns-local` |

The engine start path (`easyproxy run`, and the procd `start_service`) never
hits the network: downloads only happen in `config generate` / `easyproxy start`.

### Transparent capture

Everything the capture needs lives in **our own namespace**:

| Object | Name | Why |
|---|---|---|
| nft table | `table ip easyproxy` | never touches fw4's tables, so removing it cannot damage the router's firewall |
| chain | `prerouting` (priority `mangle`) | intercepts LAN input before routing |
| set | `bypass_ipv4` | private ranges + every node server address + `transparent.exclude` |
| policy rule | `fwmark <mark> lookup <table>` | sends the marked packets back to the local stack |
| route table | `local default dev lo` | the destination the mark resolves to |
| generated file | `/etc/easyproxy/nftables.conf` | what actually got loaded, so `nft -f` can be replayed or inspected |

Capture tracer: LAN packet → `prerouting` (only the listed interfaces, bypass
set and the `mixed` port return early) → `tproxy to :7891` + `meta mark set 1` →
`tproxy-in` → sniffed domain → split routing from Stage 4.

`easyproxy transparent apply` refuses to run — and applies nothing — when any of
these is true, because each one would black-hole the LAN:

| Refusal | Reason |
|---|---|
| `transparent.enabled=0` | feature is off |
| no enabled nodes | captured traffic would have nowhere to go |
| `nft` missing or not runnable | nothing to load the rules with |
| engine not running | a tproxy rule without a listener drops packets |

Rollback is two deletes plus two `ip` deletes: `easyproxy transparent remove`
(also invoked automatically by `easyproxy stop` and the init script's
`stop_service`). It never needs to know what the firewall looked like before.

Kernel note: the tproxy listener needs `CAP_NET_ADMIN` (`IP_TRANSPARENT`). On a
router the engine runs as root under procd, so this is satisfied; in an
unprivileged container sing-box exits with
`configure tproxy TCP listener: operation not permitted` (verified), which means
the config is correct but the host cannot intercept. `sing-box check` cannot
detect this — it validates syntax only.

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
  "inbounds": [
    { "type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 7890 },
    /* only when transparent.enabled=1 and a node exists */
    { "type": "tproxy", "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": 7891,
      "sniff": true, "sniff_override_destination": true, "udp_timeout": "5m" }
  ],
  "outbounds": [
    /* one per enabled node */,
    { "type": "urltest", "tag": "proxy", "outbounds": ["hk-01"], "url": "http://www.gstatic.com/generate_204", "interval": "5m", "tolerance": 50 },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "auto_detect_interface": true,   /* only with the tproxy inbound */
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
| `routing.china_policy` | `direct` | locked: CN traffic always bypasses the proxy, `proxy` is rejected |
| `routing.proxy_policy` | `proxy` | group used for non-CN traffic and remote DNS |
| `routing.fail_closed` | `1` | locked: with CN rule sets missing the config is all-direct; there is no full-tunnel fallback |
| `routing.rule_set_dir` | `/etc/easyproxy/ruleset` | where the `.srs` files live |
| `routing.geosite_cn_url` | SagerNet `geosite-cn.srs` | domain rule-set source |
| `routing.geoip_cn_url` | SagerNet `geoip-cn.srs` | address rule-set source |
| `routing.rule_set_update_days` | `7` | refresh a cached file older than this |
| `routing.dns_local_server` | `223.5.5.5` | domestic resolver |
| `routing.dns_remote_server` | `https://1.1.1.1/dns-query` | remote DoH resolver |

### Transparent capture options

| UCI option | Default | Meaning |
|---|---|---|
| `transparent.enabled` | `0` | master switch; nothing is captured unless this is `1` **and** the engine is running |
| `transparent.tproxy_port` | `7891` | the `tproxy-in` listen port (must match the generated config) |
| `transparent.fwmark` | `1` | mark written by nft and matched by the policy rule |
| `transparent.route_table` | `100` | table holding `local default dev lo` |
| `transparent.lan_interfaces` | `br-lan` | interfaces whose input is captured, space separated |
| `transparent.exclude` | *(empty)* | extra IPv4 addresses/CIDRs that must stay direct |
| `transparent.ipv6_policy` | `direct` | `direct` or `block`: IPv6 is never captured silently |

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

Share links are the quicker path — `easyproxy node add '<link>'` understands
ss://, ssr://, vmess://, trojan://, vless://, hysteria2://, tuic:// and
socks://; `easyproxy node import <file>` reads a batch, `easyproxy node export`
prints them back, and `sub.sh`-style subscriptions are fetched by
`/usr/lib/easyproxy/subscribe.sh <url>` (the URL is never written to UCI or
the log).

### `easyproxy status --json`

```json
{
  "ok": true,
  "package": "easyproxy",
  "version": "0.6.0",
  "stage": 6,
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
  "transparent": 1,
  "tproxy_port": 7891,
  "tproxy_state": "active",
  "ipv6_policy": "direct",
  "ipv6_state": "direct",
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
| `transparent` | `1` when capture is configured (not when it is actually loaded) |
| `tproxy_state` | `active` (table loaded) / `inactive` / `unsupported` (no usable nft) |
| `ipv6_state` | `direct` / `block` / `unsupported` (no `ip6tables`-capable nft) |
| `config_state` | `ok` / `invalid` / `missing`, verified with `sing-box check` |
| `nodes` / `nodes_enabled` | total node sections and how many are enabled |

### Data path

```
/etc/config/easyproxy
        ↓ (uci)
/usr/sbin/easyproxy status --json
        ↓ (rpcd file.exec, ACL: luci-app-easyproxy)
/usr/lib/easyproxy/app.js  →  overview / nodes / subscription / split / engines /
                              dns / rules / logs / backup / settings
```

## Layout

```
package/easyproxy/
├── Makefile
└── files/
    ├── etc/config/easyproxy
    ├── etc/init.d/easyproxy
    ├── etc/hotplug.d/iface/95-easyproxy
    ├── usr/sbin/easyproxy
    ├── usr/lib/easyproxy/common.sh
    ├── usr/lib/easyproxy/config.sh
    ├── usr/lib/easyproxy/transparent.sh
    ├── usr/lib/easyproxy/node.sh
    ├── usr/lib/easyproxy/maint.sh
    ├── usr/lib/easyproxy/traffic.sh
    ├── usr/lib/easyproxy/subscribe.sh
    ├── usr/lib/easyproxy/adapters/{dae.sh,sing-box.sh}
    ├── usr/share/easyproxy/easyproxy.default
    ├── usr/share/luci/menu.d/luci-app-easyproxy.json
    ├── usr/share/rpcd/acl.d/luci-app-easyproxy.json
    ├── www/luci-static/resources/easyproxy/app.js
    └── www/luci-static/resources/view/easyproxy/*.js   (10 views)
scripts/
├── make-ipk.sh          # build the ipk (all / x86_64 / ...) from package/easyproxy
├── make-kernel-ipk.sh   # build sing-box_<ver>_<arch>.ipk / dae_<ver>_<arch>.ipk
├── install.sh           # one-line installer: panel + sing-box + dae, upgrade, status
└── uninstall.sh         # one-line uninstaller: backup, --purge, --keep-kernels
tests/
├── test-cli.sh             # CLI surface (status/validate/engine/start guard)
├── test-runtime.sh         # config generation + start/stop lifecycle
├── test-routing.sh         # split routing, DNS block, rule-set handling
├── test-transparent.sh     # tproxy inbound, nft/ip takeover, IPv6 policy, rollback
├── test-engine.sh          # engine registry, health probes, node probe, dev refusal
├── test-nodes.sh           # share-link parsing, groups, platform/custom rules
├── test-maintenance.sh     # backup/restore/reset, ruleset update+verify, doctor, log rotate
├── test-ipk-layout.sh      # ipk payload + control metadata, all and x86_64
└── test-install-scripts.sh # installer/uninstaller against stubbed opkg/apk/curl
docs/
└── router-install-test.md  # step-by-step acceptance test on a real router
```

## Tests

All suites run on any Linux shell, without OpenWrt and without a real engine
(a stub `sing-box` is generated inside a temp sandbox; the routing suite compiles
its own rule-set fixtures with the real binary when one is supplied):

```sh
for t in tests/test-*.sh; do sh "$t" || break; done

# additionally validate the generated config against a real binary:
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/test-runtime.sh
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/test-routing.sh
EP_SING_BOX_BIN=/usr/bin/sing-box sh tests/test-transparent.sh
```

Nine suites, 464 checks: routing 32, transparent 84, nodes 61, engine 44,
maintenance 44, install scripts 119, ipk layout 40, CLI 21, runtime 19
(`runtime` and `transparent` hold 19 and 84 without a real `sing-box` binary,
which is also what CI runs).

The install-script suite stubs `opkg`, `apk`, `curl`, `uci` and the init/rpcd
scripts in a sandbox, so it covers both package managers, the API-unreachable
fallback, the rootfs route, the arch-matched ipk choice, the three-component
install, both kernels (sha256, architecture, reuse, failure), `upgrade` with its
version table and rollback, `status`, and the uninstall ordering, backup,
`--purge` and `--keep-kernels` without touching `/etc` at all.

The transparent suite stubs `nft` and `ip`, so the takeover state machine is
exercised (apply, idempotent re-apply, rollback, refusals, missing nft)
without touching the host's firewall and without root.

## Build

`.github/workflows/build.yml` downloads the official ImmortalWrt SDK
(25.12.2, x86-64), runs the repo test suites, copies `package/easyproxy` into the
SDK and builds the native package, then builds the two kernel packages for
x86_64, `aarch64_cortex-a53` and `arm_cortex-a7_neon-vfpv4` out of the official
upstream archives (each checked against a pinned sha256), writes `KERNEL-VERSIONS`
and uploads the `easyproxy-immortalwrt-25.12.2` artifact. Runs on push/PR to `main`,
on `workflow_dispatch`, and on `v*` tags. A failing suite stops the build before
anything is published.

Every release carries the three components as separate packages plus checksums:

| Asset | For |
|---|---|
| `easyproxy_<ver>-1_all.ipk` | any opkg firmware, architecture-independent |
| `easyproxy_<ver>-1_x86_64.ipk` | opkg firmware that refuses `Architecture: all` (x86_64 targets) |
| `easyproxy-<ver>-1.apk` | ImmortalWrt 25.x images using `apk` |
| `easyproxy-<ver>-rootfs.tar.gz` | no matching package manager: extract at `/` |
| `sing-box_<ver>_<arch>.ipk` | sing-box kernel, one package per architecture |
| `dae_<ver>_<arch>.ipk` | dae kernel, binary plus `/usr/share/dae` routing assets |
| `SHA256SUMS` | sha256 of every asset above, kernels included |
| `KERNEL-VERSIONS` | the kernel versions and architectures this release pins |

`<arch>` is one of `x86_64`, `aarch64_cortex-a53`, `arm_cortex-a7_neon-vfpv4`.
The kernels cannot live inside `easyproxy_..._all.ipk`: that package is
architecture-independent, so an amd64 binary would be installed on an ARM router.
Three separate packages also mean three separate upgrades and three separate
removals, which is what the installer drives.

`sh scripts/make-ipk.sh package/easyproxy dist all` and
`sh scripts/make-ipk.sh package/easyproxy dist x86_64` build the two ipk flavours
locally; the architecture is stamped into the `control` member.
`sh scripts/make-kernel-ipk.sh sing-box x86_64 dist` and
`sh scripts/make-kernel-ipk.sh dae x86_64 dist` build the kernel packages the
same way the workflow does.

## Install

### One-line install from GitHub

On the router, over SSH, the whole install is one command:

```sh
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh
```

One command installs all three components. It:

1. detects the firmware (`opkg` or `apk`) and refuses to continue when neither
   exists and `--rootfs` was not asked for;
2. picks the matching asset of the **latest release**: on opkg firmware the ipk
   that matches this host's architecture (falling back to `_all.ipk` when there
   is no arch-specific one or when it fails to download), on apk images the
   `.apk`, and for `--rootfs` the rootfs archive;
3. verifies **every** download against `SHA256SUMS` before anything is installed
   and refuses a package that is not the one the checksum file describes;
4. installs the panel, then the sing-box kernel, then the dae kernel - each from
   its own release asset when the release carries one
   (`sing-box_<ver>_<arch>.ipk`, `dae_<ver>_<arch>.ipk`, installed through the
   package manager so opkg owns the files), otherwise from the official upstream
   archive with the sha256 pinned inside the script, unpacked, checked to be a
   real ELF executable and installed to `/usr/bin/sing-box` and `/usr/bin/dae`
   (`/usr/share/dae` for dae's `geoip.dat` / `geosite.dat`);
5. records what it installed in `/etc/easyproxy/owned/`, so a later uninstall
   removes only those files and never a kernel the user installed themselves;
6. points `easyproxy.sing_box.binary` / `easyproxy.dae.binary` at them, leaves
   `main.engine` untouched unless it is still empty or `none`, enables the
   service and restarts `rpcd` so the LuCI menu shows up;
7. runs `<binary> version` on both kernels, prints a per-component summary and
   exits non-zero if anything did not install. A failed download or checksum is
   reported as a failure - the script never prints success over a broken install.

Re-running it is safe: an already present kernel of the right version is reused
instead of downloaded again.

| Command | What it does |
|---|---|
| `sh install.sh` | install panel + sing-box + dae |
| `sh install.sh upgrade` | upgrade all three, with a version table |
| `sh install.sh upgrade --only dae` | upgrade one component only |
| `sh install.sh status` | installed versions of all three |
| `sh install.sh --ipk` | force the `.ipk` asset |
| `sh install.sh --apk` | force the `.apk` asset |
| `sh install.sh --rootfs` | skip the package manager, extract the rootfs archive at `/` |
| `sh install.sh --no-sing-box` | panel + dae only |
| `sh install.sh --no-dae` | panel + sing-box only |
| `sh install.sh --no-engine` | panel only, no kernel |
| `sh install.sh --help` | usage, no network access |

### Upgrade and status

```sh
# all three components, after printing what changes
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s upgrade

# one component only
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s upgrade --only package    # panel
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s upgrade --only sing-box  # kernel
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s upgrade --only dae       # kernel

# what is on disk right now
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh -s status
```

`upgrade` prints the current and newest version of each component first, then
upgrades only those whose version differs:

```
component    current      newest
easyproxy    0.6.0-1      0.6.0-1
sing-box     1.9.0        1.10.7
dae          2.1.0        2.1.2
```

Before a kernel is replaced its old binary is copied to
`/etc/easyproxy/backup/<kernel>.old`. The new one must answer `<binary> version`,
otherwise the old binary is restored, the component is reported as
`upgrade incomplete` and the command exits non-zero. The service is stopped for
the duration of the upgrade and started again afterwards.

Without a pipe, the same two actions run from a local copy:
`sh scripts/install.sh upgrade` and `sh scripts/install.sh status`.

### Uninstall

```sh
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
```

It removes the nftables capture first, then stops the service, then removes the
package — in that order, so LAN traffic is never left pointing at a dead listener.
Before anything is removed, a backup of the config and state is written to
`/root/easyproxy-backup-<date>-<time>.tar.gz` and its path is printed.
`/etc/config/easyproxy` and `/etc/easyproxy` are kept afterwards.

| Command | What it does |
|---|---|
| `sh uninstall.sh` | remove everything, keep config and state, keep a backup |
| `sh uninstall.sh --purge` | remove the package, the config and the state too |
| `sh uninstall.sh --keep-config` | explicit alias of the default |
| `sh uninstall.sh --keep-kernels` | remove only the panel, leave sing-box and dae |
| `sh uninstall.sh --no-backup` | do not write the backup archive |

The kernels are only removed when this installer put them there: their paths are
listed in `/etc/easyproxy/owned/`, and a `sing-box` or `dae` the user installed
themselves has no such record, so it is never touched.

Both scripts are idempotent, and both still work when `api.github.com` is
rate-limited or unreachable: the asset URL is then rebuilt from `PKG_VERSION`
in `package/easyproxy/Makefile`. Only `curl` or `wget` is required.

Prefer to read before running? Fetch, inspect, then execute:

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh
sh /tmp/install.sh
```

### From a package you downloaded yourself

```sh
opkg install --force-reinstall /tmp/easyproxy_*.ipk
opkg install /tmp/sing-box_*.ipk   # or install the kernel yourself and point
opkg install /tmp/dae_*.ipk        # easyproxy.sing_box.binary / easyproxy.dae.binary at it
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
`geoip-cn.srs` to `/etc/easyproxy/ruleset/` by hand and run it again —
`fail_closed` takes over until the two files are back: the config is generated
all-direct, `config generate` exits non-zero, and `status` reports
`rule_set_state: missing`. CN sites and the LAN never depend on them; only
foreign sites wait.

Capture is off by default. To let the router proxy the whole LAN:

```sh
uci set easyproxy.transparent.enabled='1'
uci set easyproxy.transparent.lan_interfaces="$(uci get network.lan.device 2>/dev/null || echo br-lan)"
uci commit easyproxy
easyproxy restart          # regenerates the config (adds tproxy-in), applies the capture
easyproxy transparent status
```

A LAN client then needs nothing configured at all. To roll the capture back
without touching anything else:

```sh
easyproxy transparent remove
uci set easyproxy.transparent.enabled='0'
uci commit easyproxy
easyproxy restart
```

`remove` deletes `table ip easyproxy` and the policy rule/route it created;
nothing else on the router is modified. To stop EasyProxy entirely:
`easyproxy stop` (which removes the capture first) and
`uci set easyproxy.main.enabled='0'`.

## Maintenance

```sh
easyproxy config backup        # /etc/easyproxy/backups/easyproxy-<date>.tar.gz
easyproxy config restore <f>   # keeps <config>.before-restore first
easyproxy config reset         # back to the packaged defaults, keeps .before-reset
easyproxy ruleset update       # download .new then move it, a failure keeps the old file
easyproxy ruleset verify       # exists / non-empty / SRS magic / plausible size
easyproxy doctor [--json]      # 11 checks: locks, engines, rule sets, capture, config
easyproxy log rotate           # <log> -> <log>.1, then truncate
easyproxy uninstall-clean      # delete only EasyProxy's own nft objects
```

`uninstall-clean` is what `scripts/uninstall.sh` calls first, and it prints
`stock ImmortalWrt rules untouched` — the router's own firewall is never
rewritten, not even during removal.

## Roadmap

| Stage | Scope |
|---|---|
| 1 | Packaging fix so the panel appears in LuCI |
| 2 | Panel reads real status/validation data |
| 3 | sing-box config generation + procd-supervised runtime |
| 4 | Split routing + DNS (China direct, others proxied), local rule sets |
| 5 | Transparent capture: own nft table + policy routing, reversible in one command |
| **6 (current, 0.6.0)** | Engine registry, node/subscription import, maintenance CLI (`config backup/restore/reset`, `ruleset update/verify`, `doctor`, `log rotate`, `uninstall-clean`), ten-page panel |
| 7 (done in 0.6.0) | Compile/install/uninstall verification: dual ipk (all + x86_64), CI test gate, arch-aware installer, on-router acceptance checklist in `docs/router-install-test.md` |

Transparent capture got its own stage because it is the one change that touches
firewall state on the user's router. It is kept out of fw4 entirely and ships
with a rollback that only deletes objects EasyProxy created.

## License

MIT — see `LICENSE`.
