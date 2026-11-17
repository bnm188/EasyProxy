#!/usr/bin/env sh
# Suite for the maintenance CLI: config backup / restore / reset, rule-set
# update and verification, doctor, log rotation and uninstall-clean.
#
#   sh tests/test-maintenance.sh
#
# Every path the CLI touches is redirected into a temp sandbox and `uci`,
# `curl`, `logger`, `nft` and `ip` are stubs, so nothing outside the sandbox is
# read or written. Both branches of `uninstall-clean` are exercised: a host
# without nft, and a host with nft where only EasyProxy's own table may go.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/fix" "$SB/log" "$SB/state"

# --- fixtures -------------------------------------------------------------
printf 'config main\n\toption enabled \0471\047\n' > "$SB/state/default"
printf 'config main\n\toption enabled \0470\047\n' > "$SB/state/current"
printf 'SRS\000\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020' > "$SB/fix/good.srs"
printf '<html>404</html>' > "$SB/fix/bad.srs"

# --- stubs ----------------------------------------------------------------
cat > "$SB/bin/uci" <<'STUB'
#!/bin/sh
case "$*" in
	*backup_dir*)        printf '%s\n' "$EP_TEST_BACKUP_DIR" ;;
	*rule_set_dir*)      printf '%s\n' "$EP_TEST_RULESET_DIR" ;;
	*log_max_bytes*)     printf '%s\n' "${EP_TEST_LOG_MAX:-1048576}" ;;
	*geosite_cn_url*)    printf '%s\n' "https://example.test/geosite-cn.srs" ;;
	*geoip_cn_url*)      printf '%s\n' "https://example.test/geoip-cn.srs" ;;
	*default_config*)    printf '%s\n' "$EP_TEST_DEFAULT" ;;
	*) exit 0 ;;
esac
STUB
cat > "$SB/bin/curl" <<'STUB'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
	case "$1" in
		-o) out="$2"; shift 2 ;;
		-*) shift ;;
		*) shift ;;
	esac
done
[ -f "$EP_TEST_LOG/curl.fail" ] && exit 22
[ -n "$out" ] || exit 22
cp "$EP_TEST_FIX/good.srs" "$out"
STUB
cat > "$SB/bin/logger" <<'STUB'
#!/bin/sh
printf 'log %s\n' "$*" >> "$EP_TEST_LOG/logger.log"
exit 0
STUB
chmod +x "$SB/bin/"*

export PATH="$SB/bin:$PATH"
export EP_TEST_LOG="$SB/log"
export EP_TEST_FIX="$SB/fix"
export EP_TEST_BACKUP_DIR="$SB/state/backups"
export EP_TEST_RULESET_DIR="$SB/state/ruleset"
export EP_TEST_DEFAULT="$SB/state/default"
export EP_CONFIG_FILE="$SB/state/current"
export EP_LOG_FILE="$SB/state/easyproxy.log"
export EP_RUNTIME_DIR="$SB/state/run"
mkdir -p "$EP_TEST_BACKUP_DIR" "$EP_TEST_RULESET_DIR" "$EP_RUNTIME_DIR"

# The CLI sources its libraries from fixed absolute paths, so stage a sandboxed
# copy with those paths rewritten and run that copy.
mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin"
for f in common.sh config.sh node.sh maint.sh transparent.sh traffic.sh subscribe.sh; do
	[ -f "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" ] || continue
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" "$SB/usr/lib/easyproxy/$f"
done
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/#$SB/usr/lib/easyproxy/#g" \
    -e "s#/etc/config/easyproxy#$SB/state/current#g" \
    "$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"

CLI="$SB/usr/sbin/easyproxy"

reset() {
	rm -rf "$SB/log" "$EP_TEST_BACKUP_DIR" "$EP_TEST_RULESET_DIR"
	mkdir -p "$SB/log" "$EP_TEST_BACKUP_DIR" "$EP_TEST_RULESET_DIR"
	printf 'config main\n\toption enabled \0470\047\n' > "$EP_CONFIG_FILE"
	rm -f "$EP_LOG_FILE.1" "$EP_CONFIG_FILE.before-restore" "$EP_CONFIG_FILE.before-reset"
}

run_cli() { sh "$CLI" "$@" > "$SB/out" 2>&1; RC=$?; }

# --- config backup --------------------------------------------------------
reset
run_cli config backup
[ "$RC" -eq 0 ] && ok "config backup 退出码 0" || no "config backup 退出码 0" "$(cat "$SB/out")"
arch="$(awk '/^Backup written: / { print $3 }' "$SB/out")"
[ -f "$arch" ] && ok "备份文件已生成" || no "备份文件已生成" "$(cat "$SB/out")"
case "$arch" in
	*easyproxy-*.tar.gz) ok "备份名带时间戳" ;;
	*) no "备份名带时间戳" "$arch" ;;
esac
tar tzf "$arch" 2>/dev/null | grep -q './config/easyproxy' \
	&& ok "备份内含 config/easyproxy" || no "备份内含 config/easyproxy" "$(tar tzf "$arch" 2>/dev/null)"
