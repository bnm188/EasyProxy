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
# The update fixtures below use a version deliberately far above PKG_VERSION
# (0.9.9): an upgrade test needs a release newer than the build under test, so
# hardcoding the "next" version would break every time the version is bumped.
# 面板的"版本"按钮直接调 easyproxy version：必须 rc=0 且只打印版本号，
# 不能落到 usage（真机上曾经就这样返回 code=2）。
vout="$(env PATH="$SB/bin:$PATH" EP_TEST_UCI_DB="$SB/etc/uci.db" "$EP" version 2>&1)"; vrc=$?
[ "$vrc" = "0" ] && ok "version 命令 rc=0" || no "version 命令 rc=0（实际 $vrc）"
[ "$vout" = "$PKG_VER" ] && ok "version 命令输出 $PKG_VER" || no "version 命令输出（实际 $vout）"
vjson="$(env PATH="$SB/bin:$PATH" EP_TEST_UCI_DB="$SB/etc/uci.db" "$EP" version --json 2>&1)"
[ "$(printf '%s' "$vjson" | json_get "['version']")" = "$PKG_VER" ] && ok "version --json" || no "version --json（实际 $vjson）"
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

# --- log file: written, locked down, rotated --------------------------------
# ep_log used to go to syslog only, so the file the panel reads stayed empty.
# Sourced directly: the point is the helper, not which CLI verb logs.
mkdir -p "$SB/diag"
export EP_LOG_FILE="$SB/diag/easyproxy.log"
rm -f "$EP_LOG_FILE" "$EP_LOG_FILE.1"
( PATH="$SB/bin:$PATH"; . "$SB/usr/lib/easyproxy/common.sh"; ep_log "unit-test line" )
[ -f "$EP_LOG_FILE" ] && ok "ep_log 写出了日志文件" || no "ep_log 写出了日志文件" "$(ls -l "$SB/diag")"
[ "$(stat -c %a "$EP_LOG_FILE" 2>/dev/null)" = "600" ] \
	&& ok "日志文件权限为 600" || no "日志文件权限为 600" "$(stat -c %a "$EP_LOG_FILE" 2>/dev/null)"
grep -q 'easyproxy: unit-test line' "$EP_LOG_FILE" 2>/dev/null && ok "日志行带标记写入" || no "日志行格式" "$(cat "$EP_LOG_FILE")"
grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$EP_LOG_FILE" 2>/dev/null \
	&& ok "日志行有时间戳" || no "日志行有时间戳" "$(cat "$EP_LOG_FILE")"

# rotation: exceed the 1 MiB default, then log once more
head -c 1200000 /dev/zero | tr '\0' 'x' > "$EP_LOG_FILE"
chmod 600 "$EP_LOG_FILE"
( PATH="$SB/bin:$PATH"; . "$SB/usr/lib/easyproxy/common.sh"; ep_log "after-rotation line" )
[ -f "$EP_LOG_FILE.1" ] && ok "超过上限后轮转为 .1" || no "超过上限后轮转为 .1" "$(ls -l "$SB/diag")"
[ "$(stat -c %a "$EP_LOG_FILE" 2>/dev/null)" = "600" ] && ok "轮转后新文件仍是 600" || no "轮转后新文件仍是 600" ""
grep -q 'after-rotation line' "$EP_LOG_FILE" && ok "轮转后新行写进新文件" || no "轮转后新行写进新文件" ""

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

# --- customer numbering, private repo default, daily job -------------------
# Each machine files its bundles under its own number: diagnostics/001/...
export EP_DIAG_ID_FILE="$SB/diag/customer.id"
export EP_CRONTAB="$SB/diag/crontab"
rm -f "$EP_DIAG_ID_FILE" "$EP_CRONTAB"
out="$("$EP" diag --set-id 007 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diag --set-id 接受纯数字编号" || no "diag --set-id 接受纯数字编号" "rc=$rc $out"
[ "$(cat "$EP_DIAG_ID_FILE" 2>/dev/null)" = "007" ] && ok "客户编号写入文件" || no "客户编号写入文件" "$(cat "$EP_DIAG_ID_FILE" 2>/dev/null)"
[ "$(stat -c %a "$EP_DIAG_ID_FILE" 2>/dev/null)" = "600" ] && ok "客户编号文件权限 600" || no "客户编号文件权限 600" ""
out="$("$EP" diag --set-id abc 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "非数字编号被拒绝" || no "非数字编号被拒绝" "rc=$rc $out"

