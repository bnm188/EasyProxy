#!/usr/bin/env sh
# Stage 5 transparent-proxy suite: tproxy inbound + nftables/route takeover.
#
#   sh tests/test-transparent.sh
#
# Runs in a temp sandbox with a stub UCI, a stub engine, a stub `nft` and a
# stub `ip`, so the firewall state machine can be exercised without touching
# the host. Nothing here needs root or a real netfilter stack.
# Pass EP_SING_BOX_BIN to also validate the generated config for real.

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
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/transparent.sh" "$SB/usr/lib/easyproxy/transparent.sh" 2>/dev/null || : > "$SB/usr/lib/easyproxy/transparent.sh"
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

# Engine stub: `check` parses the JSON, `run` stays alive so runtime=running.
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

# nft stub: `-f` applies (creates a marker and records the script), `list`
# reports the table, `delete` drops it. Only what the CLI uses is modelled.
cat > "$SB/bin/nft" <<'NFT'
#!/bin/sh
[ -f "$EP_TEST_NFT_BROKEN" ] && { echo "nft: not available" >&2; exit 1; }
case "$1" in
	-f)
		cp "$2" "$EP_TEST_NFT_APPLIED" 2>/dev/null
		touch "$EP_TEST_NFT_TABLE"
		exit 0
		;;
	list)
		[ -f "$EP_TEST_NFT_TABLE" ] || { echo "nft: no such file or directory" >&2; exit 1; }
		echo "table ip easyproxy {"
		exit 0
		;;
	delete)
		shift
		[ -f "$EP_TEST_NFT_TABLE" ] || { echo "nft: no such file or directory" >&2; exit 1; }
		rm -f "$EP_TEST_NFT_TABLE"
		exit 0
		;;
esac
exit 0
NFT
chmod +x "$SB/bin/nft"

# ip stub: keeps a tiny state file with the policy rule and the local route.
cat > "$SB/bin/ip" <<'IP'
#!/bin/sh
S="$EP_TEST_IP_STATE"
[ -f "$S" ] || : > "$S"
arg_after() { key="$1"; shift; prev=""; for a in "$@"; do [ "$prev" = "$key" ] && { echo "$a"; return 0; }; prev="$a"; done }
tbl="$(arg_after table "$@")"
if [ "$1" = "rule" ]; then
	mark="$(arg_after fwmark "$@")"
	case "$mark" in 0x*) ;; '') ;; *) mark="0x$mark" ;; esac
	[ -n "$tbl" ] || tbl="$(arg_after lookup "$@")"
	case "$2" in
		add) grep -q "rule fwmark $mark lookup $tbl" "$S" || echo "rule fwmark $mark lookup $tbl" >> "$S" ;;
		del) grep -v "rule fwmark $mark lookup $tbl" "$S" > "$S.tmp" 2>/dev/null; mv "$S.tmp" "$S" ;;
		show) sed 's/^rule //' "$S" 2>/dev/null ;;
	esac
	exit 0
fi
if [ "$1" = "addr" ] || [ "$1" = "-4" ] || [ "$1" = "-o" ]; then
	# Only what the bypass builder needs: the router's own LAN IPv4 addresses.
	dev="$(arg_after dev "$@")"
	case "$dev" in
		br-lan) echo "2: br-lan    inet 192.168.10.1/24 brd 192.168.10.255 scope global br-lan" ;;
		br-guest) echo "3: br-guest    inet 10.10.10.10/24 brd 10.10.10.255 scope global br-guest" ;;
		br-mgmt) echo "4: br-mgmt    inet 198.51.100.9/24 brd 198.51.100.255 scope global br-mgmt" ;;
		*) [ "$EP_TEST_IP_NOADDR" = "1" ] || echo "1: lo    inet 127.0.0.1/8 scope host lo" ;;
	esac
	exit 0
fi
if [ "$1" = "route" ]; then
	case "$2" in
		add)
			[ "$EP_TEST_IP_ROUTE_FAIL" = "1" ] && exit 1
			grep -q "route $tbl local default dev lo" "$S" || echo "route $tbl local default dev lo" >> "$S"
			;;
		del) grep -v "route $tbl local default dev lo" "$S" > "$S.tmp" 2>/dev/null; mv "$S.tmp" "$S" ;;
		show) sed -n "s/^route $tbl //p" "$S" 2>/dev/null ;;
	esac
	exit 0
