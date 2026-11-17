#!/usr/bin/env sh
# The ipk that users actually install must carry everything the repo ships.
#
#   sh tests/test-ipk-layout.sh
#
# scripts/make-ipk.sh copies the installed files separately from the OpenWrt
# Makefile, so a new hook/library/view can silently be missing from the opkg twin
# while the SDK build has it. This suite packs the real package directory and
# asserts the payload, and it also asserts the architecture stamping (all vs a
# concrete target), which is what older opkg builds require.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

if ! sh "$SRC/scripts/make-ipk.sh" "$SRC/package/easyproxy" "$OUT" >"$OUT/log" 2>&1; then
	no "make-ipk.sh 能打出包" "$(cat "$OUT/log")"
	say ""
	say "结果：$PASS 通过，$FAIL 失败"
	exit 1
fi
ok "make-ipk.sh 打出了 ipk"

IPK="$(ls "$OUT"/*.ipk 2>/dev/null | head -1)"
[ -n "$IPK" ] && ok "产物是 .ipk（$(basename "$IPK")" || no "产物是 .ipk" "$(ls "$OUT")"

mkdir -p "$OUT/x"
# Two layouts are legal: the historical `ar` archive older opkg reads, and the
# gzip tar 24.10+ expects. Unpack whichever this build produced.
if head -c 8 "$IPK" | grep -q '!<arch>'; then
	FORMAT=ar
	( cd "$OUT/x" && ar x "$IPK" ) >/dev/null 2>&1
else
	FORMAT=tar
	tar -xzf "$IPK" -C "$OUT/x" >/dev/null 2>&1
fi
ok "ipk 布局可解包（$FORMAT）"
[ -f "$OUT/x/debian-binary" ] && ok "ipk 内含 debian-binary" || no "ipk 内含 debian-binary"
[ -f "$OUT/x/data.tar.gz" ] && ok "ipk 内含 data.tar.gz" || no "ipk 内含 data.tar.gz"
[ -f "$OUT/x/control.tar.gz" ] && ok "ipk 内含 control.tar.gz" || no "ipk 内含 control.tar.gz"

# Default build must be the modern layout, and --ar must still be available for
# firmware whose opkg rejects it.
if head -c 8 "$IPK" | grep -q '!<arch>'; then
	no "默认产物是新版 gzip-tar 布局" "头部是 ar"
else
	ok "默认产物是新版 gzip-tar 布局"
