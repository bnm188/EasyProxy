#!/bin/sh
# Node import/export/grouping helpers.
#
# Busybox only: no python, no jq. A busybox image may ship `base64`, may ship
# `openssl`, and sometimes ships neither (the Kwrt 25.12 build this is tested
# against has both missing), so the awk codec below is the implementation that
# matters and the external tools are only a shortcut.
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

# Base64 decode; tolerant of standard and URL-safe alphabets ("-" "_"),
# missing padding and wrapped input. Share links in the wild are URL-safe
# base64 without padding, which plain `base64 -d` rejects outright.
#
# A busybox image frequently ships neither `base64` nor `openssl` (the Kwrt
# build this was tested on has neither), so the awk decoder below is the real
# implementation; the external tools are just a shortcut when present.
ep_b64_decode_awk() {
	awk 'BEGIN {
		alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (i = 1; i <= 64; i++) idx[substr(alpha, i, 1)] = i - 1;
	}
	{
		s = $0; n = length(s); out = "";
		for (p = 1; p <= n; p += 4) {
			ca = substr(s, p, 1);
			cb = substr(s, p + 1, 1);
			cc = substr(s, p + 2, 1);
			cd = substr(s, p + 3, 1);
			if (ca == "=" || cb == "") break;
			a = idx[ca];
			b = (cb == "") ? 0 : idx[cb];
			c = (cc == "" || cc == "=") ? -1 : idx[cc];
			d = (cd == "" || cd == "=") ? -1 : idx[cd];
			out = out sprintf("%c", a * 4 + int(b / 16));
			if (c >= 0) out = out sprintf("%c", (b % 16) * 16 + int(c / 4));
			if (d >= 0) out = out sprintf("%c", (c % 4) * 64 + d);
		}
		printf "%s", out;
	}'
}

ep_b64_decode() {
	local data="$1" pad
	case "$data" in
		*-*|*_*) data="$(printf '%s' "$data" | tr '_' '/' | tr '-' '+')" ;;
	esac
	pad=$(( ${#data} % 4 ))
	case "$pad" in
		2) data="${data}==" ;;
		3) data="${data}=" ;;
		1) return 1 ;;
	esac
	if command -v base64 >/dev/null 2>&1; then
		printf '%s' "$data" | base64 -d 2>/dev/null && return 0
	fi
	if command -v openssl >/dev/null 2>&1; then
		printf '%s' "$data" | openssl base64 -d -A 2>/dev/null && return 0
	fi
	if command -v awk >/dev/null 2>&1; then
		printf '%s\n' "$data" | ep_b64_decode_awk && return 0
	fi
	return 1
}

ep_b64_encode_awk() {
	awk 'function ord(c,   i) {
		for (i = 0; i < 256; i++)
			if (sprintf("%c", i) == c)
				return i;
		return 0;
	}
	BEGIN { alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; }
	{
		s = $0; n = length(s); out = "";
		for (p = 1; p <= n; p += 3) {
			c1 = ord(substr(s, p, 1));
			c2 = (p + 1 <= n) ? ord(substr(s, p + 1, 1)) : 0;
			c3 = (p + 2 <= n) ? ord(substr(s, p + 2, 1)) : 0;
			b1 = int(c1 / 4);
			b2 = (c1 % 4) * 16 + int(c2 / 16);
			b3 = (c2 % 16) * 4 + int(c3 / 64);
			b4 = c3 % 64;
			out = out substr(alpha, b1 + 1, 1) substr(alpha, b2 + 1, 1);
			out = out ((p + 1 <= n) ? substr(alpha, b3 + 1, 1) : "=");
			out = out ((p + 2 <= n) ? substr(alpha, b4 + 1, 1) : "=");
		}
		printf "%s", out;
	}'
}

