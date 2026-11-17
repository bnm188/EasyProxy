#!/bin/sh
# One-line installer, upgrader and status report for EasyProxy.
#
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/install.sh | sh
#   sh install.sh [install] [--apk|--ipk|--rootfs|--no-sing-box|--no-dae|--no-engine]
#   sh install.sh upgrade [--only package|sing-box|dae]
#   sh install.sh status
#
# Three components are managed independently and can be upgraded one by one:
#
#   easyproxy   the CLI, the ten-page LuCI panel, UCI defaults, nftables capture
#   sing-box    the primary proxy kernel (official SagerNet build for this arch)
#   dae         the second proxy kernel (official daeuniverse build for this arch)
#
# Nothing is installed before its sha256 has been checked: the package comes
# from this repository's release with a SHA256SUMS entry, the kernels either
# come from the release's own kernel ipk (also covered by SHA256SUMS) or, when
# this architecture has no kernel ipk, from the pinned official archive whose
# sha256 is compiled into this file. An ipk is additionally rejected unless it
# starts with the ar magic, so a truncated file or a CDN error page can never
# reach opkg.
#
# This script never writes proxy policy: it installs binaries and points UCI at
# them. china_policy, fail_closed, the intranet bypass and the split rules stay
# exactly as the package ships them.

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
STATE="${EP_STATE_DIR:-/etc/easyproxy}"

SING_BOX_VER="${EP_SING_BOX_VER:-1.14.4}"
SING_BOX_BASE="${EP_SING_BOX_BASE:-https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VER}}"
DAE_VER="${EP_DAE_VER:-2.1.2}"
DAE_BASE="${EP_DAE_BASE:-https://github.com/daeuniverse/dae/releases/download/v${DAE_VER}}"

ACTION=install
MODE="${EP_MODE:-}"
NO_SING_BOX=0
NO_DAE=0
ONLY=""
KERNELS='sing-box dae'
SING_BOX_TARGET="$SING_BOX_VER"
DAE_TARGET="$DAE_VER"

usage() {
	cat <<'EOF'
EasyProxy installer

  install.sh                 detect opkg/apk, install the matching release asset,
                             then install the sing-box and dae kernels for this host
  install.sh --apk           force the .apk asset (apk-based firmware)
  install.sh --ipk           force the .ipk asset (opkg-based firmware)
  install.sh --rootfs        skip the package manager, extract the rootfs archive at /
  install.sh --no-sing-box   install EasyProxy and dae only
  install.sh --no-dae        install EasyProxy and sing-box only
  install.sh --no-engine     install EasyProxy only
  install.sh upgrade         compare all three components with the newest release,
                             print the version changes and upgrade the ones that differ
  install.sh upgrade --only sing-box|dae|package
                             upgrade a single component
  install.sh status          print the installed version of each component
  install.sh --help          this text

The kernels are not inside the package: one ipk serves every architecture, so an
x86_64 binary in `_all.ipk` would be installed on ARM routers too. They are
fetched per host, matched to this host's own architecture, pinned by sha256, and
only the payload is kept - no rootfs is unpacked over the firmware.

Environment overrides (mostly for testing): EP_REPO, EP_BRANCH, EP_API_URL,
EP_RAW_BASE, EP_TMP, EP_INIT, EP_BIN, EP_RPCD, EP_LUCI_CACHE, EP_ROOT,
EP_STATE_DIR, EP_SING_BOX_VER, EP_SING_BOX_BASE, EP_SING_BOX_SHA,
EP_SING_BOX_BIN, EP_DAE_VER, EP_DAE_BASE, EP_DAE_SHA, EP_DAE_BIN.
EOF
}

info() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		install) ACTION=install ;;
		upgrade) ACTION=upgrade ;;
		status) ACTION=status ;;
		--apk) MODE=apk ;;
		--ipk) MODE=ipk ;;
		--rootfs) MODE=rootfs ;;
		--no-sing-box) NO_SING_BOX=1 ;;
		--no-dae) NO_DAE=1 ;;
		--no-engine) NO_SING_BOX=1; NO_DAE=1 ;;
		--only)
			[ $# -ge 2 ] || die "--only needs a component: package, sing-box or dae"
			ONLY="$2"; shift ;;
		--only=*) ONLY="${1#--only=}" ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
	shift
done

case "$ONLY" in
	''|package|sing-box|dae) : ;;
	*) die "--only accepts package, sing-box or dae (got $ONLY)" ;;
esac

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

sha256_of() {
	command -v sha256sum >/dev/null 2>&1 || return 1
	sha256sum "$1" | awk '{ print $1 }'
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
		# Some firmware answer `print-architecture` with a placeholder line that
		# is literally "arch" ahead of the real target (Kwrt does), so the first
		# line is not trustworthy. Drop the placeholders, then prefer the entry
		# that agrees with uname instead of taking whatever came first.
		a="$(opkg print-architecture 2>/dev/null | awk '{ print $1 }' \
			| grep -vx -e 'arch' -e 'all' -e 'noarch' || true)"
		case "$(uname -m 2>/dev/null)" in
			x86_64|amd64)  a="$(printf '%s\n' "$a" | grep -m1 -E 'x86_64|amd64|corei' || true)" ;;
			aarch64|arm64) a="$(printf '%s\n' "$a" | grep -m1 -E 'aarch64|arm64' || true)" ;;
			armv7l|armv7)  a="$(printf '%s\n' "$a" | grep -m1 -E 'armv7|arm_cortex' || true)" ;;
		esac
		if [ -z "$a" ]; then
			a="$(opkg print-architecture 2>/dev/null | awk '{ print $1 }' \
				| grep -vx -e 'arch' -e 'all' -e 'noarch' | head -1 || true)"
		fi
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

# Whether this opkg has the --force-architecture option at all. Kwrt 25.12's
# opkg does not, and calling it there aborts the install with a usage dump, so
# the option is probed instead of assumed.
opkg_supports_force_arch() {
	command -v opkg >/dev/null 2>&1 || return 1
	opkg 2>&1 </dev/null | grep -q -- '--force-architecture'
}

# Whether this opkg accepts `Architecture: all`. Asked, not assumed: some builds
# only accept their own target architecture.
opkg_accepts_all() {
	command -v opkg >/dev/null 2>&1 || return 1
	opkg print-architecture 2>/dev/null | awk '{ print $1 }' | grep -qx 'all'
}

# x86_64 / aarch64 / armv7 - the three families both kernels publish for.
host_family() {
	local a
	a="$(host_ipk_arch)"
	case "$a" in
		x86_64|amd64) printf '%s' x86_64; return 0 ;;
		aarch64*)     printf '%s' aarch64; return 0 ;;
		armv7*|armv6*) printf '%s' armv7; return 0 ;;
	esac
	case "$(uname -m 2>/dev/null)" in
		x86_64|amd64)  printf '%s' x86_64 ;;
		aarch64|arm64) printf '%s' aarch64 ;;
		armv7l|armv7)  printf '%s' armv7 ;;
		*)             printf '%s' '' ;;
	esac
}

