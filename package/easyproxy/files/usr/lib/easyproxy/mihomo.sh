#!/bin/sh
# mihomo (Clash.Meta) configuration generation.
#
# Second engine next to sing-box. Both writers read the same UCI node sections
# so a node imported once works on either engine; this one renders Clash YAML
# instead of sing-box JSON.
#
# Only what EasyProxy actually drives is emitted: a mixed inbound, an external
# controller for stats, the proxies, one select group and a CN-direct rule.
#
# geodata matters here. mihomo downloads geoip.metadb on first start unless the
# file is already in its home directory - that blocked startup for 4.7 seconds
# on the test box and would simply fail on a box with no internet. So the
# package ships geoip.metadb under /etc/easyproxy/mihomo and geo-auto-update
# stays off.

# Double-quoted YAML scalar with the two characters that can break it escaped
ep_yaml_str() {
	printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# Home directory mihomo uses (-d): geodata and its own cache live here
ep_mihomo_home() {
	local value
	value="$(uci -q get easyproxy.mihomo.home 2>/dev/null)"
	printf '%s' "${value:-/etc/easyproxy/mihomo}"
}

# Local DNS servers for the nameserver list, one per line
ep_mihomo_nameservers() {
	local list
	list="$(ep_get routing dns_local_server '223.5.5.5')"
	printf '%s\n' "$list"
}

# The controller port is only bound to loopback; the panel reads stats from it
ep_mihomo_controller() {
	local value
	value="$(uci -q get easyproxy.mihomo.controller 2>/dev/null)"
	printf '%s' "${value:-127.0.0.1:9090}"
}

# One proxy entry. Prints nothing and sets EP_ERR when the node is unusable.
ep_mihomo_node() {
	local section="$1" tag type server port method password uuid flow
	local sni tls alter_id

	tag="$(ep_node_uniq_tag "$section")"
	type="$(ep_get "$section" type '')"
	server="$(ep_get "$section" server '')"
	port="$(ep_get "$section" port '')"
	sni="$(ep_get "$section" sni '')"
	tls="$(ep_bool "$(ep_get "$section" tls 0)")"

	[ -n "$type" ] || { ep_err "node ${tag}: missing type"; return 1; }
	[ -n "$server" ] || { ep_err "node ${tag}: missing server"; return 1; }
	case "$port" in
		''|*[!0-9]*) ep_err "node ${tag}: missing or non-numeric port"; return 1 ;;
	esac

	printf '  - name: %s\n' "$(ep_yaml_str "$tag")"
	printf '    server: %s\n' "$(ep_yaml_str "$server")"
	printf '    port: %s\n' "$port"

	case "$type" in
		shadowsocks)
			method="$(ep_get "$section" method 'aes-256-gcm')"
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: shadowsocks needs password"; return 1; }
			printf '    type: ss\n'
			printf '    cipher: %s\n' "$(ep_yaml_str "$method")"
			printf '    password: %s\n' "$(ep_yaml_str "$password")"
			if [ -n "$sni" ]; then printf '    sni: %s\n' "$(ep_yaml_str "$sni")"; fi
			;;
		vmess)
			uuid="$(ep_get "$section" uuid '')"
			alter_id="$(ep_get "$section" alter_id 0)"
			[ -n "$uuid" ] || { ep_err "node ${tag}: vmess needs uuid"; return 1; }
			case "$alter_id" in ''|*[!0-9]*) alter_id=0 ;; esac
			printf '    type: vmess\n'
			printf '    uuid: %s\n' "$(ep_yaml_str "$uuid")"
			printf '    alterId: %s\n' "$alter_id"
			printf '    cipher: auto\n'
			if [ "$tls" = "1" ]; then printf '    tls: true\n'; fi
			if [ -n "$sni" ]; then printf '    servername: %s\n' "$(ep_yaml_str "$sni")"; fi
			;;
		vless)
			uuid="$(ep_get "$section" uuid '')"
			flow="$(ep_get "$section" flow '')"
			[ -n "$uuid" ] || { ep_err "node ${tag}: vless needs uuid"; return 1; }
			printf '    type: vless\n'
			printf '    uuid: %s\n' "$(ep_yaml_str "$uuid")"
			if [ -n "$flow" ]; then printf '    flow: %s\n' "$(ep_yaml_str "$flow")"; fi
			if [ "$tls" = "1" ]; then printf '    tls: true\n'; fi
			if [ -n "$sni" ]; then printf '    servername: %s\n' "$(ep_yaml_str "$sni")"; fi
			printf '    udp: true\n'
			;;
		trojan)
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: trojan needs password"; return 1; }
			printf '    type: trojan\n'
			printf '    password: %s\n' "$(ep_yaml_str "$password")"
			if [ -n "$sni" ]; then printf '    sni: %s\n' "$(ep_yaml_str "$sni")"; fi
			printf '    udp: true\n'
			;;
		hysteria2)
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: hysteria2 needs password"; return 1; }
			printf '    type: hysteria2\n'
			printf '    password: %s\n' "$(ep_yaml_str "$password")"
			if [ -n "$sni" ]; then printf '    sni: %s\n' "$(ep_yaml_str "$sni")"; fi
			;;
		tuic)
			uuid="$(ep_get "$section" uuid '')"
			password="$(ep_get "$section" password '')"
			[ -n "$uuid" ] || { ep_err "node ${tag}: tuic needs uuid"; return 1; }
			[ -n "$password" ] || { ep_err "node ${tag}: tuic needs password"; return 1; }
			printf '    type: tuic\n'
			printf '    uuid: %s\n' "$(ep_yaml_str "$uuid")"
			printf '    password: %s\n' "$(ep_yaml_str "$password")"
			if [ -n "$sni" ]; then printf '    sni: %s\n' "$(ep_yaml_str "$sni")"; fi
			;;
		socks5)
			printf '    type: socks5\n'
			password="$(ep_get "$section" password '')"
			if [ -n "$password" ]; then
				printf '    username: %s\n' "$(ep_yaml_str "$(ep_get "$section" username '')")"
				printf '    password: %s\n' "$(ep_yaml_str "$password")"
			fi
			;;
		*)
			ep_err "node ${tag}: type ${type} has no mihomo mapping yet"
			return 1
			;;
	esac
	return 0
}

