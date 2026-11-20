#!/bin/sh
# Policy layer rendering suite: the 13 fixed groups inside the generated
# sing-box config.
#
#   sh tests/test-policy-render.sh
#
# Same sandbox as test-routing.sh: stub uci, stub engine, fake rule sets.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/package/easyproxy/files/usr/lib/easyproxy"
FAIL=0
PASS=0
ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin" "$SB/run" "$SB/log" "$SB/rules"

for f in common.sh config.sh transparent.sh policy.sh; do
	cp "$LIB/$f" "$SB/usr/lib/easyproxy/$f"
done
cp "$LIB/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
    -e "s#/usr/lib/easyproxy/policy.sh#$SB/usr/lib/easyproxy/policy.sh#" \
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
case "$1" in
	check)
		shift
		while [ $# -gt 0 ]; do [ "$1" = "-c" ] && cfg="$2"; shift; done
		python3 -c "import json;json.load(open('$cfg'))" || exit 1
		exit 0 ;;
	run) exec sleep 30 ;;
esac
exit 0
STUB
chmod +x "$SB/bin/sing-box" "$SB/bin/logger"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
export EP_RUNTIME_DIR="$SB/run" EP_LOG_FILE="$SB/log/easyproxy.log"
EP="$SB/usr/sbin/easyproxy"
CFG="$SB/etc/sing-box.json"
printf 'fake-geosite' > "$SB/rules/geosite-cn.srs"
printf 'fake-geoip' > "$SB/rules/geoip-cn.srs"

base_ucis() {
	cat > "$SB/etc/uci.db" <<DB
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.main.listen=127.0.0.1
easyproxy.main.listen_port=7890
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.routing.rule_set_dir=$SB/rules
easyproxy.routing.geosite_cn_url=https://example.com/geosite-cn.srs
easyproxy.routing.geoip_cn_url=https://example.com/geoip-cn.srs
easyproxy.sing_box.config_file=$CFG
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
easyproxy.@node[1].type=shadowsocks
easyproxy.@node[1].server=203.0.113.11
easyproxy.@node[1].port=8388
easyproxy.@node[1].method=aes-256-gcm
easyproxy.@node[1].password=pw-us
DB
}

policy_ucis() {
	cat >> "$SB/etc/uci.db" <<DB
easyproxy.p_netflix=policy
easyproxy.p_netflix.key=netflix
easyproxy.p_netflix.label=Netflix
easyproxy.p_netflix.mode=urltest
easyproxy.p_netflix.builtin=1
easyproxy.p_netflix.sort=1
easyproxy.p_netflix.fallback=other
easyproxy.p_netflix.nodes=@node[0] @node[1]
easyproxy.p_other=policy
easyproxy.p_other.key=other
easyproxy.p_other.label=其他
easyproxy.p_other.mode=selector
easyproxy.p_other.builtin=1
easyproxy.p_other.sort=12
easyproxy.p_other.nodes=@node[0]
easyproxy.p_speed=policy
easyproxy.p_speed.key=speed
easyproxy.p_speed.label=Speed
easyproxy.p_speed.mode=selector
easyproxy.p_speed.builtin=0
easyproxy.p_speed.sort=99
easyproxy.p_speed.nodes=@node[0] @node[1]
DB
}

jq() { python3 -c "$1" "$CFG" 2>/dev/null; }

# --- 1. no policy membership: the legacy layout must render unchanged -----
base_ucis
"$EP" config generate --json >/dev/null 2>"$SB/g.err" || no "无策略成员时仍能生成" "$(cat "$SB/g.err")"
out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(d['route']['final'])")"
[ "$out" = "proxy" ] && ok "无成员时 route.final 仍是 proxy（旧行为不变）" || no "无成员时 final=proxy" "$out"
out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(sum(1 for o in d['outbounds'] if o['tag'].startswith('policy-')))")"
[ "$out" = "0" ] && ok "无成员时不生成 policy-* 出站" || no "无成员时不生成 policy-*" "$out"

# --- 2. with membership ---------------------------------------------------
base_ucis
policy_ucis
"$EP" config generate --json >/dev/null 2>"$SB/g.err" || { no "有成员时生成成功" "$(cat "$SB/g.err")"; }

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(d['route']['final'])")"
[ "$out" = "policy-other" ] && ok "有成员时 route.final=policy-other" || no "final=policy-other" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print([o['type'] for o in d['outbounds'] if o['tag']=='policy-netflix'][0])")"
[ "$out" = "urltest" ] && ok "policy-netflix 是 urltest" || no "policy-netflix 类型" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(len([o for o in d['outbounds'] if o['tag']=='policy-netflix'][0]['outbounds']))")"
[ "$out" = "2" ] && ok "policy-netflix 含两个节点" || no "policy-netflix 成员数" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print([o['type'] for o in d['outbounds'] if o['tag']=='policy-other'][0])")"
[ "$out" = "selector" ] && ok "policy-other 是 selector" || no "policy-other 类型" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(any(o['tag']=='policy-china' for o in d['outbounds']))")"
[ "$out" = "False" ] && ok "国内组不生成出站（固定直连）" || no "国内组无出站" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));rr=[r for r in d['route']['rules'] if r.get('outbound')=='policy-netflix'];print(len(rr)>0 and any('netflix.com' in ' '.join(rr[0].get('domain_suffix',[])) for _ in [0]))")"
[ "$out" = "True" ] && ok "生成 netflix 域名分流规则且指向 policy-netflix" || no "netflix 分流规则" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(any(r.get('outbound')=='policy-other' for r in d['route']['rules']))")"
[ "$out" = "False" ] && ok "其他组不生成规则（由 route.final 兜底）" || no "其他组无规则" "$out"

out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(any(r.get('outbound')=='policy-foreign' for r in d['route']['rules']))")"
[ "$out" = "False" ] && ok "国外组无成员时不生成 invert 规则" || no "国外组 invert 规则" "$out"

# --- 3. 国外 with members gets the inverted CN rule -----------------------
cat >> "$SB/etc/uci.db" <<DB
easyproxy.p_foreign=policy
easyproxy.p_foreign.key=foreign
easyproxy.p_foreign.label=国外
easyproxy.p_foreign.mode=urltest
easyproxy.p_foreign.builtin=1
easyproxy.p_foreign.sort=10
easyproxy.p_foreign.fallback=other
easyproxy.p_foreign.nodes=@node[1]
DB
"$EP" config generate --json >/dev/null 2>"$SB/g.err" || { no "国外组生成成功" "$(cat "$SB/g.err")"; }
out="$(jq "import json,sys;d=json.load(open(sys.argv[1]));print(any(r.get('invert') and r.get('outbound')=='policy-foreign' for r in d['route']['rules']))")"
[ "$out" = "True" ] && ok "国外组生成 invert 的 CN 反向规则" || no "国外组 invert 规则" "$out"

printf '\n%s\n' "结果：$PASS 通过，$FAIL 失败"
[ $FAIL -eq 0 ]
