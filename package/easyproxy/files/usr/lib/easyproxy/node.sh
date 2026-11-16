#!/bin/sh
# Node import/export/grouping helpers.
#
# Busybox only: no python, no jq. `base64` ships on every OpenWrt image and
# `openssl` is the fallback, so base64 links decode on old and new firmwares.
#
# Supported share links:
#   ss://         shadowsocks (base64 or plain "method:password" userinfo)
#   vmess://      base64 JSON body
#   vless://      uuid@host:port?params
#   trojan://     password@host:port?params
#   hysteria2://  password@host:port?params   (hy2:// accepted)
#   tuic://       uuid:password@host:port?params
#   socks5://     [user:pass@]host:port
#   http://       [user:pass@]host:port
#
# ep_node_parse_uri prints "key=value" lines; the caller stores them as UCI
# options. An option that cannot be determined is reported as an error instead
# of being invented.

# Percent-decode %XX sequences in one process (per-byte forks are too slow).
ep_uri_unescape() {
	# LC_ALL=C keeps %c byte-exact: a UTF-8 locale would re-encode the byte
	# and double-encode every non-ASCII character of a Chinese node name.
	printf '%s' "$1" | LC_ALL=C awk 'BEGIN{ out="" } {
		s = $0
		n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 1)
			if (c == "%" && i + 2 <= n) {
				h = tolower(substr(s, i + 1, 2))
				v = 0; ok = 1
				for (k = 1; k <= 2; k++) {
					d = substr(h, k, 1)
					p = index("0123456789abcdef", d)
					if (p == 0) { ok = 0; break }
					v = v * 16 + (p - 1)
				}
				if (ok) { out = out sprintf("%c", v); i += 2; continue }
			}
			out = out c
		}
		printf "%s", out
	}'
}

# Base64 decode; tolerant of missing padding and wrapped input
ep_b64_decode() {
	local data="$1" pad
	if command -v base64 >/dev/null 2>&1; then
		printf '%s' "$data" | base64 -d 2>/dev/null && return 0
	fi
	if command -v openssl >/dev/null 2>&1; then
		pad=$(( ${#data} % 4 ))
		[ "$pad" -eq 2 ] && data="${data}=="
		[ "$pad" -eq 3 ] && data="${data}="
		printf '%s' "$data" | openssl base64 -d -A 2>/dev/null && return 0
	fi
	return 1
}

ep_b64_encode() {
	if command -v base64 >/dev/null 2>&1; then
		printf '%s' "$1" | base64 | tr -d '\n'
		return 0
	fi
	printf '%s' "$1" | openssl base64 -A 2>/dev/null | tr -d '\n'
}

# Split "userinfo@host:port?query#frag" into EP_URI_USER / EP_URI_HOST /
# EP_URI_PORT / EP_URI_QUERY. Missing pieces stay empty.
ep_uri_split() {
	local rest="$1"
	EP_URI_USER=""
	EP_URI_QUERY=""
	EP_URI_HOST=""
	EP_URI_PORT=""
	case "$rest" in
		*\#*) rest="${rest%%\#*}" ;;
	esac
	case "$rest" in
		*\?*) EP_URI_QUERY="${rest#*\?}"; rest="${rest%%\?*}" ;;
	esac
	case "$rest" in
		*@*) EP_URI_USER="${rest%@*}"; rest="${rest##*@}" ;;
	esac
	case "$rest" in
		*:*)
			EP_URI_PORT="${rest##*:}"
			EP_URI_HOST="${rest%:*}"
			;;
		*) EP_URI_HOST="$rest" ;;
	esac
}

# Value of one query parameter, percent-decoded
ep_uri_param() {
	local query="$1" want="$2" pair old_ifs
	[ -n "$query" ] || return 0
	old_ifs="$IFS"
	IFS='&'
	for pair in $query; do
		case "$pair" in
			"$want"=*) IFS="$old_ifs"; ep_uri_unescape "${pair#*=}"; return 0 ;;
		esac
	done
	IFS="$old_ifs"
	return 0
}

