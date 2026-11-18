#!/bin/sh
# Regression suite for node import/export, region grouping and custom rules.
# No OpenWrt needed: UCI, logger and the engine binaries are all stubbed.
#
#   sh tests/test-nodes.sh
#
# Exit code 0 means every case passed.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

# EP_TEST_SB=/some/dir keeps the sandbox around for debugging
if [ -n "${EP_TEST_SB:-}" ]; then
	SB="$EP_TEST_SB"
	rm -rf "$SB"
	mkdir -p "$SB"
else
	SB="$(mktemp -d)"
	trap 'rm -rf "$SB"' EXIT
fi

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin" "$SB/run" "$SB/log" "$SB/rules"
for f in common.sh config.sh transparent.sh node.sh; do
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" "$SB/usr/lib/easyproxy/$f"
done
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
    -e "s#/usr/lib/easyproxy/node.sh#$SB/usr/lib/easyproxy/node.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

cat > "$SB/etc/uci.db" <<DB
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.main.listen_port=7890
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.routing.rule_set_dir=$SB/rules
easyproxy.sing_box.binary=$SB/bin/sing-box
easyproxy.sing_box.config_file=$SB/etc/sing-box.json
DB

# UCI stub with a real key/value store: get/show/add/set/delete/commit
cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
q=0
[ "$1" = "-q" ] && { q=1; shift; }
cmd="$1"; shift
db_set() {
	awk -v k="$1" -v v="$2" '
		BEGIN { done = 0 }
		{ if (length($0) > length(k) && substr($0, 1, length(k) + 1) == k "=") { print k "=" v; done = 1 } else print }
		END { if (!done) print k "=" v }
	' "$DB" > "$DB.new" && mv "$DB.new" "$DB"
}
case "$cmd" in
	get) key="$1"; grep -m1 -F "$key=" "$DB" | cut -d= -f2-; exit 0 ;;
	show) grep -F "$1" "$DB" | grep -v '^$'; exit 0 ;;
	add)
		pkg="$1"; type="$2"
		# real uci hands out max(index)+1; counting lines breaks after a delete
		n=$(grep -F "$pkg.@$type[" "$DB" | grep "=$type\$" | sed 's/.*\[\([0-9]*\)\].*/\1/' | sort -n | tail -1)
		[ -n "$n" ] || n=-1
		n=$((n + 1))
		sec="@$type[$n]"
		printf '%s.%s=%s\n' "$pkg" "$sec" "$type" >> "$DB"
		printf '%s' "$sec"
		exit 0
		;;
	set)
		# Real uci only accepts the single-argument "key=value" form; the
		# two-argument form prints usage and fails with a non-zero code.
		one="$1"
		case "$one" in
			*=*) key="${one%%=*}"; val="${one#*=}" ;;
			*) echo "uci: set needs key=value" >&2; exit 1 ;;
		esac
		db_set "$key" "$val"
		exit 0
		;;
	delete) awk -v k="$1" '{ if (index($0, k "=") == 1 || index($0, k ".") == 1) next; print }' "$DB" > "$DB.new" && mv "$DB.new" "$DB"; exit 0 ;;
	commit) exit 0 ;;
esac
exit 0
UCI
chmod +x "$SB/bin/uci"

printf '#!/bin/sh\nexit 0\n' > "$SB/bin/logger"
chmod +x "$SB/bin/logger"
printf '#!/bin/sh\necho "sing-box version 1.14.4"\nexit 0\n' > "$SB/bin/sing-box"
chmod +x "$SB/bin/sing-box"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
export EP_LIB_DIR="$SB/usr/lib/easyproxy"
export EP_RUNTIME_DIR="$SB/run"
export EP_LOG_FILE="$SB/log/easyproxy.log"
EP="$SB/usr/sbin/easyproxy"
CFG="$SB/etc/sing-box.json"

json_py() { python3 -c "$1" 2>/dev/null || python -c "$1" 2>/dev/null; }

