#!/bin/sh
# dae engine contract. The dae runtime is not implemented yet: Stage 3 ships
# the sing-box runtime only, and `easyproxy start` refuses dae rather than
# pretending to have started something.

dae_check() {
	command -v dae >/dev/null 2>&1
}

dae_validate_config() {
	[ -r "$(uci -q get easyproxy.dae.config_file)" ]
}

dae_run() {
	echo "EasyProxy: the dae runtime adapter is not implemented yet." >&2
	return 2
}
