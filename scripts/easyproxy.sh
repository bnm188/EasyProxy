#!/bin/sh
# EasyProxy 统一入口：安装 / 升级 / 状态 / 检查系统环境 / 卸载
#
# 在路由器 SSH 里一条命令就能用：
#   wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh
#
# 也可以带参数直接执行某一项，适合脚本里调用：
#   sh easyproxy.sh install     安装（面板 + sing-box + dae）
#   sh easyproxy.sh upgrade     三组件升级
#   sh easyproxy.sh status      看装了哪些组件、版本多少
#   sh easyproxy.sh check       检查系统环境（不改任何东西，只读）
#   sh easyproxy.sh uninstall   卸载（默认保留配置并先备份）
#
# 这个入口本身不写任何系统状态：安装和卸载交给 install.sh / uninstall.sh，
# 检查和状态是纯读操作。内核版本、分流策略、UCI 字段一律不在这一层改动。

set -eu

REPO="${EP_REPO:-bnm188/EasyProxy}"
BRANCH="${EP_BRANCH:-main}"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/scripts"

say()  { printf '%s\n' "$*"; }
die()  { printf '错误：%s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
ok()   { say "  [通过] $*"; }
warn() { say "  [注意] $*"; }
bad()  { say "  [失败] $*"; }

need_root() {
	[ "$(id -u 2>/dev/null || echo 0)" = "0" ] || die "请用 root 执行（路由器上一般就是 root）"
}

need_wget() {
	have wget || die "缺少 wget。先装：opkg install wget（apk 固件用 apk add wget）"
}

fetch() {
	# fetch <文件名> <本地路径>
	need_wget
	wget -qO "$2" "${BASE}/$1" || die "下载 $1 失败：检查这台路由器能否访问 raw.githubusercontent.com"
	[ -s "$2" ] || die "下载 $1 得到空文件"
}

run_sub() {
	# run_sub <脚本名> [参数...]
	script="$1"; shift
	tmp="$(mktemp 2>/dev/null || echo /tmp/ep-entry.$$)"
	fetch "$script" "$tmp"
	sh "$tmp" "$@"
	code=$?
	rm -f "$tmp"
	return $code
}

check_env() {
	say "=== EasyProxy 系统环境检查（只读，不改任何东西）==="
	fail=0

	# 1. 固件
	if [ -f /etc/openwrt_release ]; then
		rel="$(sed -n "s/^DISTRIB_ID=.*'\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null || true)"
		relr="$(sed -n "s/^DISTRIB_RELEASE=.*'\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null || true)"
		ver="$(sed -n "s/^VERSION_ID=.*'\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null || true)"
		say "固件：${rel:-未知} ${relr:-}${ver:+ / VERSION_ID=$ver}"
		case "$rel" in
			ImmortalWrt|OpenWrt|Kwrt) ok "在受支持列表内（ImmortalWrt / OpenWrt / Kwrt）" ;;
			"") warn "读不到 DISTRIB_ID，无法判断固件类型，仍可试装" ;;
			*) warn "固件 $rel 不在已知列表内，仍可试装，但出问题不保证能修" ;;
		esac
	else
		bad "/etc/openwrt_release 不存在：这不是 OpenWrt 系固件，装不了"
		fail=1
	fi

	# 2. 包管理器
	if have opkg; then
		ok "包管理器：opkg"
	elif have apk; then
		ok "包管理器：apk"
	else
		bad "既没有 opkg 也没有 apk：需要加 --rootfs 走归档安装，或换固件"
		fail=1
	fi

	# 3. 架构
	m="$(uname -m 2>/dev/null || echo unknown)"
	case "$m" in
		x86_64|amd64)  a=x86_64; s=ok ;;
		aarch64|arm64) a=aarch64_cortex-a53; s=ok ;;
		armv7*|armv7l) a=arm_cortex-a7_neon-vfpv4; s=ok ;;
		*)             a=""; s=warn ;;
	esac
	if [ "$s" = ok ]; then
		ok "架构：$m → 发布包 $a"
	else
		warn "架构：$m 没有现成内核包，只能装根文件（面板可用，内核需自备）"
	fi

	# 4. 必要命令
	for c in sha256sum tar nft wget; do
		if have "$c"; then ok "命令 $c 可用"; else bad "缺少命令 $c（安装器要用它）"; fail=1; fi
	done

	# 5. nftables 能否真正建表（透明代理的前提）
	if have nft && nft list tables >/dev/null 2>&1; then
		ok "nftables 可操作（透明代理与入口旁路的前提）"
	else
		warn "nftables 不可操作：透明代理与入口旁路会失效，安装仍可完成"
	fi

	# 6. 磁盘空间
	free_kb="$(df -k / 2>/dev/null | awk 'NR==2{print $4}')"
	if [ -n "${free_kb:-}" ] && [ "$free_kb" -gt 0 ] 2>/dev/null; then
		free_mb=$((free_kb / 1024))
		if [ "$free_mb" -ge 60 ]; then
			ok "根分区可用 ${free_mb} MB（三件套约需 60 MB）"
		else
			warn "根分区只剩 ${free_mb} MB，可能装不下三个组件"
		fi
	fi

	# 7. 已装情况
	if [ -x /usr/sbin/easyproxy ]; then
		ok "已装 EasyProxy：$(/usr/sbin/easyproxy version 2>/dev/null | head -1 || echo 版本未知)"
	else
		say "  [信息] 尚未安装 EasyProxy"
	fi

	say ""
	if [ "$fail" = 0 ]; then
		say "结论：可以安装。直接复制下面这一行执行："
		say ""
		say "  wget -qO- https://raw.githubusercontent.com/${REPO}/${BRANCH}/scripts/easyproxy.sh | sh -s install"
	else
		say "结论：存在阻塞项，先按上面 [失败] 的提示处理，再执行安装。"
	fi
	return 0
}