# --- 1. ss:// base64 userinfo ------------------------------------------------
say "== node import: ss =="
SS_B64="$(printf 'aes-256-gcm:secretpass' | base64 | tr -d '\n')"
out="$("$EP" node add "ss://${SS_B64}@203.0.113.10:8388#%E9%A6%99%E6%B8%AF-01" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "ss base64 链接导入成功" || no "ss base64 链接导入成功" "rc=$rc $out"
[ "$(grep -c '\.type=shadowsocks$' "$SB/etc/uci.db")" = "1" ] && ok "节点类型写成 shadowsocks" || no "节点类型写成 shadowsocks" "$(grep 'type=' "$SB/etc/uci.db")"
grep -q '\.method=aes-256-gcm$' "$SB/etc/uci.db" && ok "解出加密方式" || no "解出加密方式"
grep -q '\.password=secretpass$' "$SB/etc/uci.db" && ok "解出密码" || no "解出密码"
grep -q '\.server=203.0.113.10$' "$SB/etc/uci.db" && ok "解出服务器地址" || no "解出服务器地址"
grep -q '\.port=8388$' "$SB/etc/uci.db" && ok "解出端口" || no "解出端口"
grep -qE '\.name=.*香港-01$' "$SB/etc/uci.db" && ok "百分号编码的节点名被解码" || no "百分号编码的节点名被解码" "$(grep '\.name=' "$SB/etc/uci.db")"

# --- 2. ss:// plain userinfo -------------------------------------------------
out="$("$EP" node add "ss://chacha20-ietf-poly1305:pw2@198.51.100.7:8443#us-02" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "ss 明文 userinfo 也能导入" || no "ss 明文 userinfo 也能导入" "rc=$rc $out"
grep -q '\.method=chacha20-ietf-poly1305$' "$SB/etc/uci.db" && ok "明文方式写入正确" || no "明文方式写入正确"

# --- 2b. ss:// base64url userinfo, unpadded ----------------------------------
# Real share links use the URL-safe alphabet and drop padding; plain
# `base64 -d` rejects that outright.
SS_URL="$(printf 'aes-256-gcm:p+a/s' | base64 | tr -d '=\n' | tr '+/' '-_')"
out="$("$EP" node add "ss://${SS_URL}@198.51.100.16:8388#jp-url" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "ss base64url 链接导入成功" || no "ss base64url 链接导入成功" "rc=$rc $out"
grep -q '\.password=p+a/s$' "$SB/etc/uci.db" && ok "base64url 解出密码" || no "base64url 解出密码" "$(grep 'password=' "$SB/etc/uci.db")"
grep -q '\.method=aes-256-gcm$' "$SB/etc/uci.db" && ok "base64url 解出加密方式" || no "base64url 解出加密方式"

# --- 3. vmess:// -------------------------------------------------------------
say "== node import: vmess / vless / trojan =="
VMESS_JSON='{"v":"2","ps":"jp-tokyo","add":"203.0.113.20","port":"443","id":"11111111-2222-3333-4444-555555555555","aid":"0","net":"ws","tls":"tls","sni":"jp.example.com"}'
VMESS_B64="$(printf '%s' "$VMESS_JSON" | base64 | tr -d '\n')"
out="$("$EP" node add "vmess://${VMESS_B64}" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "vmess 链接导入成功" || no "vmess 链接导入成功" "rc=$rc $out"
grep -q '\.server=203.0.113.20$' "$SB/etc/uci.db" && ok "vmess 取出服务器" || no "vmess 取出服务器"
grep -q '\.uuid=11111111-2222-3333-4444-555555555555$' "$SB/etc/uci.db" && ok "vmess 取出 uuid" || no "vmess 取出 uuid"
grep -q '\.sni=jp.example.com$' "$SB/etc/uci.db" && ok "vmess 取出 sni" || no "vmess 取出 sni"
grep -q '\.tls=1$' "$SB/etc/uci.db" && ok "vmess 识别 tls" || no "vmess 识别 tls"

out="$("$EP" node add "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@203.0.113.30:443?security=tls&sni=us.example.com#us-03" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "vless 链接导入成功" || no "vless 链接导入成功" "rc=$rc $out"
grep -q '\.type=vless$' "$SB/etc/uci.db" && ok "vless 类型写入" || no "vless 类型写入"
grep -q '\.sni=us.example.com$' "$SB/etc/uci.db" && ok "vless 取出 sni" || no "vless 取出 sni"

