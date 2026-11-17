#!/bin/sh
# Stage 9 regression suite: D1/D2/D3 (P1 defects), D5 (unverified download),
# D7 (upgrade safety), D9 (ACL) and the release workflow (D6/D8).
#
#   sh tests/test-regressions.sh
#
# Every case below was written before the fix and failed on 641502f. Nothing
# outside a temp sandbox is read or written: the installer runs against stub
# curl/opkg in $SBI/root, exactly like tests/test-install-scripts.sh does.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

APP="$SRC/package/easyproxy/files/www/luci-static/resources/easyproxy/app.js"
TRAFFIC="$SRC/package/easyproxy/files/usr/lib/easyproxy/traffic.sh"
ACL="$SRC/package/easyproxy/files/usr/share/rpcd/acl.d/luci-app-easyproxy.json"
INSTALL="$SRC/scripts/install.sh"
WF="$SRC/.github/workflows/build.yml"

# --- D1: the traffic sample reads the transmit column, not "$1" + "0" --------
say ""
say "== D1 traffic.sh 读 /proc/net/dev 第 10 列 =="
IF="$(awk -F: 'NR > 2 { sub(/^ +/, "", $1); print $1; exit }' /proc/net/dev 2>/dev/null)"
if [ -z "$IF" ]; then
	no "读取本机网卡名" "/proc/net/dev 不可读"
else
	WANT="$(awk -v i="$IF" '{ n = $0; sub(/^ +/, "", n)
		if (index(n, i":") == 1) { sub(/.*:/, "", n); split(n, a, " "); print a[9]; exit } }' /proc/net/dev)"
	GOT_RAW="$(sh "$TRAFFIC" "$IF" 2>&1)"
	GOT="$(printf '%s' "$GOT_RAW" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tx"))' 2>/dev/null)"
	[ "$GOT" = "$WANT" ] \
		&& ok "tx 等于网卡发送字节数（$IF: $WANT）" \
		|| no "tx 等于网卡发送字节数" "期望 $WANT，实际 '${GOT:-<无法解析>}'，原始输出: $GOT_RAW"
	# rx 必须仍然是第 2 列
	GOTRX="$(printf '%s' "$GOT_RAW" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("rx"))' 2>/dev/null)"
	WANTRX="$(awk -v i="$IF" '{ n = $0; sub(/^ +/, "", n)
		if (index(n, i":") == 1) { sub(/.*:/, "", n); split(n, a, " "); print a[1]; exit } }' /proc/net/dev)"
	[ "$GOTRX" = "$WANTRX" ] && ok "rx 未被破坏（$WANTRX）" || no "rx 未被破坏" "期望 $WANTRX，实际 $GOTRX"
fi

# --- D2: the panel must not call an undefined renderer -----------------------
say ""
say "== D2 面板总览的错误卡片调用 =="
if grep -q 'herrCard' "$APP"; then
	no "app.js 不再引用未定义的 herrCard" "$(grep -n 'herrCard' "$APP" | head -2)"
else
	ok "app.js 不再引用未定义的 herrCard"
fi
grep -q '^function errCard' "$APP" && ok "errCard 有定义" || no "errCard 有定义" "找不到 function errCard"
if command -v node >/dev/null 2>&1; then
	node --check "$APP" >/dev/null 2>&1 && ok "app.js 语法检查通过（node --check）" || no "app.js 语法检查通过"
else
	say "  SKIP  node 不存在，未做语法检查"
fi

# --- D3: dae must not be selectable as an engine from the panel --------------
say ""
say "== D3 内核下拉不能把 dae 存进 UCI =="
DAE_OPT="$(grep 'value: .dae.' "$APP" 2>/dev/null | head -1)"
case "$DAE_OPT" in
	*disabled*) ok "dae 选项在面板上是 disabled" ;;
	*) no "dae 选项在面板上是 disabled" "实际行: ${DAE_OPT:-<没有找到 dae 选项>}" ;;
