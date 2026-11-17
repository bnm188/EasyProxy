#!/bin/sh
# Aggregate runner: the only place a suite total may come from.
#
#   sh tests/run-all.sh              # logs into ./test-logs
#   EP_SING_BOX_BIN=... sh tests/run-all.sh
#   EP_TEST_LOG_DIR=/tmp/x sh tests/run-all.sh
#
# Why this exists (report 005): the 504 figure quoted in report 004 came from
# ten separate runs added up by hand. A number assembled by hand can drift from
# what actually ran, and a suite that prints SKIP or dies before its result line
# silently contributes 0 while still "passing". This runner therefore
#   * only counts the `结果：N 通过，M 失败` line that each suite prints at the end,
#   * treats a missing result line as 未覆盖 (not as a pass),
#   * treats any `  SKIP  ` line as a failure of the run,
#   * cross-checks the exit code against the parsed counts,
#   * lists every suite that did not contribute.
#
# The real sing-box is handed only to the suites that validate a generated
# config. The installer suite asserts that the kernel is *downloaded*, so a host
# EP_SING_BOX_BIN would make those assertions pass without a download (that is
# what made CI red in runs #116..#122).

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${EP_TEST_LOG_DIR:-$SRC/test-logs}"
mkdir -p "$LOG_DIR"

# Every suite that must run. A missing file is a coverage gap, not a pass.
EXPECTED="test-cli test-engine test-install-scripts test-ipk-layout test-maintenance test-nodes test-regressions test-routing test-runtime test-release test-security test-transparent"

say() { printf '%s\n' "$*"; }

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED=""
SKIPPED=""
UNCOVERED=""
INCONSISTENT=""

printf '%-24s %8s %8s %6s  %s\n' "suite" "通过" "失败" "SKIP" "日志"
printf '%-24s %8s %8s %6s  %s\n' "------------------------" "--------" "--------" "------" "----"

for name in $EXPECTED; do
	t="$SRC/tests/$name.sh"
	log="$LOG_DIR/$name.log"
	if [ ! -r "$t" ]; then
		UNCOVERED="$UNCOVERED $name(文件缺失)"
		printf '%-24s %8s %8s %6s  %s\n' "$name" "-" "-" "-" "文件缺失，未覆盖"
		continue
	fi

	rc=0
	case "$name" in
		test-routing|test-runtime|test-transparent|test-engine)
			if [ -n "${EP_SING_BOX_BIN:-}" ]; then
				EP_SING_BOX_BIN="$EP_SING_BOX_BIN" sh "$t" > "$log" 2>&1 || rc=$?
			else
				env -u EP_SING_BOX_BIN sh "$t" > "$log" 2>&1 || rc=$?
			fi
			;;
		*)
			env -u EP_SING_BOX_BIN sh "$t" > "$log" 2>&1 || rc=$?
			;;
	esac

	line="$(grep -E '结果：[0-9]+ 通过，[0-9]+ 失败' "$log" | tail -n 1)"
	if [ -z "$line" ]; then
		UNCOVERED="$UNCOVERED $name(无结果行)"
		printf '%-24s %8s %8s %6s  %s\n' "$name" "?" "?" "?" "没有打印结果行，未覆盖（rc=$rc）"
		continue
	fi
	p="$(printf '%s' "$line" | sed -n 's/.*结果：\([0-9][0-9]*\) 通过.*/\1/p')"
	f="$(printf '%s' "$line" | sed -n 's/.*通过，\([0-9][0-9]*\) 失败.*/\1/p')"
	sk="$(grep -c '  SKIP  ' "$log" 2>/dev/null || true)"
	[ -n "$sk" ] || sk=0

	TOTAL_PASS=$((TOTAL_PASS + p))
	TOTAL_FAIL=$((TOTAL_FAIL + f))

	if [ "$f" -gt 0 ]; then
		FAILED="$FAILED $name"
	fi
	if [ "$sk" -gt 0 ]; then
		SKIPPED="$SKIPPED $name"
	fi
	# The suite must agree with its own exit code: rc=0 with failures, or
	# rc!=0 with no failures, means the suite is not reporting what happened.
	if { [ "$rc" -eq 0 ] && [ "$f" -gt 0 ]; } || { [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; }; then
		INCONSISTENT="$INCONSISTENT $name(rc=$rc,失败=$f)"
	fi

	printf '%-24s %8s %8s %6s  %s\n' "$name" "$p" "$f" "$sk" "$log"
done

say ""
say "合计（只统计各套件自己打印的结果行）：$TOTAL_PASS 通过，$TOTAL_FAIL 失败"
if [ -n "$SKIPPED" ]; then
	say "SKIP（跳过不等于通过）：$SKIPPED"
fi
if [ -n "$FAILED" ]; then
	say "失败套件：$FAILED"
fi
if [ -n "$INCONSISTENT" ]; then
	say "结果自相矛盾的套件：$INCONSISTENT"
fi
if [ -n "$UNCOVERED" ]; then
	say "未覆盖（不计入通过）：$UNCOVERED"
fi
say "未覆盖的验证面（套件无法覆盖，报告里必须写明）：真机安装/升级/回滚、真实 rpcd 渲染 ACL、shellcheck（环境未安装）"

status=0
[ "$TOTAL_FAIL" -eq 0 ] || status=1
[ -z "$SKIPPED" ] || status=1
[ -z "$INCONSISTENT" ] || status=1
[ -z "$UNCOVERED" ] || status=1
exit "$status"
