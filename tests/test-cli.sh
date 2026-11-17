#!/bin/sh
# Local regression suite for the EasyProxy CLI.
# Runs on any Linux/macOS shell with no OpenWrt dependency: UCI and logger are
# stubbed, so the whole data path can be exercised before packaging.
#
#   sh tests/test-cli.sh
#
# Exit code 0 means every case passed.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

# --- sandbox -----------------------------------------------------------------
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/usr/lib/easyproxy/adapters" "$SB/usr/sbin" "$SB/etc" "$SB/bin"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh" "$SB/usr/lib/easyproxy/common.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/config.sh" "$SB/usr/lib/easyproxy/config.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/transparent.sh" "$SB/usr/lib/easyproxy/transparent.sh"
cp "$SRC/package/easyproxy/files/usr/lib/easyproxy/adapters/"*.sh "$SB/usr/lib/easyproxy/adapters/"
sed -e "s#/usr/lib/easyproxy/common.sh#$SB/usr/lib/easyproxy/common.sh#" \
    -e "s#/usr/lib/easyproxy/config.sh#$SB/usr/lib/easyproxy/config.sh#" \
    -e "s#/usr/lib/easyproxy/transparent.sh#$SB/usr/lib/easyproxy/transparent.sh#" \
	"$SRC/package/easyproxy/files/usr/sbin/easyproxy" > "$SB/usr/sbin/easyproxy"
chmod +x "$SB/usr/sbin/easyproxy"

# Fake UCI database: one "uci show"-style dump, queried by key.
cat > "$SB/etc/uci.db" <<'DB'
easyproxy.main.enabled=1
easyproxy.main.engine=sing-box
easyproxy.routing.china_policy=direct
easyproxy.routing.proxy_policy=proxy
easyproxy.routing.fail_closed=1
easyproxy.dae.config_file=/etc/easyproxy/dae.conf
easyproxy.dae.binary=/usr/bin/dae
easyproxy.sing_box.config_file=/etc/easyproxy/sing-box.json
easyproxy.sing_box.binary=/usr/bin/sing-box
easyproxy.@node[0]=node
easyproxy.@node[0].name=hk-01
easyproxy.@node[1]=node
easyproxy.@node[1].name=us-01
DB

# Point the UCI engine paths at the sandbox binaries so the test controls
# whether "the binary is installed" itself.
sed -i "s#/usr/bin/sing-box#$SB/bin/sing-box#; s#/usr/bin/dae#$SB/bin/dae#" "$SB/etc/uci.db"

cat > "$SB/bin/uci" <<'UCI'
#!/bin/sh
DB="${EP_TEST_UCI_DB:?}"
# supports: uci [-q] get <key>   |   uci [-q] show <package>
while [ $# -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		get) shift; key="$1"; grep -m1 "^$key=" "$DB" | cut -d= -f2-; exit 0 ;;
		show) shift; grep "^$1" "$DB"; exit 0 ;;
		*) shift ;;
	esac
done
exit 0
UCI
chmod +x "$SB/bin/uci"
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/logger"
chmod +x "$SB/bin/logger"

export EP_TEST_UCI_DB="$SB/etc/uci.db"
export PATH="$SB/bin:$PATH"
EP="$SB/usr/sbin/easyproxy"

# Fake engine binaries so binary_ok can be toggled.
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/sing-box"
chmod +x "$SB/bin/sing-box"

json_get() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

# --- 1. status --json is one valid JSON line --------------------------------
out="$("$EP" status --json)"
lines="$(printf '%s' "$out" | wc -l)"
[ "$lines" -eq 0 ] && ok "status --json 输出为单行" || no "status --json 输出为单行" "实际 ${lines} 行"
if printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
	ok "status --json 是合法 JSON"
else
	no "status --json 是合法 JSON" "$out"
fi
[ "$(printf '%s' "$out" | json_get "['ok']")" = "True" ] && ok "status ok=true" || no "status ok=true"
PKG_VER="$(sed -n 's/^PKG_VERSION:=//p' "$SRC/package/easyproxy/Makefile" | head -1)"
[ -n "$PKG_VER" ] || no "version=<PKG_VERSION unreadable>"
[ "$(printf '%s' "$out" | json_get "['version']")" = "$PKG_VER" ] && ok "version=$PKG_VER" || no "version=$PKG_VER"
[ "$(printf '%s' "$out" | json_get "['engine']")" = "sing-box" ] && ok "engine 来自 UCI" || no "engine 来自 UCI"
[ "$(printf '%s' "$out" | json_get "['nodes']")" = "2" ] && ok "nodes 统计出 2 个节点" || no "nodes 统计出 2 个节点"
[ "$(printf '%s' "$out" | json_get "['binary_ok']")" = "1" ] && ok "binary_ok=1（二进制可执行）" || no "binary_ok=1"
[ "$(printf '%s' "$out" | json_get "['route_mode']")" = "direct" ] && ok "route_mode=direct（无规则集，fail_closed 默认 1）" || no "route_mode=direct" "$(printf '%s' "$out" | json_get "['route_mode']")"

