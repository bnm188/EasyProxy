#!/bin/sh
# Local regression suite for the EasyProxy CLI.
# Runs on any Linux/macOS shell with no OpenWrt dependency: UCI and logger are
# stubbed, so the whole data path can be exercised before packaging.
#
#   sh tests/test-cli.sh
#
# Exit code 0 means every case passed.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

# --- sandbox -----------------------------------------------------------------
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh" "$SB/usr/lib/easyproxy/common.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

# Fake UCI database: one "uci show"-style dump, queried by key.
cat > "$SB/etc/uci.db" <<'DB'
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.dae.config_file=/etc/easyproxy/dae.conf
easyproxy.dae.binary=/usr/bin/dae
easyproxy.sing_box.config_file=/etc/easyproxy/sing-box.json
easyproxy.sing_box.binary=/usr/bin/sing-box
easyproxy.@node[0]=node
easyproxy.@node[0].name=hk-01
easyproxy.@node[1]=node
easyproxy.@node[1].name=us-01
DB

# Point the UCI engine paths at the sandbox binaries so the test controls
# whether "the binary is installed" itself.
sed -i "s#/usr/bin/sing-box#$SB/bin/sing-box#; s#/usr/bin/dae#$SB/bin/dae#" "$SB/etc/uci.db"

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
# supports: uci [-q] get <key>   |   uci [-q] show <package>
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		get) shift; key="$1"; grep -m1 "^$key=" "$DB" | cut -d= -f2-; exit 0 ;;
		show) shift; grep "^$1" "$DB"; exit 0 ;;
		*) shift ;;
	esac
done
exit 0
UCI
chmod +x "$SB/bin/uci"
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/logger"
chmod +x "$SB/bin/logger"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
EP="$SB/usr/sbin/easyproxy"

# Fake engine binaries so binary_ok can be toggled.
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/sing-box"
chmod +x "$SB/bin/sing-box"

json_get() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

# --- 1. status --json is one valid JSON line --------------------------------
out="$("$EP" status --json)"
lines="$(printf '%s' "$out" | wc -l)"
[ "$lines" -eq 0 ] && ok "status --json 输出为单行" || no "status --json 输出为单行" "实际 ${lines} 行"
if printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
	ok "status --json 是合法 JSON"
else
	no "status --json 是合法 JSON" "$out"
fi
[ "$(printf '%s' "$out" | json_get "['ok']")" = "True" ] && ok "status ok=true" || no "status ok=true"
[ "$(printf '%s' "$out" | json_get "['version']")" = "0.2.0" ] && ok "version=0.2.0" || no "version=0.2.0"
[ "$(printf '%s' "$out" | json_get "['engine']")" = "sing-box" ] && ok "engine 来自 UCI" || no "engine 来自 UCI"
[ "$(printf '%s' "$out" | json_get "['nodes']")" = "2" ] && ok "nodes 统计出 2 个节点" || no "nodes 统计出 2 个节点"
[ "$(printf '%s' "$out" | json_get "['binary_ok']")" = "1" ] && ok "binary_ok=1（二进制可执行）" || no "binary_ok=1"

# --- 2. missing binary is reported, not invented ----------------------------
mv "$SB/bin/sing-box" "$SB/bin/sing-box.off"
out="$("$EP" status --json)"
[ "$(printf '%s' "$out" | json_get "['binary_ok']")" = "0" ] && ok "二进制缺失时 binary_ok=0" || no "二进制缺失时 binary_ok=0"
mv "$SB/bin/sing-box.off" "$SB/bin/sing-box"

# --- 3. validate happy path ------------------------------------------------
"$EP" validate --json > "$SB/v1.json"; rc=$?
[ "$rc" -eq 0 ] && ok "validate 合法配置退出码 0" || no "validate 合法配置退出码 0" "rc=$rc"
[ "$(json_get "['ok']" < "$SB/v1.json")" = "True" ] && ok "validate ok=true" || no "validate ok=true"

# --- 4. validate rejects a bad engine --------------------------------------
sed -i 's/^easyproxy.main.engine=.*/easyproxy.main.engine=clash/' "$SB/etc/uci.db"
"$EP" validate --json > "$SB/v2.json"; rc=$?
[ "$rc" -eq 1 ] && ok "validate 非法引擎退出码 1" || no "validate 非法引擎退出码 1" "rc=$rc"
[ "$(json_get "['ok']" < "$SB/v2.json")" = "False" ] && ok "validate ok=false" || no "validate ok=false"
printf '%s' "$(json_get "['messages']" < "$SB/v2.json")" | grep -q 'Invalid main.engine' \
	&& ok "validate 报出具体错误字段" || no "validate 报出具体错误字段"
sed -i 's/^easyproxy.main.engine=.*/easyproxy.main.engine=sing-box/' "$SB/etc/uci.db"

# --- 5. validate rejects china_policy=proxy as a warning only ---------------
cp "$SB/etc/uci.db" "$SB/uci.bak"
sed -i 's/^easyproxy.routing.china_policy=.*/easyproxy.routing.china_policy=proxy/' "$SB/etc/uci.db"
"$EP" validate --json > "$SB/v3.json"; rc=$?
[ "$rc" -eq 0 ] && ok "china_policy=proxy 仅警告不报错" || no "china_policy=proxy 仅警告不报错" "rc=$rc"
grep -q 'PROXY' "$SB/v3.json" && ok "china_policy=proxy 输出警告文案" || no "china_policy=proxy 输出警告文案"
cp "$SB/uci.bak" "$SB/etc/uci.db"

# --- 6. start stays guarded (no routing change in Stage 2) -----------------
out="$("$EP" start 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "start 被拦截且退出码 2" || no "start 被拦截且退出码 2" "rc=$rc"
printf '%s' "$out" | grep -q 'No firewall, DNS or route changes were made' \
	&& ok "start 明确声明未改动路由" || no "start 明确声明未改动路由"

# --- 7. engine subcommand --------------------------------------------------
out="$("$EP" engine 2>&1)"
printf '%s' "$out" | grep -q 'sing-box' && ok "engine 打印所选内核" || no "engine 打印所选内核"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
