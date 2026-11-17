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

out="$("$EP" diag --daily on 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "diag --daily on 返回 0" || no "diag --daily on 返回 0" "rc=$rc $out"
grep -q 'easyproxy diag --auto' "$EP_CRONTAB" 2>/dev/null && ok "crontab 写入每日任务" || no "crontab 写入每日任务" "$(cat "$EP_CRONTAB" 2>/dev/null)"
grep -q '17 3 \* \* \*' "$EP_CRONTAB" 2>/dev/null && ok "每日任务固定在 03:17" || no "每日任务时间" "$(cat "$EP_CRONTAB" 2>/dev/null)"
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
printf '{"tag_name": "v0.8.4"}\n' > "$UP/repo/rel.json"

# payload that looks like an installed EasyProxy
mkdir -p "$UP/pack/usr/sbin" "$UP/pack/etc/init.d" "$UP/pack/www/luci-static/resources/easyproxy"
printf '#!/bin/sh\nEP_VERSION="0.8.4"\n' > "$UP/pack/usr/sbin/easyproxy"
printf '#!/bin/sh\n' > "$UP/pack/etc/init.d/easyproxy"
printf "'require baseclass'\nreturn baseclass.extend({});\n" > "$UP/pack/www/luci-static/resources/easyproxy/app.js"
( cd "$UP/pack" && tar -czf "$UP/repo/easyproxy-0.8.4-rootfs.tar.gz" . )
( cd "$UP/repo" && sha256sum easyproxy-0.8.4-rootfs.tar.gz > SHA256SUMS )
printf 'deadbeefdeadbeef  easyproxy-0.8.4-rootfs.tar.gz\n' > "$UP/repo/SHA256SUMS.bad"

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
	*api.github.com*) cp "$base/rel.json" "$out" || exit 1 ;;
	*SHA256SUMS.bad*) cp "$base/SHA256SUMS.bad" "$out" || exit 1 ;;
	*SHA256SUMS*) cp "$base/SHA256SUMS" "$out" || exit 1 ;;
	*easyproxy-*-rootfs.tar.gz*) cp "$base/easyproxy-0.8.4-rootfs.tar.gz" "$out" || exit 1 ;;
	*) exit 1 ;;
esac
STUB
chmod +x "$SB/bin/wget"

# a pre-existing install: the backup must be able to archive it
printf "'require baseclass'\nreturn baseclass.extend({ original: true });\n" \
	> "$UP/root/www/luci-static/resources/easyproxy/app.js"
printf '#!/bin/sh\nEP_VERSION="0.8.3"\n' > "$UP/root/usr/sbin/easyproxy"
printf '#!/bin/sh\n' > "$UP/root/etc/init.d/easyproxy"

runup() { # runup <relbase> <args...>
	local rel="$1"; shift
	PATH="$SB/bin:$PATH" EP_TEST_REL="$rel" EP_UPDATE_REPO="bnm188/EasyProxy" \
	EP_UPDATE_ROOT="$UP/root" EP_UPDATE_BACKUP_DIR="$UP/backups" \
	EP_UPDATE_APP_JS="$UP/root/www/luci-static/resources/easyproxy/app.js" \
	EP_UPDATE_MENU_JSON="$UP/root/menu.json" EP_UPDATE_MIRRORS="" \
	"$EP" update "$@" 2>&1
}

out="$(runup "$UP/repo" check)"; rc=$?
[ "$rc" -eq 0 ] && ok "update check 退出码 0" || no "update check 退出码 0" "rc=$rc $out"
printf '%s' "$out" | grep -q 'latest:  0.8.4' && ok "update check 认出最新版本" || no "update check 认出最新版本" "$out"
printf '%s' "$out" | grep -q 'update is available' && ok "提示可升级" || no "提示可升级" "$out"

out="$(runup "$UP/repo" check --json)"
printf '%s' "$out" | grep -q '"available":true' && ok "update check --json 供面板解析" || no "--json 输出" "$out"

out="$(runup "$UP/nowhere" check)"; rc=$?
[ "$rc" -eq 4 ] && ok "拿不到 Release 时返回 4" || no "拿不到 Release 时返回 4" "rc=$rc $out"

# checksum mismatch must abort before replacing anything
out="$(runup "$UP/repo" apply 0.8.4 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "校验通过时升级成功" || no "校验通过时升级成功" "rc=$rc $out"
printf '%s' "$out" | grep -q 'checksum verified' && ok "动手前先校验 sha256" || no "动手前先校验" "$out"
[ -f "$UP/backups/rollback-0.8.3.tar.gz" ] && ok "升级前备份当前版本" || no "升级前备份当前版本" "$(ls -l "$UP/backups" 2>/dev/null)"
[ -f "$UP/root/www/luci-static/resources/easyproxy/app.js" ] && ok "解包后面板文件就位" || no "解包后面板文件就位" "$out"
printf '%s' "$out" | grep -q 'now running 0.8.4' && ok "报告新版本已生效" || no "报告新版本已生效" "$out"

# a bad SHA256SUMS entry must stop the install
cp "$UP/repo/SHA256SUMS" "$UP/repo/SHA256SUMS.ok"; cp "$UP/repo/SHA256SUMS.bad" "$UP/repo/SHA256SUMS"
out="$(runup "$UP/repo" apply 0.8.4 2>&1)"; rc=$?
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