out="$("$EP" node add "trojan://trpass@203.0.113.40:8443?sni=hk.example.com#hk-04" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "trojan 链接导入成功" || no "trojan 链接导入成功" "rc=$rc $out"
grep -q '\.type=trojan$' "$SB/etc/uci.db" && ok "trojan 类型写入" || no "trojan 类型写入"
grep -q '\.tls=1$' "$SB/etc/uci.db" && ok "trojan 默认 tls" || no "trojan 默认 tls"

out="$("$EP" node add "hysteria2://hypass@198.51.100.9:443?sni=hy.example.com#hk-05" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "hysteria2 链接导入成功" || no "hysteria2 链接导入成功" "rc=$rc $out"
grep -q '\.type=hysteria2$' "$SB/etc/uci.db" && ok "hysteria2 类型写入" || no "hysteria2 类型写入"

out="$("$EP" node add "tuic://tuuuid:tupass@198.51.100.11:443#jp-06" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "tuic 链接导入成功" || no "tuic 链接导入成功" "rc=$rc $out"
grep -q '\.uuid=tuuuid$' "$SB/etc/uci.db" && ok "tuic 取 uuid" || no "tuic 取 uuid"
grep -q '\.password=tupass$' "$SB/etc/uci.db" && ok "tuic 取密码" || no "tuic 取密码"

# --- 4. rejection paths ------------------------------------------------------
say "== 导入失败路径 =="
out="$("$EP" node add "ftp://user@host:21" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "不支持的协议被拒绝" || no "不支持的协议被拒绝" "rc=$rc"
printf '%s\n' "$out" | grep -q 'unsupported share link scheme' && ok "拒绝时说明原因" || no "拒绝时说明原因" "$out"
out="$("$EP" node add "ss://not-base64@1.2.3.4:1" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || printf '%s\n' "$out" | grep -q 'no method:password' && ok "ss 无密码被拒绝" || no "ss 无密码被拒绝" "rc=$rc $out"
out="$("$EP" node add "vmess://$(printf 'garbage' | base64 | tr -d '\n')" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "vmess 缺字段被拒绝" || no "vmess 缺字段被拒绝" "rc=$rc"

# --- 5. node list / grouping -------------------------------------------------
say "== node list 与自动分组 =="
sed -i 's/^easyproxy.routing.fail_closed=1/easyproxy.routing.fail_closed=1/' "$SB/etc/uci.db"
out="$("$EP" node list 2>&1)"
printf '%s\n' "$out" | grep -q '香港' && ok "文本列表带中文地区" || no "文本列表带中文地区" "$out"
printf '%s\n' "$out" | grep -q 'auto-hk' && ok "文本列表显示分组 auto-hk" || no "文本列表显示分组 auto-hk" "$out"
printf '%s\n' "$out" | grep -q 'auto-jp' && ok "日本节点归入 auto-jp" || no "日本节点归入 auto-jp" "$out"
printf '%s\n' "$out" | grep -q 'auto-us' && ok "美国节点归入 auto-us" || no "美国节点归入 auto-us" "$out"

"$EP" node list --json > "$SB/list.json" 2>/dev/null
json_py "import json;d=json.load(open('$SB/list.json'));print(len(d['nodes']))" > "$SB/n1"
[ "$(cat "$SB/n1")" -ge 7 ] && ok "JSON 列出全部导入节点" || no "JSON 列出全部导入节点" "实际 $(cat "$SB/n1")"
json_py "import json;d=json.load(open('$SB/list.json'));print(sorted(g['tag'] for g in d['groups']))" > "$SB/n2"
[ "$(cat "$SB/n2")" = "['auto-hk', 'auto-jp', 'auto-us']" ] && ok "三个地区分组齐备" || no "三个地区分组齐备" "$(cat "$SB/n2")"
json_py "import json;d=json.load(open('$SB/list.json'));print([n['group'] for n in d['nodes'] if n['name']=='hk-04'][0])" > "$SB/n3"
[ "$(cat "$SB/n3")" = "auto-hk" ] && ok "单节点也能报出所属分组" || no "单节点也能报出所属分组" "$(cat "$SB/n3")"

