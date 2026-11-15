#!/bin/sh

EP_CONFIG="easyproxy"

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
