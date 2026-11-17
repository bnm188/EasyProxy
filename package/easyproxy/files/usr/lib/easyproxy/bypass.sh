#!/bin/sh
# Entry bypass (M1 of 0.8.2): traffic whose destination is a China IPv4 address
# is released at the nftables entry instead of being handed to tproxy, so it
# never enters the sing-box userspace process at all.
#
# This is NOT the same as `china_policy=direct`: with `direct` the packet still
# goes through tproxy, sing-box, and a route lookup. With the bypass the packet
# is accepted in `prerouting` and follows the router's normal forwarding path.
#
# Safety rules:
#  - The CIDR list is validated before it is ever loaded; a broken or truncated
#    download must never produce a half-loaded set.
#  - A missing list is reported as `missing` and the bypass is skipped, never
#    silently downgraded to "everything goes to the kernel".
#  - `bypass restore` is the break-glass path: it removes our nft tables, undoes
#    the policy routing and switches the whole takeover off.

EP_CN_CIDR_FILE="${EP_CN_CIDR_FILE:-/etc/easyproxy/rulesets/cn-ipv4.txt}"
EP_CN_CIDR_URL="${EP_CN_CIDR_URL:-https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt}"
EP_CN_CIDR_MIN="${EP_CN_CIDR_MIN:-200}"

ep_bypass_enabled() {
	[ "$(ep_bool "$(ep_get transparent cn_bypass 1)")" = "1" ]
}

ep_bypass_cidr_file() {
	printf '%s' "$EP_CN_CIDR_FILE"
}

# Number of usable CIDR lines (comments and blank lines ignored)
ep_bypass_cidr_count() {
	[ -r "$EP_CN_CIDR_FILE" ] || { printf '%s' '0'; return 0; }
	awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/ { n++ } END { print n + 0 }' "$EP_CN_CIDR_FILE" 2>/dev/null || printf '%s' '0'
}

# Lines that look like data but are not a valid IPv4 CIDR: a corrupt download
# usually shows up here as a count > 0.
ep_bypass_cidr_invalid() {
	[ -r "$EP_CN_CIDR_FILE" ] || { printf '%s' '0'; return 0; }
	awk '/^[[:space:]]*(#|$)/ { next } !/^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/ { n++ } END { print n + 0 }' "$EP_CN_CIDR_FILE" 2>/dev/null || printf '%s' '0'
}

ep_bypass_cidr_ready() {
	local n bad
	n="$(ep_bypass_cidr_count)"
	bad="$(ep_bypass_cidr_invalid)"
	[ "$bad" = "0" ] || return 1
	[ "$n" -ge "$EP_CN_CIDR_MIN" ] 2>/dev/null || return 1
	return 0
}

# Fetch the list atomically: download to a temp file, validate, then move.
ep_bypass_fetch() {
	local tmp dir
	dir="$(dirname "$EP_CN_CIDR_FILE")"
	mkdir -p "$dir" 2>/dev/null || return 1
	tmp="${EP_CN_CIDR_FILE}.tmp.$$"
	if command -v wget >/dev/null 2>&1; then
		wget -q -O "$tmp" "$EP_CN_CIDR_URL" 2>/dev/null || :
	fi
	if [ ! -s "$tmp" ] && command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$tmp" "$EP_CN_CIDR_URL" 2>/dev/null || :
	fi
	if [ ! -s "$tmp" ]; then
		rm -f "$tmp" 2>/dev/null
		EP_ERR="could not download the China CIDR list from $EP_CN_CIDR_URL"
		return 1
	fi
	# Validate before replacing the live list
	if ! grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?' "$tmp" 2>/dev/null; then
		rm -f "$tmp" 2>/dev/null
		EP_ERR="downloaded list has no IPv4 CIDR entries"
		return 1
	fi
	mv "$tmp" "$EP_CN_CIDR_FILE" 2>/dev/null || {
		rm -f "$tmp" 2>/dev/null
		EP_ERR="could not replace $EP_CN_CIDR_FILE"
		return 1
	}
	ep_bypass_cidr_ready || {
		EP_ERR="downloaded list failed validation ($(ep_bypass_cidr_count) entries, $(ep_bypass_cidr_invalid) invalid)"
		return 1
	}
	return 0
}

# nft set elements, comma separated, single line
ep_bypass_elements() {
	[ -r "$EP_CN_CIDR_FILE" ] || return 0
	grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' "$EP_CN_CIDR_FILE" 2>/dev/null |
		awk 'BEGIN { first = 1 } { if (!first) printf ", "; printf "%s", $0; first = 0 }'
}

# active | ready | missing | disabled | unsupported
ep_bypass_state() {
	if ! ep_nft_usable; then
		printf '%s' 'unsupported'
		return 0
	fi
	ep_bypass_enabled || { printf '%s' 'disabled'; return 0; }
	ep_bypass_cidr_ready || { printf '%s' 'missing'; return 0; }
	if "$EP_NFT_BIN" list table ip easyproxy 2>/dev/null | grep -q 'cn_ipv4'; then
		printf '%s' 'active'
	else
		printf '%s' 'ready'
	fi
}

ep_bypass_set_value() {
	uci -q set "easyproxy.transparent.cn_bypass=$1" || return 1
	uci -q commit easyproxy || return 1
	return 0
}

# Re-render and reload our own table only. `transparent apply` refuses to run
# unless the engine is up, but a bypass flip must not depend on the runtime:
# it is a firewall change, not a takeover. The window without our table is
# milliseconds and the policy routing rule stays harmless meanwhile.
ep_bypass_reload_rules() {
	[ "$(ep_transparent_state)" = "active" ] || return 0
	ep_transparent_render || { EP_ERR="cannot render $EP_NFT_FILE"; return 1; }
	"$EP_NFT_BIN" delete table ip easyproxy >/dev/null 2>&1 || :
	"$EP_NFT_BIN" -f "$EP_NFT_FILE" >/dev/null 2>&1 || {
		EP_ERR="nft rejected the reloaded rules"
		return 1
	}
	return 0
}

# Enable / disable the entry bypass and re-render the live rules.
ep_bypass_apply_after_change() {
	ep_bypass_reload_rules
}

ep_bypass_on() {
	if ! ep_bypass_enabled; then
		ep_bypass_set_value 1 || { EP_ERR="could not write cn_bypass=1"; return 1; }
	elif [ "$(ep_bypass_state)" = "active" ]; then
		return 0
	fi
	ep_bypass_cidr_ready || ep_bypass_fetch || return 1
	[ "$(ep_transparent_state)" = "active" ] && return 0
	return 0
}

ep_bypass_off() {
	ep_bypass_set_value 0 || { EP_ERR="could not write cn_bypass=0"; return 1; }
	# Re-render the rules without the bypass set so it stops applying now
	ep_bypass_reload_rules
	return 0
}

# Break-glass: remove every trace of the takeover and fall back to plain routing.
ep_bypass_restore() {
	ep_bypass_set_value 0 >/dev/null 2>&1 || :
	uci -q set easyproxy.transparent.enabled=0 2>/dev/null || :
	uci -q commit easyproxy 2>/dev/null || :
	if ep_nft_usable; then
		"$EP_NFT_BIN" delete table ip easyproxy 2>/dev/null || :
		"$EP_NFT_BIN" delete table ip6 easyproxy 2>/dev/null || :
	fi
	command -v ep_transparent_routing_down >/dev/null 2>&1 && ep_transparent_routing_down
	rm -f "$EP_NFT_FILE" 2>/dev/null || :
	ep_log info "bypass restored: transparent capture removed, router is direct again"
	return 0
}