# --- 5b. region fallback: a renamed node must still find its group ----------
reg() { sh -c ". '$SB/usr/lib/easyproxy/common.sh'; ep_node_region \"$1\" \"$2\""; }
r="$(reg "11" "3.d.s.p.r.x.0.8.d.jp01-ae5.entry.v51124-4.qpon")"
[ "$r" = "jp" ] && ok "名称为空泛时按服务器 token 判地区" || no "服务器 token 判地区" "got=$r"
r="$(reg "任意名" "host.us3.example.com")"
[ "$r" = "us" ] && ok "服务器 us3 token 判 us" || no "服务器 us3 token 判 us" "got=$r"
r="$(reg "任意名" "")"
[ "$r" = "other" ] && ok "名称与地址都无线索才判 other" || no "无线索判 other" "got=$r"
# --- 5c. the airport prefix must not hijack the region -----------------------
# "nodebuf" contains the substring "de"; a bare two-letter substring match
# tagged every stamped node as German and dropped it out of its real group.
r="$(reg "nodebuf | 日本-01" "")"
[ "$r" = "jp" ] && ok "机场名前缀不影响地区判断" || no "机场名前缀不影响地区判断" "got=$r"
r="$(reg "nodebuf | 其他-01" "")"
[ "$r" = "other" ] && ok "机场名含 de 不误判德国" || no "机场名含 de 不误判德国" "got=$r"
r="$(reg "🇺🇸_US_美国_IPV4" "")"
[ "$r" = "us" ] && ok "英文双字母整词仍能识别" || no "英文双字母整词仍能识别" "got=$r"
r="$(reg "must-plus-01" "")"
[ "$r" = "other" ] && ok "substring us 不算美国" || no "substring us 不算美国" "got=$r"

# --- 6. export round-trip ----------------------------------------------------
say "== node export =="
out="$("$EP" node export hk-05 2>&1)"
printf '%s\n' "$out" | grep -q '^hysteria2://hypass@198.51.100.9:443' && ok "hysteria2 导出成链接" || no "hysteria2 导出成链接" "$out"
out="$("$EP" node export 203.0.113.10 2>&1)"
printf '%s\n' "$out" | grep -q '^ss://' && ok "ss 按服务器地址解析并导出" || no "ss 按服务器地址解析并导出" "$out"
out="$("$EP" node export 2>&1)"
[ "$(printf '%s\n' "$out" | grep -c '://')" -ge 6 ] && ok "不带参数导出全部节点" || no "不带参数导出全部节点" "$out"

# --- 7. delete ---------------------------------------------------------------
say "== node del =="
out="$("$EP" node del us-03 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "按名字删除节点" || no "按名字删除节点" "rc=$rc $out"
[ "$(grep -c '\.type=vless$' "$SB/etc/uci.db")" = "0" ] && ok "删除后 vless 节点消失" || no "删除后 vless 节点消失"
out="$("$EP" node del nosuch 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "删不存在的节点报错" || no "删不存在的节点报错" "rc=$rc"

# --- 8. custom rules ---------------------------------------------------------
say "== 自定义规则 =="
out="$("$EP" rule list 2>&1)"
printf '%s\n' "$out" | grep -q 'No custom rules' && ok "初始没有自定义规则" || no "初始没有自定义规则" "$out"
"$EP" rule add "domain-suffix:example.org:proxy" >/dev/null 2>&1
"$EP" rule add "domain:ads.test:block" >/dev/null 2>&1
"$EP" rule add "ip-cidr:198.18.0.0/15:direct" >/dev/null 2>&1
out="$("$EP" rule list 2>&1)"
printf '%s\n' "$out" | grep -q 'domain-suffix' && ok "规则写入并列出" || no "规则写入并列出" "$out"
[ "$(grep -c 'ads.test' "$SB/etc/uci.db")" = "1" ] && ok "规则只写一次" || no "规则只写一次"
"$EP" rule list --json > "$SB/rules.json" 2>/dev/null
json_py "import json;d=json.load(open('$SB/rules.json'));print(len(d['rules']))" > "$SB/r1"
[ "$(cat "$SB/r1")" = "3" ] && ok "JSON 报出三条规则" || no "JSON 报出三条规则" "$(cat "$SB/r1")"
"$EP" rule del 2 >/dev/null 2>&1
out="$("$EP" rule list 2>&1)"
printf '%s\n' "$out" | grep -q 'ads.test' && no "删除第 2 条规则后不再出现" "$out" || ok "删除第 2 条规则后不再出现"
# 真机上按规格删除才是自然用法：rule del domain-suffix:x:proxy。只认序号会
# 让人以为删掉了，实际 rc=2（真机实测 "rule index must be a number"）。
out="$("$EP" rule del "ip-cidr:198.18.0.0/15:direct" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "按规格删除规则" || no "按规格删除规则" "rc=$rc $out"
printf '%s\n' "$("$EP" rule list 2>&1)" | grep -q '198.18.0.0/15' \
	&& no "按规格删除后规则消失" || ok "按规格删除后规则消失"
