#!/bin/sh
# EasyProxy 独立面板 CGI 接口
# 由 lighttpd(8090) 调用，直接驱动 /usr/sbin/easyproxy CLI。
#
# 约定：所有响应均为 JSON；除 state / setup / login 外，一律要求有效会话 cookie。

EP="$(command -v easyproxy 2>/dev/null || echo /usr/sbin/easyproxy)"
PW_FILE=/etc/easyproxy/panel.pw
SESS_FILE=/tmp/easyproxy-sessions
LOG=/var/log/easyproxy-panel-cgi.log
COOKIE_NAME=ep_sess

# ---------- 基础输出 ----------
hdr() { printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n'; }
ok()  { hdr; printf '%s\n' "$1"; exit 0; }
# Set-Cookie 必须出现在 header 区（第一个空行之前），否则浏览器会把它当正文
ok_cookie() {
	printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n'
	[ -n "$SET_COOKIE" ] && printf '%s\r\n' "$SET_COOKIE"
	printf '\r\n%s\n' "$1"
	exit 0
}
bad() { hdr; printf '{"ok":false,"error":"%s"}\n' "$(jesc "$1")"; exit 0; }

jesc() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r//g' -e 's/\n/ /g'
}

# 从 JSON 里取字符串字段（够用即可，不做完整解析）
jget() {
	printf '%s' "$1" | sed -n "s/.*\"$2\"[ ]*:[ ]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# ---------- 输入 ----------
QS="${QUERY_STRING:-}"
CMD=""
case "$QS" in
	cmd=*) CMD="${QS#cmd=}" ;;
esac
CMD="${CMD%%&*}"

BODY=""
if [ "${REQUEST_METHOD:-GET}" = "POST" ]; then
	len="${CONTENT_LENGTH:-0}"
	case "$len" in ''|*[!0-9]*) len=0 ;; esac
	[ "$len" -gt 0 ] 2>/dev/null && BODY="$(dd bs=1 count="$len" 2>/dev/null)"
	[ -n "$CMD" ] || CMD="$(jget "$BODY" cmd)"
fi

# ---------- 会话 ----------
hash_pw() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

have_pw() { [ -s "$PW_FILE" ]; }

cookie_token() {
	printf '%s' "${HTTP_COOKIE:-}" | tr ';' '\n' | sed -n "s/^[ ]*${COOKIE_NAME}=//p" | head -1 | tr -d '\r'
}

session_valid() {
	tok="$(cookie_token)"
	[ -n "$tok" ] || return 1
	[ -f "$SESS_FILE" ] || return 1
	line="$(grep -m1 "^$tok " "$SESS_FILE" 2>/dev/null)"
	[ -n "$line" ] || return 1
	exp="${line##* }"
	case "$exp" in ''|*[!0-9]*) return 1 ;; esac
	now="$(date +%s)"
	[ "$exp" -gt "$now" ] || return 1
	return 0
}

new_session() {
	now="$(date +%s)"
	tok="$(printf '%s-%s-%s-%s' "$$" "$now" "${REMOTE_ADDR:-x}" "$(cat /proc/uptime 2>/dev/null | cut -d' ' -f1)" | sha256sum | cut -c1-40)"
	exp=$((now + 86400 * 7))
	mkdir -p /tmp
	touch "$SESS_FILE"
	# 清掉过期行，避免文件无限增长
	awk -v n="$now" '$2 > n' "$SESS_FILE" > "$SESS_FILE.tmp" 2>/dev/null && mv "$SESS_FILE.tmp" "$SESS_FILE"
	chmod 600 "$SESS_FILE" 2>/dev/null
	printf '%s %s\n' "$tok" "$exp" >> "$SESS_FILE"
	SET_COOKIE="Set-Cookie: $COOKIE_NAME=$tok; Path=/; Max-Age=$((86400 * 7)); SameSite=Lax; HttpOnly"
}

# ---------- 系统指标 ----------
cpu_json() {
	line="$(top -bn1 2>/dev/null | grep -i 'CPU:' | head -1)"
	if [ -z "$line" ]; then
		printf '{"user":0,"sys":0,"idle":0,"usage":0}'
		return
	fi
	usr="$(printf '%s' "$line" | sed -n 's/.*\([0-9]\+\)% usr.*/\1/p')"
	usr="${usr:-0}"
	sys="$(printf '%s' "$line" | sed -n 's/.*\([0-9]\+\)% sys.*/\1/p')"
	sys="${sys:-0}"
	idle="$(printf '%s' "$line" | sed -n 's/.*\([0-9]\+\)% idle.*/\1/p')"
	idle="${idle:-0}"
	usage=$((usr + sys))
	[ "$usage" -gt 100 ] && usage=100
	printf '{"user":%s,"sys":%s,"idle":%s,"usage":%s}' "$usr" "$sys" "$idle" "$usage"
}

