#!/bin/sh
# sing-box engine contract. The CLI generates the config with
# usr/lib/easyproxy/config.sh, then `easyproxy run` starts the process and
# supervises it (procd respawns the wrapper if it exits).

sing_box_binary() {
	uci -q get easyproxy.sing_box.binary 2>/dev/null || printf '%s' '/usr/bin/sing-box'
}

sing_box_config() {
	uci -q get easyproxy.sing_box.config_file 2>/dev/null || printf '%s' '/etc/easyproxy/sing-box.json'
}

sing_box_check() {
	local binary cfg
	binary="$(sing_box_binary)"
	cfg="$(sing_box_config)"
	[ -r "$cfg" ] || { echo "EasyProxy: config file missing: $cfg" >&2; return 1; }
	[ -x "$binary" ] || { echo "EasyProxy: binary missing: $binary" >&2; return 1; }
	"$binary" check -c "$cfg"
}

sing_box_run() {
	local binary cfg
	binary="$(sing_box_binary)"
	cfg="$(sing_box_config)"
	exec "$binary" run -c "$cfg"
}