ep_b64_encode() {
	if command -v base64 >/dev/null 2>&1; then
		printf '%s' "$1" | base64 | tr -d '\n'
		return 0
	fi
	if command -v openssl >/dev/null 2>&1; then
		printf '%s' "$1" | openssl base64 -A 2>/dev/null | tr -d '\n'
		return 0
	fi
	if command -v awk >/dev/null 2>&1; then
		printf '%s\n' "$1" | ep_b64_encode_awk
		return 0
	fi
	return 1
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
# Endpoint identity of a share link, without touching UCI. Used by the
# subscription importer so the same server is not imported twice.
ep_node_key_from_uri() {
	local uri="$1" parsed type server port method
	parsed="$(ep_node_parse_uri "$uri" 2>/dev/null)" || return 1
	type="$(printf '%s\n' "$parsed" | sed -n 's/^type=//p')"
	server="$(printf '%s\n' "$parsed" | sed -n 's/^server=//p')"
	port="$(printf '%s\n' "$parsed" | sed -n 's/^port=//p')"
	method="$(printf '%s\n' "$parsed" | sed -n 's/^method=//p')"
	[ -n "$server" ] || return 1
	printf '%s|%s|%s|%s' "$type" "$server" "$port" "$method"
}

ep_node_import() {
	local uri="$1" want_name="${2:-}" parsed section key value name dupkey existing
	parsed="$(ep_node_parse_uri "$uri")" || { printf '%s\n' "$EP_NODE_ERR" >&2; return 1; }
	[ -n "$parsed" ] || { echo "empty node definition" >&2; return 1; }

	# The same endpoint must not be stored twice: duplicate sections end up as
	# duplicate outbound tags and make the entire config generation fail.
	dupkey="$(printf '%s\n' "$parsed" | sed -n 's/^server=//p')"
	if [ -n "$dupkey" ]; then
		dupkey="$(printf '%s|%s|%s|%s' \
			"$(printf '%s\n' "$parsed" | sed -n 's/^type=//p')" \
			"$(printf '%s\n' "$parsed" | sed -n 's/^server=//p')" \
			"$(printf '%s\n' "$parsed" | sed -n 's/^port=//p')" \
			"$(printf '%s\n' "$parsed" | sed -n 's/^method=//p')")"
		existing="$(ep_node_sections | while read -r s; do
			[ "$(ep_node_key_of "$s")" = "$dupkey" ] && { printf '%s' "$s"; break; }
		done)"
		if [ -n "$existing" ]; then
			echo "node already exists: $existing ($(ep_node_tag "$existing"))" >&2
			return 1
		fi
	fi
	section="$(uci -q add "$EP_CONFIG" node)" || { echo "cannot add a node section" >&2; return 1; }
	[ -n "$section" ] || { echo "uci did not return a section id" >&2; return 1; }
	printf '%s\n' "$parsed" | while IFS= read -r line; do
		[ -n "$line" ] || continue
		key="${line%%=*}"
		value="${line#*=}"
		uci -q set "${EP_CONFIG}.${section}.${key}=${value}"
	done
	uci -q set "${EP_CONFIG}.${section}.enabled=1"
	if [ -n "$want_name" ]; then
		uci -q set "${EP_CONFIG}.${section}.name=${want_name}"
	else
		name="$(printf '%s\n' "$parsed" | sed -n 's/^name=//p')"
		[ -n "$name" ] && uci -q set "${EP_CONFIG}.${section}.name=${name}"
	fi
	uci -q commit "$EP_CONFIG" 2>/dev/null
	printf '%s' "$section"
}

# Where an imported Clash block is kept. The block itself is what gets written
# into mihomo's proxies list, so it never has to survive a lossy round trip
# through EasyProxy's own node fields.
ep_clash_dir() {
	local d
	d="$(ep_get main clash_dir '')"
	printf '%s' "${d:-/etc/easyproxy/clash}"
}

# Map a Clash proxy "type:" to the type name the rest of EasyProxy uses.
ep_clash_type() {
	case "$1" in
		ss) printf 'shadowsocks' ;;
		ssr) printf 'shadowsocksr' ;;
		*) printf '%s' "$1" ;;
	esac
}

