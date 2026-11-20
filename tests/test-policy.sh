#!/bin/sh
# Off-device unit test for policy.sh. Stubs `uci` against a flat file so the
# group/rule logic can be exercised without OpenWrt.

set -u
HERE=$(dirname "$0")
LIB=$(cd "$HERE/../package/easyproxy/files/usr/lib/easyproxy" && pwd)

STORE=$(mktemp)
PASS=0
FAIL=0

uci() {
	flags=""
	while [ "$1" = "-q" ]; do shift; done
	cmd="$1"; shift
	case "$cmd" in
		get)
			key="$1"
			sect=${key%%\.*}; rest=${key#*.}
			sec=${rest%%.*}; opt=${rest#*.}
			if [ "$opt" = "$sec" ]; then
				out=$(awk -F= -v s="$sect.$sec" '$1==s {print $2}' "$STORE")
			else
				out=$(awk -F= -v s="$sect.$sec.$opt" '$1==s {print substr($0, index($0,"=")+1)}' "$STORE")
			fi
			[ -z "$out" ] && return 1
			printf '%s\n' "$out"
			;;
		set)
			kv="$1"
			k=${kv%%=*}; v=${kv#*=}
			v=$(printf '%s' "$v" | sed "s/^'//; s/'$//")
			if line=$(awk -F= -v s="$k" '$1==s' "$STORE"); then
				if [ -n "$line" ]; then
					sed -i "\\#^${k}=#d" "$STORE"
				fi
			fi
			printf '%s=%s\n' "$k" "$v" >> "$STORE"
			;;
		show)
			pkg="$1"
			awk -F= -v p="$pkg" -v q="'" '$1 ~ "^"p"\\." {
				split($1, a, "=");
				key=$1; val=substr($0, index($0,"=")+1);
				if (val == "") { print key; next }
				print key "=" q val q
			}' "$STORE"
			;;
		commit)
			;;
		delete)
			k=${1#easyproxy.}
			sed -i "\\#^easyproxy\.${k}\\.#d; \\#^easyproxy\.${k}=#d" "$STORE"
			;;
		*) return 1 ;;
	esac
}

# minimal deps from common.sh
ep_get() { uci -q get "easyproxy.$1.$2" || printf '%s' "$3"; }
ep_json_escape() { printf '%s' "$1"; }
ep_err() { EP_ERR="$*"; return 1; }
ep_node_exists_key() { return 0; }
ep_node_resolve() { printf '%s' "$1"; }

. "$LIB/policy.sh"

check() {
	desc="$1"; expect="$2"; got="$3"
	if [ "$got" = "$expect" ]; then
		PASS=$((PASS + 1))
		printf '  ok   %s\n' "$desc"
	else
		printf '  FAIL %s\n     expect=[%s]\n     got   =[%s]\n' "$desc" "$expect" "$got"
		FAIL=$((FAIL+1))
	fi
}

printf 'policy.sh unit tests\n'

ep_policy_ensure
check "13 groups created" "13" "$(uci -q show easyproxy | awk -F= '$2 ~ /policy/ {n++} END{print n+0}')"
check "netflix mode" "urltest" "$(ep_policy_get netflix mode '')"
check "speed sort" "1" "$(ep_policy_get speed sort '')"
check "china mode is direct" "direct" "$(ep_policy_get china mode '')"

check "key valid netflix" "0" "$(ep_policy_key_valid netflix; echo $?)"
check "key invalid foo" "1" "$(ep_policy_key_valid foo; echo $?)"

ep_policy_bind netflix n1 n2 >/dev/null
check "bind two" "n1 n2" "$(ep_policy_nodes netflix)"
ep_policy_bind netflix n2 n3 >/dev/null
check "bind keeps existing, no dupe" "n1 n2 n3" "$(ep_policy_nodes netflix)"
ep_policy_unbind netflix n2 >/dev/null
check "unbind middle" "n1 n3" "$(ep_policy_nodes netflix)"

S=$(ep_policy_rule_add youtube domain-suffix .example.org)
check "rule section created" "y" "$(case "$S" in pr_youtube_*) echo y;; *) echo n;; esac)"
check "rule listed" "domain-suffix:.example.org" "$(ep_policy_rules youtube)"
check "rule json" '[{"type":"domain-suffix","value":".example.org"}]' "$(ep_policy_rules_json youtube)"

check "builtin domains count" "8" "$(ep_policy_domains_json netflix | tr ',' '\n' | wc -l | tr -d ' ')"
ep_policy_rule_del "$S"
check "rule deleted" "" "$(ep_policy_rules youtube)"

ep_policy_bind netflix n9 >/dev/null
check "all bound dedup" "n1 n3 n9" "$(ep_policy_all_bound_nodes)"

uci -q set "easyproxy.p_netflix.builtin=0"
check "builtin off => empty" "0" "$(ep_policy_domains_json netflix | tr -cd ',' | wc -c | tr -d ' ')"

printf '\n结果：%s 通过，%s 失败\n' "$PASS" "$FAIL"
rm -f "$STORE"
[ $FAIL -eq 0 ]