# Fragment of a share link, percent-decoded; becomes the node name
ep_uri_tag() {
	local uri="$1"
	case "$uri" in
		*\#*) ep_uri_unescape "${uri#*\#}" ;;
		*) printf '%s' '' ;;
	esac
}

# Extract a JSON string value by key from a one-line JSON object
ep_json_field() {
	printf '%s' "$1" | awk -v key="$2" '{
		pat = "\"" key "\""
		i = index($0, pat)
		if (!i) exit
		s = substr($0, i + length(pat))
		# skip spaces, colon, spaces, then the opening quote
		sub(/^[[:space:]]*:[[:space:]]*"/, "", s)
		if (substr(s, 1, 1) != "") { sub(/".*/, "", s); printf "%s", s }
	}'
}

# Extract a JSON numeric value by key
ep_json_number() {
	printf '%s' "$1" | LC_ALL=C awk -v key="$2" '{
		pat = "\"" key "\""
		i = index($0, pat)
		if (!i) exit
		s = substr($0, i + length(pat))
		sub(/^[[:space:]]*:[[:space:]]*/, "", s)
		if (substr(s, 1, 1) == "\"") s = substr(s, 2)
		sub(/[^0-9].*/, "", s)
		printf "%s", s
	}'
}

# Parse one share link into key=value lines. Sets EP_NODE_ERR on failure.
ep_node_parse_uri() {
	local uri="$1" scheme body auth payload name sni security
	EP_NODE_ERR=""
	EP_URI_USER=""; EP_URI_HOST=""; EP_URI_PORT=""; EP_URI_QUERY=""
	case "$uri" in
		*://*) ;;
		*) EP_NODE_ERR="not a share link: $uri"; printf '%s\n' "not a share link: $uri" >&2; return 1 ;;
	esac
	scheme="${uri%%://*}"
	body="${uri#*://}"
	case "$scheme" in
		ss|vmess|vless|trojan|hysteria2|hy2|tuic|socks|socks5|http|https) ;;
		*) EP_NODE_ERR="unsupported share link scheme: ${scheme}"; printf '%s\n' "unsupported share link scheme: ${scheme}" >&2; return 1 ;;
	esac

	name="$(ep_uri_tag "$uri")"
	[ -n "$name" ] && printf 'name=%s\n' "$name"

	case "$scheme" in
		ss)
			payload="${body%%\#*}"
			ep_uri_split "$payload"
			auth="$(ep_uri_unescape "$EP_URI_USER")"
			case "$auth" in
				*:*) ;;
				*) auth="$(ep_b64_decode "$auth")" || { EP_NODE_ERR="ss userinfo is not base64"; printf '%s\n' "ss userinfo is not base64" >&2; return 1; } ;;
			esac
			case "$payload" in
				*@*) ;;
				*)
					# ss://base64(method:password@host:port)
					payload="$(ep_b64_decode "$payload")" || { EP_NODE_ERR="ss link is not valid base64"; printf '%s\n' "ss link is not valid base64" >&2; return 1; }
					ep_uri_split "$payload"
					auth="$(ep_uri_unescape "$EP_URI_USER")"
					;;
			esac
			[ -n "$EP_URI_HOST" ] && [ -n "$EP_URI_PORT" ] || { EP_NODE_ERR="ss link has no host:port"; printf '%s\n' "ss link has no host:port" >&2; return 1; }
			[ -n "$auth" ] && [ "${auth#*:}" != "$auth" ] || { EP_NODE_ERR="ss link has no method:password"; printf '%s\n' "ss link has no method:password" >&2; return 1; }
			printf 'type=shadowsocks\nserver=%s\nport=%s\nmethod=%s\npassword=%s\n' \
				"$EP_URI_HOST" "$EP_URI_PORT" "${auth%%:*}" "${auth#*:}"
			;;
		vmess)
			payload="$(ep_b64_decode "${body%%\#*}")" || { EP_NODE_ERR="vmess link is not valid base64"; printf '%s\n' "vmess link is not valid base64" >&2; return 1; }
			EP_URI_HOST="$(ep_json_field "$payload" add)"
			EP_URI_PORT="$(ep_json_field "$payload" port)"
			[ -n "$EP_URI_PORT" ] || EP_URI_PORT="$(ep_json_number "$payload" port)"
			auth="$(ep_json_field "$payload" id)"
			sni="$(ep_json_field "$payload" sni)"
			[ -n "$EP_URI_HOST" ] && [ -n "$EP_URI_PORT" ] && [ -n "$auth" ] \
				|| { EP_NODE_ERR="vmess link is missing add/port/id"; printf '%s\n' "vmess link is missing add/port/id" >&2; return 1; }
			printf 'type=vmess\nserver=%s\nport=%s\nuuid=%s\nalter_id=%s\n' \
				"$EP_URI_HOST" "$EP_URI_PORT" "$auth" "$(ep_json_number "$payload" aid)"
			case "$(ep_json_field "$payload" tls)" in
				tls|reality) printf 'tls=1\n' ;;
			esac
			[ -n "$sni" ] && printf 'sni=%s\n' "$sni"
			# vmess links keep the display name in the JSON body ("ps"), not in
			# the fragment, so fall back to it when there is no #name.
			if [ -z "$name" ]; then
				name="$(ep_json_field "$payload" ps)"
				[ -n "$name" ] && printf 'name=%s\n' "$name"
			fi
			;;
		vless|trojan|hysteria2|hy2|tuic)
			ep_uri_split "$body"
			[ -n "$EP_URI_HOST" ] && [ -n "$EP_URI_PORT" ] || { EP_NODE_ERR="$scheme link has no host:port"; printf '%s\n' "$scheme link has no host:port" >&2; return 1; }
			auth="$(ep_uri_unescape "$EP_URI_USER")"
			case "$scheme" in
				vless) printf 'type=vless\nuuid=%s\n' "$auth" ;;
				trojan) printf 'type=trojan\npassword=%s\ntls=1\n' "$auth" ;;
				hysteria2|hy2) printf 'type=hysteria2\npassword=%s\ntls=1\n' "$auth" ;;
				tuic) printf 'type=tuic\nuuid=%s\npassword=%s\ntls=1\n' "${auth%%:*}" "${auth#*:}" ;;
			esac
			printf 'server=%s\nport=%s\n' "$EP_URI_HOST" "$EP_URI_PORT"
			sni="$(ep_uri_param "$EP_URI_QUERY" sni)"
			[ -n "$sni" ] || sni="$(ep_uri_param "$EP_URI_QUERY" peer)"
			[ -n "$sni" ] && printf 'sni=%s\n' "$sni"
			security="$(ep_uri_param "$EP_URI_QUERY" security)"
			case "$security" in
				tls|reality) printf 'tls=1\n' ;;
			esac
			;;
		socks|socks5|http|https)
			ep_uri_split "$body"
			[ -n "$EP_URI_HOST" ] && [ -n "$EP_URI_PORT" ] || { EP_NODE_ERR="$scheme link has no host:port"; printf '%s\n' "$scheme link has no host:port" >&2; return 1; }
			case "$scheme" in
				socks|socks5) printf 'type=socks\n' ;;
				*) printf 'type=http\n' ;;
			esac
			printf 'server=%s\nport=%s\n' "$EP_URI_HOST" "$EP_URI_PORT"
			auth="$(ep_uri_unescape "$EP_URI_USER")"
			if [ -n "$auth" ]; then
				printf 'username=%s\n' "${auth%%:*}"
				printf 'password=%s\n' "${auth#*:}"
			fi
			;;
	esac
	return 0
}

