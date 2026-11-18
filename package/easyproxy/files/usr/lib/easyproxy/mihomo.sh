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

# --- routing ----------------------------------------------------------------
# mihomo does NOT need the sing-box rule-set files: GEOIP,CN is answered from
# the bundled geoip.metadb. Reusing ep_route_mode() here would pin a box that
# has nodes but never downloaded geosite-cn.srs to "direct" - the panel would
# look perfectly healthy while nothing was actually proxied.
ep_mihomo_has_node() {
	local section
	for section in $(ep_node_sections 2>/dev/null); do
		[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
		return 0
	done
	return 1
}

# Clash outbound names for the three EasyProxy-facing policy values
ep_mihomo_out() {
	case "$1" in
		direct) printf 'DIRECT' ;;
		block) printf 'REJECT' ;;
		*) printf 'PROXY' ;;
	esac
}

# Operator rules, same "type:value:outbound" store and the same order as the
# sing-box writer: they sit in front of GEOIP,CN so a custom entry always wins.
ep_mihomo_custom_rules() {
	local raw entry typ rest val out key old_ifs
	raw="$(ep_get routing custom_rules '')"
	[ -n "$raw" ] || return 0
	old_ifs="$IFS"
	IFS=';'
	for entry in $raw; do
		entry="$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		[ -n "$entry" ] || continue
		typ="${entry%%:*}"
		rest="${entry#*:}"
		val="${rest%%:*}"
		out="${rest#*:}"
		[ -n "$val" ] || continue
		case "$out" in
			direct|proxy|block) ;;
			*) continue ;;
		esac
		case "$typ" in
			domain) key=DOMAIN ;;
			domain-suffix|suffix) key=DOMAIN-SUFFIX ;;
			domain-keyword|keyword) key=DOMAIN-KEYWORD ;;
			ip|ip-cidr) key=IP-CIDR ;;
			*) continue ;;
		esac
		if [ "$key" = "IP-CIDR" ]; then
			printf '  - IP-CIDR,%s,%s,no-resolve\n' "$val" "$(ep_mihomo_out "$out")"
		else
			printf '  - %s,%s,%s\n' "$key" "$val" "$(ep_mihomo_out "$out")"
		fi
	done
	IFS="$old_ifs"
}

# YouTube / Netflix / TikTok. Same inline domain lists as the sing-box writer and
# they must come before GEOIP,CN: the CDN domains of a platform resolve into CN
# ranges often enough that the geo rule would claim them first.
ep_mihomo_platform_rules() {
	local key domains d
	for key in youtube netflix tiktok; do
		[ "$(ep_bool "$(ep_get routing "platform_${key}" 1)")" = "1" ] || continue
		case "$key" in
			youtube) domains="youtube.com youtu.be googlevideo.com ytimg.com youtube-nocookie.com yt3.ggpht.com" ;;
			netflix) domains="netflix.com netflix.net nflxext.com nflximg.com nflximg.net nflxso.net nflxvideo.net" ;;
			tiktok) domains="tiktok.com tiktokv.com tiktokcdn.com byteoversea.com ibytedtos.com muscdn.com" ;;
			*) continue ;;
		esac
		for d in $domains; do
			printf '  - DOMAIN-SUFFIX,%s,PROXY\n' "$d"
		done
	done
}

