#!/bin/sh
# Entry-bypass suite (M1 of 0.8.2): China traffic released in nft before tproxy.
#
#   sh tests/test-bypass.sh
#
# Runs in a temp sandbox with stub `uci`, `nft`, `ip`, `wget`/`curl`, so the
# state machine can be exercised without root, nftables or a real network.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; return 0; }

SB="$(mktemp -d)"
[ -n "${EP_KEEP:-}" ] && echo "SANDBOX=$SB" || trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc/easyproxy/rulesets" "$SB/bin" "$SB/run" "$SB/log"
for f in common.sh config.sh transparent.sh bypass.sh; do
	cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/$f" "$SB/usr/lib/easyproxy/$f"
done
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/" 2>/dev/null || :
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
    -e "s#/usr/lib/easyproxy/bypass.sh#$SB/usr/lib/easyproxy/bypass.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

ESSENTIALS="$SB/etc/easyproxy"
export EP_CN_CIDR_FILE="$ESSENTIALS/rulesets/cn-ipv4.txt"
export EP_NFT_FILE="$ESSENTIALS/nftables.conf"
export EP_TEST_UCI_DB="$ESSENTIALS/uci.db"
export EP_TEST_NFT_TABLE="$ESSENTIALS/nft.table"
export EP_TEST_NFT_STATE="$ESSENTIALS/nft.state"
export EP_TEST_NFT_BROKEN="$ESSENTIALS/nft.broken"
export EP_TEST_IP_STATE="$ESSENTIALS/ip.state"
export EP_TEST_WGET_MODE="$ESSENTIALS/wget.mode"

printf 'transparent.cn_bypass=1\ntransparent.enabled=1\n' > "$EP_TEST_UCI_DB"

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		get) shift; key="${1#easyproxy.}"; awk -v k="$key=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$DB"; exit 0 ;;
		set) shift; key="${1%%=*}"; key="${key#easyproxy.}"; val="${1#*=}"
			awk -v k="$key=" -v v="$val" 'index($0, k) == 1 { print k v; found = 1; next } { print } END { if (!found) print k v }' "$DB" > "$DB.tmp" && mv "$DB.tmp" "$DB"
			exit 0 ;;
		commit|delete) exit 0 ;;
		*) shift ;;
	esac
done
exit 0
UCI
chmod +x "$SB/bin/uci"

cat > "$SB/bin/logger" <<'L'
#!/bin/sh
exit 0
L
chmod +x "$SB/bin/logger"

# nft: `-f` records the generated script, `list` echoes it, `delete` clears it.
cat > "$SB/bin/nft" <<'NFT'
#!/bin/sh
[ -f "$EP_TEST_NFT_BROKEN" ] && { echo "nft: not supported" >&2; exit 1; }
case "$1" in
	-V) echo "nftables v1.0.9"; exit 0 ;;
	-f) cp "$2" "$EP_TEST_NFT_STATE" 2>/dev/null; [ -f "$EP_TEST_NFT_STATE" ] && touch "$EP_TEST_NFT_TABLE"; exit 0 ;;
	list) [ -f "$EP_TEST_NFT_STATE" ] || { echo "no such table" >&2; exit 1; }; cat "$EP_TEST_NFT_STATE"; exit 0 ;;
	delete) rm -f "$EP_TEST_NFT_STATE" "$EP_TEST_NFT_TABLE"; exit 0 ;;
esac
exit 0
NFT
chmod +x "$SB/bin/nft"

cat > "$SB/bin/ip" <<'IP'
#!/bin/sh
S="$EP_TEST_IP_STATE"
[ -f "$S" ] || : > "$S"
if [ "$1" = "rule" ] && [ "$2" = "show" ]; then cat "$S"; exit 0; fi
if [ "$1" = "rule" ] && [ "$2" = "add" ]; then echo "rule $3 $4 lookup $6" >> "$S"; exit 0; fi
if [ "$1" = "rule" ] && [ "$2" = "del" ]; then : ; exit 0; fi
exit 0
IP
chmod +x "$SB/bin/ip"

