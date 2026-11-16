#!/bin/sh
# Decide which GitHub releases to delete, so the project keeps at most N.
#
#   gh api "repos/OWNER/REPO/releases?per_page=100" \
#     | sh scripts/release-gc.sh --keep 20 --protect v0.6.0
#
# Reads the GitHub API releases array on stdin and writes the plan on stdout:
#
#   KEEP   v0.25.0  最新版本
#   DELETE v0.5.0   超出保留数量（keep=20）
#
# The caller performs the deletion for every DELETE line. Nothing is deleted
# here, so the decision can be reviewed in the job log first.
#
# Protection rules, in order (deleting a release cannot be undone):
#   1. drafts are never deleted and never counted against the limit
#   2. the newest release is never deleted
#   3. a release whose assets have downloads is never deleted: someone is
#      installing it, so it is still in use
#   4. a tag passed with --protect is never deleted (the version the installer
#      pins, or any version an operator names)
#   5. everything else beyond the newest N is deleted
# A protected release beyond the limit makes the total exceed N on purpose:
# keeping a release in use matters more than hitting the number exactly.

set -u

KEEP=20
PROTECT=""

while [ $# -gt 0 ]; do
	case "$1" in
		--keep) KEEP="${2:-}"; shift 2 ;;
		--keep=*) KEEP="${1#*=}"; shift ;;
		--protect) PROTECT="${2:-}"; shift 2 ;;
		--protect=*) PROTECT="${1#*=}"; shift ;;
		-h|--help)
			echo "usage: release-gc.sh [--keep N] [--protect tag[,tag]]" >&2
			exit 0
			;;
		*)
			echo "release-gc: unknown argument: $1" >&2
			exit 2
			;;
	esac
done

case "$KEEP" in
	''|*[!0-9]*) echo "release-gc: --keep needs a number, got '${KEEP}'" >&2; exit 2 ;;
esac
[ "$KEEP" -gt 0 ] || { echo "release-gc: --keep must be at least 1" >&2; exit 2; }

IN="$(cat)"
[ -n "$IN" ] || { echo "release-gc: empty input (pipe the GitHub releases JSON on stdin)" >&2; exit 2; }

ROWS="$(printf '%s' "$IN" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception as exc:
    sys.stderr.write("release-gc: cannot parse the releases JSON: %s\n" % exc)
    raise SystemExit(2)

if not isinstance(data, list):
    sys.stderr.write("release-gc: expected a JSON array of releases\n")
    raise SystemExit(2)

for r in data:
    tag = (r.get("tag_name") or "").strip()
    if not tag:
        continue
    created = (r.get("created_at") or "")
    draft = "1" if r.get("draft") else "0"
    downloads = 0
    for a in (r.get("assets") or []):
        try:
            downloads += int(a.get("download_count") or 0)
        except (TypeError, ValueError):
            pass
    print("%s\t%s\t%s\t%d" % (created, tag, draft, downloads))
')" || exit 2

if [ -z "$ROWS" ]; then
	echo "release-gc: no release in the input, nothing to do"
	exit 0
fi

printf '%s\n' "$ROWS" | sort -r | {
	idx=0
	while IFS="$(printf '\t')" read -r created tag draft downloads; do
		[ -n "$tag" ] || continue
		if [ "$draft" = "1" ]; then
			printf 'KEEP\t%s\t草稿，不计入保留数量\n' "$tag"
			continue
		fi
		reason=""
		if [ "$idx" -eq 0 ]; then
			reason="最新版本"
		elif [ "$downloads" -gt 0 ]; then
			reason="资产已被下载 ${downloads} 次，仍在使用"
		elif printf ' %s ' "$PROTECT" | tr ',' ' ' | grep -q " ${tag} "; then
			reason="受保护（--protect），不删除"
		elif [ "$idx" -ge "$KEEP" ]; then
			printf 'DELETE\t%s\t超出保留数量（keep=%s）\n' "$tag" "$KEEP"
			idx=$((idx + 1))
			continue
		else
			reason="属于最新 ${KEEP} 个版本"
		fi
		printf 'KEEP\t%s\t%s\n' "$tag" "$reason"
		idx=$((idx + 1))
	done
}
