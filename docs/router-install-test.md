# On-router install test

The last stage-7 item is the only one that cannot run in CI: it needs a real
ImmortalWrt box. Work through the list in order; every step names the exact
command and the expected output. Stop at the first step that does not match and
collect the diagnostics printed by `easyproxy doctor` before unpinning anything.

## 0. Before you start

```sh
uname -a
cat /etc/openwrt_release
opkg --version 2>/dev/null || apk --version 2>/dev/null
ip -4 addr show | grep -E 'inet ' ; uci get network.lan.ifname 2>/dev/null
```

Expected: an ImmortalWrt/OpenWrt build, exactly one package manager, at least one
LAN interface. Note the package manager — it decides which asset the installer
picks.

Record the pre-install state so the rollback check has a baseline:

```sh
nft list tables > /tmp/tables.before 2>&1
ip rule show > /tmp/rules.before
ip route show table 100 > /tmp/table100.before 2>&1
```

## 1. Install

```sh
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh
```

Expected tail: the installer prints the asset it downloaded, `opkg install` (or
`apk add --allow-untrusted`) succeeds, the service is enabled, `rpcd` is
restarted, and `easyproxy status` prints a table.

```sh
easyproxy status
```

Expected: `Version: 0.7.0`, `Stage: 6`, `Enabled: 0`, engine `sing-box`,
`China policy: direct`, `Fail closed: 1`. No runtime pid yet — the service is
installed, not started.

Failure to check: if `Architecture` is refused by opkg, install the x86_64 asset
instead: download `easyproxy_0.7.0-1_x86_64.ipk` from the release page and run
`opkg install --force-reinstall /tmp/easyproxy_0.7.0-1_x86_64.ipk`.

## 2. Panel

Open `服务 → EasyProxy` in LuCI (log out and back in if the menu is missing —
rpcd caches its ACLs).

Expected: ten menu entries and a dark overview page showing version, engine, node
count, split mode, capture state and a live traffic curve refreshing every two
seconds. No browser console errors; if `fs.exec` is denied, `rpcd` was not
restarted.

## 3. Rule sets + config

```sh
easyproxy ruleset update
easyproxy ruleset verify
```

Expected: `ruleset: 2 ok, 0 fail` and two files under `/etc/easyproxy/ruleset/`.

```sh
easyproxy config generate && easyproxy validate
```

Expected: the generated config validates. Deliberately break it to prove the
locks:

```sh
uci set easyproxy.routing.china_policy='proxy'; easyproxy config generate
```

Expected: **refused** with `routing.china_policy=proxy is locked out ...` and a
non-zero exit. Then:

```sh
uci set easyproxy.routing.china_policy='direct'
mv /etc/easyproxy/ruleset/geosite-cn.srs /tmp/ ; \
  uci set easyproxy.routing.geosite_cn_url='https://127.0.0.1/none'; easyproxy config generate
```

Expected: exit non-zero, the generated config has `route.final` and
`dns.final` = `direct`, and the log says the CN rule sets are missing. This is
`fail_closed`: no full-tunnel fallback. Restore the file and the URL afterwards.

## 4. Engine and capture

Install the matching sing-box binary and one real node first
(`easyproxy node add '<share link>'`, `easyproxy node test`).

```sh
easyproxy start
easyproxy status
```

Expected: runtime pid, listen port open, node probe ok.

```sh
easyproxy transparent apply
easyproxy transparent status
nft list table ip easyproxy | head -40
ip rule show | grep fwmark
```

Expected: `table ip easyproxy` exists with a `prerouting` chain and a
`bypass_ipv4` set, and one `fwmark` policy rule. Then verify the intranet lock —
this is the whole point of the release:

```sh
ip -4 route get 10.10.10.10
ping -c 2 10.10.10.10
nft get element ip easyproxy bypass_ipv4 '{ 10.10.10.10 }' 2>/dev/null || true
```

