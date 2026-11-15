#!/bin/sh
# Stage 1 adapter contract. Runtime integration is implemented in Stage 2.

dae_check() {
	command -v dae >/dev/null 2>&1
}

dae_validate_config() {
	[ -r "$(uci -q get easyproxy.dae.config_file)" ]
}

dae_start() {
	echo "EasyProxy: dae runtime adapter is not implemented yet." >&2
	return 2
}

dae_stop() {
	echo "EasyProxy: dae runtime adapter is not implemented yet." >&2
	return 2
}
