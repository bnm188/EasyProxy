#!/usr/bin/env sh
# Stage 6 engine-management suite: registry, dev marking, health, node probing.
#
#   sh tests/test-engine.sh
#
# Everything runs in a sandbox: UCI, logger, nc and the engine binary are
# stubs, so the health report can be pointed at a known-good and a known-bad
# router state without touching this host. A real listening socket is opened
# with python3 to exercise the port check for real.

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
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/config.sh" "$SB/usr/lib/easyproxy/config.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/transparent.sh" "$SB/usr/lib/easyproxy/transparent.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/mihomo.sh" "$SB/usr/lib/easyproxy/mihomo.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/clash.sh" "$SB/usr/lib/easyproxy/clash.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
    -e "s#/usr/lib/easyproxy/mihomo.sh#$SB/usr/lib/easyproxy/mihomo.sh#" \
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

# nc stub: reachability and latency are decided by EP_TEST_NC_RC / _MS.
cat > "$SB/bin/nc" <<'NC'
#!/bin/sh
[ -f "$EP_TEST_NC_SLEEP" ] && sleep 0.1
case "${EP_TEST_NC_RC:-0}" in
	0) exit 0 ;;
	*) exit 1 ;;
esac
NC
chmod +x "$SB/bin/nc" "$SB/bin/logger"

# curl stub: ep_tcp_probe tries curl first now (the stripped busybox nc on the
# target firmware rejects -w and always exits 1), so reachability is decided
# here. 0 stands for a completed handshake.
cat > "$SB/bin/curl" <<'CURL'
#!/bin/sh
[ -f "$EP_TEST_NC_SLEEP" ] && sleep 0.1
case "${EP_TEST_NC_RC:-0}" in
	0) exit 0 ;;
	*) exit "${EP_TEST_CURL_RC:-7}" ;;
esac
CURL
chmod +x "$SB/bin/curl"

# Engine stub: answers version/check, and exits 0 immediately for run.
cat > "$SB/bin/sing-box" <<'ENG'
#!/bin/sh
case "$1" in
	version) echo "sing-box version ${EP_TEST_ENGINE_VERSION:-1.14.4} (test stub)" ;;
	check)
		while [ $# -gt 0 ]; do [ "$1" = "-c" ] && cfg="$2"; shift; done
		python3 -c "import json,sys; json.load(open('$cfg'))"
		;;
	run) exit 0 ;;
esac
exit 0
ENG
chmod +x "$SB/bin/sing-box"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
export EP_RUNTIME_DIR="$SB/run" EP_LOG_FILE="$SB/log/easyproxy.log"
export EP_LIB_DIR="$SB/usr/lib/easyproxy"
EP="$SB/usr/sbin/easyproxy"
CFG="$SB/etc/sing-box.json"

write_ucis() { # $1 enabled  $2 engine  $3 binary  $4 listen_port  $5 nodes(1|0)
	cat > "$SB/etc/uci.db" <<-DB
	easyproxy.main.enabled=${1:-1}
	easyproxy.main.engine=${2:-sing-box}
	easyproxy.main.listen=127.0.0.1
	easyproxy.main.listen_port=${4:-7890}
	easyproxy.main.log_level=notice
	easyproxy.routing.china_policy=direct
	easyproxy.routing.proxy_policy=proxy
	easyproxy.routing.fail_closed=1
	easyproxy.routing.rule_set_dir=$SB/rules
	easyproxy.dae.config_file=$SB/etc/dae.conf
	easyproxy.dae.binary=$SB/bin/dae
	easyproxy.sing_box.config_file=$CFG
	easyproxy.sing_box.binary=${3:-$SB/bin/sing-box}
	DB
	if [ "${5:-1}" = "1" ]; then
		cat >> "$SB/etc/uci.db" <<-DB
		easyproxy.@node[0]=node
		easyproxy.@node[0].name=hk-01
		easyproxy.@node[0].type=shadowsocks
		easyproxy.@node[0].server=203.0.113.10
		easyproxy.@node[0].port=8388
		easyproxy.@node[0].method=aes-256-gcm
		easyproxy.@node[0].password=pw-hk
		DB
	fi
}