: > "$SB/diag/gh2.log"
out="$(EP_TEST_LOG_GH="$SB/diag/gh2.log" EP_DIAG_TOKEN_FILE="$SB/diag/token" EP_DIAG_OUT="$SB/diag/out4.txt" \
	"$EP" diag --upload 2>&1)"
grep -q 'diagnostics/007/' "$SB/diag/gh2.log" && ok "上传路径按客户编号分目录" || no "上传路径按客户编号分目录" "$(cat "$SB/diag/gh2.log")"

# default target is the private archive repository, not the public one
printf '%s' "$out" | grep -q 'raw: https://raw.githubusercontent.com/bnm188/EasyProxy-Diag/' \
	&& ok "默认上传到私有仓库 EasyProxy-Diag" || no "默认私有仓库" "$out"

# without a number the bundle still goes out, but under unassigned/
rm -f "$EP_DIAG_ID_FILE"
: > "$SB/diag/gh3.log"
EP_TEST_LOG_GH="$SB/diag/gh3.log" EP_DIAG_TOKEN_FILE="$SB/diag/token" EP_DIAG_OUT="$SB/diag/out5.txt" \
	"$EP" diag --upload >/dev/null 2>&1
grep -q 'diagnostics/unassigned/' "$SB/diag/gh3.log" && ok "未设编号时落到 unassigned/" || no "未设编号时落到 unassigned/" "$(cat "$SB/diag/gh3.log")"

# --- diag --upload over WebDAV (own cloud, no GitHub token) -----------------
# A customer's own Nextcloud / Nutstore exposes WebDAV: one PUT, no token, no
# repository. This path must not require the GitHub token file at all.
cat > "$SB/bin/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$EP_TEST_LOG_WD"
if [ "${EP_TEST_WD_CODE:-201}" = "401" ]; then printf '401'; else printf '201'; fi
exit 0
STUB
chmod +x "$SB/bin/curl"
printf 'app-pass-123\n' > "$SB/diag/pass"; chmod 600 "$SB/diag/pass"
printf '007\n' > "$EP_DIAG_ID_FILE"

: > "$SB/diag/wd.log"
out="$(EP_TEST_LOG_WD="$SB/diag/wd.log" EP_DIAG_WEBDAV="https://dav.example.test/dav/EasyProxy/" \
	EP_DIAG_USER="me@example.test" EP_DIAG_PASS_FILE="$SB/diag/pass" \
	EP_DIAG_OUT="$SB/diag/out6.txt" "$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "WebDAV 上传成功返回 0" || no "WebDAV 上传成功返回 0" "rc=$rc $out"
grep -q 'dav.example.test/dav/EasyProxy/007/' "$SB/diag/wd.log" 2>/dev/null \
	&& ok "WebDAV 路径按客户编号分目录" || no "WebDAV 路径按客户编号分目录" "$(cat "$SB/diag/wd.log" 2>/dev/null)"
grep -q -- '-T ' "$SB/diag/wd.log" 2>/dev/null \
	&& ok "WebDAV 用 curl -T 上传文件本体" || no "WebDAV 用 curl -T 上传" "$(cat "$SB/diag/wd.log" 2>/dev/null)"
# WebDAV does not create folders on PUT: a missing <id>/ folder makes the upload
# fail with 409, so the folder is created first (405 means it already existed).
grep -q 'MKCOL' "$SB/diag/wd.log" 2>/dev/null \
	&& ok "上传前先建客户编号目录（MKCOL）" || no "上传前先建客户编号目录（MKCOL）" "$(cat "$SB/diag/wd.log" 2>/dev/null)"
grep -q 'MKCOL.*EasyProxy/007/' "$SB/diag/wd.log" 2>/dev/null \
	&& ok "MKCOL 针对客户编号目录" || no "MKCOL 针对客户编号目录" "$(cat "$SB/diag/wd.log" 2>/dev/null)"
