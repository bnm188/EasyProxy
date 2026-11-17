#!/bin/sh
# sing-box configuration generation.
#
# Turns the "config node" sections of /etc/config/easyproxy into a sing-box
# config file. Only enabled nodes are emitted; the result is validated with
# `sing-box check` before it replaces the live file.
#
# Stage 4 adds the routing layer: China domains/addresses go out through
# `direct`, everything else falls through to the node group, and DNS is split
# the same way (domestic resolvers for CN names, remote DoH for the rest).
# Stage 5 adds the tproxy inbound used by the transparent-proxy takeover.
# Stage 6 makes fail_closed real and keeps every LAN destination direct.
# Stage 6 also locks the two safety knobs: china_policy is always direct and
# fail_closed is always 1, so no UCI value can turn routing into a full proxy.
# Stage 7 adds vless / hysteria2 / tuic nodes, per-region latency groups and
# YouTube / Netflix / TikTok plus custom split rules.

EP_ERR=""
EP_ERR_FILE=""
EP_WARN=""

# Map an OpenWrt/syslog log level onto a sing-box log level
ep_singbox_log_level() {
	case "$1" in
		debug|info|warn|error|fatal|panic) printf '%s' "$1" ;;
		notice) printf '%s' 'info' ;;
		warning) printf '%s' 'warn' ;;
		err|crit|alert|emerg) printf '%s' 'error' ;;
		*) printf '%s' 'info' ;;
	esac
}

# Set the error text both in this shell and in a file, so a message raised
# inside "$( ... )" (a subshell) still reaches the caller.
ep_err() {
	EP_ERR="$*"
	[ -n "${EP_ERR_FILE:-}" ] && printf '%s' "$*" > "$EP_ERR_FILE"
	return 1
}

# Tag used for a node: its "name" option, else the UCI section identifier
ep_node_tag() {
	local section="$1" name
	name="$(ep_get "$section" name '')"
	printf '%s' "${name:-$section}"
}

# Optional TLS block, empty when disabled
ep_node_tls() {
	local section="$1" server="$2" tls sni
	tls="$(ep_bool "$(ep_get "$section" tls 0)")"
	[ "$tls" = "1" ] || return 0
	sni="$(ep_get "$section" sni "$server")"
	printf ',"tls":{"enabled":true,"server_name":"%s"}' "$(ep_json_escape "$sni")"
}

