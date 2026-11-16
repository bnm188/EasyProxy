#!/bin/sh
# Transparent proxy takeover (Stage 5, hardened in Stage 6).
#
# LAN traffic is captured with TPROXY and handed to the sing-box `tproxy`
# inbound, then marked so the kernel routes it into a dedicated table. Everything
# lives in our own `table ip easyproxy` and our own policy rule/table, never
# inside fw4's tables, so `easyproxy transparent remove` is two deletes and
# leaves the router's firewall exactly as it was.
#
# Only IPv4 is captured. IPv6 is left untouched on purpose: an unsupported
# capture must fail open for the LAN, never silently drop local traffic.

EP_NFT_BIN="${EP_NFT_BIN:-nft}"
EP_IP_BIN="${EP_IP_BIN:-ip}"
EP_NFT_FILE="${EP_NFT_FILE:-/etc/easyproxy/nftables.conf}"

ep_transparent_enabled() {
	[ "$(ep_bool "$(ep_get transparent enabled 0)")" = "1" ]
}

ep_tproxy_port() {
	ep_get transparent tproxy_port '7891'
}

ep_transparent_fwmark() {
	ep_get transparent fwmark '1'
}

ep_transparent_route_table() {
	ep_get transparent route_table '100'
}

ep_transparent_ifaces() {
	ep_get transparent lan_interfaces 'br-lan'
}

# nft present and actually runnable on this host?
ep_nft_usable() {
	command -v "$EP_NFT_BIN" >/dev/null 2>&1 || return 1
	"$EP_NFT_BIN" -V >/dev/null 2>&1 || return 1
	return 0
}

# active | inactive | unsupported
ep_transparent_state() {
	if ! ep_nft_usable; then
		printf '%s' 'unsupported'
	elif "$EP_NFT_BIN" list table ip easyproxy >/dev/null 2>&1; then
		printf '%s' 'active'
	else
		printf '%s' 'inactive'
	fi
}

# Every IPv4 address on the LAN interfaces themselves: the router's own
# management address must never be captured, otherwise the panel and SSH on the
# LAN side break as soon as the takeover is applied.
ep_transparent_local_addrs() {
	local one addrs a
	for one in $(ep_transparent_ifaces); do
		addrs="$("$EP_IP_BIN" -4 addr show dev "$one" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "inet") print $(i + 1) }')"
		[ -n "$addrs" ] || continue
		for a in $addrs; do
			# pin the address itself, not the whole subnet behind it
			printf ', %s/32' "${a%%/*}"
		done
	done
}

# IPv4 addresses that must never be captured: private space (with 10.10.10.10
# spelled out because it is a common router/AP management address), the router's
# own LAN addresses, every node server (capturing the proxy's own upstream would
# loop) and the operator excludes.
ep_transparent_bypass_raw() {
	local section server extra
	printf '127.0.0.0/8, 169.254.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 192.0.0.0/24, 198.18.0.0/15, 240.0.0.0/4, 10.10.10.10/32'
	ep_transparent_local_addrs
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
		server="$(ep_get "$section" server '')"
		case "$server" in
			''|*[!0-9.]*) continue ;;
			esac
		printf ', %s' "$server"
	done
	extra="$(ep_get transparent exclude '')"
	[ -n "$extra" ] && printf ', %s' "$extra"
	printf '\n'
}