json_py() { code="$1"; shift; python3 -c "$code" "$@" 2>/dev/null; }

write_ucis 1 sing-box

# --- 1. engine registry -----------------------------------------------------
out="$("$EP" engine list 2>&1)"
printf '%s' "$out" | grep -q 'sing-box' && ok "engine list 列出 sing-box" || no "engine list 列出 sing-box" "$out"
printf '%s' "$out" | grep -Eq 'sing-box +stable' && ok "sing-box 标记为 stable" || no "sing-box 标记为 stable" "$out"
printf '%s' "$out" | grep -Eq 'dae +dev' && ok "dae 标记为 dev（开发中）" || no "dae 标记为 dev" "$out"

out="$("$EP" engine 2>&1)"
printf '%s' "$out" | grep -q 'Selected engine: sing-box' && ok "engine 打印所选内核" || no "engine 打印所选内核" "$out"
printf '%s' "$out" | grep -q 'Status: stable' && ok "sing-box 状态为 stable" || no "sing-box 状态为 stable" "$out"
printf '%s' "$out" | grep -q 'Adapter:' && ok "engine 打印 adapter 路径" || no "engine 打印 adapter 路径" "$out"

# --- 2. dae is explicitly 开发中, never silently usable ---------------------
sed -i 's/^easyproxy.main.engine=.*/easyproxy.main.engine=dae/' "$SB/etc/uci.db"
out="$("$EP" engine 2>&1)"
printf '%s' "$out" | grep -q '开发中' && ok "dae 被标记为开发中" || no "dae 被标记为开发中" "$out"
printf '%s' "$out" | grep -q 'Status: 开发中' && ok "dae 的 Status 行直接写开发中" || no "dae 的 Status 行写开发中" "$out"

out="$("$EP" engine health 2>&1)"; rc=$?
printf '%s' "$out" | grep -q '\[warn\] dev' && ok "health 对 dae 给出 dev 警告" || no "health 对 dae 给出 dev 警告" "$out"
[ "$rc" -ne 0 ] && ok "dae 缺二进制时 health 失败" || echo "  SKIP  dae 缺二进制时 health 失败（本机 dae 存在）"

out="$("$EP" start 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "start 拒绝 dae（退出码 2）" || no "start 拒绝 dae" "rc=$rc $out"
printf '%s' "$out" | grep -q '开发中' && ok "拒绝 dae 时明确写开发中" || no "拒绝 dae 时明确写开发中" "$out"

out="$("$EP" config generate 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "config generate 拒绝 dae（尚未实现）" || no "config generate 拒绝 dae" "rc=$rc"
printf '%s' "$out" | grep -q '开发中' && ok "config generate 拒绝 dae 时点明开发中" || no "config generate 拒绝 dae 时点明开发中" "$out"

# --- 3. every version-relevant string is a real engine answer --------------
write_ucis 1 sing-box
out="$("$EP" engine version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "engine version 调用内核自身回答" || no "engine version 调用内核" "rc=$rc $out"
printf '%s' "$out" | grep -q '1.14.4' && ok "engine version 透传版本号" || no "engine version 透传版本号" "$out"

# --- 4. health: all good ---------------------------------------------------
write_ucis 1 sing-box
"$EP" config generate >/dev/null 2>&1

# Node outbounds must carry their own resolver: a DoH lookup with detour=proxy
# deadlocks on the very outbound it is trying to open.
if grep -q '"domain_resolver": "dns-local"' "$CFG" 2>/dev/null; then
	ok "节点出站自带 domain_resolver=dns-local"
else
	no "节点出站自带 domain_resolver=dns-local" "$(grep -o '"type":"[a-z0-9]*"' "$CFG" 2>/dev/null | head -3)"