grep -q 'app-pass-123' "$SB/diag/wd.log" 2>/dev/null \
	&& no "密码不得出现在命令行参数里" "" || ok "密码没有泄露到命令行参数"
[ -f "$SB/diag/out6.txt" ] && ok "WebDAV 成功后本地包仍保留" || no "WebDAV 成功后本地包保留" ""

# no password file: refuse locally, never send a credential-less request
rm -f "$SB/diag/pass"; : > "$SB/diag/wd.log"
out="$(EP_TEST_LOG_WD="$SB/diag/wd.log" EP_DIAG_WEBDAV="https://dav.example.test/dav/EasyProxy/" \
	EP_DIAG_USER="me@example.test" EP_DIAG_PASS_FILE="$SB/diag/pass" \
	EP_DIAG_OUT="$SB/diag/out7.txt" "$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "WebDAV 无密码文件时返回 3" || no "WebDAV 无密码文件时返回 3" "rc=$rc $out"
printf '%s' "$out" | grep -q 'diag: no password at' && ok "提示密码文件该放哪里" || no "提示密码文件位置" "$out"
[ -s "$SB/diag/wd.log" ] && no "无密码时不得发出请求" "$(cat "$SB/diag/wd.log")" || ok "无密码时没有发出请求"

# credentials rejected: say so, keep the bundle
printf 'wrong-pass\n' > "$SB/diag/pass"; chmod 600 "$SB/diag/pass"; : > "$SB/diag/wd.log"
out="$(EP_TEST_WD_CODE=401 EP_TEST_LOG_WD="$SB/diag/wd.log" EP_DIAG_WEBDAV="https://dav.example.test/dav/EasyProxy/" \
	EP_DIAG_USER="me@example.test" EP_DIAG_PASS_FILE="$SB/diag/pass" \
	EP_DIAG_OUT="$SB/diag/out8.txt" "$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && ok "WebDAV 凭据被拒返回 5" || no "WebDAV 凭据被拒返回 5" "rc=$rc $out"
printf '%s' "$out" | grep -qi 'credential' && ok "说明是凭据被拒" || no "说明是凭据被拒" "$out"
[ -f "$SB/diag/out8.txt" ] && ok "凭据被拒后本地包仍保留" || no "凭据被拒后本地包保留" ""
rm -f "$SB/diag/pass"

# --- diag --upload from one 600 file (URL + account + password) --------------
# The account itself must not have to live in uci: `uci show easyproxy` is one
# command away for anyone with a root shell. One file, mode 600, carries all
# three values instead.
printf '%s\n%s\n%s\n' 'https://dav.conf.test/dav/EP/' 'me@conf.test' 'conf-pass-777' > "$SB/diag/conf"
chmod 600 "$SB/diag/conf"
: > "$SB/diag/wd.log"
out="$(EP_TEST_LOG_WD="$SB/diag/wd.log" EP_DIAG_CONF="$SB/diag/conf" \
	EP_DIAG_OUT="$SB/diag/out9.txt" "$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diag.conf：仅凭 600 文件即可上传（返回 0）" || no "diag.conf：仅凭 600 文件上传" "rc=$rc $out"
grep -q 'dav.conf.test/dav/EP/007/' "$SB/diag/wd.log" 2>/dev/null \
	&& ok "diag.conf：地址取自第一行" || no "diag.conf：地址取自第一行" "$(cat "$SB/diag/wd.log" 2>/dev/null)"
grep -q 'MKCOL' "$SB/diag/wd.log" 2>/dev/null \
	&& ok "diag.conf：照样先建客户编号目录" || no "diag.conf：照样先建客户编号目录" "$(cat "$SB/diag/wd.log" 2>/dev/null)"
grep -q 'conf-pass-777' "$SB/diag/wd.log" 2>/dev/null \
	&& no "diag.conf：密码不进命令行" "" || ok "diag.conf：密码没有出现在命令行参数里"
# the account must reach curl through netrc, never through argv
grep -q 'me@conf.test' "$SB/diag/wd.log" 2>/dev/null \
	&& no "diag.conf：账号不进命令行" "" || ok "diag.conf：账号没有出现在命令行参数里"

