#!/bin/sh
# Stage 9 follow-up security suite (report 005).
#
#   sh tests/test-security.sh
#
# Three groups, all of them regressions for the 004 acceptance findings:
#   A. LuCI/rpcd privilege boundary: the panel and its ACL may only reach the
#      fixed CLI entry, never a generic shell.
#   B. Escalation attempts against that entry: hostile arguments must be
#      refused, not executed.
#   C. The two routing locks that must never regress: mainland China stays
#      direct, the intranet never enters the tunnel.
#
# The ACL/JS checks are static (the objects are files). The escalation checks
# run the real CLI inside a temp sandbox with stub uci/logger/engine, exactly
# like tests/test-cli.sh. Nothing outside $SB is written.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

APP="$SRC/package/easyproxy/files/www/luci-static/resources/easyproxy/app.js"
ACL="$SRC/package/easyproxy/files/usr/share/rpcd/acl.d/luci-app-easyproxy.json"
BIN_SRC="$SRC/package/easyproxy/files/usr/sbin/easyproxy"
LIB="$SRC/package/easyproxy/files/usr/lib/easyproxy"
VIEWS="$SRC/package/easyproxy/files/www/luci-static/resources/view/easyproxy"

# --- sandbox ----------------------------------------------------------------
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin" "$SB/run" "$SB/log" "$SB/rules"
for f in common.sh config.sh transparent.sh node.sh maint.sh traffic.sh subscribe.sh; do
	[ -r "$LIB/$f" ] && cp "$LIB/$f" "$SB/usr/lib/easyproxy/$f"
done
cp "$LIB/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
# The CLI sources its libraries by absolute path; rewrite that prefix once so
# the whole sandbox copy is self-contained.
sed -e "s#/usr/lib/easyproxy/#$SB/usr/lib/easyproxy/#g" "$BIN_SRC" > "$SB/usr/sbin/easyproxy"
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
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/sing-box"
chmod +x "$SB/bin/logger" "$SB/bin/sing-box"

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
easyproxy.@node[0]=node
easyproxy.@node[0].name=hk-01
easyproxy.@node[0].type=shadowsocks
easyproxy.@node[0].server=203.0.113.10
easyproxy.@node[0].port=443
easyproxy.@node[0].password=pw
easyproxy.@node[0].method=aes-128-gcm
DB
printf 'x' > "$SB/rules/geosite-cn.srs"
printf 'x' > "$SB/rules/geoip-cn.srs"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
export EP_RUNTIME_DIR="$SB/run"
export EP_LOG_FILE="$SB/log/easyproxy.log"
export EP_TRAFFIC_LIB="$SB/usr/lib/easyproxy/traffic.sh"
export EP_SUBSCRIBE_LIB="$SB/usr/lib/easyproxy/subscribe.sh"
EP="$SB/usr/sbin/easyproxy"

# ===========================================================================
# A. privilege boundary
# ===========================================================================
say ""
say "== A. ACL 只放行固定入口，不放行通用 shell =="

if python3 - "$ACL" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["luci-app-easyproxy"]
sys.exit(0 if isinstance(d.get("write", {}).get("file"), dict) else 1)
PY
then
	ok "ACL 的 write 段用 per-path 的 file 权限表（不是整表 exec）"
else
	no "ACL 的 write 段用 per-path 的 file 权限表（不是整表 exec）" "解析失败或结构不是 per-path：$ACL"
fi

if grep -q '"/bin/sh"' "$ACL"; then
	no "ACL 不再把 /bin/sh 的执行权限授予面板账号" "ACL 仍含 \"/bin/sh\" [ \"exec\" ]：任何拿到该 ACL 的 ubus 调用方都能以 root 执行任意命令"
else
	ok "ACL 不再把 /bin/sh 的执行权限授予面板账号"
fi

# What the write section may exec: only the fixed CLI, spelled out, no glob.
BAD_EXEC="$(python3 - "$ACL" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["luci-app-easyproxy"]
f = d.get("write", {}).get("file", {})
bad = []
for path, ops in f.items():
    if "exec" not in ops:
        continue
    if path != "/usr/sbin/easyproxy":
        bad.append(path)
    if "*" in path:
        bad.append(path + " (glob)")
print(" ".join(bad))
PY
)"
if [ -z "$BAD_EXEC" ]; then
	ok "write 段只有 /usr/sbin/easyproxy 可执行（精确路径，无通配）"
else
	no "write 段只有 /usr/sbin/easyproxy 可执行（精确路径，无通配）" "越界条目: $BAD_EXEC"
fi

if python3 - "$ACL" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["luci-app-easyproxy"]["read"]
f = d.get("file", {})
sys.exit(0 if all("exec" not in ops and "list" not in ops for ops in f.values()) else 1)
PY
then
	ok "read 段没有 exec/list，只能按白名单读文件"
else
	no "read 段没有 exec/list，只能按白名单读文件"
