#!/bin/sh
# Fetch a subscription and import its share links one by one.
# Usage: sh subscribe.sh <url> [name-prefix]
#
# Two things this must survive on a real router:
#   * a busybox image with neither `base64` nor `openssl` (the v2ray style
#     base64 blob is decoded through node.sh, whose awk codec always works);
#   * importing the same subscription twice, which used to create duplicate
#     nodes and then break the whole config generation (duplicate outbound tag).
#
# The URL itself is never logged; the caller may record it in
# /etc/easyproxy/subscribe.conf (mode 600) so the daily update can re-run it.

[ -n "$1" ] || { echo "usage: subscribe.sh <url> [name-prefix]" >&2; exit 2; }
url="$1"
prefix="$2"

case "$url" in
	http://*|https://*) ;;
	*)
		echo "refusing subscription URL: only http:// and https:// are accepted" >&2
		exit 2
		;;
esac

EP_LIB_DIR="${EP_LIB_DIR:-/usr/lib/easyproxy}"
EP_CONFIG="${EP_CONFIG:-easyproxy}"
EP_CONFIG_FILE="${EP_CONFIG_FILE:-/etc/config/easyproxy}"
if [ -r "$EP_LIB_DIR/common.sh" ] && [ -r "$EP_LIB_DIR/node.sh" ]; then
	. "$EP_LIB_DIR/common.sh"
	. "$EP_LIB_DIR/node.sh"
fi

tmp="$(mktemp /tmp/easyproxy-sub.XXXXXX 2>/dev/null)" || exit 1
trap 'rm -f "$tmp" "$tmp.dec" "$tmp.b64"' EXIT

if command -v curl >/dev/null 2>&1; then
	curl -fsSL --max-time 30 -A 'EasyProxy/0.8' "$url" -o "$tmp" || { echo "download failed" >&2; exit 1; }
else
	wget -q -T 30 -O "$tmp" "$url" || { echo "download failed" >&2; exit 1; }
fi
[ -s "$tmp" ] || { echo "subscription is empty" >&2; exit 1; }

# v2ray style subscriptions ship a base64 blob with no scheme at all.
if ! grep -q '://' "$tmp" 2>/dev/null; then
	tr -d '\r\n ' < "$tmp" > "$tmp.b64"
	body="$(cat "$tmp.b64")"
	decoded=""
	if command -v ep_b64_decode >/dev/null 2>&1; then
		decoded="$(ep_b64_decode "$body")"
	fi
	if [ -n "$decoded" ]; then
		printf '%s\n' "$decoded" > "$tmp.dec"
		mv "$tmp.dec" "$tmp"
	else
		echo "subscription is neither plain links nor decodable base64" >&2
		exit 1
	fi
fi

added=0
skipped=0
failed=0
while IFS= read -r line; do
	line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	case "$line" in
		""|\#*) continue ;;
	esac
	case "$line" in
		*://*) ;;
		*) continue ;;
	esac

	# Duplicate detection runs on the parsed endpoint, not on the name: a
	# subscription that ships the same server twice must not create two nodes.
	key=""
	if command -v ep_node_key_from_uri >/dev/null 2>&1; then
		key="$(ep_node_key_from_uri "$line" 2>/dev/null)"
	fi
	if [ -n "$key" ] && ep_node_exists_key "$key"; then
		skipped=$((skipped + 1))
		continue
	fi

	if [ -n "$prefix" ]; then
		name="$prefix-$((added + skipped + failed + 1))"
		if easyproxy node add "$line" "$name" >/dev/null 2>&1; then
			added=$((added + 1))
		else
			failed=$((failed + 1))
		fi
	else
		if easyproxy node add "$line" >/dev/null 2>&1; then
			added=$((added + 1))
		else
			failed=$((failed + 1))
		fi
	fi
done < "$tmp"

printf 'imported: %s, skipped: %s, failed: %s\n' "$added" "$skipped" "$failed"
[ "$added" -gt 0 ] || [ "$skipped" -gt 0 ]
