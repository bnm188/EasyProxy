# Locked routing behaviour (0.6.0)

These three rules cannot be turned off from LuCI, UCI, the CLI or the config
template. Editing `/etc/config/easyproxy` has no effect on them; it only shows up
as a warning.

## 1. China mainland always goes direct

`routing.china_policy` accepts two values only: `direct` and `split`.
`china_policy=proxy` no longer exists - there is deliberately no code path that
builds a config without the CN rule set. The geosite-cn / geoip-cn rule sets are
written to `route.rules` as `outbound: direct` in every generated config.

A hand-edited `china_policy=proxy` is ignored and produces:

```
routing.china_policy=proxy is locked out: mainland traffic is always direct
```

## 2. Rule sets missing means everything direct (`fail_closed` is pinned to 1)

`routing.fail_closed` is always `1`. When geosite-cn or geoip-cn cannot be
fetched, the generated config keeps exactly one rule (LAN + reserved ranges) and
sets `route.final = direct` and `dns.final = dns-local`. Nothing is proxied and
foreign sites are unreachable until the rule sets are back.

The alternative - falling back to `final = proxy` - would silently turn a broken
rule set into a global proxy, so it is not implemented.

A hand-edited `fail_closed=0` is ignored and produces:

```
routing.fail_closed=0 is locked out: a missing rule set must go direct, not global proxy
```

## 3. LAN and router management addresses are never captured

The tproxy bypass set always contains:

| entry | why |
|---|---|
| `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | RFC1918 LANs |
| `10.10.10.10/32` | explicitly listed management address |
| `127.0.0.0/8`, `169.254.0.0/16`, `100.64.0.0/10`, `224.0.0.0/4`, `240.0.0.0/4` | loopback, link-local, CGNAT, multicast, reserved |
| every `inet` address on the interfaces in `transparent.lan_interfaces`, pinned to `/32` | the router's own panel/SSH address |
| every node server address | the tunnel must not be captured |

Without the router's own address the first capture kills the LuCI panel and SSH,
which is exactly the failure this bypass prevents. Downstream devices in the same
LAN keep their normal direct path to each other and to the router.

## How to check it

```sh
easyproxy status            # prints `LAN: always direct`, china_policy=direct, fail_closed=1
easyproxy status --json     # same values; tampered UCI values appear under `Lock:`
easyproxy validate          # exits 1 if china_policy != direct or fail_closed != 1
easyproxy config generate   # warnings on stderr, only split|direct in the summary
```

Test coverage: `tests/test-routing.sh` (sections 3, 4b, 4c) and
`tests/test-transparent.sh` (sections 5 and 8).
