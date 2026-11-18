#!/usr/bin/env sh
# Selector-group suite: reading PROXY and pointing it somewhere else.
#
#   sh tests/test-clash-group.sh
#
# The generator now emits PROXY (select) + one url-test group per region. What
# the user does with that is switch it, and a switch that silently does nothing
# is worse than no switch at all - so both the read side (what is selected,
# what can be selected) and the write side (did the API accept it) are pinned
# here.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/lib" "$SB/bin"
for f in common.sh node.sh clash.sh; do
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" "$SB/lib/$f"
done

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		get) shift; k="$1"
			awk -v k="$k=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$DB"; exit 0 ;;
		*) shift ;;
	esac
done
exit 0
UCI
chmod +x "$SB/bin/uci"

# Answers /proxies/PROXY like mihomo does, and records a PUT so the test can
# assert the exact body the switch sent.
cat > "$SB/bin/curl" <<'CURL'
#!/bin/sh
for a in "$@"; do
	case "$a" in
		*"/proxies/PROXY"*) target=1 ;;
	esac
done
case "$*" in
	*"PUT"*)
		printf '%s\n' "$*" >> "${EP_TEST_CURL_LOG:?}"
		printf '%s' "${EP_TEST_PUT_REPLY:-}"
		exit 0 ;;
esac
[ -n "${target:-}" ] && cat "${EP_TEST_JSON:?}"
exit 0
CURL
chmod +x "$SB/bin/curl"

export PATH="$SB/bin:$PATH"
export EP_TEST_UCI_DB="$SB/uci.db"
export EP_TEST_CURL_LOG="$SB/curl.log"
: > "$EP_TEST_UCI_DB"
: > "$EP_TEST_CURL_LOG"
printf 'easyproxy.main.engine=mihomo\n' >> "$EP_TEST_UCI_DB"
printf 'easyproxy.main.enabled=1\n' >> "$EP_TEST_UCI_DB"

# A provider name can carry a comma; a naive comma split would tear it apart.
JSONFILE="$SB/proxies.json"
cat > "$JSONFILE" <<'JSON'
{"name":"PROXY","type":"Selector","now":"自动-日本","all":["DIRECT","所有-自动","自动-美国","自动-日本","🇺🇸_US_美国,IPV4 (6)","🇯🇵_JP_日本_IPV4 (3)"],"history":[{"time":"2026-11-18T02:00:00Z","delay":120}],"dialer-proxy":"","emptyFallback":"COMPATIBLE","hidden":false}
JSON
export EP_TEST_JSON="$JSONFILE"

cat > "$SB/probe.sh" <<PROBE
#!/bin/sh
PATH="$SB/bin:\$PATH"
export EP_TEST_UCI_DB="$EP_TEST_UCI_DB" EP_TEST_CURL_LOG="$EP_TEST_CURL_LOG" EP_TEST_JSON="$EP_TEST_JSON"
for f in common.sh node.sh clash.sh; do . "$SB/lib/\$f"; done
"\$@"
PROBE
chmod +x "$SB/probe.sh"

say "代理组读取与切换"

# --- read -------------------------------------------------------------------
members="$(sh "$SB/probe.sh" ep_clash_group_members PROXY)"
count="$(printf '%s\n' "$members" | grep -c .)"

[ "$count" = "6" ] && ok "解析出 6 个成员" || no "成员数不对（期望 6，实际 $count）" "$members"
printf '%s\n' "$members" | grep -q 'dialer-proxy' && no "把 all 之后的字段也吃进来了" "$members" || ok "只取 all 段，不吞后续字段"
printf '%s\n' "$members" | grep -qx '🇯🇵_JP_日本_IPV4 (3)' && ok "带空格的成员名完整保留" || no "带空格的成员名被拆断" "$members"
printf '%s\n' "$members" | grep -qx '自动-日本' && ok "成员含 自动-日本" || no "成员缺 自动-日本"
printf '%s\n' "$members" | grep -qx '🇺🇸_US_美国,IPV4 (6)' && ok "名字带逗号的成员没被拆断" || no "名字带逗号的成员被拆断" "$members"
printf '%s\n' "$members" | grep -qx 'DIRECT' && ok "成员含 DIRECT" || no "成员缺 DIRECT"

now="$(sh "$SB/probe.sh" ep_clash_group_now PROXY)"
[ "$now" = "自动-日本" ] && ok "读到当前选中 自动-日本" || no "当前选中读错：$now"

# --- switch -----------------------------------------------------------------
say "切换"
if sh "$SB/probe.sh" ep_clash_select PROXY '自动-美国' >/dev/null 2>&1; then
	ok "切换到 自动-美国 成功"
else
	no "切换失败"
fi
grep -q '"name":"自动-美国"' "$EP_TEST_CURL_LOG" && ok "发送的 body 正确" || no "body 不对" "$(cat "$EP_TEST_CURL_LOG")"
grep -q 'PUT' "$EP_TEST_CURL_LOG" && ok "用的是 PUT" || no "没用 PUT"

# mihomo rejects a name that is not a member with this exact message
export EP_TEST_PUT_REPLY='{"message":"Selector update error: proxy not exist"}'
if sh "$SB/probe.sh" ep_clash_select PROXY '不存在' >/dev/null 2>&1; then
	no "API 报错时切换仍返回成功"
else
	ok "API 拒绝时切换返回失败"
fi
unset EP_TEST_PUT_REPLY || :

# --- no engine ---------------------------------------------------------------
say "非 mihomo 引擎"
printf 'easyproxy.main.engine=sing-box\n' > "$EP_TEST_UCI_DB"
if sh "$SB/probe.sh" ep_clash_select PROXY '自动-美国' >/dev/null 2>&1; then
	no "sing-box 下切换仍返回成功"
else
	ok "sing-box 下切换明确失败"
fi

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
