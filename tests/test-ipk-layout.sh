#!/usr/bin/env sh
# The ipk that users actually install must carry everything the repo ships.
#
#   sh tests/test-ipk-layout.sh
#
# scripts/make-ipk.sh lists its installed files by hand, separately from the
# OpenWrt Makefile, so a new hook can silently be missing from the opkg twin
# while the SDK build has it. This suite packs the real package directory and
# asserts the payload - that is what closes the "restart recovery is in the
# release" gap for good.

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
[ -n "$IPK" ] && ok "产物是 .ipk（$(basename "$IPK")）" || no "产物是 .ipk" "$(ls "$OUT")"

mkdir -p "$OUT/x"
( cd "$OUT/x" && ar x "$IPK" ) >/dev/null 2>&1
[ -f "$OUT/x/data.tar.gz" ] && ok "ipk 内含 data.tar.gz" || no "ipk 内含 data.tar.gz"
[ -f "$OUT/x/control.tar.gz" ] && ok "ipk 内含 control.tar.gz" || no "ipk 内含 control.tar.gz"

tar tzf "$OUT/x/data.tar.gz" > "$OUT/list" 2>/dev/null
tar tvzf "$OUT/x/data.tar.gz" > "$OUT/detail" 2>/dev/null

want_file() {
	if grep -q "./$1/$\|./$1$" "$OUT/list"; then ok "包内含 $1"; else no "包内含 $1" "$(head -30 "$OUT/list")"; fi
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
want_file usr/lib/easyproxy/adapters/sing-box.sh
want_file etc/easyproxy/ruleset

# The rules shipped in the package must be the ones the repo edited: repack
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

# control metadata still names the right files
tar xzf "$OUT/x/control.tar.gz" -C "$OUT/x" >/dev/null 2>&1
grep -q '/etc/config/easyproxy' "$OUT/x/conffiles" 2>/dev/null && ok "control 声明 conffiles" || no "control 声明 conffiles"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