out="$("$EP" rule del "domain:no-such.test:proxy" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "删除不存在的规格报错" || no "删除不存在的规格报错" "rc=$rc $out"

# the block rule is added back so the config path that emits the block outbound runs
"$EP" rule add "domain:ads.test:block" >/dev/null 2>&1
out="$("$EP" rule add "domain:foo.com" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "格式不合法的规则被拒绝" || no "格式不合法的规则被拒绝" "rc=$rc $out"
out="$("$EP" rule add "domain:foo.com:banana" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "非法出站被拒绝" || no "非法出站被拒绝" "rc=$rc $out"

# --- 9. generated config -----------------------------------------------------
say "== 配置生成：分组 + 分流 =="
# Rule sets present so the split path (not the fail-closed lock) is exercised
printf 'fake-geosite' > "$SB/rules/geosite-cn.srs"
printf 'fake-geoip' > "$SB/rules/geoip-cn.srs"
gen_out="$("$EP" config generate 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "生成配置成功" || no "生成配置成功" "rc=$rc $gen_out"
json_py "import json;d=json.load(open('$CFG'));print([o['tag'] for o in d['outbounds'] if o['type']=='urltest'])" > "$SB/g1"
json_py "import json;d=json.load(open('$CFG'));print(sorted(o['tag'] for o in d['outbounds'] if o['type']=='urltest'))" > "$SB/g1"
[ "$(cat "$SB/g1")" = "['auto-hk', 'auto-jp', 'auto-us']" ] && ok "每个地区一个 urltest 组" || no "每个地区一个 urltest 组" "$(cat "$SB/g1")"
json_py "import json;d=json.load(open('$CFG'));print([(o['type'],o['tag']) for o in d['outbounds'] if o['tag']=='proxy'])" > "$SB/g2"
[ "$(cat "$SB/g2")" = "[('selector', 'proxy')]" ] && ok "proxy 是 selector 而不是单一 urltest" || no "proxy 是 selector" "$(cat "$SB/g2")"
json_py "import json;d=json.load(open('$CFG'));print([o['tag'] for o in d['outbounds'] if o['tag']=='proxy'][0], [o['outbounds'] for o in d['outbounds'] if o['tag']=='proxy'][0])" > "$SB/g3"
grep -q 'auto-hk' "$SB/g3" && ok "selector 指向地区分组" || no "selector 指向地区分组" "$(cat "$SB/g3")"
json_py "import json;d=json.load(open('$CFG'));r=d['route']['rules'];print(sum(1 for x in r if 'youtube.com' in str(x.get('domain_suffix',[]))))" > "$SB/g4"
[ "$(cat "$SB/g4")" = "1" ] && ok "YouTube 分流规则存在" || no "YouTube 分流规则存在" "$(cat "$SB/g4")"
json_py "import json;d=json.load(open('$CFG'));r=d['route']['rules'];print(sum(1 for x in r if 'netflix.com' in str(x.get('domain_suffix',[]))))" > "$SB/g5"
[ "$(cat "$SB/g5")" = "1" ] && ok "Netflix 分流规则存在" || no "Netflix 分流规则存在" "$(cat "$SB/g5")"
json_py "import json;d=json.load(open('$CFG'));r=d['route']['rules'];print(sum(1 for x in r if 'tiktok.com' in str(x.get('domain_suffix',[]))))" > "$SB/g6"
[ "$(cat "$SB/g6")" = "1" ] && ok "TikTok 分流规则存在" || no "TikTok 分流规则存在" "$(cat "$SB/g6")"
json_py "import json;d=json.load(open('$CFG'));r=d['route']['rules'];print([x['outbound'] for x in r if x.get('domain_suffix') and 'example.org' in x['domain_suffix']])" > "$SB/g7"
[ "$(cat "$SB/g7")" = "['proxy']" ] && ok "自定义规则进入 route.rules" || no "自定义规则进入 route.rules" "$(cat "$SB/g7")"
json_py "import json;d=json.load(open('$CFG'));print([o['tag'] for o in d['outbounds'] if o['type']=='block'])" > "$SB/g8"
[ "$(cat "$SB/g8")" = "['block']" ] && ok "有 block 规则时生成 block 出站" || no "有 block 规则时生成 block 出站" "$(cat "$SB/g8")"
json_py "import json;d=json.load(open('$CFG'));print(d['route']['final'])" > "$SB/g9"
[ "$(cat "$SB/g9")" = "proxy" ] && ok "final 仍指向 proxy" || no "final 仍指向 proxy" "$(cat "$SB/g9")"
# platform rules must be before the CN rule so YouTube is not re-directed
json_py "import json;d=json.load(open('$CFG'));r=d['route']['rules'];print(next(i for i,x in enumerate(r) if 'youtube.com' in str(x)) < next(i for i,x in enumerate(r) if x.get('rule_set')))" > "$SB/g10"
[ "$(cat "$SB/g10")" = "True" ] && ok "平台分流排在 CN 规则之前" || no "平台分流排在 CN 规则之前" "$(cat "$SB/g10")"

