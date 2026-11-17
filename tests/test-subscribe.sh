#!/bin/sh
# Regression suite for subscription import: deduplication, the remembered URL,
# incremental update and the daily cron entry.
#
#   sh tests/test-subscribe.sh
#
# No network: curl is stubbed and serves a fixed payload.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

if [ -n "${EP_TEST_SB:-}" ]; then
	SB="$EP_TEST_SB"; rm -rf "$SB"; mkdir -p "$SB"
else
	SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
fi

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin" "$SB/run" "$SB/log" "$SB/rules"
for f in common.sh config.sh transparent.sh node.sh subscribe.sh; do
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" "$SB/usr/lib/easyproxy/$f"
done
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
    -e "s#/usr/lib/easyproxy/node.sh#$SB/usr/lib/easyproxy/node.sh#" \
    -e "s#/usr/lib/easyproxy/subscribe.sh#$SB/usr/lib/easyproxy/subscribe.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

cat > "$SB/etc/uci.db" <<DB
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.main.listen_port=7890
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.routing.rule_set_dir=$SB/rules
easyproxy.sing_box.binary=$SB/bin/sing-box
easyproxy.sing_box.config_file=$SB/etc/sing-box.json
DB

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
[ "$1" = "-q" ] && shift
cmd="$1"; shift
db_set() {
	awk -v k="$1" -v v="$2" '
		BEGIN { done = 0 }
		{ if (length($0) > length(k) && substr($0, 1, length(k) + 1) == k "=") { print k "=" v; done = 1 } else print }
		END { if (!done) print k "=" v }
	' "$DB" > "$DB.new" && mv "$DB.new" "$DB"
}
case "$cmd" in
	get) grep -m1 -F "$1=" "$DB" | cut -d= -f2-; exit 0 ;;
	show) grep -F "$1" "$DB" | grep -v '^$'; exit 0 ;;
	add)
		n=$(grep -F "$1.@$2[" "$DB" | grep "=$2\$" | sed 's/.*\[\([0-9]*\)\].*/\1/' | sort -n | tail -1)
		[ -n "$n" ] || n=-1
		n=$((n + 1))
		printf '%s.@%s[%s]=%s\n' "$1" "$2" "$n" "$2" >> "$DB"
		printf '%s' "@$2[$n]"; exit 0 ;;
	set)
		case "$1" in
			*=*) db_set "${1%%=*}" "${1#*=}" ;;
			*) echo "uci: set needs key=value" >&2; exit 1 ;;
		esac
		exit 0 ;;
	delete) awk -v k="$1" '{ if (index($0, k "=") == 1 || index($0, k ".") == 1) next; print }' "$DB" > "$DB.new" && mv "$DB.new" "$DB"; exit 0 ;;
	commit) exit 0 ;;
esac
exit 0
UCI
chmod +x "$SB/bin/uci"

printf '#!/bin/sh\nexit 0\n' > "$SB/bin/logger"; chmod +x "$SB/bin/logger"
printf '#!/bin/sh\necho "sing-box version 1.14.4"\nexit 0\n' > "$SB/bin/sing-box"; chmod +x "$SB/bin/sing-box"

# curl stub: serves $EP_TEST_SUB_PAYLOAD
cat > "$SB/bin/curl" <<'CURL'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
	case "$1" in
		-o) out="$2"; shift 2 ;;
		*) shift ;;
	esac
done
[ -n "$out" ] || exit 0
cat "$EP_TEST_SUB_PAYLOAD" > "$out"
exit 0
CURL
chmod +x "$SB/bin/curl"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export EP_TEST_SUB_PAYLOAD="$SB/sub.txt"
export PATH="$SB/usr/sbin:$SB/bin:$PATH"
export EP_LIB_DIR="$SB/usr/lib/easyproxy"
export EP_SUB_CONF="$SB/etc/easyproxy/subscribe.conf"
export EP_SUBSCRIBE_LIB="$SB/usr/lib/easyproxy/subscribe.sh"
export EP_CRONTAB="$SB/etc/crontabs/root"
export EP_RUNTIME_DIR="$SB/run"
export EP_LOG_FILE="$SB/log/easyproxy.log"

EP="$SB/usr/sbin/easyproxy"
DB="$SB/etc/uci.db"