fi
PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
python3 - "$PORT" >/dev/null 2>&1 <<'PY' &
import socket, sys, time
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", port))
s.listen(1)
time.sleep(3)
PY
LISTENER=$!
sleep 0.3
sed -i "s/^easyproxy.main.listen_port=.*/easyproxy.main.listen_port=$PORT/" "$SB/etc/uci.db"
printf '%s 1\n' "$LISTENER" > "$EP_RUNTIME_DIR/easyproxy.pid"
out="$("$EP" engine health 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "健康状态下 engine health 退出码 0" || no "健康状态健康检查 exit 0" "rc=$rc $out"
printf '%s' "$out" | grep -q '\[ok\].*binary' && ok "health 确认二进制可用并带版本" || no "health 确认二进制可用" "$out"
printf '%s' "$out" | grep -q '\[ok\].*config' && ok "health 确认配置被内核接受" || no "health 确认配置被内核接受" "$out"
printf '%s' "$out" | grep -q "\[ok\].*listen: port $PORT is listening" && ok "health 真的检测到监听端口" || no "health 检测监听端口" "$out"
out="$("$EP" engine health --json)"
json_py "import json,sys;d=json.loads(sys.argv[1]);print(d['ok'],len(d['checks']))" "$out" > "$SB/h1"
case "$(cat "$SB/h1")" in
	True*) ok "health --json 报 ok=true 且有检查项" ;;
	*) no "health --json 报 ok=true" "$(cat "$SB/h1")" ;;
esac
kill "$LISTENER" 2>/dev/null
rm -f "$EP_RUNTIME_DIR/easyproxy.pid"

# --- 5. health catches a missing binary and a bad config -------------------
write_ucis 1 sing-box "$SB/bin/absent"
out="$("$EP" engine health 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "二进制缺失时 health 失败" || no "二进制缺失时 health 失败" "rc=$rc"
printf '%s' "$out" | grep -q '\[FAIL\] binary' && ok "health 点名 binary 失败" || no "health 点名 binary" "$out"

write_ucis 1 sing-box
rm -f "$CFG"
out="$("$EP" engine health 2>&1)"
printf '%s' "$out" | grep -q '\[warn\] config' && ok "无生成配置时 health 只警告" || no "无生成配置时 health 只警告" "$out"

# --- 6. node connectivity test --------------------------------------------
write_ucis 1 sing-box
export EP_TEST_NC_RC=0
out="$("$EP" node test 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "可达节点 node test 退出码 0" || no "可达节点 node test 退出码 0" "rc=$rc $out"
printf '%s' "$out" | grep -q 'hk-01' && ok "node test 列出节点名" || no "node test 列出节点名" "$out"
printf '%s' "$out" | grep -q 'reachable' && ok "node test 报 reachable" || no "node test 报 reachable" "$out"
printf '%s' "$out" | grep -q 'Reachable: 1/1' && ok "node test 汇总可达数" || no "node test 汇总可达数" "$out"

out="$("$EP" node test --json)"
json_py "import json,sys;d=json.loads(sys.argv[1]);n=d['nodes'][0];print(n['name'],n['state'],isinstance(n['latency_ms'],int))" "$out" > "$SB/n1"
[ "$(cat "$SB/n1")" = "hk-01 reachable True" ] && ok "node test --json 给出名字/状态/数值延迟" || no "node test --json 结构" "$(cat "$SB/n1")"

export EP_TEST_NC_RC=1
out="$("$EP" node test 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "全部不可达时 node test 退出码非 0" || no "全部不可达时 node test 退出码非 0" "rc=$rc"
printf '%s' "$out" | grep -q 'unreachable' && ok "node test 报 unreachable" || no "node test 报 unreachable" "$out"

# The probe clock must be millisecond-precise: busybox date prints seconds
# for %3N, which made every sub-second handshake report latency 0.
delta="$(sh -c ". '$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh'; a=\$(ep_now_ms); sleep 0.12; b=\$(ep_now_ms); echo \$((b-a))" 2>/dev/null)"
case "$delta" in
	''|*[!0-9]*) no "探测时钟是毫秒级" "got=$delta" ;;
	*) if [ "$delta" -ge 50 ] && [ "$delta" -le 400 ]; then ok "探测时钟是毫秒级"; else no "探测时钟是毫秒级" "delta=$delta"; fi ;;
esac

