#!/bin/sh
# CLI-level test: runs the real `easyproxy` script with its /usr/lib paths
# redirected at the repo copy, against an executable `uci` stub on PATH.
set -u
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd)
LIB="$ROOT/package/easyproxy/files/usr/lib/easyproxy"
BIN="$ROOT/package/easyproxy/files/usr/sbin/easyproxy"
STORE=$(mktemp)
TMPBIN=$(mktemp)
BINDIR=$(mktemp -d)
PASS=0
FAIL=0

sed "s#/usr/lib/easyproxy/#$LIB/#g; s#/usr/share/easyproxy/#$ROOT/package/easyproxy/files/usr/share/easyproxy/#g" "$BIN" > "$TMPBIN"

cat > "$BINDIR/uci" <<'STUB'
#!/bin/sh
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
		[ -z "$out" ] && exit 1
		printf '%s\n' "$out"
		;;
	set)
		kv="$1"; k=${kv%%=*}; v=${kv#*=}
		sed -i "\#^${k}=#d" "$STORE" 2>/dev/null
		printf '%s=%s\n' "$k" "$v" >> "$STORE"
		;;
	delete)
		k=${1#easyproxy.}
		awk -F= -v p="easyproxy.$k" '$1 !~ "^"p {print}' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
		;;
	show)
		pkg="$1"
		while IFS= read -r line; do
			case "$line" in
				"$pkg".*=*)
					section="${line%%=*}"; rest="${section#*.}"
					if [ "$rest" != "${rest#*.}" ]; then
						printf "%s='%s'\n" "$section" "${line#*=}"
					else
						printf '%s\n' "$line"
					fi
					;;
			esac
		done < "$STORE"
		;;
	commit) ;;
	*) exit 1 ;;
esac
exit 0
STUB
chmod +x "$BINDIR/uci"
export STORE
export PATH="$BINDIR:$PATH"

check() {
	desc="$1"; expect="$2"; got="$3"
	if [ "$got" = "$expect" ]; then
		PASS=$((PASS + 1))
		printf '  ok   %s\n' "$desc"
	else
		printf '  FAIL %s\n     expect=[%s]\n     got   =[%s]\n' "$desc" "$expect" "$got"
			FAIL=$((FAIL + 1))
	fi
}

printf 'policy CLI tests\n'

check "policy list exits 0" "0" "$(sh "$TMPBIN" policy list >/dev/null 2>&1; echo $?)"
check "policy list shows 13 rows" "13" "$(sh "$TMPBIN" policy list 2>/dev/null | tail -n +2 | grep -c .)"
check "policy list --json has 13 keys" "13" "$(sh "$TMPBIN" policy list --json 2>/dev/null | grep -o '"key":' | wc -l | tr -d ' ')"

uci -q set easyproxy.n1=node
uci -q set easyproxy.n1.name=HK-01
uci -q set easyproxy.n1.enabled=1
uci -q set easyproxy.n2=node
uci -q set easyproxy.n2.name=US-02
uci -q set easyproxy.n2.enabled=1


check "bind reports new members" "bound: 2 new member(s), 2 total" "$(sh "$TMPBIN" policy bind netflix n1 n2 2>&1)"
check "bind is idempotent" "bound: 0 new member(s), 2 total" "$(sh "$TMPBIN" policy bind netflix n1 n2 2>&1)"
check "show json has 2 node objects" "2" "$(sh "$TMPBIN" policy show netflix --json 2>/dev/null | grep -o '"section":' | wc -l | tr -d ' ')"

check "rule add prints section" "y" "$(case "$(sh "$TMPBIN" policy rule add netflix domain-suffix:.abc.test 2>/dev/null)" in pr_netflix_*) echo y;; *) echo n;; esac)"
check "rule list shows it" "domain-suffix:.abc.test" "$(sh "$TMPBIN" policy rule list netflix 2>/dev/null)"

check "unknown key rejected" "2" "$(sh "$TMPBIN" policy show foo >/dev/null 2>&1; echo $?)"
check "bad mode rejected" "2" "$(sh "$TMPBIN" policy set netflix mode bogus >/dev/null 2>&1; echo $?)"
sh "$TMPBIN" policy set netflix label 视频 >/dev/null 2>&1
check "set label works" "视频" "$(sh "$TMPBIN" policy show netflix 2>/dev/null | awk -F': *' '/Label/ {print $2}')"

printf '\n结果：%s 通过，%s 失败\n' "$PASS" "$FAIL"
rm -rf "$STORE" "$TMPBIN" "$BINDIR"
[ $FAIL -eq 0 ]