esac
if grep -q 'dae 适配器开发中' "$APP"; then
	ok "保存前有 dae 拦截提示"
else
	no "保存前有 dae 拦截提示" "app.js 里没有拒绝保存 dae 的分支"
fi
if grep -q 'function saveEngine' "$APP"; then
	ok "内核保存集中在 saveEngine"
else
	no "内核保存集中在 saveEngine" "保存逻辑仍是内联匿名函数，无法统一校验"
fi

# --- D9: the ACL must not hand the panel exec on arbitrary paths ------------
say ""
say "== D9 ACL 权限收窄 =="
ACL_RES="$(python3 -c '
import json,sys
d=json.load(open("'"$ACL"'"))["luci-app-easyproxy"]
bad=[]
if "list" in (d.get("read",{}).get("ubus",{}).get("file") or []): bad.append("list")
pe=set()
for s in ("read","write"):
    for p,m in (d.get(s,{}).get("file") or {}).items():
        if "exec" in m: pe.add(p)
allowed={"/usr/sbin/easyproxy"}
ex=pe-allowed
if ex: bad.append("exec:"+",".join(sorted(ex)))
if "/bin/sh" in pe: bad.append("/bin/sh")
if any("*" in x for x in pe): bad.append("wildcard")
if "/etc/config/easyproxy" in ((d.get("write",{}).get("file") or {})): bad.append("config-file-write")
print("OK" if not bad else "BAD "+" ".join(bad))
' 2>&1)"
[ "$ACL_RES" = "OK" ] && ok "ACL 只授予 CLI 需要的 exec 路径" || no "ACL 只授予 CLI 需要的 exec 路径" "$ACL_RES"

# --- installer sandbox ------------------------------------------------------
SBI="$(mktemp -d)"
mkdir -p "$SBI/bin" "$SBI/fix" "$SBI/log" "$SBI/tmp" \
	"$SBI/root/etc/config" "$SBI/root/usr/sbin" \
	"$SBI/root/usr/lib/easyproxy" "$SBI/root/usr/lib/opkg/info" "$SBI/root/etc/easyproxy/backup"
{ mkdir -p "$SBI/root/etc/init.d"; } 2>/dev/null || true

printf '!<arch>\nIPK-BYTES\n' > "$SBI/fix/asset.ipk"
printf 'PKG_VERSION:=0.7.0\nPKG_RELEASE:=1\n' > "$SBI/fix/Makefile"
H="$(sha256sum "$SBI/fix/asset.ipk" | awk '{ print $1 }')"
{
	printf '%s  %s\n' "$H" easyproxy_0.9.9-1_x86_64.ipk
	printf '%s  %s\n' "$H" easyproxy_0.9.9-1_all.ipk
	printf '%s  %s\n' "$H" easyproxy_0.7.0-1_all.ipk
} > "$SBI/fix/SHA256SUMS"

cat > "$SBI/fix/api.json" <<'JSON'
{
  "assets": [
    { "name": "easyproxy_0.9.9-1_x86_64.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.9.9-1_x86_64.ipk" },
    { "name": "easyproxy_0.9.9-1_all.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.9.9-1_all.ipk" },
    { "name": "easyproxy_0.7.0-1_all.ipk", "browser_download_url": "https://example.test/dl/easyproxy_0.7.0-1_all.ipk" },
    { "name": "sing-box_1.14.4_x86_64.ipk", "browser_download_url": "https://example.test/dl/sing-box_1.14.4_x86_64.ipk" },
    { "name": "dae_2.1.2_x86_64.ipk", "browser_download_url": "https://example.test/dl/dae_2.1.2_x86_64.ipk" },
    { "name": "SHA256SUMS", "browser_download_url": "https://example.test/dl/SHA256SUMS" }
  ]
}
JSON

cat > "$SBI/bin/curl" <<STUB
#!/bin/sh
out=""; url=""
while [ \$# -gt 0 ]; do
	case "\$1" in
		-o) out="\$2"; shift 2 ;;
		-*) shift ;;
		*) url="\$1"; shift ;;
	esac