# --- 7. config generation refinements -------------------------------------
write_ucis 1 sing-box
"$EP" config generate >/dev/null 2>&1
json_py "import json,sys;d=json.load(open('$CFG'));rules=d['route']['rules'];print([r for r in rules if 'ip_cidr' in r])" > "$SB/c1"
grep -q '203.0.113.10/32' "$SB/c1" && ok "节点服务器地址在 route 里被固定为 direct（防环路）" || no "节点服务器地址走 direct" "$(cat "$SB/c1")"
json_py "import json,sys;d=json.load(open('$CFG'));print(d['experimental']['cache_file']['enabled'],d['experimental']['cache_file']['path'])" > "$SB/c2"
[ "$(cat "$SB/c2")" = "True /etc/easyproxy/cache.db" ] && ok "生成物带 cache_file（规则集缓存）" || no "生成物带 cache_file" "$(cat "$SB/c2")"
sed -i "s#^easyproxy.routing.rule_set_dir=.*#easyproxy.routing.rule_set_dir=$SB/rules#; \$a easyproxy.main.cache_file=$SB/cache.db" "$SB/etc/uci.db"
"$EP" config generate >/dev/null 2>&1
json_py "import json,sys;d=json.load(open('$CFG'));print(d['experimental']['cache_file']['path'])" > "$SB/c3"
[ "$(cat "$SB/c3")" = "$SB/cache.db" ] && ok "cache_file 路径可由 UCI 覆盖" || no "cache_file 路径可由 UCI 覆盖" "$(cat "$SB/c3")"

REAL="${EP_SING_BOX_BIN:-}"
if [ -n "$REAL" ] && [ -x "$REAL" ]; then
	if "$REAL" check -c "$CFG" >/dev/null 2>&1; then
		ok "真实 sing-box 接受带 cache_file 与 ip_cidr 的配置"
	else
		no "真实 sing-box 接受新配置" "$("$REAL" check -c "$CFG" 2>&1 | tail -3)"
	fi
else
	say "  SKIP  未提供 EP_SING_BOX_BIN，跳过真实内核校验"
fi

# --- 8. adapter contract ---------------------------------------------------
for fn in sing_box_available sing_box_version sing_box_config sing_box_validate sing_box_run; do
	grep -q "^${fn}()" "$SB/usr/lib/easyproxy/adapters/sing-box.sh" && ok "sing-box adapter 提供 $fn" || no "sing-box adapter 提供 $fn"
done
for fn in dae_available dae_version dae_config dae_validate dae_run; do
	grep -q "^${fn}()" "$SB/usr/lib/easyproxy/adapters/dae.sh" && ok "dae adapter 提供 $fn（切换接口已预留）" || no "dae adapter 提供 $fn"
done


# --- 9. mihomo (second engine) ---------------------------------------------
# Same UCI node model, different config dialect. These assertions pin the YAML
# shape the engine needs: without mixed-port or a rule list mihomo starts and
# proxies nothing, which looks exactly like "it works" until you curl through it.
say ""
say "9. mihomo 第二内核"

for fn in mihomo_available mihomo_version mihomo_config mihomo_validate mihomo_run; do
	grep -q "^${fn}()" "$SB/usr/lib/easyproxy/adapters/mihomo.sh" && ok "mihomo adapter 提供 $fn" || no "mihomo adapter 提供 $fn"
done

out="$("$EP" engine list 2>&1)"
printf '%s' "$out" | grep -q 'mihomo' && ok "engine list 列出 mihomo" || no "engine list 列出 mihomo" "$out"
printf '%s' "$out" | grep -Eq 'mihomo +stable' && ok "mihomo 标为 stable（真机验收通过）" || no "mihomo 未标 stable" "$out"

MIHOMO_YAML="$SB/etc/mihomo.yaml"
write_ucis 1 mihomo "$SB/bin/sing-box" 7890 1
cat >> "$SB/etc/uci.db" <<-DB
	easyproxy.mihomo.config_file=$MIHOMO_YAML
	easyproxy.mihomo.binary=$SB/bin/mihomo
	easyproxy.mihomo.home=$SB/etc/mihomo
	DB

