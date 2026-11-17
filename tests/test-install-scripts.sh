#!/usr/bin/env sh
# Suite for scripts/install.sh and scripts/uninstall.sh.
#
#   sh tests/test-install-scripts.sh
#
# Both scripts touch /etc, a package manager and rpcd on the target router. Here
# every one of those is a stub in a temp sandbox: `opkg`, `apk`, `curl`, `wget`,
# `uci`, the init script, rpcd, and easyproxy itself. Nothing outside the sandbox
# is read or written.
#
# Three components are covered: the easyproxy package, the sing-box kernel and
# the dae kernel - install, independent upgrade, rollback and removal.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/fix" "$SB/log" "$SB/root/etc" "$SB/opt" "$SB/backup"

# --- fixtures -------------------------------------------------------------
cat > "$SB/fix/api.json" <<'JSON'
{
  "tag_name": "v0.5.0",
  "assets": [
    { "name": "easyproxy-0.5.0-r1.apk", "browser_download_url": "https://example.test/dl/easyproxy-0.5.0-r1.apk" },
    { "name": "easyproxy-0.5.0-rootfs.tar.gz", "browser_download_url": "https://example.test/dl/easyproxy-0.5.0-rootfs.tar.gz" },
    { "name": "easyproxy_0.5.0-1_all.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.5.0-1_all.ipk" },
    { "name": "SHA256SUMS", "browser_download_url": "https://example.test/dl/SHA256SUMS" }
  ]
}
JSON

# A release that still carries an older same-named asset (the publish step
# uploaded dist/ wholesale once, so 0.8.11 rode along inside the 0.8.12
# release). The older asset is listed first, exactly as the API returned it.
cat > "$SB/fix/api-stale.json" <<'JSON'
{
  "tag_name": "v0.9.9",
  "assets": [
    { "name": "easyproxy_0.9.8-1_x86_64.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.9.8-1_x86_64.ipk" },
    { "name": "easyproxy_0.9.9-1_x86_64.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.9.9-1_x86_64.ipk" },
    { "name": "SHA256SUMS", "browser_download_url": "https://example.test/dl/SHA256SUMS" }
  ]
}
JSON
printf 'PKG_VERSION:=0.9.9\nPKG_RELEASE:=1\n' > "$SB/fix/Makefile"
printf 'APK-BYTES\n' > "$SB/fix/asset.apk"
{ printf '!<arch>\n'; printf 'IPK-BYTES\n'; } > "$SB/fix/asset.ipk"
tar -czf "$SB/fix/asset.tar.gz" --files-from /dev/null 2>/dev/null || tar -czf "$SB/fix/asset.tar.gz" -C "$SB" .
printf 'all 1\nx86_64 10\n' > "$SB/fix/opkg.arch"
: > "$SB/fix/SHA256SUMS"
h_ipk="$(sha256sum "$SB/fix/asset.ipk" | awk '{ print $1 }')"
h_apk="$(sha256sum "$SB/fix/asset.apk" | awk '{ print $1 }')"
h_tgz="$(sha256sum "$SB/fix/asset.tar.gz" | awk '{ print $1 }')"
for n in easyproxy_0.5.0-1_all.ipk easyproxy_0.5.0-1_x86_64.ipk easyproxy_0.9.9-1_all.ipk easyproxy_0.9.9-1_x86_64.ipk \
	sing-box_1.14.4_x86_64.ipk dae_2.1.2_x86_64.ipk; do
	printf '%s  %s\n' "$h_ipk" "$n" >> "$SB/fix/SHA256SUMS"
done
for n in easyproxy-0.5.0-r1.apk easyproxy-0.9.9-r1.apk; do
	printf '%s  %s\n' "$h_apk" "$n" >> "$SB/fix/SHA256SUMS"
done
for n in easyproxy-0.5.0-rootfs.tar.gz easyproxy-0.9.9-rootfs.tar.gz; do
	printf '%s  %s\n' "$h_tgz" "$n" >> "$SB/fix/SHA256SUMS"
done
sed 's/^[0-9a-f]/0/' "$SB/fix/SHA256SUMS" > "$SB/fix/SHA256SUMS.bad"

# Sums for the release that carries both 0.9.8 and 0.9.9 of the same package:
# everything the normal release publishes, plus the stale 0.9.8 entry.
{ cat "$SB/fix/SHA256SUMS"
  printf '%s  easyproxy_0.9.8-1_x86_64.ipk\n' "$h_ipk"; } > "$SB/fix/SHA256SUMS.stale"

# A real 24.10+ ipk: a gzip-tar holding debian-binary + control.tar.gz +
# data.tar.gz. scripts/make-ipk.sh emits this by default, so the installer's
# format check has to accept it - the historical `!<arch>` check cannot.
mkdir -p "$SB/fix/ipkdir/ctrl" "$SB/fix/ipkdir/data"
printf '2.0\n' > "$SB/fix/ipkdir/debian-binary"
printf 'Package: easyproxy\nVersion: 0.5.0-1\nArchitecture: x86_64\n' > "$SB/fix/ipkdir/ctrl/control"
printf '/etc/config/easyproxy\n' > "$SB/fix/ipkdir/ctrl/conffiles"
tar -czf "$SB/fix/ipkdir/control.tar.gz" -C "$SB/fix/ipkdir/ctrl" ./control ./conffiles
tar -czf "$SB/fix/ipkdir/data.tar.gz" -C "$SB/fix/ipkdir/data" .
tar -czf "$SB/fix/asset-targz.ipk" -C "$SB/fix/ipkdir" ./debian-binary ./control.tar.gz ./data.tar.gz
# Same gzip container without debian-binary: still not a valid ipk.
tar -czf "$SB/fix/asset-gzipbad.ipk" -C "$SB/fix/ipkdir" ./control.tar.gz ./data.tar.gz
h_targz="$(sha256sum "$SB/fix/asset-targz.ipk" | awk '{ print $1 }')"
h_gzipbad="$(sha256sum "$SB/fix/asset-gzipbad.ipk" | awk '{ print $1 }')"
{ printf '%s  easyproxy_0.5.0-1_x86_64.ipk\n' "$h_targz"
  printf '%s  easyproxy-0.5.0-rootfs.tar.gz\n' "$h_tgz"; } > "$SB/fix/SHA256SUMS.targz"
{ printf '%s  easyproxy_0.5.0-1_x86_64.ipk\n' "$h_gzipbad"
  printf '%s  easyproxy-0.5.0-rootfs.tar.gz\n' "$h_tgz"; } > "$SB/fix/SHA256SUMS.gzipbad"

# A release that also carries the kernel ipks, so the "prefer the kernel ipk"
# route can be exercised.
cat > "$SB/fix/api-kernels.json" <<'JSON'
{
  "tag_name": "v0.5.0",
  "assets": [
    { "name": "easyproxy_0.5.0-1_all.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.5.0-1_all.ipk" },
    { "name": "sing-box_1.14.4_x86_64.ipk", "browser_download_url": "https://example.test/dl/sing-box_1.14.4_x86_64.ipk" },
    { "name": "dae_2.1.2_x86_64.ipk", "browser_download_url": "https://example.test/dl/dae_2.1.2_x86_64.ipk" },
    { "name": "SHA256SUMS", "browser_download_url": "https://example.test/dl/SHA256SUMS" }
  ]
}
JSON

# A release carrying the architecture-specific ipk the layout cases install.
cat > "$SB/fix/api-x86.json" <<'JSON'
{
  "tag_name": "v0.5.0",
  "assets": [
    { "name": "easyproxy_0.5.0-1_x86_64.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.5.0-1_x86_64.ipk" },
    { "name": "easyproxy-0.5.0-rootfs.tar.gz", "browser_download_url": "https://example.test/dl/easyproxy-0.5.0-rootfs.tar.gz" },
    { "name": "SHA256SUMS", "browser_download_url": "https://example.test/dl/SHA256SUMS" }
  ]
}
JSON

