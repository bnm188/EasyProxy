#!/bin/sh
# Generate the short Chinese release note for a version.
#
#   sh scripts/release-notes.sh <version> [<from-ref>]
#
# Run inside the repository. Writes the note to stdout, so the workflow can
# hand it to `gh release create --notes-file`.
#
# The note always carries the three sections the project requires, in this
# order:
#   修复了什么问题      (fix commits)
#   修改了什么功能      (feat/add commits)
#   优化了什么内容      (everything else: perf, refactor, ci, docs, chore)
# A release with an empty note is not allowed, so when the range yields no
# commit at all the script exits 1 instead of printing three empty headings.

set -u

VER="${1:-}"
FROM="${2:-}"

case "$VER" in
	''|*[!0-9A-Za-z._-]*)
		echo "usage: release-notes.sh <version> [<from-ref>]" >&2
		exit 2
		;;
esac

if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "release-notes: this repository has no commit; refusing to publish an empty note" >&2
	exit 1
fi

if [ -n "$FROM" ]; then
	RANGE="${FROM}..HEAD"
else
	RANGE="HEAD"
fi

SUBJECTS="$(git log --no-merges --format='%s' "$RANGE" 2>/dev/null)"
if [ -z "$SUBJECTS" ]; then
	echo "release-notes: range ${RANGE} has no commit; refusing to publish an empty note" >&2
	exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/fix"
: > "$TMP/feat"
: > "$TMP/opt"

printf '%s\n' "$SUBJECTS" | while IFS= read -r subject; do
	[ -n "$subject" ] || continue
	body="$(printf '%s' "$subject" | sed -e 's/^[A-Za-z][A-Za-z0-9_-]*\(([^)]*)\)\{0,1\}!\{0,1\}: //')"
	low="$(printf '%s' "$subject" | tr 'A-Z' 'a-z')"
	# 正式发布说明只写用户关心的修复/功能/优化。开发过程提交不进说明：
	# chore / ci / docs / test / build / style / revert / wip，以及临时诊断与
	# 一次性搬运工作流（diag、one-shot、workflow、.github、report 之类）。
	case "$low" in
		chore*|ci*|docs*|doc*|test*|tests*|build*|style*|revert*|wip*|tmp*|temp*|diag*|diagnos*|*one-shot*|*workflow*|*.github*|*report*|*报告*)
			continue
			;;
	esac
	case "$low" in
		fix*|bugfix*|hotfix*|*修复*|*修掉*|*修正*)
			[ "$(wc -l < "$TMP/fix")" -lt 8 ] && printf -- '- %s\n' "$body" >> "$TMP/fix"
			;;
		feat*|feature*|add*|*新增*|*实现*)
			[ "$(wc -l < "$TMP/feat")" -lt 8 ] && printf -- '- %s\n' "$body" >> "$TMP/feat"
			;;
		*)
			[ "$(wc -l < "$TMP/opt")" -lt 8 ] && printf -- '- %s\n' "$body" >> "$TMP/opt"
			;;
	esac
done

if [ ! -s "$TMP/fix" ] && [ ! -s "$TMP/feat" ] && [ ! -s "$TMP/opt" ]; then
	echo "release-notes: every commit in ${RANGE} is a development-process commit; refusing to publish a note with no user-facing change" >&2
	exit 1
fi

printf 'EasyProxy %s 更新说明\n\n' "$VER"
printf '修复了什么问题\n'
if [ -s "$TMP/fix" ]; then cat "$TMP/fix"; else printf -- '- 本次没有修复类改动\n'; fi
printf '\n修改了什么功能\n'
if [ -s "$TMP/feat" ]; then cat "$TMP/feat"; else printf -- '- 本次没有功能类改动\n'; fi
printf '\n优化了什么内容\n'
if [ -s "$TMP/opt" ]; then cat "$TMP/opt"; else printf -- '- 本次没有优化类改动\n'; fi
printf '\n安装与校验：见本页 Assets 里的 ipk / rootfs.tar.gz 与 SHA256SUMS；安装器会拒绝校验不通过的包。\n'