# --- 2. missing binary is reported, not invented ----------------------------
mv "$SB/bin/sing-box" "$SB/bin/sing-box.off"
out="$("$EP" status --json)"
[ "$(printf '%s' "$out" | json_get "['binary_ok']")" = "0" ] && ok "二进制缺失时 binary_ok=0" || no "二进制缺失时 binary_ok=0"
mv "$SB/bin/sing-box.off" "$SB/bin/sing-box"

# --- 3. validate happy path ------------------------------------------------
"$EP" validate --json > "$SB/v1.json"; rc=$?
[ "$rc" -eq 0 ] && ok "validate 合法配置退出码 0" || no "validate 合法配置退出码 0" "rc=$rc"
[ "$(json_get "['ok']" < "$SB/v1.json")" = "True" ] && ok "validate ok=true" || no "validate ok=true"

# --- 4. validate rejects a bad engine --------------------------------------
sed -i 's/^easyproxy.main.engine=.*/easyproxy.main.engine=clash/' "$SB/etc/uci.db"
"$EP" validate --json > "$SB/v2.json"; rc=$?
[ "$rc" -eq 1 ] && ok "validate 非法引擎退出码 1" || no "validate 非法引擎退出码 1" "rc=$rc"
[ "$(json_get "['ok']" < "$SB/v2.json")" = "False" ] && ok "validate ok=false" || no "validate ok=false"
printf '%s' "$(json_get "['messages']" < "$SB/v2.json")" | grep -q 'Invalid main.engine' \
	&& ok "validate 报出具体错误字段" || no "validate 报出具体错误字段"
sed -i 's/^easyproxy.main.engine=.*/easyproxy.main.engine=sing-box/' "$SB/etc/uci.db"

# --- 5. validate rejects the locked-out escape hatches ---------------------
cp "$SB/etc/uci.db" "$SB/uci.bak"
sed -i 's/^easyproxy.routing.china_policy=.*/easyproxy.routing.china_policy=proxy/' "$SB/etc/uci.db"
"$EP" validate --json > "$SB/v3.json"; rc=$?
[ "$rc" -eq 1 ] && ok "china_policy=proxy 被 validate 拒绝（锁死国内直连）" || no "china_policy=proxy 被拒绝" "rc=$rc"
grep -q 'china_policy' "$SB/v3.json" && ok "报出 china_policy 错误字段" || no "报出 china_policy 错误字段"
sed -i 's/^easyproxy.routing.china_policy=.*/easyproxy.routing.china_policy=direct/' "$SB/etc/uci.db"
sed -i 's/^easyproxy.routing.fail_closed=.*/easyproxy.routing.fail_closed=0/' "$SB/etc/uci.db"
"$EP" validate --json > "$SB/v4.json"; rc=$?
[ "$rc" -eq 1 ] && ok "fail_closed=0 被 validate 拒绝（锁死 fail closed）" || no "fail_closed=0 被拒绝" "rc=$rc"
grep -q 'fail_closed' "$SB/v4.json" && ok "报出 fail_closed 错误字段" || no "报出 fail_closed 错误字段"
cp "$SB/uci.bak" "$SB/etc/uci.db"

# --- 6. start refuses while disabled --------------------------------------
sed -i 's/^easyproxy.main.enabled=.*/easyproxy.main.enabled=0/' "$SB/etc/uci.db"
out="$("$EP" start 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "未启用时 start 被拒绝" || no "未启用时 start 被拒绝" "rc=$rc"
printf '%s' "$out" | grep -qi 'disabled' && ok "拒绝原因明确（disabled）" || no "拒绝原因明确（disabled）"
sed -i 's/^easyproxy.main.enabled=.*/easyproxy.main.enabled=1/' "$SB/etc/uci.db"

