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
	sing-box_1.10.7_x86_64.ipk dae_2.1.2_x86_64.ipk; do
	printf '%s  %s\n' "$h_ipk" "$n" >> "$SB/fix/SHA256SUMS"
done
for n in easyproxy-0.5.0-r1.apk easyproxy-0.9.9-r1.apk; do
	printf '%s  %s\n' "$h_apk" "$n" >> "$SB/fix/SHA256SUMS"
done
for n in easyproxy-0.5.0-rootfs.tar.gz easyproxy-0.9.9-rootfs.tar.gz; do
	printf '%s  %s\n' "$h_tgz" "$n" >> "$SB/fix/SHA256SUMS"
done
sed 's/^[0-9a-f]/0/' "$SB/fix/SHA256SUMS" > "$SB/fix/SHA256SUMS.bad"
