#!/bin/sh
# Clash API reader for the mihomo engine.
#
# The reason to run mihomo next to sing-box is its external-controller
# (127.0.0.1:9090 by default): /connections reports live flows with the source
# address, the target host, the outbound that actually carried them, and byte
# counters. sing-box has nothing comparable.
#
# Everything here degrades instead of failing. No curl, API down, or an engine
# that is not mihomo all yield "absent"/empty, because a monitoring endpoint
# must never be able to break `easyproxy status`.
#
# The controller binds loopback only, so a browser cannot reach it directly;
# these functions are the backend that turns Clash JSON into EasyProxy's own
# shape.

ep_clash_controller() {
	local c
	c="$(ep_get mihomo controller 127.0.0.1:9090)"
	[ -n "$c" ] || c="127.0.0.1:9090"
	printf '%s' "$c"
}

# Only mihomo speaks this protocol.
ep_clash_applicable() {
	[ "$(ep_get main engine none)" = "mihomo" ]
}

ep_clash_get() {
	local path c secret url
	path="$1"
	command -v curl >/dev/null 2>&1 || return 1
	c="$(ep_clash_controller)"
	url="http://${c}${path}"
	secret="$(ep_get mihomo secret "")"
	if [ -n "$secret" ]; then
		curl -fsS -m 2 -H "Authorization: Bearer ${secret}" "$url" 2>/dev/null
	else
		curl -fsS -m 2 "$url" 2>/dev/null
	fi
}

# One integer field out of a flat JSON object.
# busybox has no jq; grep -o plus cut is the smallest thing that works and does
# not care where in the document the field sits.
ep_clash_num() {
	local key
	key="$2"
	printf '%s' "$1" | grep -o "\"${key}\":[0-9][0-9]*" 2>/dev/null | head -1 | cut -d: -f2
}

# First string value of a key, e.g. "version":"v1.19.34".
ep_clash_str() {
	local key
	key="$2"
	printf '%s' "$1" | grep -o "\"${key}\":\"[^\"]*\"" 2>/dev/null | head -1 | sed 's/.*:"//; s/"$//'
}

# One snapshot line: api<TAB>count<TAB>up_total<TAB>down_total<TAB>memory
# api is "ok" or "absent", and the numbers are 0 when absent so no caller has
# to special-case them.
ep_clash_snapshot() {
	local body count up down mem
	if ! ep_clash_applicable; then
		printf 'absent\t0\t0\t0\t0'
		return 0
	fi
	body="$(ep_clash_get /connections)"
	if [ -z "$body" ]; then
		printf 'absent\t0\t0\t0\t0'
		return 0
	fi
	up="$(ep_clash_num "$body" uploadTotal)"
	down="$(ep_clash_num "$body" downloadTotal)"
	mem="$(ep_clash_num "$body" memory)"
	# An empty array carries no "id", so counting per-connection markers is the
	# cheapest count available without jq.
	count="$(printf '%s' "$body" | grep -o '"id":' | wc -l | tr -d ' ')"
	printf 'ok\t%s\t%s\t%s\t%s' \
		"${count:-0}" "${up:-0}" "${down:-0}" "${mem:-0}"
}

# Strip a single leading zero so 08 is not read as octal-shaped input.
ep_clash_dec() {
	local v
	v="$1"
	v="${v#0}"
	printf '%s' "${v:-0}"
}