# a truncated file must not silently fall back to some other credential source
printf '%s\n%s\n' 'https://dav.conf.test/dav/EP/' 'me@conf.test' > "$SB/diag/conf"
chmod 600 "$SB/diag/conf"; : > "$SB/diag/wd.log"
out="$(EP_TEST_LOG_WD="$SB/diag/wd.log" EP_DIAG_CONF="$SB/diag/conf" \
	EP_DIAG_PASS_FILE="$SB/diag/no-such-pass" EP_DIAG_OUT="$SB/diag/out10.txt" "$EP" diag --upload 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "diag.conf：缺密码行时返回 3" || no "diag.conf：缺密码行时返回 3" "rc=$rc $out"
[ -s "$SB/diag/wd.log" ] && no "diag.conf：缺密码时不发请求" "$(cat "$SB/diag/wd.log")" || ok "diag.conf：缺密码时没有发出请求"
rm -f "$SB/diag/conf"

out="$("$EP" diag --daily on 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diag --daily on 返回 0" || no "diag --daily on 返回 0" "rc=$rc $out"
grep -q 'easyproxy diag --auto' "$EP_CRONTAB" 2>/dev/null && ok "crontab 写入定期上报任务" || no "crontab 写入定期上报任务" "$(cat "$EP_CRONTAB" 2>/dev/null)"
# 15 days, not every day: 1st/16th/31st at 03:17 keeps the quota untouched
grep -q '17 3 \*/15 \* \*' "$EP_CRONTAB" 2>/dev/null && ok "上报周期为每 15 天（03:17）" || no "上报周期为每 15 天" "$(cat "$EP_CRONTAB" 2>/dev/null)"
out="$("$EP" diag --daily on 2>&1)"
[ "$(grep -c 'easyproxy diag --auto' "$EP_CRONTAB" 2>/dev/null)" = "1" ] && ok "重复开启不会写两条" || no "重复开启只有一条" "$(cat "$EP_CRONTAB")"
out="$("$EP" diag --daily off 2>&1)"
grep -q 'easyproxy diag --auto' "$EP_CRONTAB" 2>/dev/null && no "关闭后任务仍在" "" || ok "--daily off 移除任务"

# --- update: check, verify, install, rollback ------------------------------
# A self-update that trusts the download is how a router ends up bricked, so
# these cases pin the checksum gate and the rollback path.
UP="$SB/update"
mkdir -p "$UP/repo" "$UP/root/usr/sbin" "$UP/root/etc/init.d" \
	"$UP/root/www/luci-static/resources/easyproxy" "$UP/backups"
printf '{"tag_name": "v0.9.9"}\n' > "$UP/repo/rel.json"

# payload that looks like an installed EasyProxy
mkdir -p "$UP/pack/usr/sbin" "$UP/pack/etc/init.d" "$UP/pack/www/luci-static/resources/easyproxy" \
	"$UP/pack/usr/lib/easyproxy"
printf '#!/sh\n' > "$UP/pack/usr/sbin/easyproxy"
# The update verifies the version baked into the tree it just installed, and
# that version lives in common.sh (reading the CLI itself made the sed match
# its own source line). A payload without common.sh is an invalid tree.
printf 'EP_VERSION="0.9.9"\n' > "$UP/pack/usr/lib/easyproxy/common.sh"
# The payload is a full rootfs tree and therefore ships the default config.
# A user config must survive the upgrade untouched.
mkdir -p "$UP/pack/etc/config"
printf 'config main\n\toption enabled 1\n\toption shipped_default_marker 1\n' > "$UP/pack/etc/config/easyproxy"
printf '#!/bin/sh\n' > "$UP/pack/etc/init.d/easyproxy"
printf "'require baseclass'\nreturn baseclass.extend({});\n" > "$UP/pack/www/luci-static/resources/easyproxy/app.js"
( cd "$UP/pack" && tar -czf "$UP/repo/easyproxy-0.9.9-rootfs.tar.gz" . )
( cd "$UP/repo" && sha256sum easyproxy-0.9.9-rootfs.tar.gz > SHA256SUMS )
printf 'deadbeefdeadbeef  easyproxy-0.9.9-rootfs.tar.gz\n' > "$UP/repo/SHA256SUMS.bad"

