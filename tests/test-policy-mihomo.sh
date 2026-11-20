#!/usr/bin/env sh
# mihomo-side rendering for the 13 fixed business groups.
#
#   sh tests/test-policy-mihomo.sh
#
# The groups are configuration, not runtime: a box whose engine is mihomo has to
# see the same group layout the sing-box writer produces, otherwise the panel
# lets a user assign nodes that no rule ever reaches. With no member assigned
# the old auto-<region> + scene layout must stay byte-for-byte behaviourally
# unchanged.

set -u
HERE=$(dirname "$0")
LIB=$(cd "$HERE/../package/easyproxy/files/usr/lib/easyproxy" && pwd)

SB=$(mktemp -d)
STORE="$SB/uci.db"
export EP_TEST_UCI_DB="$STORE"
PASS=0
FAIL=0
trap 'rm -rf "$SB"' EXIT
: > "$EP_TEST_UCI_DB"

mkdir -p "$SB/bin"
cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
while [ "$1" = "-q" ]; do shift; done
cmd="$1"; shift
case "$cmd" in
	get)
		key="$1"
		sect=${key%%.*}; rest=${key#*.}
		sec=${rest%%.*}; opt=${rest#*.}
		if [ "$opt" = "$sec" ]; then
			out=$(awk -F= -v s="$sect.$sec" '$1==s {print $2}' "$DB")
		else
			out=$(awk -F= -v s="$sect.$sec.$opt" '$1==s {print substr($0, index($0,"=")+1)}' "$DB")
		fi
		[ -z "$out" ] && exit 1
		printf '%s\n' "$out"
		;;
	set)
		kv="$1"; k=${kv%%=*}; v=${kv#*=}
		v=$(printf '%s' "$v" | sed "s/^'//; s/'$//")
		sed -i "\#^${k}=#d" "$DB"
		printf '%s=%s\n' "$k" "$v" >> "$DB"
		;;
	show)
		awk -F= -v p="$1" -v q="'" '$1 ~ "^"p"\\." {
			n = split($1, a, ".");
			val = substr($0, index($0,"=")+1);
			if (n == 2) { print $1 "=" val; next }
			if (val == "") { print $1; next }
			print $1 "=" q val q
		}' "$DB"
		;;
	commit|reload) ;;
	delete)
		k=${1#easyproxy.}
		sed -i "\#^easyproxy\.${k}\.#d; \#^easyproxy\.${k}=#d" "$DB"
		;;
	*) exit 1 ;;
esac
exit 0
UCI
chmod +x "$SB/bin/uci"
export PATH="$SB/bin:$PATH"

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

printf 'easyproxy.mihomo.config_file=%s/out.yaml\n' "$SB" >> "$EP_TEST_UCI_DB"
printf 'easyproxy.mihomo.binary=%s/nosuch\n' "$SB" >> "$EP_TEST_UCI_DB"

add_node() {
	printf 'easyproxy.%s=node\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.name=%s\n' "$1" "$2" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.type=shadowsocks\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.server=%s\n' "$1" "$3" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.port=8388\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.method=aes-256-gcm\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.password=pw\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.enabled=1\n' "$1" >> "$EP_TEST_UCI_DB"
}
add_node cfg0001 '🇯🇵_JP_日本_IPV4' jp1.example.com
add_node cfg0003 '🇺🇸_US_美国_IPV4' us1.example.com

cat > "$SB/probe.sh" <<PROBE
#!/bin/sh
for f in common.sh node.sh mihomo.sh config.sh policy.sh; do
	. "$LIB/\$f"
done
ep_policy_ensure
if [ "\${1:-}" = "bind" ]; then
	ep_policy_bind netflix cfg0001
fi
if [ "\${1:-}" = "bindall" ]; then
	ep_policy_bind netflix cfg0001
	ep_policy_bind foreign cfg0003
fi
ep_mihomo_config_build "$(uci -q get easyproxy.mihomo.config_file)"
PROBE
chmod +x "$SB/probe.sh"


printf 'mihomo 策略分组渲染\n'

# ---- 未分配节点：必须完全退回旧布局 ----
if EP_STORE="$EP_TEST_UCI_DB" sh "$SB/probe.sh" >"$SB/a.log" 2>&1 && cp "$SB/out.yaml" "$SB/a.yaml"; then
	ok "无成员时生成成功"
else
	no "无成员时生成失败" "$(tail -3 "$SB/a.log")"
fi
A="$SB/a.yaml"
grep -q 'policy-' "$A" 2>/dev/null && no "无成员却出现了 policy 组" || ok "无成员时没有 policy 组"
grep -q 'MATCH,PROXY' "$A" 2>/dev/null && ok "无成员时尾部仍是 MATCH,PROXY" || no "尾部规则被改"
grep -qE 'name: .*Youtube' "$A" 2>/dev/null && ok "无成员时保留场景组" || no "场景组丢了"

# ---- 分配节点后：13 组接管 ----
if EP_STORE="$EP_TEST_UCI_DB" sh "$SB/probe.sh" bind >"$SB/b.log" 2>&1 && cp "$SB/out.yaml" "$SB/b.yaml"; then
	ok "绑定后生成成功"
else
	no "绑定后生成失败" "$(tail -3 "$SB/b.log")"
fi
B="$SB/b.yaml"

grep -q '  - name: policy-netflix' "$B" 2>/dev/null && ok "生成 policy-netflix 组" || no "缺 policy-netflix 组"
awk '/- name: policy-netflix$/{f=1} f && /type:/{print "TYPE=" $2; exit}' "$B" > "$SB/nf" 2>/dev/null
grep -q 'TYPE=url-test' "$SB/nf" && ok "netflix 组是 url-test" || no "netflix 组类型不对"
grep -q 'DOMAIN-SUFFIX,netflix.com,policy-netflix' "$B" 2>/dev/null && ok "netflix 内置域名落到规则里" || no "没有 netflix 域名规则"
grep -q 'MATCH,policy-other' "$B" 2>/dev/null && ok "尾部兜底指向 policy-other" || no "尾部兜底没指向 policy-other"
grep -q 'name: policy-china' "$B" 2>/dev/null && no "direct 组不该建 proxy-group" || ok "国内组不建 proxy-group"
grep -qE 'name: .*Youtube' "$B" 2>/dev/null && no "policy 激活后场景组仍在" || ok "policy 激活后场景组让位"
grep -q 'GEOIP,CN,DIRECT' "$B" 2>/dev/null && ok "国内仍走 GEOIP 直连" || no "国内直连规则丢了"
grep -q 'MATCH,policy-foreigin' "$B" 2>/dev/null && no "拼写错误" || true

# foreign 有成员时才接管兜底
sh "$SB/probe.sh" bindall >"$SB/c.log" 2>&1 && cp "$SB/out.yaml" "$SB/c.yaml"
C="$SB/c.yaml"
grep -q 'MATCH,policy-foreign' "$C" 2>/dev/null && ok "国外有成员时接管尾部落点" || no "国外成员没接管尾部落点"
grep -q 'MATCH,policy-other' "$C" 2>/dev/null && no "国外接管后不该再出现 policy-other" || ok "国外接管后 other 让位"

printf '\n结果：%s 通过，%s 失败\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