fi

# Comments are stripped before the search: the file documents why /bin/sh is
# not used, and that explanation is not a call.
if python3 - "$APP" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
code = re.sub(r"/*.*?*/", "", src, flags=re.S)
code = re.sub(r"(^|\s)//[^\n]*", "", code)
sys.exit(1 if "/bin/sh" in code else 0)
PY
then
	ok "app.js 的代码里不再通过 /bin/sh 调脚本"
else
	no "app.js 的代码里不再通过 /bin/sh 调脚本" "$(grep -n '/bin/sh' "$APP" | head -3)"
fi

BAD_EXECJS="$(python3 - "$APP" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# Every fs.exec(...) must name the fixed CLI as its first argument, either as
# the literal or as a variable bound to it.
allowed = {"/usr/sbin/easyproxy"}
for m in re.finditer(r"var\s+(\w+)\s*=\s*'([^']*)'", src):
    if m.group(2) == "/usr/sbin/easyproxy":
        allowed.add(m.group(1))
bad = [m.group(0) for m in re.finditer(r"fs\.exec\(\s*([^,]+),", src)
       if m.group(1).strip().strip("\"'") not in allowed]
print("; ".join(bad))
PY
)"
if [ -z "$BAD_EXECJS" ]; then
	ok "app.js 的每个 fs.exec 首参都是 /usr/sbin/easyproxy"
else
	no "app.js 的每个 fs.exec 首参都是 /usr/sbin/easyproxy" "越界调用: $BAD_EXECJS"
fi

if grep -rn "fs.exec" "$VIEWS" | grep -v "/usr/sbin/easyproxy" | grep -q .; then
	no "其他页面同样只 exec 固定 CLI" "$(grep -rn 'fs.exec' "$VIEWS" | grep -v '/usr/sbin/easyproxy' | head -3)"
else
	ok "其他页面同样只 exec 固定 CLI"
fi

if grep -qn "eval \|sh -c\|sh -c " "$BIN_SRC"; then
	no "CLI 不使用 eval / sh -c 解释参数" "$(grep -n 'eval \|sh -c' "$BIN_SRC" | head -3)"
else
	ok "CLI 不使用 eval / sh -c 解释参数"
fi

# ===========================================================================
# B. escalation attempts
# ===========================================================================
say ""
say "== B. 越权/注入尝试必须被拒绝，而不是被执行 =="

MARK="$SB/pwned"
rm -f "$MARK"

out="$("$EP" traffic "lo; touch $MARK" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "traffic 拒绝含分号的网卡名（rc=$rc）" || no "traffic 拒绝含分号的网卡名" "rc=$rc"
printf '%s' "$out" | grep -qi 'invalid interface' && ok "拒绝理由是参数不合法（不是命令不存在）" || no "拒绝理由是参数不合法（不是命令不存在）" "$out"
[ -e "$MARK" ] && no "分号参数没有被执行" "出现了 $MARK" || ok "分号参数没有被执行"

out="$("$EP" traffic '$(touch '"$MARK"')' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "traffic 拒绝命令替换参数（rc=$rc）" || no "traffic 拒绝命令替换参数" "rc=$rc"
[ -e "$MARK" ] && no "命令替换参数没有被执行" "出现了 $MARK" || ok "命令替换参数没有被执行"

out="$("$EP" subscribe 'file:///etc/passwd' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "subscribe 拒绝 file:// 订阅地址（rc=$rc）" || no "subscribe 拒绝 file:// 订阅地址" "rc=$rc"
printf '%s' "$out" | grep -qi 'http' && ok "拒绝原因明确（只接受 http/https）" || no "拒绝原因明确（只接受 http/https）" "$out"

out="$("$EP" subscribe 'gopher://127.0.0.1:6379/x' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "subscribe 拒绝 gopher:// （rc=$rc）" || no "subscribe 拒绝 gopher://" "rc=$rc"
printf '%s' "$out" | grep -qi 'http' && ok "gopher:// 的拒绝理由是协议不允许" || no "gopher:// 的拒绝理由是协议不允许" "$out"

out="$("$EP" subscribe 'https://127.0.0.1:1/sub' 'a;rm -rf /tmp/x' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "subscribe 对非法前缀 + 不可达地址失败退出（rc=$rc）" || no "subscribe 对非法前缀 + 不可达地址失败退出" "rc=$rc"

out="$(sh "$EP_SUBSCRIBE_LIB" 'file:///etc/passwd' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "subscribe.sh 自身也拒绝 file://（脚本层防线）" || no "subscribe.sh 自身也拒绝 file://" "rc=$rc"
printf '%s' "$out" | grep -qi 'http' && ok "subscribe.sh 的拒绝理由是协议不允许（不是下载失败）" || no "subscribe.sh 的拒绝理由是协议不允许" "$out"

