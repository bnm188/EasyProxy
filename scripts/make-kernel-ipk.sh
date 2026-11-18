#!/bin/sh
# Build an opkg .ipk for the proxy kernels out of the official upstream archives.
#
#   sh scripts/make-kernel-ipk.sh sing-box x86_64 dist
#   sh scripts/make-kernel-ipk.sh dae aarch64_cortex-a53 dist
#   sh scripts/make-kernel-ipk.sh mihomo x86_64 dist
#
# The kernels cannot live in `easyproxy_…_all.ipk`: one package serves every
# architecture, so an amd64 binary would be installed on ARM routers. Packaging
# them separately gives independent packages - easyproxy, sing-box, mihomo, dae -
# each upgradable and removable on its own while opkg keeps track of the files.
#
# Every archive is checked against the sha256 pinned below before anything is
# unpacked, the extracted file must be an ELF binary, and only then is it packed.
#
# Supported ipk architectures: x86_64, aarch64_cortex-a53,
# arm_cortex-a7_neon-vfpv4.

set -eu

KERNEL="${1:-}"
ARCH="${2:-}"
OUT_DIR="${3:-dist}"

SING_BOX_VER="${EP_SING_BOX_VER:-1.14.4}"
DAE_VER="${EP_DAE_VER:-2.1.2}"
MIHOMO_VER="${EP_MIHOMO_VER:-1.19.34}"

usage() {
	cat <<'EOF'
make-kernel-ipk.sh <sing-box|mihomo|dae> <arch> [out-dir]

  arch: x86_64 | aarch64_cortex-a53 | arm_cortex-a7_neon-vfpv4

Downloads the official upstream archive for that architecture, verifies its
sha256, and packs the binary into an .ipk that opkg can install next to
easyproxy_<ver>.ipk.

mihomo additionally carries its geodata (geoip.metadb): the engine downloads
that file on first start when the -d directory lacks it, which stalls a
firewalled or offline box for several seconds. Pass EP_META=<file> to package a
copy from this machine instead of fetching the latest from upstream.
EOF
}

case "$KERNEL" in
	sing-box|mihomo|dae) : ;;
	*) usage >&2; exit 2 ;;
esac
case "$ARCH" in
	x86_64|aarch64_cortex-a53|arm_cortex-a7_neon-vfpv4) : ;;
	*) echo "unsupported arch: $ARCH" >&2; usage >&2; exit 2 ;;
esac

# ipk arch -> upstream arch
upstream_arch() {
	case "$KERNEL:$ARCH" in
		sing-box:x86_64) printf '%s' amd64 ;;
		sing-box:aarch64_cortex-a53) printf '%s' arm64 ;;
		sing-box:arm_cortex-a7_neon-vfpv4) printf '%s' armv7 ;;
		mihomo:x86_64) printf '%s' amd64 ;;
		mihomo:aarch64_cortex-a53) printf '%s' arm64 ;;
		mihomo:arm_cortex-a7_neon-vfpv4) printf '%s' armv7 ;;
		dae:x86_64) printf '%s' x86_64 ;;
		dae:aarch64_cortex-a53) printf '%s' arm64 ;;
		dae:arm_cortex-a7_neon-vfpv4) printf '%s' armv7 ;;
	esac
}

pinned_sha() {
	case "$KERNEL:$(upstream_arch)" in
		sing-box:amd64) echo 699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968 ;;
		sing-box:arm64) echo 436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26 ;;
		sing-box:armv7) echo fd164ed45ebc784f657a3e1d0e0ad0f68afdcff864ee57122c2cfed3ddb80a00 ;;
		mihomo:amd64) echo 0c07340a01408d033dda4088ea2a4c1e4d82aeed7b2f84f7c046e93b6ff3290c ;;
		mihomo:arm64) echo daaf78a6240a282cdfd75bcbf98fe321f6bd52765cc29e79f344191198f0b50f ;;
		mihomo:armv7) echo aa5e51572e29ce22ace7b6e28e611e1f1f635210d76420d161ce12a5431bf93e ;;
		dae:x86_64) echo 37e19ce6abe12fe713a339d8a9335e10a5777c6d62613c5af91d64ca5bb3a56c ;;
		dae:arm64) echo 59979e524bb52a2634e11536def5db8efefba897ed6f565ea1d083221faf7709 ;;
		dae:armv7) echo 6c72afba36d4656c430f502c4615d505c6f681577d79de4c307a4be5bd7e8736 ;;
	esac
}

UARCH="$(upstream_arch)"
SHA="$(pinned_sha)"

