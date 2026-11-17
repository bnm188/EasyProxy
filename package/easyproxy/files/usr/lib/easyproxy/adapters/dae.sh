#!/bin/sh
# dae engine contract — FRAME ONLY (开发中 / dev).
#
# The dae runtime is not implemented in this stage. The adapter still implements
# the same six verbs as the sing-box one so that switching engines later is a
# UCI change plus work on this file, not a change in the CLI, the init script or
# the LuCI panel:
#
#   dae_available / dae_version / dae_config / dae_validate / dae_check / dae_run
#
# `ep_engine_stability` reports dae as `dev`, which makes `easyproxy start` and
# the panel refuse it with an explicit "开发中" message instead of pretending
# something started.

dae_binary() {
	uci -q get easyproxy.dae.binary 2>/dev/null || printf '%s' '/usr/bin/dae'
}

dae_config() {
	uci -q get easyproxy.dae.config_file 2>/dev/null || printf '%s' '/etc/easyproxy/dae.conf'
}

dae_available() {
	local binary
	binary="$(dae_binary)"
	[ -n "$binary" ] && [ -x "$binary" ]
}

dae_version() {
	local binary
	binary="$(dae_binary)"
	dae_available || return 1
	"$binary" --version 2>/dev/null | head -n 1
}

# The dae config is only checked for presence: there is no implemented
# validator yet, and claiming one would be worse than saying so.
dae_validate() {
	[ -r "$(dae_config)" ]
}

dae_check() {
	dae_available
}

dae_run() {
	echo "EasyProxy: dae runtime is 开发中 (dev): the adapter contract exists, the runtime does not." >&2
	return 2
}