done
printf '%s\n' "\$url" >> "$SBI/log/curl.urls"
case "\$url" in
	*releases/latest) f="$SBI/fix/api.json" ;;
	*SHA256SUMS) [ -f "$SBI/fix/nosums" ] && exit 22; f="$SBI/fix/SHA256SUMS" ;;
	*.ipk) f="$SBI/fix/asset.ipk" ;;
	*Makefile) f="$SBI/fix/Makefile" ;;
	*) exit 22 ;;
esac
if [ -n "\$out" ]; then cp "\$f" "\$out"; else cat "\$f"; fi
STUB
cat > "$SBI/bin/wget" <<'STUB'
#!/bin/sh
exit 22
STUB
cat > "$SBI/bin/opkg" <<STUB
#!/bin/sh
printf 'opkg %s\n' "\$*" >> "$SBI/log/pm.log"
case "\$1" in
	print-architecture) printf 'all 1\n%s 10\n' "\${EP_TEST_ARCH:-x86_64}" ;;
	list-installed) printf 'easyproxy - %s\n' "\${EP_TEST_PKG_VER:-0.6.0-1}" ;;
	install)
		if [ -f "$SBI/log/fail_pm" ]; then
			printf 'BIN-NEW-BROKEN\n' > "$SBI/root/usr/sbin/easyproxy"
			rm -f "$SBI/root/usr/lib/easyproxy/config.sh"
			exit 1
		fi ;;
esac
exit 0
STUB
printf '#!/bin/sh\necho "sing-box version 1.14.4"\n' > "$SBI/bin/sb-probe"
printf '#!/bin/sh\necho "dae version v2.1.2"\n' > "$SBI/bin/dae-probe"
printf '#!/bin/sh\nexit 0\n' > "$SBI/bin/uci"
chmod +x "$SBI/bin/curl" "$SBI/bin/wget" "$SBI/bin/opkg" "$SBI/bin/sb-probe" "$SBI/bin/dae-probe" "$SBI/bin/uci"

printf 'CONFIG-OLD\n' > "$SBI/root/etc/config/easyproxy"
printf 'BIN-OLD\n' > "$SBI/root/usr/sbin/easyproxy"
printf 'LIB-OLD\n' > "$SBI/root/usr/lib/easyproxy/config.sh"
printf '/usr/sbin/easyproxy\n/usr/lib/easyproxy/config.sh\n' > "$SBI/root/usr/lib/opkg/info/easyproxy.list"

sb_reset() {
	rm -f "$SBI/fix/nosums" "$SBI/log/fail_pm"
	rm -rf "$SBI/root/etc/easyproxy"
	mkdir -p "$SBI/root/etc/easyproxy/backup"
	printf 'CONFIG-OLD\n' > "$SBI/root/etc/config/easyproxy"
	printf 'BIN-OLD\n' > "$SBI/root/usr/sbin/easyproxy"
	printf 'LIB-OLD\n' > "$SBI/root/usr/lib/easyproxy/config.sh"
	printf '/usr/sbin/easyproxy\n/usr/lib/easyproxy/config.sh\n' > "$SBI/root/usr/lib/opkg/info/easyproxy.list"
}

run_installer() {
	env -i PATH="$SBI/bin:/usr/local/bin:/usr/bin:/bin" HOME="$SBI" \
		EP_ROOT="$SBI/root" EP_TMP="$SBI/tmp" \
		EP_STATE_DIR="$SBI/root/etc/easyproxy" \
		EP_BIN="$SBI/root/usr/sbin/easyproxy" \
		EP_INIT="$SBI/root/etc/init.d/easyproxy" \
		EP_RPCD="$SBI/root/etc/init.d/rpcd" \
		EP_LUCI_CACHE="$SBI/root/tmp/luci-indexcache" \
		EP_API_URL="https://api.test/releases/latest" \
		EP_RAW_BASE="https://raw.test/main" \
		EP_SING_BOX_BIN="$SBI/bin/sb-probe" EP_DAE_BIN="$SBI/bin/dae-probe" \
		EP_MIN_FREE_KB="${EP_MIN_FREE_KB:-}" EP_SKIP_COMPAT="${EP_SKIP_COMPAT:-}" \
		EP_TEST_ARCH="${EP_TEST_ARCH:-}" \
		EP_TEST_PKG_VER="${EP_TEST_PKG_VER:-0.6.0-1}" \
		sh "$INSTALL" "$@"
}