# nftables refuses a `flags interval` set whose members nest inside each other
# ("Could not process rule: File exists"), so a /32 that already lives in
# 10.0.0.0/8 - or the router's own address in 192.168.0.0/16 - would make the
# whole ruleset fail to load and the capture never come up. The list is
# therefore normalised to disjoint intervals; nested entries are not lost, they
# are reported as covered by their parent and rendered as comments.
#   mode=list    -> the comma separated element list
#   mode=covered -> "covered by <parent>: <child>" lines
ep_bypass_normalize() {
	awk -v mode="$1" '
	function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }
	function parse(s,   n, o, i, bits, size) {
		s = trim(s)
		if (s == "") return 0
		n = split(s, parts, "/")
		if (n > 2) return 0
		if (split(parts[1], o, ".") != 4) return 0
		for (i = 1; i <= 4; i++)
			if (o[i] !~ /^[0-9]+$/ || o[i] + 0 > 255) return 0
		bits = (n == 2) ? parts[2] : 32
		if (bits !~ /^[0-9]+$/ || bits + 0 > 32) return 0
		b = bits + 0
		size = 1
		for (i = 0; i < 32 - b; i++) size *= 2
		ts = ((o[1] * 256 + o[2]) * 256 + o[3]) * 256 + o[4]
		ts = ts - (ts % size)
		te = ts + size - 1
		tt = s
		return 1
	}
	{
		cnt = split($0, raw, ",")
		k = 0
		pass = ""
		for (i = 1; i <= cnt; i++) {
			item = trim(raw[i])
			if (item == "") continue
			if (!parse(item)) { pass = pass (pass == "" ? "" : ", ") item; continue }
			if (tt in seen) continue
			seen[tt] = 1
			k++
			t[k] = tt; s[k] = ts; e[k] = te
		}
		for (i = 1; i <= k; i++) {
			par = ""
			span = -1
			for (j = 1; j <= k; j++) {
				if (i == j) continue
				if (s[j] <= s[i] && e[j] >= e[i] && (e[j] - s[j]) > span) {
					span = e[j] - s[j]
					par = t[j]
				}
			}
			if (par == "") continue
			covered[i] = 1
			if (mode == "covered") printf "covered by %s: %s\n", par, t[i]
		}
		if (mode == "list") {
			out = pass
			for (i = 1; i <= k; i++) {
				if (covered[i]) continue
				out = out (out == "" ? "" : ", ") t[i]
			}
			printf "%s\n", out
		}
	}
	'
}

ep_transparent_bypass() {
	ep_transparent_bypass_raw | ep_bypass_normalize list
}

ep_transparent_bypass_covered() {
	ep_transparent_bypass_raw | ep_bypass_normalize covered
}

# Render the nftables script for the current UCI values
ep_transparent_render() {
	local port mark ifaces expr one listen_port
	port="$(ep_tproxy_port)"
	mark="$(ep_transparent_fwmark)"
	ifaces="$(ep_transparent_ifaces)"
	expr=""
	for one in $ifaces; do
		if [ -z "$expr" ]; then
			expr="\"$one\""
		else
			expr="$expr, \"$one\""
		fi
	done
	[ -n "$expr" ] || expr='"br-lan"'
	case "$expr" in
		*','*) expr="{ $expr }" ;;
	esac
	listen_port="$(ep_get main listen_port '7890')"

	mkdir -p "$(dirname "$EP_NFT_FILE")" 2>/dev/null
	{
		printf '#!/usr/sbin/nft -f\n'
		printf '# Generated by easyproxy %s (Stage %s). Do not edit: run "easyproxy transparent apply".\n' \
			"$EP_VERSION" "$EP_STAGE"
		printf 'table ip easyproxy {\n'
		ep_transparent_bypass_covered | while IFS= read -r cl; do
			[ -n "$cl" ] && printf '\t# %s\n' "$cl"
		done
		printf '\tset bypass_ipv4 {\n'
		printf '\t\ttype ipv4_addr\n'
		printf '\t\tflags interval\n'
		printf '\t\telements = { %s }\n' "$(ep_transparent_bypass)"
		printf '\t}\n'
		printf '\tchain prerouting {\n'
		printf '\t\ttype filter hook prerouting priority mangle; policy accept;\n'
		printf '\t\tiifname != %s return\n' "$expr"
		printf '\t\tip daddr @bypass_ipv4 return\n'
		printf '\t\ttcp dport %s return\n' "$listen_port"
		printf '\t\tmeta l4proto tcp tproxy to :%s meta mark set %s accept\n' "$port" "$mark"
		printf '\t\tmeta l4proto udp tproxy to :%s meta mark set %s accept\n' "$port" "$mark"
		printf '\t}\n'
		printf '}\n'
	} > "$EP_NFT_FILE" || return 1
	return 0
}