# sing-box fixture: same layout as the official archive, and it answers
# `version` the way the real binary does.
mkdir -p "$SB/fix/singbox/sing-box-1.14.4-linux-amd64"
cat > "$SB/fix/singbox/sing-box-1.14.4-linux-amd64/sing-box" <<'STUB'
#!/bin/sh
echo "sing-box version 1.14.4"
STUB
chmod +x "$SB/fix/singbox/sing-box-1.14.4-linux-amd64/sing-box"
tar -czf "$SB/fix/sing-box.tar.gz" -C "$SB/fix/singbox" sing-box-1.14.4-linux-amd64
h_sb="$(sha256sum "$SB/fix/sing-box.tar.gz" | awk '{ print $1 }')"

# A kernel that installs but cannot run: the upgrade must roll it back.
mkdir -p "$SB/fix/singbox-broken/sing-box-1.14.4-linux-amd64"
cat > "$SB/fix/singbox-broken/sing-box-1.14.4-linux-amd64/sing-box" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$SB/fix/singbox-broken/sing-box-1.14.4-linux-amd64/sing-box"
tar -czf "$SB/fix/sing-box.broken.tar.gz" -C "$SB/fix/singbox-broken" sing-box-1.14.4-linux-amd64

# dae fixture: same layout as the official archive (binary + routing assets).
mkdir -p "$SB/fix/dae/usr/bin" "$SB/fix/dae/usr/share/dae"
cat > "$SB/fix/dae/usr/bin/dae" <<'STUB'
#!/bin/sh
echo "dae version v2.1.2"
STUB
chmod +x "$SB/fix/dae/usr/bin/dae"
printf 'GEOIP-BYTES\n' > "$SB/fix/dae/usr/share/dae/geoip.dat"
printf 'GEOSITE-BYTES\n' > "$SB/fix/dae/usr/share/dae/geosite.dat"
tar -cJf "$SB/fix/dae.tar.xz" -C "$SB/fix/dae" ./usr
h_dae="$(sha256sum "$SB/fix/dae.tar.xz" | awk '{ print $1 }')"

# --- stubs ----------------------------------------------------------------
cat > "$SB/bin/curl" <<'STUB'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
	case "$1" in
		-o) out="$2"; shift 2 ;;
		-*) shift ;;
		*) url="$1"; shift ;;
	esac
done
printf '%s\n' "$url" >> "$EP_TEST_LOG/curl.urls"
case "$url" in
	*releases/latest) [ -f "$EP_TEST_LOG/api.fail" ] && exit 22; f="${EP_TEST_API_FIX:-$EP_TEST_FIX/api.json}" ;;
	*SagerNet/sing-box*) [ -f "$EP_TEST_LOG/engine.fail" ] && exit 22; f="$EP_TEST_FIX/${EP_TEST_SB_ARCHIVE:-sing-box.tar.gz}" ;;
	*daeuniverse/dae*) [ -f "$EP_TEST_LOG/dae.fail" ] && exit 22; f="${EP_TEST_DAE_ARCHIVE:-$EP_TEST_FIX/dae.tar.xz}" ;;
	*Makefile) f="$EP_TEST_FIX/Makefile" ;;
	*.apk) f="$EP_TEST_FIX/asset.apk" ;;
	*_x86_64.ipk) [ -f "$EP_TEST_LOG/x86.fail" ] && exit 22; f="${EP_TEST_IPK:-$EP_TEST_FIX/asset.ipk}" ;;
	*.ipk) f="$EP_TEST_FIX/asset.ipk" ;;
	*SHA256SUMS) f="${EP_TEST_SUMS:-$EP_TEST_FIX/SHA256SUMS}" ;;
	*.tar.gz) f="$EP_TEST_FIX/asset.tar.gz" ;;
	*) exit 22 ;;
esac
if [ -n "$out" ]; then cp "$f" "$out"; else cat "$f"; fi
# A CDN edge can serve a stale object under an immutable release URL. flaky
# corrupts one download, flaky.always corrupts every one of them.
case "$url" in
	*SHA256SUMS|*releases/latest|*Makefile) ;;
	*)
		if [ -f "$EP_TEST_LOG/flaky" ]; then
			printf 'GARBAGE-BYTES\n' >> "$out"
			[ -f "$EP_TEST_LOG/flaky.always" ] || rm -f "$EP_TEST_LOG/flaky"
		fi ;;
esac
STUB
cat > "$SB/bin/uname" <<'STUB'
#!/bin/sh
printf '%s\n' "${EP_TEST_UNAME:-x86_64}"
STUB
cat > "$SB/bin/wget" <<'STUB'
#!/bin/sh
exit 22
STUB
cat > "$SB/bin/opkg" <<'STUB'
#!/bin/sh
printf 'opkg %s\n' "$*" >> "$EP_TEST_LOG/pm.log"
printf 'pm %s\n' "$*" >> "$EP_TEST_LOG/timeline"
case "$1" in
	"")
		# Bare `opkg` prints usage; the installer probes it for --force-architecture
		# because Kwrt 25.12 has no such option and calling it aborts the install.
		printf 'usage: opkg [options...] sub-command [arguments...]\n'
		if [ -n "${EP_TEST_OPKG_FORCE_ARCH:-}" ]; then
			printf '        --force-architecture  Install packages of foreign architecture\n'
		fi
		exit 1 ;;
	install)
		# Some builds refuse an ipk outright, e.g. "Malformed package file". EP_TEST_OPKG_REJECT makes this
		# stub do exactly that so the installer's fallback can be exercised.
		if [ -n "${EP_TEST_OPKG_REJECT:-}" ]; then
			printf 'Collected errors:\n * pkg_init_from_file: Malformed package file %s.\n' "${3:-$2}" >&2
			exit 1
		fi
		: > "$EP_TEST_LOG/installed" ;;
	print-architecture) cat "${EP_TEST_OPKG_ARCH:-$EP_TEST_FIX/opkg.arch}" ;;
	list-installed) printf 'easyproxy - %s\n' "${EP_TEST_PKG_VER:-0.5.0-1}" ;;
	remove) : ;;
esac
exit 0
STUB
cat > "$SB/bin/apk" <<'STUB'
#!/bin/sh
printf 'apk %s\n' "$*" >> "$EP_TEST_LOG/pm.log"
printf 'pm %s\n' "$*" >> "$EP_TEST_LOG/timeline"
: > "$EP_TEST_LOG/installed"
exit 0
STUB
cat > "$SB/bin/easyproxy" <<'STUB'
#!/bin/sh
printf 'easyproxy %s\n' "$*" >> "$EP_TEST_LOG/ep.log"
printf 'ep %s\n' "$*" >> "$EP_TEST_LOG/timeline"
case "$1" in
	status) printf 'engine: sing-box\nstate: idle\n' ;;
esac
exit 0
STUB
cat > "$SB/bin/uci" <<'STUB'
#!/bin/sh
printf 'uci ' >> "$EP_TEST_LOG/uci.log"
printf '%s ' "$@" >> "$EP_TEST_LOG/uci.log"
printf '\n' >> "$EP_TEST_LOG/uci.log"
case "$1" in
	get) exit 1 ;;
esac
exit 0
STUB
cat > "$SB/root/etc/init.d-easyproxy" <<'STUB'
#!/bin/sh
printf 'init %s\n' "$*" >> "$EP_TEST_LOG/init.log"
exit 0
STUB
cat > "$SB/root/etc/init.d-rpcd" <<'STUB'
#!/bin/sh
printf 'rpcd %s\n' "$*" >> "$EP_TEST_LOG/rpcd.log"
exit 0
STUB
chmod +x "$SB/bin/"* "$SB/root/etc/init.d-"*