Expected: `10.10.10.10` resolves on the LAN route, the ping goes out **without**
hitting the proxy (watch `/proc/net/dev` on the LAN interface: RX/TX move, the
proxy's own counters do not), and the element lookup shows it in `bypass_ipv4`.
Repeat for one address in each of `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.

Then a Chinese site and a foreign site:

```sh
wget -q -O /dev/null --timeout=3 https://www.baidu.com && echo cn-ok
easyproxy node test
```

Expected: `cn-ok` even with the proxy stopped (CN is direct), and the foreign
site only reachable while the engine runs.

## 5. Reboot recovery

```sh
reboot
```

After it comes back (do not touch anything for ~90 s):

```sh
easyproxy status
easyproxy transparent status
```

Expected: the service starts by itself, the capture table is rebuilt by the
hotplug hook, and LAN traffic flows. If the table is missing, run
`logread | grep -i easyproxy` and keep the output.

## 6. Maintenance commands

```sh
easyproxy config backup
easyproxy doctor
easyproxy doctor --json | head -c 400
easyproxy log rotate
```

Expected: `Backup written: /etc/easyproxy/backups/easyproxy-<date>.tar.gz (<N> bytes)`,
`doctor: N ok, M warn, K fail` with the two safety locks reported `ok`, valid
JSON with a `checks` array, and a log-rotation line.

## 7. Uninstall and rollback

```sh
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
nft list tables | diff /tmp/tables.before -
ip rule show | diff /tmp/rules.before -
```

Expected: `easyproxy` is gone, `table ip easyproxy` no longer exists, the
fwmark rule is gone, and **no stock ImmortalWrt rule or table is missing** —
the two diffs must show only EasyProxy's own objects disappearing. LAN, DHCP
and DNS keep working during and after removal.

`/etc/config/easyproxy` and `/etc/easyproxy` survive; `--purge` drops them too.

## Step 8 - the three components and their independent lifecycle

One command installs the panel and both kernels:

```sh
wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh
```

Expected, at the end of the run:

```
components:
  easyproxy  <version>  (/usr/sbin/easyproxy)
  sing-box   <version>  (/usr/bin/sing-box)
  dae        <version>  (/usr/bin/dae)  [adapter 开发中]
```

Check each piece separately:

```sh
sing-box version                 # sing-box version 1.14.4
dae --version                    # dae version v2.1.2
ls -l /usr/share/dae             # geoip.dat, geosite.dat for dae
ls /etc/easyproxy/owned          # sing-box, dae - proof this installer put them there
opkg list-installed | grep -E 'easyproxy|sing-box|dae'
wget -qO- .../install.sh | sh -s status
```

Then the upgrade path, on a router where an older kernel is installed:

```sh
wget -qO- .../install.sh | sh -s upgrade
```

Expected: a `component / current / newest` table, `sing-box: 1.10.7 -> 1.14.4`
style lines only for the components that changed, `upgrade done` and exit 0.
`/etc/easyproxy/backup/<kernel>.old` holds the previous binary. If the new kernel
cannot run, the old one is restored and the command exits non-zero with
`upgrade incomplete`.

`--only package`, `--only sing-box` and `--only dae` each upgrade exactly one
component; the untouched ones keep their version.

Then removal, checking that a user-installed kernel is never touched:

```sh
# install a kernel by hand first, outside EasyProxy's records
wget -qO- .../uninstall.sh | sh                      # panel gone, config kept
ls /usr/bin/dae                                      # still there only if you installed it
wget -qO- .../uninstall.sh | sh -s -- --keep-kernels  # panel gone, kernels kept
```

After a plain uninstall nothing from the installer is left in `/usr/bin`, the
nftables capture is gone, and `/root/easyproxy-backup-*.tar.gz` holds the
config that was removed from service.

## Report template

```
firmware / kernel:
package manager:
asset installed (all / x86_64 / apk / rootfs):
step 1 install:          ok / fail
step 2 panel:            ok / fail
step 3 locks:            ok / fail
step 4 capture + intranet: ok / fail
step 5 reboot recovery:  ok / fail
step 6 maintenance:      ok / fail
step 7 rollback:         ok / fail
step 8 kernels:          ok / fail
sing-box version:
dae --version:
upgrade:                 ok / fail (versions before -> after)
uninstall:               ok / fail (kernels removed / kept)
doctor output:
logread excerpt:
```