# EP_SRC packages an engine binary that already exists on this machine.
#
# The official upstream linux-amd64 release is a glibc build. On a musl firmware
# it installs cleanly and then cannot exec: "required file not found", because
# the loader path the binary names does not exist. Verified on the Kwrt x86_64
# box - it has /lib/ld-musl-x86_64.so.1 and no glibc loader - so the downloaded
# engine ran nowhere while the musl-built engine already on the box ran fine.
# A musl target therefore needs EP_SRC; the upstream download path stays for
# targets that can run the official build.
if [ -n "${EP_SRC:-}" ]; then
	[ -r "$EP_SRC" ] || { echo "EP_SRC not readable: $EP_SRC" >&2; exit 2; }
	head -c 4 "$EP_SRC" | grep -q ELF || { echo "EP_SRC is not an ELF binary: $EP_SRC" >&2; exit 1; }
else
	[ -n "$UARCH" ] && [ -n "$SHA" ] || { echo "no upstream build for $KERNEL/$ARCH" >&2; exit 1; }
fi

fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		echo "need curl or wget" >&2
		exit 1
	fi
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT_DIR"

if [ -n "${EP_SRC:-}" ]; then
	# The engine reports its own version; EP_KERNEL_VER overrides it.
	# "-openbox-45" becomes "-ob45" because opkg splits the last dash into
	# version and release, and a stray dash makes upgrades compare wrongly.
	if [ "$KERNEL" = mihomo ]; then
		# `mihomo -v` prints "Mihomo Meta v1.19.34 linux amd64 with go1.22 ..."
		VER="${EP_KERNEL_VER:-$("$EP_SRC" -v 2>/dev/null | awk 'match($0, /v[0-9]+\.[0-9]+\.[0-9]+/) { s = substr($0, RSTART + 1, RLENGTH - 1); print s; exit }')}"
	else
		VER="${EP_KERNEL_VER:-$("$EP_SRC" version 2>/dev/null | awk '/^sing-box version/ {print $3; exit}')}"
	fi
	VER="$(printf '%s' "$VER" | sed 's/-openbox-/-ob/')"
	[ -n "$VER" ] || { echo "cannot read version from $EP_SRC; pass EP_KERNEL_VER" >&2; exit 3; }
	SRC="$EP_SRC"
	LOCAL=1
else
	LOCAL=0
	case "$KERNEL" in
		sing-box)
			VER="$SING_BOX_VER"
			URL="https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${UARCH}.tar.gz"
			FILE="$STAGE/archive.tar.gz" ;;
		mihomo)
			# amd64 ships v1/v2/v3 microarchitecture builds; v1 is the
			# portable one and the only one that runs on every x86_64 box.
			# arm builds are not split that way.
			VER="$MIHOMO_VER"
			case "$UARCH" in
				amd64) MFILE="mihomo-linux-amd64-v1-v${VER}.gz" ;;
				*)     MFILE="mihomo-linux-${UARCH}-v${VER}.gz" ;;
			esac
			URL="https://github.com/MetaCubeX/mihomo/releases/download/v${VER}/${MFILE}"
			FILE="$STAGE/archive.gz" ;;
		dae)
			VER="$DAE_VER"
			URL="https://github.com/daeuniverse/dae/releases/download/v${VER}/dae-linux-${UARCH}.tar.xz"
			FILE="$STAGE/archive.tar.xz" ;;
	esac

	echo "downloading $(basename "$URL")"
	fetch "$URL" "$FILE"
	GOT="$(sha256sum "$FILE" | awk '{ print $1 }')"
	[ "$GOT" = "$SHA" ] || { echo "sha256 mismatch for $(basename "$URL"): expected $SHA, got $GOT" >&2; exit 1; }
	echo "sha256 ok: $(basename "$URL")"
fi

D="$STAGE/data"
mkdir -p "$D/usr/bin"
if [ "$LOCAL" = 0 ]; then
	case "$KERNEL" in
		sing-box) mkdir -p "$STAGE/x" && tar -xzf "$FILE" -C "$STAGE/x" ;;
		mihomo)
			mkdir -p "$STAGE/x"
			gunzip -c "$FILE" > "$STAGE/x/mihomo" ;;
		dae)      mkdir -p "$STAGE/x" && tar -xJf "$FILE" -C "$STAGE/x" ;;
	esac
	SRC="$(find "$STAGE/x" -type f -name "$KERNEL" | head -1)"
	[ -n "$SRC" ] || { echo "archive carries no $KERNEL binary" >&2; exit 1; }