export EP_TEST_LOG="$SB/log"
export EP_TEST_FIX="$SB/fix"
export PATH="$SB/bin:$PATH"
export EP_TMP="$SB/tmp"
export EP_INIT="$SB/root/etc/init.d-easyproxy"
export EP_BIN="$SB/bin/easyproxy"
export EP_RPCD="$SB/root/etc/init.d-rpcd"
export EP_ROOT="$SB/rootfs"
export EP_CFG="$SB/opt/config.easyproxy"
export EP_STATE_DIR="$SB/opt/easyproxy"
export EP_LUCI_CACHE="$SB/opt/luci-indexcache"
export EP_BACKUP_DIR="$SB/backup"
export EP_SING_BOX_SHA="$h_sb"
export EP_DAE_SHA="$h_dae"
mkdir -p "$EP_TMP" "$EP_STATE_DIR" "$EP_ROOT/usr/sbin" "$EP_ROOT/etc/init.d" "$EP_ROOT/var/log"
touch "$EP_CFG"
touch "$EP_LUCI_CACHE"

reset() {
	rm -rf "$SB/log" "$SB/tmp"
	mkdir -p "$SB/log" "$SB/tmp"
	rm -f "$EP_STATE_DIR/nftables.conf"
	# kernels and their ownership records start empty in every case
	rm -rf "$EP_ROOT/usr/bin" "$EP_ROOT/usr/share/dae" "$EP_STATE_DIR/owned" "$EP_STATE_DIR/backup"
	touch "$EP_CFG"
}

INSTALL="$SRC/scripts/install.sh"
UNINSTALL="$SRC/scripts/uninstall.sh"

# --- install: opkg host -----------------------------------------------
reset
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "opkg 主机：安装退出码 0" || no "opkg 主机：安装退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q 'install .*easyproxy.*\.ipk' "$EP_TEST_LOG/pm.log" 2>/dev/null \
	&& ok "opkg 主机：调用 opkg install 且装的是 ipk" || no "opkg 主机：调用 opkg install 且装的是 ipk" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"
grep -q '\.ipk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "opkg 主机：下载的是 ipk 资产" || no "opkg 主机：下载的是 ipk 资产" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"
[ -f "$EP_TEST_LOG/installed" ] && ok "opkg 主机：包管理器报告已安装" || no "opkg 主机：包管理器报告已安装"
grep -q 'init enable' "$EP_TEST_LOG/init.log" 2>/dev/null && ok "安装后注册开机启动" || no "安装后注册开机启动"
grep -q 'rpcd restart' "$EP_TEST_LOG/rpcd.log" 2>/dev/null && ok "安装后重启 rpcd" || no "安装后重启 rpcd"
grep -q 'easyproxy status' "$EP_TEST_LOG/ep.log" 2>/dev/null && ok "安装后打印状态" || no "安装后打印状态"
# The log can quote a node URL, and /var/log is world-readable on OpenWrt.
[ "$(stat -c %a "$EP_ROOT/var/log/easyproxy.log" 2>/dev/null)" = "600" ] \
	&& ok "安装后日志文件权限为 600" || no "安装后日志文件权限为 600" "$(ls -l "$EP_ROOT/var/log" 2>/dev/null)"

# --- install: apk-only host -------------------------------------------
reset
cp "$SB/bin/opkg" "$SB/opkg.apktest.saved"
rm -f "$SB/bin/opkg"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "apk 主机：安装退出码 0" || no "apk 主机：安装退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q 'apk add --allow-untrusted .*\.apk' "$EP_TEST_LOG/pm.log" 2>/dev/null \
	&& ok "apk 主机：apk add --allow-untrusted 且装的是 apk" || no "apk 主机：apk add 命令" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"
grep -q '\.apk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null && ok "apk 主机：下载的是 apk 资产" || no "apk 主机：下载的是 apk 资产"
cp "$SB/opkg.apktest.saved" "$SB/bin/opkg"

# --- install: API unavailable, falls back to raw Makefile version ------
reset
touch "$EP_TEST_LOG/api.fail"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "API 不可用时仍能安装（走版本号兜底）" || no "API 不可用时仍能安装" "rc=$rc $(cat "$SB/out")"
grep -q 'releases/download/v0\.9\.9/' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "兜底 URL 由 Makefile 版本拼出（0.9.9）" || no "兜底 URL 由 Makefile 版本拼出" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"

# --- install: release also carries an older same-named asset -----------
# 发布 v0.8.12 时把 dist/ 里 0.8.11 的 ipk 一起传了上去，API 按资产出现顺序
# 返回旧包在前；安装器若只取第一个匹配，真机就装到了旧版本。
reset
EP_TEST_API_FIX="$SB/fix/api-stale.json" EP_TEST_SUMS="$SB/fix/SHA256SUMS.stale" \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "残留旧资产：安装仍然成功" || no "残留旧资产：安装仍然成功" "rc=$rc $(cat "$SB/out")"
grep -q 'easyproxy_0\.9\.9-1_x86_64\.ipk' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "残留旧资产：下载的是版本号最大的 0.9.9" || no "残留旧资产：下载的是版本号最大的 0.9.9" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"
if grep -q 'easyproxy_0\.9\.8' "$EP_TEST_LOG/curl.urls" 2>/dev/null; then
	no "残留旧资产：不应下载旧包 0.9.8" "$(cat "$EP_TEST_LOG/curl.urls")"
else
	ok "残留旧资产：未下载旧包 0.9.8"
fi

# --- install: no package manager -------------------------------------
reset
mv "$SB/bin/opkg" "$SB/opkg.off"
mv "$SB/bin/apk" "$SB/apk.off"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "没有包管理器时拒绝安装（非 0）" || no "没有包管理器时拒绝安装" "rc=$rc $(cat "$SB/out")"
grep -qi 'opkg\|apk' "$SB/out" && ok "拒绝时说明缺少哪种包管理器" || no "拒绝时说明缺少哪种包管理器" "$(cat "$SB/out")"
mv "$SB/opkg.off" "$SB/bin/opkg"
mv "$SB/apk.off" "$SB/bin/apk"

# --- install: rootfs archive route -----------------------------------
reset
sh "$INSTALL" --rootfs > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--rootfs 走 tar 解包而不是包管理器" || no "--rootfs 走 tar 解包" "rc=$rc $(cat "$SB/out")"
grep -qE '^opkg install|^apk add' "$EP_TEST_LOG/pm.log" 2>/dev/null && no "--rootfs 不应调用包管理器安装" "$(cat "$EP_TEST_LOG/pm.log")" || ok "--rootfs 不调用包管理器安装"

# --- install: --help does nothing ------------------------------------
reset
sh "$INSTALL" --help > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'install.sh' "$SB/out" && ok "--help 打印用法并退出 0" || no "--help 打印用法并退出 0" "rc=$rc"
[ -f "$EP_TEST_LOG/curl.urls" ] && no "--help 不应联网" || ok "--help 不联网"

# --- install: two ipk assets, prefer the one matching this host --------
cat > "$SB/fix/api-two.json" <<'JSON'
{
  "tag_name": "v0.5.0",
  "assets": [
    { "name": "easyproxy_0.5.0-1_all.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.5.0-1_all.ipk" },
    { "name": "easyproxy_0.5.0-1_x86_64.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.5.0-1_x86_64.ipk" }
  ]
}
JSON
reset
EP_TEST_API_FIX="$SB/fix/api-two.json" EP_TEST_UNAME=x86_64 sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "双 ipk 时安装成功" || no "双 ipk 时安装成功" "rc=$rc $(cat "$SB/out")"
grep -q '_x86_64\.ipk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "x86_64 主机下载架构匹配的 ipk" || no "x86_64 主机下载架构匹配的 ipk" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"

reset
touch "$EP_TEST_LOG/x86.fail"
EP_TEST_API_FIX="$SB/fix/api-two.json" EP_TEST_UNAME=x86_64 sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "架构包 404 时退回 all 包仍能安装" || no "架构包 404 时退回 all 包仍能安装" "rc=$rc $(cat "$SB/out")"
grep -q '_all\.ipk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "退回时确实改用 all 地址" || no "退回时确实改用 all 地址" "$(cat "$EP_TEST_LOG/curl.urls")"