# wget: mode=good serves a CIDR list, mode=junk serves an HTML error page.
cat > "$SB/bin/wget" <<'W'
#!/bin/sh
out=""; while [ $# -gt 0 ]; do case "$1" in -O) out="$2"; shift 2 ;; *) shift ;; esac; done
mode="$(cat "$EP_TEST_WGET_MODE" 2>/dev/null || echo good)"
if [ "$mode" = junk ]; then printf '<html><body>404 not found</body></html>\n' > "$out"; exit 0; fi
awk 'BEGIN { for (i = 1; i <= 300; i++) printf "10.%d.%d.0/24\n", int(i / 250), i % 250 }' > "$out"
exit 0
W
chmod +x "$SB/bin/wget"
printf 'good\n' > "$EP_TEST_WGET_MODE"

run() { PATH="$SB/bin:$PATH" sh "$SB/usr/sbin/easyproxy" "$@" 2>&1; }

say "== 文件与语法 =="
[ -f "$SB/usr/lib/easyproxy/bypass.sh" ] && ok "bypass.sh 存在" || no "bypass.sh 缺失"
sh -n "$SB/usr/lib/easyproxy/bypass.sh" && ok "sh -n 通过" || no "sh -n 失败"
dash -n "$SB/usr/lib/easyproxy/bypass.sh" && ok "dash -n 通过" || no "dash -n 失败"
head -1 "$SRC/package/easyproxy/files/usr/lib/easyproxy/bypass.sh" | grep -qx '#!/bin/sh' && ok "shebang 是 /bin/sh" || no "shebang 不对"
if grep -v '^[[:space:]]*#' "$SRC/package/easyproxy/files/usr/lib/easyproxy/bypass.sh" | grep -qE '[[][[]([[:space:]]|$)'; then
	no "用了 [[ ]]"
else
	ok "无 [[ ]]"
fi
if grep -v '^[[:space:]]*#' "$SRC/package/easyproxy/files/usr/lib/easyproxy/bypass.sh" | grep -q 'pipefail'; then
	no "用了 pipefail"
else
	ok "无 pipefail"
fi

say "== CIDR 列表 =="
: > "$EP_CN_CIDR_FILE"
[ "$(PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_cidr_count')" = "0" ] && ok "空文件计数为 0" || no "空文件计数不对"

printf '10.0.0.0/8\n# comment\n192.168.1.1\n' > "$EP_CN_CIDR_FILE"
[ "$(PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_cidr_count')" = "2" ] && ok "注释与空行被忽略" || no "计数未忽略注释"

printf '10.0.0.0/8\nnot-a-cidr\n' > "$EP_CN_CIDR_FILE"
[ "$(PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_cidr_invalid')" = "1" ] && ok "非法行被识别" || no "非法行未识别"

printf '10.0.0.0/8\n' > "$EP_CN_CIDR_FILE"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_cidr_ready' && no "条目过少却判定可用" || ok "条目过少判定不可用"

say "== 下载校验 =="
printf 'junk\n' > "$EP_TEST_WGET_MODE"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_fetch' && no "垃圾响应被接受" || ok "垃圾响应被拒绝"
[ -f "$EP_CN_CIDR_FILE" ] && ok "失败时保留原列表" || no "失败时原列表被覆盖"

printf 'good\n' > "$EP_TEST_WGET_MODE"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_fetch' && ok "正常列表下载成功" || no "正常列表下载失败"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_cidr_ready' && ok "下载后列表可用" || no "下载后列表不可用"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_elements' | grep -q '10\.[0-9]*\.[0-9]*\.0/24, ' && ok "元素以逗号拼接" || no "元素拼接格式不对"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_elements' | grep -q ', $' && no "元素尾部多逗号" || ok "元素尾部无逗号"

say "== 状态机 =="
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_state' | grep -qx 'ready' && ok "未下发时状态为 ready" || no "状态不是 ready"

# Render directly: `transparent apply` correctly refuses without a running
# engine, and this suite is about the rule content, not the takeover.
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_transparent_render'
touch "$EP_TEST_NFT_TABLE"
cp "$EP_NFT_FILE" "$EP_TEST_NFT_STATE" 2>/dev/null || :
grep -q 'set cn_ipv4' "$EP_NFT_FILE" 2>/dev/null && ok "渲染包含 cn_ipv4 集合" || no "渲染缺少 cn_ipv4 集合"
grep -q 'ip daddr @cn_ipv4 return' "$EP_NFT_FILE" 2>/dev/null && ok "渲染包含入口放行规则" || no "渲染缺少放行规则"
grep -q 'cn_ipv4' "$EP_NFT_FILE" 2>/dev/null && grep -q 'elements = { 10' "$EP_NFT_FILE" && ok "集合带真实元素" || no "集合元素为空"

PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_state' | grep -qx 'active' && ok "下发后状态为 active" || no "下发后状态不是 active"

say "== 开关 =="
run bypass off >/dev/null 2>&1 && grep -qx 'transparent.cn_bypass=0' "$EP_TEST_UCI_DB" && ok "bypass off 写入 cn_bypass=0" || no "bypass off 未写入"
run bypass status 2>&1 | grep -q 'disabled' && ok "off 后状态为 disabled" || no "off 后状态不对"
grep -q 'cn_ipv4' "$EP_TEST_NFT_STATE" 2>/dev/null && no "off 后规则仍带 bypass" || ok "off 后重新渲染已去掉 bypass"

run bypass on >/dev/null 2>&1 && grep -qx 'transparent.cn_bypass=1' "$EP_TEST_UCI_DB" && ok "bypass on 写入 cn_bypass=1" || no "bypass on 未写入"
run bypass on >/dev/null 2>&1 && ok "on 可重复执行（幂等）" || no "on 不可重复执行"

say "== 恢复直连 =="
run bypass restore >/dev/null 2>&1 && ok "restore 返回 0" || no "restore 失败"
[ -f "$EP_TEST_NFT_STATE" ] && no "restore 后 nft 表仍在" || ok "restore 后 nft 表已清"
[ -f "$EP_NFT_FILE" ] && no "restore 后规则文件仍在" || ok "restore 后规则文件已删"
grep -qx 'transparent.enabled=0' "$EP_TEST_UCI_DB" && ok "restore 关闭了透明代理开关" || no "restore 未关闭透明代理"

say "== 命令行 =="
run bypass status >/dev/null 2>&1 && ok "bypass status 可用" || no "bypass status 不可用"
run bypass nonsense >/dev/null 2>&1 && no "未知动作未报错" || ok "未知动作返回非零"
run help 2>/dev/null | grep -q 'easyproxy bypass restore' && ok "帮助里列出 bypass restore" || no "帮助里没有 bypass restore"
run status --json 2>/dev/null | grep -q '"bypass_state"' && ok "status --json 含 bypass_state" || no "status --json 缺 bypass_state"

say "== 面板与入口 =="
APP="$SRC/package/easyproxy/files/www/luci-static/resources/easyproxy/app.js"
grep -q '入口旁路（国内不进内核）' "$APP" && ok "面板有入口旁路卡片" || no "面板缺少入口旁路卡片"
grep -q "run(['bypass', 'restore']" "$APP" && ok "面板一键恢复直连调用 bypass restore" || no "面板恢复按钮未接 CLI"
grep -q 'function bypassHint' "$APP" && ok "面板按状态给出说明文案" || no "面板缺少状态文案函数"
node --check "$APP" >/dev/null 2>&1 && ok "app.js 语法通过" || no "app.js 语法错误"
grep -q 'act_rescue' "$SRC/scripts/easyproxy-manager.sh" && ok "SSH 入口有紧急恢复直连" || no "SSH 入口缺少紧急恢复"
grep -q '10) dispatch rescue' "$SRC/scripts/easyproxy-manager.sh" && ok "菜单第 10 项已接线" || no "菜单未接线"

say "== nft 不可用 =="
touch "$EP_TEST_NFT_BROKEN"
PATH="$SB/bin:$PATH" sh -c '. '"$SB"'/usr/lib/easyproxy/common.sh; . '"$SB"'/usr/lib/easyproxy/transparent.sh; . '"$SB"'/usr/lib/easyproxy/bypass.sh; ep_bypass_state' | grep -qx 'unsupported' && ok "nft 不可用时状态为 unsupported" || no "nft 不可用时状态不对"
rm -f "$EP_TEST_NFT_BROKEN"

printf '\n结果：%d 通过，%d 失败\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
