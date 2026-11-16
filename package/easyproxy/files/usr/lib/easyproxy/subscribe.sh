#!/bin/sh
# Fetch a subscription and import its share links one by one.
# Usage: sh subscribe.sh <url> [name-prefix]
# The URL is never written to UCI or the log: this is a one-shot import.

[ -n "$1" ] || { echo "usage: subscribe.sh <url> [name-prefix]" >&2; exit 2; }
url="$1"
prefix="$2"

# This runs as root (it is started by the root-owned CLI), so the scheme is
# checked here as well: curl would happily read `file:///etc/shadow` or speak
# gopher to a local service. Only http(s) subscriptions are supported.
case "$url" in
	http://*|https://*) ;;
	*)
		echo "refusing subscription URL: only http:// and https:// are accepted" >&2
		exit 2
		;;
esac
tmp="$(mktemp /tmp/easyproxy-sub.XXXXXX 2>/dev/null)" || exit 1
trap 'rm -f "$tmp" "$tmp.dec"' EXIT

if command -v curl >/dev/null 2>&1; then
	curl -fsSL --max-time 30 -A 'EasyProxy/0.6' "$url" -o "$tmp" || { echo "download failed" >&2; exit 1; }
else
	wget -q -T 30 -O "$tmp" "$url" || { echo "download failed" >&2; exit 1; }
fi
[ -s "$tmp" ] || { echo "subscription is empty" >&2; exit 1; }

# v2ray style subscriptions ship a base64 blob with no scheme at all.