# one wget stub for both diag PUT and the update downloads
cat > "$SB/bin/wget" <<'STUB'
#!/bin/sh
for a in "$@"; do
	case "$a" in
		--method=PUT|method=PUT) echo "PUT" >> "${EP_TEST_LOG_GH:?}"; exit 0 ;;
	esac
done
out=""; url=""
while [ $# -gt 0 ]; do
	case "$1" in
		-O|--output-document) shift; out="$1" ;;
		--header|--body-file|--method|-T|--timeout) shift ;;
		-q|--quiet|--spider) ;;
		http*) url="$1" ;;
	esac
	shift
done
[ -n "$out" ] || exit 1
base="${EP_TEST_REL:-}"
[ -n "$base" ] || exit 1
case "$url" in
	*releases.atom*) [ -f "$base/atom.xml" ] && cp "$base/atom.xml" "$out" || exit 1 ;;
	*api.github.com*) [ -n "${EP_TEST_API_BROKEN:-}" ] && exit 1; cp "$base/rel.json" "$out" || exit 1 ;;
	*SHA256SUMS.bad*) cp "$base/SHA256SUMS.bad" "$out" || exit 1 ;;
	*SHA256SUMS*) cp "$base/SHA256SUMS" "$out" || exit 1 ;;
	*easyproxy-*-rootfs.tar.gz*) cp "$base/easyproxy-0.9.9-rootfs.tar.gz" "$out" || exit 1 ;;
	*) exit 1 ;;
esac
STUB
chmod +x "$SB/bin/wget"

# a pre-existing install: the backup must be able to archive it
printf "'require baseclass'\nreturn baseclass.extend({ original: true });\n" \
	> "$UP/root/www/luci-static/resources/easyproxy/app.js"
mkdir -p "$UP/root/etc/config"
printf 'config main\n\toption enabled 1\n\toption user_marker keepme\n' > "$UP/root/etc/config/easyproxy"
printf '#!/bin/sh\nEP_VERSION="0.8.8"\n' > "$UP/root/usr/sbin/easyproxy"
printf '#!/bin/sh\n' > "$UP/root/etc/init.d/easyproxy"

runup() { # runup <relbase> <args...>
	local rel="$1"; shift
	PATH="$SB/bin:$PATH" EP_TEST_REL="$rel" EP_UPDATE_REPO="bnm188/EasyProxy" \
	EP_TEST_API_BROKEN="${EP_TEST_API_BROKEN:-}" \
	EP_UPDATE_ROOT="$UP/root" EP_UPDATE_BACKUP_DIR="$UP/backups" \
	EP_UPDATE_APP_JS="$UP/root/www/luci-static/resources/easyproxy/app.js" \
	EP_UPDATE_MENU_JSON="$UP/root/menu.json" EP_UPDATE_MIRRORS="" \
	"$EP" update "$@" 2>&1
}

out="$(runup "$UP/repo" check)"; rc=$?
[ "$rc" -eq 0 ] && ok "update check 退出码 0" || no "update check 退出码 0" "rc=$rc $out"
printf '%s' "$out" | grep -q 'latest:  0.9.9' && ok "update check 认出最新版本" || no "update check 认出最新版本" "$out"
printf '%s' "$out" | grep -q 'update is available' && ok "提示可升级" || no "提示可升级" "$out"

out="$(runup "$UP/repo" check --json)"
printf '%s' "$out" | grep -q '"available":true' && ok "update check --json 供面板解析" || no "--json 输出" "$out"

out="$(runup "$UP/nowhere" check)"; rc=$?
[ "$rc" -eq 4 ] && ok "拿不到 Release 时返回 4" || no "拿不到 Release 时返回 4" "rc=$rc $out"

