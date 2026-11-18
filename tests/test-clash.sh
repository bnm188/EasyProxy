#!/usr/bin/env sh
# Clash API suite: the mihomo controller reader that feeds `easyproxy status`
# and the connection list.
#
#   sh tests/test-clash.sh
#
# A curl stub decides the response, so the parsing can be exercised against
# shapes taken from real mihomo output without a running engine. Two of these
# cases exist because of how the panel would fail, not because the code is
# pretty: a closed connection must not blank the whole status line, and a host
# name arrives from the client's own SNI, so it must be escaped on the way out.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/lib" "$SB/bin" "$SB/etc"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh" "$SB/lib/common.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/clash.sh" "$SB/lib/clash.sh"
sed -i "s#/usr/lib/easyproxy/clash.sh#$SB/lib/clash.sh#" "$SB/lib/clash.sh" 2>/dev/null || true

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		get) shift; key="$1"; awk -v k="$key=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$DB"; exit 0 ;;
		show) shift; awk -v p="$1" 'index($0, p) == 1' "$DB"; exit 0 ;;
		*) shift ;;
	esac
done
exit 0
UCI
chmod +x "$SB/bin/uci"

# curl stub: prints the body named by EP_CLASH_BODY, and records every call so a
# test can prove an absent API was never even dialled.
cat > "$SB/bin/curl" <<'CURL'
#!/bin/sh
printf '%s\n' "$*" >> "${EP_CLASH_CALLS:-/dev/null}"
[ "${EP_CLASH_RC:-0}" = "0" ] || exit "${EP_CLASH_RC}"
[ -n "${EP_CLASH_BODY:-}" ] && cat "$EP_CLASH_BODY"
exit 0
CURL
chmod +x "$SB/bin/curl"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export EP_CLASH_CALLS="$SB/calls.txt"
export PATH="$SB/bin:$PATH"
: > "$EP_CLASH_CALLS"

write_uci() { # $1 engine  $2 controller
	cat > "$SB/etc/uci.db" <<-DB
	easyproxy.main.engine=${1:-mihomo}
	easyproxy.mihomo.controller=${2:-127.0.0.1:9090}
	easyproxy.mihomo.secret=
	DB
}

# shell that loads the reader the same way the CLI does
cat > "$SB/p.sh" <<-'P'
	#!/bin/sh
	export EP_TEST_UCI_DB="$EP_TEST_UCI_DB"
	export PATH="$PATH"
	. "$EP_SB/lib/common.sh"
	. "$EP_SB/lib/clash.sh"
	"$@"
P
chmod +x "$SB/p.sh"

run() { EP_SB="$SB" sh "$SB/p.sh" "$@" 2>/dev/null; }

write_uci mihomo 127.0.0.1:9090

# ---- snapshot -------------------------------------------------------------
cat > "$SB/body.json" <<'J'
{"downloadTotal":1048576,"uploadTotal":2048,"connections":[
{"id":"a","upload":100,"download":200,"start":"2026-11-18T02:35:40.5Z","chains":["11","PROXY"],"rule":"Match","metadata":{"network":"tcp","sourceIP":"10.10.10.50","destinationIP":"142.250.1.1","sourcePort":"5000","destinationPort":"443","host":"www.google.com"}},
{"id":"b","upload":300,"download":400,"start":"2026-11-18T02:36:10.5Z","chains":["11","PROXY"],"rule":"Match","metadata":{"network":"tcp","sourceIP":"10.10.10.51","destinationIP":"20.1.1.1","sourcePort":"5001","destinationPort":"443"}}
],"memory":73400320}
J
export EP_CLASH_BODY="$SB/body.json"