# --- D5: no SHA256SUMS means no install -------------------------------------
say ""
say "== D5 下载校验缺失时必须拒装 =="
sb_reset
: > "$SBI/fix/nosums"
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "拿不到 SHA256SUMS 时安装器退出非 0（rc=$RC）" || no "拿不到 SHA256SUMS 时安装器退出非 0" "rc=$RC，输出: $(printf '%s' "$OUT" | tail -3)"
printf '%s' "$OUT" | grep -qi 'refus' && ok "拒绝原因写明 refusing（不装未校验的包）" || no "拒绝原因写明 refusing" "$(printf '%s' "$OUT" | tail -3)"
if [ -f "$SBI/log/pm.log" ] && grep -q 'install' "$SBI/log/pm.log" 2>/dev/null; then
	no "未校验的包没有交给 opkg" "$(cat "$SBI/log/pm.log")"
else
	ok "未校验的包没有交给 opkg"
fi
rm -f "$SBI/fix/nosums"

# --- D7a: disk space is checked before anything is written ------------------
say ""
say "== D7a 升级/安装前检查磁盘空间 =="
sb_reset
OUT="$(EP_MIN_FREE_KB=999999999 run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "剩余空间不足时退出非 0（rc=$RC）" || no "剩余空间不足时退出非 0" "rc=$RC"
printf '%s' "$OUT" | grep -qi 'disk' && ok "报出磁盘空间不足" || no "报出磁盘空间不足" "$(printf '%s' "$OUT" | tail -3)"

# --- D7b: firmware compatibility is checked --------------------------------
say ""
say "== D7b 固件兼容检查 =="
sb_reset
printf "DISTRIB_ID='RandomOS'\nDISTRIB_RELEASE='0.1'\nVERSION_ID='0.1'\n" > "$SBI/root/etc/openwrt_release"
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "非 OpenWrt/ImmortalWrt 固件被拒绝（rc=$RC）" || no "非 OpenWrt/ImmortalWrt 固件被拒绝" "rc=$RC"
printf '%s' "$OUT" | grep -qi 'firmware' && ok "拒绝理由写明固件不兼容" || no "拒绝理由写明固件不兼容" "$(printf '%s' "$OUT" | tail -3)"
printf "DISTRIB_ID='ImmortalWrt'\nDISTRIB_RELEASE='25.12.2'\nVERSION_ID='25.12.2'\n" > "$SBI/root/etc/openwrt_release"
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "ImmortalWrt 25.12.2 通过兼容检查（rc=0）" || no "ImmortalWrt 25.12.2 通过兼容检查" "rc=$RC $(printf '%s' "$OUT" | tail -3)"

