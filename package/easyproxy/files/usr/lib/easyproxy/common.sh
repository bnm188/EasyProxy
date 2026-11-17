#!/bin/sh

EP_CONFIG="easyproxy"
EP_CONFIG_FILE="${EP_CONFIG_FILE:-/etc/config/easyproxy}"
EP_VERSION="0.8.13"
EP_STAGE="7"

EP_RUNTIME_DIR="${EP_RUNTIME_DIR:-/var/run/easyproxy}"
EP_PID_FILE="$EP_RUNTIME_DIR/easyproxy.pid"
EP_LOG_FILE="${EP_LOG_FILE:-/var/log/easyproxy.log}"
EP_LIB_DIR="${EP_LIB_DIR:-/usr/lib/easyproxy}"

# Two sinks on purpose: syslog (so `logread -e easyproxy` works and procd keeps
# it after a reboot) and a file the panel and `doctor` can read. The file is
# created 0600 - a log line can quote a node URL or a subscription token, and
# /var/log is world-readable on OpenWrt by default.
ep_log() {
	local msg
	msg="$*"
	logger -t easyproxy "$msg" 2>/dev/null || true
	[ -n "${EP_LOG_FILE:-}" ] || return 0
	[ -d "$(dirname "$EP_LOG_FILE")" ] || return 0
	if [ ! -e "$EP_LOG_FILE" ]; then
		( umask 077; : >> "$EP_LOG_FILE" ) 2>/dev/null || return 0
		chmod 600 "$EP_LOG_FILE" 2>/dev/null || true
	fi
	ep_log_maybe_rotate
	printf '%s easyproxy: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$msg" \
		>> "$EP_LOG_FILE" 2>/dev/null || return 0
	return 0
}

# Rotate at the configured size before the file grows without bound. Called from
# every log write because that is the only place that knows the log is filling.
ep_log_maybe_rotate() {
	local max size
	[ -n "${EP_LOG_FILE:-}" ] || return 0
	[ -s "$EP_LOG_FILE" ] || return 0
	max="$(ep_get main log_max_bytes 1048576)"
	case "$max" in ''|*[!0-9]*) max=1048576 ;; esac
	size="$(wc -c < "$EP_LOG_FILE" 2>/dev/null | tr -d ' ')"
	case "$size" in ''|*[!0-9]*) return 0 ;; esac
	[ "$size" -le "$max" ] && return 0
	mv -f "$EP_LOG_FILE" "$EP_LOG_FILE.1" 2>/dev/null || return 0
	( umask 077; : >> "$EP_LOG_FILE" ) 2>/dev/null
	chmod 600 "$EP_LOG_FILE" 2>/dev/null || true
	return 0
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
		dae) printf '%s' "$EP_LIB_DIR/adapters/dae.sh" ;;
		sing-box) printf '%s' "$EP_LIB_DIR/adapters/sing-box.sh" ;;
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
# Where sing-box is likely to live. Firmware bundles vary: this router ships
# Open-Box under /opt/open-box/bin instead of /usr/bin, so a stale recorded
# path must not turn into "binary missing" while the engine is installed.
EP_SING_BOX_BIN_CANDIDATES="${EP_SING_BOX_BIN_CANDIDATES:-/usr/bin/sing-box /usr/sbin/sing-box /opt/open-box/bin/sing-box /opt/bin/sing-box /usr/lib/sing-box/sing-box}"

ep_engine_binary() {
	local section recorded found
	section="$(ep_engine_section "$1")" || return 0
	case "$1" in
		dae) ep_get "$section" binary '/usr/bin/dae' ;;
		sing-box) recorded="$(ep_get "$section" binary '/usr/bin/sing-box')" ;;
		*) return 0 ;;
	esac
	[ "$1" = "sing-box" ] || { printf '%s' "$recorded"; return 0; }
	if [ -n "$recorded" ] && [ -x "$recorded" ]; then
		printf '%s' "$recorded"
		return 0
	fi
	for found in $EP_SING_BOX_BIN_CANDIDATES; do
		if [ -x "$found" ]; then
			printf '%s' "$found"
			return 0
		fi
	done
	printf '%s' "$recorded"
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

# Tag actually used for a node inside a generated config. Two nodes that share
# a display name would otherwise emit the same outbound tag and sing-box
# rejects the whole config ("duplicate outbound/endpoint tag"), taking every
# proxy down. EP_TAG_MAP is built once per generate run by
# ep_build_tag_map; without it this falls back to the plain name.
ep_node_uniq_tag() {
	local section="$1" mapped=""
	if [ -n "${EP_TAG_MAP:-}" ] && [ -f "$EP_TAG_MAP" ]; then
		mapped="$(awk -F'\t' -v s="$section" '$1 == s { print $2; exit }' "$EP_TAG_MAP" 2>/dev/null)"
		[ -n "$mapped" ] && { printf '%s' "$mapped"; return 0; }
	fi
	ep_node_tag "$section"
}