usage() {
	cat <<'EOF'
EasyProxy 统一入口

用法：
  sh easyproxy.sh              交互菜单
  sh easyproxy.sh install      安装（面板 + sing-box + dae）
  sh easyproxy.sh upgrade      三组件升级
  sh easyproxy.sh status       已装组件与版本
  sh easyproxy.sh check        检查系统环境（只读）
  sh easyproxy.sh uninstall    卸载（保留配置并先备份；加 --purge 连配置删）
  sh easyproxy.sh diag         采集诊断包（脱敏）；加 --upload 传到 GitHub

一条命令（不下载到本地）：
  wget -qO- https://raw.githubusercontent.com/bnm188/EasyProxy/main/scripts/easyproxy.sh | sh
EOF
}

prompt_choice() {
	# 管道执行时 stdin 已到 EOF，此时从 /dev/tty 读；连 tty 都没有就不假装能交互。
	if [ -t 0 ]; then
		read -r choice || choice=""
		return 0
	fi
	if ( : </dev/tty ) 2>/dev/null; then
		read -r choice </dev/tty || choice=""
		return 0
	fi
	return 1
}

# Support bundle: collect locally, upload only when asked. The installed CLI
# does the masking; this wrapper only finds it and forwards the flag.
diagnose() {
	local bin=""
	for p in /usr/sbin/easyproxy /usr/bin/easyproxy; do
		[ -x "$p" ] && { bin="$p"; break; }
	done
	if [ -z "$bin" ]; then
		say "EasyProxy 尚未安装，没有可采集的状态。先执行安装："
		say "  sh easyproxy.sh install"
		return 1
	fi
	exec "$bin" diag "$@"
}

menu() {
	cat <<'EOF'

  EasyProxy 一键入口
  ─────────────────────────────
  1) 安装       面板 + sing-box + dae
  2) 升级       三组件各自升级
  3) 状态       已装组件与版本
  4) 检查环境   只读诊断，不改系统
  5) 卸载       保留配置并先备份
  6) 诊断上报   采集日志与状态（可选上传 GitHub）
  0) 退出

EOF
	printf '请选择 [0-6]: '
	if ! prompt_choice; then
		printf '\n检测到非交互环境（管道执行）。请带参数直接执行，例如：\n'
		printf '  wget -qO- https://raw.githubusercontent.com/%s/%s/scripts/easyproxy.sh | sh -s install\n' "$REPO" "$BRANCH"
		return 1
	fi
	case "$choice" in
		1) need_root; run_sub install.sh install ;;
		2) need_root; run_sub install.sh upgrade ;;
		3) run_sub install.sh status ;;
		4) check_env ;;
		5) need_root; run_sub uninstall.sh ;;
		6) need_root; diagnose ;;
		0|"") say "已退出"; ;;
		*) say "无效选项：$choice"; ;;
	esac
}

main() {
	case "${1:-}" in
		# shift first: `install --rootfs` must reach install.sh, otherwise a
		# firmware without a usable package manager has no way in through this
		# entry. The same applies to upgrade and its own switches.
		install)   need_root; shift; run_sub install.sh install "$@" ;;
		upgrade)   need_root; shift; run_sub install.sh upgrade "$@" ;;
		status)    run_sub install.sh status ;;
		check)     check_env ;;
		uninstall) need_root; shift; run_sub uninstall.sh "$@" ;;
		diag)      need_root; shift; diagnose "$@" ;;
		-h|--help|help) usage ;;
		"")        menu ;;
		*)         usage; exit 2 ;;
	esac
}

main "$@"
