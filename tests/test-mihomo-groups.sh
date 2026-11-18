#!/usr/bin/env sh
# mihomo proxy-group layout suite.
#
#   sh tests/test-mihomo-groups.sh
#
# Nodes are useless to a user if the only way to pick one is editing UCI. The
# generator therefore has to emit the same two-level layout a mature client
# uses: one url-test group per region, plus a select group the rules point at.
# A flat list of 25 nodes in one select group is what we had, and it is why the
# panel had no usable node switch.

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
for f in common.sh node.sh mihomo.sh config.sh; do
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" "$SB/lib/$f"
done

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		get)
			shift; k="$1"
			awk -v k="$k=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$DB"
			exit 0 ;;
		set)
			shift; kv="$1"; k="${kv%%=*}"; v="${kv#*=}"
			if grep -q "^$k=" "$DB" 2>/dev/null; then
				awk -v k="$k=" -v v="$v" 'index($0, k) == 1 { print k v; next } { print }' "$DB" > "$DB.n"
				mv "$DB.n" "$DB"
			else
				printf '%s=%s\n' "$k" "$v" >> "$DB"
			fi
			exit 0 ;;
		show)
			shift; awk -v p="$1" 'index($0, p) == 1' "$DB"; exit 0 ;;
		commit|reload) exit 0 ;;
		*) shift ;;
	esac
done
exit 0
UCI
chmod +x "$SB/bin/uci"

export EP_TEST_UCI_DB="$SB/uci.db"
export PATH="$SB/bin:$PATH"
: > "$EP_TEST_UCI_DB"

printf 'easyproxy.mihomo.config_file=%s/etc/mihomo.yaml\n' "$SB" >> "$EP_TEST_UCI_DB"
printf 'easyproxy.mihomo.binary=%s/bin/mihomo\n' "$SB" >> "$EP_TEST_UCI_DB"
printf 'easyproxy.mihomo.home=%s/etc/mihomo\n' "$SB" >> "$EP_TEST_UCI_DB"
printf 'easyproxy.main.listen_port=7890\n' >> "$EP_TEST_UCI_DB"

add_node() {
	printf 'easyproxy.%s=node\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.name=%s\n' "$1" "$2" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.type=shadowsocks\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.server=%s\n' "$1" "$3" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.port=8388\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.method=aes-256-gcm\n' "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.password=pw-%s\n' "$1" "$1" >> "$EP_TEST_UCI_DB"
	printf 'easyproxy.%s.enabled=1\n' "$1" >> "$EP_TEST_UCI_DB"
}

add_node cfg0001 '🇺🇸_US_美国_IPV4' us1.example.com
add_node cfg0002 '🇺🇸_US_美国_IPV4 (2)' us2.example.com
add_node cfg0003 '🇯🇵_JP_日本_IPV4' jp1.example.com
add_node cfg0004 '机场A | 香港-01' hk1.example.com

cat > "$SB/probe.sh" <<PROBE
#!/bin/sh
PATH="$SB/bin:\$PATH"
export EP_TEST_UCI_DB="$EP_TEST_UCI_DB"
for f in common.sh node.sh mihomo.sh config.sh; do
	. "$SB/lib/\$f"
done
ep_mihomo_config_build "$SB/etc/mihomo.yaml"
PROBE
chmod +x "$SB/probe.sh"

say "mihomo 代理组布局"

if sh "$SB/probe.sh" >"$SB/out" 2>&1; then
	ok "生成配置成功"
else
	no "生成配置失败" "$(cat "$SB/out")"
fi

CFG="$SB/etc/mihomo.yaml"

grep -q '^proxy-groups:' "$CFG" && ok "有 proxy-groups 段" || no "缺 proxy-groups 段"

# --- region detection -------------------------------------------------------
say "地区识别"
for want in '自动-美国' '自动-日本' '自动-香港'; do
	grep -q "$want" "$CFG" && ok "生成地区组 $want" || no "没有地区组 $want"
done

grep -q 'type: url-test' "$CFG" && ok "地区组用 url-test" || no "地区组不是 url-test"
grep -q 'url: http://www.gstatic.com/generate_204' "$CFG" && ok "urltest 使用 gstatic 204" || no "urltest 探测 URL 不对"
grep -qE 'interval: 300' "$CFG" && ok "urltest interval 300" || no "urltest interval 不对"

# 中文名没有国家码时也要能归类
grep -q '机场A | 香港-01' "$CFG" && grep -q '自动-香港' "$CFG" && ok "中文国家名也能归组" || no "中文国家名没归组"

# --- the select group the rules use -----------------------------------------
say "PROXY 选择组"
awk '/^  - name: PROXY$/{f=1} f && /^  - name: / && !/^  - name: PROXY$/{exit} f' "$CFG" > "$SB/proxy.sec"
grep -q 'type: select' "$SB/proxy.sec" && ok "PROXY 是 select" || no "PROXY 不是 select"
for want in '自动-美国' '自动-日本' '自动-香港'; do
	grep -q "$want" "$SB/proxy.sec" && ok "PROXY 含地区组 $want" || no "PROXY 缺地区组 $want"
done
grep -q -- '- DIRECT' "$SB/proxy.sec" && ok "PROXY 含 DIRECT 手动直连" || no "PROXY 缺 DIRECT"

# 单个节点也要能直接选，不能只剩地区组
grep -q -- '🇯🇵_JP_日本_IPV4' "$SB/proxy.sec" && ok "PROXY 保留具体节点条目" || no "PROXY 丢了具体节点"

# --- all-nodes url-test -----------------------------------------------------
say "所有节点自动组"
grep -q '所有-自动' "$CFG" && ok "有 所有-自动 组" || no "没有 所有-自动 组"

# --- rules still point at PROXY ---------------------------------------------
say "规则"
grep -q 'MATCH,PROXY' "$CFG" && ok "尾部规则仍是 MATCH,PROXY" || no "尾部规则变了"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ]