# The Architecture string stamped into the kernel ipks this repository builds.
kernel_ipk_arch() {
	case "$(host_family)" in
		x86_64)  printf '%s' x86_64 ;;
		aarch64) printf '%s' aarch64_cortex-a53 ;;
		armv7)   printf '%s' arm_cortex-a7_neon-vfpv4 ;;
		*)       printf '%s' '' ;;
	esac
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
	local url ver
	url="$(asset_from_api 'SHA256SUMS' || true)"
	if [ -n "$url" ]; then
		printf '%s' "$url"
		return 0
	fi
	ver="$(fallback_version || true)"
	[ -n "$ver" ] || return 1
	printf '%s' "https://github.com/${REPO}/releases/download/v${ver}/SHA256SUMS"
}

# The version this release publishes for a component, read from its asset names
# so an upgrade never needs a hardcoded guess. Falls back to the pinned
# constants when the API is unreachable.
release_component_version() {
	local name v ver
	name="$1"
	v="$(fetch_text "$API" 2>/dev/null \
		| grep -o "\"name\": \"${name}_[0-9][0-9a-zA-Z._-]*\.ipk\"" \
		| head -1 \
		| sed "s|\"name\": \"${name}_||; s|\.ipk\"||; s|_[0-9a-z_]*$||")"
	if [ -n "$v" ]; then
		printf '%s' "$v"
		return 0
	fi
	case "$name" in
		easyproxy) ver="$(fallback_version || true)"; printf '%s' "${ver:-0}" ;;
		sing-box) printf '%s' "$SING_BOX_VER" ;;
		dae) printf '%s' "$DAE_VER" ;;
	esac
}

# A download that is not byte-for-byte what the release published is never
# installed: a truncated file or a CDN error page would otherwise be handed to
# opkg/apk as a package.
verify_download() {
	local file url sums want got
	file="$1"
	url="$2"
	if ! command -v sha256sum >/dev/null 2>&1; then
		die "this firmware has no sha256sum; refusing to install $(basename "$url") unverified"
	fi
	sums="$(asset_sums_url || true)"
	if [ -z "$sums" ]; then
		die "this release publishes no SHA256SUMS; refusing to install $(basename "$url") unverified"
	fi
	if ! fetch_file "$sums" "$work/SHA256SUMS" 2>/dev/null; then
		die "cannot download SHA256SUMS; refusing to install $(basename "$url") unverified"
	fi
	want="$(awk -v n="$(basename "$url")" '$2 == n || $2 == "./" n { print $1 }' "$work/SHA256SUMS" | head -1)"
	[ -n "$want" ] || die "the release has no checksum for $(basename "$url"); refusing to install an unverified package"
	got="$(sha256_of "$file" || true)"
	if [ "$want" != "$got" ]; then
		info "checksum mismatch for $(basename "$url"): expected $want, got $got"
		return 1
	fi
	info "sha256 ok: $(basename "$url")"
}

# Fetch a release asset and accept it only when it matches SHA256SUMS. A CDN
# edge or a transparent proxy can serve a stale or truncated object under a
# release URL (seen in practice: the same tag served two different tarballs a
# second apart), so a mismatch is retried a couple of times before the install
# is declared broken. A mismatch is never accepted, only retried.
fetch_verified() {
	local url file attempt
	url="$1"
	file="$2"
	attempt=1
	while [ "$attempt" -le 3 ]; do
		if fetch_file "$url" "$file" && verify_download "$file" "$url"; then
			return 0
		fi
		attempt=$((attempt + 1))
		[ "$attempt" -le 3 ] || return 1
		info "retrying $(basename "$url") (attempt $attempt of 3)"
	done
	return 1
}

# Same idea for an object pinned by a sha256 inside this file rather than a
# release's SHA256SUMS (the official upstream kernel archives).
fetch_pinned() {
	local url file want got attempt
	url="$1"
	file="$2"
	want="$3"
	attempt=1
	while [ "$attempt" -le 3 ]; do
		if fetch_file "$url" "$file"; then
			got="$(sha256_of "$file" || true)"
			if [ "$want" = "$got" ]; then
				return 0
			fi
			info "checksum mismatch for $(basename "$url"): expected $want, got $got"
		fi
		attempt=$((attempt + 1))
		[ "$attempt" -le 3 ] || return 1
		info "retrying $(basename "$url") (attempt $attempt of 3)"
	done
	return 1
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
	local pm file force
	pm="$1"
	file="$2"
	force="${3:-0}"
	case "$pm" in
		opkg)
			# --force-architecture is used for the EasyProxy panel alone. The
			# panel is pure shell + LuCI assets with no compiled object, so its
			# payload is valid on every architecture; a kernel package is never
			# forced, because a wrong-architecture binary cannot run.
			if [ "$force" = 1 ] && opkg_supports_force_arch; then
				opkg install --force-architecture "$file"
			else
				[ "$force" = 1 ] && info "this opkg has no --force-architecture; installing $(basename "$file") normally"
				opkg install "$file"
			fi ;;
		apk) apk add --allow-untrusted "$file" ;;
		*) die "no package manager matched ($pm)" ;;
	esac
}

# --- component bookkeeping -------------------------------------------------
kernel_bin() {
	case "$1" in
		sing-box) printf '%s' "${EP_SING_BOX_BIN:-$ROOT/usr/bin/sing-box}" ;;
		dae)      printf '%s' "${EP_DAE_BIN:-$ROOT/usr/bin/dae}" ;;
		*) return 1 ;;
	esac
}

kernel_geodata() { printf '%s' "${EP_DAE_DATA:-$ROOT/usr/share/dae}"; }

# What the kernel reports about itself, parsed from its own `version` output:
# sing-box prints `sing-box version 1.14.4`, dae prints `dae version v2.1.2`.
kernel_probe() {
	local bin out
	bin="$(kernel_bin "$1")"
	[ -x "$bin" ] || return 1
	case "$1" in
		sing-box) out="$("$bin" version 2>/dev/null | head -1 | awk '{ print $3 }')" ;;
		dae)      out="$("$bin" --version 2>/dev/null | head -1 | sed 's/^dae version //')" ;;
		*) return 1 ;;
	esac
	out="$(printf '%s' "$out" | sed 's/^v//')"
	[ -n "$out" ] || return 1
	printf '%s' "$out"
}

kernel_present() {
	[ -x "$(kernel_bin "$1")" ] && kernel_probe "$1" >/dev/null 2>&1
}

