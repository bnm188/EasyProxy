#!/bin/sh

EP_CONFIG="easyproxy"
EP_CONFIG_FILE="/etc/config/easyproxy"
EP_VERSION="0.2.0"
EP_STAGE="2"

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
