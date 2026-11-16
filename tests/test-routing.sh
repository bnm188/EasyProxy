#!/usr/bin/env sh
# Stage 4 routing suite: 分流规则 + DNS 段落 in the generated config.
#
#   sh tests/test-routing.sh
#
# Runs in a temp sandbox with a stub UCI and a stub engine. Rule sets are
# injected as fake local files, so no download and no network is needed.
# Pass EP_SING_BOX_BIN to also validate the output with a real binary.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin" "$SB/run" "$SB/log" "$SB/rules"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh" "$SB/usr/lib/easyproxy/common.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/config.sh" "$SB/usr/lib/easyproxy/config.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/transparent.sh" "$SB/usr/lib/easyproxy/transparent.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

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

write_ucis() {
	cat > "$SB/etc/uci.db" <<DB
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.main.listen=127.0.0.1
easyproxy.main.listen_port=7890
easyproxy.routing.china_policy=$1
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.routing.rule_set_dir=$SB/rules
easyproxy.routing.geosite_cn_url=${2:-https://example.com/geosite-cn.srs}
easyproxy.routing.geoip_cn_url=${3:-https://example.com/geoip-cn.srs}
easyproxy.sing_box.config_file=$SB/etc/sing-box.json
easyproxy.sing_box.binary=$SB/bin/sing-box
easyproxy.@node[0]=node
easyproxy.@node[0].name=hk-01
easyproxy.@node[0].type=shadowsocks
easyproxy.@node[0].server=203.0.113.10
easyproxy.@node[0].port=8388
easyproxy.@node[0].method=aes-256-gcm
easyproxy.@node[0].password=pw-hk
DB
}

# The engine validates rule-set files too, so when a real binary is available
# the fixtures are compiled with it; otherwise placeholder bytes are used.
seed_rules() {
	real="${EP_SING_BOX_BIN:-$(command -v sing-box 2>/dev/null || true)}"
	if [ -n "$real" ] && [ -x "$real" ] && [ "$real" != "$SB/bin/sing-box" ]; then
		printf '{"version":1,"rules":[{"domain_suffix":[".cn"]}]}' > "$SB/src-geosite.json"
		printf '{"version":1,"rules":[{"ip_cidr":["1.0.0.0/8"]}]}' > "$SB/src-geoip.json"
		"$real" rule-set compile -o "$SB/rules/geosite-cn.srs" "$SB/src-geosite.json" >/dev/null 2>&1
		"$real" rule-set compile -o "$SB/rules/geoip-cn.srs" "$SB/src-geoip.json" >/dev/null 2>&1
	fi
	[ -s "$SB/rules/geosite-cn.srs" ] || printf 'fake-geosite' > "$SB/rules/geosite-cn.srs"
	[ -s "$SB/rules/geoip-cn.srs" ] || printf 'fake-geoip' > "$SB/rules/geoip-cn.srs"
}

json_py() { code="$1"; shift; python3 -c "$code" "$@" 2>/dev/null; }
gen() { "$EP" config generate --json > "$SB/g.json" 2>"$SB/g.err"; }

seed_rules

# --- 1. china_policy=direct -------------------------------------------------
write_ucis direct
gen; rc=$?
[ "$rc" -eq 0 ] && ok "生成成功（china=direct）" || no "生成成功（china=direct）" "rc=$rc $(cat "$SB/g.err")"

json_py "import json,sys;d=json.load(open('$CFG'));print(len(d.get('route',{}).get('rules',[])))" > "$SB/n1"
[ "$(cat "$SB/n1")" = "2" ] && ok "route.rules 有 2 条（内网直连 + 大陆直连）" || no "route.rules 有 2 条" "实际 $(cat "$SB/n1") 条"

json_py "import json,sys;d=json.load(open('$CFG'));print([r['tag'] for r in d['route'].get('rule_set',[])])" > "$SB/n2"
grep -q "geosite-cn" "$SB/n2" && grep -q "geoip-cn" "$SB/n2" \
	&& ok "声明了 geosite-cn 与 geoip-cn 规则集" || no "声明了 geosite-cn 与 geoip-cn 规则集" "$(cat "$SB/n2")"

json_py "import json,sys;d=json.load(open('$CFG'));rs=d['route']['rule_set'];print(all(r['type']=='local' for r in rs), all(r['path'].startswith('$SB/rules') for r in rs))" > "$SB/n5"
[ "$(cat "$SB/n5")" = "True True" ] && ok "规则集引用本地文件（启动不依赖联网）" || no "规则集引用本地文件" "$(cat "$SB/n5")"

json_py "import json,sys;d=json.load(open('$CFG'));print([r.get('outbound') for r in d['route']['rules'] if 'rule_set' in r])" > "$SB/n3"
grep -q "direct" "$SB/n3" && ok "大陆规则集指向 direct" || no "大陆规则集指向 direct" "$(cat "$SB/n3")"

json_py "import json,sys;d=json.load(open('$CFG'));print(d['route']['final'])" > "$SB/n4"
[ "$(cat "$SB/n4")" = "proxy" ] && ok "有节点时 route.final=proxy" || no "有节点时 route.final=proxy" "$(cat "$SB/n4")"

# --- 2. dns block -----------------------------------------------------------
json_py "import json,sys;d=json.load(open('$CFG'));print([s['tag'] for s in d['dns']['servers']])" > "$SB/d1"
grep -q "dns-local" "$SB/d1" && grep -q "dns-remote" "$SB/d1" \
	&& ok "dns 有 local 与 remote 两个上游" || no "dns 有 local 与 remote 两个上游" "$(cat "$SB/d1")"

json_py "import json,sys;d=json.load(open('$CFG'));print(d['dns']['final'])" > "$SB/d2"
[ "$(cat "$SB/d2")" = "dns-remote" ] && ok "dns.final=dns-remote（有节点时）" || no "dns.final=dns-remote" "$(cat "$SB/d2")"

json_py "import json,sys;d=json.load(open('$CFG'));print([r.get('server') for r in d['dns']['rules']])" > "$SB/d3"
grep -q "dns-local" "$SB/d3" && ok "dns 规则把大陆域名交给 local" || no "dns 规则把大陆域名交给 local" "$(cat "$SB/d3")"

json_py "import json,sys;d=json.load(open('$CFG'));print(d['dns']['servers'][1]['detour'])" > "$SB/d4"
[ "$(cat "$SB/d4")" = "proxy" ] && ok "remote dns 走 proxy 出站" || no "remote dns 走 proxy 出站" "$(cat "$SB/d4")"

# --- 3. china_policy=proxy removes the CN rule ------------------------------
write_ucis proxy
gen; rc=$?
[ "$rc" -eq 0 ] && ok "生成成功（china=proxy）" || no "生成成功（china=proxy）" "rc=$rc $(cat "$SB/g.err")"
json_py "import json,sys;d=json.load(open('$CFG'));print('geosite-cn' in json.dumps(d))" > "$SB/p1"
[ "$(cat "$SB/p1")" = "False" ] && ok "china=proxy 时不生成大陆直连规则" || no "china=proxy 时不生成大陆直连规则"
json_py "import json,sys;d=json.load(open('$CFG'));print(len(d['route']['rules']))" > "$SB/p2"
[ "$(cat "$SB/p2")" = "1" ] && ok "china=proxy 时只剩内网直连规则" || no "china=proxy 时只剩内网直连规则" "实际 $(cat "$SB/p2")"

# --- 4. no nodes: everything must fall back to direct -----------------------
write_ucis direct
sed -i '/easyproxy\.@node\[0\]/d' "$SB/etc/uci.db"
gen; rc=$?
[ "$rc" -eq 0 ] && ok "无节点时生成成功" || no "无节点时生成成功" "rc=$rc $(cat "$SB/g.err")"
json_py "import json,sys;d=json.load(open('$CFG'));print(d['route']['final'],d['dns']['final'],len(d['dns']['servers']))" > "$SB/e1"
[ "$(cat "$SB/e1")" = "direct dns-local 1" ] && ok "无节点时 final 与 dns 全部退回 direct/local" || no "无节点时 final 与 dns 全部退回 direct/local" "$(cat "$SB/e1")"

# --- 4b. rule sets unavailable and undownloadable: degrade to full proxy ---
write_ucis direct "http://127.0.0.1:1/geosite-cn.srs" "http://127.0.0.1:1/geoip-cn.srs"
rm -f "$SB/rules/"*.srs
gen; rc=$?
[ "$rc" -eq 0 ] && ok "规则集下载失败仍能生成配置" || no "规则集下载失败仍能生成配置" "rc=$rc $(cat "$SB/g.err")"
json_py "import json,sys;d=json.load(open('$CFG'));print(len(d['route']['rules']),d['route']['final'])" > "$SB/w1"
[ "$(cat "$SB/w1")" = "1 proxy" ] && ok "缺规则集时退回全代理（只剩内网直连规则）" || no "缺规则集时退回全代理" "$(cat "$SB/w1")"
grep -qi 'rule set' "$SB/g.err" && ok "降级时给出警告" || no "降级时给出警告" "$(cat "$SB/g.err")"

# --- 5. status exposes the routing shape -----------------------------------
write_ucis direct
seed_rules
gen
out="$("$EP" status --json)"
json_py "import json,sys;d=json.loads(sys.argv[1]);print(d.get('china_rule'),d.get('route_rules'),d.get('dns_mode'),d.get('rule_set_state'))" "$out" > "$SB/s1"
[ "$(cat "$SB/s1")" = "1 2 split ready" ] && ok "status 报出 china_rule/route_rules/dns_mode/rule_set_state" || no "status 报出四个分流字段" "$(cat "$SB/s1")"

rm -f "$SB/rules/"*.srs
out="$("$EP" status --json)"
json_py "import json,sys;d=json.loads(sys.argv[1]);print(d.get('china_rule'),d.get('rule_set_state'))" "$out" > "$SB/s2"
[ "$(cat "$SB/s2")" = "0 missing" ] && ok "规则集缺失时 status 降级为 all-proxy/missing" || no "规则集缺失时 status 降级" "$(cat "$SB/s2")"
seed_rules
gen

# --- 6. real validator accepts the whole thing -----------------------------
REAL="${EP_SING_BOX_BIN:-$(command -v sing-box 2>/dev/null || true)}"
if [ -n "$REAL" ] && [ -x "$REAL" ] && [ "$REAL" != "$SB/bin/sing-box" ]; then
	if timeout 60 "$REAL" check -c "$CFG" >/dev/null 2>&1; then
		ok "真实 sing-box check 通过（含 dns 与 rule_set）"
	else
		no "真实 sing-box check 通过" "$(timeout 60 "$REAL" check -c "$CFG" 2>&1 | tail -3)"
	fi
else
	say "  SKIP  本机无真实 sing-box，跳过 check"
fi

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