mem_json() {
	total="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
	avail="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
	total="${total:-0}"; avail="${avail:-0}"
	used=$(( (total - avail) / 1024 ))
	pct=0
	[ "$total" -gt 0 ] && pct=$(( (total - avail) * 100 / total ))
	printf '{"total_mb":%s,"used_mb":%s,"pct":%s}' "$((total / 1024))" "$used" "$pct"
}

# ---------- mihomo Clash API ----------
clash_base() {
	c="$(uci get easyproxy.mihomo.controller 2>/dev/null)"
	[ -n "$c" ] || c="127.0.0.1:9090"
	case "$c" in http*) printf '%s' "$c" ;; *) printf 'http://%s' "$c" ;; esac
}

url_enc() {
	printf '%s' "$1" | sed -e 's|:|%3A|g' -e 's|/|%2F|g' -e 's|?|%3F|g' -e 's|&|%26|g'
}

# ---------- 命令分发 ----------

case "$CMD" in

state)
	need=0; have_pw || need=1
	li=0; session_valid && li=1
	ver="$("$EP" version 2>/dev/null | head -1)"
	ver="$(printf '%s' "${ver:-unknown}" | tr -d '\r')"
	ok "{\"ok\":true,\"need_setup\":$need,\"logged_in\":$li,\"version\":\"$(jesc "$ver")\",\"host\":\"$(jesc "$(cat /proc/sys/kernel/hostname 2>/dev/null)")\"}"
	;;

setup)
	have_pw && bad "已经设置过密码"
	pw="$(jget "$BODY" password)"
	[ -n "$pw" ] || bad "密码不能为空"
	len="$(printf '%s' "$pw" | wc -c)"
	[ "$len" -ge 6 ] || bad "密码至少 6 位"
	mkdir -p "$(dirname "$PW_FILE")"
	hash_pw "$pw" > "$PW_FILE"
	chmod 600 "$PW_FILE"
	new_session
	ok_cookie '{"ok":true}'
	;;

login)
	have_pw || bad "尚未设置密码"
	pw="$(jget "$BODY" password)"
	[ -n "$pw" ] || bad "密码不能为空"
	want="$(cat "$PW_FILE" 2>/dev/null)"
	got="$(hash_pw "$pw")"
	[ "$want" = "$got" ] || bad "密码错误"
	new_session
	ok_cookie '{"ok":true}'
	;;

logout)
	tok="$(cookie_token)"
	[ -n "$tok" ] && [ -f "$SESS_FILE" ] && grep -v "^$tok " "$SESS_FILE" > "$SESS_FILE.t" 2>/dev/null && mv "$SESS_FILE.t" "$SESS_FILE"
	SET_COOKIE="Set-Cookie: $COOKIE_NAME=; Path=/; Max-Age=0; HttpOnly"
	ok_cookie '{"ok":true}'
	;;
esac

# 以下全部需要登录
session_valid || bad "未登录或会话已失效"

case "$CMD" in

status)
	st="$("$EP" status --json 2>/dev/null)"
	[ -n "$st" ] || bad "status 调用失败"
	ok "{\"ok\":true,\"status\":$st,\"cpu\":$(cpu_json),\"mem\":$(mem_json),\"uptime\":$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)}"
	;;

clash-proxies)
	raw="$(curl -s -m 8 "$(clash_base)/proxies" 2>/dev/null)"
	[ -n "$raw" ] || bad "Clash API 不可用（引擎可能未运行）"
	case "$raw" in {*) ok "{\"ok\":true,\"data\":$raw}" ;; *) bad "Clash API 返回异常" ;; esac
	;;

delay-all)
	ge="$(jget "$BODY" group_enc)"
	[ -n "$ge" ] || bad "缺少 group_enc"
	u="$(jget "$BODY" url)"
	[ -n "$u" ] || u="http://www.gstatic.com/generate_204"
	t="$(jget "$BODY" timeout)"
	case "$t" in ''|*[!0-9]*) t=5000 ;; esac
	ue="$(url_enc "$u")"
	raw="$(curl -s -m 50 "$(clash_base)/group/$ge/delay?url=$ue&timeout=$t" 2>/dev/null)"
	case "$raw" in {*) ok "{\"ok\":true,\"data\":$raw}" ;; *) bad "测速超时或失败" ;; esac
	;;