# Print one sing-box outbound object for a node section, or explain why not
ep_node_outbound() {
	local section="$1" tag type server port method password uuid alter_id user
	local tls sni flow

	tag="$(ep_node_uniq_tag "$section")"
	type="$(ep_get "$section" type '')"
	server="$(ep_get "$section" server '')"
	port="$(ep_get "$section" port '')"

	[ -n "$type" ] || { ep_err "node ${tag}: missing type"; return 1; }
	[ -n "$server" ] || { ep_err "node ${tag}: missing server"; return 1; }
	case "$port" in
		''|*[!0-9]*) ep_err "node ${tag}: missing or non-numeric port"; return 1 ;;
	esac

	tag="$(ep_json_escape "$tag")"
	server="$(ep_json_escape "$server")"
	tls="$(ep_node_tls "$section" "$(ep_get "$section" server '')")"

	case "$type" in
		shadowsocks)
			method="$(ep_get "$section" method 'aes-256-gcm')"
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: shadowsocks needs password"; return 1; }
			printf '{"type":"shadowsocks","tag":"%s","server":"%s","server_port":%s,"method":"%s","password":"%s"%s}' \
				"$tag" "$server" "$port" "$(ep_json_escape "$method")" "$(ep_json_escape "$password")" "$tls"
			;;
		vmess)
			uuid="$(ep_get "$section" uuid '')"
			alter_id="$(ep_get "$section" alter_id 0)"
			[ -n "$uuid" ] || { ep_err "node ${tag}: vmess needs uuid"; return 1; }
			case "$alter_id" in ''|*[!0-9]*) alter_id=0 ;; esac
			printf '{"type":"vmess","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","alter_id":%s,"security":"auto"%s}' \
				"$tag" "$server" "$port" "$(ep_json_escape "$uuid")" "$alter_id" "$tls"
			;;
		trojan)
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: trojan needs password"; return 1; }
			printf '{"type":"trojan","tag":"%s","server":"%s","server_port":%s,"password":"%s"%s}' \
				"$tag" "$server" "$port" "$(ep_json_escape "$password")" "$tls"
			;;
		vless)
			uuid="$(ep_get "$section" uuid '')"
			[ -n "$uuid" ] || { ep_err "node ${tag}: vless needs uuid"; return 1; }
			flow="$(ep_get "$section" flow '')"
			printf '{"type":"vless","tag":"%s","server":"%s","server_port":%s,"uuid":"%s"' \
				"$tag" "$server" "$port" "$(ep_json_escape "$uuid")"
			[ -n "$flow" ] && printf ',"flow":"%s"' "$(ep_json_escape "$flow")"
			printf '%s}' "$tls"
			;;
		hysteria2)
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: hysteria2 needs password"; return 1; }
			printf '{"type":"hysteria2","tag":"%s","server":"%s","server_port":%s,"password":"%s"%s}' \
				"$tag" "$server" "$port" "$(ep_json_escape "$password")" "$tls"
			;;
		tuic)
			uuid="$(ep_get "$section" uuid '')"
			password="$(ep_get "$section" password '')"
			[ -n "$uuid" ] || { ep_err "node ${tag}: tuic needs uuid"; return 1; }
			[ -n "$password" ] || { ep_err "node ${tag}: tuic needs password"; return 1; }
			printf '{"type":"tuic","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","password":"%s"%s}' \
				"$tag" "$server" "$port" "$(ep_json_escape "$uuid")" "$(ep_json_escape "$password")" "$tls"
			;;
		socks|http)
			user="$(ep_get "$section" username '')"
			password="$(ep_get "$section" password '')"
			if [ -n "$user" ] && [ -n "$password" ]; then
				printf '{"type":"%s","tag":"%s","server":"%s","server_port":%s,"username":"%s","password":"%s"}' \
					"$type" "$tag" "$server" "$port" "$(ep_json_escape "$user")" "$(ep_json_escape "$password")"
			else
				printf '{"type":"%s","tag":"%s","server":"%s","server_port":%s}' \
					"$type" "$tag" "$server" "$port"
			fi
			;;
		*)
			ep_err "node ${tag}: unsupported type ${type}"
			return 1
			;;
	esac
}

# 1 when the domestic split (CN direct, rest proxied) is actually wired up:
# it needs at least one usable node and the CN rule sets on disk.
ep_china_split_active() {
	local nodes
	nodes="${1:-0}"
	[ "$nodes" -gt 0 ] || return 1
	[ "$(ep_rule_set_state)" = "ready" ] || return 1
	return 0
}

# split | direct — what the routing layer will really do.
#   split  : CN direct, everything else through the node group
#   direct : nothing is proxied (no enabled node, or the CN rule sets are missing)
# There is deliberately no "proxy" mode: china_policy and fail_closed are locked
# (see ep_locked_warn) so no UCI value can turn routing into a full proxy.
ep_route_mode() {
	local nodes
	nodes="${1:-0}"
	[ "$nodes" -gt 0 ] 2>/dev/null || nodes=0
	[ "$nodes" -gt 0 ] || { printf '%s' 'direct'; return 0; }
	[ "$(ep_rule_set_state)" = "ready" ] && { printf '%s' 'split'; return 0; }
	printf '%s' 'direct'
}