fi
exit 0
IP
chmod +x "$SB/bin/ip"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export EP_TEST_NFT_TABLE="$SB/nft.table"
export EP_TEST_NFT_APPLIED="$SB/nft.applied"
export EP_TEST_NFT_BROKEN="$SB/nft.broken"
export EP_TEST_IP_STATE="$SB/ip.state"
export EP_NFT_FILE="$SB/etc/nftables.conf"
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
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.routing.rule_set_dir=$SB/rules
easyproxy.sing_box.config_file=$SB/etc/sing-box.json
easyproxy.sing_box.binary=$SB/bin/sing-box
easyproxy.transparent.enabled=${1:-1}
easyproxy.transparent.tproxy_port=${2:-7891}
easyproxy.transparent.fwmark=${3:-1}
easyproxy.transparent.route_table=${4:-100}
easyproxy.transparent.lan_interfaces=${5:-br-lan}
easyproxy.transparent.exclude=${6:-}
easyproxy.@node[0]=node
easyproxy.@node[0].name=hk-01
easyproxy.@node[0].type=shadowsocks
easyproxy.@node[0].server=203.0.113.10
easyproxy.@node[0].port=8388
easyproxy.@node[0].method=aes-256-gcm
easyproxy.@node[0].password=pw-hk
DB
}

json_py() { code="$1"; shift; python3 -c "$code" "$@" 2>/dev/null; }
gen() { "$EP" config generate --json > "$SB/g.json" 2>"$SB/g.err"; }

write_ucis 1
gen; rc=$?
[ "$rc" -eq 0 ] && ok "transparent 开启时配置生成成功" || no "transparent 开启时配置生成成功" "rc=$rc $(cat "$SB/g.err")"

# --- 1. tproxy inbound in the generated config -----------------------------
json_py "import json,sys;d=json.load(open('$CFG'));print([i['tag'] for i in d['inbounds']])" > "$SB/t1"
grep -q "tproxy-in" "$SB/t1" && ok "生成物包含 tproxy-in 入站" || no "生成物包含 tproxy-in 入站" "$(cat "$SB/t1")"
json_py "import json,sys;d=json.load(open('$CFG'));i=[x for x in d['inbounds'] if x['tag']=='tproxy-in'][0];print(i['listen'],i['listen_port'],i.get('sniff'))" > "$SB/t2"
[ "$(cat "$SB/t2")" = "0.0.0.0 7891 True" ] && ok "tproxy 监听 0.0.0.0:7891 且开启 sniff" || no "tproxy 监听与 sniff" "$(cat "$SB/t2")"
json_py "import json,sys;d=json.load(open('$CFG'));print(d['route'].get('auto_detect_interface'))" > "$SB/t3"
[ "$(cat "$SB/t3")" = "True" ] && ok "透明模式启用 auto_detect_interface" || no "透明模式启用 auto_detect_interface" "$(cat "$SB/t3")"
json_py "import json,sys;d=json.load(open('$CFG'));print(len(d['inbounds']))" > "$SB/t4"
[ "$(cat "$SB/t4")" = "2" ] && ok "仍保留 mixed 入站（共 2 个）" || no "仍保留 mixed 入站" "$(cat "$SB/t4")"

# --- 2. disabled transparent leaves the config alone ----------------------
write_ucis 0
gen
json_py "import json,sys;d=json.load(open('$CFG'));print('tproxy-in' in json.dumps(d), d['route'].get('auto_detect_interface'))" > "$SB/t5"
[ "$(cat "$SB/t5")" = "False None" ] && ok "transparent=0 时不生成 tproxy 入站" || no "transparent=0 时不生成 tproxy 入站" "$(cat "$SB/t5")"

# --- 3. real validator accepts the transparent config ---------------------
write_ucis 1
gen
REAL="${EP_SING_BOX_BIN:-$(command -v sing-box 2>/dev/null || true)}"
if [ -n "$REAL" ] && [ -x "$REAL" ] && [ "$REAL" != "$SB/bin/sing-box" ]; then
	if timeout 60 "$REAL" check -c "$CFG" >/dev/null 2>&1; then
		ok "真实 sing-box check 通过（含 tproxy 入站）"
	else
		no "真实 sing-box check 通过" "$(timeout 60 "$REAL" check -c "$CFG" 2>&1 | tail -3)"
	fi