node-delay)
	ne="$(jget "$BODY" name_enc)"
	[ -n "$ne" ] || bad "缺少 name_enc"
	u="$(jget "$BODY" url)"
	[ -n "$u" ] || u="http://www.gstatic.com/generate_204"
	t="$(jget "$BODY" timeout)"
	case "$t" in ''|*[!0-9]*) t=5000 ;; esac
	ue="$(url_enc "$u")"
	raw="$(curl -s -m 15 "$(clash_base)/proxies/$ne/delay?url=$ue&timeout=$t" 2>/dev/null)"
	case "$raw" in {*) ok "{\"ok\":true,\"data\":$raw}" ;; *) ok '{"ok":true,"data":{"delay":0,"error":"timeout"}}' ;; esac
	;;

select)
	ge="$(jget "$BODY" group_enc)"
	n="$(jget "$BODY" name)"
	[ -n "$ge" ] || bad "缺少 group_enc"
	[ -n "$n" ] || bad "缺少 name"
	nj="$(jesc "$n")"
	code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -d "{\"name\":\"$nj\"}" "$(clash_base)/proxies/$ge" 2>/dev/null)"
	case "$code" in 204|200) ok '{"ok":true}' ;; *) bad "切换失败（HTTP ${code:-000}）" ;; esac
	;;

nodes)
	n="$("$EP" node list --json 2>/dev/null)"
	[ -n "$n" ] || bad "node list 调用失败"
	ok "{\"ok\":true,\"data\":$n}"
	;;

group)
	g="$("$EP" group list --json 2>/dev/null)"
	[ -n "$g" ] || bad "group list 调用失败"
	ok "{\"ok\":true,\"data\":$g}"
	;;

group-use)
	member="$(jget "$BODY" member)"
	grp="$(jget "$BODY" group)"
	[ -n "$member" ] || bad "缺少 member"
	if [ -n "$grp" ]; then
		out="$("$EP" group set "$grp" "$member" 2>&1)"
	else
		out="$("$EP" group use "$member" 2>&1)"
	fi
	rc=$?
	if [ "$rc" -ne 0 ]; then bad "$(printf '%s' "${out:-切换失败}" | tr '\n' ' ')"; fi
	ok "{\"ok\":true,\"message\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

engine)
	action="$(jget "$BODY" action)"
	case "$action" in
		start|stop|restart)
			out="$("$EP" "$action" 2>&1)"; rc=$?
			[ "$rc" -eq 0 ] || bad "引擎 $action 失败：$(printf '%s' "$out" | tr '\n' ' ')"
			ok "{\"ok\":true}"
			;;
		*) bad "未知动作 $action" ;;
	esac
	;;

conn)
	c="$("$EP" connections --json 2>/dev/null)"
	[ -n "$c" ] || c='{"connections":[]}'
	ok "{\"ok\":true,\"data\":$c}"
	;;

node-test)
	name="$(jget "$BODY" name)"
	[ -n "$name" ] || bad "缺少 name"
	out="$("$EP" node test "$name" 2>&1)"
	ok "{\"ok\":true,\"message\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

clash-conns)
	raw="$(curl -s -m 8 "$(clash_base)/connections" 2>/dev/null)"
	[ -n "$raw" ] || bad "Clash API 不可用（引擎可能未运行）"
	case "$raw" in {*) ok "{\"ok\":true,\"data\":$raw}" ;; *) bad "Clash API 返回异常" ;; esac
	;;

conn-close)
	id="$(jget "$BODY" id)"
	[ -n "$id" ] || bad "缺少 id"
	code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X DELETE "$(clash_base)/connections/$id" 2>/dev/null)"
	case "$code" in 204|200) ok '{"ok":true}' ;; *) bad "关闭失败（HTTP ${code:-000}）" ;; esac
	;;

logs)
	n="$(jget "$BODY" lines)"
	case "$n" in ''|*[!0-9]*) n=120 ;; esac
	[ "$n" -le 400 ] || n=400
	out="$(tail -n "$n" /var/log/easyproxy.log 2>/dev/null | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | sed -e 's/^/"/' -e 's/$/",/' | tr -d '\n')"
	out="${out%,}"
	ok "{\"ok\":true,\"lines\":[$out]}"
	;;