# Mark a binary this installer put there, so uninstall can drop it again without
# ever deleting a kernel the user installed themselves.
kernel_own() {
	local bin
	bin="$(kernel_bin "$1")"
	mkdir -p "$STATE/owned" 2>/dev/null || true
	printf '%s\n' "$bin" > "$STATE/owned/$1" 2>/dev/null || true
}

kernel_owned() { [ -f "$STATE/owned/$1" ]; }

# Point UCI at the installed binary. The engine *choice* is only set when it is
# still empty: an existing choice (dae, or sing-box configured by the user) is
# never overwritten, because that would change the routing policy this script
# must not touch.
kernel_configure() {
	local bin
	command -v uci >/dev/null 2>&1 || return 0
	bin="$(kernel_bin "$1")"
	case "$1" in
		sing-box)
			uci -q set easyproxy.sing_box.binary="$bin" 2>/dev/null || true
			if [ -z "$(uci -q get easyproxy.main.engine 2>/dev/null || true)" ] \
				|| [ "$(uci -q get easyproxy.main.engine 2>/dev/null || true)" = none ]; then
				uci -q set easyproxy.main.engine='sing-box' 2>/dev/null || true
			fi ;;
		dae)
			uci -q set easyproxy.dae.binary="$bin" 2>/dev/null || true ;;
	esac
	uci -q commit easyproxy 2>/dev/null || true
	info "$1: uci points at $bin"
}

# Paths other proxy packages leave a static sing-box/dae in. Open-Box ships
# /opt/open-box/bin/sing-box; KoolShare-style bundles and hand drops land in the
# other entries. The official upstream build is glibc-linked and cannot exec on
# a musl firmware at all, so a binary already on the box is worth more than a
# download: adopting it is the difference between "installed" and "runs".
kernel_external_paths() {
	case "$1" in
		sing-box) printf '%s\n' \
			"$ROOT/opt/open-box/bin/sing-box" \
			"$ROOT/usr/local/bin/sing-box" \
			"$ROOT/etc/sing-box/sing-box" \
			"$ROOT/koolshare/bin/sing-box" \
			"$ROOT/opt/sing-box/sing-box" ;;
		dae) printf '%s\n' \
			"$ROOT/usr/local/bin/dae" \
			"$ROOT/etc/dae/dae" \
			"$ROOT/opt/dae/dae" ;;
	esac
}

# Adopt an existing static binary instead of downloading one. Returns 0 and
# leaves the path in KERNEL_ADOPTED when it found something that actually runs.
# Nothing is copied and nothing is recorded as installer-owned: uninstall must
# never delete a kernel that belongs to another package.
kernel_adopt_external() {
	local name path ver
	name="$1"
	KERNEL_ADOPTED=""
	for path in $(kernel_external_paths "$name"); do
		[ -x "$path" ] || continue
		case "$name" in
			sing-box) ver="$("$path" version 2>/dev/null | head -1)" ;;
			dae) ver="$("$path" --version 2>/dev/null | head -1)" ;;
			*) ver="" ;;
		esac
		[ -n "$ver" ] || continue
		info "$name: found a working static binary at $path ($ver)"
		info "$name: adopting it instead of downloading (it keeps belonging to whatever installed it)"
		KERNEL_ADOPTED="$path"
		return 0
	done
	return 1
}

# Point UCI at an adopted binary. Separate from kernel_configure() because that
# one derives the path from kernel_bin() - here the binary lives outside our tree.
kernel_configure_adopted() {
	local name path
	name="$1"
	path="$2"
	command -v uci >/dev/null 2>&1 || return 0
	case "$name" in
		sing-box)
			uci -q set easyproxy.sing_box.binary="$path" 2>/dev/null || true
			if [ -z "$(uci -q get easyproxy.main.engine 2>/dev/null || true)" ] \
				|| [ "$(uci -q get easyproxy.main.engine 2>/dev/null || true)" = none ]; then
				uci -q set easyproxy.main.engine='sing-box' 2>/dev/null || true
			fi ;;
		dae) uci -q set easyproxy.dae.binary="$path" 2>/dev/null || true ;;
	esac
	uci -q commit easyproxy 2>/dev/null || true
	info "$name: uci points at $path"
}

# Another proxy manager on the same box means two owners of nft tables and of
# the 7890-family ports. Installing next to one is fine; starting both is not.
# Say it out loud instead of letting the user discover it as "my proxy stopped
# working after I installed this".
coexistence_notice() {
	local hit svc
	hit=""
	if command -v nft >/dev/null 2>&1; then
		hit="$(nft list tables 2>/dev/null \
			| sed -n 's/^table \(inet\|ip\|ip6\) \{1,\}\([A-Za-z0-9_-]*\)/\2/p' \
			| grep -E '^(openbox|sing-box|passwall|passwall2|clash|mihomo|shellcrash|ssrplus|ssr)$' \
			| sort -u | tr '\n' ' ')"
	fi
	if [ -z "$hit" ]; then
		for svc in openbox sing-box mihomo passwall passwall2 shellcrash; do
			[ -x "$ROOT/etc/init.d/$svc" ] || continue
			case "$( "$ROOT/etc/init.d/$svc" status 2>/dev/null | head -1)" in
				running*) hit="$hit $svc" ;;
			esac
		done
	fi
	[ -n "$(printf '%s' "$hit" | tr -d ' ')" ] || return 0
	info "another proxy is already active:$hit"
	info "  both build nft tables and bind the same ports, so run only one at a time:"
	info "  /etc/init.d/<name> stop    # e.g. openbox, passwall"
	info "  installing next to it is fine; starting EasyProxy while it runs is not."
}

# --- kernel sources -------------------------------------------------------
kernel_sha() {
	local name arch target
	name="$1"
	arch="$2"
	case "$name" in
		sing-box) target="$SING_BOX_TARGET" ;;
		dae)      target="$DAE_TARGET" ;;
		*) return 1 ;;
	esac
	if [ "$target" != "$SING_BOX_VER" ] && [ "$name" = sing-box ]; then
		return 1
	fi
	if [ "$target" != "$DAE_VER" ] && [ "$name" = dae ]; then
		return 1
	fi
	case "$name" in
		sing-box)
			[ -n "${EP_SING_BOX_SHA:-}" ] && { printf '%s' "$EP_SING_BOX_SHA"; return 0; }
			case "$arch" in
				amd64) printf '%s' '699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968' ;;
				arm64) printf '%s' '436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26' ;;
				armv7) printf '%s' 'fd164ed45ebc784f657a3e1d0e0ad0f68afdcff864ee57122c2cfed3ddb80a00' ;;
			esac ;;
		dae)
			[ -n "${EP_DAE_SHA:-}" ] && { printf '%s' "$EP_DAE_SHA"; return 0; }
			case "$arch" in
				x86_64) printf '%s' '37e19ce6abe12fe713a339d8a9335e10a5777c6d62613c5af91d64ca5bb3a56c' ;;
				arm64)  printf '%s' '59979e524bb52a2634e11536def5db8efefba897ed6f565ea1d083221faf7709' ;;
				armv7)  printf '%s' '6c72afba36d4656c430f502c4615d505c6f681577d79de4c307a4be5bd7e8736' ;;
			esac ;;
	esac
}