# Build the whole file into a temp path, validate it with the engine itself when
# the binary is present, and only then replace the live config.
ep_mihomo_config_build() {
	local outfile="${1:-}" tmp node_sections section count first_tag listen_port
	local log_level controller home ns binary

	EP_ERR=""
	outfile="${outfile:-$(ep_engine_config_path mihomo)}"
	[ -n "$outfile" ] || { EP_ERR="no config path configured"; return 1; }

	listen_port="$(ep_get main listen_port '7890')"
	case "$listen_port" in
		''|*[!0-9]*) EP_ERR="main.listen_port is not a number"; return 1 ;;
	esac
	log_level="$(ep_get main log_level 'info')"
	case "$log_level" in
		debug|info|warning|error|silent) : ;;
		warn) log_level=warning ;;
		*) log_level=info ;;
	esac
	controller="$(ep_mihomo_controller)"
	home="$(ep_mihomo_home)"

	tmp="$(mktemp)" || { EP_ERR="cannot create a temporary file"; return 1; }
	EP_ERR_FILE="$tmp.errmsg"
	: > "$EP_ERR_FILE"
	EP_TAG_MAP="$tmp.tags"
	export EP_TAG_MAP
	if command -v ep_build_tag_map >/dev/null 2>&1; then
		ep_build_tag_map "$EP_TAG_MAP"
	fi

	node_sections="$(ep_node_sections)"
	count=0
	first_tag=""
	for section in $node_sections; do
		[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
		count=$((count + 1))
	done
	[ "$count" -gt 0 ] || { rm -f "$tmp" "$tmp.errmsg" "$tmp.tags"; EP_ERR="no enabled nodes"; return 1; }

	{
		printf '# generated by EasyProxy - do not edit, run "easyproxy config generate"\n'
		printf 'mixed-port: %s\n' "$listen_port"
		printf 'bind-address: 127.0.0.1\n'
		printf 'allow-lan: false\n'
		printf 'mode: rule\n'
		printf 'log-level: %s\n' "$log_level"
		printf 'external-controller: %s\n' "$(ep_yaml_str "$controller")"
		printf 'external-ui: ""\n'
		printf 'unified-delay: true\n'
		printf 'tcp-concurrent: true\n'
		printf 'geodata-loader: memconservative\n'
		printf 'geo-auto-update: false\n'
		printf '\n'
		printf 'dns:\n'
		printf '  enable: true\n'
		printf '  ipv6: false\n'
		printf '  enhanced-mode: redir-host\n'
		printf '  nameserver:\n'
		for ns in $(ep_mihomo_nameservers); do
			printf '    - %s\n' "$(ep_yaml_str "$ns")"
		done
		printf '\n'
		printf 'proxies:\n'
		for section in $node_sections; do
			[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
			# Inside this block a `return` would only leave the redirection
			# subshell, so a bad node has to `exit` to surface as a failure.
			if ! ep_mihomo_node "$section"; then
				exit 1
			fi
			[ -n "$first_tag" ] || first_tag="$(ep_node_uniq_tag "$section")"
		done
		printf '\n'
		printf 'proxy-groups:\n'
		printf '  - name: PROXY\n'
		printf '    type: select\n'
		printf '    proxies:\n'
		for section in $node_sections; do
			[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
			printf '      - %s\n' "$(ep_yaml_str "$(ep_node_uniq_tag "$section")")"
		done
		printf '\n'
		printf 'rules:\n'
		printf '  - GEOIP,CN,DIRECT\n'
		printf '  - MATCH,PROXY\n'
	} > "$tmp.body" || {
		# ep_err inside the block wrote to EP_ERR_FILE, not to this shell
		if [ -s "$tmp.errmsg" ]; then
			EP_ERR="$(cat "$tmp.errmsg")"
		else
			EP_ERR="cannot write the config body"
		fi
		rm -f "$tmp"*
		return 1
	}

	# Validate with the engine's own parser. A file that mihomo rejects must
	# never replace a config that is currently working.
	if [ -n "$(ep_engine_binary mihomo)" ] && [ -x "$(ep_engine_binary mihomo)" ]; then
		mkdir -p "$home" 2>/dev/null
		if ! "$(ep_engine_binary mihomo)" -t -f "$tmp.body" -d "$home" >"$tmp.check" 2>&1; then
			EP_ERR="mihomo rejected the generated config: $(head -n 2 "$tmp.check" | tr '\n' ' ')"
			rm -f "$tmp"*
			return 1
		fi
	fi

	mv "$tmp.body" "$outfile" || { rm -f "$tmp"*; EP_ERR="cannot write $outfile"; return 1; }
	EP_NODES="$count"
	EP_FINAL="proxy"
	rm -f "$tmp" "$tmp.errmsg" "$tmp.tags" "$tmp.check"
	return 0
}