say "== 重名节点不破坏配置生成 =="
"$EP" node add "ss://chacha20-ietf-poly1305:pa@198.51.100.31:8443#dup-name" >/dev/null 2>&1
"$EP" node add "ss://chacha20-ietf-poly1305:pb@198.51.100.32:8443#dup-name" >/dev/null 2>&1
out="$("$EP" config generate 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "重名节点也能生成配置" || no "重名节点也能生成配置" "rc=$rc $out"
json_py "import json;d=json.load(open('$CFG'));t=[o.get('tag') for o in d['outbounds']];print('OK' if len(t)==len(set(t)) else 'DUP')" > "$SB/dup1"
[ "$(cat "$SB/dup1")" = "OK" ] && ok "所有出站 tag 唯一" || no "所有出站 tag 唯一" "$(cat "$SB/dup1")"
json_py "import json;d=json.load(open('$CFG'));print('YES' if any(o.get('tag')=='dup-name-2' for o in d['outbounds']) else 'NO')" > "$SB/dup2"
[ "$(cat "$SB/dup2")" = "YES" ] && ok "重名节点自动加后缀" || no "重名节点自动加后缀"
json_py "import json;d=json.load(open('$CFG'));u=[o for o in d['outbounds'] if o['type']=='urltest'];print('OK' if all(len(g['outbounds'])==len(set(g['outbounds'])) for g in u) else 'DUP')" > "$SB/dup3"
[ "$(cat "$SB/dup3")" = "OK" ] && ok "分组引用不重复" || no "分组引用不重复" "$(cat "$SB/dup3")"

say "== 同一端点重复导入被拒绝 =="
out="$("$EP" node add "ss://chacha20-ietf-poly1305:pa@198.51.100.31:8443#dup-name" 2>&1)"; rc=$?
[ "$rc" = "1" ] && ok "重复导入返回非 0" || no "重复导入返回非 0" "rc=$rc $out"
printf '%s' "$out" | grep -q 'already exists' && ok "重复导入提示已存在" || no "重复导入提示已存在" "$out"
[ "$(grep -c '198.51.100.31' "$SB/etc/uci.db")" = "1" ] && ok "重复导入没有多建 section" || no "重复导入没有多建 section" "$(grep -c '198.51.100.31' "$SB/etc/uci.db")"