out="$("$EP" "sh -c touch $MARK" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "未知命令被拒绝（rc=$rc）" || no "未知命令被拒绝" "rc=$rc"
[ -e "$MARK" ] && no "未知命令没有副作用" "出现了 $MARK" || ok "未知命令没有副作用"

IF="$(awk -F: 'NR > 2 { sub(/^ +/, "", $1); print $1; exit }' /proc/net/dev 2>/dev/null)"
if [ -n "$IF" ]; then
	WANT="$(awk -v i="$IF" '{ n = $0; sub(/^ +/, "", n)
		if (index(n, i":") == 1) { sub(/.*:/, "", n); split(n, a, " "); print a[9]; exit } }' /proc/net/dev)"
	out="$("$EP" traffic "$IF" --json 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && ok "traffic 经固定入口返回成功（rc=0）" || no "traffic 经固定入口返回成功" "rc=$rc, out=$out"
	GOT="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tx"))' 2>/dev/null)"
	[ "$GOT" = "$WANT" ] && ok "traffic 经固定入口的 tx 仍是第 10 列（$WANT）" || no "traffic 经固定入口的 tx 仍是第 10 列" "期望 $WANT，实际 ${GOT:-<无法解析>}"
else
	say "  SKIP  /proc/net/dev 不可读，未做 traffic 取值断言"
fi

# ===========================================================================
# C. routing locks
# ===========================================================================
say ""
say "== C. 国内直连与内网绕过（生成配置层面） =="

"$EP" config generate >/dev/null 2>&1 || no "config generate 在沙箱里成功" "generate 失败，后续断言无法进行"
CFG="$SB/etc/sing-box.json"
if [ -r "$CFG" ]; then
	CN_OUT="$(python3 - "$CFG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hits = [r.get("outbound") for r in d["route"]["rules"] if "geosite-cn" in str(r.get("rule_set")) or "geoip-cn" in str(r.get("rule_set"))]
print(hits[0] if len(hits) == 1 else ("|".join(hits) if hits else "NONE"))
PY
)"
	[ "$CN_OUT" = "direct" ] && ok "中国大陆规则集的出口是 direct" || no "中国大陆规则集的出口是 direct" "实际: $CN_OUT"

	PRIV_OUT="$(python3 - "$CFG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hits = [r.get("outbound") for r in d["route"]["rules"] if r.get("ip_is_private") is True]
print(hits[0] if len(hits) == 1 else ("|".join(hits) if hits else "NONE"))
PY
)"
	[ "$PRIV_OUT" = "direct" ] && ok "私网地址（ip_is_private）的出口是 direct" || no "私网地址的出口是 direct" "实际: $PRIV_OUT"

	LEAK="$(python3 - "$CFG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = []
for r in d["route"]["rules"]:
    if r.get("outbound") != "proxy":
        continue
    if r.get("ip_is_private") is True:
        bad.append("ip_is_private")
    rs = str(r.get("rule_set", ""))
    if "cn" in rs:
        bad.append(rs)
print(" ".join(bad))
PY
)"
	[ -z "$LEAK" ] && ok "没有任何把国内规则集或私网送进 proxy 的规则" || no "没有任何把国内规则集或私网送进 proxy 的规则" "违规: $LEAK"
fi

cp "$SB/etc/uci.db" "$SB/uci.keep"
sed -i 's/^easyproxy.routing.china_policy=.*/easyproxy.routing.china_policy=proxy/' "$SB/etc/uci.db"
out="$("$EP" validate --json 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "china_policy=proxy 仍被 validate 拒绝（rc=$rc）" || no "china_policy=proxy 仍被 validate 拒绝" "rc=$rc"
cp "$SB/uci.keep" "$SB/etc/uci.db"

# The bypass list itself: private space, the router's own addresses, and every
# node server (capturing the proxy's own upstream would loop).
BYPASS="$(EP_LIB="$SB/usr/lib/easyproxy" sh -c '. "$EP_LIB/common.sh" 2>/dev/null; . "$EP_LIB/transparent.sh" 2>/dev/null; ep_transparent_bypass_raw' 2>/dev/null)"
if [ -z "$BYPASS" ]; then
	no "能取到透明抓包的绕过列表" "ep_transparent_bypass_raw 没有输出"
else
	for cidr in 10.0.0.0/8 172.16.0.0/32 192.168.0.0/16 10.10.10.10/32; do
		case "$cidr" in
			172.16.0.0/32) want=172.16.0.0/12 ;;
			*) want="$cidr" ;;
		esac
		printf '%s' "$BYPASS" | grep -q "$want" \
			&& ok "绕过列表包含 $want" \
			|| no "绕过列表包含 $want" "实际: $BYPASS"
	done
	printf '%s' "$BYPASS" | grep -q '203.0.113.10' \
		&& ok "节点服务器地址在绕过列表里（防回环）" \
		|| no "节点服务器地址在绕过列表里（防回环）" "实际: $BYPASS"
fi

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
