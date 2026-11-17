#!/usr/bin/env sh
# Suite for scripts/easyproxy.sh - the single SSH entry point.
#
#   sh tests/test-entry.sh
#
# The entry never installs anything itself: it fetches install.sh / uninstall.sh
# and hands over the work. What this suite pins down is the hand-over, above all
# that arguments survive it: `install --rootfs` must reach install.sh, otherwise
# a firmware with no usable package manager has no way in through this entry.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/fix"

# --- stubs ----------------------------------------------------------------
# easyproxy.sh refuses to act unless it runs as root.
cat > "$SB/bin/id" <<'STUB'
#!/bin/sh
printf '0\n'
STUB

# Records the arguments the entry passed through, so the assertions can read
# them instead of guessing from output text.
cat > "$SB/fix/install-stub.sh" <<'STUB'
#!/bin/sh
printf 'install.sh %s\n' "$*" >> "$EP_ARGS_LOG"
exit 0
STUB

cat > "$SB/fix/uninstall-stub.sh" <<'STUB'
#!/bin/sh
printf 'uninstall.sh %s\n' "$*" >> "$EP_ARGS_LOG"
exit 0
STUB

cat > "$SB/bin/wget" <<'STUB'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
	case "$1" in
		-qO) out="$2"; url="$3"; shift 3 ;;
		-q) shift ;;
		-O) out="$2"; shift 2 ;;
		-*) shift ;;
		*) url="$1"; shift ;;
	esac
done
[ -n "$out" ] || exit 1
case "$url" in
	*/install.sh)   cp "$EP_TEST_FIX/install-stub.sh" "$out" ;;
	*/uninstall.sh) cp "$EP_TEST_FIX/uninstall-stub.sh" "$out" ;;
	*) exit 22 ;;
esac
STUB

cat > "$SB/bin/opkg" <<'STUB'
#!/bin/sh
exit 0
STUB
cat > "$SB/bin/apk" <<'STUB'
#!/bin/sh
exit 0
STUB
cat > "$SB/bin/nft" <<'STUB'
#!/bin/sh
exit 0
STUB

chmod +x "$SB/bin/"* "$SB/fix/"*

export EP_TEST_FIX="$SB/fix"
export EP_ARGS_LOG="$SB/args"
export PATH="$SB/bin:$PATH"

ENTRY="$SRC/scripts/easyproxy.sh"

run() { : > "$EP_ARGS_LOG"; sh "$ENTRY" "$@" > "$SB/out" 2>&1; echo $?; }
args() { cat "$EP_ARGS_LOG" 2>/dev/null || true; }

# --- install keeps the arguments it was given -----------------------------
rc="$(run install)"
[ "$rc" = 0 ] && ok "install：退出码 0" || no "install：退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q '^install.sh install' "$EP_ARGS_LOG" 2>/dev/null \
	&& ok "install：调用安装器并传 install" || no "install：调用安装器并传 install" "$(args)"

rc="$(run install --rootfs)"
[ "$rc" = 0 ] && ok "install --rootfs：退出码 0" || no "install --rootfs：退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q -- 'install.sh install --rootfs' "$EP_ARGS_LOG" 2>/dev/null \
	&& ok "install --rootfs：--rootfs 透传到安装器" || no "install --rootfs：--rootfs 透传到安装器" "$(args)"

rc="$(run install --rootfs --no-dae)"
grep -q -- 'install.sh install --rootfs --no-dae' "$EP_ARGS_LOG" 2>/dev/null \
	&& ok "install 多个参数原样透传" || no "install 多个参数原样透传" "$(args)"

# --- upgrade keeps the arguments it was given -----------------------------
rc="$(run upgrade)"
[ "$rc" = 0 ] && ok "upgrade：退出码 0（拒绝不等于失败）" || no "upgrade：退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q '^install.sh upgrade' "$EP_ARGS_LOG" 2>/dev/null \
	&& ok "upgrade：调用安装器的 upgrade" || no "upgrade：调用安装器的 upgrade" "$(args)"

# --- uninstall already passed arguments through; keep it that way ---------
rc="$(run uninstall --keep-config)"
[ "$rc" -ne 0 ] || grep -q -- 'uninstall.sh .*--keep-config' "$EP_ARGS_LOG" 2>/dev/null \
	&& ok "uninstall 透传参数" || no "uninstall 透传参数" "$(args)"

# --- unknown verb is a usage error, never a silent install ----------------
rc="$(run bogus)"
[ "$rc" -ne 0 ] && ok "未知动词返回非 0" || no "未知动词返回非 0" "rc=$rc $(cat "$SB/out")"
[ -s "$EP_ARGS_LOG" ] && no "未知动词不得调用任何子脚本" "$(args)" || ok "未知动词没有调用子脚本"

# --- status is read-only: it may call the installer, never mutate it ------
rc="$(run status)"
[ "$rc" = 0 ] && ok "status：退出码 0" || no "status：退出码 0" "rc=$rc $(cat "$SB/out")"
grep -q '^install.sh status' "$EP_ARGS_LOG" 2>/dev/null \
	&& ok "status：只调用安装器的 status 子命令" || no "status：只调用安装器的 status 子命令" "$(args)"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