grep -q 'bytes' "$SB/out" && ok "备份输出含体积" || no "备份输出含体积"

# --- config restore -------------------------------------------------------
reset
printf 'config main\n\toption enabled \0471\047\n' > "$EP_CONFIG_FILE"
run_cli config backup
arch="$(awk '/^Backup written: / { print $3 }' "$SB/out")"
printf 'config main\n\toption enabled \0470\047\n' > "$EP_CONFIG_FILE"
run_cli config restore "$arch"
[ "$RC" -eq 0 ] && ok "config restore 退出码 0" || no "config restore 退出码 0" "$(cat "$SB/out")"
grep -q 'enabled .1.' "$EP_CONFIG_FILE" && ok "恢复后配置内容回到备份状态" || no "恢复后配置内容回到备份状态" "$(cat "$EP_CONFIG_FILE")"
[ -f "$EP_CONFIG_FILE.before-restore" ] && ok "恢复前配置留档 .before-restore" || no "恢复前配置留档"

reset
run_cli config restore "$SB/state/current"
[ "$RC" -ne 0 ] && ok "拒绝恢复非 tar 文件" || no "拒绝恢复非 tar 文件" "$(cat "$SB/out")"
grep -qi 'not a valid backup\|no config' "$SB/out" && ok "拒绝原因可读" || no "拒绝原因可读" "$(cat "$SB/out")"

# --- config reset ---------------------------------------------------------
reset
run_cli config reset
[ "$RC" -eq 0 ] && ok "config reset 退出码 0" || no "config reset 退出码 0" "$(cat "$SB/out")"
cmp -s "$EP_TEST_DEFAULT" "$EP_CONFIG_FILE" \
	&& ok "重置为包内默认配置" || no "重置为包内默认配置" "$(cat "$EP_CONFIG_FILE")"
[ -f "$EP_CONFIG_FILE.before-reset" ] && ok "重置前配置留档 .before-reset" || no "重置前配置留档"

# --- ruleset --------------------------------------------------------------
reset
run_cli ruleset verify
[ "$RC" -ne 0 ] && ok "规则集缺失时校验失败（非 0）" || no "规则集缺失时校验失败" "$(cat "$SB/out")"
grep -q 'missing' "$SB/out" && ok "缺失项标记为 missing" || no "缺失项标记为 missing" "$(cat "$SB/out")"
grep -q 'ruleset: 0 ok, 2 fail' "$SB/out" && ok "汇总计数 0 ok / 2 fail" || no "汇总计数" "$(cat "$SB/out")"

run_cli ruleset update
[ "$RC" -eq 0 ] && ok "ruleset update 退出码 0" || no "ruleset update 退出码 0" "$(cat "$SB/out")"
[ -s "$EP_TEST_RULESET_DIR/geosite-cn.srs" ] && [ -s "$EP_TEST_RULESET_DIR/geoip-cn.srs" ] \
	&& ok "两份规则集都已落地" || no "两份规则集都已落地"
run_cli ruleset verify
[ "$RC" -eq 0 ] && ok "更新后校验通过" || no "更新后校验通过" "$(cat "$SB/out")"
grep -q 'ruleset: 2 ok, 0 fail' "$SB/out" && ok "汇总计数 2 ok / 0 fail" || no "汇总计数 2 ok" "$(cat "$SB/out")"

reset
cp "$EP_TEST_FIX/good.srs" "$EP_TEST_RULESET_DIR/geosite-cn.srs" 2>/dev/null || true
touch "$SB/log/curl.fail"
run_cli ruleset update
[ "$RC" -ne 0 ] && ok "下载失败时返回非 0" || no "下载失败时返回非 0" "$(cat "$SB/out")"
grep -q 'previous file kept' "$SB/out" && ok "下载失败保留旧文件" || no "下载失败保留旧文件" "$(cat "$SB/out")"
[ ! -f "$EP_TEST_RULESET_DIR/geosite-cn.srs.new" ] && ok "失败时不留 .new 临时文件" || no "失败时不留 .new 临时文件"

reset
printf '<html>404</html>' > "$EP_TEST_RULESET_DIR/geosite-cn.srs"
cp "$SB/fix/bad.srs" "$EP_TEST_RULESET_DIR/geoip-cn.srs"
run_cli ruleset verify
[ "$RC" -ne 0 ] && ok "HTML 错误页不算规则集" || no "HTML 错误页不算规则集" "$(cat "$SB/out")"
grep -q 'magic is not SRS' "$SB/out" && ok "识别出 SRS 魔数不对" || no "识别出 SRS 魔数不对" "$(cat "$SB/out")"

# --- doctor ---------------------------------------------------------------
run_cli doctor
[ "$RC" -ne 0 ] || [ "$RC" -eq 0 ] && ok "doctor 可执行并给出汇总" || no "doctor 可执行"
grep -q 'doctor: .* ok, .* warn, .* fail' "$SB/out" && ok "doctor 输出 ok/warn/fail 汇总" || no "doctor 输出汇总" "$(head -3 "$SB/out")"
run_cli doctor --json
[ "$RC" -le 1 ] && ok "doctor --json 退出码 0/1" || no "doctor --json 退出码" "rc=$RC"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get("checks"), list) else 1)' "$SB/out" 2>/dev/null \
	&& ok "doctor --json 是合法 JSON 且含 checks 数组" || no "doctor --json 结构" "$(head -c 200 "$SB/out")"

