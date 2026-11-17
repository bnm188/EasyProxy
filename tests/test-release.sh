#!/bin/sh
# Release policy suite (report 005).
#
#   sh tests/test-release.sh
#
# Two things are checked here, both against real code rather than greps:
#   1. scripts/release-notes.sh always produces a short Chinese note with the
#      three required sections, and refuses to produce an empty one.
#   2. scripts/release-gc.sh keeps the newest 20 releases and never drops the
#      latest release, a release whose assets are still being downloaded, or a
#      tag it was told to protect.
# A third block checks that the workflow actually calls those scripts and asks
# for an ipk and SHA256SUMS, so the policy cannot be bypassed by editing one
# side only.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); say "  FAIL  $1"; [ $# -gt 1 ] && say "        $2"; }

RN="$SRC/scripts/release-notes.sh"
GC="$SRC/scripts/release-gc.sh"
WF="$SRC/.github/workflows/build.yml"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# ===========================================================================
# 1. release notes
# ===========================================================================
say ""
say "== 发布说明：中文三节、不允许空白 =="

if [ ! -r "$RN" ]; then
	no "scripts/release-notes.sh 存在" "文件不存在"
else
	ok "scripts/release-notes.sh 存在"
	G="$SB/gitnotes"
	mkdir -p "$G"
	git -C "$G" init -q
	git -C "$G" config user.email t@example.com
	git -C "$G" config user.name t
	git -C "$G" commit -q --allow-empty -m "chore: 初始化"
	git -C "$G" commit -q --allow-empty -m "feat: 新增 traffic 与 subscribe 固定入口"
	git -C "$G" commit -q --allow-empty -m "fix: 修复面板通过 /bin/sh 调脚本的越权问题"
	git -C "$G" commit -q --allow-empty -m "docs: 更新报告索引"

	out="$(cd "$G" && sh "$RN" 0.7.0 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && ok "有内容时 release-notes 退出 0" || no "有内容时 release-notes 退出 0" "rc=$rc, out=$out"

	for h in "修复了什么问题" "修改了什么功能" "优化了什么内容"; do
		printf '%s' "$out" | grep -q "$h" && ok "说明里包含「$h」一节" || no "说明里包含「$h」一节" "$out"
	done
	# Each section must carry at least one bullet: a heading alone is a blank note.
	printf '%s\n' "$out" > "$SB/notes.txt"
	SEC_RES="$(python3 -c '
import sys
text = open(sys.argv[1], encoding="utf-8").read()
order = ["修复了什么问题", "修改了什么功能", "优化了什么内容"]
bad, found = [], []
for i, name in enumerate(order):
    pos = text.find(name)
    if pos < 0:
        bad.append("%s(缺少)" % name)
        continue
    start = pos + len(name)
    end = len(text)
    for nxt in order[i + 1:]:
        p = text.find(nxt, start)
        if p >= 0:
            end = min(end, p)
    bullets = [l for l in text[start:end].splitlines() if l.strip().startswith("- ")]
    if bullets:
        found.append("%s:%d" % (name, len(bullets)))
    else:
        bad.append("%s(没有条目)" % name)
print(" ".join(bad) if bad else "OK " + " ".join(found))
' "$SB/notes.txt")"
	case "$SEC_RES" in
		OK*) ok "三节都至少有一条具体条目（$SEC_RES）" ;;
		*) no "三节都至少有一条具体条目" "$SEC_RES" ;;
	esac
	printf '%s' "$out" | grep -q '越权' && ok "修复条目来自真实提交（含「越权」）" || no "修复条目来自真实提交（含「越权」）" "$out"
	printf '%s' "$out" | grep -q 'traffic' && ok "功能条目来自真实提交（含 traffic）" || no "功能条目来自真实提交（含 traffic）" "$out"
	printf '%s' "$out" | grep -q '0.7.0' && ok "说明里写明版本号 0.7.0" || no "说明里写明版本号 0.7.0" "$out"

	# A repo with no commit at all can produce nothing; publishing must stop.
	E="$SB/gitempty"
	mkdir -p "$E"
	git -C "$E" init -q
	git -C "$E" config user.email t@example.com
	git -C "$E" config user.name t
	out="$(cd "$E" && sh "$RN" 0.7.0 2>&1)"; rc=$?
	[ "$rc" -ne 0 ] && ok "没有任何提交时 release-notes 拒绝生成空白说明" || no "没有任何提交时 release-notes 拒绝生成空白说明" "rc=$rc, out=$out"
fi

# ===========================================================================
# 2. retention: newest 20, and never drop something still in use
# ===========================================================================
say ""
say "== Release 保留策略：最多 20 个，不误删在用版本 =="

mkjson() {
	python3 - "$@" <<'PY'
import json, sys
n, latest_dl, dl_tag, protect = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
out = []
for i in range(n, 0, -1):
    tag = "v0.%d.0" % i
    out.append({
        "tag_name": tag,
        "created_at": "2026-01-%02dT00:00:00Z" % i,
        "draft": False,
        "assets": [{"name": "easyproxy.ipk", "download_count": latest_dl if tag == dl_tag else 0}],
    })
print(json.dumps(out, ensure_ascii=False))
PY
}