# --- diagnostics bundle -----------------------------------------------------
# A secret in a log must never reach GitHub. These cases feed the collector a
# log full of credentials and then grep the bundle for the originals.
mkdir -p "$SB/diag"
cat > "$SB/bin/logread" <<'STUB'
#!/bin/sh
cat "$SB_DIAG_LOG"
STUB
chmod +x "$SB/bin/logread"
cat > "$SB/diag/secret.log" <<'LOG'
2026-11-17 easyproxy: node ss://YWVzLTI1Ni1nY206c2VjcmV0MTIz@10.0.0.1:8388#JP
2026-11-17 easyproxy: subscribe https://sub.example.test/api/v1/client/subscribe?token=abcdef123456
2026-11-17 easyproxy: node vmess://eyJhZGQiOiIxMC4wLjAuMSIsInBvcnQiOiI4ODg4IiwiaWQiOiIxMjM0NTY3OC0xMjM0LTEyMzQtMTIzNC0xMjM0NTY3ODkwYWIifQ==
2026-11-17 easyproxy: config {"password":"hunter2","uuid":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}
LOG

out="$(SB_DIAG_LOG="$SB/diag/secret.log" EP_DIAG_OUT="$SB/diag/out.txt" "$EP" diag 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diag 退出码 0" || no "diag 退出码 0" "rc=$rc $out"
[ -f "$SB/diag/out.txt" ] && ok "diag 产出了采集包" || no "diag 产出了采集包" "$out"
printf '%s' "$out" | grep -q 'upload skipped' && ok "默认不上传，并提示加 --upload" || no "默认不上传" "$out"
grep -q -- '--- status ---' "$SB/diag/out.txt" && grep -q -- '--- logs ---' "$SB/diag/out.txt" \
	&& ok "采集包含 status 与 logs 段" || no "采集包分段" "$(head -20 "$SB/diag/out.txt")"

grep -q 'ss://YWVzLTI1Ni1nY206c2VjcmV0MTIz' "$SB/diag/out.txt" && no "分享链接未脱敏" "" || ok "分享链接已脱敏"
grep -q 'token=abcdef123456' "$SB/diag/out.txt" && no "订阅 token 未脱敏" "" || ok "订阅 token 已脱敏"
grep -q 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' "$SB/diag/out.txt" && no "uuid 未脱敏" "" || ok "uuid 已脱敏"
grep -q 'hunter2' "$SB/diag/out.txt" && no "密码未脱敏" "" || ok "JSON 密码已脱敏"

# --- diag --upload without a token -----------------------------------------
out="$(EP_DIAG_TOKEN_FILE="$SB/diag/no-token" EP_DIAG_OUT="$SB/diag/out2.txt" "$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "无 token 时 --upload 返回 3" || no "无 token 时 --upload 返回 3" "rc=$rc $out"
[ -f "$SB/diag/out2.txt" ] && ok "上传失败仍保留本地采集包" || no "上传失败仍保留本地采集包" ""
printf '%s' "$out" | grep -q 'no token at' && ok "提示 token 应放在哪里" || no "提示 token 位置" "$out"

# --- diag --upload with a token (wget PUT stub) ----------------------------
cat > "$SB/bin/wget" <<'STUB'
#!/bin/sh
for a in "$@"; do
	case "$a" in
		--spider) exit 0 ;;
		--method=PUT) printf 'put %s\n' "$*" >> "$EP_TEST_LOG_GH"; exit 0 ;;
	esac
done
exit 1
STUB
chmod +x "$SB/bin/wget"
cat > "$SB/bin/curl" <<'STUB'
#!/bin/sh
for a in "$@"; do
	case "$a" in
		PUT) printf 'put %s\n' "$*" >> "$EP_TEST_LOG_GH" ;;
		%{http_code}) true ;;
	esac
done
# -w '%{http_code}' is the last argument in the upload call
printf '201'
exit 0
STUB
chmod +x "$SB/bin/curl"
printf 'dummy-token\n' > "$SB/diag/token"
chmod 600 "$SB/diag/token"
: > "$SB/diag/gh.log"
out="$(EP_TEST_LOG_GH="$SB/diag/gh.log" EP_DIAG_TOKEN_FILE="$SB/diag/token" \
	EP_DIAG_REPO="bnm188/EasyProxy" EP_DIAG_BRANCH="diag" EP_DIAG_OUT="$SB/diag/out3.txt" \
	"$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "有 token 时上传成功返回 0" || no "有 token 时上传成功返回 0" "rc=$rc $out"
printf '%s' "$out" | grep -q 'raw: https://raw.githubusercontent.com/bnm188/EasyProxy/diag/' \
	&& ok "打印可直接读取的 raw 链接" || no "打印 raw 链接" "$out"
grep -qE 'method=PUT|-X PUT' "$SB/diag/gh.log" 2>/dev/null && ok "确实发出了 PUT 请求" || no "确实发出了 PUT 请求" "$(cat "$SB/diag/gh.log")"

# --- 7. engine subcommand --------------------------------------------------
out="$("$EP" engine 2>&1)"
printf '%s' "$out" | grep -q 'sing-box' && ok "engine 打印所选内核" || no "engine 打印所选内核"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