sites)
	out='['
	first=1
	for h in www.baidu.com www.qq.com www.taobao.com www.google.com; do
		res="$(curl -s -k -o /dev/null -m 8 -w '%{http_code}|%{time_total}' -x http://127.0.0.1:7890 "https://$h" 2>/dev/null)"
		code="${res%%|*}"
		t="${res##*|}"
		[ -n "$code" ] || code=000
		ms="$(printf '%s' "$t" | awk '{printf "%.0f", $1*1000}')"
		[ -n "$ms" ] || ms=0
		[ "$first" -eq 1 ] || out="$out,"
		first=0
		out="$out{\"host\":\"$h\",\"code\":\"$code\",\"time\":\"${ms} ms\",\"via\":\"mihomo 7890\"}"
	done
	ok "{\"ok\":true,\"mode\":\"经 7890 出口\",\"data\":$out}"
	;;

dns)
	loc="$(uci get easyproxy.routing.dns_local_server 2>/dev/null)"
	rem="$(uci get easyproxy.routing.dns_remote_server 2>/dev/null)"
	rsd="$(uci get easyproxy.routing.rule_set_dir 2>/dev/null)"
	st="$("$EP" status --json 2>/dev/null)"
	dmode="$(jget "$st" dns_mode)"
	ok "{\"ok\":true,\"data\":{\"dns_local\":\"$(jesc "${loc:-—}")\",\"dns_remote\":\"$(jesc "${rem:-—}")\",\"dns_mode\":\"$(jesc "${dmode:-—}")\",\"fakeip\":\"未启用\",\"cache\":1,\"ruleset_dir\":\"$(jesc "${rsd:-—}")\"}}"
	;;

engines)
	out='['
	first=1
	for e in sing-box mihomo dae; do
		if [ "$e" = "sing-box" ]; then key="sing_box"; else key="$e"; fi
		bin="$(uci get "easyproxy.$key.binary" 2>/dev/null)"
		inst=0
		if [ -n "$bin" ] && [ -x "$bin" ]; then inst=1; fi
		[ "$first" -eq 1 ] || out="$out,"
		first=0
		out="$out{\"name\":\"$e\",\"binary\":\"$(jesc "${bin:-}")\",\"installed\":$inst}"
	done
	ok "{\"ok\":true,\"data\":$out}"
	;;

engine-use)
	name="$(jget "$BODY" name)"
	[ -n "$name" ] || bad "缺少 name"
	out="$("$EP" engine use "$name" 2>&1)"
	rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-切换失败}" | tr '\n' ' ')"
	ok "{\"ok\":true,\"message\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

node-toggle)
	sec="$(jget "$BODY" section)"
	[ -n "$sec" ] || bad "缺少 section"
	en="$(printf '%s' "$BODY" | sed -n 's/.*"enable"[ ]*:[ ]*\([0-9]*\).*/\1/p' | head -1)"
	if [ "${en:-1}" = "0" ]; then act=disable; else act=enable; fi
	out="$("$EP" node "$act" "$sec" 2>&1)"
	rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-操作失败}" | tr '\n' ' ')"
	ok "{\"ok\":true}"
	;;

node-import)
	url="$(jget "$BODY" url)"
	[ -n "$url" ] || bad "缺少订阅地址"
	out="$("$EP" node import-clash "$url" 2>&1)"
	rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-导入失败}" | tr '\n' ' ')"
	ok "{\"ok\":true,\"message\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

passwd)
	old="$(jget "$BODY" old)"
	new="$(jget "$BODY" new)"
	[ -n "$new" ] || bad "新密码不能为空"
	[ "${#new}" -ge 6 ] || bad "新密码至少 6 位"
	want="$(cat "$PW_FILE" 2>/dev/null)"
	got="$(hash_pw "$old")"
	[ "$want" = "$got" ] || bad "当前密码不正确"
	hash_pw "$new" > "$PW_FILE"
	chmod 600 "$PW_FILE"
	: > "$SESS_FILE"
	SET_COOKIE="Set-Cookie: $COOKIE_NAME=; Path=/; Max-Age=0; HttpOnly"
	ok_cookie '{"ok":true}'
	;;

diag)
	out="$("$EP" doctor 2>&1)"
	ok "{\"ok\":true,\"text\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

*)
	bad "未知命令"
	;;
esac
