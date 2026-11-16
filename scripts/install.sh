#!/bin/sh
# One-line installer for EasyProxy.
#
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh
#   sh install.sh [--apk|--ipk|--rootfs|--no-engine]
#
# Picks the right artifact from the latest GitHub release, installs it with the
# package manager this firmware actually has, installs the proxy kernel, enables
# the service and refreshes the LuCI menu. Safe to re-run: it always installs
# the newest release.

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
NO_ENGINE=0
ENGINE_FAILED=0
ENGINE_VER="${EP_ENGINE_VER:-1.10.7}"
ENGINE_BASE="${EP_ENGINE_BASE:-https://github.com/SagerNet/sing-box/releases/download/v${ENGINE_VER}}"

usage() {
	cat <<'EOF'
EasyProxy installer

  install.sh              detect opkg/apk, install the matching release asset
                          and install the sing-box kernel for this host
  install.sh --apk        force the .apk asset (apk-based firmware)
  install.sh --ipk        force the .ipk asset (opkg-based firmware)
  install.sh --rootfs     skip the package manager, extract the rootfs archive at /
  install.sh --no-engine  install EasyProxy only, skip the sing-box kernel
  install.sh --help       this text

The kernel is not inside the package: one ipk serves every architecture, so an
amd64 binary in `_all.ipk` would be installed on ARM routers too. It is fetched
from the official sing-box release for this host's architecture, checked against
a pinned sha256 and only then moved into <root>/usr/bin/sing-box.

Environment overrides (mostly for testing): EP_REPO, EP_BRANCH, EP_API_URL,
EP_RAW_BASE, EP_TMP, EP_INIT, EP_BIN, EP_RPCD, EP_LUCI_CACHE, EP_ROOT,
EP_ENGINE_VER, EP_ENGINE_BASE, EP_ENGINE_SHA, EP_ENGINE_BIN.
EOF
}

info() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--apk) MODE=apk ;;
		--ipk) MODE=ipk ;;
		--rootfs) MODE=rootfs ;;
		--no-engine) NO_ENGINE=1 ;;
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

# Which ipk flavour this host can install. The release ships `_all.ipk` plus one
# stamp per target; an opkg that refuses `Architecture: all` needs the exact one.
# The answer comes from opkg itself (`opkg print-architecture`), never from a
# guess about uname, because the package manager is what will refuse the file.
host_ipk_arch() {
	local a
	if command -v opkg >/dev/null 2>&1; then
		a="$(opkg print-architecture 2>/dev/null \
			| awk 'NF >= 2 && $1 != "all" && $1 != "noarch" { print $1; exit }')"
		if [ -n "$a" ]; then
			printf '%s' "$a"
			return 0
		fi
	fi
	case "$(uname -m 2>/dev/null)" in
		x86_64|amd64)   printf '%s' x86_64 ;;
		aarch64|arm64)  printf '%s' aarch64 ;;
		armv7l|armv7)   printf '%s' armv7 ;;
		*)              printf '%s' '' ;;
	esac
}

# Whether this opkg accepts `Architecture: all`. Asked, not assumed: some builds
# only accept their own target architecture.
opkg_accepts_all() {
	command -v opkg >/dev/null 2>&1 || return 1
	opkg print-architecture 2>/dev/null | awk '{ print $1 }' | grep -qx 'all'
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
	local pattern url ver rel arch
	pattern="$1"
	arch="${2:-}"
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
		'\.ipk$')
			if [ -n "$arch" ]; then
				printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/easyproxy_${ver}-${rel}_${arch}.ipk"
			else
				printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/easyproxy_${ver}-${rel}_all.ipk"
			fi ;;
		'\.tar\.gz$') printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/easyproxy-${ver}-rootfs.tar.gz" ;;
		*) return 1 ;;
	esac
}

asset_sums_url() {
	local url ver rel
	url="$(asset_from_api 'SHA256SUMS' || true)"
	if [ -n "$url" ]; then
		printf '%s' "$url"
		return 0
	fi
	ver="$(fallback_version || true)"
	[ -n "$ver" ] || return 1
	rel="$(fallback_release || true)"
	rel="${rel:-1}"
	printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/SHA256SUMS"
}