# Rebuild a share link from a node section (ss / vmess / trojan / vless / socks / http)
ep_node_export_uri() {
	local section="$1" type server port method password uuid sni user name
	type="$(ep_get "$section" type '')"
	server="$(ep_get "$section" server '')"
	port="$(ep_get "$section" port '')"
	name="$(ep_node_tag "$section")"
	case "$type" in
		shadowsocks)
			method="$(ep_get "$section" method 'aes-256-gcm')"
			password="$(ep_get "$section" password '')"
			printf 'ss://%s@%s:%s#%s\n' \
				"$(ep_b64_encode "${method}:${password}")" "$server" "$port" "$name"
			;;
		trojan)
			password="$(ep_get "$section" password '')"
			sni="$(ep_get "$section" sni '')"
			printf 'trojan://%s@%s:%s' "$password" "$server" "$port"
			[ -n "$sni" ] && printf '?sni=%s' "$sni"
			printf '#%s\n' "$name"
			;;
		vless)
			uuid="$(ep_get "$section" uuid '')"
			sni="$(ep_get "$section" sni '')"
			printf 'vless://%s@%s:%s' "$uuid" "$server" "$port"
			[ -n "$sni" ] && printf '?sni=%s&security=tls' "$sni"
			printf '#%s\n' "$name"
			;;
		socks|http)
			user="$(ep_get "$section" username '')"
			password="$(ep_get "$section" password '')"
			if [ -n "$user" ]; then
				printf '%s://%s:%s@%s:%s#%s\n' "$type" "$user" "$password" "$server" "$port" "$name"
			else
				printf '%s://%s:%s#%s\n' "$type" "$server" "$port" "$name"
			fi
			;;
		hysteria2)
			password="$(ep_get "$section" password '')"
			sni="$(ep_get "$section" sni '')"
			printf 'hysteria2://%s@%s:%s' "$password" "$server" "$port"
			[ -n "$sni" ] && printf '?sni=%s' "$sni"
			printf '#%s\n' "$name"
			;;
		tuic)
			uuid="$(ep_get "$section" uuid '')"
			password="$(ep_get "$section" password '')"
			printf 'tuic://%s:%s@%s:%s#%s\n' "$uuid" "$password" "$server" "$port" "$name"
			;;
		vmess)
			uuid="$(ep_get "$section" uuid '')"
			printf 'vmess://%s\n' "$(ep_b64_encode "{\"v\":\"2\",\"ps\":\"${name}\",\"add\":\"${server}\",\"port\":\"${port}\",\"id\":\"${uuid}\",\"aid\":\"$(ep_get "$section" alter_id 0)\",\"net\":\"tcp\"}")"
			;;
		*) return 1 ;;
	esac
}