else
	say "  SKIP  本机无真实 sing-box，跳过 check"
fi

# --- 4. apply refuses to capture while the engine is not running ----------
out="$("$EP" transparent apply 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "引擎未运行时拒绝接管" || no "引擎未运行时拒绝接管" "rc=$rc"
printf '%s' "$out" | grep -qi 'not running' && ok "拒绝原因明确（not running）" || no "拒绝原因明确" "$out"
[ -f "$EP_TEST_NFT_TABLE" ] && no "拒绝时不应写 nft 表" || ok "拒绝时没有写 nft 表"

# --- 5. apply after the engine is up -------------------------------------
"$EP" start > "$SB/start.log" 2>&1
sleep 1
out="$("$EP" status --json)"
json_py "import json,sys;print(json.loads(sys.argv[1])['runtime'])" "$out" > "$SB/r0"
[ "$(cat "$SB/r0")" = "running" ] && ok "引擎已启动（前置条件成立）" || no "引擎已启动" "$(cat "$SB/r0")"

out="$("$EP" transparent apply 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "引擎运行时接管成功" || no "引擎运行时接管成功" "rc=$rc $out"
[ -f "$EP_TEST_NFT_TABLE" ] && ok "nft 表已建立" || no "nft 表已建立"
[ -s "$EP_NFT_FILE" ] && ok "把规则写成了可检查的文件 ($EP_NFT_FILE)" || no "规则文件已写出"

grep -q 'table ip easyproxy' "$EP_NFT_FILE" && ok "独立 table ip easyproxy（不碰 fw4）" || no "独立 table ip easyproxy"
grep -q '203.0.113.10' "$EP_NFT_FILE" && ok "节点服务器地址进入 bypass 集合" || no "节点服务器地址进入 bypass 集合" "$(cat "$EP_NFT_FILE")"
grep -q '192.168.0.0/16' "$EP_NFT_FILE" && ok "私有网段进入 bypass 集合" || no "私有网段进入 bypass 集合"
grep -q '10.0.0.0/8' "$EP_NFT_FILE" && ok "10.0.0.0/8 进入 bypass 集合" || no "10.0.0.0/8 进入 bypass 集合"
grep -q '172.16.0.0/12' "$EP_NFT_FILE" && ok "172.16.0.0/12 进入 bypass 集合" || no "172.16.0.0/12 进入 bypass 集合"
grep 'elements = {' "$EP_NFT_FILE" | grep -q '10.10.10.10/32' && no "bypass 集合不应出现被 10.0.0.0/8 覆盖的 10.10.10.10/32" "$(grep elements "$EP_NFT_FILE")" || ok "bypass 集合没有 10.10.10.10/32 这种被大段覆盖的条目"
grep -q '# covered by 10.0.0.0/8: 10.10.10.10/32' "$EP_NFT_FILE" && ok "10.10.10.10 的覆盖关系写进注释（仍受保护且可审计）" || no "10.10.10.10 的覆盖关系写进注释" "$(cat "$EP_NFT_FILE")"
grep -q '# covered by 192.168.0.0/16: 192.168.10.1/32' "$EP_NFT_FILE" && ok "路由器自身 LAN 地址的覆盖关系写进注释" || no "路由器自身 LAN 地址的覆盖关系写进注释" "$(cat "$EP_NFT_FILE")"
if python3 - "$EP_NFT_FILE" >"$SB/iv" 2>&1 <<'PY'
import re, sys
txt = open(sys.argv[1]).read()
m = re.search(r'elements\s*=\s*\{([^}]*)\}', txt, re.S)
if not m:
    sys.exit("no elements block")
items = [x.strip() for x in m.group(1).split(',') if x.strip()]
def span(c):
    parts = c.split('/')
    ip = parts[0]
    octets = [int(x) for x in ip.split('.')]
    bits = int(parts[1]) if len(parts) > 1 else 32
    start = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
    size = 1 << (32 - bits)
    start -= start % size
    return start, start + size - 1
spans = sorted((span(c)[0], span(c)[1], c) for c in items)
for a, b in zip(spans, spans[1:]):
    if b[0] <= a[1]:
        sys.exit("overlap: %s and %s" % (a[2], b[2]))