# Add the policy rule and route table once (idempotent)
ep_transparent_routing_up() {
	local mark table
	mark="$(ep_transparent_fwmark)"
	table="$(ep_transparent_route_table)"
	if ! "$EP_IP_BIN" rule show 2>/dev/null | grep -q "fwmark 0x${mark} lookup ${table}"; then
		# A rule without its local route table black-holes the marked packets, so
		# any failure after the rule exists tears the whole thing down again.
		"$EP_IP_BIN" rule add fwmark "$mark" lookup "$table" 2>/dev/null || {
			ep_transparent_routing_down
			return 1
		}
	fi
	if ! "$EP_IP_BIN" route show table "$table" 2>/dev/null | grep -q 'local default dev lo'; then
		"$EP_IP_BIN" route add local default dev lo table "$table" 2>/dev/null || {
			ep_transparent_routing_down
			return 1
		}
	fi
	return 0
}

ep_transparent_routing_down() {
	local mark table
	mark="$(ep_transparent_fwmark)"
	table="$(ep_transparent_route_table)"
	while "$EP_IP_BIN" rule show 2>/dev/null | grep -q "fwmark 0x${mark} lookup ${table}"; do
		"$EP_IP_BIN" rule del fwmark "$mark" lookup "$table" 2>/dev/null || break
	done
	while "$EP_IP_BIN" route show table "$table" 2>/dev/null | grep -q 'local default dev lo'; do
		"$EP_IP_BIN" route del local default dev lo table "$table" 2>/dev/null || break
	done
	return 0
}

# Bring the capture up. Refuses anything that would black-hole the router:
# disabled feature, no nodes, no nft, engine not running.
ep_transparent_apply() {
	local port mark table
	EP_ERR=""
	ep_transparent_enabled || { EP_ERR="transparent proxy is not enabled; set easyproxy.transparent.enabled=1"; return 1; }
	[ "$(ep_node_count_enabled)" -gt 0 ] || { EP_ERR="no enabled nodes; nothing to route captured traffic to"; return 1; }

	ep_nft_usable || { EP_ERR="nft is not available on this host; transparent capture requires nftables"; return 1; }
	[ "$(ep_runtime_state)" = "running" ] || { EP_ERR="engine is not running; refusing to capture traffic (start EasyProxy first)"; return 1; }
	port="$(ep_tproxy_port)"
	case "$port" in
		''|*[!0-9]*) EP_ERR="transparent.tproxy_port is not a number"; return 1 ;;
	esac
	mark="$(ep_transparent_fwmark)"
	table="$(ep_transparent_route_table)"


	ep_transparent_render || { EP_ERR="cannot write $EP_NFT_FILE"; return 1; }

	# Policy routing first: packets are only marked after nft is loaded, so the
	# rule has to exist before the mark can be produced.

	ep_transparent_routing_up || { EP_ERR="cannot set up policy routing (fwmark ${mark}, table ${table})"; return 1; }

	if [ "$(ep_transparent_state)" = "active" ]; then
		"$EP_NFT_BIN" delete table ip easyproxy >/dev/null 2>&1
	fi
	if ! "$EP_NFT_BIN" -f "$EP_NFT_FILE" >/dev/null 2>&1; then
		ep_transparent_routing_down
		EP_ERR="nft rejected $EP_NFT_FILE; capture not applied"
		return 1
	fi
	return 0
}

# Tear everything down. Safe to call when nothing is up.
ep_transparent_remove() {
	EP_ERR=""
	if command -v "$EP_NFT_BIN" >/dev/null 2>&1; then
		while "$EP_NFT_BIN" list table ip easyproxy >/dev/null 2>&1; do
			"$EP_NFT_BIN" delete table ip easyproxy >/dev/null 2>&1 || break
		done
	fi
	command -v "$EP_IP_BIN" >/dev/null 2>&1 && ep_transparent_routing_down
	return 0
}