cat > "$SB/probe-mihomo.sh" <<-PROBE
#!/bin/sh
export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:\$PATH"
export EP_LIB_DIR="$SB/usr/lib/easyproxy"
. "$SB/usr/lib/easyproxy/common.sh"
. "$SB/usr/lib/easyproxy/config.sh"
. "$SB/usr/lib/easyproxy/mihomo.sh"
PROBE
chmod +x "$SB/probe-mihomo.sh"

# binary 不存在时不校验，直接落盘
# The trailing echo must not swallow the build's exit status: "no enabled
# nodes" is asserted by exit code further down.
printf 'ep_mihomo_config_build "%s"; rc=$?; echo "MODE=$EP_ROUTE_MODE"; exit $rc\n' "$MIHOMO_YAML" >> "$SB/probe-mihomo.sh"
if sh "$SB/probe-mihomo.sh" >/dev/null 2>&1; then
	ok "无二进制时也能生成 mihomo 配置"
else
	no "生成 mihomo 配置" "$(sh "$SB/probe-mihomo.sh" 2>&1 | tail -2)"
fi

if [ -s "$MIHOMO_YAML" ]; then
	grep -q 'mixed-port: 7890' "$MIHOMO_YAML" && ok "mixed-port 取 main.listen_port" || no "mixed-port 取 main.listen_port"
	grep -q 'external-controller: "127.0.0.1:9090"' "$MIHOMO_YAML" && ok "external-controller 绑回环" || no "external-controller 绑回环"
	grep -q 'geo-auto-update: false' "$MIHOMO_YAML" && ok "关闭 geodata 自动下载（断网不卡启动）" || no "关闭 geo-auto-update"
	grep -q '  - name: "hk-01"' "$MIHOMO_YAML" && ok "节点进入 proxies" || no "节点进入 proxies"
	grep -q '    type: ss' "$MIHOMO_YAML" && ok "shadowsocks 映射为 type ss" || no "ss 映射"
	grep -q '    cipher: "aes-256-gcm"' "$MIHOMO_YAML" && ok "method 映射为 cipher" || no "cipher 映射"
	grep -q '  - name: PROXY' "$MIHOMO_YAML" && ok "生成 PROXY 选择组" || no "生成 PROXY 选择组"
	grep -q 'GEOIP,CN,DIRECT' "$MIHOMO_YAML" && ok "国内流量直连规则" || no "国内流量直连规则"
	grep -q 'MATCH,PROXY' "$MIHOMO_YAML" && ok "其余流量走代理" || no "其余流量走代理"
	# The panel used to write platform switches and custom rules into UCI and
	# nothing read them on the mihomo side: the boxes looked configured while
	# those domains were still decided by GEOIP,CN alone. Assert they land in
	# the YAML, and that they sit in front of the geo rule.
	grep -q '  - DOMAIN-SUFFIX,youtube.com,Youtube' "$MIHOMO_YAML" && ok "平台规则进 YAML（YouTube）" || no "平台规则进 YAML"
	# status must speak for the engine that is actually selected: mihomo splits
	# without the sing-box .srs files, so a box with nodes but no rule sets was
	# being reported as "direct only" while every packet went through the proxy.
	rm -f "$SB/rules/"*.srs 2>/dev/null
	out="$("$EP" status --json)"
	json_py "import json,sys;d=json.loads(sys.argv[1]);print(d.get('engine'),d.get('route_mode'),d.get('rule_set_state'))" "$out" > "$SB/mh-mode" 2>/dev/null || printf 'parse-error' > "$SB/mh-mode"
	[ "$(cat "$SB/mh-mode")" = "mihomo split ready" ] && ok "mihomo 下 status 报 split（不因缺 srs 误报 direct）" || no "mihomo 下 status 报 split" "$(cat "$SB/mh-mode")"
	write_ucis 1 sing-box "$SB/bin/sing-box" 7890 1
	out="$("$EP" status --json)"
	json_py "import json,sys;d=json.loads(sys.argv[1]);print(d.get('engine'),d.get('route_mode'),d.get('rule_set_state'))" "$out" > "$SB/sb-mode" 2>/dev/null || printf 'parse-error' > "$SB/sb-mode"
	[ "$(cat "$SB/sb-mode")" = "sing-box direct missing" ] && ok "同一台机器切回 sing-box 仍按 srs 缺失报 direct（fail closed 不变）" || no "sing-box 侧判定未被放宽" "$(cat "$SB/sb-mode")"
	write_ucis 1 mihomo "$SB/bin/sing-box" 7890 1
	printf '%s\n' 'easyproxy.mihomo.config_file='$MIHOMO_YAML 'easyproxy.mihomo.binary='$SB/bin/mihomo 'easyproxy.mihomo.home='$SB/etc/mihomo >> "$SB/etc/uci.db"

	mode_line="$(sh "$SB/probe-mihomo.sh" 2>/dev/null | sed -n 's/^MODE=//p' | tail -1)"
	case "$mode_line" in
		split) ok "摘要不会把 mihomo 误报成 direct only" ;;
		*) no "摘要不会把 mihomo 误报成 direct only" "MODE=$mode_line" ;;
	esac

	grep -q '  - DOMAIN-SUFFIX,nflxvideo.net,Netflix' "$MIHOMO_YAML" && ok "平台规则进 YAML（Netflix CDN）" || no "Netflix 规则进 YAML"
	LANLINE="$(grep -n 'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve' "$MIHOMO_YAML" | cut -d: -f1)"
	GEOLINE="$(grep -n 'GEOIP,CN,DIRECT' "$MIHOMO_YAML" | cut -d: -f1)"
	if [ -n "$LANLINE" ] && [ -n "$GEOLINE" ] && [ "$LANLINE" -lt "$GEOLINE" ]; then
		ok "内网直连排在 GEOIP 之前"
	else
		no "内网直连排在 GEOIP 之前" "lan=$LANLINE geo=$GEOLINE"
	fi

	# custom rules: same type:value:outbound store as sing-box
	printf '%s\n' 'easyproxy.routing.custom_rules=domain-suffix:example.com:direct;domain:blocked.test:block;ip-cidr:1.2.3.0/24:proxy' >> "$SB/etc/uci.db"
	printf '%s\n' 'easyproxy.routing.platform_youtube=0' >> "$SB/etc/uci.db"
	if sh "$SB/probe-mihomo.sh" >/dev/null 2>&1; then
		grep -q '  - DOMAIN-SUFFIX,example.com,DIRECT' "$MIHOMO_YAML" && ok "自定义域名规则映射为 DOMAIN-SUFFIX,DIRECT" || no "自定义域名规则未进 YAML"
		grep -q '  - DOMAIN,blocked.test,REJECT' "$MIHOMO_YAML" && ok "自定义 block 映射为 REJECT" || no "block 未映射为 REJECT"
		grep -q '  - IP-CIDR,1.2.3.0/24,PROXY,no-resolve' "$MIHOMO_YAML" && ok "自定义 IP 段带 no-resolve" || no "自定义 IP 段未进 YAML"
		grep -q 'youtube.com,PROXY' "$MIHOMO_YAML" && no "关闭 YouTube 开关后不再有 youtube 规则" || ok "关闭 YouTube 开关后不再有 youtube 规则"
		grep -q 'nflxvideo.net,Netflix' "$MIHOMO_YAML" && ok "关闭 YouTube 不影响 Netflix 规则" || no "Netflix 规则被误删"
	else
		no "带自定义规则时仍能生成" "$(sh "$SB/probe-mihomo.sh" 2>&1 | tail -2)"
	fi
	# restore the switches the later cases depend on
	sed -i '/^easyproxy.routing.custom_rules=/d; /^easyproxy.routing.platform_youtube=/d' "$SB/etc/uci.db"
	sh "$SB/probe-mihomo.sh" >/dev/null 2>&1