# Build section -> unique tag mapping for all enabled nodes. Duplicates get a
# "-2", "-3" ... suffix in section order, stable across regenerations.
ep_build_tag_map() {
	local out="$1" section base uniq n seen
	: > "$out"
	seen=" "
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
		base="$(ep_node_tag "$section")"
		[ -n "$base" ] || base="$section"
		uniq="$base"
		n=2
		while :; do
			case "$seen" in
				*" $uniq "*) uniq="${base}-${n}"; n=$((n + 1)) ;;
				*) break ;;
			esac
		done
		seen="$seen$uniq "
		printf '%s\t%s\n' "$section" "$uniq" >> "$out"
	done
	return 0
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

# --- engine registry ---------------------------------------------------------
# One line per engine, "<name>:<stability>". `dev` means the adapter exists as a
# frame (config path, binary, check/run contract) but the runtime is not
# implemented: the CLI refuses to start it and status says so instead of
# pretending something is running.
ep_engine_list() {
	printf 'sing-box:stable\ndae:dev\n'
}

ep_engine_stability() {
	local engine="$1" name stability
	while IFS=: read -r name stability; do
		[ "$name" = "$engine" ] && { printf '%s' "$stability"; return 0; }
	done <<EOF
$(ep_engine_list)
EOF
	printf '%s' 'unknown'
}

# stable | dev | unknown — the label humans see in status/engine output
ep_engine_label() {
	case "$(ep_engine_stability "$1")" in
		dev) printf '%s (开发中 / dev)' "$1" ;;
		stable) printf '%s' "$1" ;;
		*) printf '%s (unknown)' "$1" ;;
	esac
}

# 1 when the engine has a working runtime, 0 when it is still a frame
ep_engine_is_dev() {
	[ "$(ep_engine_stability "$1")" = "dev" ] && printf '1' || printf '0'
}

# Why an engine cannot run yet, empty for a stable engine
ep_engine_dev_reason() {
	case "$1" in
		dae) printf '%s' 'dae runtime adapter is not implemented yet; the config/binary/lifecycle contract is kept so the engine can be switched in later' ;;
		*) printf '%s' '' ;;
	esac
}

# The adapter file that implements the engine contract, empty when unknown
ep_engine_adapter_file() {
	ep_adapter_path "$1" 2>/dev/null
}

# First version line of the engine binary, empty when it cannot be asked
ep_engine_version() {
	local binary="$1"
	[ -n "$binary" ] && [ -x "$binary" ] || return 0
	"$binary" version 2>/dev/null | head -n 1
}

# Print one tab-separated health/diagnostic line: status<TAB>check<TAB>detail
ep_health_line() {
	printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}"
}

# 1 when something is listening on <port> locally, 0 otherwise.
# Reads /proc/net/tcp{,6} so it works on a router without ss/netstat.
ep_port_listening() {
	local port="$1" hex
	case "$port" in
		''|*[!0-9]*) printf '0'; return 0 ;;
	esac
	hex="$(printf '%04X' "$port" 2>/dev/null)" || { printf '0'; return 0; }
	if awk -v want="$hex" '
		NR > 1 && $4 == "0A" {
			split($2, a, ":")
			if (toupper(a[2]) == want) { found = 1 }
		}
		END { exit(found ? 0 : 1) }' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
		printf '1'
	else
		printf '0'
	fi
}

# Milliseconds since the epoch, second granularity when %N is unavailable
ep_now_ms() {
	local ms
	ms="$(date +%s%3N 2>/dev/null)"
	case "$ms" in
		''|*[!0-9]*) ms=$(( $(date +%s) * 1000 )) ;;
	esac
	printf '%s' "$ms"
}

