#!/usr/bin/env sh
# Clash config import suite: a subscription that answers with a Clash YAML
# document instead of a list of share links.
#
#   sh tests/test-clash-import.sh
#
# The point of these cases is the parameter fidelity, not the parsing: a vless
# node with reality-opts / xhttp-opts must reach mihomo exactly as the provider
# published it, because a field mapping would drop the transport and produce a
# node that connects to nothing. The sing-box side must refuse those nodes
# loudly rather than render a half-correct outbound.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/lib" "$SB/bin" "$SB/etc" "$SB/clash"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh" "$SB/lib/common.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/node.sh" "$SB/lib/node.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/mihomo.sh" "$SB/lib/mihomo.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/config.sh" "$SB/lib/config.sh"

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
CNT="${DB}.cnt"
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		add)
			shift; prefix="$1"
			n="$(cat "$CNT" 2>/dev/null || echo 0)"
			n=$((n + 1)); printf '%s' "$n" > "$CNT"
			sec="cfg$(printf '%04d' "$n")"
			printf "%s.%s=node\n" "$prefix" "$sec" >> "$DB"
			printf '%s\n' "$sec"; exit 0 ;;
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
		delete)
			shift; k="$1"
			awk -v k="$k=" 'index($0, k) != 1' "$DB" > "$DB.n"; mv "$DB.n" "$DB"
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
printf 'yaml-config' > "$SB/etc/mihomo.yaml"

# Keep the importer off the real /etc: the block directory is a UCI option.
printf 'easyproxy.main.clash_dir=%s\n' "$SB/clash" >> "$EP_TEST_UCI_DB"

# run in a subshell so a function can use the stubs without polluting this shell
run() {
	(
		EP_CONFIG_FILE="$SB/etc/easyproxy"
		. "$SB/lib/common.sh"
		. "$SB/lib/node.sh"
		. "$SB/lib/mihomo.sh"
		. "$SB/lib/config.sh"
		"$@"
	)
}

# A two-entry fixture: one vless with reality + xhttp, one plain shadowsocks.
# Shapes are copied from a real provider file, emoji in the names included.
cat > "$SB/sub.yaml" <<'YAML'
mixed-port: 7890
mode: rule
dns:
  enable: true
proxies:
  - type: vless
    name: RU reality xhttp
    server: 78ec29x.fi2.h1clayd.click
    port: 443
    uuid: 537d8ade-134d-4ec2-905c-0187e7e1e22e
    tls: true
    servername: 78ec29x.fi2.h1clayd.click
    client-fingerprint: chrome
    reality-opts:
      public-key: WCuIW5EhUUfvOtDeVO-M7NjwXaE20zinTv3rpQ9erxs
      short-id: 6f2d8ece33a96159
    network: xhttp
    xhttp-opts:
      path: /
      mode: auto
  - name: "US ss node"
    type: ss
    server: 172.233.129.172
    port: 8443
    cipher: aes-256-gcm
    password: "pa55word"
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - RU reality xhttp
rules:
  - GEOIP,CN,DIRECT
YAML

say "== 解析与导入 =="
OUT="$(run ep_node_import_clash "$SB/sub.yaml" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "导入返回成功" || no "导入返回成功" "$OUT"
case "$OUT" in
	*"2 imported"*) ok "两个 proxy 都入库" ;;
	*) no "两个 proxy 都入库" "$OUT" ;;
esac

# proxy-groups must not be mistaken for a node
[ "$(run ep_node_sections | wc -l | tr -d ' ')" = "2" ] && ok "proxy-groups 未被当成节点" || no "proxy-groups 未被当成节点" "$(run ep_node_sections | tr '\n' ' ')"

S1="$(run ep_node_sections | head -n 1)"
RAW1="$(run sh -c '. "$0/lib/common.sh"; . "$0/lib/node.sh"; ep_get "$1" clash_raw ""' "$SB" "$S1" 2>/dev/null)"
if [ -n "$RAW1" ]; then ok "节点记下了原始块文件名"; else no "节点记下了原始块文件名"; fi

# The block on disk must still carry the transport, otherwise the import did
# nothing but copy a display name.
if grep -q 'reality-opts' "$SB/clash/$RAW1" 2>/dev/null && grep -q 'xhttp-opts' "$SB/clash/$RAW1" 2>/dev/null; then
	ok "原始块保留了 reality-opts 与 xhttp-opts"
else
	no "原始块保留了 reality-opts 与 xhttp-opts" "$(head -3 "$SB/clash/$RAW1" 2>/dev/null)"
fi