# The two safety knobs are locked ON. Both are still readable as UCI keys so old
# configs load, but their values are not honoured; a wrong value only produces a
# warning explaining that the lock kept the safe behaviour.
ep_locked_warn() {
	local msg raw
	msg=""
	raw="$(ep_get routing china_policy direct)"
	if [ "$raw" != "direct" ]; then
		msg="routing.china_policy=${raw} is locked out: domestic traffic must stay direct, so the CN direct rule is always installed"
	fi
	if [ "$(ep_bool "$(ep_get routing fail_closed 1)")" != "1" ]; then
		[ -n "$msg" ] && msg="$msg; "
		msg="${msg}routing.fail_closed=0 is locked out: without the CN rule sets nothing is proxied, routing never degrades to a full proxy"
	fi
	printf '%s' "$msg"
}

# Download one rule set into the local directory when it is absent or stale.
# A failure here is not fatal: ep_route_mode() decides the safe fallback.
ep_rule_set_fetch() {
	local url="$1" file="$2" days="$3" tmp
	[ -n "$url" ] || return 1
	[ -z "${EP_RULE_SET_NO_FETCH:-}" ] || return 1
	if [ -s "$file" ] && [ -z "$(find "$file" -mtime "+${days:-7}" 2>/dev/null)" ]; then
		return 0
	fi
	mkdir -p "$(dirname "$file")" 2>/dev/null || return 1
	tmp="$file.part"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --max-time 30 -o "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
	elif command -v wget >/dev/null 2>&1; then
		wget -q -T 30 -O "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
	else
		return 1
	fi
	[ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
	mv "$tmp" "$file" 2>/dev/null || { rm -f "$tmp"; return 1; }
	return 0
}

# Make sure both CN rule sets are available locally (no network at engine start)
ep_rule_set_ensure() {
	local dir days geoip geosite
	dir="$(ep_rule_set_dir)"
	days="$(ep_get routing rule_set_update_days 7)"
	geosite="$(ep_get routing geosite_cn_url 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs')"
	geoip="$(ep_get routing geoip_cn_url 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs')"
	ep_rule_set_fetch "$geosite" "$dir/geosite-cn.srs" "$days"
	ep_rule_set_fetch "$geoip" "$dir/geoip-cn.srs" "$days"
	[ "$(ep_rule_set_state)" = "ready" ]
}

# Cache file the engine keeps for rule sets and resolved domains
ep_cache_file() {
	ep_get main cache_file '/etc/easyproxy/cache.db'
}

# Local rule-set definitions for the domestic split
ep_route_rule_sets() {
	local dir
	dir="$(ep_rule_set_dir)"
	printf '      { "type": "local", "tag": "geosite-cn", "format": "binary", "path": "%s" },\n' \
		"$(ep_json_escape "$dir/geosite-cn.srs")"
	printf '      { "type": "local", "tag": "geoip-cn", "format": "binary", "path": "%s" }\n' \
		"$(ep_json_escape "$dir/geoip-cn.srs")"
}


# --- rule helpers -----------------------------------------------------------
# Platform split: which well-known services must leave through the node group.
# Each one is a UCI switch (default on) so an operator can keep a service on
# the direct path when the node cannot handle it.
ep_platform_enabled() {
	[ "$(ep_bool "$(ep_get routing "platform_$1" 1)")" = "1" ]
}

ep_platform_rule_line() {
	local key="$1" domains="$2"
	ep_platform_enabled "$key" || return 0
	printf '      { "domain_suffix": [%s], "outbound": "proxy" }' "$domains"
}

# Youtube / Netflix / TikTok: domain lists are inline so no extra rule-set has
# to be downloaded and the split works on a fresh install without network.
ep_platform_rules_json() {
	local items="" _r
	_r="$(ep_platform_rule_line youtube '"youtube.com", "youtu.be", "googlevideo.com", "ytimg.com", "youtube-nocookie.com", "yt3.ggpht.com"')"
	[ -n "$_r" ] && items="$_r"
	_r="$(ep_platform_rule_line netflix '"netflix.com", "netflix.net", "nflxext.com", "nflximg.com", "nflximg.net", "nflxso.net", "nflxvideo.net"')"
	[ -n "$_r" ] && items="${items:+$items,
}$_r"
	_r="$(ep_platform_rule_line tiktok '"tiktok.com", "tiktokv.com", "tiktokcdn.com", "byteoversea.com", "ibytedtos.com", "muscdn.com"')"
	[ -n "$_r" ] && items="${items:+$items,
}$_r"
	printf '%s' "$items"
}