# A download that is not byte-for-byte what the release published is never
# installed: a truncated file or a CDN error page would otherwise be handed to
# opkg/apk as a package.
verify_download() {
	local file url sums want got
	file="$1"
	url="$2"
	if ! command -v sha256sum >/dev/null 2>&1; then
		info "sha256: skipped, this firmware has no sha256sum"
		return 0
	fi
	sums="$(asset_sums_url || true)"
	if [ -z "$sums" ]; then
		info "sha256: this release publishes no SHA256SUMS, cannot verify $(basename "$url")"
		return 0
	fi
	if ! fetch_file "$sums" "$work/SHA256SUMS" 2>/dev/null; then
		info "sha256: cannot download SHA256SUMS, cannot verify $(basename "$url")"
		return 0
	fi
	want="$(awk -v n="$(basename "$url")" '$2 == n || $2 == "./" n { print $1 }' "$work/SHA256SUMS" | head -1)"
	[ -n "$want" ] || die "the release has no checksum for $(basename "$url"); refusing to install an unverified package"
	got="$(sha256sum "$file" | awk '{ print $1 }')"
	[ "$want" = "$got" ] || die "checksum mismatch for $(basename "$url"): expected $want, got $got (invalid download, nothing installed)"
	info "sha256 ok: $(basename "$url")"
}

# Cheap format check, so an HTML error page is stopped even when the checksum
# list itself could not be fetched.
check_package_file() {
	case "$1" in
		*.ipk) dd if="$2" bs=1 count=8 2>/dev/null | grep -q '!<arch>' \
			|| die "$(basename "$1") is not an ipk archive (invalid download, nothing installed)" ;;
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

# --- proxy kernel ---------------------------------------------------------
# One ipk serves every architecture, so the kernel cannot live inside it: an
# amd64 binary in `_all.ipk` would be installed on ARM routers too. It is
# fetched per host, matched to this host's own architecture, pinned by sha256,
# and only the binary is kept - no rootfs is unpacked over the firmware.
engine_arch() {
	local a
	a="$(host_ipk_arch)"
	case "$a" in
		x86_64|amd64) printf '%s' amd64; return 0 ;;
		aarch64*) printf '%s' arm64; return 0 ;;
		armv7*|armv6*) printf '%s' armv7; return 0 ;;
	esac
	case "$(uname -m 2>/dev/null)" in
		x86_64|amd64) printf '%s' amd64 ;;
		aarch64|arm64) printf '%s' arm64 ;;
		armv7l|armv7) printf '%s' armv7 ;;
		*) printf '%s' '' ;;
	esac
}

engine_sha() {
	case "$1" in
		amd64) printf '%s' '1951a0785c8b4e1e21e0640227a49528ca772aec3d680061652e3d6b687e00fe' ;;
		arm64) printf '%s' '15b43a0a50b4e6962aca819d4f3055aaac75ca7481350d4aaebe93ed06b7af49' ;;
		armv7) printf '%s' '691882d609c877f97bc8d6f8645b97d12de81b6f7b89651df66489ef11b4c5d0' ;;
		*) printf '%s' '' ;;
	esac
}

engine_bin() { printf '%s' "${EP_ENGINE_BIN:-$ROOT/usr/bin/sing-box}"; }

engine_configure() {
	local bin
	bin="$(engine_bin)"
	command -v uci >/dev/null 2>&1 || return 0
	uci -q set easyproxy.main.engine='sing-box' 2>/dev/null || true
	uci -q set easyproxy.sing_box.binary="$bin" 2>/dev/null || true
	uci -q commit easyproxy 2>/dev/null || true
	info "engine: uci points at $bin"
}