# Upstream arch name in the official archive file name.
kernel_arch() {
	case "$1:$2" in
		sing-box:x86_64)  printf '%s' amd64 ;;
		sing-box:aarch64) printf '%s' arm64 ;;
		sing-box:armv7)   printf '%s' armv7 ;;
		dae:x86_64)       printf '%s' x86_64 ;;
		dae:aarch64)      printf '%s' arm64 ;;
		dae:armv7)        printf '%s' armv7 ;;
		*) printf '%s' '' ;;
	esac
}

kernel_archive_url() {
	local name family arch ver
	name="$1"
	family="$(host_family)"
	arch="$(kernel_arch "$name" "$family")"
	[ -n "$arch" ] || return 1
	case "$name" in
		sing-box)
			ver="$SING_BOX_TARGET"
			printf '%s' "https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${arch}.tar.gz" ;;
		dae)
			printf '%s' "https://github.com/daeuniverse/dae/releases/download/v${DAE_TARGET}/dae-linux-${arch}.tar.xz" ;;
	esac
}

# The kernel ipk this repository publishes for the host, if any.
kernel_ipk_url() {
	local name ipkarch ver api
	name="$1"
	ipkarch="$(kernel_ipk_arch)"
	[ -n "$ipkarch" ] || return 1
	case "$name" in
		sing-box) ver="$SING_BOX_TARGET" ;;
		dae)      ver="$DAE_TARGET" ;;
		*) return 1 ;;
	esac
	api="$(fetch_text "$API" 2>/dev/null || true)"
	[ -n "$api" ] || return 1
	printf '%s' "$api" \
		| tr '{' '\n' \
		| grep -o 'https://[^"]*' \
		| grep -E "/${name}_[0-9][0-9a-zA-Z._-]*_${ipkarch}\.ipk$" \
		| head -1
}

check_payload() {
	local file
	file="$1"
	if dd if="$file" bs=1 count=4 2>/dev/null | grep -q 'ELF'; then
		return 0
	fi
	if dd if="$file" bs=1 count=2 2>/dev/null | grep -q '#!'; then
		return 0
	fi
	die "$2 is neither an ELF binary nor an executable script (invalid download, nothing installed)"
}

# Install one kernel from the release kernel ipk, or from the official archive
# when this architecture has no kernel ipk.
install_kernel() {
	local name bin url file arch want got src pm dest via_ipk
	name="$1"
	bin="$(kernel_bin "$name")"
	via_ipk=0

	url="$(kernel_ipk_url "$name" || true)"
	if [ -n "$url" ]; then
		file="$work/$(basename "$url")"
		info "$name: downloading $(basename "$url")"
		if ! fetch_verified "$url" "$file"; then
			info "$name: no verified kernel ipk for $(host_family), falling back to the official archive"
			url=""
		else
			check_package_file "$url" "$file"
			pm="$(detect_pm || printf '%s' '')"
			if [ -z "$pm" ]; then
				info "$name: kernel ipk downloaded but this firmware has no package manager"
				url=""
			else
				info "$name: installing $(basename "$url") with $pm"
				if install_pkg "$pm" "$file"; then
					via_ipk=1
				else
					# opkg here calls our kernel ipk "Malformed package file" (its
					# parser rejects the archive) - the official pinned binary still
					# installs, so fall through to that route instead of failing.
					info "$name: $pm refused $(basename "$url") as unreadable; using the official archive"
					url=""
				fi
			fi
		fi
	fi

	# The kernel ipk just installed it; the binary is on disk already.
	if [ "$via_ipk" = 1 ] && [ -x "$bin" ]; then
		chmod 755 "$bin" 2>/dev/null || true
		kernel_own "$name"
		info "$name: installed $bin"
		return 0
	fi

	# Official archive route.
	arch="$(kernel_arch "$name" "$(host_family)")"
	if [ -z "$arch" ]; then
		info "$name: install failed: $(uname -m 2>/dev/null) has no official $name build"
		return 1
	fi
	url="$(kernel_archive_url "$name" || true)"
	[ -n "$url" ] || { info "$name: install failed: cannot build the archive URL"; return 1; }
	file="$work/$(basename "$url")"
	info "$name: downloading $(basename "$url")"
	want="$(kernel_sha "$name" "$arch" || true)"
	if [ -z "$want" ]; then
		info "$name: install failed: no pinned sha256 for $arch; refusing an unverified binary"
		return 1
	fi
	if ! command -v sha256sum >/dev/null 2>&1; then
		info "$name: install failed: this firmware has no sha256sum, cannot verify the download"
		return 1
	fi
	if ! fetch_pinned "$url" "$file" "$want"; then
		rm -f "$file"
		info "$name: install failed: cannot download a verified archive, nothing was installed"
		return 1
	fi
	info "$name sha256 ok: $(basename "$url")"

	mkdir -p "$work/$name"
	case "$name" in
		dae)
			if ! tar -xJf "$file" -C "$work/$name" 2>/dev/null; then
				info "$name: install failed: cannot extract $(basename "$url") (this firmware may lack xz support); the release kernel ipk avoids xz"
				return 1
			fi ;;
		*)
			if ! tar -xzf "$file" -C "$work/$name" 2>/dev/null; then
				info "$name: install failed: cannot extract $(basename "$url")"
				return 1
			fi ;;
	esac
	src="$(find "$work/$name" -type f -name "$name" 2>/dev/null | head -1)"
	if [ -z "$src" ]; then
		info "$name: install failed: the archive carries no $name binary"
		return 1
	fi
	check_payload "$src" "$(basename "$src")"
	mkdir -p "$(dirname "$bin")"
	cp "$src" "$bin" || { info "$name: install failed: cannot write $bin"; return 1; }
	chmod 755 "$bin"

	if [ "$name" = dae ]; then
		dest="$(kernel_geodata)"
		mkdir -p "$dest"
		for dat in "$work/$name"/usr/share/dae/*.dat; do
			[ -f "$dat" ] || continue
			cp "$dat" "$dest/$(basename "$dat")" || { info "dae: install failed: cannot write $dest/$(basename "$dat")"; return 1; }
		done
		info "dae: routing assets in $dest"
	fi
	kernel_own "$name"
	info "$name: installed $bin"
	return 0
}

# A kernel counts as installed only if it runs and reports a version.
kernel_verify() {
	local name ver
	name="$1"
	ver="$(kernel_probe "$name" || true)"
	if [ -z "$ver" ]; then
		info "$name: install failed: $(kernel_bin "$name") does not report a version"
		return 1
	fi
	info "$name: $ver runs ($(kernel_bin "$name"))"
	return 0
}

ensure_kernel() {
	local name ver
	name="$1"
	if [ -x "$(kernel_bin "$name")" ] && kernel_present "$name"; then
		ver="$(kernel_probe "$name")"
		info "$name: already present ($(kernel_bin "$name") $ver)"
		kernel_configure "$name"
		return 0
	fi
	# A static binary another package already installed beats a download: the
	# upstream builds are glibc and will not exec on musl firmware.
	if kernel_adopt_external "$name"; then
		kernel_configure_adopted "$name" "$KERNEL_ADOPTED"
		return 0
	fi
	install_kernel "$name" || return 1
	kernel_verify "$name" || return 1
	kernel_configure "$name"
	return 0
}

# --- package component ----------------------------------------------------
package_version() {
	local v
	command -v opkg >/dev/null 2>&1 || {
		command -v apk >/dev/null 2>&1 || return 1
		apk info -e easyproxy >/dev/null 2>&1 || return 1
		apk list --installed 2>/dev/null | sed -n 's/^easyproxy-\([0-9][0-9a-zA-Z._-]*\)-[a-z0-9_]*\.apk.*/\1/p' | head -1
		return 0
	}
	v="$(opkg list-installed easyproxy 2>/dev/null | awk '{ print $3 }' | head -1)"
	[ -n "$v" ] && { printf '%s' "$v"; return 0; }
	# A rootfs-archive install (Kwrt, or any opkg that refuses our ipk) is not
	# registered with the package manager, so ask the binary itself instead of
	# reporting "unknown".
	if [ -x "$BIN" ]; then
		"$BIN" status 2>/dev/null | head -1 \
			| sed -n 's/.*EasyProxy \([0-9][0-9]*\.[0-9][0-9.]*\).*/\1/p'
	fi
}