print("disjoint %d" % len(spans))
PY
then ok "bypass 区间互不重叠（nftables interval 集合不会报 File exists）"; else no "bypass 区间互不重叠" "$(cat "$SB/iv")"; fi
grep -q 'iifname != "br-lan"' "$EP_NFT_FILE" && ok "只接管 br-lan 入向流量" || no "只接管 br-lan 入向流量" "$(cat "$EP_NFT_FILE")"
grep -q 'tproxy to :7891' "$EP_NFT_FILE" && ok "tproxy 指向 7891" || no "tproxy 指向 7891"
grep -q 'meta mark set 1' "$EP_NFT_FILE" && ok "打上 fwmark 1" || no "打上 fwmark 1"
grep -q 'tcp dport 7890 return' "$EP_NFT_FILE" && ok "放行 mixed 端口，避免回环" || no "放行 mixed 端口，避免回环"

grep -q 'fwmark 0x1 lookup 100' "$EP_TEST_IP_STATE" && ok "策略路由 rule 已添加" || no "策略路由 rule 已添加" "$(cat "$EP_TEST_IP_STATE")"
grep -q 'route 100 local default dev lo' "$EP_TEST_IP_STATE" && ok "local 路由表 100 已添加" || no "local 路由表 100 已添加" "$(cat "$EP_TEST_IP_STATE")"

# --- 6. idempotent apply -------------------------------------------------
"$EP" transparent apply >/dev/null 2>&1
[ "$(grep -c 'rule fwmark 0x1 lookup 100' "$EP_TEST_IP_STATE")" = "1" ] && ok "重复 apply 不重复添加 rule" || no "重复 apply 不重复添加 rule" "$(cat "$EP_TEST_IP_STATE")"
[ "$(grep -c 'route 100 local default dev lo' "$EP_TEST_IP_STATE")" = "1" ] && ok "重复 apply 不重复添加 route" || no "重复 apply 不重复添加 route"

# --- 7. status reports the takeover --------------------------------------
out="$("$EP" status --json)"
json_py "import json,sys;d=json.loads(sys.argv[1]);print(d['transparent'],d['tproxy_port'],d['tproxy_state'])" "$out" > "$SB/s1"
[ "$(cat "$SB/s1")" = "1 7891 active" ] && ok "status 报出透明代理状态 active" || no "status 报出透明代理状态" "$(cat "$SB/s1")"
"$EP" transparent status --json > "$SB/ts.json" 2>/dev/null
json_py "import json,sys;d=json.load(open('$SB/ts.json'));print(d['state'],d['port'],d['fwmark'],d['route_table'])" > "$SB/s2"
[ "$(cat "$SB/s2")" = "active 7891 1 100" ] && ok "transparent status --json 字段完整" || no "transparent status --json 字段完整" "$(cat "$SB/s2")"

# --- 8. extra excludes and multiple interfaces ---------------------------
"$EP" transparent remove >/dev/null 2>&1
write_ucis 1 7891 1 100 "br-lan br-guest" "198.51.100.7/32"
gen
"$EP" transparent apply >/dev/null 2>&1
grep -q '198.51.100.7/32' "$EP_NFT_FILE" && ok "transparent.exclude 进入 bypass 集合" || no "transparent.exclude 进入 bypass 集合" "$(cat "$EP_NFT_FILE")"
grep -q 'iifname != { "br-lan", "br-guest" }' "$EP_NFT_FILE" && ok "多个接口渲染为集合" || no "多个接口渲染为集合"
grep 'elements = {' "$EP_NFT_FILE" | grep -q '10.10.10.10/32' && no "10.10.10.10/32 不应作为独立元素出现" "$(grep elements "$EP_NFT_FILE")" || ok "多接口场景下 bypass 仍无 10.10.10.10/32 嵌套条目"
grep -q '# covered by 10.0.0.0/8: 10.10.10.10/32' "$EP_NFT_FILE" && ok "多接口场景下 10.10.10.10 仍在覆盖注释里" || no "多接口场景下 10.10.10.10 仍在覆盖注释里" "$(cat "$EP_NFT_FILE")"