# Import every proxy of a Clash / Clash.Meta config.
#
# Why the raw block is stored instead of field-mapped: a subscription carries
# reality-opts, ws-opts, xhttp-opts, grpc-opts ... Mapping them into EasyProxy
# node keys would drop the ones we have no field for, and a vless node that
# connects with the wrong transport looks healthy in the panel while never
# carrying a byte. The original block is therefore kept verbatim and handed to
# mihomo untouched; sing-box refuses those nodes on purpose (see config.sh).
# Is a node already stored under this display name? Compares the name option
# directly: a lookup by name through ep_node_resolve cannot be relied on for
# names with emoji or CJK characters.
ep_clash_name_taken() {
	local want="$1" sec
	for sec in $(ep_node_sections); do
		[ "$(ep_get "$sec" name '')" = "$want" ] && return 0
	done
	return 1
}

# Is this exact endpoint already stored? Providers publish dozens of entries
# under one display name, so the name alone decides nothing; the endpoint does.
ep_clash_endpoint_exists() {
	local t="$1" s="$2" p="$3" u="$4" pw="$5" sec
	for sec in $(ep_node_sections); do
		[ "$(ep_get "$sec" server '')" = "$s" ] || continue
		[ "$(ep_get "$sec" port '')" = "$p" ] || continue
		[ "$(ep_get "$sec" type '')" = "$(ep_clash_type "$t")" ] || continue
		if [ -n "$u" ]; then
			[ "$(ep_get "$sec" uuid '')" = "$u" ] || continue
		elif [ -n "$pw" ]; then
			[ "$(ep_get "$sec" password '')" = "$pw" ] || continue
		fi
		return 0
	done
	return 1
}