# --- host checks ----------------------------------------------------------
# Both kernels plus the package plus the archives and their unpacked copies
# need room in /tmp and at /: a download that fills the filesystem fails
# halfway, which is worse than refusing up front. EP_MIN_FREE_KB overrides the
# requirement (the tests set it to 0).
MIN_FREE_KB="${EP_MIN_FREE_KB:-65536}"

check_disk_space() {
	local need path avail
	need="${MIN_FREE_KB:-65536}"
	case "$need" in
		''|*[!0-9]*) need=65536 ;;
	esac
	for path in "$TMP" "$ROOT"; do
		[ -d "$path" ] || continue
		avail="$(df -Pk "$path" 2>/dev/null | awk 'NR == 2 { print $4 }')"
		[ -n "${avail:-}" ] || continue
		if [ "$avail" -lt "$need" ]; then
			die "not enough disk space on $path: ${avail} KB free, ${need} KB needed; free space and run again (EP_MIN_FREE_KB overrides this)"
		fi
		info "disk: $path has ${avail} KB free (need ${need} KB)"
	done
}

# The firmware family is read from the firmware itself, never assumed. A
# missing /etc/openwrt_release (a stripped image, a test sandbox) is reported
# instead of guessed at; EP_SKIP_COMPAT=1 forces an install on an unknown one.
check_firmware() {
	local rel id ver desc relver derivative release_mm major minor
	rel="$ROOT/etc/openwrt_release"
	if [ ! -r "$rel" ]; then
		info "firmware: $rel is missing, the firmware family cannot be checked"
		return 0
	fi
	id="$(sed -n "s/^DISTRIB_ID=['\"]*//p" "$rel" | sed "s/['\"][^'\"]*.*//" | head -1)"
	ver="$(sed -n "s/^VERSION_ID=['\"]*//p" "$rel" | sed "s/['\"][^'\"]*.*//" | head -1)"
	desc="$(sed -n "s/^DISTRIB_DESCRIPTION=['\"]*//p" "$rel" | sed "s/['\"][^'\"]*.*//" | head -1)"
	relver="$(sed -n "s/^DISTRIB_RELEASE=['\"]*//p" "$rel" | sed "s/['\"][^'\"]*.*//" | head -1)"
	derivative=0
	case "$id" in
		ImmortalWrt|OpenWrt|LEDE|immortalwrt|openwrt) : ;;
		Kwrt|kwrt|KWRT)
			# Kwrt (dl.openwrt.ai, Kiddin9's builds) is an OpenWrt derivative,
			# not a fork of its own: real images carry DISTRIB_ID='Kwrt' and
			# DISTRIB_RELEASE='25.12-SNAPSHOT' with no VERSION_ID line, so the
			# OpenWrt baseline has to come from DISTRIB_RELEASE (falling back to
			# DISTRIB_DESCRIPTION). Its package manager is still opkg even on
			# 25.12 bases, which detect_pm settles by asking the firmware.
			derivative=1
			[ -n "${ver:-}" ] || ver="${relver:-}"
			if [ -z "${ver:-}" ] && [ -n "${desc:-}" ]; then
				ver="$(printf '%s' "$desc" | sed "s/^${id}[[:space:]]*//")"
			fi ;;
		*)
			if [ "${EP_SKIP_COMPAT:-}" = 1 ]; then
				info "firmware: ${id:-unknown} is not verified, EP_SKIP_COMPAT=1 forces the install"
				return 0
			fi
			die "firmware: ${id:-unknown} is not OpenWrt/ImmortalWrt; this build targets 21.02 or newer (EP_SKIP_COMPAT=1 forces the install)" ;;
	esac
	if [ -z "${ver:-}" ]; then
		if [ "$derivative" = 1 ]; then
			if [ "${EP_SKIP_COMPAT:-}" = 1 ]; then
				info "firmware: $id states no release at all, EP_SKIP_COMPAT=1 forces the install"
				return 0
			fi
			die "firmware: $id states no DISTRIB_RELEASE, the OpenWrt baseline cannot be confirmed; this build needs 21.02 or newer (EP_SKIP_COMPAT=1 forces the install)"
		fi
		info "firmware: $id has no VERSION_ID, the release cannot be checked"
		return 0
	fi
	# 21.02 / 23.05 / 25.12 - the leading NN.mm token, so '25.12-SNAPSHOT' and
	# 'Kwrt 25.12-SNAPSHOT 10.11.2026' both resolve. Build dates (10.11.2026)
	# do not match, because the year part starts at 12.
	release_mm="$(printf '%s' "$ver" | grep -oE '(1[2-9]|2[0-9]|3[0-9])\.[0-9][0-9]' | head -1)"
	if [ -z "$release_mm" ]; then
		if [ "${EP_SKIP_COMPAT:-}" = 1 ]; then
			info "firmware: $id ${ver} states no OpenWrt baseline, EP_SKIP_COMPAT=1 forces the install"
			return 0
		fi
		die "firmware: $id ${ver} states no OpenWrt baseline (expected a release like 23.05 or 25.12); this build needs 21.02 or newer (EP_SKIP_COMPAT=1 forces the install)"
	fi
	major="${release_mm%%.*}"
	minor="${release_mm#*.}"
	minor="${minor#0}"
	if [ "$major" -lt 21 ] || { [ "$major" -eq 21 ] && [ "$minor" -lt 2 ]; }; then
		if [ "${EP_SKIP_COMPAT:-}" = 1 ]; then
			info "firmware: $id $ver is not verified, EP_SKIP_COMPAT=1 forces the install"
			return 0
		fi
		die "firmware: $id $ver is older than 21.02; this build needs 21.02 or newer (EP_SKIP_COMPAT=1 forces the install)"
	fi
	if [ "$derivative" = 1 ]; then
		info "firmware: $id $ver (OpenWrt $release_mm derivative)"
	else
		info "firmware: $id $ver"
	fi
}

