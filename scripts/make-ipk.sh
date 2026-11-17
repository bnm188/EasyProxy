#!/bin/sh
# Build an .ipk from package/easyproxy/files.
#
#   sh scripts/make-ipk.sh [PACKAGE_DIR] [OUT_DIR] [ARCH]
#   ARCH=x86_64 sh scripts/make-ipk.sh package/easyproxy dist
#
# Two layouts exist. Firmware built on 24.10+ expects a *gzip tar* holding
# ./debian-binary, ./control.tar.gz and ./data.tar.gz; older opkg wants the
# historical `ar` archive with the same three members. The modern layout is the
# default and `--ar` (or IPK_FORMAT=ar) switches back, because an ipk the
# target opkg calls "Malformed" is useless. The SDK build on CI already produces the native package for the
# target it was built against (apk on ImmortalWrt 25.x); this script produces
# the opkg-readable twin from the same files, so older opkg firmware can install
# the same release. Every file comes straight from package/easyproxy/files --
# nothing is compiled, which is why an `all` package is honest here.
#
# ARCH defaults to `all`. Some opkg builds refuse `Architecture: all` and demand
# an exact target name; passing `x86_64` (3rd argument or env) stamps that into
# the control member while the payload stays identical.

set -eu

FORMAT="${IPK_FORMAT:-tar}"
for a in "$@"; do
	case "$a" in
		--ar) FORMAT=ar ;;
		--tar) FORMAT=tar ;;
	esac
done

SRC_DIR="${1:-package/easyproxy}"
OUT_DIR="${2:-dist}"
ARCH="${3:-${ARCH:-all}}"
case "$ARCH" in
	all|x86_64|aarch64|armv7|armv7hf|mipsel|mips|riscv64) : ;;
	*) echo "unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac

VER="$(sed -n 's/^PKG_VERSION:=//p' "$SRC_DIR/Makefile" | head -1)"
REL="$(sed -n 's/^PKG_RELEASE:=//p' "$SRC_DIR/Makefile" | head -1)"
[ -n "$VER" ] || { echo "cannot read PKG_VERSION from $SRC_DIR/Makefile" >&2; exit 1; }
REL="${REL:-1}"
IPK="${OUT_DIR}/easyproxy_${VER}-${REL}_${ARCH}.ipk"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

D="$STAGE/data"
mkdir -p "$STAGE/control"
mkdir -p "$D/etc/config" "$D/etc/init.d" "$D/etc/hotplug.d/iface" "$D/usr/sbin" \
	"$D/usr/lib/easyproxy/adapters" \
	"$D/usr/share/easyproxy" \
	"$D/www/luci-static/resources/easyproxy" \
	"$D/www/luci-static/resources/view/easyproxy" \
	"$D/usr/share/luci/menu.d" "$D/usr/share/rpcd/acl.d" \
	"$D/usr/share/rpcd/ucode" \
	"$D/etc/easyproxy/ruleset"

F="$SRC_DIR/files"
install -m 0644 "$F/etc/config/easyproxy" "$D/etc/config/easyproxy"
install -m 0644 "$F/usr/share/easyproxy/easyproxy.default" "$D/usr/share/easyproxy/easyproxy.default"
install -m 0755 "$F/etc/init.d/easyproxy" "$D/etc/init.d/easyproxy"
install -m 0755 "$F/etc/hotplug.d/iface/95-easyproxy" "$D/etc/hotplug.d/iface/95-easyproxy"
install -m 0755 "$F/usr/sbin/easyproxy" "$D/usr/sbin/easyproxy"
# Every library in usr/lib/easyproxy is copied, not a hand-written list: a new
# library can no longer be missing from the opkg build while the SDK has it.
for lib in "$F"/usr/lib/easyproxy/*.sh; do
	install -m 0644 "$lib" "$D/usr/lib/easyproxy/$(basename "$lib")"
done
for adapter in "$F"/usr/lib/easyproxy/adapters/*.sh; do
	install -m 0644 "$adapter" "$D/usr/lib/easyproxy/adapters/$(basename "$adapter")"
done
# The panel now has a shared module plus ten thin views; copy both.
for js in "$F"/www/luci-static/resources/easyproxy/*.js; do
	install -m 0644 "$js" "$D/www/luci-static/resources/easyproxy/$(basename "$js")"
done
for view in "$F"/www/luci-static/resources/view/easyproxy/*; do
	install -m 0644 "$view" "$D/www/luci-static/resources/view/easyproxy/$(basename "$view")"
done
install -m 0644 "$F/usr/share/luci/menu.d/luci-app-easyproxy.json" \
	"$D/usr/share/luci/menu.d/luci-app-easyproxy.json"
install -m 0644 "$F/usr/share/rpcd/acl.d/luci-app-easyproxy.json" \
	"$D/usr/share/rpcd/acl.d/luci-app-easyproxy.json"
install -m 0644 "$F/usr/share/rpcd/ucode/luci.easyproxy.uc" \
	"$D/usr/share/rpcd/ucode/luci.easyproxy.uc"

SIZE="$(du -sk "$D" | awk '{print $1}')"
cat > "$STAGE/control/control" <<EOF
Package: easyproxy
Version: ${VER}-${REL}
Depends: uci, luci-base
Architecture: ${ARCH}
Maintainer: EasyProxy Contributors
Section: utils
Priority: optional
Installed-Size: ${SIZE}
Source: package/easyproxy
SourceName: easyproxy
License: MIT
Description: Modular proxy management framework for ImmortalWrt.
 Generates a split-routing sing-box config with local rule sets, captures LAN
 traffic through an nftables tproxy table (fully reversible), supervises the
 runtime through procd and shows live state in the LuCI panel.
EOF
printf '/etc/config/easyproxy\n' > "$STAGE/control/conffiles"

tar --owner=0 --group=0 --numeric-owner -czf "$STAGE/control.tar.gz" \
	-C "$STAGE/control" ./control ./conffiles
tar --owner=0 --group=0 --numeric-owner -czf "$STAGE/data.tar.gz" -C "$D" .
printf '2.0\n' > "$STAGE/debian-binary"

mkdir -p "$OUT_DIR"
python3 - "$STAGE" "$IPK" "$FORMAT" <<'PYWRITE'
import os, sys, time, tarfile
stage, out, fmt = sys.argv[1], sys.argv[2], sys.argv[3]
members = ["debian-binary", "control.tar.gz", "data.tar.gz"]

if fmt == "ar":
    # argparse-free ar writer: opkg wants the three members in this exact order
    # and no symbol table, which GNU ar may add.
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
else:
    # modern layout: an outer gzip tar holding the same three members, which
    # is what opkg on 24.10+ reads. control/data are already compressed, so
    # they go in as-is rather than being gzipped twice.
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
PYWRITE

echo "built $IPK (architecture ${ARCH}, format ${FORMAT})"
