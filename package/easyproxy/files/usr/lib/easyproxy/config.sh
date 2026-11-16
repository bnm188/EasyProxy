#!/bin/sh
# sing-box configuration generation.
#
# Turns the "config node" sections of /etc/config/easyproxy into a sing-box
# config file. Only enabled nodes are emitted; the result is validated with
# `sing-box check` before it replaces the live file.

EP_ERR=""
EP_ERR_FILE=""

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
	local tls sni

	tag="$(ep_node_tag "$section")"
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
			printf '{"type":"shadowsocks","tag":"%s","server":"%s","server_port":%s,"method":"%s","password":"%s"}%s' \
				"$tag" "$server" "$port" "$(ep_json_escape "$method")" "$(ep_json_escape "$password")" "$tls"
			;;
		vmess)
			uuid="$(ep_get "$section" uuid '')"
			alter_id="$(ep_get "$section" alter_id 0)"
			[ -n "$uuid" ] || { ep_err "node ${tag}: vmess needs uuid"; return 1; }
			case "$alter_id" in ''|*[!0-9]*) alter_id=0 ;; esac
			printf '{"type":"vmess","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","alter_id":%s,"security":"auto"}%s' \
				"$tag" "$server" "$port" "$(ep_json_escape "$uuid")" "$alter_id" "$tls"
			;;
		trojan)
			password="$(ep_get "$section" password '')"
			[ -n "$password" ] || { ep_err "node ${tag}: trojan needs password"; return 1; }
			printf '{"type":"trojan","tag":"%s","server":"%s","server_port":%s,"password":"%s"}%s' \
				"$tag" "$server" "$port" "$(ep_json_escape "$password")" "$tls"
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

# Build the config file. Returns 0 on success, non-zero with EP_ERR set.
# Exit 2 means the file was assembled but the engine rejected it.
ep_config_build() {
	local outfile="$1" engine binary listen listen_port final
	local tmp out sections tags nodes section line
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

	if [ "$nodes" -gt 0 ]; then
		final="proxy"
	else
		final="direct"
	fi

	{
		printf '{\n'
		printf '  "log": { "level": "%s", "timestamp": true },\n' \
			"$(ep_singbox_log_level "$(ep_get main log_level notice)")"
		printf '  "inbounds": [\n'
		printf '    { "type": "mixed", "tag": "mixed-in", "listen": "%s", "listen_port": %s }\n' \
			"$(ep_json_escape "$listen")" "$listen_port"
		printf '  ],\n'
		printf '  "outbounds": [\n'
		if [ "$nodes" -gt 0 ]; then
			# Node outbounds followed by the latency-tested selector
			awk '{ printf "    %s,\n", $0 }' "$out"
			printf '    { "type": "urltest", "tag": "proxy", "outbounds": ['
			first=1
			for section in $sections; do
				[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
				[ "$first" = "1" ] || printf ', '
				printf '"%s"' "$(ep_json_escape "$(ep_node_tag "$section")")"
				first=0
			done
			printf '], "url": "http://www.gstatic.com/generate_204", "interval": "5m", "tolerance": 50 },\n'
		fi
		printf '    { "type": "direct", "tag": "direct" }\n'
		printf '  ],\n'
		printf '  "route": { "final": "%s" }\n' "$final"
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
	return 0
}
