#!/bin/sh
# EasyProxy 唯一 SSH 入口：一个地址、九个菜单。
#
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy-manager.sh | sh
#
# 兼容范围（真机目标：ImmortalWrt / OpenWrt 18.06 ~ 25.x）：
#   * 只用 POSIX sh 语法，busybox ash 与 dash 都能跑（不用 [[ ]]、数组、pipefail）
#   * 包管理器两种都认：opkg（24.x 及更早）与 apk（25.x 起），按存在性探测
#   * 下载两种都认：wget（busybox 版 -O -）与 curl（-fsSL），失败自动换另一个
#   * 不依赖 bash、不依赖 /usr/bin/env bash、不依赖 GNU coreutils 扩展参数
#   * 脚本本身不写配置、不改包、不删东西：所有动作都转给仓库里已有的
#     install.sh / uninstall.sh / easyproxy CLI，避免第二套逻辑分叉
#
# 退出码：0 成功；1 动作失败；2 用法错误；3 环境不支持（既无 wget 也无 curl）

set -u

REPO_RAW="${EP_REPO_RAW:-https://raw.githubusercontent.com/bnm188/EasyProxy/main}"
TMP="${EP_TMP_DIR:-/tmp}"

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

usage() {
	cat <<'USAGE'
EasyProxy 管理入口

用法：
  sh easyproxy-manager.sh            进入菜单
  sh easyproxy-manager.sh <动作>     直接执行某一项（便于脚本化）

动作：
  install      安装（面板 + sing-box + dae）
  upgrade      升级三件套（内核坏了自动回滚）
  uninstall    卸载（默认保留配置）
  status       状态
  doctor       诊断（11 项自检）
  kernel       内核管理（版本、切换、重装）
  backup       配置备份 / 恢复 / 重置
  rulesets     规则集更新 / 校验
  panel        面板入口说明
  rescue       紧急恢复直连（删除 nft 接管，回到纯直连）
  help         本帮助
USAGE
}

# ---- 环境探测 -------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

pkg_manager() {
	if have apk; then
		printf 'apk'
	elif have opkg; then
		printf 'opkg'
	else
		printf 'none'
	fi
}

fetch() {
	# fetch <url> <输出文件>
	_url="$1"; _out="$2"
	if have wget; then
		wget -q -O "$_out" "$_url" 2>/dev/null && return 0
	fi
	if have curl; then
		curl -fsSL "$_url" -o "$_out" 2>/dev/null && return 0
	fi
	return 1
}

need_net() {
	if ! have wget && ! have curl; then
		err "既没有 wget 也没有 curl，无法下载。请先 opkg install wget-ssl 或 apk add wget"
		exit 3
	fi
}

show_env() {
	_pm="$(pkg_manager)"
	say "包管理器：${_pm}"
	if [ "$_pm" = "none" ]; then
		say "警告：既没有 opkg 也没有 apk，安装/升级不可用（可用 rootfs 方式手工展开）"
	fi
	if [ -r /etc/openwrt_release ]; then
		. /etc/openwrt_release 2>/dev/null || true
		say "固件：${DISTRIB_ID:-unknown} ${DISTRIB_RELEASE:-unknown} (${DISTRIB_ARCH:-unknown})"
	fi
	say "下载器：$(have wget && printf wget)$(have wget && have curl && printf ' + ')$(have curl && printf curl)"
}

# ---- 动作（全部转给仓库已有脚本，不复制逻辑）------------------------------

run_remote() {
	# run_remote <脚本名> [参数...]
	_name="$1"; shift
	need_net
	_f="$TMP/easyproxy-${_name}.$$"
	if ! fetch "$REPO_RAW/scripts/${_name}" "$_f"; then
		err "下载 ${_name} 失败（检查网络或 EP_REPO_RAW）"
		return 1
	fi
	# 下载下来的必须是脚本而不是错误页：至少含 shebang 且非空
	if [ ! -s "$_f" ] || ! head -n 1 "$_f" | grep -q '#!'; then
		err "下载到的 ${_name} 不是有效脚本（可能是网络拦截页）"
		rm -f "$_f"
		return 1
	fi
	sh "$_f" "$@"
	_rc=$?
	rm -f "$_f"
	return $_rc
}

act_install()   { run_remote install.sh; }
act_upgrade()   { run_remote install.sh upgrade; }
act_uninstall() { run_remote uninstall.sh; }
act_status()    { run_remote install.sh status; }