# Measure a TCP handshake to host:port. Prints "<ms>" on success, "unreachable"
# on a refused/timeout connection, "unknown" when no probe tool is installed.
# nc is preferred (busybox ships it); curl is the fallback and only exit 0
# counts as a completed handshake.
ep_tcp_probe() {
	local host="$1" port="$2" timeout="${3:-3}" start end rc
	[ -n "$host" ] && [ -n "$port" ] || { printf '%s' 'unknown'; return 0; }
	case "$port" in
		''|*[!0-9]*) printf '%s' 'unknown'; return 0 ;;
	esac
	# curl first: the busybox `nc` on a stripped firmware is a two-argument
	# "nc IPADDR PORT" build that rejects -w and exits 1 on every call, which
	# silently marked every node unreachable.
	if command -v curl >/dev/null 2>&1; then
		start="$(ep_now_ms)"
		curl -sS -o /dev/null --connect-timeout "$timeout" --max-time "$timeout" \
			"http://${host}:${port}/" >/dev/null 2>&1
		rc=$?
		end="$(ep_now_ms)"
		# A shadowsocks/socks port speaks no HTTP, so a completed handshake
		# comes back as 52 (empty reply) or 56 (reset) -- the port is alive.
		# Only "never reached" is a failure: 7 refused, 28 timeout,
		# 6/35 resolution or TLS.
		case "$rc" in
			0|52|56|92) printf '%s' "$((end - start))" ;;
			*) printf '%s' 'unreachable' ;;
		esac
		return 0
	fi
	if command -v nc >/dev/null 2>&1; then
		start="$(ep_now_ms)"
		nc -w "$timeout" "$host" "$port" </dev/null >/dev/null 2>&1
		rc=$?
		end="$(ep_now_ms)"
		if [ "$rc" = "0" ]; then
			printf '%s' "$((end - start))"
		else
			printf '%s' 'unreachable'
		fi
		return 0
	fi
	printf '%s' 'unknown'
}

# TCP probe for one node section: "<reachable|unreachable|unknown> <ms|->"
ep_node_probe() {
	local section="$1" server port timeout result
	server="$(ep_get "$section" server '')"
	port="$(ep_get "$section" port '')"
	timeout="$(ep_get routing probe_timeout 3)"
	case "$timeout" in ''|*[!0-9]*) timeout=3 ;; esac
	result="$(ep_tcp_probe "$server" "$port" "$timeout")"
	case "$result" in
		unreachable) printf 'unreachable -' ;;
		unknown) printf 'unknown -' ;;
		'') printf 'unknown -' ;;
		*) printf 'reachable %s' "$result" ;;
	esac
}

# Full engine health report: one ep_health_line per check, exit 0 when no check
# failed (warnings do not fail). This is what `easyproxy engine health` prints.
ep_engine_health() {
	local engine binary bstate cfg cfg_state runtime port adapter version
	local failed=0
	engine="$(ep_get main engine none)"

	if [ "$(ep_bool "$(ep_get main enabled 0)")" = "1" ]; then
		ep_health_line ok enabled "main.enabled=1"
	else
		ep_health_line warn enabled "main.enabled=0: the engine is configured but EasyProxy is switched off"
	fi

	if [ "$engine" = "none" ]; then
		ep_health_line fail engine "no proxy engine selected (main.engine=none)"
		return 1
	fi
	ep_health_line ok engine "main.engine=$engine ($(ep_engine_stability "$engine"))"
	if [ "$(ep_engine_is_dev "$engine")" = "1" ]; then
		ep_health_line warn dev "$(ep_engine_dev_reason "$engine")"
	fi

	adapter="$(ep_engine_adapter_file "$engine")"
	if [ -n "$adapter" ] && [ -r "$adapter" ]; then
		ep_health_line ok adapter "$adapter"
	else
		ep_health_line fail adapter "adapter missing for engine $engine"
		failed=1
	fi

	binary="$(ep_engine_binary "$engine")"
	bstate="$(ep_binary_state "$binary")"
	if [ "$bstate" = "available" ]; then
		version="$(ep_engine_version "$binary")"
		ep_health_line ok binary "${binary} (${version:-version unknown})"
	else
		ep_health_line fail binary "engine binary missing: ${binary:-unset}"
		failed=1
	fi

	cfg="$(ep_engine_config_path "$engine")"
	cfg_state="$(ep_config_state)"
	case "$cfg_state" in
		ok) ep_health_line ok config "$cfg" ;;
		invalid) ep_health_line fail config "generated config rejected by the engine: $cfg"; failed=1 ;;
		*) ep_health_line warn config "no generated config yet: $cfg (run easyproxy config generate)" ;;
	esac

	runtime="$(ep_runtime_state)"
	if [ "$runtime" = "running" ]; then
		ep_health_line ok runtime "wrapper running (pid $(ep_pid), up $(ep_runtime_uptime)s)"
	else
		ep_health_line warn runtime "wrapper not running (easyproxy start)"
	fi

	port="$(ep_get main listen_port 7890)"
	if [ "$runtime" = "running" ]; then
		if [ "$(ep_port_listening "$port")" = "1" ]; then
			ep_health_line ok listen "port $port is listening"
		else
			ep_health_line fail listen "wrapper is running but nothing listens on port $port (engine crashed or config broken)"; failed=1
		fi
	else
		ep_health_line warn listen "port $port not checked while the wrapper is stopped"
	fi

	[ "$failed" = "0" ] && return 0 || return 1
}