# Elapsed milliseconds since the connection started.
# Clash reports `start` as an RFC3339 timestamp, so this is same-day arithmetic;
# a clock skew or a date rollover yields "-" rather than a nonsense number.
ep_clash_elapsed() {
	local s t h m sec nh nm ns d tz
	s="$1"
	case "$s" in
		????-??-??T*) : ;;
		*) printf '%s' "-"; return 0 ;;
	esac
	# Clash reports start in UTC (trailing Z). Comparing that against local time
	# put every connection 8 hours old on a CST box, which is exactly the kind of
	# number that makes an operator trust a panel less.
	case "$s" in
		*Z) tz="-u" ;;
		*) tz="" ;;
	esac
	t="${s#*T}"
	h="${t%%:*}"
	m="${t#*:}"; m="${m%%:*}"
	sec="${t##*:}"; sec="${sec%%.*}"
	h="$(ep_clash_dec "$h")"
	m="$(ep_clash_dec "$m")"
	sec="$(ep_clash_dec "$sec")"
	nh="$(date $tz +%H 2>/dev/null)"; nh="$(ep_clash_dec "$nh")"
	nm="$(date $tz +%M 2>/dev/null)"; nm="$(ep_clash_dec "$nm")"
	ns="$(date $tz +%S 2>/dev/null)"; ns="$(ep_clash_dec "$ns")"
	d=$(( (nh * 3600 + nm * 60 + ns) - (h * 3600 + m * 60 + sec) ))
	[ "$d" -ge 0 ] || { printf '%s' "-"; return 0; }
	[ "$d" -lt 86400 ] || { printf '%s' "-"; return 0; }
	printf '%s' $(( d * 1000 ))
}

# Connection array normalised into tab-separated rows:
# host<TAB>source<TAB>node<TAB>upload<TAB>download<TAB>elapsed_ms
#
# host falls back to the destination IP when the flow carries no SNI/Host
# (IP literals, some UDP). node is the FIRST element of chains, not the last:
# mihomo writes the chain inside-out, so a real payload reads
# ["11","PROXY"] - the selector group sits at the end and the outbound that
# actually carried the flow sits at the front. Taking the last element put the
# selector's name (`PROXY`) in the NODE column on the live box.
ep_clash_connections() {
	local body rows
	ep_clash_applicable || return 1
	body="$(ep_clash_get /connections)"
	[ -n "$body" ] || return 1
	# split the array on "},{" so one row is one object
	rows="$(printf '%s' "$body" | sed 's/},{"}/}\n{/g')"
	printf '%s\n' "$rows" | while IFS= read -r line; do
		case "$line" in
			*'"metadata"'*) : ;;
			*) continue ;;
		esac
		host="$(printf '%s' "$line" | grep -o '"host":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//')"
		[ -n "$host" ] || host="$(printf '%s' "$line" | grep -o '"destinationIP":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//')"
		src="$(printf '%s' "$line" | grep -o '"sourceIP":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//')"
		node="$(printf '%s' "$line" | grep -o '"chains":\[[^]]*\]' | head -1 | sed 's/.*\[//; s/\]//; s/"//g' | awk -F, '{ print $1 }')"
		up="$(ep_clash_num "$line" upload)"
		down="$(ep_clash_num "$line" download)"
		start="$(ep_clash_elapsed "$(ep_clash_str "$line" start)")"
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
			"${host:--}" "${src:--}" "${node:--}" "${up:-0}" "${down:-0}" "${start:--}"
	done
}

# Flatten the rows into the single JSON object the panel consumes.
# Every string goes through ep_json_escape: a host name here comes from the
# client's own CONNECT/SNI, so it is attacker-influenced input.
ep_clash_connections_json() {
	local rows host src node up down start first
	rows="$(ep_clash_connections)" || rows=""
	first=1
	printf '{"ok":true,"engine":"mihomo","connections":['
	printf '%s\n' "$rows" | while IFS='	' read -r host src node up down start; do
		[ -n "$host" ] || continue
		if [ "$first" = "1" ]; then
			first=0
		else
			printf ','
		fi
		printf '{"host":"%s","source":"%s","node":"%s","upload":%s,"download":%s,"elapsed_ms":%s}' \
			"$(ep_json_escape "$host")" \
			"$(ep_json_escape "$src")" \
			"$(ep_json_escape "$node")" \
			"${up:-0}" "${down:-0}" \
			"$(case "$start" in ''|-) printf 'null' ;; *) printf '%s' "$start" ;; esac)"
	done
	printf ']}\n'
}