# --- 8b. LAN address outside RFC1918 stays an explicit /32 ---------------
"$EP" transparent remove >/dev/null 2>&1
write_ucis 1 7891 1 100 "br-mgmt" ""
gen
"$EP" transparent apply >/dev/null 2>&1
grep -q '198.51.100.9/32' "$EP_NFT_FILE" && ok "公网段管理地址 198.51.100.9 以 /32 进 bypass" || no "公网段管理地址 198.51.100.9 以 /32 进 bypass" "$(cat "$EP_NFT_FILE")"

# --- 9. remove rolls everything back -------------------------------------
"$EP" transparent remove >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "remove 退出码 0" || no "remove 退出码 0" "rc=$rc"
[ -f "$EP_TEST_NFT_TABLE" ] && no "remove 后 nft 表应消失" || ok "remove 后 nft 表消失"
grep -q 'fwmark 0x1 lookup 100' "$EP_TEST_IP_STATE" && no "remove 后 rule 应消失" "$(cat "$EP_TEST_IP_STATE")" || ok "remove 后 rule 消失"
grep -q 'route 100 local default dev lo' "$EP_TEST_IP_STATE" && no "remove 后 route 应消失" || ok "remove 后 route 消失"
"$EP" transparent remove >/dev/null 2>&1; [ $? -eq 0 ] && ok "重复 remove 幂等" || no "重复 remove 幂等"
out="$("$EP" status --json)"
json_py "import json,sys;print(json.loads(sys.argv[1])['tproxy_state'])" "$out" > "$SB/s3"
[ "$(cat "$SB/s3")" = "inactive" ] && ok "remove 后 status 报 inactive" || no "remove 后 status 报 inactive" "$(cat "$SB/s3")"

# --- 9b. partial policy-routing failure rolls the rule back --------------
"$EP" transparent remove >/dev/null 2>&1
write_ucis 1
gen
EP_TEST_IP_ROUTE_FAIL=1 "$EP" transparent apply >"$SB/fb.out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "路由表写入失败时 apply 失败" || no "路由表写入失败时 apply 失败" "rc=$rc $(cat "$SB/fb.out")"
grep -q 'rule fwmark 0x1 lookup 100' "$EP_TEST_IP_STATE" && no "失败后不应残留 fwmark 规则" "$(cat "$EP_TEST_IP_STATE")" || ok "失败后 fwmark 规则已回滚"
grep -q 'route 100 local default dev lo' "$EP_TEST_IP_STATE" && no "失败后不应残留路由表" || ok "失败后路由表已回滚"
[ -f "$EP_TEST_NFT_TABLE" ] && no "失败后不应留下 nft 表" || ok "失败后没有留下 nft 表"
"$EP" transparent apply >/dev/null 2>&1
grep -q 'rule fwmark 0x1 lookup 100' "$EP_TEST_IP_STATE" && ok "回滚后重新 apply 仍能建立接管" || no "回滚后重新 apply 仍能建立接管" "$(cat "$EP_TEST_IP_STATE")"

# --- 10. unsupported host: no nft --------------------------------------
touch "$EP_TEST_NFT_BROKEN"
out="$("$EP" transparent apply 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "nft 不可用时拒绝接管" || no "nft 不可用时拒绝接管" "rc=$rc"
printf '%s' "$out" | grep -qi 'nft is not available' && ok "错误信息点名 nft" || no "错误信息点名 nft" "$out"
out="$("$EP" status --json)"
json_py "import json,sys;print(json.loads(sys.argv[1])['tproxy_state'])" "$out" > "$SB/s4"
[ "$(cat "$SB/s4")" = "unsupported" ] && ok "nft 不可用时 status 报 unsupported" || no "nft 不可用时 status 报 unsupported" "$(cat "$SB/s4")"
rm -f "$EP_TEST_NFT_BROKEN"

# --- 11. no nodes: no capture -------------------------------------------
"$EP" stop >/dev/null 2>&1
write_ucis 1
sed -i '/easyproxy\.@node\[0\]/d' "$SB/etc/uci.db"
"$EP" start > "$SB/start2.log" 2>&1
sleep 1
out="$("$EP" transparent apply 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "没有节点时拒绝接管" || no "没有节点时拒绝接管" "rc=$rc $out"
printf '%s' "$out" | grep -qi 'no enabled nodes' && ok "错误信息点名没有节点" || no "错误信息点名没有节点" "$out"

"$EP" stop >/dev/null 2>&1

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