# The release feed on github.com is the path that survives a rate-limited IP:
# api.github.com allows 60 unauthenticated requests per hour per address, and a
# router behind carrier NAT shares that budget with every neighbour. Version
# detection must therefore work with the API answering 403.
printf '<?xml version="1.0" encoding="UTF-8"?>\n<feed xmlns="http://www.w3.org/2005/Atom">\n  <title>Release notes from EasyProxy</title>\n  <entry>\n    <id>tag:github.com,2008:Repository/1458940874/v0.9.9</id>\n    <link rel="alternate" type="text/html" href="https://github.com/bnm188/EasyProxy/releases/tag/v0.9.9"/>\n    <title>EasyProxy 0.9.9</title>\n  </entry>\n</feed>\n' > "$UP/repo/atom.xml"

out="$(EP_TEST_API_BROKEN=1 runup "$UP/repo" check)"; rc=$?
[ "$rc" -eq 0 ] && ok "API 被限流时仍能检查更新（走 atom）" || no "API 被限流时仍能检查更新（走 atom）" "rc=$rc $out"
printf '%s' "$out" | grep -q 'latest:  0.9.9' \
	&& ok "atom 解析出最新版本" || no "atom 解析出最新版本" "$out"
out="$(EP_TEST_API_BROKEN=1 runup "$UP/repo" check --json)"
printf '%s' "$out" | grep -q '"latest":"0.9.9"' \
	&& ok "atom 路径的 --json 输出可供面板解析" || no "atom 路径的 --json 输出" "$out"

# checksum mismatch must abort before replacing anything
out="$(runup "$UP/repo" apply 0.9.9 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "校验通过时升级成功" || no "校验通过时升级成功" "rc=$rc $out"
printf '%s' "$out" | grep -q 'checksum verified' && ok "动手前先校验 sha256" || no "动手前先校验" "$out"
ls "$UP/backups"/rollback-*.tar.gz >/dev/null 2>&1 && ok "升级前备份当前版本" || no "升级前备份当前版本" "$(ls -l "$UP/backups" 2>/dev/null)"
[ -f "$UP/root/www/luci-static/resources/easyproxy/app.js" ] && ok "解包后面板文件就位" || no "解包后面板文件就位" "$out"
printf '%s' "$out" | grep -q 'now running 0.9.9' && ok "报告新版本已生效" || no "报告新版本已生效" "$out"
grep -q 'user_marker keepme' "$UP/root/etc/config/easyproxy" 2>/dev/null && ok "升级不覆盖用户配置（节点/开关保住）" || no "升级不覆盖用户配置（节点/开关保住）" "$(cat "$UP/root/etc/config/easyproxy" 2>/dev/null)"

# a bad SHA256SUMS entry must stop the install
cp "$UP/repo/SHA256SUMS" "$UP/repo/SHA256SUMS.ok"; cp "$UP/repo/SHA256SUMS.bad" "$UP/repo/SHA256SUMS"
out="$(runup "$UP/repo" apply 0.9.9 2>&1)"; rc=$?
printf '%s' "$out" | grep -q 'checksum mismatch' && ok "校验不符时拒绝安装" || no "校验不符时拒绝安装" "rc=$rc $out"
[ "$rc" -ne 0 ] && ok "校验不符返回非 0" || no "校验不符返回非 0" "rc=$rc"
cp "$UP/repo/SHA256SUMS.ok" "$UP/repo/SHA256SUMS"

# rollback restores the archived tree
printf "'require baseclass'\nreturn baseclass.extend({ broken: true });\n" > "$UP/root/www/luci-static/resources/easyproxy/app.js"
out="$(runup "$UP/repo" rollback)"; rc=$?
[ "$rc" -eq 0 ] && ok "update rollback 返回 0" || no "update rollback 返回 0" "rc=$rc $out"
printf '%s' "$out" | grep -q 'restoring rollback-' && ok "回滚用备份包恢复" || no "回滚用备份包恢复" "$out"
grep -q 'broken' "$UP/root/www/luci-static/resources/easyproxy/app.js" 2>/dev/null && no "回滚后面板文件仍是坏的" "" || ok "回滚后面板文件已复原"

# --- 7. engine subcommand --------------------------------------------------# --- 7. engine subcommand --------------------------------------------------
out="$("$EP" engine 2>&1)"
printf '%s' "$out" | grep -q 'sing-box' && ok "engine 打印所选内核" || no "engine 打印所选内核"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
