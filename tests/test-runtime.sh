#!/bin/sh
# Stage 3 runtime suite: config generation + process supervision + status.
#
#   sh tests/test-runtime.sh
#
# Uses a stub engine binary, so no real sing-box install is required. The
# generated config is additionally handed to `sing-box check` when a real
# binary is found on PATH or in EP_SING_BOX_BIN.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin" "$SB/run" "$SB/log"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh" "$SB/usr/lib/easyproxy/common.sh"
[ -f "$SRC/package/easyproxy/files/usr/lib/easyproxy/config.sh" ] && \
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/config.sh" "$SB/usr/lib/easyproxy/config.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/transparent.sh" "$SB/usr/lib/easyproxy/transparent.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

cat > "$SB/etc/uci.db" <<DB
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.main.listen=127.0.0.1
easyproxy.main.listen_port=7890
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.sing_box.config_file=$SB/etc/sing-box.json
easyproxy.sing_box.binary=$SB/bin/sing-box
easyproxy.@node[0]=node
easyproxy.@node[0].name=hk-01
easyproxy.@node[0].type=shadowsocks
easyproxy.@node[0].server=203.0.113.10
easyproxy.@node[0].port=8388
easyproxy.@node[0].method=aes-256-gcm
easyproxy.@node[0].password=pw-hk
easyproxy.@node[1]=node
easyproxy.@node[1].name=us-01
easyproxy.@node[1].type=trojan
easyproxy.@node[1].server=198.51.100.7
easyproxy.@node[1].port=443
easyproxy.@node[1].password=pw-us
easyproxy.@node[1].sni=us.example.com
DB

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
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/logger"

# Stub engine: understands `check` and `run`, so the wrapper's lifecycle can be
# exercised without a real proxy.
cat > "$SB/bin/sing-box" <<'STUB'
#!/bin/sh
cmd="$1"; shift
case "$cmd" in
	check)
		while [ $# -gt 0 ]; do [ "$1" = "-c" ] && cfg="$2"; shift; done
		python3 -c "import json,sys; json.load(open('$cfg'))" || exit 1
		exit 0
		;;
	run)
		exec sleep 30
		;;
esac
exit 0
STUB
chmod +x "$SB/bin/sing-box" "$SB/bin/logger"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
export EP_RUNTIME_DIR="$SB/run"
export EP_LOG_FILE="$SB/log/easyproxy.log"
EP="$SB/usr/sbin/easyproxy"
CFG="$SB/etc/sing-box.json"

json_get() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }

# --- 1. config generation --------------------------------------------------
"$EP" config generate --json > "$SB/g1.json" 2>"$SB/g1.err"; rc=$?
[ "$rc" -eq 0 ] && ok "config generate 退出码 0" || no "config generate 退出码 0" "rc=$rc $(cat "$SB/g1.err")"
[ "$(json_get "['ok']" < "$SB/g1.json")" = "True" ] && ok "generate ok=true" || no "generate ok=true"
[ -f "$CFG" ] && ok "配置文件已写出" || no "配置文件已写出" "缺 $CFG"
python3 - "$CFG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
tags = [o['tag'] for o in d.get('outbounds', [])]
need = ['hk-01', 'us-01', 'proxy', 'direct']
missing = [t for t in need if t not in tags]
print('TAGS=' + ','.join(tags))
sys.exit(1 if missing else 0)
PY
[ $? -eq 0 ] && ok "生成物包含两个节点 + proxy 组 + direct" || no "生成物包含两个节点 + proxy 组 + direct"

# --- 2. generated config is a real sing-box config -------------------------
REAL="${EP_SING_BOX_BIN:-$(command -v sing-box 2>/dev/null || true)}"
if [ -n "$REAL" ] && [ -x "$REAL" ] && [ "$REAL" != "$SB/bin/sing-box" ]; then
	if "$REAL" check -c "$CFG" >/dev/null 2>&1; then
		ok "真实 sing-box check 通过（$REAL）"
	else
		no "真实 sing-box check 通过" "$("$REAL" check -c "$CFG" 2>&1 | tail -3)"
	fi