# Import one share link as a new node section. Prints the section id.
# `uci add` is used (not a fixed index) so an upgrade never collides.
ep_node_import() {
	local uri="$1" want_name="${2:-}" parsed section key value name
	parsed="$(ep_node_parse_uri "$uri")" || { printf '%s\n' "$EP_NODE_ERR" >&2; return 1; }
	[ -n "$parsed" ] || { echo "empty node definition" >&2; return 1; }

	section="$(uci -q add "$EP_CONFIG" node)" || { echo "cannot add a node section" >&2; return 1; }
	[ -n "$section" ] || { echo "uci did not return a section id" >&2; return 1; }
	printf '%s\n' "$parsed" | while IFS= read -r line; do
		[ -n "$line" ] || continue
		key="${line%%=*}"
		value="${line#*=}"
		uci -q set "${EP_CONFIG}.${section}.${key}" "$value"
	done
	uci -q set "${EP_CONFIG}.${section}.enabled" '1'
	if [ -n "$want_name" ]; then
		uci -q set "${EP_CONFIG}.${section}.name" "$want_name"
	else
		name="$(printf '%s\n' "$parsed" | sed -n 's/^name=//p')"
		[ -n "$name" ] && uci -q set "${EP_CONFIG}.${section}.name" "$name"
	fi
	uci -q commit "$EP_CONFIG" 2>/dev/null
	printf '%s' "$section"
}

# Delete a node section by name, server address or id
ep_node_delete() {
	local section
	section="$(ep_node_resolve "$1")" || { echo "no such node: $1" >&2; return 1; }
	uci -q delete "${EP_CONFIG}.${section}" 2>/dev/null
	uci -q commit "$EP_CONFIG" 2>/dev/null
	printf '%s' "$section"
}
