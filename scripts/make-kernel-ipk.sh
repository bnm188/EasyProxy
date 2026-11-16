#!/bin/sh
# Build an opkg .ipk for the proxy kernels out of the official upstream archives.
#
#   sh scripts/make-kernel-ipk.sh sing-box x86_64 dist
#   sh scripts/make-kernel-ipk.sh dae aarch64_cortex-a53 dist
#
# The kernels cannot live in `easyproxy_…_all.ipk`: one package serves every
# architecture, so an amd64 binary would be installed on ARM routers. Packaging
# them separately gives three independent packages - easyproxy, sing-box, dae -
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

SING_BOX_VER="${EP_SING_BOX_VER:-1.10.7}"
DAE_VER="${EP_DAE_VER:-2.1.2}"

usage() {
	cat <<'EOF'
make-kernel-ipk.sh <sing-box|dae> <arch> [out-dir]

  arch: x86_64 | aarch64_cortex-a53 | arm_cortex-a7_neon-vfpv4

Downloads the official upstream archive for that architecture, verifies its
sha256, and packs the binary (plus dae's routing assets) into an .ipk that opkg
can install next to easyproxy_<ver>.ipk.
EOF
}

case "$KERNEL" in
	sing-box|dae) : ;;
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
		dae:x86_64) printf '%s' x86_64 ;;
		dae:aarch64_cortex-a53) printf '%s' arm64 ;;
		dae:arm_cortex-a7_neon-vfpv4) printf '%s' armv7 ;;
	esac
}

pinned_sha() {
	case "$KERNEL:$(upstream_arch)" in
		sing-box:amd64) echo 1951a0785c8b4e1e21e0640227a49528ca772aec3d680061652e3d6b687e00fe ;;
		sing-box:arm64) echo 15b43a0a50b4e6962aca819d4f3055aaac75ca7481350d4aaebe93ed06b7af49 ;;
		sing-box:armv7) echo 691882d609c877f97bc8d6f8645b97d12de81b6f7b89651df66489ef11b4c5d0 ;;
		dae:x86_64) echo 37e19ce6abe12fe713a339d8a9335e10a5777c6d62613c5af91d64ca5bb3a56c ;;
		dae:arm64) echo 59979e524bb52a2634e11536def5db8efefba897ed6f565ea1d083221faf7709 ;;
		dae:armv7) echo 6c72afba36d4656c430f502c4615d505c6f681577d79de4c307a4be5bd7e8736 ;;
	esac
}

UARCH="$(upstream_arch)"
SHA="$(pinned_sha)"
[ -n "$UARCH" ] && [ -n "$SHA" ] || { echo "no upstream build for $KERNEL/$ARCH" >&2; exit 1; }

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

case "$KERNEL" in
	sing-box)
		VER="$SING_BOX_VER"
		URL="https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${UARCH}.tar.gz"
		FILE="$STAGE/archive.tar.gz" ;;
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

D="$STAGE/data"
mkdir -p "$D/usr/bin"
case "$KERNEL" in
	sing-box) mkdir -p "$STAGE/x" && tar -xzf "$FILE" -C "$STAGE/x" ;;
	dae)      mkdir -p "$STAGE/x" && tar -xJf "$FILE" -C "$STAGE/x" ;;
esac
SRC="$(find "$STAGE/x" -type f -name "$KERNEL" | head -1)"
[ -n "$SRC" ] || { echo "archive carries no $KERNEL binary" >&2; exit 1; }
head -c 4 "$SRC" | grep -q ELF || { echo "extracted $KERNEL is not an ELF binary" >&2; exit 1; }
install -m 0755 "$SRC" "$D/usr/bin/$KERNEL"

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
python3 - "$STAGE" "$IPK" <<'PY'
import os, sys, time
stage, out = sys.argv[1], sys.argv[2]
members = ["debian-binary", "control.tar.gz", "data.tar.gz"]
with open(out, "wb") as f:
    f.write(b"!<arch>\n")
    for m in members:
        path = os.path.join(stage, m)
        size = os.path.getsize(path)
        header = (m + "/").ljust(16).encode() + str(int(time.time())).ljust(12).encode() \
            + b"0".ljust(6) + b"0".ljust(6) + b"100644".ljust(8) \
            + str(size).ljust(10).encode() + b"`\n"
        f.write(header)
        with open(path, "rb") as g:
            f.write(g.read())
        if size % 2:
            f.write(b"\n")
PY

echo "built $IPK (kernel $KERNEL $VER, architecture ${ARCH}, upstream linux-${UARCH})"