# Custom rules, "type:value:outbound" entries separated by ';'. The operator
# order is preserved and they sit between the LAN rules and the CN rule, so a
# custom entry can force a domain through the proxy or block it outright.
ep_custom_rules_json() {
	local raw entry typ rest val out items old_ifs key obj
	raw="$(ep_get routing custom_rules '')"
	[ -n "$raw" ] || return 0
	items=""
	old_ifs="$IFS"
	IFS=';'
	for entry in $raw; do
		entry="$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		[ -n "$entry" ] || continue
		typ="${entry%%:*}"
		rest="${entry#*:}"
		val="${rest%%:*}"
		out="${rest#*:}"
		[ -n "$typ" ] && [ -n "$val" ] && [ -n "$out" ] || continue
		case "$out" in
			direct|proxy|block) ;;
			*) continue ;;
		esac
		case "$typ" in
			domain) key="domain" ;;
			domain-suffix|suffix) key="domain_suffix" ;;
			domain-keyword|keyword) key="domain_keyword" ;;
			ip|ip-cidr) key="ip_cidr" ;;
			*) continue ;;
		esac
		# built in a variable first: ${items:+...} would stop at the first '}'
		# inside the JSON object and the quotes would then be eaten by word splitting
		obj="      { \"$key\": [\"$(ep_json_escape "$val")\"], \"outbound\": \"$out\" }"
		if [ -n "$items" ]; then
			items="$items,
$obj"
		else
			items="$obj"
		fi
	done
	IFS="$old_ifs"
	printf '%s' "$items"
}

# 1 when a custom rule can land on the block outbound (needed for its tag)
ep_custom_uses_block() {
	local raw entry rest out old_ifs
	raw="$(ep_get routing custom_rules '')"
	[ -n "$raw" ] || { printf '0'; return 0; }
	old_ifs="$IFS"
	IFS=';'
	for entry in $raw; do
		rest="${entry#*:}"
		out="${rest#*:}"
		if [ "$out" = "block" ]; then
			IFS="$old_ifs"
			printf '1'
			return 0
		fi
	done
	IFS="$old_ifs"
	printf '0'
}

# --- custom rule store ------------------------------------------------------
# Rules live in one UCI string so a backup of /etc/config/easyproxy carries
# them; the CLI edits that string entry by entry.

ep_rule_entries() {
	ep_get routing custom_rules '' | tr ';' '\n'
}

ep_rule_add() {
	local entry="$1" cur
	case "$entry" in
		*:*:*)
			case "${entry##*:}" in
				direct|proxy|block) ;;
				*) echo "outbound must be direct, proxy or block" >&2; return 1 ;;
			esac
			;;
		*) echo "rule must be type:value:outbound" >&2; return 1 ;;
	esac
	cur="$(ep_get routing custom_rules '')"
	if [ -n "$cur" ]; then
		uci -q set "${EP_CONFIG}.routing.custom_rules=${cur};${entry}"
	else
		uci -q set "${EP_CONFIG}.routing.custom_rules=${entry}"
	fi
	uci -q commit "$EP_CONFIG" 2>/dev/null
	printf '%s' "$entry"
}