reset
printf 'all 1\nriscv64 10\n' > "$SB/fix/opkg.arch.rv"
EP_TEST_API_FIX="$SB/fix/api-two.json" EP_TEST_OPKG_ARCH="$SB/fix/opkg.arch.rv" sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "无匹配架构时仍能安装" || no "无匹配架构时仍能安装" "rc=$rc $(cat "$SB/out")"
grep -q '_all\.ipk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "无匹配架构时退回 all 包" || no "无匹配架构时退回 all 包" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"

# --- install: opkg knows its own architectures --------------------------
reset
EP_TEST_API_FIX="$SB/fix/api-two.json" EP_TEST_UNAME=aarch64 sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "按 opkg 架构选包时安装成功" || no "按 opkg 架构选包时安装成功" "rc=$rc $(cat "$SB/out")"
grep -q '_x86_64\.ipk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "信 opkg 的架构列表而不是 uname" || no "信 opkg 的架构列表而不是 uname" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"

reset
printf 'all 1\naarch64_cortex-a53 10\n' > "$SB/fix/opkg.arch.arm"
EP_TEST_API_FIX="$SB/fix/api-two.json" EP_TEST_OPKG_ARCH="$SB/fix/opkg.arch.arm" sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "无对应架构包时不装错包、退回 all" || no "无对应架构包时不装错包、退回 all" "rc=$rc $(cat "$SB/out")"
grep -q '_all\.ipk$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "退回的是 all 包" || no "退回的是 all 包" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"

# --- install: the release also carries dae/sing-box ipks ---------------
# Every kernel is published as `_x86_64.ipk` too, so a panel lookup that only
# matches `_x86_64.ipk$` picks dae's package first - the router downloaded
# dae_2.1.2_x86_64.ipk as the panel and then failed. The panel pattern must be
# anchored on the easyproxy prefix.
reset
cat > "$SB/fix/api-mixed.json" <<'JSON'
{
  "tag_name": "v0.8.2",
  "assets": [
    { "name": "dae_2.1.2_x86_64.ipk", "browser_download_url": "https://example.test/dl/dae_2.1.2_x86_64.ipk" },
    { "name": "sing-box_1.14.4_x86_64.ipk", "browser_download_url": "https://example.test/dl/sing-box_1.14.4_x86_64.ipk" },
    { "name": "easyproxy_0.8.2-1_x86_64.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.8.2-1_x86_64.ipk" }
  ]
}
JSON
EP_TEST_API_FIX="$SB/fix/api-mixed.json" EP_TEST_UNAME=x86_64 sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
grep -q 'easyproxy_0\.8\.2-1_x86_64\.ipk' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "面板下载的是 easyproxy 的架构包" || no "面板下载的是 easyproxy 的架构包" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"
grep -q 'dae_2\.1\.2_x86_64\.ipk' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& no "面板不去下载 dae 的架构包" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)" \
	|| ok "面板不去下载 dae 的架构包"

# --- install: an opkg that rejects all still gets the panel -------------
# Kwrt 25.12-SNAPSHOT ships an opkg that accepts only its own architecture
# (`riscv64` here) and refuses `Architecture: all`. The panel is a pure script
# package, so it installs with --force-architecture instead of failing.
reset
printf 'riscv64 10\n' > "$SB/fix/opkg.arch.noall"
cat > "$SB/fix/api-only-all.json" <<'JSON'
{
  "tag_name": "v0.5.0",
  "assets": [
    { "name": "easyproxy_0.5.0-1_all.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.5.0-1_all.ipk" }
  ]
}
JSON
EP_TEST_API_FIX="$SB/fix/api-only-all.json" EP_TEST_OPKG_ARCH="$SB/fix/opkg.arch.noall" EP_TEST_OPKG_FORCE_ARCH=1 \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "opkg 不收 all 时仍然装上面板（退出码 0）" || no "opkg 不收 all 时仍然装上面板" "rc=$rc $(cat "$SB/out")"
grep -q -- '--force-architecture' "$EP_TEST_LOG/pm.log" 2>/dev/null \
	&& ok "面板包用 --force-architecture 安装" || no "面板包用 --force-architecture 安装" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"
grep -qi 'force-architecture' "$SB/out" && ok "安装器说明了为什么强制架构" || no "安装器说明了为什么强制架构" "$(cat "$SB/out")"
if grep -q -- '--force-architecture' "$EP_TEST_LOG/pm.log" 2>/dev/null; then
	if grep -- '--force-architecture' "$EP_TEST_LOG/pm.log" | grep -qE 'sing-box|dae'; then
		no "内核包从不使用 --force-architecture" "$(grep -- '--force-architecture' "$EP_TEST_LOG/pm.log")"
	else
		ok "内核包从不使用 --force-architecture"
	fi
else
	no "内核包从不使用 --force-architecture" "没有强制架构的调用，断言无从校验"
fi

# --- install: an opkg with no --force-architecture (Kwrt 25.12) ----------
# The option does not exist there; passing it makes opkg print usage and abort,
# which the router showed. The installer must detect that and never pass it.
reset
EP_TEST_API_FIX="$SB/fix/api-only-all.json" EP_TEST_OPKG_ARCH="$SB/fix/opkg.arch.noall" \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "opkg 无 --force-architecture 时仍然装上面板（退出码 0）" || no "opkg 无 --force-architecture 时仍然装上面板" "rc=$rc $(cat "$SB/out")"
if grep -q -- '--force-architecture' "$EP_TEST_LOG/pm.log" 2>/dev/null; then
	no "opkg 不支持时不传 --force-architecture" "$(cat "$EP_TEST_LOG/pm.log")"
else
	ok "opkg 不支持时不传 --force-architecture"
fi
grep -qi 'rootfs' "$SB/out" && ok "不支持强制架构时改走 rootfs 归档" || no "不支持强制架构时改走 rootfs 归档" "$(cat "$SB/out")"

# --- install: --force-architecture refused, fall back to the archive -----
reset
EP_TEST_API_FIX="$SB/fix/api-only-all.json" EP_TEST_OPKG_ARCH="$SB/fix/opkg.arch.noall" EP_TEST_OPKG_REJECT=1 \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "opkg 拒绝强制架构后改用 rootfs 归档（退出码 0）" || no "opkg 拒绝强制架构后改用 rootfs 归档" "rc=$rc $(cat "$SB/out")"
grep -qi 'rootfs' "$SB/out" && ok "回退时说明了走 rootfs 归档" || no "回退时说明了走 rootfs 归档" "$(cat "$SB/out")"
grep -q 'easyproxy-.*-rootfs\.tar\.gz$' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "回退时下载了 rootfs 归档" || no "回退时下载了 rootfs 归档" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"

# --- install: an ipk the opkg parser calls malformed, replaced by the archive
reset
EP_TEST_OPKG_REJECT=1 sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "opkg 判 ipk 为 Malformed 时改用 rootfs 归档（退出码 0）" || no "opkg 判 Malformed 时改用 rootfs 归档" "rc=$rc $(cat "$SB/out")"
grep -qi 'rootfs archive' "$SB/out" && ok "回退时说明改走 rootfs 归档" || no "回退时说明改走 rootfs 归档" "$(cat "$SB/out")"

# --- install: the ipk layout the release actually ships (24.10+ gzip-tar)
# A gzip-tar ipk is what make-ipk.sh produces by default. Rejecting it would
# make every fresh install on every firmware fail, whatever the opkg can read.
reset
EP_TEST_IPK="$SB/fix/asset-targz.ipk" EP_TEST_SUMS="$SB/fix/SHA256SUMS.targz" EP_TEST_API_FIX="$SB/fix/api-x86.json" \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "gzip-tar 布局的 ipk：安装退出码 0" || no "gzip-tar 布局的 ipk：安装退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q 'is not an ipk archive' "$SB/out" \
	&& no "gzip-tar 布局不得被判为非 ipk 归档" "$(grep 'is not an ipk' "$SB/out")" \
	|| ok "gzip-tar 布局不被判为非 ipk 归档"
