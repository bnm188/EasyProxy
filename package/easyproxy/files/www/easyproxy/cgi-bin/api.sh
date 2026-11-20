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

# 概览采样兜底：文件为空时立刻采一次
ov_ensure() {
	OVDIR=/etc/easyproxy/stats
	OVRR="$OVDIR/rr.jsonl"
	mkdir -p "$OVDIR" 2>/dev/null
	if [ ! -s "$OVRR" ]; then
		sh /usr/lib/easyproxy/stats.sh >/dev/null 2>&1
	fi
}

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

# ---- 策略分组（13 个固定业务组） ----
policy-list)
	p="$("$EP" policy list --json 2>/dev/null)"
	[ -n "$p" ] || bad "policy list 调用失败"
	ok "$p"
	;;

policy-show)
	key="$(jget "$BODY" key)"
	[ -n "$key" ] || bad "缺少 key"
	out="$("$EP" policy show "$key" --json 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-policy show 失败}" | tr '\n' ' ')"
	ok "$out"
	;;

policy-set)
	key="$(jget "$BODY" key)"
	opt="$(jget "$BODY" option)"
	val="$(jget "$BODY" value)"
	[ -n "$key" ] || bad "缺少 key"
	[ -n "$opt" ] || bad "缺少 option"
	out="$("$EP" policy set "$key" "$opt" "$val" 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-设置失败}" | tr '\n' ' ')"
	ok '{"ok":true}'
	;;

policy-bind)
	key="$(jget "$BODY" key)"
	nodes="$(jget "$BODY" nodes)"
	[ -n "$key" ] || bad "缺少 key"
	[ -n "$nodes" ] || bad "缺少 nodes"
	# nodes 是空格分隔的节点 section 列表，交给 CLI 分词处理
	out="$("$EP" policy bind "$key" $nodes 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-绑定失败}" | tr '\n' ' ')"
	ok "{\"ok\":true,\"message\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

policy-unbind)
	key="$(jget "$BODY" key)"
	nodes="$(jget "$BODY" nodes)"
	[ -n "$key" ] || bad "缺少 key"
	[ -n "$nodes" ] || bad "缺少 nodes"
	out="$("$EP" policy unbind "$key" $nodes 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-解绑失败}" | tr '\n' ' ')"
	ok "{\"ok\":true,\"message\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

policy-rule-add)
	key="$(jget "$BODY" key)"
	typ="$(jget "$BODY" type)"
	value="$(jget "$BODY" value)"
	[ -n "$key" ] || bad "缺少 key"
	[ -n "$value" ] || bad "缺少 value"
	[ -n "$typ" ] || typ=domain-suffix
	out="$("$EP" policy rule add "$key" "$typ:$value" 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-添加失败}" | tr '\n' ' ')"
	ok "{\"ok\":true,\"section\":\"$(jesc "$(printf '%s' "$out" | tr -d '\n')")\"}"
	;;

policy-rule-del)
	section="$(jget "$BODY" section)"
	[ -n "$section" ] || bad "缺少 section"
	out="$("$EP" policy rule del "$section" 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] || bad "$(printf '%s' "${out:-删除失败}" | tr '\n' ' ')"
	ok '{"ok":true}'
	;;

policy-test)
	out="$("$EP" policy test --json 2>/dev/null)"
	[ -n "$out" ] || bad "policy test 调用失败"
	ok "$out"
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
	# key|显示名|探测地址 —— 概览四站点胶囊
	for pair in "baidu|百度|www.baidu.com" "google|Google|www.google.com" "openai|OpenAI|api.openai.com" "telegram|Telegram|api.telegram.org"; do
		k="${pair%%|*}"; rest="${pair#*|}"
		name="${rest%%|*}"; h="${rest##*|}"
		res="$(curl -s -k -o /dev/null -m 8 -w '%{http_code}|%{time_total}' -x http://127.0.0.1:7890 "https://$h" 2>/dev/null)"
		code="${res%%|*}"
		t="${res##*|}"
		[ -n "$code" ] || code=000
		ms="$(printf '%s' "$t" | awk '{printf "%.0f", $1*1000}')"
		[ -n "$ms" ] || ms=0
		okf=false
		case "$code" in 200|204|301|302|404|400|401|403) okf=true ;; esac
		[ "$first" -eq 1 ] || out="$out,"
		first=0
		out="$out{\"key\":\"$k\",\"name\":\"$name\",\"host\":\"$h\",\"code\":\"$code\",\"ms\":$ms,\"time\":\"${ms} ms\",\"ok\":$okf,\"via\":\"mihomo 7890\"}"
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