# Remove one rule by its 1-based position (as printed by `rule list`)
ep_rule_delete() {
	local idx="$1" old_ifs n=0 out="" entry
	old_ifs="$IFS"
	IFS=';'
	for entry in $(ep_get routing custom_rules ''); do
		n=$((n + 1))
		[ "$n" = "$idx" ] && continue
		out="${out:+$out;}$entry"
	done
	IFS="$old_ifs"
	[ "$n" -gt 0 ] || { echo "no custom rules configured" >&2; return 1; }
	[ "$idx" -ge 1 ] && [ "$idx" -le "$n" ] || { echo "no rule #$idx" >&2; return 1; }
	uci -q set "${EP_CONFIG}.routing.custom_rules=${out}"
	uci -q commit "$EP_CONFIG" 2>/dev/null
}

# Comma-separated JSON array body of IP literals used as node servers.
# Traffic to the proxy server itself must never be captured and re-proxied:
# with a hostname the engine resolves it, with a literal we can pin it here.
ep_node_server_cidrs() {
	local section server first=1
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
		server="$(ep_get "$section" server '')"
		case "$server" in
			# IPv4 literal
			[0-9]*.[0-9]*.[0-9]*.[0-9]*)
				case "$server" in
					*[!0-9.]*) continue ;;
				esac
				[ "$first" = "1" ] || printf ', '
				printf '"%s/32"' "$(ep_json_escape "$server")"
				first=0
				;;
			# IPv6 literal
			[0-9a-fA-F:]*:*)
				case "$server" in
					*[!0-9a-fA-F:]*) continue ;;
				esac
				[ "$first" = "1" ] || printf ', '
				printf '"%s/128"' "$(ep_json_escape "$server")"
				first=0
				;;
		esac
	done
}

# One DNS server in the shape sing-box 1.12+ requires. The legacy `address`
# field (`https://host/path`, `tls://host`, `223.5.5.5`) was deprecated in
# 1.12.0 and removed in 1.14.0, so the scheme becomes `type` and the host,
# port and path become separate fields. `detour` is kept: it is still the
# outbound tag the query leaves through.
ep_dns_server_json() {
	local tag="$1" addr="$2" detour="$3"
	local type rest host port path
	type=udp
	case "$addr" in
		https://*) type=https; rest="${addr#https://}" ;;
		tls://*)   type=tls;   rest="${addr#tls://}" ;;
		quic://*)  type=quic;  rest="${addr#quic://}" ;;
		h3://*)    type=h3;    rest="${addr#h3://}" ;;
		*://*)     type=udp;   rest="${addr#*://}" ;;
		*)         type=udp;   rest="$addr" ;;
	esac
	path=""
	case "$rest" in
		*/*) host="${rest%%/*}"; path="/${rest#*/}" ;;
		*)   host="$rest" ;;
	esac
	port=""
	case "$host" in
		*:*:*) : ;;
		*:*) port="${host##*:}"; host="${host%:*}" ;;
	esac
	[ -n "$host" ] || return 1
	[ -n "$path" ] || { [ "$type" = https ] && path="/dns-query"; }
	# 新格式里 `detour: "direct"` 会被内核直接拒绝（"detour to an empty
	# direct outbound makes no sense"）：直连出站没有任何拨号字段，不是合法
	# 的 DNS 出站。指向 direct 时省略 detour 才是真正的直连解析。
	[ "$detour" = "direct" ] && detour=""
	printf '{ "type": "%s", "tag": "%s", "server": "%s"' \
		"$type" "$(ep_json_escape "$tag")" "$(ep_json_escape "$host")"
	[ -n "$port" ] && printf ', "server_port": %s' "$port"
	[ "$type" = https ] && [ -n "$path" ] && printf ', "path": "%s"' "$(ep_json_escape "$path")"
	[ -n "$detour" ] && printf ', "detour": "%s"' "$(ep_json_escape "$detour")"
	printf ' }'
}

