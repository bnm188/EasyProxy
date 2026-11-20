#!/bin/sh
# EasyProxy 概览采样器（每分钟由 crond 调用）
# 输出落盘：/etc/easyproxy/stats/
#   rr.jsonl     最近 1440 条分钟采样（硬件负载 + 速率 + 连接）
#   daily.csv    日期,上行字节,下行字节,连接数峰值
#   hourly.csv   日期,小时,上行字节,下行字节
#   clients.csv  ip,上行字节,下行字节,最后seen
# 只读 /proc 与 mihomo 控制器，不写配置。

DIR=/etc/easyproxy/stats
mkdir -p "$DIR" 2>/dev/null
RR="$DIR/rr.jsonl"
DAILY="$DIR/daily.csv"
HOURLY="$DIR/hourly.csv"
CLIENTS="$DIR/clients.csv"
PREV="$DIR/.prev"
[ -f "$RR" ] || : > "$RR"
[ -f "$DAILY" ] || : > "$DAILY"
[ -f "$HOURLY" ] || : > "$HOURLY"
[ -f "$CLIENTS" ] || : > "$CLIENTS"

NOW=$(date +%s)
DAY=$(date +%Y-%m-%d)
HH=$(date +%H)

# ---------- mihomo 控制面 ----------
BASE="$(uci -q get easyproxy.mihomo.controller 2>/dev/null)"
[ -n "$BASE" ] || BASE="127.0.0.1:9090"
case "$BASE" in http*) ;; *) BASE="http://$BASE" ;; esac

# ---------- CPU ----------
awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; print t, ($4+$5)}' /proc/stat 2>/dev/null > "$DIR/.cpu_now"
if [ -s "$DIR/.cpu_now" ]; then
    if [ -s "$DIR/.cpu_prev" ]; then
        CPU="$(awk 'NR==FNR{pt=$1; pi=$2; next}{dt=$1-pt; di=$2-pi; if(dt<=0){print 0}else{p=(dt-di)*100/dt; if(p<0)p=0; if(p>100)p=100; printf "%.1f", p}}' "$DIR/.cpu_prev" "$DIR/.cpu_now")"
    else
        CPU="0.0"
    fi
    cp "$DIR/.cpu_now" "$DIR/.cpu_prev" 2>/dev/null
else
    CPU="0.0"
fi

# 各核（瞬时口径，用两次快照 diff）
CORES="$(awk '/^cpu[0-9]+ /{n=$1; sub("cpu","",n); t=0; for(i=2;i<=NF;i++) t+=$i; busy=t-($4+$5); printf "%s:%d ", n, (t>0? busy*100/t:0)}' /proc/stat 2>/dev/null)"

# ---------- 内存 ----------
MT=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
MA=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
MT="${MT:-0}"; MA="${MA:-0}"
MUSED=$(( (MT - MA) / 1024 ))
MTOT=$(( MT / 1024 ))
MPCT=0
[ "$MT" -gt 0 ] 2>/dev/null && MPCT=$(( (MT - MA) * 100 / MT ))

# ---------- 进程内存（内核进程） ----------
PID="$(pidof mihomo 2>/dev/null | awk '{print $1}')"
[ -n "$PID" ] || PID="$(pidof sing-box 2>/dev/null | awk '{print $1}')"
RSS=0
if [ -n "$PID" ] && [ -r "/proc/$PID/status" ]; then
    RSS=$(awk '/^VmRSS:/{print int($2/1024)}' "/proc/$PID/status" 2>/dev/null)
    [ -n "$RSS" ] || RSS=0
fi

# ---------- 速率 / 连接 / 终端 ----------
TR="$(curl -s -N --max-time 2 "$BASE/traffic" 2>/dev/null | tail -1)"
UP_RATE=$(printf '%s' "$TR" | sed -n 's/.*"up":\([0-9]*\).*/\1/p')
DN_RATE=$(printf '%s' "$TR" | sed -n 's/.*"down":\([0-9]*\).*/\1/p')
[ -n "$UP_RATE" ] || UP_RATE=0
[ -n "$DN_RATE" ] || DN_RATE=0

CONNS="$(curl -s -m 5 "$BASE/connections" 2>/dev/null)"
CN=$(printf '%s' "$CONNS" | grep -o '"id":"[^"]*"' 2>/dev/null | wc -l | tr -d ' ')
CL=$(printf '%s' "$CONNS" | grep -o '"sourceIP":"[^"]*"' 2>/dev/null | sort -u | wc -l | tr -d ' ')
[ -n "$CN" ] || CN=0
[ -n "$CL" ] || CL=0

# ---------- 增量累计 ----------
UP_INC=$(( UP_RATE * 60 ))
DN_INC=$(( DN_RATE * 60 ))

awk -F, -v d="$DAY" -v u="$UP_INC" -v n="$DN_INC" -v c="$CN" '
BEGIN{found=0}
$1==d { $2=$2+u; $3=$3+n; if ($4+0 < c) $4=c; found=1; print $1","$2","$3","$4; next }
{ print }
END{ if(!found) print d","u","n","c }
' "$DAILY" > "$DAILY.t" 2>/dev/null && mv "$DAILY.t" "$DAILY"

awk -F, -v d="$DAY" -v h="$HH" -v u="$UP_INC" -v n="$DN_INC" '
BEGIN{found=0}
$1==d && $2==h { $3=$3+u; $4=$4+n; found=1; print $1","$2","$3","$4; next }
{ print }
END{ if(!found) print d","h","u","n }
' "$HOURLY" > "$HOURLY.t" 2>/dev/null && mv "$HOURLY.t" "$HOURLY"

# 终端：按连接数占比累积（流量分配到不了单 IP，这里只记录连接占用）
if [ "$CL" -gt 0 ]; then
    printf '%s' "$CONNS" | grep -o '"sourceIP":"[^"]*"' 2>/dev/null \
      | sed 's/.*:"//; s/"//' | sort | uniq -c | while read -r cnt ip; do
        awk -F, -v i="$ip" -v c="$cnt" -v n="$NOW" '
        BEGIN{f=0} $1==i { $2=$2+c; $3=n; f=1; print $1","$2","$3; next }
        { print } END{ if(!f) print i","c","n }' "$CLIENTS" > "$CLIENTS.t" 2>/dev/null && mv "$CLIENTS.t" "$CLIENTS"
    done
fi

# ---------- 写 rr ----------
printf '{"t":%s,"cpu":%s,"cores":"%s","mu":%s,"mt":%s,"mp":%s,"rss":%s,"ur":%s,"dr":%s,"cn":%s,"cl":%s}\n' \
    "$NOW" "$CPU" "$CORES" "$MUSED" "$MTOT" "$MPCT" "$RSS" "$UP_RATE" "$DN_RATE" "$CN" "$CL" >> "$RR"

# 保留最近 1440 行
TOTAL=$(wc -l < "$RR" 2>/dev/null | tr -d ' ')
if [ "${TOTAL:-0}" -gt 1440 ] 2>/dev/null; then
    tail -n 1440 "$RR" > "$RR.t" && mv "$RR.t" "$RR"
fi

exit 0