else
	no "生成了非空的 mihomo.yaml"
fi

# 坏节点必须报错且不能覆盖现有配置
cp "$MIHOMO_YAML" "$SB/mihomo-keep.yaml"
sed -i 's/^easyproxy.@node\[0\].password=.*/easyproxy.@node[0].password=/' "$SB/etc/uci.db"
if sh "$SB/probe-mihomo.sh" >/dev/null 2>&1; then
	no "缺 password 的节点应当失败"
else
	ok "缺 password 的节点被拒绝"
fi
cmp -s "$MIHOMO_YAML" "$SB/mihomo-keep.yaml" && ok "生成失败不覆盖原配置" || no "生成失败覆盖了原配置"

# 没有节点时也应当直接失败，而不是写出一份空 proxies
sed -i '/^easyproxy.@node\[0\].*/d' "$SB/etc/uci.db"
if sh "$SB/probe-mihomo.sh" >/dev/null 2>&1; then
	no "无节点时应当失败"
else
	ok "无节点时拒绝生成"
fi

# 适配器缺失时 ep_engine_verb 用 127 表示"未实现"，调用方才能区分
# 生成配置只能走 ep_engine_config_generate：真机上曾因为 cmd_start 和 init 脚本
# 直接调 ep_config_build，把 Clash YAML 当 sing-box JSON 生成，还留下一个
# 长驻进程占着 7890。这条断言守住"新增引擎只改一个地方"。
if grep -q "ep_config_build" "$SRC/package/easyproxy/files/usr/sbin/easyproxy"; then
	no "CLI 不再直接调用 ep_config_build" "$(grep -n 'ep_config_build' "$SRC/package/easyproxy/files/usr/sbin/easyproxy")"
