#!/bin/sh
# Build an architecture-independent .ipk from package/easyproxy/files.
#
#   sh scripts/make-ipk.sh [PACKAGE_DIR] [OUT_DIR]
#
# OpenWrt's opkg is an `ar` archive holding debian-binary + control.tar.gz +
# data.tar.gz. The SDK build on CI already produces the native package for the
# target it was built against (apk on ImmortalWrt 25.x); this script produces
# the opkg-readable twin from the same files, so older opkg firmware can install
# the same release. Every file comes straight from package/easyproxy/files --
# nothing is compiled, which is why PKGARCH:=all is honest here.

set -eu

SRC_DIR="${1:-package/easyproxy}"
OUT_DIR="${2:-dist}"

VER="$(sed -n 's/^PKG_VERSION:=//p' "$SRC_DIR/Makefile" | head -1)"
REL="$(sed -n 's/^PKG_RELEASE:=//p' "$SRC_DIR/Makefile" | head -1)"
[ -n "$VER" ] || { echo "cannot read PKG_VERSION from $SRC_DIR/Makefile" >&2; exit 1; }
REL="${REL:-1}"
IPK="${OUT_DIR}/easyproxy_${VER}-${REL}_all.ipk"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

D="$STAGE/data"
mkdir -p "$STAGE/control"
mkdir -p "$D/etc/config" "$D/etc/init.d" "$D/usr/sbin" \
	"$D/usr/lib/easyproxy/adapters" \
	"$D/www/luci-static/resources/view/easyproxy" \
	"$D/usr/share/luci/menu.d" "$D/usr/share/rpcd/acl.d" \
	"$D/etc/easyproxy/ruleset"

F="$SRC_DIR/files"
install -m 0644 "$F/etc/config/easyproxy" "$D/etc/config/easyproxy"
install -m 0755 "$F/etc/init.d/easyproxy" "$D/etc/init.d/easyproxy"
install -m 0755 "$F/usr/sbin/easyproxy" "$D/usr/sbin/easyproxy"
for lib in common.sh config.sh transparent.sh; do
	install -m 0644 "$F/usr/lib/easyproxy/$lib" "$D/usr/lib/easyproxy/$lib"
done
for adapter in dae.sh sing-box.sh; do
	install -m 0644 "$F/usr/lib/easyproxy/adapters/$adapter" "$D/usr/lib/easyproxy/adapters/$adapter"
done
install -m 0644 "$F/www/luci-static/resources/view/easyproxy/overview.js" \
	"$D/www/luci-static/resources/view/easyproxy/overview.js"
install -m 0644 "$F/usr/share/luci/menu.d/luci-app-easyproxy.json" \
	"$D/usr/share/luci/menu.d/luci-app-easyproxy.json"
install -m 0644 "$F/usr/share/rpcd/acl.d/luci-app-easyproxy.json" \
	"$D/usr/share/rpcd/acl.d/luci-app-easyproxy.json"

SIZE="$(du -sk "$D" | awk '{print $1}')"
cat > "$STAGE/control/control" <<EOF
Package: easyproxy
Version: ${VER}-${REL}
Depends: uci, luci-base
Architecture: all
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
# argparse-free ar writer: opkg wants the three members in this exact order and
# no symbol table, which GNU ar may add.
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

echo "built $IPK"