# The panel ipk and the kernel ipks exist for three families only; anything else
# (mipsel_24kc, arm_cortex-a9, ...) would install files the device cannot run, so
# name the architecture and stop instead of failing somewhere deeper.
check_arch() {
	local a m
	a="$(host_ipk_arch)"
	m="$(uname -m 2>/dev/null)"
	case "$a" in
		x86_64|amd64|aarch64*|armv7*|armv6*) return 0 ;;
	esac
	if [ -z "$a" ]; then
		case "$m" in
			x86_64|amd64|aarch64|arm64|armv7l|armv7) return 0 ;;
		esac
	fi
	# The panel ships an `_all.ipk` (architecture independent), so it still
	# installs here; the kernels do not, and the kernel step says so if asked.
	info "arch: ${a:-$m} is outside x86_64/aarch64/armv7; the panel installs, but this build carries no kernel for that architecture"
}

# The panel is a LuCI app: installing it without LuCI leaves a package that no
# menu ever shows. Report that instead of letting the user hunt for a missing
# page; opkg still pulls luci-base from the feeds when it can.
check_luci() {
	[ -r "$ROOT/usr/share/luci/menu.d" ] && return 0
	[ -d "$ROOT/usr/lib/lua/luci" ] && return 0
	info "luci: $ROOT/usr/share/luci/menu.d is missing; the easyproxy menu appears only after luci-base is installed"
}

# --- actions -------------------------------------------------------------
work=""
mkwork() {
	mkdir -p "$TMP"
	work="$(mktemp -d "$TMP/easyproxy.XXXXXX")"
	trap 'rm -rf "$work"' EXIT
}

# Permissions that must not depend on the caller's umask: the log can quote a
# node URL or a subscription token and /var/log is world-readable on OpenWrt,
# and /etc/easyproxy holds the node links themselves.
harden_paths() {
	if [ -d "$ROOT/var/log" ]; then
		[ -e "$ROOT/var/log/easyproxy.log" ] || : >> "$ROOT/var/log/easyproxy.log" 2>/dev/null || true
		chmod 600 "$ROOT/var/log/easyproxy.log" 2>/dev/null || true
	fi
	[ -d "$ROOT/etc/easyproxy" ] && chmod 700 "$ROOT/etc/easyproxy" 2>/dev/null || true
	return 0
}

# The package manager is not the only way to lay the panel down: the same tree
# is published as a rootfs archive. `--rootfs` uses it directly, and the ipk
# branch falls back to it when opkg refuses the package (`Malformed package
# file`, an architecture it does not accept, ...). Verified assets only.
install_rootfs() {
	local url file
	url="$(asset_url '\.tar\.gz$')" \
		|| die "cannot resolve the rootfs archive URL (release API unreachable and no version in the Makefile)"
	file="$work/$(basename "$url")"
	info "downloading $(basename "$url")"
	fetch_verified "$url" "$file" || die "download failed or unverified: $url"
	info "extracting at $ROOT (no package manager involved)"
	tar -xzf "$file" -C "$ROOT" || die "cannot extract $file at $ROOT"
	chmod 755 "$ROOT/usr/sbin/easyproxy" "$ROOT/etc/init.d/easyproxy" 2>/dev/null || true
	harden_paths
}

install_package() {
	local arch accepts_all url alt file force_panel pmout refused
	arch=""
	accepts_all=0
	force_panel=0
	if [ -z "$MODE" ]; then
		pm="$(detect_pm)" || die "found neither opkg nor apk; this firmware has no supported package manager.
Use: sh install.sh --rootfs  (extracts the archive at / without a package manager)"
		case "$pm" in
			opkg) MODE=ipk ;;
			apk) MODE=apk ;;
		esac
	fi

	case "$MODE" in
		apk|ipk)
			if [ "$MODE" = "apk" ]; then
				url="$(asset_url '\.apk$')" \
					|| die "cannot resolve the apk download URL (release API unreachable and no version in the Makefile)"
			else
				# The release carries one ipk per target next to `_all.ipk`. The arch is
				# whatever opkg itself reports; `_all.ipk` is only used when this opkg
				# actually accepts `Architecture: all`.
				arch="$(host_ipk_arch)"
				if opkg_accepts_all; then
					accepts_all=1
				fi
				[ -n "$arch" ] && url="$(asset_from_api "easyproxy_[0-9][0-9a-zA-Z._-]*_${arch}\.ipk$" || true)"
				if [ -z "${url:-}" ] && [ "$accepts_all" = 1 ]; then
					url="$(asset_from_api 'easyproxy_[0-9][0-9a-zA-Z._-]*_all\.ipk$' || true)"
				fi
				if [ -z "${url:-}" ]; then
					if [ "$accepts_all" != 1 ]; then
						# This opkg accepts only the architecture it was built for, and
						# the release carries no ipk stamped with it (Kwrt 25.12-SNAPSHOT
						# on riscv64, mipsel_24kc, ...). The panel payload is
						# architecture independent, so install the `_all.ipk` with
						# --force-architecture; if even that is refused, the archive
						# route below finishes the install. Kernels are never forced.
						url="$(asset_from_api 'easyproxy_[0-9][0-9a-zA-Z._-]*_all\.ipk$' || true)"
						[ -n "${url:-}" ] || url="$(asset_url 'easyproxy_[0-9][0-9a-zA-Z._-]*\.ipk$')" \
							|| die "cannot resolve the ipk download URL (release API unreachable and no version in the Makefile)"
						force_panel=1
					else
						url="$(asset_url '\.ipk$' "$arch")" \
							|| die "cannot resolve the ipk download URL (release API unreachable and no version in the Makefile)"
					fi
				fi
			fi
			file="$work/$(basename "$url")"
			info "downloading $(basename "$url")"
			if ! fetch_verified "$url" "$file"; then
				if [ "$MODE" = "ipk" ] && [ "$accepts_all" = 1 ]; then
					alt="$(asset_from_api 'easyproxy_[0-9][0-9a-zA-Z._-]*_all\.ipk$' || true)"
					[ -n "$alt" ] || alt="$(asset_url 'easyproxy_[0-9][0-9a-zA-Z._-]*\.ipk$' 2>/dev/null || true)"
					[ -n "$alt" ] || die "download failed: $url"
					info "architecture-specific package unavailable, retrying $(basename "$alt")"
					url="$alt"
					file="$work/$(basename "$url")"
					fetch_verified "$url" "$file" || die "download failed or unverified: $url"
				else
					die "download failed or unverified: $url"
				fi
			fi
			check_package_file "$url" "$file"
			if [ "$force_panel" = 1 ]; then
				info "warning: this opkg rejects Architecture: all and the release has no _${arch:-unknown}.ipk; installing $(basename "$url") with --force-architecture (panel only, never a kernel)"
			fi
			info "installing with $(detect_pm || printf '%s' 'package manager')"
			pmout="$work/pm.out"
			if install_pkg "$(detect_pm || printf '%s' opkg)" "$file" "$force_panel" > "$pmout" 2>&1; then
				:
			else
				cat "$pmout"
				# The archive route replaces the package manager only when the
				# package itself was refused (no architecture this opkg takes, or
				# an ipk its parser calls malformed). A failure in the middle of an
				# install - the kind an upgrade rolls back - is reported as a
				# failure, so the caller can restore the previous package.
				refused=0
				[ "$force_panel" = 1 ] && refused=1
				grep -qi 'malformed package file\|invalid package file\|unknown package arch' "$pmout" && refused=1
				if [ "$MODE" = "ipk" ] && [ "$refused" = 1 ]; then
					info "the package manager refused $(basename "$url"); falling back to the rootfs archive"
					install_rootfs || return 1
				else
					info "the package manager refused $(basename "$url"); nothing was installed"
					return 1
				fi
			fi
			;;
		rootfs)
			install_rootfs
			;;
		*)
			die "unknown mode: $MODE"
		;;
	esac
}

