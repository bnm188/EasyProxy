#!/bin/sh

EP_CONFIG="easyproxy"
EP_CONFIG_FILE="/etc/config/easyproxy"
EP_VERSION="0.6.0"
EP_STAGE="6"

EP_RUNTIME_DIR="${EP_RUNTIME_DIR:-/var/run/easyproxy}"
EP_PID_FILE="$EP_RUNTIME_DIR/easyproxy.pid"
EP_LOG_FILE="${EP_LOG_FILE:-/var/log/easyproxy.log}"

ep_log() {
	logger -t easyproxy "$*"
}

ep_get() {
	local section="$1"
	local option="$2"
	local fallback="$3"
	local value
	value="$(uci -q get "${EP_CONFIG}.${section}.${option}" 2>/dev/null)"
	[ -n "$value" ] && printf '%s' "$value" || printf '%s' "$fallback"
}

ep_valid_engine() {
	case "$1" in
		none|dae|sing-box) return 0 ;;
		*) return 1 ;;
	esac
}

ep_adapter_path() {
	case "$1" in
		dae) printf '%s' '/usr/lib/easyproxy/adapters/dae.sh' ;;
		sing-box) printf '%s' '/usr/lib/easyproxy/adapters/sing-box.sh' ;;
		*) return 1 ;;
	esac
}

# UCI section that holds the defaults of a given engine
ep_engine_section() {
	case "$1" in
		dae) printf '%s' 'dae' ;;
		sing-box) printf '%s' 'sing_box' ;;
		*) return 1 ;;
	esac
}

# Absolute path of the selected engine binary (empty when no engine is set)
ep_engine_binary() {
	local section
	section="$(ep_engine_section "$1")" || return 0
	case "$1" in
		dae) ep_get "$section" binary '/usr/bin/dae' ;;
		sing-box) ep_get "$section" binary '/usr/bin/sing-box' ;;
	esac
}

# Path of the config file the selected engine consumes
ep_engine_config_path() {
	local section
	section="$(ep_engine_section "$1")" || return 0
	case "$1" in
		dae) ep_get "$section" config_file '/etc/easyproxy/dae.conf' ;;
		sing-box) ep_get "$section" config_file '/etc/easyproxy/sing-box.json' ;;
	esac
}

# available | missing
ep_binary_state() {
	if [ -n "$1" ] && [ -x "$1" ]; then
		printf '%s' 'available'
	else
		printf '%s' 'missing'
	fi
}

# Number of configured node sections, named or anonymous
ep_node_count() {
	uci -q show "$EP_CONFIG" 2>/dev/null \
		| awk -F= '$2 == "node" { c++ } END { printf "%d", c + 0 }'
}

# Section identifiers of every node, named or anonymous
ep_node_sections() {
	uci -q show "$EP_CONFIG" 2>/dev/null \
		| sed -n 's/^easyproxy\.\([^.=]*\)=node$/\1/p'
}

# Number of nodes that are not explicitly disabled
ep_node_count_enabled() {
	local section count=0
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" enabled 1)" = "1" ] && count=$((count + 1))
	done
	printf '%s' "$count"
}

# Running wrapper PID, empty when the pid file is stale or absent
ep_pid() {
	local pid started
	[ -r "$EP_PID_FILE" ] || return 0
	read -r pid started < "$EP_PID_FILE" 2>/dev/null || return 0
	[ -n "${pid:-}" ] || return 0
	[ -d "/proc/$pid" ] || return 0
	printf '%s' "$pid"
}

# running | stopped
ep_runtime_state() {
	if [ -n "$(ep_pid)" ]; then
		printf '%s' 'running'
	else
		printf '%s' 'stopped'
	fi
}

# Seconds since the wrapper started, 0 when not running
ep_runtime_uptime() {
	local pid started now
	[ -r "$EP_PID_FILE" ] || { printf '0'; return 0; }
	read -r pid started < "$EP_PID_FILE" 2>/dev/null || { printf '0'; return 0; }
	[ -n "${started:-}" ] || { printf '0'; return 0; }
	now="$(date +%s)"
	[ "$now" -gt "$started" ] 2>/dev/null && printf '%s' "$((now - started))" || printf '0'
}

# Directory holding the local rule-set files used by the domestic split
ep_rule_set_dir() {
	ep_get routing rule_set_dir '/etc/easyproxy/ruleset'
}

# ready | missing — both CN rule sets present and non-empty
ep_rule_set_state() {
	local dir
	dir="$(ep_rule_set_dir)"
	if [ -s "$dir/geosite-cn.srs" ] && [ -s "$dir/geoip-cn.srs" ]; then
		printf '%s' 'ready'
	else
		printf '%s' 'missing'
	fi
}

# ok | invalid | missing — validated with the engine binary when one is installed
ep_config_state() {
	local engine binary path
	engine="$(ep_get main engine none)"
	binary="$(ep_engine_binary "$engine")"
	path="$(ep_engine_config_path "$engine")"
	[ -n "$path" ] && [ -s "$path" ] || { printf '%s' 'missing'; return 0; }
	if [ "$(ep_binary_state "$binary")" = "available" ]; then
		if "$binary" check -c "$path" >/dev/null 2>&1; then
			printf '%s' 'ok'
		else
			printf '%s' 'invalid'
		fi
	else
		printf '%s' 'ok'
	fi
}

# Escape a value so it can be embedded inside a JSON string literal
ep_json_escape() {
	printf '%s' "$1" | tr -d '\r\n' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}

# Normalise a boolean UCI value to 0/1
ep_bool() {
	case "$1" in
		1) printf '1' ;;
		*) printf '0' ;;
	esac
}

ep_utc_now() {
	date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null
}
