#!/bin/sh
# Sample byte counters for the panel's traffic chart.
# Usage: sh traffic.sh [iface]  ->  {"ok":true,"iface":"br-lan","rx":N,"tx":N}
# Reads /proc/net/dev only; never writes anything.

iface="$1"
# Which interface to sample matters: br-lan only counts LAN-to-router traffic,
# which is near zero on a router that proxies for the whole LAN. Prefer an
# explicit UCI choice, then the default-route interface (the one that actually
# carries the proxied traffic), then the first LAN interface.
[ -n "$iface" ] || iface="$(uci -q get easyproxy.main.traffic_iface 2>/dev/null)"
if [ -z "$iface" ]; then
	iface="$(LC_ALL=C awk '$1 == "00000000" { print $2; exit }' /proc/net/route 2>/dev/null)"
fi
[ -n "$iface" ] || iface="$(uci -q get easyproxy.transparent.lan_interfaces 2>/dev/null | LC_ALL=C awk '{ print $1 }')"
[ -n "$iface" ] || iface="br-lan"

if [ ! -r /proc/net/dev ]; then
	printf '{"ok":false,"iface":"%s","rx":0,"tx":0}\n' "$iface"
	exit 0
fi

rx=0
tx=0
found=0
while IFS= read -r line; do
	set -- $line
	name="$(printf '%s' "$1" | tr -d ':')"
	[ "$name" = "$iface" ] || continue
	found=1
	rx="$2"
	tx="${10}"
	done <<EOF
$(LC_ALL=C awk 'NR > 2 { gsub(":", " "); print }' /proc/net/dev)
EOF

[ "$found" = "1" ] || {
	rx=0
	tx=0
}

printf '{"ok":%s,"iface":"%s","rx":%s,"tx":%s}\n' \
	"$([ "$found" = "1" ] && printf 'true' || printf 'false')" \
	"$iface" "${rx:-0}" "${tx:-0}"