fi
if IPK_FORMAT=ar sh "$SRC/scripts/make-ipk.sh" "$SRC/package/easyproxy" "$OUT/ar" >"$OUT/ar.log" 2>&1 \
	&& head -c 8 "$OUT/ar"/*.ipk | grep -q '!<arch>'; then
	ok "--ar 仍能打旧版布局"
else
	no "--ar 仍能打旧版布局" "$(cat "$OUT/ar.log" 2>/dev/null)"
fi

tar tzf "$OUT/x/data.tar.gz" > "$OUT/list" 2>/dev/null
tar tvzf "$OUT/x/data.tar.gz" > "$OUT/detail" 2>/dev/null

want_file() {
	if grep -q "./$1/\$\|./$1$" "$OUT/list"; then ok "包内含 $1"; else no "包内含 $1" "$(head -30 "$OUT/list")"; fi
}
want_mode() {
	if awk -v p="./$1" '$NF == p { print $1 }' "$OUT/detail" | grep -q "^$2"; then
		ok "$1 权限为 $2"
	else
		no "$1 权限为 $2" "$(awk -v p="./$1" '$NF == p' "$OUT/detail")"
	fi
}

want_file etc/config/easyproxy
want_mode etc/config/easyproxy -rw-r--r--
want_file etc/init.d/easyproxy
want_mode etc/init.d/easyproxy -rwxr-xr-x
want_file etc/hotplug.d/iface/95-easyproxy
want_mode etc/hotplug.d/iface/95-easyproxy -rwxr-xr-x
want_file usr/sbin/easyproxy
want_mode usr/sbin/easyproxy -rwxr-xr-x
want_file usr/lib/easyproxy/transparent.sh
want_file usr/lib/easyproxy/config.sh
want_file usr/lib/easyproxy/common.sh
want_file usr/lib/easyproxy/node.sh
want_file usr/lib/easyproxy/maint.sh
want_file usr/lib/easyproxy/traffic.sh
want_file usr/lib/easyproxy/subscribe.sh
want_file usr/lib/easyproxy/adapters/sing-box.sh
want_file usr/share/easyproxy/easyproxy.default
want_file usr/share/luci/menu.d/luci-app-easyproxy.json
want_file usr/share/rpcd/acl.d/luci-app-easyproxy.json
want_file usr/share/rpcd/ucode/luci.easyproxy.uc
want_file www/luci-static/resources/easyproxy/app.js
want_file www/luci-static/resources/view/easyproxy/overview.js
want_file www/luci-static/resources/view/easyproxy/settings.js
want_file etc/easyproxy/ruleset

# The files shipped in the package must be the ones the repo edited: repack
# from a stale copy and the extraction below would not match.
mkdir -p "$OUT/d"
tar xzf "$OUT/x/data.tar.gz" -C "$OUT/d" >/dev/null 2>&1
if grep -q 'ep_ipv6_policy' "$OUT/d/usr/lib/easyproxy/transparent.sh" 2>/dev/null; then
	ok "包内的 transparent.sh 带 IPv6 策略实现"
else
	no "包内的 transparent.sh 带 IPv6 策略实现" "$(grep -c ipv6 "$OUT/d/usr/lib/easyproxy/transparent.sh" 2>/dev/null)"
fi
if grep -q 'transparent audit' "$OUT/d/usr/sbin/easyproxy" 2>/dev/null; then
	ok "包内的 CLI 带 transparent audit"
else
	no "包内的 CLI 带 transparent audit"
fi
if [ -s "$OUT/d/etc/hotplug.d/iface/95-easyproxy" ]; then
	ok "包内的 hotplug 钩子非空"
else
	no "包内的 hotplug 钩子非空"
fi
if grep -q 'ep_uninstall_clean' "$OUT/d/usr/lib/easyproxy/maint.sh" 2>/dev/null; then
	ok "包内的 maint.sh 带卸载清理实现"
else
	no "包内的 maint.sh 带卸载清理实现"
fi

# control metadata still names the right files
tar xzf "$OUT/x/control.tar.gz" -C "$OUT/x" >/dev/null 2>&1
grep -q '/etc/config/easyproxy' "$OUT/x/conffiles" 2>/dev/null && ok "control 声明 conffiles" || no "control 声明 conffiles"
grep -q '^Architecture: all$' "$OUT/x/control" 2>/dev/null && ok "默认包 Architecture: all" || no "默认包 Architecture: all" "$(grep Architecture "$OUT/x/control" 2>/dev/null)"

# The release also ships a package stamped for a concrete target: an opkg build
# that refuses `Architecture: all` installs only an exactly matching package.
mkdir -p "$OUT/x86"
if ARCH=x86_64 sh "$SRC/scripts/make-ipk.sh" "$SRC/package/easyproxy" "$OUT/x86" >"$OUT/x86.log" 2>&1; then
	ok "make-ipk.sh 能打出 x86_64 包"
else
	no "make-ipk.sh 能打出 x86_64 包" "$(cat "$OUT/x86.log")"
fi
XIPK="$(ls "$OUT/x86"/*_x86_64.ipk 2>/dev/null | head -1)"
[ -n "$XIPK" ] && ok "x86_64 产物文件名带 _x86_64" || no "x86_64 产物文件名带 _x86_64" "$(ls "$OUT/x86")"
if [ -n "$XIPK" ]; then
	mkdir -p "$OUT/x86u"
	if head -c 8 "$XIPK" | grep -q '!<arch>'; then
		( cd "$OUT/x86u" && ar x "$XIPK" ) >/dev/null 2>&1
	else
		tar -xzf "$XIPK" -C "$OUT/x86u" >/dev/null 2>&1
	fi
	tar xzf "$OUT/x86u/control.tar.gz" -C "$OUT/x86u" >/dev/null 2>&1
	grep -q '^Architecture: x86_64$' "$OUT/x86u/control" 2>/dev/null \
		&& ok "x86_64 包 Architecture 字段正确" || no "x86_64 包 Architecture 字段" "$(grep Architecture "$OUT/x86u/control" 2>/dev/null)"
	tar tzf "$OUT/x/data.tar.gz" 2>/dev/null | sort > "$OUT/l1"
	tar tzf "$OUT/x86u/data.tar.gz" 2>/dev/null | sort > "$OUT/l2"
	if diff "$OUT/l1" "$OUT/l2" >/dev/null 2>&1; then
		ok "x86_64 包与 all 包内文件一致"
	else
		no "x86_64 包与 all 包内文件一致" "$(diff "$OUT/l1" "$OUT/l2" | head -6)"
	fi
	grep -q 'Depends: uci, luci-base' "$OUT/x86u/control" 2>/dev/null \
		&& ok "x86_64 包保留依赖声明" || no "x86_64 包保留依赖声明" "$(grep Depends "$OUT/x86u/control" 2>/dev/null)"
fi

mkdir -p "$OUT/arm"
if ARCH=aarch64 sh "$SRC/scripts/make-ipk.sh" "$SRC/package/easyproxy" "$OUT/arm" >"$OUT/arm.log" 2>&1; then
	ok "同一脚本可打其他架构（aarch64）"
else
	no "同一脚本可打其他架构（aarch64）" "$(cat "$OUT/arm.log")"
fi
if ARCH=bogus sh "$SRC/scripts/make-ipk.sh" "$SRC/package/easyproxy" "$OUT/bogus" >"$OUT/bogus.log" 2>&1; then
	no "未知架构应被拒绝" "$(cat "$OUT/bogus.log")"
else
	grep -q 'unsupported ARCH' "$OUT/bogus.log" 2>/dev/null \
		&& ok "未知架构被明确拒绝" || no "未知架构被明确拒绝" "$(cat "$OUT/bogus.log")"
fi

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