grep -q 'install .*easyproxy.*\.ipk' "$EP_TEST_LOG/pm.log" 2>/dev/null \
	&& ok "gzip-tar 布局：仍交给 opkg 安装" || no "gzip-tar 布局：仍交给 opkg 安装" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"

# --- install: gzip container that is not an ipk is still refused -------
reset
EP_TEST_IPK="$SB/fix/asset-gzipbad.ipk" EP_TEST_SUMS="$SB/fix/SHA256SUMS.gzipbad" EP_TEST_API_FIX="$SB/fix/api-x86.json" \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "缺 debian-binary 的 gzip 容器被拒绝（非 0）" || no "缺 debian-binary 的 gzip 容器被拒绝" "rc=$rc $(cat "$SB/out")"
grep -q 'is not an ipk archive' "$SB/out" \
	&& ok "拒绝原因指明不是 ipk 归档" || no "拒绝原因指明不是 ipk 归档" "$(cat "$SB/out")"
[ -f "$EP_TEST_LOG/installed" ] && no "被拒的容器不得交给包管理器" "" || ok "被拒的容器没有交给包管理器"

# --- install: never install a bad download ----------------------------
reset
EP_TEST_SUMS="$SB/fix/SHA256SUMS.bad" sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "校验和不符时拒绝安装（非 0）" || no "校验和不符时拒绝安装" "rc=$rc $(cat "$SB/out")"
grep -riq 'checksum' "$SB/out" && ok "拒绝原因提到校验和" || no "拒绝原因提到校验和" "$(cat "$SB/out")"
[ -f "$EP_TEST_LOG/installed" ] && no "校验失败时不应调用包管理器" || ok "校验失败时不调用包管理器"

reset
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "校验和对得上时正常安装" || no "校验和对得上时正常安装" "rc=$rc $(cat "$SB/out")"
grep -q 'sha256' "$SB/out" && ok "安装前打印了校验结果" || no "安装前打印了校验结果" "$(cat "$SB/out")"

# --- install: both kernels come with the package -----------------------
reset
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "默认安装：三个组件一起装好（退出码 0）" || no "默认安装三个组件" "rc=$rc $(cat "$SB/out")"
[ -x "$EP_ROOT/usr/bin/sing-box" ] && ok "sing-box 落在 usr/bin 且可执行" || no "sing-box 落在 usr/bin" "$(cat "$SB/out")"
[ -x "$EP_ROOT/usr/bin/dae" ] && ok "dae 落在 usr/bin 且可执行" || no "dae 落在 usr/bin" "$(cat "$SB/out")"
[ -f "$EP_ROOT/usr/share/dae/geoip.dat" ] && ok "dae 的路由资产一并装好" || no "dae 路由资产" "$(cat "$SB/out")"
grep -q 'SagerNet/sing-box' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "sing-box 从官方 release 下载" || no "sing-box 从官方 release 下载" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"
grep -q 'daeuniverse/dae' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& ok "dae 从官方 release 下载" || no "dae 从官方 release 下载" "$(cat "$EP_TEST_LOG/curl.urls" 2>/dev/null)"
grep -q 'sing-box sha256 ok' "$SB/out" && ok "sing-box 下载过 sha256" || no "sing-box 下载过 sha256" "$(cat "$SB/out")"
grep -q 'dae sha256 ok' "$SB/out" && ok "dae 下载过 sha256" || no "dae 下载过 sha256" "$(cat "$SB/out")"
grep -q 'sing-box: 1.14.4 runs' "$SB/out" && ok "装好的 sing-box 能报版本" || no "sing-box 能报版本" "$(cat "$SB/out")"
grep -q 'dae: 2.1.2 runs' "$SB/out" && ok "装好的 dae 能报版本" || no "dae 能报版本" "$(cat "$SB/out")"
grep -q 'sing_box.binary' "$EP_TEST_LOG/uci.log" 2>/dev/null && ok "uci 指向 sing-box" || no "uci 指向 sing-box" "$(cat "$EP_TEST_LOG/uci.log" 2>/dev/null)"
grep -q 'dae.binary' "$EP_TEST_LOG/uci.log" 2>/dev/null && ok "uci 指向 dae" || no "uci 指向 dae" "$(cat "$EP_TEST_LOG/uci.log" 2>/dev/null)"
[ -f "$EP_STATE_DIR/owned/sing-box" ] && [ -f "$EP_STATE_DIR/owned/dae" ] \
	&& ok "两个内核都登记了归属" || no "内核归属登记"

# --- install: component switches ---------------------------------------
reset
sh "$INSTALL" --no-dae > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--no-dae 仍能装好并退出 0" || no "--no-dae 安装" "rc=$rc $(cat "$SB/out")"
grep -q 'daeuniverse' "$EP_TEST_LOG/curl.urls" 2>/dev/null && no "--no-dae 不应下载 dae" || ok "--no-dae 跳过 dae"
[ -x "$EP_ROOT/usr/bin/sing-box" ] && ok "--no-dae 时 sing-box 照常安装" || no "--no-dae 时 sing-box 未安装"

reset
sh "$INSTALL" --no-sing-box > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--no-sing-box 仍能装好并退出 0" || no "--no-sing-box 安装" "rc=$rc $(cat "$SB/out")"
grep -q 'SagerNet' "$EP_TEST_LOG/curl.urls" 2>/dev/null && no "--no-sing-box 不应下载 sing-box" || ok "--no-sing-box 跳过 sing-box"
[ -x "$EP_ROOT/usr/bin/dae" ] && ok "--no-sing-box 时 dae 照常安装" || no "--no-sing-box 时 dae 未安装"

reset
sh "$INSTALL" --no-engine > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--no-engine 只装面板，退出 0" || no "--no-engine 安装" "rc=$rc $(cat "$SB/out")"
if grep -q 'SagerNet' "$EP_TEST_LOG/curl.urls" 2>/dev/null || grep -q 'daeuniverse' "$EP_TEST_LOG/curl.urls" 2>/dev/null; then
	no "--no-engine 不应下载任何内核"
else
	ok "--no-engine 跳过两个内核"
fi

# --- install: an already present kernel is reused ----------------------
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 1.14.4"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'sing-box: already present' "$SB/out" \
	&& ok "已有 sing-box 时复用、不重复下载" || no "已有 sing-box 时复用" "rc=$rc $(cat "$SB/out")"
grep -q 'dae: already present' "$SB/out" && ok "已有 dae 时复用" || no "已有 dae 时复用"
grep -q 'SagerNet' "$EP_TEST_LOG/curl.urls" 2>/dev/null \
	&& no "复用时不应再下载 sing-box" || ok "复用时没有重复下载"
[ -s "$EP_ROOT/usr/bin/dae" ] && grep -q 'dae version v2.1.2' "$EP_ROOT/usr/bin/dae" \
	&& ok "已有 dae 没有被覆盖" || no "已有 dae 被覆盖"

# --- install: kernel failures are reported, never hidden ---------------
reset
EP_SING_BOX_SHA=0000000000000000000000000000000000000000000000000000000000000000 \
	sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "sing-box 校验不符时安装报非 0" || no "sing-box 校验不符时报非 0" "rc=$rc $(cat "$SB/out")"
[ -e "$EP_ROOT/usr/bin/sing-box" ] && no "校验失败的 sing-box 不应落地" || ok "校验失败的 sing-box 不落地"
grep -q 'sing-box: install failed' "$SB/out" && ok "报错指明 sing-box 失败" || no "报错指明 sing-box 失败" "$(cat "$SB/out")"

reset
touch "$EP_TEST_LOG/engine.fail"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "sing-box 下载失败时安装报非 0" || no "sing-box 下载失败时报非 0" "rc=$rc $(cat "$SB/out")"
grep -q 'sing-box: install failed' "$SB/out" && ok "下载失败写明 sing-box 这一步" || no "下载失败写明 sing-box" "$(cat "$SB/out")"
[ -f "$EP_TEST_LOG/installed" ] && ok "内核失败不影响面板本体已安装" || no "内核失败时面板仍应安装"