else
	say "  SKIP  本机无真实 sing-box，跳过 check"
fi

# --- 3. incomplete node is rejected ---------------------------------------
sed -i "/easyproxy.@node\[0\]\.server=/d" "$SB/etc/uci.db"
"$EP" config generate --json > "$SB/g2.json" 2>/dev/null; rc=$?
[ "$rc" -ne 0 ] && ok "缺 server 的节点被拒绝" || no "缺 server 的节点被拒绝" "rc=$rc"
[ "$(json_get "['ok']" < "$SB/g2.json")" = "False" ] && ok "拒绝时 ok=false" || no "拒绝时 ok=false"
grep -q 'hk-01' "$SB/g2.json" && ok "错误信息定位到具体节点" || no "错误信息定位到具体节点"
cp "$SB/etc/uci.db" "$SB/uci.bak"
sed -i "/easyproxy.@node\[0\]\.name=hk-01/a easyproxy.@node[0].server=203.0.113.10" "$SB/etc/uci.db"

# --- 4. no nodes means direct-only ---------------------------------------
cp "$SB/etc/uci.db" "$SB/uci.nodes"
python3 - "$SB/etc/uci.db" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'easyproxy\.@node\[[01]\]\.[a-z_]+=.*\n', '', s)
s = re.sub(r'easyproxy\.@node\[[01]\]=node\n', '', s)
open(p, 'w').write(s)
PY
"$EP" config generate --json > "$SB/g3.json" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "无节点时仍可生成（仅直连）" || no "无节点时仍可生成（仅直连）" "rc=$rc"
[ "$(json_get "['final']" < "$SB/g3.json")" = "direct" ] && ok "无节点时 final=direct" || no "无节点时 final=direct"
cp "$SB/uci.nodes" "$SB/etc/uci.db"
"$EP" config generate --json >/dev/null 2>&1

# --- 5. status reports config and runtime state ---------------------------
out="$("$EP" status --json)"
[ "$(printf '%s' "$out" | json_get "['config_state']")" = "ok" ] && ok "status 报告 config_state=ok" || no "status 报告 config_state=ok" "$out"
[ "$(printf '%s' "$out" | json_get "['runtime']")" = "stopped" ] && ok "未启动时 runtime=stopped" || no "未启动时 runtime=stopped" "$out"

# --- 6. start / stop lifecycle -------------------------------------------
"$EP" start > "$SB/start.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "start 成功" || no "start 成功" "rc=$rc $(cat "$SB/start.log")"
sleep 1
out="$("$EP" status --json)"
[ "$(printf '%s' "$out" | json_get "['runtime']")" = "running" ] && ok "启动后 runtime=running" || no "启动后 runtime=running" "$out"
pid="$(printf '%s' "$out" | json_get "['runtime_pid']")"
[ "$pid" -gt 0 ] 2>/dev/null && ok "status 给出真实 pid ($pid)" || no "status 给出真实 pid" "$out"

"$EP" stop > "$SB/stop.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "stop 成功" || no "stop 成功" "rc=$rc"
sleep 1
out="$("$EP" status --json)"
[ "$(printf '%s' "$out" | json_get "['runtime']")" = "stopped" ] && ok "停止后 runtime=stopped" || no "停止后 runtime=stopped" "$out"
pgrep -f 'sleep 30' >/dev/null 2>&1 && no "停止后无残留进程" || ok "停止后无残留进程"

# --- 7. disabled config refuses to start ---------------------------------
sed -i 's/^easyproxy.main.enabled=.*/easyproxy.main.enabled=0/' "$SB/etc/uci.db"
"$EP" start > "$SB/s2.log" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "未启用时拒绝启动" || no "未启用时拒绝启动" "rc=$rc"
grep -qi 'disabled\|未启用' "$SB/s2.log" && ok "拒绝原因清晰" || no "拒绝原因清晰" "$(cat "$SB/s2.log")"
sed -i 's/^easyproxy.main.enabled=.*/easyproxy.main.enabled=1/' "$SB/etc/uci.db"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