# --- D7d: Kwrt (OpenWrt derivative) recognition -----------------------------
# The values below are copied verbatim from a real Kwrt image
# (dl.openwrt.ai/releases/targets/ramips/mt7621/kwrt-10.08.2026-...-rootfs.tar.gz):
# DISTRIB_ID='Kwrt', DISTRIB_RELEASE='25.12-SNAPSHOT' and no VERSION_ID line.
say ""
say "== D7d Kwrt 固件识别 =="
kwrt_rel() {
	printf "DISTRIB_ID='Kwrt'\nDISTRIB_RELEASE='%s'\nDISTRIB_REVISION='10.11.2026'\nDISTRIB_TARGET='x86/64'\nDISTRIB_ARCH='x86_64'\nDISTRIB_DESCRIPTION='%s'\nDISTRIB_TAINTS='busybox override'\n" "$1" "$2" > "$SBI/root/etc/openwrt_release"
}
sb_reset
kwrt_rel '25.12-SNAPSHOT' 'Kwrt 25.12-SNAPSHOT 10.11.2026'
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "Kwrt 25.12-SNAPSHOT 被识别并放行（rc=0）" || no "Kwrt 25.12-SNAPSHOT 被识别并放行" "rc=$RC $(printf '%s' "$OUT" | tail -3)"
printf '%s' "$OUT" | grep -q 'Kwrt 25.12' && ok "放行日志写明 Kwrt 与其 OpenWrt 基线版本" || no "放行日志写明 Kwrt 与基线版本" "$(printf '%s' "$OUT" | grep -i firmware | tail -2)"
sb_reset
kwrt_rel '23.05.5' 'Kwrt 23.05.5 09.08.2025'
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "Kwrt 23.05.5 同样放行（rc=0）" || no "Kwrt 23.05.5 同样放行" "rc=$RC $(printf '%s' "$OUT" | tail -3)"
sb_reset
kwrt_rel '19.07.10' 'Kwrt 19.07.10'
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "Kwrt 19.07（低于 21.02）被拒绝（rc=$RC）" || no "Kwrt 19.07 被拒绝" "rc=$RC $(printf '%s' "$OUT" | tail -3)"
printf '%s' "$OUT" | grep -q '21.02' && ok "拒绝理由写明 21.02 基线" || no "拒绝理由写明 21.02 基线" "$(printf '%s' "$OUT" | tail -3)"
sb_reset
kwrt_rel 'SNAPSHOT' 'Kwrt'
OUT="$(run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "Kwrt 无版本号时拒绝安装（不能确认基线，rc=$RC）" || no "Kwrt 无版本号时拒绝安装" "rc=$RC $(printf '%s' "$OUT" | tail -3)"
printf '%s' "$OUT" | grep -q 'Kwrt' && ok "无法确认版本时的拒绝理由点名 Kwrt" || no "拒绝理由点名 Kwrt" "$(printf '%s' "$OUT" | tail -3)"
sb_reset
kwrt_rel 'SNAPSHOT' 'Kwrt'
OUT="$(EP_SKIP_COMPAT=1 run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "EP_SKIP_COMPAT=1 仍可强制装 Kwrt（rc=0）" || no "EP_SKIP_COMPAT=1 强制装 Kwrt" "rc=$RC $(printf '%s' "$OUT" | tail -3)"
sb_reset
kwrt_rel '25.12-SNAPSHOT' 'Kwrt 25.12-SNAPSHOT 10.11.2026'
OUT="$(run_installer --ipk --no-engine 2>&1)"
printf '%s' "$OUT" | grep -q 'luci:' && ok "缺少 LuCI 时提示面板菜单不会出现" || no "缺少 LuCI 时提示" "$(printf '%s' "$OUT" | tail -3)"
mkdir -p "$SBI/root/usr/share/luci/menu.d"
OUT="$(run_installer --ipk --no-engine 2>&1)"
printf '%s' "$OUT" | grep -q 'luci:' && no "装有 LuCI 时不再提示" "$(printf '%s' "$OUT" | grep 'luci:' | tail -2)" || ok "装有 LuCI 时不再提示"
sb_reset
kwrt_rel '25.12-SNAPSHOT' 'Kwrt 25.12-SNAPSHOT 10.11.2026'
OUT="$(EP_TEST_ARCH=mipsel_24kc run_installer --ipk --no-engine 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "Kwrt mipsel_24kc 仍能装面板（_all.ipk 架构无关，rc=0）" || no "Kwrt mipsel_24kc 装面板" "rc=$RC $(printf '%s' "$OUT" | tail -3)"
printf '%s' "$OUT" | grep -q 'mipsel_24kc' && ok "架构提示点名实际架构" || no "架构提示点名实际架构" "$(printf '%s' "$OUT" | tail -3)"
printf '%s' "$OUT" | grep -q 'no kernel for that architecture' && ok "明确提示该架构没有内核包（不会硬装）" || no "提示没有内核包" "$(printf '%s' "$OUT" | tail -3)"