act_doctor() {
	# 诊断优先用本机已装的 CLI；没装就说明没装，不假装跑过
	if [ -x /usr/sbin/easyproxy ]; then
		/usr/sbin/easyproxy doctor
	else
		err "未安装 EasyProxy（找不到 /usr/sbin/easyproxy），先选 install"
		return 1
	fi
}

act_kernel() {
	if [ -x /usr/sbin/easyproxy ]; then
		/usr/sbin/easyproxy engine
		/usr/sbin/easyproxy engine list
		/usr/sbin/easyproxy engine health
		/usr/sbin/easyproxy engine version
	else
		err "未安装 EasyProxy，先选 install"
		return 1
	fi
}

act_backup() {
	if [ -x /usr/sbin/easyproxy ]; then
		say "备份：easyproxy config backup [文件]"
		/usr/sbin/easyproxy config backup
		say ""
		say "恢复：easyproxy config restore <备份文件>"
		say "重置：easyproxy config reset"
	else
		err "未安装 EasyProxy，先选 install"
		return 1
	fi
}

act_rulesets() {
	if [ -x /usr/sbin/easyproxy ]; then
		/usr/sbin/easyproxy ruleset update
	else
		err "未安装 EasyProxy，先选 install"
		return 1
	fi
}

act_rescue() {
	if [ -x /usr/sbin/easyproxy ]; then
		say "即将删除 nft 接管规则并切回纯直连。"
		printf '确认继续？[y/N]: '
		read -r _yn || _yn=""
		case "$_yn" in
			y|Y|yes|YES) /usr/sbin/easyproxy bypass restore ;;
			*) say "已取消。" ;;
		esac
	else
		# 未安装也允许救机：直接清掉可能残留的 nft 表
		if have nft; then
			nft delete table ip easyproxy 2>/dev/null || :
			nft delete table ip6 easyproxy 2>/dev/null || :
			say "已删除残留的 nft 接管规则。"
		else
			err "nft 不可用，无法清理"
			return 1
		fi
	fi
}

act_panel() {
	say "面板入口：LuCI → 服务 → EasyProxy（登录 http://<路由器IP>/cgi-bin/luci）"
	say "若面板未出现：/etc/init.d/rpcd restart && /etc/init.d/uhttpd restart"
}

dispatch() {
	case "$1" in
		install)   act_install ;;
		upgrade)   act_upgrade ;;
		uninstall) act_uninstall ;;
		status)    act_status ;;
		doctor)    act_doctor ;;
		kernel)    act_kernel ;;
		backup)    act_backup ;;
		rulesets)  act_rulesets ;;
		panel)     act_panel ;;
		rescue)    act_rescue ;;
		help|-h|--help) usage ;;
		*) err "未知动作：$1"; usage; exit 2 ;;
	esac
}

# ---- 菜单 -----------------------------------------------------------------

menu() {
	show_env
	say ""
	say "  EasyProxy 管理菜单"
	say "  --------------------------------------------------"
	say "  1) 安装（面板 + sing-box + dae）"
	say "  2) 升级（内核坏了自动回滚）"
	say "  3) 卸载"
	say "  4) 状态"
	say "  5) 诊断（doctor）"
	say "  6) 内核管理"
	say "  7) 配置备份 / 恢复"
	say "  8) 规则集更新"
	say "  9) 面板入口"
	say " 10) 紧急恢复直连（上不了网时用）"
	say "  0) 退出"
	say "  --------------------------------------------------"
	printf '选择: '
	read -r _ans || exit 0
	case "$_ans" in
		1) dispatch install ;;
		2) dispatch upgrade ;;
		3) dispatch uninstall ;;
		4) dispatch status ;;
		5) dispatch doctor ;;
		6) dispatch kernel ;;
		7) dispatch backup ;;
		8) dispatch rulesets ;;
		9) dispatch panel ;;
		10) dispatch rescue ;;
		0|"") exit 0 ;;
		*) err "无效选项：$_ans"; exit 2 ;;
	esac
}

if [ $# -gt 0 ]; then
	dispatch "$1"
	_rc=$?
	exit $_rc
fi

# 交互菜单只在终端里给；通过 wget | sh 管道进来时 stdin 是管道，
# 直接打印动作清单，避免"菜单读不到输入就静默退出"。
if [ -t 0 ]; then
	menu
else
	usage
	say ""
	say "非交互调用：sh easyproxy-manager.sh <动作>"
fi
