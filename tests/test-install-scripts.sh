#!/usr/bin/env sh
# Suite for scripts/install.sh and scripts/uninstall.sh.
#
#   sh tests/test-install-scripts.sh
#
# Both scripts touch /etc, a package manager and rpcd on the target router. Here
# every one of those is a stub in a temp sandbox: `opkg`, `apk`, `curl`, `wget`,
# the init script, rpcd, and easyproxy itself. Nothing outside the sandbox is
# read or written.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/fix" "$SB/log" "$SB/root/etc" "$SB/opt"

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
printf 'PKG_VERSION:=0.9.9\nPKG_RELEASE:=1\n' > "$SB/fix/Makefile"
printf 'APK-BYTES\n' > "$SB/fix/asset.apk"
printf 'IPK-BYTES\n' > "$SB/fix/asset.ipk"
tar -czf "$SB/fix/asset.tar.gz" --files-from /dev/null 2>/dev/null || tar -czf "$SB/fix/asset.tar.gz" -C "$SB" .

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
	*releases/latest) [ -f "$EP_TEST_LOG/api.fail" ] && exit 22; f="$EP_TEST_FIX/api.json" ;;
	*Makefile) f="$EP_TEST_FIX/Makefile" ;;
	*.apk) f="$EP_TEST_FIX/asset.apk" ;;
	*.ipk) f="$EP_TEST_FIX/asset.ipk" ;;
	*.tar.gz) f="$EP_TEST_FIX/asset.tar.gz" ;;
	*) exit 22 ;;
esac
if [ -n "$out" ]; then cp "$f" "$out"; else cat "$f"; fi
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
	install) : > "$EP_TEST_LOG/installed"; ;;
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
mkdir -p "$EP_TMP" "$EP_STATE_DIR" "$EP_ROOT/usr/sbin" "$EP_ROOT/etc/init.d"
touch "$EP_CFG"
touch "$EP_LUCI_CACHE"

reset() {
	rm -rf "$SB/log" "$SB/tmp"
	mkdir -p "$SB/log" "$SB/tmp"
	rm -f "$EP_STATE_DIR/nftables.conf"
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
[ -s "$EP_TEST_LOG/pm.log" ] && no "--rootfs 不应调用包管理器" "$(cat "$EP_TEST_LOG/pm.log")" || ok "--rootfs 不调用包管理器"

# --- install: --help does nothing ------------------------------------
reset
sh "$INSTALL" --help > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'install.sh' "$SB/out" && ok "--help 打印用法并退出 0" || no "--help 打印用法并退出 0" "rc=$rc"
[ -f "$EP_TEST_LOG/curl.urls" ] && no "--help 不应联网" || ok "--help 不联网"

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

# --- uninstall --purge ------------------------------------------------
reset
printf 'nft\n' > "$EP_STATE_DIR/nftables.conf"
printf 'config\n' > "$EP_CFG"
sh "$UNINSTALL" --purge > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--purge 退出码 0" || no "--purge 退出码 0" "rc=$rc $(cat "$SB/out")"
[ -f "$EP_CFG" ] && no "--purge 应删除配置文件" || ok "--purge 删除配置文件"
[ -d "$EP_STATE_DIR" ] && no "--purge 应删除状态目录" || ok "--purge 删除状态目录"
grep -q 'rpcd restart' "$EP_TEST_LOG/rpcd.log" 2>/dev/null && ok "卸载后重启 rpcd" || no "卸载后重启 rpcd"

# --- uninstall on a host with no easyproxy at all ---------------------
reset
mv "$EP_BIN" "$SB/ep.off"
sh "$UNINSTALL" > "$SB/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "没装过时卸载仍返回 0（幂等）" || no "没装过时卸载仍返回 0" "rc=$rc $(cat "$SB/out")"
mv "$SB/ep.off" "$EP_BIN"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