post_install() {
	harden_paths
	if [ -x "$INIT" ]; then
		"$INIT" enable >/dev/null 2>&1 || true
	fi
	if [ -x "$RPCD" ]; then
		"$RPCD" restart >/dev/null 2>&1 || true
	fi
	rm -f "$LUCI_INDEX"* 2>/dev/null || true
	if [ -x "$BIN" ]; then
		info "service: $("$BIN" status 2>/dev/null | head -1 || true)"
	else
		info "installed, but $BIN is not executable; check the package layout"
	fi
}

print_summary() {
	local pver sver dver
	pver="$(package_version 2>/dev/null || true)"
	[ -n "$pver" ] || pver="unknown"
	sver="$(kernel_probe sing-box 2>/dev/null || true)"
	dver="$(kernel_probe dae 2>/dev/null || true)"
	info ""
	info "components:"
	info "  easyproxy  ${pver}  ($BIN)"
	info "  sing-box   ${sver:-not installed}  ($(kernel_bin sing-box))"
	info "  dae        ${dver:-not installed}  ($(kernel_bin dae))  [adapter 开发中]"
}

do_install() {
	check_firmware
	check_luci
	check_arch
	check_disk_space
	mkwork
	install_package || die "the package could not be installed; nothing was installed"
	post_install

	KERNEL_FAILED=""
	coexistence_notice
	if [ "$NO_SING_BOX" = 0 ]; then
		ensure_kernel sing-box || KERNEL_FAILED="$KERNEL_FAILED sing-box"
	else
		info "sing-box: skipped"
	fi
	if [ "$NO_DAE" = 0 ]; then
		ensure_kernel dae || KERNEL_FAILED="$KERNEL_FAILED dae"
	else
		info "dae: skipped"
	fi

	print_summary

	if [ -n "$KERNEL_FAILED" ]; then
		die "EasyProxy is installed but these kernels are not:$KERNEL_FAILED
The package alone cannot start traffic: re-run this installer, or place a static
binary yourself and set easyproxy.sing_box.binary / easyproxy.dae.binary."
	fi
}

# --- upgrade -------------------------------------------------------------
backup_kernel() {
	local name bin dir
	name="$1"
	bin="$(kernel_bin "$name")"
	dir="$STATE/backup"
	mkdir -p "$dir" 2>/dev/null || true
	[ -x "$bin" ] || return 0
	cp "$bin" "$dir/$name.old" 2>/dev/null || true
	info "$name: previous binary saved to $dir/$name.old"
}

restore_kernel() {
	local name bin dir
	name="$1"
	bin="$(kernel_bin "$name")"
	dir="$STATE/backup"
	if [ -f "$dir/$name.old" ]; then
		cp "$dir/$name.old" "$bin" 2>/dev/null && chmod 755 "$bin" 2>/dev/null || true
		info "$name: restored $(kernel_probe "$name" 2>/dev/null || printf '%s' 'the previous binary')"
		return 0
	fi
	return 1
}

upgrade_kernel() {
	local name before after target
	name="$1"
	target="$(release_component_version "$name")"
	case "$name" in
		sing-box) SING_BOX_TARGET="$target" ;;
		dae)      DAE_TARGET="$target" ;;
	esac
	before="$(kernel_probe "$name" 2>/dev/null || true)"
	backup_kernel "$name"
	if ! install_kernel "$name"; then
		restore_kernel "$name" || true
		return 1
	fi
	after="$(kernel_probe "$name" 2>/dev/null || true)"
	if [ -z "$after" ]; then
		info "$name: the new binary does not run; rolling back"
		restore_kernel "$name" || true
		return 1
	fi
	if [ -z "$before" ]; then
		info "$name: installed $after"
	else
		info "$name: $before -> $after"
	fi
	kernel_verify "$name" >/dev/null 2>&1 || return 1
	kernel_configure "$name"
	return 0
}

# The UCI config and the installer's own state are the two things an upgrade
# must never lose: the package ships defaults for /etc/config/easyproxy, and
# /etc/easyproxy/owned is what lets uninstall remove only what this installer
# put there. Both are tarred before anything is replaced.
backup_config() {
	local dir stamp archive
	dir="$STATE/backup"
	mkdir -p "$dir" 2>/dev/null || { info "backup: cannot create $dir, the config is not backed up"; return 1; }
	stamp="$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || printf '%s' manual)"
	archive="$dir/config-$stamp.tar.gz"
	if [ ! -f "$ROOT/etc/config/easyproxy" ] && [ ! -d "$STATE" ]; then
		info "backup: nothing to back up yet"
		return 1
	fi
	# The archive is written outside $STATE first. Writing it straight into
	# $STATE/backup means tar is archiving the directory it is still writing to,
	# and GNU tar intermittently exits 1 with "file changed as we read it" -
	# which silently skipped the pre-upgrade backup (seen once in a full run,
	# report 009). The --exclude keeps older backups out of the new one.
	tmp="$STATE/../.ep-backup-$stamp.tar.gz"
	if ! tar -czf "$tmp" --exclude="$dir" "$ROOT/etc/config/easyproxy" "$STATE" 2>/dev/null; then
		rm -f "$tmp"
		info "backup: tar failed, the config is not backed up"
		return 1
	fi
	if ! mv "$tmp" "$archive"; then
		rm -f "$tmp"
		info "backup: cannot move the archive into $dir, the config is not backed up"
		return 1
	fi
	info "backup: config and state saved to $archive"
	return 0
}

