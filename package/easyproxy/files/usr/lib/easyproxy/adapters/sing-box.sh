#!/bin/sh
# Stage 1 adapter contract. Runtime integration is implemented in Stage 2.

sing_box_check() {
	command -v sing-box >/dev/null 2>&1
}

sing_box_validate_config() {
	[ -r "$(uci -q get easyproxy.sing_box.config_file)" ]
}

sing_box_start() {
	echo "EasyProxy: sing-box runtime adapter is not implemented yet." >&2
	return 2
}

sing_box_stop() {
	echo "EasyProxy: sing-box runtime adapter is not implemented yet." >&2
	return 2
}