# --- 10. platform switches ---------------------------------------------------
say "== 平台分流可关闭 =="
printf 'easyproxy.routing.platform_netflix=0\n' >> "$SB/etc/uci.db"
"$EP" config generate >/dev/null 2>&1
json_py "import json;d=json.load(open('$CFG'));print(sum(1 for x in d['route']['rules'] if 'netflix.com' in str(x)))" > "$SB/g11"
[ "$(cat "$SB/g11")" = "0" ] && ok "关闭 Netflix 开关后规则消失" || no "关闭 Netflix 开关后规则消失" "$(cat "$SB/g11")"

say ""
say "== 无 base64/openssl 时的 awk 兜底 =="
# Kwrt 25.12 ships neither base64 nor openssl; without the awk codec every
# share link failed with "userinfo is not base64".
mkdir -p "$SB/minbin"
for t in awk tr sed sh; do
	p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$SB/minbin/$t"
done
out="$(PATH="$SB/minbin" "$SB/minbin/sh" -c '. "$1"; ep_b64_decode "$2"' _ "$SB/usr/lib/easyproxy/node.sh" "$SS_URL" 2>/dev/null)"
[ "$out" = "aes-256-gcm:p+a/s" ] && ok "awk 解码 base64url" || no "awk 解码 base64url" "got=$out"
out="$(PATH="$SB/minbin" "$SB/minbin/sh" -c '. "$1"; ep_b64_decode "$2"' _ "$SB/usr/lib/easyproxy/node.sh" "$SS_B64" 2>/dev/null)"
[ "$out" = "aes-256-gcm:secretpass" ] && ok "awk 解码标准 base64" || no "awk 解码标准 base64" "got=$out"
out="$(PATH="$SB/minbin" "$SB/minbin/sh" -c '. "$1"; ep_b64_encode "$2"' _ "$SB/usr/lib/easyproxy/node.sh" "aes-256-gcm:secretpass" 2>/dev/null)"
[ "$out" = "$SS_B64" ] && ok "awk 编码与标准编码一致" || no "awk 编码与标准编码一致" "got=$out want=$SS_B64"

say ""
say "== 测速超时判不可达 =="
# A connect that never completes must never be reported as a live node. curl
# exits 28 on --max-time and 7 on refusal; only 0 is a completed handshake.
mkdir -p "$SB/probe"
cat > "$SB/probe/curl" <<'CURLSTUB'
#!/bin/sh
exit "${EP_STUB_CURL_RC:-28}"
CURLSTUB
cat > "$SB/probe/date" <<'DATESTUB'
#!/bin/sh
printf '1'
DATESTUB
chmod +x "$SB/probe/curl" "$SB/probe/date"
ln -sf "$(command -v sh)" "$SB/probe/sh" 2>/dev/null || ln -sf /bin/sh "$SB/probe/sh"
probe() { PATH="$SB/probe" EP_STUB_CURL_RC="$1" "$SB/probe/sh" -c '. "$1"; ep_tcp_probe 10.255.255.1 8388 1' _ "$SB/usr/lib/easyproxy/common.sh" 2>/dev/null; }
out="$(probe 28)"
[ "$out" = "unreachable" ] && ok "curl 超时(28)判为不可达" || no "curl 超时(28)判为不可达" "got=$out"
out="$(probe 7)"
[ "$out" = "unreachable" ] && ok "curl 拒绝(7)判为不可达" || no "curl 拒绝(7)判为不可达" "got=$out"
out="$(probe 0)"
case "$out" in
	''|unreachable|unknown) no "curl 成功(0)判为可达" "got=$out" ;;
	*) ok "curl 成功(0)判为可达" ;;
esac
# 52 / 56 是"TCP 已建立但对方不说 HTTP"（shadowsocks 端口的正常表现），
# 真机上这种端口被旧的判定规则全部误判为不可达。
out="$(probe 52)"
case "$out" in
	''|unreachable|unknown) no "curl 空响应(52)判为可达" "got=$out" ;;
	*) ok "curl 空响应(52)判为可达" ;;
esac
out="$(probe 56)"
case "$out" in
	''|unreachable|unknown) no "curl 连接重置(56)判为可达" "got=$out" ;;
	*) ok "curl 连接重置(56)判为可达" ;;
esac

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ]