else
	ok "CLI 不再直接调用 ep_config_build"
fi
if grep -q "ep_config_build" "$SRC/package/easyproxy/files/etc/init.d/easyproxy"; then
	no "init 脚本不再直接调用 ep_config_build" "$(grep -n 'ep_config_build' "$SRC/package/easyproxy/files/etc/init.d/easyproxy")"
else
	ok "init 脚本不再直接调用 ep_config_build"
fi
grep -q "^ep_engine_config_generate()" "$SB/usr/lib/easyproxy/common.sh" 	&& ok "配置生成有统一入口 ep_engine_config_generate" || no "配置生成有统一入口"

cat > "$SB/probe-verb.sh" <<-PROBE
#!/bin/sh
export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:\$PATH"
export EP_LIB_DIR="$SB/usr/lib/easyproxy"
. "$SB/usr/lib/easyproxy/common.sh"
. "$SB/usr/lib/easyproxy/config.sh"
. "$SB/usr/lib/easyproxy/mihomo.sh"
ep_engine_verb nope validate
echo "rc=\$?"
PROBE
sh "$SB/probe-verb.sh" 2>/dev/null | grep -q 'rc=127' && ok "未知引擎的 verb 返回 127" || no "未知引擎的 verb 返回 127"

# `easyproxy connections --json` used to print the text table: the generic
# argument loop eats --json into JSON=1, so the subcommand never saw the flag
# and the panel's JSON.parse() got a table. The mode now has to be passed on
# explicitly, and this asserts it stays that way.
export EP_CLASH_LIB="$SB/usr/lib/easyproxy/clash.sh"
write_ucis 1 mihomo "$SB/bin/sing-box" 7890 1
CONN_JSON="$("$EP" connections --json 2>/dev/null)"
case "$CONN_JSON" in
	'{"ok":false'*) ok "--json 走 JSON 分支（API 不可达时给出错误对象，不是表格）" ;;
	*) no "--json 走 JSON 分支" "得到：$(printf '%s' "$CONN_JSON" | head -1)" ;;
esac
case "$CONN_JSON" in
	*HOST*) no "--json 不混入表格表头" "输出里有 HOST" ;;
	*) ok "--json 不混入表格表头" ;;
esac

# and the same call on an engine without the API must fail cleanly, not hang
write_ucis 1 sing-box "$SB/bin/sing-box" 7890 1
CONN_BOX="$("$EP" connections --json 2>/dev/null)"
case "$CONN_BOX" in
	'{"ok":false'*'mihomo'*) ok "非 mihomo 引擎下 --json 明确说明原因" ;;
	*) no "非 mihomo 引擎下 --json 明确说明原因" "得到：$(printf '%s' "$CONN_BOX" | head -1)" ;;
esac

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