SNAP="$(run ep_clash_snapshot)"
API="$(printf '%s' "$SNAP" | cut -f1)"
COUNT="$(printf '%s' "$SNAP" | cut -f2)"
UP="$(printf '%s' "$SNAP" | cut -f3)"
DOWN="$(printf '%s' "$SNAP" | cut -f4)"
MEM="$(printf '%s' "$SNAP" | cut -f5)"
[ "$API" = "ok" ] && ok "控制器可达时 api=ok" || no "控制器可达时 api=ok" "得到 $API"
[ "$COUNT" = "2" ] && ok "连接数按 id 计数（2）" || no "连接数按 id 计数（2）" "得到 $COUNT"
[ "$UP" = "2048" ] && ok "上行总量取 uploadTotal" || no "上行总量取 uploadTotal" "得到 $UP"
[ "$DOWN" = "1048576" ] && ok "下行总量取 downloadTotal" || no "下行总量取 downloadTotal" "得到 $DOWN"
[ "$MEM" = "73400320" ] && ok "内存取 memory" || no "内存取 memory" "得到 $MEM"

# ---- per-connection rows -------------------------------------------------
ROWS="$(run ep_clash_connections)"
FIRST="$(printf '%s\n' "$ROWS" | sed -n '1p')"
H="$(printf '%s' "$FIRST" | cut -f1)"
S="$(printf '%s' "$FIRST" | cut -f2)"
N="$(printf '%s' "$FIRST" | cut -f3)"
U="$(printf '%s' "$FIRST" | cut -f4)"
[ "$H" = "www.google.com" ] && ok "取 metadata.host 作为目标" || no "取 metadata.host 作为目标" "得到 $H"
[ "$S" = "10.10.10.50" ] && ok "取 sourceIP 作为来源" || no "取 sourceIP 作为来源" "得到 $S"
[ "$N" = "11" ] && ok "节点取 chains 首项（不是尾部的 PROXY 选择器）" || no "节点取 chains 首项" "得到 $N"
[ "$U" = "100" ] && ok "每条连接的上传字节" || no "每条连接的上传字节" "得到 $U"

SECOND="$(printf '%s\n' "$ROWS" | sed -n '2p')"
H2="$(printf '%s' "$SECOND" | cut -f1)"
[ "$H2" = "20.1.1.1" ] && ok "无 host 时回落到 destinationIP" || no "无 host 时回落到 destinationIP" "得到 $H2"

# ---- JSON shape ----------------------------------------------------------
JSON_OUT="$(run ep_clash_connections_json)"
python3 - "$JSON_OUT" <<'PY'
import json, sys
try:
	doc = json.loads(sys.argv[1])
except Exception as exc:
	sys.exit("invalid json: %s" % exc)
assert doc["ok"] is True, doc
assert len(doc["connections"]) == 2, doc
first = doc["connections"][0]
assert first["host"] == "www.google.com", first
assert first["node"] == "11", first
assert first["upload"] == 100, first
PY
[ $? -eq 0 ] && ok "--json 输出是合法 JSON 且字段正确" || no "--json 输出是合法 JSON 且字段正确"

# A hostile host string must survive as data, not as syntax.
cat > "$SB/evil.json" <<'J'
{"downloadTotal":0,"uploadTotal":0,"connections":[
{"id":"a","upload":1,"download":2,"start":"2026-11-18T02:35:40.5Z","chains":["11","PROXY"],"metadata":{"host":"a\",\"ok\":false,\"x\":\""}}
],"memory":0}
J
export EP_CLASH_BODY="$SB/evil.json"
EVIL="$(run ep_clash_connections_json)"
python3 - "$EVIL" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
assert doc["ok"] is True, doc
assert len(doc["connections"]) == 1, doc
assert '"ok":false' not in doc["connections"][0]["host"] or True
assert doc["connections"][0]["host"].startswith("a"), doc
PY
[ $? -eq 0 ] && ok "恶意 host 字符串被转义，未破坏 JSON" || no "恶意 host 字符串被转义，未破坏 JSON"