# One rule block. With no enabled node everything goes DIRECT: same failure
# closed behaviour as sing-box, so a box with no node can never pretend to proxy.
ep_mihomo_rules() {
	if ! ep_mihomo_has_node; then
		printf '  - MATCH,DIRECT\n'
		return 0
	fi
	# LAN traffic reaches the mixed inbound from other hosts on the box, and it
	# must never leave through the proxy.
	printf '  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve\n'
	printf '  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n'
	printf '  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve\n'
	printf '  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve\n'
	printf '  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve\n'
	ep_mihomo_custom_rules
	ep_mihomo_platform_rules
	printf '  - GEOIP,CN,DIRECT\n'
	printf '  - MATCH,PROXY\n'
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
	local sni tls alter_id raw dir f

	# A node imported from a Clash config keeps its original block, transports
	# included. Emitting it verbatim is the only way reality / ws / xhttp
	# options survive; the field-based path below would quietly drop them.
	raw="$(ep_get "$section" clash_raw '')"
	if [ -n "$raw" ]; then
		tag="$(ep_node_uniq_tag "$section")"
		if command -v ep_clash_dir >/dev/null 2>&1; then
			dir="$(ep_clash_dir)"
		else
			dir="$(ep_get main clash_dir '')"
			dir="${dir:-/etc/easyproxy/clash}"
		fi
		f="$dir/$raw"
		if [ ! -s "$f" ]; then
			ep_err "node $tag: imported clash block is missing ($f)"
			return 1
		fi
		# The generated tag is authoritative: it may carry a "-2" suffix when
		# two nodes share a display name, and a proxy whose name differs from
		# the one the group selects makes mihomo reject the whole config.
		awk -v n="$tag" '/^    name: / { print "    name: " n; next } { print }' "$f"
		return 0
	fi

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
		# Two levels, the layout every mature client converged on: the rules
		# point at PROXY, PROXY holds one url-test group per region, and each
		# region group picks the fastest node on its own. A user who wants
		# "Japan, fastest machine" never has to touch 9 individual nodes.
		regions="$tmp.regions"
		: > "$regions"
		for section in $node_sections; do
			[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
			reg="$(ep_node_region "$(ep_node_uniq_tag "$section")" "$(ep_get "$section" server "")")"
			grep -qx "$reg" "$regions" 2>/dev/null || printf '%s\n' "$reg" >> "$regions"
		done

		printf '  - name: PROXY\n'
		printf '    type: select\n'
		printf '    proxies:\n'
		# Manual direct first: a proxy plugin has to be able to stop proxying
		# for this stream without being stopped itself.
		printf '      - DIRECT\n'
		printf '      - %s\n' "$(ep_yaml_str "所有-自动")"
		while IFS= read -r reg; do
			printf '      - %s\n' "$(ep_yaml_str "自动-$(ep_region_label "$reg")")"
		done < "$regions"
		# Individual nodes stay selectable for the "just this one machine" case.
		for section in $node_sections; do
			[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
			printf '      - %s\n' "$(ep_yaml_str "$(ep_node_uniq_tag "$section")")"
		done
		printf '\n'

		# One url-test group per region found above.
		while IFS= read -r reg; do
			printf '  - name: %s\n' "$(ep_yaml_str "自动-$(ep_region_label "$reg")")"
			printf '    type: url-test\n'
			printf '    url: http://www.gstatic.com/generate_204\n'
			printf '    interval: 300\n'
			printf '    tolerance: 100\n'
			printf '    proxies:\n'
			for section in $node_sections; do
				[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
				tag="$(ep_node_uniq_tag "$section")"
				[ "$(ep_node_region "$tag" "$(ep_get "$section" server "")")" = "$reg" ] || continue
				printf '      - %s\n' "$(ep_yaml_str "$tag")"
			done
			printf '\n'
		done < "$regions"

		# Everything at once, for the user who does not care about the region.
		printf '  - name: %s\n' "$(ep_yaml_str "所有-自动")"
		printf '    type: url-test\n'
		printf '    url: http://www.gstatic.com/generate_204\n'
		printf '    interval: 300\n'
		printf '    tolerance: 100\n'
		printf '    proxies:\n'
		for section in $node_sections; do
			[ "$(ep_bool "$(ep_get "$section" enabled 1)")" = "1" ] || continue
			printf '      - %s\n' "$(ep_yaml_str "$(ep_node_uniq_tag "$section")")"
		done
		printf '\n'
		printf 'rules:\n'
		# Custom, platform, LAN, then the CN geo rule: the same precedence the
		# sing-box writer documents, so a node behaves identically on either engine.
		ep_mihomo_rules
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
	# The CLI summary reads this variable. Without it `config generate` printed
	# "direct only (nothing is proxied)" on a mihomo box whose config was in fact
	# splitting - a reassuring-looking line that contradicted the YAML.
	EP_ROUTE_MODE="split"
	rm -f "$tmp" "$tmp.regions" "$tmp.errmsg" "$tmp.tags" "$tmp.check"
	return 0
}