# --- 1. base64 subscription, no base64/openssl on PATH ------------------------
say "== v2ray 风格 base64 订阅 =="
# 三条 ss 链接，base64 成一整块（模拟真实订阅返回）
links="ss://YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==@203.0.113.10:8388#hk-01
ss://YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==@203.0.113.11:8388#jp-01
ss://YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==@203.0.113.12:8388#us-01"
printf '%s\n' "$links" | base64 | tr -d '\n' > "$EP_TEST_SUB_PAYLOAD"
mkdir -p "$SB/minbin"
for t in awk tr sed sh cat mktemp rm mv grep cut sort tail head dirname basename date; do
	p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$SB/minbin/$t"
done
out="$(PATH="$SB/usr/sbin:$SB/bin:$SB/minbin" "$EP" subscribe https://example.com/sub 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "无 base64 环境也能导入 base64 订阅" || no "无 base64 环境也能导入 base64 订阅" "rc=$rc $out"
printf '%s' "$out" | grep -q 'imported: 3' && ok "三条链接全部导入" || no "三条链接全部导入" "$out"
[ "$(grep -c '\.server=' "$DB")" = "3" ] && ok "节点表有三条 server" || no "节点表有三条 server" "$(grep -c '\.server=' "$DB")"

# --- 2. re-running the same subscription is idempotent -----------------------
say "== 重复拉取同一订阅 =="
out="$("$EP" subscribe https://example.com/sub 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "重复拉取仍返回成功" || no "重复拉取仍返回成功" "rc=$rc $out"
printf '%s' "$out" | grep -q 'skipped: 3' && ok "重复拉取全部跳过" || no "重复拉取全部跳过" "$out"
[ "$(grep -c '\.server=' "$DB")" = "3" ] && ok "重复拉取没有新增节点" || no "重复拉取没有新增节点" "$(grep -c '\.server=' "$DB")"

# --- 3. incremental update adds only what is new -----------------------------
say "== 增量更新 =="
printf '%s\n%s\n' "$links" 'ss://YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==@203.0.113.13:8388#sg-01' \
	| base64 | tr -d '\n' > "$EP_TEST_SUB_PAYLOAD"
out="$("$EP" subscribe --update 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "--update 成功" || no "--update 成功" "rc=$rc $out"
printf '%s' "$out" | grep -q 'imported: 1' && ok "只新增新端点" || no "只新增新端点" "$out"
printf '%s' "$out" | grep -q 'skipped: 3' && ok "老端点跳过" || no "老端点跳过" "$out"

# --- 4. remembered URL is a 0600 file, not UCI -------------------------------
say "== 订阅地址的存放 =="
[ -f "$EP_SUB_CONF" ] && ok "订阅地址记在 subscribe.conf" || no "订阅地址记在 subscribe.conf"
perm="$(ls -l "$EP_SUB_CONF" 2>/dev/null | cut -c1-10)"
[ "$perm" = "-rw-------" ] && ok "subscribe.conf 权限 600" || no "subscribe.conf 权限 600" "$perm"
[ "$(grep -c 'example.com' "$DB")" = "0" ] && ok "订阅 URL 不写进 UCI" || no "订阅 URL 不写进 UCI"

# --- 5. daily cron ----------------------------------------------------------
say "== 每日自动更新 =="
out="$("$EP" subscribe --daily on 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "开启每日更新" || no "开启每日更新" "rc=$rc $out"
grep -q 'subscribe --update' "$EP_CRONTAB" 2>/dev/null && ok "crontab 写入更新任务" || no "crontab 写入更新任务" "$(cat "$EP_CRONTAB" 2>/dev/null)"
out="$("$EP" subscribe --daily off 2>&1)"
grep -q 'subscribe --update' "$EP_CRONTAB" 2>/dev/null && no "关闭后 crontab 干净" "$(cat "$EP_CRONTAB")" || ok "关闭后 crontab 干净"

# --- 6. forget --------------------------------------------------------------
say "== 忘记订阅 =="
"$EP" subscribe --forget >/dev/null 2>&1
[ -f "$EP_SUB_CONF" ] && no "--forget 删除配置文件" || ok "--forget 删除配置文件"
[ "$(grep -c '\.server=' "$DB")" = "4" ] && ok "--forget 不动节点" || no "--forget 不动节点" "$(grep -c '\.server=' "$DB")"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ]
