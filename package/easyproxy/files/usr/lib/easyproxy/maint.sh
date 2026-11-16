#!/bin/sh
# Maintenance helpers: configuration backup / restore / reset, rule-set
# refresh and check, a single "doctor" diagnostic and log rotation.
#
# Everything here is offline-safe: the CLI commands print what they did and
# return non-zero on failure, so they can be driven from the LuCI panel or
# from a cron job.

# --- default paths -----------------------------------------------------------
ep_backup_dir() {
	ep_get main backup_dir '/etc/easyproxy/backups'
}

ep_default_config() {
	ep_get main default_config "${EP_DEFAULT_CONFIG:-/usr/share/easyproxy/easyproxy.default}"
}

ep_log_max_bytes() {
	local max
	max="$(ep_get main log_max_bytes 1048576)"
	case "$max" in
		''|*[!0-9]*) max=1048576 ;;
	esac
	printf '%s' "$max"
}

# Size in bytes of a file; 0 when it does not exist
ep_file_size() {
	[ -f "$1" ] || { printf '0'; return 0; }
	wc -c < "$1" 2>/dev/null | tr -d ' \n'
}

# --- configuration backup ----------------------------------------------------
# Package the config file plus the local rule sets into one tarball. The
# archive holds relative paths only, so it restores on any firmware layout.
#   ep_config_backup [destination]
# Prints the archive path on success.
ep_config_backup() {
	local file="$1" dir stamp stage
	stamp="$(date +%Y%m%d-%H%M%S)"
	dir="$(ep_backup_dir)"
	[ -n "$file" ] || file="$dir/easyproxy-${stamp}.tar.gz"

	[ -r "$EP_CONFIG_FILE" ] || { echo "no config at $EP_CONFIG_FILE" >&2; return 1; }
	mkdir -p "$(dirname "$file")" 2>/dev/null || { echo "cannot create $(dirname "$file")" >&2; return 1; }
	stage="$(mktemp -d)" || { echo "cannot create a temporary directory" >&2; return 1; }
	mkdir -p "$stage/config" "$stage/ruleset" || { rm -rf "$stage"; return 1; }
	cp "$EP_CONFIG_FILE" "$stage/config/easyproxy" 2>/dev/null || {
		rm -rf "$stage"; echo "cannot read $EP_CONFIG_FILE" >&2; return 1
	}
	cp "$(ep_rule_set_dir)"/*.srs "$stage/ruleset/" 2>/dev/null
	tar czf "$file" -C "$stage" . 2>/dev/null || {
		rm -rf "$stage"; echo "cannot write archive $file" >&2; return 1
	}
	rm -rf "$stage"
	printf '%s\n' "$file"
}

# Restore a backup. The file being replaced is kept as .before-restore so a
# mistaken restore is itself reversible.
ep_config_restore() {
	local file="$1" stage
	[ -n "$file" ] || { echo "usage: easyproxy config restore <archive>" >&2; return 2; }
	[ -r "$file" ] || { echo "no such backup: $file" >&2; return 1; }

	stage="$(mktemp -d)" || { echo "cannot create a temporary directory" >&2; return 1; }
	if ! tar xzf "$file" -C "$stage" 2>/dev/null; then
		rm -rf "$stage"; echo "not a valid backup archive: $file" >&2; return 1
	fi
	if [ ! -f "$stage/config/easyproxy" ]; then
		rm -rf "$stage"; echo "archive has no config/easyproxy: $file" >&2; return 1
	fi

	mkdir -p "$(dirname "$EP_CONFIG_FILE")" 2>/dev/null
	cp -f "$EP_CONFIG_FILE" "$EP_CONFIG_FILE.before-restore" 2>/dev/null
	cp -f "$stage/config/easyproxy" "$EP_CONFIG_FILE" || {
		rm -rf "$stage"; echo "cannot write $EP_CONFIG_FILE" >&2; return 1
	}
	if [ -d "$stage/ruleset" ]; then
		mkdir -p "$(ep_rule_set_dir)" 2>/dev/null
		cp -f "$stage/ruleset/"*.srs "$(ep_rule_set_dir)/" 2>/dev/null
	fi
	rm -rf "$stage"
	printf '%s\n' "$EP_CONFIG_FILE"
}

# Put the shipped defaults back; the previous config is kept.
ep_config_reset() {
	local def
	def="$(ep_default_config)"
	[ -r "$def" ] || { echo "default config missing: $def" >&2; return 1; }
	mkdir -p "$(dirname "$EP_CONFIG_FILE")" 2>/dev/null
	cp -f "$EP_CONFIG_FILE" "$EP_CONFIG_FILE.before-reset" 2>/dev/null
	cp -f "$def" "$EP_CONFIG_FILE" || { echo "cannot write $EP_CONFIG_FILE" >&2; return 1; }
	printf '%s\n' "$EP_CONFIG_FILE"
}

# --- rule sets ---------------------------------------------------------------
# Download one rule set to "<file>.new", then move it into place. The current
# file is only replaced when the download really produced a usable file, so a
# dropped connection never leaves the router without a working CN rule.
ep_rule_set_refresh() {
	local url="$1" file="$2" tmp
	[ -n "$url" ] || return 1
	mkdir -p "$(dirname "$file")" 2>/dev/null || return 1
	tmp="$file.new"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --max-time 60 -o "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
	elif command -v wget >/dev/null 2>&1; then
		wget -q -T 60 -O "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
	else
		return 1
	fi
	[ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
	mv "$tmp" "$file" 2>/dev/null || { rm -f "$tmp"; return 1; }
	return 0
}

# Refresh both CN rule sets. Returns non-zero when either download failed; the
# previous files stay in place in that case.
ep_ruleset_update() {
	local dir geosite geoip failed=0
	dir="$(ep_rule_set_dir)"
	geosite="$(ep_get routing geosite_cn_url 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs')"
	geoip="$(ep_get routing geoip_cn_url 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs')"

	if ep_rule_set_refresh "$geosite" "$dir/geosite-cn.srs"; then
		printf 'geosite-cn.srs %s bytes\n' "$(ep_file_size "$dir/geosite-cn.srs")"
	else
		failed=$((failed + 1))
		printf 'geosite-cn.srs: download failed, previous file kept\n' >&2
	fi
	if ep_rule_set_refresh "$geoip" "$dir/geoip-cn.srs"; then
		printf 'geoip-cn.srs %s bytes\n' "$(ep_file_size "$dir/geoip-cn.srs")"
	else
		failed=$((failed + 1))
		printf 'geoip-cn.srs: download failed, previous file kept\n' >&2
	fi
	[ "$failed" -eq 0 ] || return 1
	printf 'rule sets updated in %s\n' "$dir"
	return 0
}

# Check the two rule sets really are sing-box binary rule sets, not an HTML
# error page or a truncated download.
ep_ruleset_verify() {
	local dir name file size magic ok=0 bad=0
	dir="$(ep_rule_set_dir)"
	for name in geosite-cn.srs geoip-cn.srs; do
		file="$dir/$name"
		if [ ! -f "$file" ]; then
			printf '[FAIL]  %-16s missing\n' "$name"
			bad=$((bad + 1))
			continue
		fi
		size="$(ep_file_size "$file")"
		if [ "$size" -eq 0 ]; then
			printf '[FAIL]  %-16s empty\n' "$name"
			bad=$((bad + 1))
			continue
		fi
		magic="$(head -c 3 "$file" 2>/dev/null)"
		if [ "$magic" != "SRS" ]; then
			printf '[FAIL]  %-16s %s bytes, magic is not SRS\n' "$name" "$size"
			bad=$((bad + 1))
			continue
		fi
		if [ "$size" -le 16 ]; then
			printf '[FAIL]  %-16s %s bytes, too small to be a rule set\n' "$name" "$size"
			bad=$((bad + 1))
			continue
		fi
		printf '[ok]    %-16s %s bytes\n' "$name" "$size"
		ok=$((ok + 1))
	done
	printf 'ruleset: %s ok, %s fail\n' "$ok" "$bad"
	[ "$bad" -eq 0 ]
}

# --- diagnostics -------------------------------------------------------------
# One pass over everything that can make proxying silently fail. Prints
# "<status>\t<check>\t<detail>" lines; returns non-zero when a check failed.
ep_doctor() {
	local engine binary bstate cfgstate rsstate rt pid up tstate policy
	local logsize maxlog ok ports listen_port transparent enabled bad=0
	bad=0

	ep_health_line ok version "EasyProxy ${EP_VERSION} (Stage ${EP_STAGE})"

	engine="$(ep_get main engine none)"
	ep_health_line ok engine "$(ep_engine_label "$engine") ($(ep_engine_stability "$engine"))"

	binary="$(ep_engine_binary "$engine")"
	bstate="$(ep_binary_state "$binary")"
	if [ "$bstate" = "available" ]; then
		ep_health_line ok binary "$binary $(ep_engine_version "$binary")"
	else
		ep_health_line fail binary "missing: ${binary:-none}"
		bad=1
	fi

	cfgstate="$(ep_config_state)"
	case "$cfgstate" in
		ok) ep_health_line ok config "$(ep_engine_config_path "$engine")" ;;
		invalid) ep_health_line fail config "engine rejects $(ep_engine_config_path "$engine")"; bad=1 ;;
		*) ep_health_line warn config "not generated yet (easyproxy config generate)" ;;
	esac

	rsstate="$(ep_rule_set_state)"
	if [ "$rsstate" = "ready" ]; then
		ep_health_line ok ruleset "$(ep_rule_set_dir) ($(ep_file_size "$(ep_rule_set_dir)/geosite-cn.srs") + $(ep_file_size "$(ep_rule_set_dir)/geoip-cn.srs") bytes)"
	else
		ep_health_line fail ruleset "missing under $(ep_rule_set_dir); routing stays direct (no proxy)"
		bad=1
	fi

	rt="$(ep_runtime_state)"
	if [ "$rt" = "running" ]; then
		pid="$(ep_pid)"
		up="$(ep_runtime_uptime)"
		ep_health_line ok runtime "running, pid $pid, up ${up}s"
	else
		ep_health_line warn runtime "stopped"
	fi

	listen_port="$(ep_get main listen_port 7890)"
	if [ "$(ep_port_listening "$listen_port")" = "1" ]; then
		ep_health_line ok listen "port $listen_port is listening"
	else
		ep_health_line warn listen "port $listen_port is not listening"
	fi

	transparent="$(ep_bool "$(ep_get transparent enabled 0)")"
	tstate="$(ep_transparent_state)"
	case "$tstate" in
		active) ep_health_line ok transparent "capture active on $(ep_transparent_ifaces)" ;;
		unsupported) ep_health_line warn transparent "nft not available; LAN traffic is not captured" ;;
		*)
			if [ "$transparent" = "1" ]; then
				ep_health_line warn transparent "enabled in UCI but not applied (easyproxy transparent apply)"
			else
				ep_health_line ok transparent "disabled (clients use the mixed port)"
			fi ;;
	esac

	policy="$(ep_ipv6_policy)"
	ep_health_line ok "ipv6" "policy=${policy}, state=$(ep_ipv6_state)"

	logsize="$(ep_file_size "$EP_LOG_FILE")"
	maxlog="$(ep_log_max_bytes)"
	if [ "$logsize" -gt "$maxlog" ]; then
		ep_health_line warn log "$EP_LOG_FILE is ${logsize} bytes (> ${maxlog}); run 'easyproxy log rotate'"
	else
		ep_health_line ok log "$EP_LOG_FILE is ${logsize} bytes"
	fi

	return "$bad"
}

# --- log ---------------------------------------------------------------------
# Rotate the log once it exceeds main.log_max_bytes (default 1 MiB). One
# generation is kept: easyproxy.log.1.
ep_log_rotate() {
	local file="$EP_LOG_FILE" max size
	max="$(ep_log_max_bytes)"
	size="$(ep_file_size "$file")"
	if [ "$size" -eq 0 ]; then
		printf 'no log at %s; nothing to rotate\n' "$file"
		return 0
	fi
	if [ "$size" -le "$max" ]; then
		printf 'log is %s bytes, below %s bytes; nothing to rotate\n' "$size" "$max"
		return 0
	fi
	mv -f "$file" "$file.1" 2>/dev/null || { echo "cannot rotate $file" >&2; return 1; }
	: > "$file" 2>/dev/null || true
	printf 'log rotated: %s bytes -> %s.1\n' "$size" "$file"
	return 0
}

# --- uninstall ---------------------------------------------------------------
# Remove only what EasyProxy itself installed: its two nftables tables and its
# policy-routing rule. Nothing else on the router is touched, so the stock
# ImmortalWrt network configuration survives an uninstall.
ep_uninstall_clean() {
	local nft_note
	if command -v "$EP_NFT_BIN" >/dev/null 2>&1; then
		ep_transparent_remove
		nft_note="nft: EasyProxy own tables (ip/ip6 easyproxy) removed"
	else
		nft_note="nft: not installed; no EasyProxy own rules to remove"
	fi
	rm -f /tmp/luci-indexcache* 2>/dev/null
	printf '%s\n' "$nft_note"
	printf 'firewall: stock ImmortalWrt rules untouched (EasyProxy only ever adds its own table and fwmark rule)\n'
	return 0
}
