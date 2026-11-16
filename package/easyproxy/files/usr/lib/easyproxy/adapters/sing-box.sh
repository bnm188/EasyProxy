#!/bin/sh
# sing-box engine contract.
#
# Every engine adapter exposes the same six verbs, so neither the CLI nor the
# init script has to branch on the engine name:
#
#   <engine>_available    exit 0 when the binary can be executed
#   <engine>_version      first version line of the binary
#   <engine>_config       path of the config file it consumes
#   <engine>_validate     run the engine's own config check (exit 0 = ok)
#   <engine>_check        alias of <engine>_validate (kept for compatibility)
#   <engine>_run          exec the engine in the foreground (procd supervises)
#
# The CLI generates the config with usr/lib/easyproxy/config.sh, then
# `easyproxy run` starts whichever adapter is selected.

sing_box_binary() {
	uci -q get easyproxy.sing_box.binary 2>/dev/null || printf '%s' '/usr/bin/sing-box'
}

sing_box_config() {
	uci -q get easyproxy.sing_box.config_file 2>/dev/null || printf '%s' '/etc/easyproxy/sing-box.json'
}

sing_box_available() {
	local binary
	binary="$(sing_box_binary)"
	[ -n "$binary" ] && [ -x "$binary" ]
}

sing_box_version() {
	local binary
	binary="$(sing_box_binary)"
	sing_box_available || return 1
	"$binary" version 2>/dev/null | head -n 1
}

sing_box_validate() {
	local binary cfg
	binary="$(sing_box_binary)"
	cfg="$(sing_box_config)"
	[ -r "$cfg" ] || { echo "EasyProxy: config file missing: $cfg" >&2; return 1; }
	[ -x "$binary" ] || { echo "EasyProxy: binary missing: $binary" >&2; return 1; }
	"$binary" check -c "$cfg"
}

sing_box_check() {
	sing_box_validate
}

sing_box_run() {
	local binary cfg
	binary="$(sing_box_binary)"
	cfg="$(sing_box_config)"
	[ -x "$binary" ] || { echo "EasyProxy: binary missing: $binary" >&2; return 1; }
	exec "$binary" run -c "$cfg"
}