# Build the config file. Returns 0 on success, non-zero with EP_ERR set.
# Exit 2 means the file was assembled but the engine rejected it.
ep_config_build() {
	local outfile="$1" engine binary listen listen_port final
	local tmp out sections tags nodes section line first
	local proxy dns_local dns_remote split mode locked_msg node_bypass custom_rules platform_rules
	local transparent tproxy_port region default_region member_first group_first
	EP_ERR=""

	outfile="${outfile:-$(ep_engine_config_path "$(ep_get main engine sing-box)")}"
	[ -n "$outfile" ] || { EP_ERR="no config path configured"; return 1; }

	listen="$(ep_get main listen '127.0.0.1')"
	listen_port="$(ep_get main listen_port '7890')"
	case "$listen_port" in
		''|*[!0-9]*) EP_ERR="main.listen_port is not a number"; return 1 ;;
	esac

	tmp="$(mktemp)" || { EP_ERR="cannot create a temporary file"; return 1; }
	EP_ERR_FILE="$tmp.errmsg"
	: > "$EP_ERR_FILE"
	out="$tmp.body"
	: > "$out"
	# Every outbound tag in this run comes from this map, so two nodes sharing a
	# display name no longer collapse into one tag.
	EP_TAG_MAP="$tmp.tags"
	export EP_TAG_MAP
	ep_build_tag_map "$EP_TAG_MAP"
	sections="$(ep_node_sections)"
	nodes=0
	tags=""

	for section in $sections; do
		[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
		line="$(ep_node_outbound "$section")" || {
			EP_ERR="$(cat "$EP_ERR_FILE" 2>/dev/null)"
			rm -f "$tmp" "$out" "$EP_ERR_FILE"
			[ -n "$EP_ERR" ] || EP_ERR="node in section $section could not be rendered"
			return 1
		}
		printf '%s\n' "$line" >> "$out"
		nodes=$((nodes + 1))
	done

	# china_policy / fail_closed are locked: the domestic split and the
	# "never degrade to a full proxy" rule are not operator options any more.
	proxy="$(ep_get routing proxy_policy proxy)"
	dns_local="$(ep_get routing dns_local_server '223.5.5.5')"
	dns_remote="$(ep_get routing dns_remote_server 'https://1.1.1.1/dns-query')"
	transparent="$(ep_bool "$(ep_get transparent enabled 0)")"
	tproxy_port="$(ep_get transparent tproxy_port '7891')"
	case "$tproxy_port" in
		''|*[!0-9]*) tproxy_port=7891 ;;
	esac

	if [ "$nodes" -gt 0 ]; then
		ep_rule_set_ensure
	fi
	node_bypass="$(ep_node_server_cidrs)"
	mode="$(ep_route_mode "$nodes")"
	split=0
	[ "$mode" = "split" ] && split=1

	locked_msg="$(ep_locked_warn)"
	EP_WARN="$locked_msg"
	if [ "$nodes" -gt 0 ] && [ "$mode" != "split" ]; then
		if [ -n "$EP_WARN" ]; then
			EP_WARN="$EP_WARN; china rule sets are unavailable, so routing is pinned to direct: nothing is proxied and foreign sites are unreachable until geosite-cn.srs and geoip-cn.srs exist under $(ep_rule_set_dir). Run 'easyproxy config generate' with network access, or place both files there."
		else
			EP_WARN="china rule sets are unavailable, so routing is pinned to direct: nothing is proxied and foreign sites are unreachable until geosite-cn.srs and geoip-cn.srs exist under $(ep_rule_set_dir). Run 'easyproxy config generate' with network access, or place both files there."
		fi
	fi

	case "$mode" in
		split) final="$proxy" ;;
		*) final="direct" ;;
	esac

	{
		printf '{\n'
		printf '  "log": { "level": "%s", "timestamp": true },\n' \
			"$(ep_singbox_log_level "$(ep_get main log_level notice)")"

		# --- dns -----------------------------------------------------------
		printf '  "dns": {\n'
		printf '    "servers": [\n'
		printf '      '
		ep_dns_server_json "dns-local" "$dns_local" "direct" || {
			EP_ERR="routing.dns_local_server is not a usable DNS server"
			rm -f "$tmp" "$out" "$EP_ERR_FILE"
			return 1
		}
		if [ "$nodes" -gt 0 ] && [ "$mode" != "direct" ]; then
			printf ',\n      '
			ep_dns_server_json "dns-remote" "$dns_remote" "proxy" || {
				EP_ERR="routing.dns_remote_server is not a usable DNS server"
				rm -f "$tmp" "$out" "$EP_ERR_FILE"
				return 1
			}
			printf '\n'
		else
			printf '\n'
		fi
		printf '    ],\n'
		# LAN first: private addresses and local host names must always be
		# resolved by the router itself, never by the remote DoH endpoint —
		# otherwise LAN devices lose name resolution when traffic is proxied.
		if [ "$nodes" -gt 0 ] && [ "$mode" != "direct" ]; then
			printf '    "rules": [\n'
			printf '      { "ip_is_private": true, "server": "dns-local" },\n'
			printf '      { "domain_suffix": [".lan", ".local", ".localdomain", ".home.arpa", ".internal"], "server": "dns-local" }'
			if [ "$split" = "1" ]; then
				printf ',\n'
				printf '      { "domain_suffix": [".cn"], "server": "dns-local" },\n'
				printf '      { "rule_set": ["geosite-cn"], "server": "dns-local" }\n'
			else
				printf '\n'
			fi
			printf '    ],\n'
		fi
		if [ "$nodes" -gt 0 ] && [ "$mode" != "direct" ]; then
			printf '    "final": "dns-remote"\n'
		else
			printf '    "final": "dns-local"\n'
		fi
		printf '  },\n'

		# --- inbounds ------------------------------------------------------
		printf '  "inbounds": [\n'
		printf '    { "type": "mixed", "tag": "mixed-in", "listen": "%s", "listen_port": %s }' \
			"$(ep_json_escape "$listen")" "$listen_port"
		if [ "$transparent" = "1" ] && [ "$nodes" -gt 0 ]; then
			printf ',\n'
			printf '    { "type": "tproxy", "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": %s }\n' \
				"$tproxy_port"
		else
			printf '\n'
		fi
		printf '  ],\n'

		# --- outbounds -----------------------------------------------------
		printf '  "outbounds": [\n'
		if [ "$nodes" -gt 0 ]; then
			# Node outbounds followed by the latency groups and the selector
			awk '{ printf "    %s,\n", $0 }' "$out"
			# One latency group per region ("auto-hk", "auto-us", ...): urltest
			# keeps re-picking the fastest node inside that region, which is the
			# "自动选择可用节点" behaviour without any extra daemon.
			default_region=""
			for region in $(ep_node_regions); do
				[ -n "$default_region" ] || default_region="$region"
				printf '    { "type": "urltest", "tag": "auto-%s", "outbounds": [' "$region"
				member_first=1
				for section in $(ep_node_sections_in_region "$region"); do
					[ "$member_first" = "1" ] || printf ', '
					printf '"%s"' "$(ep_json_escape "$(ep_node_uniq_tag "$section")")"
					member_first=0
					done
				printf '], "url": "http://www.gstatic.com/generate_204", "interval": "5m", "tolerance": 50 },\n'
			done
			# The selector in front of the groups is what route.final points at;
			# options are the region groups, default is the first region.
			printf '    { "type": "selector", "tag": "proxy", "outbounds": ['
			group_first=1
			for region in $(ep_node_regions); do
				[ "$group_first" = "1" ] || printf ', '
				printf '"auto-%s"' "$region"
				group_first=0
			done
			printf '], "default": "auto-%s" },\n' "$default_region"
		fi
		printf '    { "type": "direct", "tag": "direct" }'
		if [ "$(ep_custom_uses_block)" = "1" ]; then
			printf ',\n    { "type": "block", "tag": "block" }'
		fi
		printf '\n'
		printf '  ],\n'

		# --- route ---------------------------------------------------------
		printf '  "route": {\n'
		# sing-box 1.12 made a missing domain resolver fatal for dial fields
		# (node server hostnames would no longer resolve at all from 1.14.0), so
		# the local resolver is named explicitly as the default.
		printf '    "default_domain_resolver": { "server": "dns-local" },\n'
		if [ "$transparent" = "1" ] && [ "$nodes" -gt 0 ]; then
			printf '    "auto_detect_interface": true,\n'
		fi
		printf '    "rules": [\n'
		# Sniffing moved out of the inbound: since sing-box 1.11 it is a route
		# action, and the legacy inbound fields (sniff, sniff_override_destination,
		# udp_timeout) were removed in 1.13.0. The action still rewrites the
		# destination from the sniffed domain for the rules that follow, which is
		# what the tproxy capture needs.
		if [ "$transparent" = "1" ] && [ "$nodes" -gt 0 ]; then
			printf '      { "action": "sniff", "inbound": ["tproxy-in"] },\n'
		fi
		printf '      { "ip_is_private": true, "outbound": "direct" }'
		if [ -n "$node_bypass" ]; then
			printf ',\n      { "ip_cidr": [%s], "outbound": "direct" }' "$node_bypass"
		fi
		# Operator rules first (their order is meaningful), then the platform
		# splits, then the domestic rule set: a platform domain must be able to
		# win over the CN rule, and a custom rule must be able to win over both.
		# Both only make sense while split routing is active: with a missing rule
		# set the hard lock above already forces every rule to DIRECT, and a
		# platform rule pointing at "proxy" would quietly reopen that hole.
		if [ "$split" = "1" ]; then
			custom_rules="$(ep_custom_rules_json)"
			if [ -n "$custom_rules" ]; then
				printf ',\n%s' "$custom_rules"
			fi
			platform_rules="$(ep_platform_rules_json)"
			if [ -n "$platform_rules" ]; then
				printf ',\n%s' "$platform_rules"
			fi
		fi
		if [ "$split" = "1" ]; then
			printf ',\n      { "rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct" }\n'
		else
			printf '\n'
		fi
		printf '    ],\n'
		if [ "$split" = "1" ]; then
			printf '    "rule_set": [\n'
			ep_route_rule_sets
			printf '    ],\n'
		fi
		printf '    "final": "%s"\n' "$final"
		printf '  },\n'
		# Keep the rule-set cache across restarts: re-checking a 10 MB .srs file
		# on every boot is what makes small routers time out on startup.
		printf '  "experimental": {\n'
		printf '    "cache_file": { "enabled": true, "path": "%s" }\n' \
			"$(ep_json_escape "$(ep_cache_file)")"
		printf '  }\n'
		printf '}\n'
	} > "$tmp.file" || { rm -f "$tmp" "$out" "$tmp.file"; EP_ERR="cannot write config"; return 1; }

	engine="$(ep_get main engine sing-box)"
	binary="$(ep_engine_binary "$engine")"
	if [ "$(ep_binary_state "$binary")" = "available" ]; then
		if ! "$binary" check -c "$tmp.file" >"$tmp.err" 2>&1; then
			EP_ERR="engine rejected the generated config: $(tr '\n' ' ' < "$tmp.err" | cut -c1-400)"
			rm -f "$tmp" "$out" "$tmp.file" "$tmp.err" "$EP_ERR_FILE"
			return 2
		fi
	fi

	mkdir -p "$(dirname "$outfile")" 2>/dev/null
	if ! mv "$tmp.file" "$outfile"; then
		rm -f "$tmp" "$out" "$tmp.file"
		EP_ERR="cannot install config to $outfile"
		return 1
	fi

	rm -f "$tmp" "$out" "$EP_ERR_FILE"
	EP_NODES="$nodes"
	EP_FINAL="$final"
	EP_SPLIT="$split"
	EP_ROUTE_MODE="$mode"
	return 0
}
