#!/bin/sh
# One-line installer for EasyProxy.
#
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh
#   sh install.sh [--apk|--ipk|--rootfs]
#
# Picks the right artifact from the latest GitHub release, installs it with the
# package manager this firmware actually has, enables the service and refreshes
# the LuCI menu. Safe to re-run: it always installs the newest release.

set -eu

REPO="${EP_REPO:-bnm188/EasyProxy}"
BRANCH="${EP_BRANCH:-main}"
TMP="${EP_TMP:-/tmp}"
API="${EP_API_URL:-https://api.github.com/repos/${REPO}/releases/latest}"
RAW="${EP_RAW_BASE:-https://raw.githubusercontent.com/${REPO}/${BRANCH}}"

INIT="${EP_INIT:-/etc/init.d/easyproxy}"
BIN="${EP_BIN:-/usr/sbin/easyproxy}"
RPCD="${EP_RPCD:-/etc/init.d/rpcd}"
LUCI_INDEX="${EP_LUCI_CACHE:-/tmp/luci-indexcache}"
ROOT="${EP_ROOT:-/}"

MODE="${EP_MODE:-}"

usage() {
	cat <<'EOF'
EasyProxy installer

  install.sh              detect opkg/apk and install the matching release asset
  install.sh --apk        force the .apk asset (apk-based firmware)
  install.sh --ipk        force the .ipk asset (opkg-based firmware)
  install.sh --rootfs     skip the package manager, extract the rootfs archive at /
  install.sh --help       this text

Environment overrides (mostly for testing): EP_REPO, EP_BRANCH, EP_API_URL,
EP_RAW_BASE, EP_TMP, EP_INIT, EP_BIN, EP_RPCD, EP_LUCI_CACHE, EP_ROOT.
EOF
}

info() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--apk) MODE=apk ;;
		--ipk) MODE=ipk ;;
		--rootfs) MODE=rootfs ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
	shift
done

# --- fetch helpers ---------------------------------------------------------
fetch_text() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$1"
	else
		return 1
	fi
}

fetch_file() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		return 1
	fi
}

# --- what can this firmware install? -------------------------------------
detect_pm() {
	if [ -n "${EP_PM:-}" ]; then
		printf '%s' "$EP_PM"
		return 0
	fi
	if command -v opkg >/dev/null 2>&1; then
		printf '%s' 'opkg'
	elif command -v apk >/dev/null 2>&1; then
		printf '%s' 'apk'
	else
		return 1
	fi
}

# --- release asset --------------------------------------------------------
# Ask the API first: asset names carry the version, so guessing them is
# fragile. If the API is unreachable (common behind a slow link), fall back to
# the version recorded in the repository Makefile.
asset_from_api() {
	fetch_text "$API" 2>/dev/null \
		| tr '{' '\n' \
		| grep -o 'https://[^"]*' \
		| grep -E "$1" \
		| head -1
}

fallback_version() {
	fetch_text "$RAW/package/easyproxy/Makefile" 2>/dev/null \
		| sed -n 's/^PKG_VERSION:=//p' \
		| head -1
}

fallback_release() {
	fetch_text "$RAW/package/easyproxy/Makefile" 2>/dev/null \
		| sed -n 's/^PKG_RELEASE:=//p' \
		| head -1
}

asset_url() {
	local pattern url ver rel
	pattern="$1"
	url="$(asset_from_api "$pattern" || true)"
	if [ -n "$url" ]; then
		printf '%s' "$url"
		return 0
	fi
	ver="$(fallback_version || true)"
	[ -n "$ver" ] || return 1
	rel="$(fallback_release || true)"
	rel="${rel:-1}"
	case "$pattern" in
		'\.apk$') printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/easyproxy-${ver}-r${rel}.apk" ;;
		'\.ipk$') printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/easyproxy_${ver}-${rel}_all.ipk" ;;
		'\.tar\.gz$') printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/easyproxy-${ver}-rootfs.tar.gz" ;;
		*) return 1 ;;
	esac
}

install_pkg() {
	local pm file
	pm="$1"
	file="$2"
	case "$pm" in
		opkg) opkg install "$file" ;;
		apk) apk add --allow-untrusted "$file" ;;
		*) die "no package manager matched ($pm)" ;;
	esac
}

# --- run ------------------------------------------------------------------
if [ -z "$MODE" ]; then
	pm="$(detect_pm)" || die "found neither opkg nor apk; this firmware has no supported package manager.
Use: sh install.sh --rootfs  (extracts the archive at / without a package manager)"
	case "$pm" in
		opkg) MODE=ipk ;;
		apk) MODE=apk ;;
	esac
fi

mkdir -p "$TMP"
work="$(mktemp -d "$TMP/easyproxy.XXXXXX")"
trap 'rm -rf "$work"' EXIT

case "$MODE" in
	apk|ipk)
		pattern='\.apk$'
		[ "$MODE" = "ipk" ] && pattern='\.ipk$'
		url="$(asset_url "$pattern")" \
			|| die "cannot resolve the $MODE download URL (release API unreachable and no version in the Makefile)"
		file="$work/$(basename "$url")"
		info "downloading $(basename "$url")"
		fetch_file "$url" "$file" || die "download failed: $url"
		info "installing with $(detect_pm || printf '%s' 'package manager')"
		install_pkg "$(detect_pm || printf '%s' opkg)" "$file"
		;;
	rootfs)
		url="$(asset_url '\.tar\.gz$')" \
			|| die "cannot resolve the rootfs archive URL (release API unreachable and no version in the Makefile)"
		file="$work/$(basename "$url")"
		info "downloading $(basename "$url")"
		fetch_file "$url" "$file" || die "download failed: $url"
		info "extracting at $ROOT (no package manager involved)"
		tar -xzf "$file" -C "$ROOT" || die "cannot extract $file at $ROOT"
		chmod 755 "$ROOT/usr/sbin/easyproxy" "$ROOT/etc/init.d/easyproxy" 2>/dev/null || true
		;;
	*)
		die "unknown mode: $MODE"
		;;
esac

# --- post install ---------------------------------------------------------
if [ -x "$INIT" ]; then
	"$INIT" enable >/dev/null 2>&1 || true
fi
if [ -x "$RPCD" ]; then
	"$RPCD" restart >/dev/null 2>&1 || true
fi
rm -f "$LUCI_INDEX"* 2>/dev/null || true

info ""
if [ -x "$BIN" ]; then
	info "installed: $("$BIN" status 2>/dev/null | head -3 || true)"
else
	info "installed, but $BIN is not executable; check the package layout"
fi

cat <<'EOF'

Next steps:
  1. install a proxy engine (sing-box) and point EasyProxy at it:
       uci set easyproxy.main.engine='sing-box'
  2. add at least one node:
       uci add easyproxy node && uci set easyproxy.@node[-1].name='hk-01' ...
  3. generate the config (needs network on first run):
       easyproxy config generate
  4. switch it on:
       uci set easyproxy.main.enabled='1' && uci commit easyproxy
       /etc/init.d/easyproxy start
  5. open LuCI - Services - EasyProxy

Uninstall: wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
EOF