# --- D7c: config backup + package rollback ----------------------------------
say ""
say "== D7c 升级前备份配置、失败回滚 =="
sb_reset
printf "DISTRIB_ID='ImmortalWrt'\nDISTRIB_RELEASE='25.12.2'\nVERSION_ID='25.12.2'\n" > "$SBI/root/etc/openwrt_release"
: > "$SBI/log/fail_pm"
OUT="$(run_installer upgrade --only package 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "面板升级失败时退出非 0（rc=$RC）" || no "面板升级失败时退出非 0" "rc=$RC $(printf '%s' "$OUT" | tail -4)"
if ls "$SBI"/root/etc/easyproxy/backup/config-*.tar.gz >/dev/null 2>&1; then
	ok "升级前把 UCI 配置打包备份到 /etc/easyproxy/backup"
else
	no "升级前把 UCI 配置打包备份" "$(ls -1 "$SBI/root/etc/easyproxy/backup" 2>/dev/null | tr '\n' ' ')"
fi
CFG_BAK="$(ls -1t "$SBI"/root/etc/easyproxy/backup/config-*.tar.gz 2>/dev/null | head -1)"
if [ -n "$CFG_BAK" ] && tar -tzf "$CFG_BAK" 2>/dev/null | grep -q 'etc/config/easyproxy'; then
	ok "备份归档可读，且里面真的有 UCI 配置"
else
	no "备份归档可读，且里面真的有 UCI 配置" "$(tar -tzf "${CFG_BAK:-/dev/null}" 2>&1 | head -2)"
fi
GOT_BIN="$(cat "$SBI/root/usr/sbin/easyproxy" 2>/dev/null)"
[ "$GOT_BIN" = "BIN-OLD" ] && ok "失败后 CLI 二进制被回滚到旧文件" || no "失败后 CLI 二进制被回滚" "实际 '${GOT_BIN:-<缺失>}'"
GOT_LIB="$(cat "$SBI/root/usr/lib/easyproxy/config.sh" 2>/dev/null)"
[ "$GOT_LIB" = "LIB-OLD" ] && ok "失败后被删除的库文件被回滚" || no "失败后被删除的库文件被回滚" "实际 '${GOT_LIB:-<缺失>}'"
rm -f "$SBI/log/fail_pm"

# --- D6/D8: the release workflow -------------------------------------------
say ""
say "== D6/D8 发布工作流 =="
if grep -q -- '--clobber' "$WF"; then
	no "工作流不再用 --clobber 覆盖同版本资产" "$(grep -n -- 'clobber' "$WF")"
else
	ok "工作流不再用 --clobber 覆盖同版本资产"
fi
if grep -q 'gh release edit' "$WF"; then
	no "工作流不再重写已发布 Release 的说明"
else
	ok "工作流不再重写已发布 Release 的说明"
fi
if grep -q "steps.intent.outputs.tag != ''" "$WF"; then
	ok "发布只在明确要求时才发生（统一发布意图，不认空的构建）"
else
	no "发布只在明确要求时才发生（统一发布意图，不认空的构建）" "发布步骤没有统一 gate"
fi
if grep -q 'already released\|已发布' "$WF"; then
	ok "同版本重复发布时工作流直接失败（提示版本号已发布）"
else
	no "同版本重复发布时工作流直接失败" "没有已发布检查"
fi
if grep -q 'SagerNet/sing-box/releases/download' "$WF" && grep -q 'linux-amd64.tar.gz' "$WF" && grep -q 'sha256sum -c' "$WF"; then
	ok "CI 下载并校验真实 sing-box 1.14.4"
else
	no "CI 下载并校验真实 sing-box 1.14.4" "工作流里没有真实内核下载"