reset
touch "$EP_TEST_LOG/dae.fail"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "dae 下载失败时安装报非 0" || no "dae 下载失败时报非 0" "rc=$rc $(cat "$SB/out")"
[ -x "$EP_ROOT/usr/bin/sing-box" ] && ok "dae 失败时 sing-box 仍装好" || no "dae 失败时 sing-box 未装"
grep -q 'dae: install failed' "$SB/out" && ok "报错指明 dae 这一步失败" || no "报错指明 dae 失败" "$(cat "$SB/out")"

# --- install: the release's kernel ipk is preferred over the archive ----
reset
EP_TEST_API_FIX="$SB/fix/api-kernels.json" sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "release 带内核 ipk 时安装成功" || no "release 带内核 ipk 时安装" "rc=$rc $(cat "$SB/out")"
grep -q 'sing-box_1.14.4_x86_64.ipk' "$EP_TEST_LOG/pm.log" 2>/dev/null \
	&& ok "sing-box 优先用 release 的内核 ipk" || no "sing-box 内核 ipk 未使用" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"
grep -q 'dae_2.1.2_x86_64.ipk' "$EP_TEST_LOG/pm.log" 2>/dev/null \
	&& ok "dae 优先用 release 的内核 ipk" || no "dae 内核 ipk 未使用" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"

# --- install: summary names all three components ------------------------
reset
sh "$INSTALL" > "$SB/out" 2>&1 || true
grep -q 'components:' "$SB/out" && ok "安装结果列出三个组件" || no "安装结果列组件" "$(cat "$SB/out")"
grep -q 'sing-box   1.14.4' "$SB/out" && grep -q 'dae        2.1.2' "$SB/out" \
	&& ok "摘要里两个内核都有版本号" || no "摘要缺内核版本" "$(cat "$SB/out")"

# --- upgrade: version table, then per-component upgrade -----------------
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 1.9.0"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.0"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
sh "$INSTALL" upgrade > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "一键升级全部组件退出 0" || no "一键升级退出码" "rc=$rc $(cat "$SB/out")"
grep -q 'component    current      newest' "$SB/out" && ok "升级前先打印版本对照表" || no "升级版本对照表" "$(cat "$SB/out")"
grep -q 'sing-box: 1.9.0 -> 1.14.4' "$SB/out" && ok "sing-box 显示旧 -> 新版本" || no "sing-box 版本变化" "$(cat "$SB/out")"
grep -q 'dae: 2.1.0 -> 2.1.2' "$SB/out" && ok "dae 显示旧 -> 新版本" || no "dae 版本变化" "$(cat "$SB/out")"
grep -q 'sing-box version 1.14.4' "$EP_ROOT/usr/bin/sing-box" && ok "sing-box 二进制已换新" || no "sing-box 未换新"
grep -q 'dae version v2.1.2' "$EP_ROOT/usr/bin/dae" && ok "dae 二进制已换新" || no "dae 未换新"
grep -q 'upgrade done' "$SB/out" && ok "升级结束有明确结论" || no "升级结论" "$(cat "$SB/out")"

# already up to date
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 1.14.4"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
sh "$INSTALL" upgrade > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'already up to date' "$SB/out" \
	&& ok "都已是新版本时不重复下载" || no "已是新版本时的处理" "rc=$rc $(cat "$SB/out")"
grep -q 'SagerNet' "$EP_TEST_LOG/curl.urls" 2>/dev/null && no "已是新版本时不应下载内核" || ok "已是新版本时没有下载"

# --only dae leaves sing-box alone
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 1.9.0"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.0"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
sh "$INSTALL" upgrade --only dae > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--only dae 只升级 dae" || no "--only dae" "rc=$rc $(cat "$SB/out")"
grep -q 'sing-box version 1.9.0' "$EP_ROOT/usr/bin/sing-box" && ok "--only dae 时 sing-box 保持原版本" || no "--only dae 动了 sing-box"
grep -q 'dae version v2.1.2' "$EP_ROOT/usr/bin/dae" && ok "--only dae 时 dae 升级到新版本" || no "--only dae 未升级 dae"

# --only package upgrades just the panel
reset
EP_TEST_PKG_VER=0.4.0-1 sh "$INSTALL" upgrade --only package > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--only package 升级面板并退出 0" || no "--only package" "rc=$rc $(cat "$SB/out")"
grep -q 'easyproxy: 0.4.0-1 -> 0.5.0' "$SB/out" && ok "面板升级显示版本变化" || no "面板版本变化" "$(cat "$SB/out")"
grep -q 'SagerNet' "$EP_TEST_LOG/curl.urls" 2>/dev/null && no "--only package 不应下载内核" || ok "--only package 不碰内核"

# a broken new kernel is rolled back
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 1.9.0"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
EP_TEST_SB_ARCHIVE=sing-box.broken.tar.gz sh "$INSTALL" upgrade --only sing-box > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "新内核跑不起来时升级报非 0" || no "坏内核升级退出码" "rc=$rc $(cat "$SB/out")"
grep -q 'restored' "$SB/out" && ok "坏内核回滚到旧版本" || no "回滚提示" "$(cat "$SB/out")"
grep -q 'sing-box version 1.9.0' "$EP_ROOT/usr/bin/sing-box" && ok "回滚后旧内核恢复可用" || no "回滚未恢复旧内核"
grep -q 'upgrade incomplete' "$SB/out" && ok "升级失败写明哪个组件" || no "升级失败说明" "$(cat "$SB/out")"

# --- status -------------------------------------------------------------
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 1.14.4"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
sh "$INSTALL" status > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "status 退出 0" || no "status 退出码" "rc=$rc $(cat "$SB/out")"
grep -q 'easyproxy  0.5.0-1' "$SB/out" && ok "status 报面板版本" || no "status 面板版本" "$(cat "$SB/out")"
grep -q 'sing-box   1.14.4' "$SB/out" && ok "status 报 sing-box 版本" || no "status sing-box" "$(cat "$SB/out")"
grep -q 'dae        2.1.2' "$SB/out" && ok "status 报 dae 版本" || no "status dae" "$(cat "$SB/out")"

# --- uninstall --------------------------------------------------------
reset
printf 'nft\n' > "$EP_STATE_DIR/nftables.conf"
printf 'config\n' > "$EP_CFG"
sh "$UNINSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "卸载退出码 0" || no "卸载退出码 0" "rc=$rc $(cat "$SB/out")"
grep -Eq 'easyproxy (uninstall-clean|transparent remove)' "$EP_TEST_LOG/ep.log" 2>/dev/null \
	&& ok "卸载前先撤销透明代理抓包" || no "卸载前先撤销透明代理抓包" "$(cat "$EP_TEST_LOG/ep.log" 2>/dev/null)"
# order: capture removal must come before the package manager runs
tl_rm="$(grep -En 'ep (uninstall-clean|transparent remove)' "$EP_TEST_LOG/timeline" 2>/dev/null | head -1 | cut -d: -f1)"
tl_pm="$(grep -n 'pm remove easyproxy' "$EP_TEST_LOG/timeline" 2>/dev/null | cut -d: -f1)"
[ -n "$tl_rm" ] && [ -n "$tl_pm" ] && [ "$tl_rm" -lt "$tl_pm" ] \
	&& ok "撤销抓包发生在包管理器卸载之前" || no "撤销抓包顺序" "rm=$tl_rm pm=$tl_pm"
grep -q 'init stop' "$EP_TEST_LOG/init.log" 2>/dev/null && ok "卸载时停止服务" || no "卸载时停止服务"
grep -q 'remove easyproxy' "$EP_TEST_LOG/pm.log" 2>/dev/null && ok "调用 opkg remove easyproxy" || no "调用 opkg remove easyproxy" "$(cat "$EP_TEST_LOG/pm.log" 2>/dev/null)"
[ -f "$EP_CFG" ] && ok "默认保留配置文件（未 --purge）" || no "默认保留配置文件"
[ -f "$EP_STATE_DIR/nftables.conf" ] && ok "默认保留状态目录（未 --purge）" || no "默认保留状态目录"

