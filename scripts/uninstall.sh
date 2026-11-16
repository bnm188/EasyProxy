#!/bin/sh
# One-line uninstaller for EasyProxy.
#
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
#   sh uninstall.sh [--purge]
#
# Order matters and is deliberate: the nftables capture is removed first, then
# the service is stopped, then the package goes away. Removing the package while
# a tproxy table still points at a dead listener would black-hole LAN traffic.
# Safe to re-run; on a host where nothing is installed it exits 0.

set -eu

INIT="${EP_INIT:-/etc/init.d/easyproxy}"
BIN="${EP_BIN:-/usr/sbin/easyproxy}"
RPCD="${EP_RPCD:-/etc/init.d/rpcd}"
CFG="${EP_CFG:-/etc/config/easyproxy}"
STATE="${EP_STATE_DIR:-/etc/easyproxy}"
LUCI_INDEX="${EP_LUCI_CACHE:-/tmp/luci-indexcache}"

PURGE=0

usage() {
	cat <<'EOF'
EasyProxy uninstaller

  uninstall.sh            remove the package, keep /etc/config/easyproxy
  uninstall.sh --purge    also delete the config and /etc/easyproxy (rules, logs)
  uninstall.sh --help     this text

Environment overrides (mostly for testing): EP_INIT, EP_BIN, EP_RPCD, EP_CFG,
EP_STATE_DIR, EP_LUCI_CACHE.
EOF
}

info() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--purge) PURGE=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
	shift
done

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

# 5. Optional: drop configuration and runtime state.
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