ensure_engine() {
	local bin arch tarurl want got src
	bin="$(engine_bin)"
	if [ "$NO_ENGINE" = 1 ]; then
		info "engine: skipped (--no-engine)"
		return 0
	fi
	if [ -x "$bin" ]; then
		info "engine: already present ($bin)"
		engine_configure
		return 0
	fi
	if command -v uci >/dev/null 2>&1; then
		src="$(uci -q get easyproxy.sing_box.binary 2>/dev/null || true)"
		if [ -n "$src" ] && [ -x "$src" ]; then
			info "engine: already present ($src)"
			return 0
		fi
	fi
	arch="$(engine_arch)"
	if [ -z "$arch" ]; then
		info "engine: install failed: $(uname -m 2>/dev/null) has no official sing-box build"
		ENGINE_FAILED=1
		return 1
	fi
	tarurl="${ENGINE_BASE}/sing-box-${ENGINE_VER}-linux-${arch}.tar.gz"
	info "engine: downloading $(basename "$tarurl")"
	if ! fetch_file "$tarurl" "$work/engine.tar.gz"; then
		info "engine: install failed: cannot download $(basename "$tarurl")"
		ENGINE_FAILED=1
		return 1
	fi
	want="${EP_ENGINE_SHA:-$(engine_sha "$arch")}"
	if [ -n "$want" ] && command -v sha256sum >/dev/null 2>&1; then
		got="$(sha256sum "$work/engine.tar.gz" | awk '{ print $1 }')"
		if [ "$want" != "$got" ]; then
			rm -f "$work/engine.tar.gz"
			info "engine: install failed: checksum mismatch for $(basename "$tarurl"): expected $want, got $got (nothing installed)"
			ENGINE_FAILED=1
			return 1
		fi
		info "engine sha256 ok: $(basename "$tarurl")"
	else
		info "engine: no pinned sha256 for linux-$arch, relying on archive and ELF checks"
	fi
	mkdir -p "$work/engine"
	if ! tar -xzf "$work/engine.tar.gz" -C "$work/engine"; then
		info "engine: install failed: cannot extract $(basename "$tarurl")"
		ENGINE_FAILED=1
		return 1
	fi
	src="$(find "$work/engine" -type f -name sing-box 2>/dev/null | head -1)"
	if [ -z "$src" ]; then
		info "engine: install failed: the archive carries no sing-box binary"
		ENGINE_FAILED=1
		return 1
	fi
	if ! dd if="$src" bs=1 count=4 2>/dev/null | grep -q 'ELF'; then
		info "engine: install failed: the extracted file is not an ELF binary (nothing installed)"
		ENGINE_FAILED=1
		return 1
	fi
	mkdir -p "$(dirname "$bin")"
	cp "$src" "$bin" || { info "engine: install failed: cannot write $bin"; ENGINE_FAILED=1; return 1; }
	chmod 755 "$bin"
	info "engine: installed $bin"
	"$bin" version 2>/dev/null | head -1 || true
	engine_configure
	return 0
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
		arch=""
		if [ "$MODE" = "apk" ]; then
			url="$(asset_url '\.apk$')" \
				|| die "cannot resolve the apk download URL (release API unreachable and no version in the Makefile)"
		else
			# The release carries one ipk per target next to `_all.ipk`. The arch is
			# whatever opkg itself reports; `_all.ipk` is only used when this opkg
			# actually accepts `Architecture: all`.
			arch="$(host_ipk_arch)"
			accepts_all=0
			if opkg_accepts_all; then
				accepts_all=1
			fi
			[ -n "$arch" ] && url="$(asset_from_api "_${arch}\.ipk$" || true)"
			if [ -z "${url:-}" ] && [ "$accepts_all" = 1 ]; then
				url="$(asset_from_api '_all\.ipk$' || true)"
			fi
			if [ -z "${url:-}" ]; then
				if [ "$accepts_all" != 1 ]; then
					die "no installable ipk for ${arch:-unknown}: this opkg does not accept 'all' and the release has no _${arch}.ipk (nothing was installed)"
				fi
				url="$(asset_url '\.ipk$' "$arch")" \
					|| die "cannot resolve the ipk download URL (release API unreachable and no version in the Makefile)"
			fi
		fi
		file="$work/$(basename "$url")"
		info "downloading $(basename "$url")"
		if ! fetch_file "$url" "$file"; then
			if [ "$MODE" = "ipk" ] && [ "$accepts_all" = 1 ]; then
				alt="$(asset_from_api '_all\.ipk$' || true)"
				[ -n "$alt" ] || alt="$(asset_url '\.ipk$' 2>/dev/null || true)"
				[ -n "$alt" ] || die "download failed: $url"
				info "architecture-specific package unavailable, retrying $(basename "$alt")"
				url="$alt"
				file="$work/$(basename "$url")"
				fetch_file "$url" "$file" || die "download failed: $url"
			else
				die "download failed: $url"
			fi
		fi
		check_package_file "$url" "$file"
		verify_download "$file" "$url"
		info "installing with $(detect_pm || printf '%s' 'package manager')"
		install_pkg "$(detect_pm || printf '%s' opkg)" "$file"
		;;
	rootfs)
		url="$(asset_url '\.tar\.gz$')" \
			|| die "cannot resolve the rootfs archive URL (release API unreachable and no version in the Makefile)"
		file="$work/$(basename "$url")"
		info "downloading $(basename "$url")"
		fetch_file "$url" "$file" || die "download failed: $url"
		verify_download "$file" "$url"
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

ensure_engine

if [ "$ENGINE_FAILED" != 0 ]; then
	die "EasyProxy is installed but the sing-box kernel is not ($(engine_bin)).
The package alone cannot start traffic: re-run this installer, or place a
static binary yourself and set easyproxy.sing_box.binary to its path."
fi

cat <<'EOF'

Next steps:
  1. add at least one node:
       uci add easyproxy node && uci set easyproxy.@node[-1].name='hk-01' ...
  2. generate the config (needs network on first run):
       easyproxy config generate
  3. switch it on:
       uci set easyproxy.main.enabled='1' && uci commit easyproxy
       /etc/init.d/easyproxy start
  4. open LuCI - Services - EasyProxy

Uninstall: wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
EOF