# backup is written before anything is removed
rm -f "$EP_BACKUP_DIR"/*.tar.gz 2>/dev/null
sh "$UNINSTALL" > "$SB/out" 2>&1
bkp="$(ls "$EP_BACKUP_DIR"/easyproxy-backup-*.tar.gz 2>/dev/null | head -1)"
[ -n "$bkp" ] && ok "卸载前先写配置备份" || no "卸载未写备份"
[ -n "$bkp" ] && tar -tzf "$bkp" >/dev/null 2>&1 && ok "备份文件是有效的 tar.gz" || no "备份文件损坏"
grep -q "backup: $bkp" "$SB/out" && ok "输出里给出备份路径" || no "备份路径未提示" "$(cat "$SB/out")"

rm -f "$EP_BACKUP_DIR"/*.tar.gz 2>/dev/null
sh "$UNINSTALL" --no-backup > "$SB/out" 2>&1
bkp="$(ls "$EP_BACKUP_DIR"/easyproxy-backup-*.tar.gz 2>/dev/null | head -1)"
[ -z "$bkp" ] && ok "--no-backup 不写备份" || no "--no-backup 仍写了备份"

# kernels this installer installed are removed; --keep-kernels keeps them
reset
mkdir -p "$EP_ROOT/usr/bin" "$EP_STATE_DIR/owned"
printf '#!/bin/sh\necho "sing-box version 1.14.4"\n' > "$EP_ROOT/usr/bin/sing-box"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/sing-box" "$EP_ROOT/usr/bin/dae"
printf '%s\n' "$EP_ROOT/usr/bin/sing-box" > "$EP_STATE_DIR/owned/sing-box"
printf '%s\n' "$EP_ROOT/usr/bin/dae" > "$EP_STATE_DIR/owned/dae"
sh "$UNINSTALL" > "$SB/out" 2>&1
[ -e "$EP_ROOT/usr/bin/sing-box" ] && no "自己装的内核应随手卸掉" || ok "自己装的 sing-box 随卸载移除"
[ -e "$EP_ROOT/usr/bin/dae" ] && no "自己装的 dae 应随手卸掉" || ok "自己装的 dae 随卸载移除"

reset
mkdir -p "$EP_ROOT/usr/bin" "$EP_STATE_DIR/owned"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$EP_ROOT/usr/bin/dae"
chmod +x "$EP_ROOT/usr/bin/dae"
printf '%s\n' "$EP_ROOT/usr/bin/dae" > "$EP_STATE_DIR/owned/dae"
sh "$UNINSTALL" --keep-kernels > "$SB/out" 2>&1
[ -x "$EP_ROOT/usr/bin/dae" ] && ok "--keep-kernels 保留内核" || no "--keep-kernels 仍删了内核"

# a kernel the user installed themselves has no ownership record: never touched
reset
mkdir -p "$EP_ROOT/usr/bin"
printf '#!/bin/sh\necho "sing-box version 2.0.0"\n' > "$EP_ROOT/usr/bin/sing-box"
chmod +x "$EP_ROOT/usr/bin/sing-box"
sh "$UNINSTALL" > "$SB/out" 2>&1
[ -x "$EP_ROOT/usr/bin/sing-box" ] && ok "没有归属记录的内核不被删除" || no "用户自装的内核被误删"

# --- uninstall --purge ------------------------------------------------
reset
printf 'nft\n' > "$EP_STATE_DIR/nftables.conf"
printf 'config\n' > "$EP_CFG"
sh "$UNINSTALL" --purge > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--purge 退出码 0" || no "--purge 退出码 0" "rc=$rc $(cat "$SB/out")"
[ -f "$EP_CFG" ] && no "--purge 应删除配置文件" || ok "--purge 删除配置文件"
[ -d "$EP_STATE_DIR" ] && no "--purge 应删除状态目录" || ok "--purge 删除状态目录"
grep -q 'rpcd restart' "$EP_TEST_LOG/rpcd.log" 2>/dev/null && ok "卸载后重启 rpcd" || no "卸载后重启 rpcd"

reset
printf 'config\n' > "$EP_CFG"
sh "$UNINSTALL" --keep-config > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -f "$EP_CFG" ] && ok "--keep-config 明确保留配置" || no "--keep-config" "rc=$rc $(cat "$SB/out")"

# --- uninstall on a host with no easyproxy at all ---------------------
reset
mv "$EP_BIN" "$SB/ep.off"
sh "$UNINSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "没装过时卸载仍返回 0（幂等）" || no "没装过时卸载仍返回 0" "rc=$rc $(cat "$SB/out")"
mv "$SB/ep.off" "$EP_BIN"

# --- a bad download is retried, then installed ----------------------------
# A CDN edge can hand back a stale object under an immutable release URL. The
# retry is part of the installer, not of the mirror, so one corrupt download
# must still end in a complete install.
reset
: > "$EP_TEST_LOG/flaky"
sh "$INSTALL" --rootfs > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "坏包重试后安装成功（退出码 0）" || no "坏包重试后安装成功" "rc=$rc $(cat "$SB/out")"
grep -q 'attempt 2 of 3' "$SB/out" && ok "打印了第 2 次尝试" || no "打印了第 2 次尝试" "$(cat "$SB/out")"
grep -q 'extracting at' "$SB/out" && ok "拿到正确文件后才解包" || no "拿到正确文件后才解包" "$(cat "$SB/out")"

# --- a bad download that never clears is a hard failure -------------------
reset
: > "$EP_TEST_LOG/flaky"; : > "$EP_TEST_LOG/flaky.always"
sh "$INSTALL" --rootfs > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "持续坏包时安装失败（退出码非 0）" || no "持续坏包时安装失败" "rc=$rc $(cat "$SB/out")"
grep -q 'checksum mismatch' "$SB/out" && ok "报错写明 checksum mismatch" || no "报错写明 checksum mismatch" "$(cat "$SB/out")"
grep -q 'attempt 3 of 3' "$SB/out" && ok "最多重试到第 3 次" || no "最多重试到第 3 次" "$(cat "$SB/out")"
grep -q 'extracting at' "$SB/out" && no "坏包不得解包" "" || ok "坏包没有解包（什么都没装）"

# --- kernel: adopt a static binary another package installed ---------------
# The upstream sing-box build is glibc and cannot exec on musl firmware, so a
# working binary already on the box is worth more than a download. This is the
# Open-Box case: /opt/open-box/bin/sing-box running 1.14.4.
reset
mkdir -p "$EP_ROOT/opt/open-box/bin"
cat > "$EP_ROOT/opt/open-box/bin/sing-box" <<'STUB'
#!/bin/sh
echo "sing-box version 1.14.4-openbox-45"
STUB
chmod +x "$EP_ROOT/opt/open-box/bin/sing-box"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "已有静态内核：安装退出码 0" || no "已有静态内核：安装退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q 'found a working static binary' "$SB/out" && ok "探测到已有静态内核并报告路径" || no "探测到已有静态内核" "$(cat "$SB/out")"
grep -q 'adopting it instead of downloading' "$SB/out" && ok "改为采用而不是下载" || no "改为采用而不是下载" "$(cat "$SB/out")"
grep -q 'SagerNet/sing-box' "$EP_TEST_LOG/curl.urls" 2>/dev/null && no "采用后不应再下载 sing-box" "$(cat "$EP_TEST_LOG/curl.urls")" || ok "采用后没有下载 sing-box"
grep -q 'easyproxy.sing_box.binary.*opt/open-box/bin/sing-box' "$EP_TEST_LOG/uci.log" 2>/dev/null 	&& ok "uci 指向被采用的内核" || no "uci 指向被采用的内核" "$(cat "$EP_TEST_LOG/uci.log" 2>/dev/null)"
grep -q 'opt/open-box/bin/sing-box' "$EP_STATE_DIR/owned/sing-box" 2>/dev/null 	&& no "被采用的内核不得记为安装器所有（卸载会误删）" "" || ok "被采用的内核不记为安装器所有"

# --- coexistence: another proxy already owns nft tables --------------------
reset
mkdir -p "$SB/bin2"
cat > "$SB/bin2/nft" <<'STUB'
#!/bin/sh
printf 'table inet openbox\n'
printf 'table inet dnsmasq\n'
STUB
chmod +x "$SB/bin2/nft"
PATH="$SB/bin2:$PATH" sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "已有其他代理时仍能安装" || no "已有其他代理时仍能安装" "rc=$rc $(cat "$SB/out")"
grep -q 'another proxy is already active' "$SB/out" && ok "提示已有其他代理在运行" || no "提示已有其他代理在运行" "$(cat "$SB/out")"
grep -q 'openbox' "$SB/out" && ok "提示里指出具体的冲突服务名" || no "提示里指出具体的冲突服务名" "$(cat "$SB/out")"
rm -rf "$SB/bin2"

# --- diag: WebDAV config handed to the installer ------------------------
reset
rm -f "$EP_ROOT/etc/easyproxy/diag.pass"
sh "$INSTALL" install --diag-webdav 'https://dav.example.com/dav/EP/' \
	--diag-user 'ops@example.com' --diag-pass 'sekret123' > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "diag：带参数安装退出码 0" || no "diag：带参数安装退出码 0" "rc=$rc $(cat "$SB/out")"
[ "$(sed -n '1p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "https://dav.example.com/dav/EP/" ] \
	&& ok "diag：地址写入配置文件第一行" \
	|| no "diag：地址写入配置文件第一行" "$(cat "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
[ "$(sed -n '2p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "ops@example.com" ] \
	&& ok "diag：账号写入配置文件第二行" \
	|| no "diag：账号写入配置文件第二行" "$(cat "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
[ "$(sed -n '3p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "sekret123" ] \
	&& ok "diag：密码写入配置文件第三行" \
	|| no "diag：密码写入配置文件第三行" "$(cat "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
[ "$(stat -c %a "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "600" ] \
	&& ok "diag：配置文件权限为 600" \
	|| no "diag：配置文件权限为 600" "$(stat -c %a "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
grep -q 'diag_webdav' "$EP_TEST_LOG/uci.log" 2>/dev/null \
	&& no "diag：地址不写进 uci" "$(cat "$EP_TEST_LOG/uci.log")" || ok "diag：地址不写进 uci"
grep -q 'diag_user' "$EP_TEST_LOG/uci.log" 2>/dev/null \
	&& no "diag：账号不写进 uci（root 可直接读 uci）" "$(cat "$EP_TEST_LOG/uci.log")" || ok "diag：账号不写进 uci"
# A machine that is handed over should report on its own: the daily job is
# switched on at install time, so nobody has to press anything afterwards.
grep -q 'diag --daily on' "$EP_TEST_LOG/ep.log" 2>/dev/null \
	&& ok "diag：安装时开启每日自动上报" || no "diag：安装时开启每日自动上报" "$(cat "$EP_TEST_LOG/ep.log" 2>/dev/null)"
grep -q 'daily report enabled' "$SB/out" && ok "diag：输出说明已开启自动上报" || no "diag：输出说明已开启自动上报" "$(cat "$SB/out")"
grep -q 'sekret123' "$SB/out" && no "diag：终端输出不回显密码" "$(cat "$SB/out")" || ok "diag：终端输出不回显密码"
grep -q 'sekret123' "$EP_TEST_LOG/uci.log" 2>/dev/null \
	&& no "diag：密码不写进 uci" "$(cat "$EP_TEST_LOG/uci.log" 2>/dev/null)" || ok "diag：密码不写进 uci"

# password may come from a file so that `history`/`ps` never hold it
reset
rm -f "$EP_ROOT/etc/easyproxy/diag.pass"
printf '%s' 'from-file' > "$SB/pw"
sh "$INSTALL" install --diag-webdav 'https://dav.example.com/dav/EP/' \
	--diag-user 'ops@example.com' --diag-pass-file "$SB/pw" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "diag：--diag-pass-file 安装退出码 0" || no "diag：--diag-pass-file" "rc=$rc $(cat "$SB/out")"
[ "$(sed -n '3p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "from-file" ] \
	&& ok "diag：从文件读取应用密码" || no "diag：从文件读取应用密码"

# without the flags nothing is written - default behaviour unchanged
reset
rm -rf "$EP_ROOT/etc/easyproxy"
sh "$INSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "diag：不带参数照常安装" || no "diag：不带参数照常安装" "rc=$rc $(cat "$SB/out")"
[ ! -f "$EP_ROOT/etc/easyproxy/diag.conf" ] \
	&& ok "diag：不带参数不创建配置文件" || no "diag：不带参数不创建配置文件"
grep -q 'diag --daily on' "$EP_TEST_LOG/ep.log" 2>/dev/null \
	&& no "diag：不带参数不开自动上报" "$(cat "$EP_TEST_LOG/ep.log")" || ok "diag：不带参数不开自动上报"

# partial flags must fail loudly instead of installing half-configured
reset
sh "$INSTALL" install --diag-webdav 'https://dav.example.com/dav/EP/' > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "diag：只给地址不给账号密码时报错退出" || no "diag：参数不全应报错" "rc=$rc"
grep -q 'diag-user' "$SB/out" && ok "diag：报错点名缺失的参数" || no "diag：报错点名缺失的参数" "$(cat "$SB/out")"

# --- diag: everything from one file, nothing on the command line --------
reset
rm -f "$EP_ROOT/etc/easyproxy/diag.pass"
printf '%s\n%s\n%s\n' 'https://dav.example.com/dav/EP/' 'ops@example.com' 'secret-cfg' > "$SB/diag.cfg"
sh "$INSTALL" install --diag-config "$SB/diag.cfg" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "diag-config：安装退出码 0" || no "diag-config：安装退出码 0" "rc=$rc $(cat "$SB/out")"
[ "$(sed -n '3p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "secret-cfg" ] \
	&& ok "diag-config：密码取自第三行" || no "diag-config：密码取自第三行" "$(cat "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
[ "$(sed -n '1p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "https://dav.example.com/dav/EP/" ] \
	&& ok "diag-config：地址取自第一行" || no "diag-config：地址取自第一行" "$(cat "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
[ "$(sed -n '2p' "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "ops@example.com" ] \
	&& ok "diag-config：账号取自第二行" || no "diag-config：账号取自第二行" "$(cat "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)"
[ "$(stat -c %a "$EP_ROOT/etc/easyproxy/diag.conf" 2>/dev/null)" = "600" ] \
	&& ok "diag-config：配置文件权限为 600" || no "diag-config：配置文件权限为 600"
grep -q 'ops@example.com' "$SB/out" && no "diag-config：输出不回显账号" "$(cat "$SB/out")" || ok "diag-config：输出不回显账号"
grep -q 'secret-cfg' "$SB/out" && no "diag-config：输出不回显密码" "$(cat "$SB/out")" || ok "diag-config：输出不回显密码"

# a short config file must be rejected, not half-installed
reset
printf '%s\n%s\n' 'https://dav.example.com/dav/EP/' 'ops@example.com' > "$SB/diag.cfg"
sh "$INSTALL" install --diag-config "$SB/diag.cfg" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "diag-config：只有两行时报错退出" || no "diag-config：只有两行应报错" "rc=$rc"
grep -q 'three lines' "$SB/out" && ok "diag-config：报错说明需要三行" || no "diag-config：报错说明需要三行" "$(cat "$SB/out")"

# a missing file must be rejected too
reset
sh "$INSTALL" install --diag-config "$SB/nope.cfg" > "$SB/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "diag-config：文件不存在时报错退出" || no "diag-config：文件不存在应报错" "rc=$rc"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