# --- node grouping ---------------------------------------------------------
# These live in common.sh because config generation needs them on every host,
# while the share-link parsers are only needed when importing a node.

# "name", server address or a section id -> section id
# Identity of a node for duplicate detection: the same server/port with the
# same protocol method is the same endpoint, no matter what it was named.
ep_node_key_of() {
	local section="$1"
	printf '%s|%s|%s|%s' \
		"$(ep_get "$section" type '')" \
		"$(ep_get "$section" server '')" \
		"$(ep_get "$section" port '')" \
		"$(ep_get "$section" method '')"
}

# 0 when a node with the same endpoint already exists. Subscriptions re-imported
# twice used to create duplicate sections, which then produced a duplicate
# outbound tag and made the whole config generation fail.
ep_node_exists_key() {
	local key="$1" section
	for section in $(ep_node_sections); do
		[ "$(ep_node_key_of "$section")" = "$key" ] && return 0
	done
	return 1
}

ep_node_resolve() {
	local want="$1" section
	for section in $(ep_node_sections); do
		[ "$section" = "$want" ] && { printf '%s' "$section"; return 0; }
	done
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" name '')" = "$want" ] && { printf '%s' "$section"; return 0; }
	done
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" server '')" = "$want" ] && { printf '%s' "$section"; return 0; }
	done
	return 1
}

# Region bucket for automatic grouping; unknown names land in "other"
ep_node_region() {
	local name
	case "$1" in
		# unnamed nodes fall back to their UCI id ("@node[3]"), which must not
		# be scanned for region keywords: "node" contains "de".
		@*) printf 'other'; return 0 ;;
	esac
	name="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
	case "$name" in
		*hk*|*hongkong*|*"hong kong"*|*香港*) printf 'hk' ;;
		*tw*|*taiwan*|*台湾*|*台灣*) printf 'tw' ;;
		*jp*|*japan*|*日本*|*东京*|*東京*|*大阪*) printf 'jp' ;;
		*sg*|*singapore*|*新加坡*) printf 'sg' ;;
		*us*|*unitedstates*|*"united states"*|*美国*|*美國*|*洛杉矶*|*硅谷*) printf 'us' ;;
		*uk*|*gb*|*london*|*英国*|*英國*|*伦敦*) printf 'uk' ;;
		*de*|*germany*|*德国*|*德國*|*法兰克福*) printf 'de' ;;
		*kr*|*korea*|*韩国*|*韓國*|*首尔*) printf 'kr' ;;
		*ru*|*russia*|*俄罗斯*|*俄羅斯*|*莫斯科*) printf 'ru' ;;
		*) printf 'other' ;;
	esac
}

# Distinct regions across enabled nodes, "other" last
ep_node_regions() {
	local section region seen
	seen=""
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
		# a section with no type is a placeholder, not a node: no group for it
		[ -n "$(ep_get "$section" type '')" ] || continue
		region="$(ep_node_region "$(ep_node_tag "$section")")"
		case " $seen " in
			*" $region "*) continue ;;
		esac
		seen="$seen $region"
	done
	for region in $seen; do
		[ "$region" = "other" ] || printf '%s\n' "$region"
	done
	case " $seen " in
		*" other "*) printf 'other\n' ;;
	esac
}

# Section ids of the enabled nodes belonging to one region
ep_node_sections_in_region() {
	local section
	for section in $(ep_node_sections); do
		[ "$(ep_get "$section" enabled 1)" = "1" ] || continue
		[ -n "$(ep_get "$section" type '')" ] || continue
		[ "$(ep_node_region "$(ep_node_tag "$section")")" = "$1" ] && printf '%s\n' "$section"
	done
}

# Chinese label for a region bucket
ep_region_label() {
	case "$1" in
		hk) printf '香港' ;;
		tw) printf '台湾' ;;
		jp) printf '日本' ;;
		sg) printf '新加坡' ;;
		us) printf '美国' ;;
		uk) printf '英国' ;;
		de) printf '德国' ;;
		kr) printf '韩国' ;;
		ru) printf '俄罗斯' ;;
		*) printf '其他' ;;
	esac
}