# The installed file list is what makes a package rollback possible: without an
# old copy of those files, a failed upgrade leaves a half-written tree.
package_files() {
	local list
	list="$ROOT/usr/lib/opkg/info/easyproxy.list"
	if [ -r "$list" ]; then
		cat "$list"
		return 0
	fi
	if command -v apk >/dev/null 2>&1; then
		apk info -L easyproxy 2>/dev/null | sed -n '/^\//p'
	fi
}

snapshot_package() {
	local dir stamp files
	dir="$STATE/backup"
	mkdir -p "$dir" 2>/dev/null || return 1
	files="$(package_files | awk -v r="$ROOT" '{ if (r != "/" && $0 ~ "^/") print r $0; else print $0 }')"
	[ -n "$files" ] || { info "backup: no installed file list, the old package is not snapshotted"; return 1; }
	stamp="$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || printf '%s' manual)"
	# shellcheck disable=SC2086
	if ! tar -czf "$dir/package-$stamp.tar.gz" $files 2>/dev/null; then
		info "backup: tar failed, the old package is not snapshotted"
		return 1
	fi
	info "backup: installed package files saved to $dir/package-$stamp.tar.gz"
	return 0
}

restore_package() {
	local archive
	archive="$(ls -1t "$STATE"/backup/package-*.tar.gz 2>/dev/null | head -1)"
	[ -n "$archive" ] || { info "rollback: no package snapshot to restore"; return 1; }
	if ! tar -xzf "$archive" -C / 2>/dev/null; then
		info "rollback: cannot extract $archive"
		return 1
	fi
	info "rollback: package files restored from $archive"
	return 0
}

upgrade_package() {
	local before target
	before="$(package_version 2>/dev/null || true)"
	target="$(release_component_version easyproxy)"
	if [ -n "$before" ] && [ "$before" = "$target" ]; then
		info "easyproxy: ${before} (already the newest release)"
		return 0
	fi
	info "easyproxy: ${before:-unknown} -> ${target:-unknown}"
	snapshot_package || true
	if install_package; then
		post_install
		return 0
	fi
	info "easyproxy: upgrade failed, restoring the package files that were there before"
	restore_package || info "easyproxy: no snapshot was taken, the old package stays installed"
	return 1
}

do_upgrade() {
	mkwork
	local pkg_cur pkg_tgt sb_cur sb_tgt dae_cur dae_tgt changed failed service_was_up
	pkg_cur="$(package_version 2>/dev/null || true)"
	pkg_tgt="$(release_component_version easyproxy)"
	sb_cur="$(kernel_probe sing-box 2>/dev/null || true)"
	sb_tgt="$(release_component_version sing-box)"
	dae_cur="$(kernel_probe dae 2>/dev/null || true)"
	dae_tgt="$(release_component_version dae)"

	info "component    current      newest"
	info "easyproxy    ${pkg_cur:-unknown}      ${pkg_tgt:-unknown}"
	info "sing-box     ${sb_cur:-missing}      ${sb_tgt:-unknown}"
	info "dae          ${dae_cur:-missing}      ${dae_tgt:-unknown}"
	info ""

	changed=0
	[ "$pkg_cur" = "$pkg_tgt" ] || changed=1
	[ "$sb_cur" = "$sb_tgt" ] || changed=1
	[ "$dae_cur" = "$dae_tgt" ] || changed=1
	if [ "$changed" = 0 ]; then
		info "already up to date: easyproxy ${pkg_cur}, sing-box ${sb_cur}, dae ${dae_cur}"
		return 0
	fi

	check_firmware
	check_luci
	check_arch
	check_disk_space
	backup_config || true

	service_was_up=0
	if [ -x "$INIT" ]; then
		if "$INIT" status >/dev/null 2>&1; then
			service_was_up=1
			"$INIT" stop >/dev/null 2>&1 || true
			info "service stopped for the upgrade"
		fi
	fi

	failed=""
	case "$ONLY" in
		'')
			if [ "$pkg_cur" != "$pkg_tgt" ]; then
				upgrade_package || failed="$failed package"
			fi
			if [ "$sb_cur" != "$sb_tgt" ]; then
				upgrade_kernel sing-box || failed="$failed sing-box"
			fi
			if [ "$dae_cur" != "$dae_tgt" ]; then
				upgrade_kernel dae || failed="$failed dae"
			fi ;;
		package)  upgrade_package || failed="$failed package" ;;
		sing-box) upgrade_kernel sing-box || failed="$failed sing-box" ;;
		dae)      upgrade_kernel dae || failed="$failed dae" ;;
	esac

	if [ "$service_was_up" = 1 ] && [ -z "$failed" ]; then
		"$INIT" start >/dev/null 2>&1 || true
		info "service restarted"
	fi

	print_summary

	if [ -n "$failed" ]; then
		die "upgrade incomplete:$failed (each failure was rolled back to the version that worked)"
	fi
	info "upgrade done"
}

do_status() {
	local pkg sb dae
	pkg="$(package_version 2>/dev/null || true)"
	sb="$(kernel_probe sing-box 2>/dev/null || true)"
	dae="$(kernel_probe dae 2>/dev/null || true)"
	info "easyproxy  ${pkg:-not installed}  ($BIN)"
	info "sing-box   ${sb:-not installed}   ($(kernel_bin sing-box))"
	info "dae        ${dae:-not installed}   ($(kernel_bin dae))"
	if [ -x "$INIT" ]; then
		info "service    $("$INIT" status 2>/dev/null | head -1 || printf '%s' unknown)"
	fi
	if [ -x "$BIN" ]; then
		info "engine     $("$BIN" status 2>/dev/null | sed -n 's/^engine: //p' | head -1 || true)"
	fi
}

# --- dispatch -------------------------------------------------------------
case "$ACTION" in
	status) do_status; exit 0 ;;
	upgrade) do_upgrade ;;
	install)
		do_install
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

Upgrade: sh install.sh upgrade      (or --only sing-box / --only dae / --only package)
Status:  sh install.sh status
Uninstall: wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/uninstall.sh | sh
EOF
		;;
	*) die "unknown action: $ACTION" ;;
esac