fi
if grep -q 'EP_SING_BOX_BIN' "$WF"; then
	ok "CI 把真实内核路径传给测试套件"
else
	no "CI 把真实内核路径传给测试套件" "没有 EP_SING_BOX_BIN"
fi
# 版本与校验值必须是同一个数：工作流、打包脚本、安装器各存一份 pin，最容易
# 出现“升了打包脚本却忘了 CI/安装器”的半升级，那会让测试用一个内核、发布
# 另一个内核。三处必须一致，amd64 的 sha256 也必须一致。
CI_VER="$(sed -n 's/^ *SB_VER=\([0-9][0-9.]*\)$/\1/p' "$WF" | head -1)"
MK_VER="$(sed -n 's/^SING_BOX_VER=.*:-\([0-9][0-9.]*\)}.*/\1/p' scripts/make-kernel-ipk.sh)"
IN_VER="$(sed -n 's/^SING_BOX_VER=.*:-\([0-9][0-9.]*\)}.*/\1/p' scripts/install.sh)"
if [ "$CI_VER" = "$MK_VER" ] && [ "$MK_VER" = "$IN_VER" ] && [ -n "$CI_VER" ]; then
	ok "工作流/打包脚本/安装器的 sing-box 版本一致（$CI_VER）"
else
	no "三处 sing-box 版本一致" "CI=$CI_VER 打包=$MK_VER 安装器=$IN_VER"
fi
CI_SHA="$(sed -n 's/^ *SB_SHA=\([0-9a-f]*\)$/\1/p' "$WF" | head -1)"
MK_SHA="$(sed -n 's/.*sing-box:amd64) echo \([0-9a-f]*\) ;;/\1/p' scripts/make-kernel-ipk.sh)"
IN_SHA="$(sed -n 's/.*amd64) printf .%s. .\([0-9a-f]\{64\}\).*/\1/p' scripts/install.sh | head -1)"
if [ "$CI_SHA" = "$MK_SHA" ] && [ "$MK_SHA" = "$IN_SHA" ] && [ -n "$CI_SHA" ]; then
	ok "工作流/打包脚本/安装器的 amd64 sha256 一致"
else
	no "三处 amd64 sha256 一致" "CI=${CI_SHA:-空} 打包=${MK_SHA:-空} 安装器=${IN_SHA:-空}"
fi
if grep -n 'GITHUB_ENV' "$WF" | grep -q 'EP_SING_BOX_BIN'; then
	no "工作流没有把内核路径泄漏成全局环境变量" "EP_SING_BOX_BIN 仍被写进 \$GITHUB_ENV，安装套件会误认为内核已存在而跳过下载"
else
	ok "工作流没有把内核路径泄漏成全局环境变量"
fi
# The per-suite kernel injection and the SKIP gate now live in the aggregate
# runner (tests/run-all.sh), which is itself exercised every time CI runs it.
# The workflow must call that runner instead of looping over the suites itself.
RUNALL="$SRC/tests/run-all.sh"
if grep -q 'env -u EP_SING_BOX_BIN sh "$t"' "$RUNALL" 2>/dev/null; then
	ok "安装类套件在清空内核路径的环境里运行（run-all.sh）"
else
	no "安装类套件在清空内核路径的环境里运行（run-all.sh）" "run-all.sh 里没有 env -u EP_SING_BOX_BIN"
fi
if grep -q "grep -c '  SKIP  '" "$RUNALL" 2>/dev/null || grep -q 'SKIPPED' "$RUNALL" 2>/dev/null; then
	ok "跳过即失败：run-all.sh 统计 SKIP 并据此失败"
else
	no "跳过即失败：run-all.sh 统计 SKIP 并据此失败" "run-all.sh 没有 SKIP 门禁"
fi
if grep -q 'tests/run-all.sh' "$WF"; then
	ok "工作流通过 run-all.sh 统计测试结果"
else
	no "工作流通过 run-all.sh 统计测试结果" "工作流仍在自己循环跑套件"
fi

rm -rf "$SBI"
say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
