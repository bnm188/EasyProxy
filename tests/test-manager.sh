#!/bin/sh
# tests/test-manager.sh — 唯一 SSH 入口 scripts/easyproxy-manager.sh
#
# 守的是"能不能在任意 OpenWrt 上跑起来"，不是"菜单好不好看"：
#   * 只用 POSIX sh，dash 与 busybox ash 都能解析；
#   * opkg（24.x 及更早）与 apk（25.x 起）两条分支都在；
#   * wget 与 curl 两种下载器都在，缺一个还有另一个；
#   * 管道进来（wget | sh）不能卡在 read 上，必须走非交互分支；
#   * 九项动作齐全，未知动作返回 2，且不许出现 CLI 里不存在的动词。
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
M="$SRC/scripts/easyproxy-manager.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
say() { printf '%s\n' "$*"; }

say ""
say "== 唯一入口脚本存在且可执行 =="
if [ -f "$M" ]; then ok "scripts/easyproxy-manager.sh 存在"; else no "scripts/easyproxy-manager.sh 存在" "文件不存在"; fi
if [ -x "$M" ]; then ok "可执行位已设置"; else no "可执行位已设置" "$(ls -l "$M" 2>/dev/null)"; fi

say ""
say "== POSIX sh 兼容（不同 OpenWrt 版本的 shell） =="
if sh -n "$M" >/dev/null 2>&1; then ok "sh -n 解析通过"; else no "sh -n 解析通过"; fi
if command -v dash >/dev/null 2>&1; then
	if dash -n "$M" >/dev/null 2>&1; then ok "dash -n 解析通过"; else no "dash -n 解析通过"; fi
else
	say "  SKIP  dash 不存在，未做 dash 解析"
fi
grep -q '^#! */bin/sh' "$M" && ok "shebang 是 /bin/sh（不是 bash）" || no "shebang 是 /bin/sh（不是 bash）"
if grep -v '^[[:space:]]*#' "$M" | grep -q '\[\['; then no "没有 bash 专有的 [[ ]]"; else ok "没有 bash 专有的 [[ ]]"; fi
if grep -v '^[[:space:]]*#' "$M" | grep -q 'pipefail'; then no "没有 bash 专有的 set -o pipefail"; else ok "没有 bash 专有的 set -o pipefail"; fi

say ""
say "== 包管理器：opkg 与 apk 都要认 =="
grep -q 'have apk' "$M" && ok "探测 apk（25.x 起）" || no "探测 apk（25.x 起）"
grep -q 'have opkg' "$M" && ok "探测 opkg（24.x 及更早）" || no "探测 opkg（24.x 及更早）"
grep -q 'pkg_manager()' "$M" && ok "包管理器只探测不假设" || no "包管理器只探测不假设"

say ""
say "== 下载器：wget 与 curl 双保险 =="
grep -q 'wget -q -O' "$M" && ok "优先用 busybox wget" || no "优先用 busybox wget"
grep -q 'curl -fsSL' "$M" && ok "wget 不行时回落 curl" || no "wget 不行时回落 curl"
grep -q 'exit 3' "$M" && ok "两个下载器都没有时明确退出 3" || no "两个下载器都没有时明确退出 3"

say ""
say "== 管道调用（wget | sh）不能卡在 read =="
grep -q '\[ -t 0 \]' "$M" && ok "按 stdin 是否为终端分流" || no "按 stdin 是否为终端分流"
OUT="$(sh "$M" help 2>&1)"
printf '%s' "$OUT" | grep -q '用法' && ok "非交互执行打印用法而不是等输入" || no "非交互执行打印用法" "$OUT"

say ""
say "== 九项动作齐全 =="
for a in install upgrade uninstall status doctor kernel backup rulesets panel; do
	grep -qE "^[[:space:]]*$a)" "$M" && ok "动作 $a 已注册" || no "动作 $a 已注册"
done
sh "$M" nosuchaction >/dev/null 2>&1
[ $? -eq 2 ] && ok "未知动作返回 2" || no "未知动作返回 2"

say ""
say "== 只调用 CLI 真实存在的动词（不许臆造） =="
if grep -q 'easyproxy kernel status' "$M"; then no "没有臆造的 easyproxy kernel status"; else ok "没有臆造的 easyproxy kernel status"; fi
if grep -q 'easyproxy backup create' "$M"; then no "没有臆造的 easyproxy backup create"; else ok "没有臆造的 easyproxy backup create"; fi
grep -q 'engine health' "$M" && ok "内核管理走 engine health" || no "内核管理走 engine health"
grep -q 'config backup' "$M" && ok "备份走 config backup" || no "备份走 config backup"
grep -q 'ruleset update' "$M" && ok "规则集走 ruleset update" || no "规则集走 ruleset update"

say ""
say "结果：$PASS 通过，$FAIL 失败"
[ "$FAIL" -eq 0 ]