fi
head -c 4 "$SRC" | grep -q ELF || { echo "$KERNEL is not an ELF binary" >&2; exit 1; }
install -m 0755 "$SRC" "$D/usr/bin/$KERNEL"

if [ "$KERNEL" = mihomo ]; then
	# mihomo lazy-loads geodata on the first GEOIP rule hit and downloads it
	# when missing - 4.7 s on a box with internet, forever on one without.
	# Ship it inside the same package so installing the engine is enough.
	META="${EP_META:-}"
	METAFILE="$STAGE/geoip.metadb"
	[ -n "$META" ] || { META="$STAGE/dl-geoip.metadb"; fetch "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb" "$META"; }
	[ -r "$META" ] || { echo "geodata not readable: $META" >&2; exit 2; }
	METASIZE="$(wc -c < "$META" | tr -d ' ')"
	[ "$METASIZE" -gt 5000000 ] || { echo "geodata looks truncated: ${METASIZE} bytes" >&2; exit 1; }
	mkdir -p "$D/etc/easyproxy/mihomo"
	install -m 0644 "$META" "$D/etc/easyproxy/mihomo/geoip.metadb"
	echo "geodata bundled: geoip.metadb (${METASIZE} bytes)"
fi

if [ "$KERNEL" = dae ]; then
	mkdir -p "$D/usr/share/dae"
	for dat in "$STAGE/x"/usr/share/dae/*.dat; do
		[ -f "$dat" ] || continue
		install -m 0644 "$dat" "$D/usr/share/dae/$(basename "$dat")"
	done
fi

CTRL="$STAGE/control"
mkdir -p "$CTRL"
SIZE="$(du -sk "$D" | awk '{ print $1 }')"
case "$KERNEL" in
	sing-box) DESC="sing-box proxy kernel for ImmortalWrt (official upstream build).
 Installed separately from easyproxy so the kernel and the panel upgrade
 independently. EasyProxy drives it through easyproxy.sing_box.binary." ;;
	mihomo) DESC="mihomo (Clash.Meta) proxy kernel for ImmortalWrt.
 Statically linked upstream build, plus the geodata it would otherwise fetch on
 first start. Installed separately from easyproxy so the engine and the panel
 upgrade independently. EasyProxy drives it through easyproxy.mihomo.binary and
 generates Clash YAML through the mihomo adapter." ;;
	dae) DESC="dae proxy kernel for ImmortalWrt (official upstream build).
 Installed separately from easyproxy so the kernel and the panel upgrade
 independently. Ships the routing assets in /usr/share/dae; the runtime adapter
 is still 开发中, so EasyProxy keeps using sing-box until it is finished." ;;
esac

cat > "$CTRL/control" <<EOF
Package: ${KERNEL}
Version: ${VER}-1
Depends:
Architecture: ${ARCH}
Maintainer: EasyProxy Contributors
Section: net
Priority: optional
Installed-Size: ${SIZE}
SourceName: ${KERNEL}
License: $( [ "$KERNEL" = dae ] && echo 'GPL-3.0' || echo 'GPL-3.0-or-later' )
Description: ${DESC}
EOF

tar --owner=0 --group=0 --numeric-owner -czf "$STAGE/control.tar.gz" -C "$CTRL" ./control
tar --owner=0 --group=0 --numeric-owner -czf "$STAGE/data.tar.gz" -C "$D" .
printf '2.0\n' > "$STAGE/debian-binary"

IPK="$OUT_DIR/${KERNEL}_${VER}_${ARCH}.ipk"
# Container format matters: this script used to emit the legacy `ar` layout,
# and the target's opkg rejected a 27 MB package built that way with
# "pkg_init_from_file: Malformed package file" while a gzip-tar package of the
# same content installed fine. Keep the same outer layout as make-ipk.sh so both
# packages take the identical path on the box.
python3 - "$STAGE" "$IPK" <<'PY'
import os, sys, time, tarfile
stage, out = sys.argv[1], sys.argv[2]
members = ["debian-binary", "control.tar.gz", "data.tar.gz"]
with tarfile.open(out, "w:gz") as t:
    for m in members:
        path = os.path.join(stage, m)
        info = t.gettarinfo(path, arcname="./" + m)
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mtime = int(time.time())
        info.mode = 0o644
        with open(path, "rb") as g:
            t.addfile(info, g)
PY

echo "built $IPK (kernel $KERNEL $VER, architecture ${ARCH}, upstream linux-${UARCH})"