say ""
say "== 同名不同端点 =="
# Providers reuse one display name for dozens of servers. Dropping them would
# silently halve the subscription, so the second copy must survive renamed.
cat > "$SB/dup.yaml" <<'YAML'
proxies:
  - type: vless
    name: US IPV4
    server: 10.0.0.1
    port: 443
    uuid: aaaa
  - type: vless
    name: US IPV4
    server: 10.0.0.2
    port: 443
    uuid: bbbb
YAML
OUTD="$(run ep_node_import_clash "$SB/dup.yaml" 2>&1)"
case "$OUTD" in
	*"2 imported"*) ok "同名不同端点两个都留下" ;;
	*) no "同名不同端点两个都留下" "$OUTD" ;;
esac
case "$OUTD" in
	*"US IPV4 (2)"*) ok "第二个节点自动加后缀" ;;
	*) no "第二个节点自动加后缀" "$OUTD" ;;
esac

# The file mihomo reads must agree with the tag the panel and the group use;
# a mismatch makes mihomo reject the whole config with "not found".
S2SEC="$(run sh -c '. "$0/lib/common.sh"; . "$0/lib/node.sh"; ep_node_sections | tail -n 1' "$SB")"
S2NAME="$(run sh -c '. "$0/lib/common.sh"; . "$0/lib/node.sh"; ep_get "$1" name ""' "$SB" "$S2SEC")"
S2RAW="$(run sh -c '. "$0/lib/common.sh"; . "$0/lib/node.sh"; ep_get "$1" clash_raw ""' "$SB" "$S2SEC")"
S2FILE="$(sed -n "s/^    name: //p" "$SB/clash/$S2RAW" 2>/dev/null | head -n 1)"
[ "$S2FILE" = "$S2NAME" ] && ok "块内名字与 UCI 名字一致" || no "块内名字与 UCI 名字一致" "块=$S2FILE uci=$S2NAME"

say ""
say "== 完全相同的端点 =="
OUTD2="$(run ep_node_import_clash "$SB/dup.yaml" 2>&1)"
case "$OUTD2" in
	*"0 imported"*"2 existed"*) ok "端点重复时跳过" ;;
	*) no "端点重复时跳过" "$OUTD2" ;;
esac

say ""
say "== 重复导入 =="
OUT2="$(run ep_node_import_clash "$SB/sub.yaml" 2>&1)"; RC2=$?
case "$OUT2" in
	*"0 imported"*"2 existed"*) ok "同名节点第二次被跳过" ;;
	*) no "同名节点第二次被跳过" "$OUT2" ;;
esac
[ "$RC2" -ne 0 ] && ok "没有新节点时返回非零" || no "没有新节点时返回非零"

say ""
say "== mihomo 原样输出 =="
MH="$(run ep_mihomo_node "$S1" 2>&1)"
case "$MH" in
	*"reality-opts"*"public-key: WCuIW5EhUUfvOtDeVO-M7NjwXaE20zinTv3rpQ9erxs"*) ok "mihomo 出站带上 reality 公钥" ;;
	*) no "mihomo 出站带上 reality 公钥" "$MH" ;;
esac
case "$MH" in
	*"xhttp-opts"*) ok "mihomo 出站带上 xhttp 传输" ;;
	*) no "mihomo 出站带上 xhttp 传输" "$MH" ;;
esac
case "$MH" in
	*"  - name: RU reality xhttp"*|*"- type: vless"*) ok "出站以列表项形式给出" ;;
	*) no "出站以列表项形式给出" "$MH" ;;
esac

say ""
say "== sing-box 拒绝 =="
SB1="$(run sh -c '. "$0/lib/common.sh"; . "$0/lib/node.sh"; . "$0/lib/mihomo.sh"; . "$0/lib/config.sh"; ep_node_outbound "$1"; rc=$?; printf "ERR=%s" "$EP_ERR"; exit $rc' "$SB" "$S1" 2>&1)"; SBRC=$?
[ "$SBRC" -ne 0 ] && ok "sing-box 侧拒绝 Clash 导入节点" || no "sing-box 侧拒绝 Clash 导入节点"
case "$SB1" in
	*"only the mihomo engine"*) ok "拒绝理由说明了只支持 mihomo" ;;
	*) no "拒绝理由说明了只支持 mihomo" "$SB1" ;;
esac

say ""
say "== 删除清理 =="
run ep_node_delete "$S1" > /dev/null 2>&1
[ -f "$SB/clash/$RAW1" ] && no "删除节点时清掉原始块文件" "文件还在" || ok "删除节点时清掉原始块文件"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