# Read one top-level key out of a Clash proxy block (4-space indent), with the
# surrounding quotes YAML may or may not use stripped off.
clash_field() {
	sed -n "s/^    $1: *//p" "$2" | head -n 1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

ep_node_import_clash() {
	local file="$1" dir tmp blocks blk name base n type server port uuid pw section raw imported skipped failed tag

	[ -n "$file" ] || { echo "usage: easyproxy node import-clash <file.yaml>" >&2; return 1; }
	[ -s "$file" ] || { echo "no such file or cannot read: $file" >&2; return 1; }
	dir="$(ep_clash_dir)"
	mkdir -p "$dir" 2>/dev/null
	tmp="$(mktemp -d)" || { echo "cannot create a temporary directory" >&2; return 1; }

	# Cut the proxies list into one file per entry. Top-level keys other than
	# proxies end the list, so proxy-groups / rules after it are ignored.
	awk -v dir="$tmp" '
		function flush() {
			if (n > 0) { f = dir "/blk" ++i; for (j = 1; j <= n; j++) print line[j] > f; close(f); n = 0 }
		}
		/^proxies:/ { inp = 1; next }
		inp && /^[A-Za-z_][A-Za-z0-9_-]*:/ { inp = 0; flush() }
		inp && /^  - / { flush(); line[++n] = $0; next }
		inp && n > 0 { line[++n] = $0 }
		END { flush() }
	' "$file" > /dev/null 2>&1

	blocks="$(ls "$tmp" 2>/dev/null | sort)"
	[ -n "$blocks" ] || { rm -rf "$tmp"; echo "no proxies found in $file" >&2; return 1; }

	imported=0; skipped=0; failed=0
	for blk in $blocks; do
		# 4-space indent marks a proxy's own keys; the leading "  - " of the
		# first line is rewritten so the whole entry reads the same way.
		sed -i -e 's/^  - /    /' "$tmp/$blk" 2>/dev/null
		name="$(clash_field name "$tmp/$blk")"
		type="$(clash_field type "$tmp/$blk")"
		server="$(clash_field server "$tmp/$blk")"
		port="$(clash_field port "$tmp/$blk")"
		uuid="$(clash_field uuid "$tmp/$blk")"
		pw="$(clash_field password "$tmp/$blk")"

		case "$port" in ''|*[!0-9]*) failed=$((failed + 1)); echo "skip (no port): ${name:-$blk}" >&2; continue ;; esac
		[ -n "$server" ] || { failed=$((failed + 1)); echo "skip (no server): ${name:-$blk}" >&2; continue; }
		[ -n "$name" ] || name="$type-$port"

		# Same endpoint twice is a real duplicate. The same display name over a
		# different server is not, so a clash gets a counter suffix instead of
		# being thrown away: mihomo refuses a config whose proxies share a name.
		if ep_clash_endpoint_exists "$type" "$server" "$port" "$uuid" "$pw"; then
			skipped=$((skipped + 1)); echo "skip (duplicate endpoint): $name" >&2; continue
		fi
		n=2
		base="$name"
		while ep_clash_name_taken "$name"; do
			name="$base ($n)"
			n=$((n + 1))
			[ "$n" -le 100 ] || break
		done
		tag="$name"
		raw=""
		# Rewrite the name inside the block as well: it has to match the tag the
		# panel and groups show, otherwise the entry exists but nothing selects it.
		awk -v n="$tag" '/^    name: / { print "    name: " n; next } { print }' "$tmp/$blk" > "$tmp/$blk.new" 2>/dev/null \
			&& mv "$tmp/$blk.new" "$tmp/$blk"

		section="$(uci -q add "$EP_CONFIG" node)" || { failed=$((failed + 1)); continue; }
		raw="$(printf '%s' "$section" | tr -c 'A-Za-z0-9_.-' '_').yaml"
		# The working copy dropped the "- " list marker so every key reads
		# uniformly; putting it back is what makes the block a proxies entry
		# again instead of a stray mapping inside the list.
		awk 'NR == 1 { sub(/^    /, "  - ") } { print }' "$tmp/$blk" > "$tmp/$blk.raw" 2>/dev/null
		cp "$tmp/$blk.raw" "$dir/$raw" 2>/dev/null || { failed=$((failed + 1)); continue; }

		uci -q set "${EP_CONFIG}.${section}.name=${tag}"
		uci -q set "${EP_CONFIG}.${section}.type=$(ep_clash_type "$type")"
		uci -q set "${EP_CONFIG}.${section}.server=${server}"
		uci -q set "${EP_CONFIG}.${section}.port=${port}"
		[ -n "$uuid" ] && uci -q set "${EP_CONFIG}.${section}.uuid=${uuid}"
		[ -n "$pw" ] && uci -q set "${EP_CONFIG}.${section}.password=${pw}"
		uci -q set "${EP_CONFIG}.${section}.clash_raw=${raw}"
		uci -q set "${EP_CONFIG}.${section}.enabled=1"
		uci -q commit "$EP_CONFIG" 2>/dev/null
		imported=$((imported + 1))
		echo "imported: $tag ($section)"
	done

	rm -rf "$tmp"
	printf 'clash import: %s imported, %s existed, %s unusable\n' "$imported" "$skipped" "$failed"
	[ "$imported" -gt 0 ]
}

# Delete a node section by name, server address or id
ep_node_delete() {
	local section raw dir
	section="$(ep_node_resolve "$1")" || { echo "no such node: $1" >&2; return 1; }
	# An imported Clash block lives in its own file; leaving it behind would
	# leak one dead file per deleted node forever.
	raw="$(ep_get "$section" clash_raw '')"
	if [ -n "$raw" ]; then
		dir="$(ep_clash_dir)"
		rm -f "$dir/$raw" 2>/dev/null
	fi
	uci -q delete "${EP_CONFIG}.${section}" 2>/dev/null
	uci -q commit "$EP_CONFIG" 2>/dev/null
	printf '%s' "$section"
}