if [ ! -r "$GC" ]; then
	no "scripts/release-gc.sh 存在" "文件不存在"
else
	ok "scripts/release-gc.sh 存在"

	# 25 releases, nothing downloaded, newest = v0.25.0
	plan="$(mkjson 25 0 "" "" | sh "$GC" --keep 20 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && ok "25 个版本时 release-gc 退出 0" || no "25 个版本时 release-gc 退出 0" "rc=$rc, $plan"
	dels="$(printf '%s\n' "$plan" | awk '/^DELETE/{print $2}')"
	[ "$(printf '%s\n' "$dels" | grep -c .)" -eq 5 ] && ok "25 个版本只删掉 5 个最旧的" || no "25 个版本只删掉 5 个最旧的" "$plan"
	printf '%s' "$dels" | grep -q 'v0.5.0' && ok "计划的删除包含最旧的 v0.5.0" || no "计划的删除包含最旧的 v0.5.0" "$plan"
	printf '%s' "$dels" | grep -q 'v0.6.0' && no "计划的删除不越过最新 20" "v0.6.0 属于最新 20，却被删除" || ok "计划的删除不越过最新 20"
	printf '%s' "$dels" | grep -q 'v0.25.0' && no "永远不删除最新版本" "v0.25.0 被列入删除" || ok "永远不删除最新版本"

	# v0.1.0 has downloads: it is in use, so it must survive even though it is
	# older than the newest 20. Protecting it means 21 releases stay, which is
	# deliberate - keeping a release that is being installed outweighs hitting
	# the number exactly.
	plan="$(mkjson 25 3 "v0.1.0" "" | sh "$GC" --keep 20 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && ok "有在用版本时 release-gc 仍退出 0" || no "有在用版本时 release-gc 仍退出 0" "rc=$rc, $plan"
	printf '%s\n' "$plan" | awk '/^DELETE/{print $2}' | grep -q 'v0.1.0' \
		&& no "被下载过的最旧版本不删（仍在用）" "v0.1.0 有下载记录却进了删除计划" \
		|| ok "被下载过的最旧版本不删（仍在用）"
	dels="$(printf '%s\n' "$plan" | awk '/^DELETE/{print $2}')"
	[ "$(printf '%s\n' "$dels" | grep -c .)" -eq 4 ] \
		&& ok "保住在用版本后只删剩下的 4 个（总数允许超过 20）" \
		|| no "保住在用版本后只删剩下的 4 个" "$plan"
	printf '%s\n' "$dels" | grep -q 'v0.6.0' \
		&& no "保住在用版本时不误删仍在保留窗口内的版本" "v0.6.0 属于最新 20 却被删" \
		|| ok "保住在用版本时不误删仍在保留窗口内的版本"

	# --protect marks a tag that must never be deleted (the pinned installer version).
	plan="$(mkjson 25 0 "" "v0.2.0" | sh "$GC" --keep 20 --protect v0.2.0 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && ok "--protect 时 release-gc 退出 0" || no "--protect 时 release-gc 退出 0" "rc=$rc, $plan"
	printf '%s\n' "$plan" | awk '/^DELETE/{print $2}' | grep -q 'v0.2.0' \
		&& no "受保护 tag 不进删除计划" "v0.2.0 被列入删除" \
		|| ok "受保护 tag 不进删除计划"

	# Exactly at the limit: nothing to do.
	plan="$(mkjson 20 0 "" "" | sh "$GC" --keep 20 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && ok "正好 20 个版本时 release-gc 退出 0" || no "正好 20 个版本时 release-gc 退出 0" "rc=$rc"
	[ -z "$(printf '%s\n' "$plan" | awk '/^DELETE/{print $2}')" ] && ok "正好 20 个版本时没有删除项" || no "正好 20 个版本时没有删除项" "$plan"
fi

# ===========================================================================
# 3. the workflow must actually use the policy
# ===========================================================================
say ""
say "== 工作流：新版本号、真 Release、IPK + SHA256、中文说明、保留 20 =="