# ================= 概览页新接口（Openbox 同构） =================
# 数据来源：/etc/easyproxy/stats/（stats.sh 每分钟采样）

vitals)
	ov_ensure
	[ -s "$OVRR" ] || bad "采样器未产生数据（stats.sh 未运行）"
	LAST="$(tail -1 "$OVRR")"
	cpu="$(printf '%s' "$LAST" | sed -n 's/.*"cpu":\([0-9.]*\).*/\1/p')"
	cores="$(printf '%s' "$LAST" | sed -n 's/.*"cores":"\([^"]*\)".*/\1/p')"
	mu="$(printf '%s' "$LAST" | sed -n 's/.*"mu":\([0-9]*\).*/\1/p')"
	mt="$(printf '%s' "$LAST" | sed -n 's/.*"mt":\([0-9]*\).*/\1/p')"
	mp="$(printf '%s' "$LAST" | sed -n 's/.*"mp":\([0-9]*\).*/\1/p')"
	rss="$(printf '%s' "$LAST" | sed -n 's/.*"rss":\([0-9]*\).*/\1/p')"
	ser="$(tail -60 "$OVRR" 2>/dev/null | sed -n 's/.*"cpu":\([0-9.]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')"
	cj="$(printf '%s' "$cores" | awk 'BEGIN{printf "[";f=1} {n=split($0,a," "); for(i=1;i<=n;i++){split(a[i],b,":"); if(length(b)>=2){printf "%s%s", (f?"":","), "{\"i\":"b[1]",\"p\":"b[2]"}"} }} END{printf "]"}')"
	MU="${mu:-0}"; MT="${mt:-0}"; AV=$(( MT - MU ))
	up="$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)"
	eng="$("$EP" status --json 2>/dev/null | sed -n 's/.*"engine":"\([^"]*\)".*/\1/p')"
	ok "{\"ok\":true,\"cpu\":{\"total\":${cpu:-0},\"cores\":${cj},\"series\":[${ser}]},\"mem\":{\"used_mb\":$MU,\"total_mb\":$MT,\"avail_mb\":$AV,\"pct\":${mp:-0}},\"proc\":{\"name\":\"$(jesc "${eng:-内核}")\",\"rss_mb\":${rss:-0}},\"uptime\":${up:-0}}"
	;;

netstatus)
	ov_ensure
	[ -s "$OVRR" ] || bad "采样器未产生数据（stats.sh 未运行）"
	LAST="$(tail -1 "$OVRR")"
	ur="$(printf '%s' "$LAST" | sed -n 's/.*"ur":\([0-9]*\).*/\1/p')"
	dr="$(printf '%s' "$LAST" | sed -n 's/.*"dr":\([0-9]*\).*/\1/p')"
	cn="$(printf '%s' "$LAST" | sed -n 's/.*"cn":\([0-9]*\).*/\1/p')"
	cl="$(printf '%s' "$LAST" | sed -n 's/.*"cl":\([0-9]*\).*/\1/p')"
	today="$(date +%Y-%m-%d)"
	tline="$(awk -F, -v d="$today" '$1==d{print $2" "$3}' /etc/easyproxy/stats/daily.csv 2>/dev/null)"
	ut="$(printf '%s' "$tline" | awk '{print $1+0}')"
	dt="$(printf '%s' "$tline" | awk '{print $2+0}')"
	sc="$(tail -60 "$OVRR" 2>/dev/null | sed -n 's/.*"cn":\([0-9]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')"
	sl="$(tail -60 "$OVRR" 2>/dev/null | sed -n 's/.*"cl":\([0-9]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')"
	su="$(tail -60 "$OVRR" 2>/dev/null | sed -n 's/.*"ur":\([0-9]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')"
	sd="$(tail -60 "$OVRR" 2>/dev/null | sed -n 's/.*"dr":\([0-9]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')"
	at="$(uci -q get easyproxy.main.overview_autotest 2>/dev/null)"
	case "$at" in 0|off|false) atf=false ;; *) atf=true ;; esac
	ok "{\"ok\":true,\"autotest\":$atf,\"kpi\":{\"conn\":${cn:-0},\"clients\":${cl:-0},\"up_rate\":${ur:-0},\"down_rate\":${dr:-0},\"up_total\":${ut:-0},\"down_total\":${dt:-0}},\"series\":{\"conn\":[${sc}],\"clients\":[${sl}],\"up\":[${su}],\"down\":[${sd}]}}"
	;;