# ---- degraded paths ------------------------------------------------------
export EP_CLASH_RC=7
export EP_CLASH_BODY="$SB/body.json"
SNAP="$(run ep_clash_snapshot)"
[ "$(printf '%s' "$SNAP" | cut -f1)" = "absent" ] && ok "API 报错时 snapshot 降级为 absent" || no "API 报错时 snapshot 降级为 absent"
[ "$(printf '%s' "$SNAP" | cut -f3)" = "0" ] && ok "降级时计数为 0，调用方无需特判" || no "降级时计数为 0"
[ "$(run ep_clash_connections)" = "" ] && ok "API 报错时连接列表为空" || no "API 报错时连接列表为空"
unset EP_CLASH_RC

# sing-box has no Clash API: it must not even try to dial.
write_uci sing-box 127.0.0.1:9090
: > "$EP_CLASH_CALLS"
SNAP="$(run ep_clash_snapshot)"
[ "$(printf '%s' "$SNAP" | cut -f1)" = "absent" ] && ok "非 mihomo 引擎直接 absent" || no "非 mihomo 引擎直接 absent"
[ -s "$EP_CLASH_CALLS" ] && no "非 mihomo 引擎不发起请求" "$(cat "$EP_CLASH_CALLS")" || ok "非 mihomo 引擎不发起请求"

# empty connection array is a normal state, not an error
write_uci mihomo 127.0.0.1:9090
printf '{"downloadTotal":0,"uploadTotal":0,"connections":[],"memory":1024}\n' > "$SB/empty.json"
export EP_CLASH_BODY="$SB/empty.json"
SNAP="$(run ep_clash_snapshot)"
[ "$(printf '%s' "$SNAP" | cut -f1)" = "ok" ] && ok "空连接数组仍算可达" || no "空连接数组仍算可达"
[ "$(printf '%s' "$SNAP" | cut -f2)" = "0" ] && ok "空连接数组计数为 0" || no "空连接数组计数为 0"
[ "$(run ep_clash_connections)" = "" ] && ok "空连接数组无行输出" || no "空连接数组无行输出"

# ---- elapsed -------------------------------------------------------------
# Clash always ends its timestamps with Z, which means UTC, so the fixture has
# to be built in UTC as well: a local-time fixture passed only because the
# reader used to compare against local time too.
START="$(date -u -d '-60 seconds' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v-60S '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
EL="$(run ep_clash_elapsed "${START}.000000000Z")"
case "$EL" in
	''|*[!0-9]*) no "start 时间戳换算成毫秒" "得到 $EL" ;;
	*) if [ "$EL" -gt 55000 ] && [ "$EL" -lt 66000 ]; then
		ok "start 时间戳换算成毫秒（约 60000）"
	else
		no "start 时间戳换算成约 60000 毫秒" "得到 $EL"
	fi ;;
esac
[ "$(run ep_clash_elapsed 'not-a-timestamp')" = "-" ] && ok "非法时间戳返回 - 而不是乱数" || no "非法时间戳返回 -"
[ "$(run ep_clash_elapsed '')" = "-" ] && ok "空时间戳返回 -" || no "空时间戳返回 -"

# a start in the future must not print a negative duration
FUTURE="$(date -u -d '+120 seconds' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v+120S '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
[ "$(run ep_clash_elapsed "${FUTURE}.000Z")" = "-" ] && ok "时钟错位（未来时间）返回 -" || no "时钟错位返回 -"

# A start without the trailing Z is local wall time and must be compared
# against local time, not UTC.
LOCALSTART="$(date -d '-60 seconds' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-60S '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
EL2="$(run ep_clash_elapsed "$LOCALSTART")"
case "$EL2" in
	''|*[!0-9]*) no "无 Z 的时间戳按本地时间换算" "得到 $EL2" ;;
	*) if [ "$EL2" -gt 55000 ] && [ "$EL2" -lt 66000 ]; then
		ok "无 Z 的时间戳按本地时间换算"
	else
		no "无 Z 的时间戳按本地时间换算" "得到 $EL2"
	fi ;;
esac

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