grep -q 'scripts/release-notes.sh' "$WF" && ok "工作流用 release-notes.sh 生成说明" || no "工作流用 release-notes.sh 生成说明"
grep -q 'scripts/release-gc.sh' "$WF" && ok "工作流用 release-gc.sh 做保留清理" || no "工作流用 release-gc.sh 做保留清理"
# Report 009: a tag push was the only trigger, so everyday work on main never
# published. The release intent is now resolved once (tag / dispatch version /
# .release-request file) and every publish step uses that one tag.
grep -q "steps.intent.outputs.tag != ''" "$WF" && ok "发布由统一的发布意图决定（tag、手动版本号或发布请求文件）" || no "发布由统一的发布意图决定（tag、手动版本号或发布请求文件）"
# Report 010: the .release-request file was replaced by the version number
# itself (commit 6aeb4e2). A push to main whose PKG_VERSION is higher than the
# newest published release publishes on its own, so the assertion now covers
# that contract instead of the removed request file.
grep -q 'PKG_VERSION' "$WF" && ok "发布意图读 PKG_VERSION（版本号即发版命令）" || no "发布意图读 PKG_VERSION"
grep -q 'newest release' "$WF" && ok "与最新 Release 比较，高于它才发布" || no "与最新 Release 比较"
grep -q 'GITHUB_REF_TYPE' "$WF" && ok "手工 push 的 v* tag 仍然触发发布" || no "手工 push 的 v* tag 仍然触发发布"
grep -q 'must be greater\|必须递增\|版本号必须' "$WF" && ok "工作流要求版本号递增（同版本不允许再发）" || no "工作流要求版本号递增（同版本不允许再发）"
if grep -q 'gh release create' "$WF"; then
	ok "工作流真的创建 GitHub Release"
else
	no "工作流真的创建 GitHub Release"
fi
if [ "$(grep -c "gh release create" "$WF")" -eq 1 ] && ! grep -q '   gh release create.*ipk\|.*dist/easyproxy\*' "$WF"; then
	no "Release 附带 IPK 资产" "gh release create 没有带 dist/easyproxy*"
else
	grep -q 'dist/easyproxy\*' "$WF" && ok "Release 附带 IPK 资产" || no "Release 附带 IPK 资产"
fi
grep -q 'dist/SHA256SUMS' "$WF" && ok "Release 附带 SHA256SUMS" || no "Release 附带 SHA256SUMS"
grep -q 'compgen -G .dist/.*\.ipk' "$WF" && ok "发布前断言至少存在一个 ipk" || no "发布前断言至少存在一个 ipk" "$(grep -n 'ipk' "$WF" | head -3)"
grep -q -- '\-\-clobber' "$WF" && no "工作流不再覆盖旧资产（无 --clobber）" || ok "工作流不再覆盖旧资产（无 --clobber）"
grep -q 'gh release edit' "$WF" && no "工作流不改写已发布的说明" || ok "工作流不改写已发布的说明"
grep -q -- '\-\-keep 20' "$WF" && ok "保留最新 20 个版本" || no "保留最新 20 个版本"
grep -q 'release-gc.sh.*--protect' "$WF" && ok "清理时保护正在使用的版本" || no "清理时保护正在使用的版本"

# Report 009: a release must be creatable without a tag push. GITHUB_TOKEN
# pushes never trigger another workflow run, so a tag made inside Actions
# publishes nothing; a manual (workflow_dispatch) run has to be able to do the
# whole job, with the version given explicitly.
grep -q 'GITHUB_EVENT_NAME}" = "workflow_dispatch"' "$WF" && ok "发布步骤支持手动触发（不依赖 tag push 触发）" || no "发布步骤支持手动触发（不依赖 tag push 触发）"
grep -q 'inputs.version' "$WF" && ok "手动发布必须显式给版本号" || no "手动发布必须显式给版本号"
# Report 009: Actions success is not release success. The job re-reads the
# release it just created and downloads it, so a silent failure cannot pass.
grep -q 'gh release view' "$WF" && ok "发布后回查 Release 是否存在" || no "发布后回查 Release 是否存在"
grep -q 'gh release download' "$WF" && ok "发布后把资产下载回来" || no "发布后把资产下载回来"
grep -q 'sha256sum -c' "$WF" && ok "下载的资产用 SHA256SUMS 校验" || no "下载的资产用 SHA256SUMS 校验"
grep -q 'curl -fIL' "$WF" && ok "逐个资产校验下载地址可用" || no "逐个资产校验下载地址可用"
grep -q 'continue-on-error' "$WF" && no "自检不允许 continue-on-error" || ok "自检不允许 continue-on-error"

# update apply reads the version out of the freshly installed tree instead of
# asking the running CLI (which would report the old build). The version lives
# in usr/lib/easyproxy/common.sh only; the CLI used to be read instead, and the
# `sed` expression then matched its own source line inside that file, so every
# upgrade "failed verification" and rolled itself back. Behavioural proof needs
# a router; these two checks pin the shape that made it impossible here.
CLI="$SRC/package/easyproxy/files/usr/sbin/easyproxy"
COMMON="$SRC/package/easyproxy/files/usr/lib/easyproxy/common.sh"
grep -q 'EP_VERSION=' "$COMMON" && ok "版本号定义在 common.sh（唯一真源）" || no "版本号定义在 common.sh（唯一真源）"
grep -q 'easyproxy"/common.sh' "$CLI" && ok "更新校验从 common.sh 读版本号" || no "更新校验从 common.sh 读版本号"
if grep -q 'sed -n .*EP_UPDATE_ROOT/usr/sbin/easyproxy' "$CLI"; then
	no "更新校验不再从 CLI 自身读版本号（会自匹配）"
else
	ok "更新校验不再从 CLI 自身读版本号（会自匹配）"
fi

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