insight)
	MONTH="$(jget "$BODY" month)"
	[ -n "$MONTH" ] || MONTH="$(printf '%s' "$QS" | sed -n 's/.*month=\([0-9][0-9]*-[0-9][0-9]*\).*/\1/p')"
	[ -n "$MONTH" ] || MONTH="$(date +%Y-%m)"
	ds="$(awk -F, -v m="$MONTH" '
		index($1,m"-")==1 { d=substr($1,length(m)+2)+0; if(d>0) printf "%s{\"d\":%d,\"up\":%s,\"down\":%s}", (n++?",":""), d, $2, $3 }
	' /etc/easyproxy/stats/daily.csv 2>/dev/null)"
	tu="$(awk -F, -v m="$MONTH" 'index($1,m"-")==1{ s+=$2 } END{printf "%d", s+0}' /etc/easyproxy/stats/daily.csv 2>/dev/null)"
	td="$(awk -F, -v m="$MONTH" 'index($1,m"-")==1{ s+=$3 } END{printf "%d", s+0}' /etc/easyproxy/stats/daily.csv 2>/dev/null)"
	nd="$(awk -F, -v m="$MONTH" 'index($1,m"-")==1{ n++ } END{printf "%d", n+0}' /etc/easyproxy/stats/daily.csv 2>/dev/null)"
	tdy="$(date +%Y-%m-%d)"
	hs="$(awk -F, -v d="$tdy" '$1==d{ printf "%s{\"h\":%d,\"up\":%s,\"down\":%s}", (n++?",":""), $2+0, $3, $4 }' /etc/easyproxy/stats/hourly.csv 2>/dev/null)"
	tup="$(awk -F, -v d="$tdy" '$1==d{ s+=$3 } END{printf "%d", s+0}' /etc/easyproxy/stats/hourly.csv 2>/dev/null)"
	tdn="$(awk -F, -v d="$tdy" '$1==d{ s+=$4 } END{printf "%d", s+0}' /etc/easyproxy/stats/hourly.csv 2>/dev/null)"
	cs="$(sort -t, -k2,2nr /etc/easyproxy/stats/clients.csv 2>/dev/null | head -8 | awk -F, '{printf "%s{\"ip\":\"%s\",\"conn\":%s,\"last\":%s}", (n++?",":""), $1, $2+0, $3+0}')"
	ok "{\"ok\":true,\"month\":\"$MONTH\",\"month_total\":{\"up\":${tu:-0},\"down\":${td:-0},\"days\":${nd:-0}},\"days\":[${ds}],\"today\":{\"date\":\"$tdy\",\"up\":${tup:-0},\"down\":${tdn:-0},\"hours\":[${hs}]},\"clients\":[${cs}]}"
	;;

nodescore)
	raw="$(curl -s -m 8 "$(clash_base)/proxies" 2>/dev/null)"
	[ -n "$raw" ] || bad "Clash API 不可用（引擎可能未运行）"
	# 节点总数（排除组类型与内置）
	tot="$(printf '%s' "$raw" | grep -o '"type":"[^"]*"' | grep -viE 'Selector|URLTest|Fallback|LoadBalance|Direct|Reject|Compatible|Relay|Pass' | wc -l | tr -d ' ')"
	delay_all="$(printf '%s' "$raw" | grep -o '"delay":[0-9]*' | sed 's/"delay"://' | awk '{if($1>0 && $1<5000) print}' )"
	okn="$(printf '%s' "$delay_all" | grep -c . 2>/dev/null | tr -d ' ')"
	avg="$(printf '%s' "$delay_all" | awk '{s+=$1; n++} END{ if(n>0) printf "%d", s/n; else print 0 }')"
	[ -n "$okn" ] || okn=0
	avail=0
	[ "${tot:-0}" -gt 0 ] 2>/dev/null && avail=$(( okn * 100 / tot ))
	lat_score=100
	[ "${avg:-0}" -ge 100 ] 2>/dev/null && lat_score=$(( 100 - (avg - 100) / 5 ))
	[ "$lat_score" -lt 0 ] && lat_score=0
	score=$(( avail * 60 / 100 + lat_score * 40 / 100 ))
	ok "{\"ok\":true,\"score\":$score,\"nodes_total\":${tot:-0},\"nodes_ok\":${okn},\"avail_pct\":$avail,\"delay_avg\":${avg:-0}}"
	;;

diag)
	out="$("$EP" doctor 2>&1)"
	ok "{\"ok\":true,\"text\":\"$(jesc "$(printf '%s' "$out" | tr '\n' ' ')")\"}"
	;;

*)
	bad "未知命令"
	;;
esac