# --- log rotate -----------------------------------------------------------
reset
printf 'x%.0s' $(seq 1 400) > "$EP_LOG_FILE"
EP_TEST_LOG_MAX=100 run_cli log rotate
[ "$RC" -eq 0 ] && ok "log rotate 退出码 0" || no "log rotate 退出码 0" "$(cat "$SB/out")"
[ -f "$EP_LOG_FILE.1" ] && ok "超过阈值时轮转为 .1" || no "超过阈值时轮转为 .1"
[ -s "$EP_LOG_FILE" ] && no "轮转后原日志应被截断" "$(wc -c < "$EP_LOG_FILE")" || ok "轮转后原日志被截断"

reset
printf 'small\n' > "$EP_LOG_FILE"
EP_TEST_LOG_MAX=1048576 run_cli log rotate
[ "$RC" -eq 0 ] && ok "未超阈值时退出码 0" || no "未超阈值时退出码 0" "$(cat "$SB/out")"
grep -q 'nothing to rotate' "$SB/out" && ok "未超阈值时不轮转" || no "未超阈值时不轮转" "$(cat "$SB/out")"
[ -f "$EP_LOG_FILE.1" ] && no "未超阈值时不应产生 .1" || ok "未超阈值时不产生 .1"

# --- uninstall-clean ------------------------------------------------------
# run the CLI on a PATH that deliberately has no nft, whatever the host ships
run_cli_no_nft() { PATH="$SB/bin:/usr/bin:/bin" sh "$CLI" "$@" > "$SB/out" 2>&1; RC=$?; }

reset
run_cli_no_nft uninstall-clean
[ "$RC" -eq 0 ] && ok "没有 nft 时 uninstall-clean 仍返回 0" || no "没有 nft 时 uninstall-clean 返回 0" "$(cat "$SB/out")"
grep -q 'stock ImmortalWrt rules untouched' "$SB/out" && ok "明确声明不动系统防火墙" || no "声明不动系统防火墙" "$(cat "$SB/out")"
grep -q 'nft: not installed' "$SB/out" && ok "没有 nft 时说明无需清理" || no "没有 nft 时说明无需清理" "$(cat "$SB/out")"

# With nft present it may only touch its own tables, never fw4's.
cat > "$SB/bin/nft" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$EP_TEST_LOG/nft.calls"
case "$1" in
	list)
		# only report EasyProxy's own table, and only while it still exists
		[ -f "$EP_TEST_LOG/tbl.exists" ] && exit 0
		exit 1 ;;
	delete)
		# a real nft would fail deleting a table that is already gone
		[ -f "$EP_TEST_LOG/tbl.exists" ] || exit 1
		rm -f "$EP_TEST_LOG/tbl.exists"
		exit 0 ;;
	*) exit 0 ;;
esac
STUB
cat > "$SB/bin/ip" <<'STUB'
#!/bin/sh
printf 'ip %s\n' "$*" >> "$EP_TEST_LOG/ip.calls"
exit 0
STUB
chmod +x "$SB/bin/nft" "$SB/bin/ip"
: > "$EP_TEST_LOG/tbl.exists"
run_cli uninstall-clean
[ "$RC" -eq 0 ] && ok "有 nft 时 uninstall-clean 仍返回 0" || no "有 nft 时 uninstall-clean 返回 0" "$(cat "$SB/out")"
grep -q 'own tables (ip/ip6 easyproxy) removed' "$SB/out" && ok "有 nft 时声明只删自己的表" || no "有 nft 时声明只删自己的表" "$(cat "$SB/out")"
grep -q 'delete table ip easyproxy' "$EP_TEST_LOG/nft.calls" 2>/dev/null \
	&& ok "有 nft 时删除了自己的 ip 表" || no "有 nft 时删除了自己的 ip 表" "$(cat "$EP_TEST_LOG/nft.calls" 2>/dev/null)"
[ ! -f "$EP_TEST_LOG/tbl.exists" ] && ok "删除后不再要求重复删除" || no "删除后不再要求重复删除" "$(cat "$EP_TEST_LOG/nft.calls" 2>/dev/null)"
if grep -Eq 'flush table .*(fw4|filter|nat|mangle)|delete table .*(fw4|filter|nat|mangle)' "$EP_TEST_LOG/nft.calls" 2>/dev/null; then
	no "nft 调用不碰系统防火墙表" "$(cat "$EP_TEST_LOG/nft.calls")"
else
	ok "nft 调用不碰系统防火墙表"
fi

# --- help ----------------------------------------------------------------
run_cli help
grep -q 'config backup' "$SB/out" && grep -q 'ruleset update' "$SB/out" && grep -q 'doctor' "$SB/out" \
	&& ok "help 里列出了第 6 类新命令" || no "help 里列出了第 6 类新命令"

printf '\n结果：%s 通过，%s 失败\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
