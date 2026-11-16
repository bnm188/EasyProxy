#!/usr/bin/env sh
# One-line uninstaller for EasyProxy.
#
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
#   sh uninstall.sh [--purge|--keep-config] [--keep-kernels] [--no-backup]
#
# Order matters and is deliberate: the nftables capture is removed first, then
# the service is stopped, then the packages go away. Removing the package while
# a tproxy table still points at a dead listener would black-hole LAN traffic.
# Safe to re-run; on a host where nothing is installed it exits 0.
#
# What happens to the user's own data is the caller's choice:
#   default          keep /etc/config/easyproxy and /etc/easyproxy, take a backup
#   --purge          delete them too (the backup is still taken first)
#   --keep-config    keep them (same as the default, spelled out)
#   --no-backup      do not write a backup archive
#   --keep-kernels   leave sing-box/dae installed (they may run other things)
#
# Kernels are only removed when this installer put them there: it records the
# path it wrote in /etc/easyproxy/owned/<kernel>, and a kernel the user installed
# themselves has no such record and is never touched.

set -eu

INIT="${EP_INIT:-/etc/init.d/easyproxy}"
BIN="${EP_BIN:-/usr/sbin/easyproxy}"
RPCD="${EP_RPCD:-/etc/init.d/rpcd}"
CFG="${EP_CFG:-/etc/config/easyproxy}"
STATE="${EP_STATE_DIR:-/etc/easyproxy}"
LUCI_INDEX="${EP_LUCI_CACHE:-/tmp/luci-indexcache}"
BACKUP_DIR="${EP_BACKUP_DIR:-/root}"
DAE_DATA="${EP_DAE_DATA:-/usr/share/dae}"
KERNELS='sing-box dae'

PURGE=0
BACKUP=1
KEEP_KERNELS=0

usage() {
	cat <<'EOF'
EasyProxy uninstaller

  uninstall.sh                 remove the packages, keep the config, write a backup
  uninstall.sh --purge         also delete /etc/config/easyproxy and /etc/easyproxy
  uninstall.sh --keep-config   keep them (the default)
  uninstall.sh --no-backup     do not write the config backup
  uninstall.sh --keep-kernels  leave sing-box and dae installed
  uninstall.sh --help          this text

Environment overrides (mostly for testing): EP_INIT, EP_BIN, EP_RPCD, EP_CFG,
EP_STATE_DIR, EP_LUCI_CACHE, EP_BACKUP_DIR, EP_DAE_DATA.
EOF
}

info() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--purge) PURGE=1 ;;
		--keep-config) PURGE=0 ;;
		--no-backup) BACKUP=0 ;;
		--keep-kernels) KEEP_KERNELS=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
	shift
done

# 0. Keep a copy of what the user configured before anything is touched.
backup_path=""
if [ "$BACKUP" = 1 ]; then
	mkdir -p "$BACKUP_DIR" 2>/dev/null || true
	backup_path="$BACKUP_DIR/easyproxy-backup-$(date +%Y%m%d-%H%M%S 2>/dev/null || printf '%s' now).tar.gz"
	BK_ARGS=""
	if [ -e "$CFG" ]; then
		BK_ARGS="${CFG#/}"
	fi
	if [ -d "$STATE" ]; then
		BK_ARGS="$BK_ARGS ${STATE#/}"
	fi
	if ! command -v tar >/dev/null 2>&1; then
		backup_path=""
		info "backup: this firmware has no tar, backup skipped"
	elif [ -z "$BK_ARGS" ]; then
		backup_path=""
		info "backup: nothing to back up"
	elif tar -czf "$backup_path" -C / $BK_ARGS 2>/dev/null; then
		info "backup: $backup_path"
	else
		rm -f "$backup_path"
		backup_path=""
		info "backup: could not write $backup_path"
	fi
fi

# 1. Stop capturing before anything else disappears. `uninstall-clean` only
# removes EasyProxy's own nftables tables and fwmark rule; stock ImmortalWrt
# network configuration is never touched.
if [ -x "$BIN" ]; then
	"$BIN" uninstall-clean >/dev/null 2>&1 || "$BIN" transparent remove >/dev/null 2>&1 || true
fi

# 2. Stop and unregister the service.
if [ -x "$INIT" ]; then
	"$INIT" stop >/dev/null 2>&1 || true
	"$INIT" disable >/dev/null 2>&1 || true
fi

# 3. Remove the package with whatever this firmware uses.
if command -v opkg >/dev/null 2>&1; then
	opkg remove easyproxy >/dev/null 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
	apk del easyproxy >/dev/null 2>&1 || true
fi

# 4. If the files are still there (no package manager, or a manually extracted
# rootfs install), remove them by path.
if [ -e /usr/sbin/easyproxy ] || [ -d /usr/lib/easyproxy ]; then
	rm -rf /usr/lib/easyproxy /usr/sbin/easyproxy \
		/etc/init.d/easyproxy \
		/www/luci-static/resources/view/easyproxy \
		/usr/share/luci/menu.d/luci-app-easyproxy.json \
		/usr/share/rpcd/acl.d/luci-app-easyproxy.json \
		/usr/share/easyproxy 2>/dev/null || true
fi

# 5. The kernels, but only the ones this installer put there.
if [ "$KEEP_KERNELS" = 0 ]; then
	for k in $KERNELS; do
		[ -f "$STATE/owned/$k" ] || continue
		owned_bin="$(cat "$STATE/owned/$k" 2>/dev/null || true)"
		if command -v opkg >/dev/null 2>&1 && opkg list-installed "$k" >/dev/null 2>&1; then
			opkg remove "$k" >/dev/null 2>&1 || true
		fi
		if [ -n "$owned_bin" ] && [ -f "$owned_bin" ]; then
			rm -f "$owned_bin" 2>/dev/null || true
		fi
		info "kernel removed: $k"
	done
	if [ -f "$STATE/owned/dae" ] && [ -d "$DAE_DATA" ]; then
		rm -rf "$DAE_DATA" 2>/dev/null || true
		info "kernel assets removed: $DAE_DATA"
	fi
else
	info "kernels kept (--keep-kernels)"
fi

# 6. Optional: drop configuration and runtime state.
if [ "$PURGE" -eq 1 ]; then
	rm -rf "$CFG" "$STATE" 2>/dev/null || true
fi

if [ -x "$RPCD" ]; then
	"$RPCD" restart >/dev/null 2>&1 || true
fi
rm -f "$LUCI_INDEX"* 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
	info "EasyProxy removed, including its configuration and runtime state."
else
	info "EasyProxy removed. $CFG and $STATE were kept; re-run with --purge to drop them too."
fi
if [ -n "$backup_path" ]; then
	info "Restore with: tar -xzf $backup_path -C /"
fi
