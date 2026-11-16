#!/usr/bin/env bash
# 一次性发布脚本：应用已审阅的 0.7.0 补丁、跑测试与构建、创建 v0.7.0 Release。
# 由 .github/workflows/release-0.7.0-once.yml 调用一次，发布后由文档提交删除。
#
# 注意：GITHUB_TOKEN 没有 workflows 权限，机器人提交里不能包含 .github/workflows/
# 下的任何改动，所以 build.yml 的 sing-box pin 由维护者单独推送，本补丁只含其余文件。
set -euo pipefail

echo "[1/9] guard"
cd "${GITHUB_WORKSPACE:-.}"
if grep -q '^PKG_VERSION:=0.7.0$' package/easyproxy/Makefile; then
  echo "0.7.0 already applied, nothing to do"
  exit 0
fi

echo "[2/9] download the reviewed patch"
PATCH_URL="https://aka.doubaocdn.com/s/OqYUm19kOf"
PATCH_SHA=0077eee2309b94f488afa4ac15aca7832b7b1bb7147701c9ea64c077f5072a59
curl -fsSL --retry 3 "$PATCH_URL" -o /tmp/release.patch || { echo "::error title=patch download::cannot download the reviewed patch"; exit 1; }
echo "$PATCH_SHA  /tmp/release.patch" | sha256sum -c - || { echo "::error title=patch checksum::patch is not the reviewed one"; exit 1; }

echo "[3/9] apply the patch and commit"
git apply --check /tmp/release.patch || { echo "::error title=apply::patch does not apply to main"; exit 1; }
git apply /tmp/release.patch
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -q -m "release: EasyProxy 0.7.0 (sing-box 1.14.4, schema 迁移与 pin 一致性测试)" || { echo "::error title=commit::git commit failed"; exit 1; }
echo "local commit $(git rev-parse HEAD)"
git push origin HEAD:main || { echo "::error title=push::git push failed"; exit 1; }
SHA="$(git rev-parse HEAD)"
echo "[3/9] committed $SHA"
git show --stat --oneline HEAD | head -20

echo "[4/9] build dependencies"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  build-essential clang flex bison g++ gawk gcc-multilib gettext git \
  libncurses-dev libssl-dev python3 python3-setuptools rsync unzip \
  zlib1g-dev file wget curl zstd

echo "[5/9] pinned sing-box for the suites"
SB_VER=1.14.4
SB_URL="https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-amd64.tar.gz"
SB_SHA=699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968
curl -fSL "$SB_URL" -o sb.tar.gz || { echo "::error title=sing-box download::cannot download $SB_URL"; exit 1; }
echo "$SB_SHA  sb.tar.gz" | sha256sum -c - || { echo "::error title=sing-box checksum::pinned archive changed"; exit 1; }
tar -xzf sb.tar.gz
mkdir -p /opt/easyproxy-ci
cp "sing-box-${SB_VER}-linux-amd64/sing-box" /opt/easyproxy-ci/sing-box
chmod +x /opt/easyproxy-ci/sing-box
/opt/easyproxy-ci/sing-box version

echo "[6/9] test suites with the real kernel"
EP_SING_BOX_BIN=/opt/easyproxy-ci/sing-box EP_TEST_LOG_DIR=test-logs bash tests/run-all.sh

echo "[7/9] SDK and package build"
SDK_URL="https://downloads.immortalwrt.org/releases/25.12.2/targets/x86/64/immortalwrt-sdk-25.12.2-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
SDK_SHA="4d4631f134c2f27215a91aa7ef5bf9a01ea96c2450d3b8a5c38048c32462ac60"
curl -fL "$SDK_URL" -o sdk.tar.zst || { echo "::error title=SDK download::cannot download the SDK"; exit 1; }
echo "$SDK_SHA  sdk.tar.zst" | sha256sum -c - || { echo "::error title=SDK checksum::SDK changed"; exit 1; }
mkdir sdk
tar --zstd -xf sdk.tar.zst -C sdk --strip-components=1

mkdir -p dist
VER="$(sed -n 's/^PKG_VERSION:=//p' package/easyproxy/Makefile | head -1)"
[ -n "$VER" ] || { echo "::error::cannot read PKG_VERSION"; exit 1; }
[ "$VER" = "0.7.0" ] || { echo "::error::patch did not set PKG_VERSION to 0.7.0"; exit 1; }
echo "PKG_VERSION=$VER"

( cd sdk && mkdir -p package/easyproxy && cp -a ../package/easyproxy/. package/easyproxy/ \
  && make defconfig \
  && make package/easyproxy/compile V=s -j2 ) || { echo "::error title=Package compile::SDK build failed"; exit 1; }

tar --owner=0 --group=0 --numeric-owner \
  -czf "dist/easyproxy-${VER}-rootfs.tar.gz" -C package/easyproxy/files .

bash scripts/make-ipk.sh package/easyproxy dist all || { echo "::error title=ipk all::failed"; exit 1; }
bash scripts/make-ipk.sh package/easyproxy dist x86_64 || { echo "::error title=ipk x86_64::failed"; exit 1; }

for arch in x86_64 aarch64_cortex-a53 arm_cortex-a7_neon-vfpv4; do
  bash scripts/make-kernel-ipk.sh sing-box "$arch" dist || { echo "::error title=sing-box $arch::failed"; exit 1; }
  bash scripts/make-kernel-ipk.sh dae "$arch" dist || { echo "::error title=dae $arch::failed"; exit 1; }
done

find sdk/bin/packages -type f \( -name 'easyproxy*.apk' -o -name 'easyproxy*.ipk' \) -exec cp -v {} dist/ \;
compgen -G 'dist/easyproxy*' > /dev/null || { echo "::error::EasyProxy package not found"; exit 1; }

echo "[8/9] KERNEL-VERSIONS and SHA256SUMS"
( cd dist
  SB_VER_PKG="$(sed -n 's/^SING_BOX_VER=.*:-\\([0-9][0-9.]*\\)}.*/\\1/p' ../scripts/make-kernel-ipk.sh)"
  DAE_VER_PKG="$(sed -n 's/^DAE_VER=.*:-\\([0-9][0-9.]*\\)}.*/\\1/p' ../scripts/make-kernel-ipk.sh)"
  [ -n "$SB_VER_PKG" ] && [ -n "$DAE_VER_PKG" ] || { echo "::error::cannot read the kernel versions"; exit 1; }
  {
    echo "component   version   upstream"
    echo "easyproxy   ${VER}     https://github.com/${GITHUB_REPOSITORY}"
    echo "sing-box    ${SB_VER_PKG}     SagerNet/sing-box v${SB_VER_PKG}"
    echo "dae         ${DAE_VER_PKG}     daeuniverse/dae v${DAE_VER_PKG}"
    echo
    echo "architectures: x86_64, aarch64_cortex-a53, arm_cortex-a7_neon-vfpv4"
    echo "kernel adapter: dae 适配器开发中，运行时分流仍由 sing-box 承担"
    echo "built from commit: ${SHA}"
    echo "built from ref: main (one-shot release run)"
  } > KERNEL-VERSIONS
  cat KERNEL-VERSIONS
  sha256sum easyproxy* sing-box_* dae_* KERNEL-VERSIONS > SHA256SUMS
  cat SHA256SUMS
)

ls -l dist/
compgen -G "dist/*.ipk" > /dev/null || { echo "::error title=no ipk::no ipk package"; exit 1; }
[ -f dist/SHA256SUMS ] || { echo "::error title=no checksums::SHA256SUMS missing"; exit 1; }
for ipk in dist/*.ipk; do
  base="$(basename "$ipk")"
  grep -q "$base" dist/SHA256SUMS || { echo "::error title=checksum gap::SHA256SUMS does not cover $base"; exit 1; }
done

echo "[9/9] publish the release"
TAG="v${VER}"
if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "::error title=version already released::release $TAG already exists"; exit 1
fi
PREV="$(gh release list --repo "$GITHUB_REPOSITORY" --limit 1 --json tagName --jq '.[0].tagName // empty' 2>/dev/null || true)"
PREV="${PREV#v}"
if [ -n "$PREV" ]; then
  HIGHEST="$(printf '%s\n%s\n' "$PREV" "$VER" | sort -V | tail -n 1)"
  if [ "$VER" = "$PREV" ] || [ "$HIGHEST" != "$VER" ]; then
    echo "::error title=version not newer::PKG_VERSION $VER must be greater than $PREV"; exit 1
  fi
  echo "version $PREV -> $VER"
fi

NOTES="$(mktemp)"
cat > "$NOTES" <<'NOTES_EOF'
## EasyProxy 0.7.0

修复了什么问题

- 升级内核后生成的配置无法被 sing-box 1.14 接受：官方在 1.14.0 移除了旧版 DNS 服务器写法（legacy DNS server formats），本版把 `dns.servers` 改写为 `type`/`server`/`server_port`/`path`/`detour` 的新格式，并按官方迁移说明补上 `route.default_domain_resolver`。
- 透明代理入站报 `legacy inbound fields`：1.13.0 起移除了 tproxy 入站的 `sniff`、`sniff_override_destination`、`udp_timeout`，本版删除这些字段，改用 `route.rules` 里的 `sniff` 动作对 `tproxy-in` 入站做嗅探。
- 真实起服时 `dns-local` 报 `detour to an empty direct outbound makes no sense`：直连的 DNS 服务器不再写 `detour: "direct"`，只有确实要走代理时才写 `detour`。
- 打包脚本、CI、安装器与测试里残留的 sing-box 1.10.7 版本号和旧 SHA256 会互相打架，本版统一到 1.14.4 的新下载地址与新校验值。

修改了什么功能

- sing-box 内核从 1.10.7 升级到 1.14.4（SagerNet/sing-box 最新正式稳定版，Release v1.14.4，发布于 2026-10-24），三架构归档按官方 Release 逐个下载后本地算出的 SHA256 固定进安装器与打包脚本：amd64 `699a1b51…c24968`、arm64 `436441f7…273ec26`、armv7 `fd164ed4…b80a00`。
- EasyProxy 版本从 0.6.0 升级到 0.7.0，新版本号与 `v0.7.0` 标签都是首次使用，`v0.6.0` 的资产与标签保持原样不动。
- dae 内核重新核实官方 Release：最新正式版仍是 2.1.2（发布于 2026-11-13），因此保持不动；dae 适配器仍在开发中，运行时分流仍由 sing-box 承担，KERNEL-VERSIONS 里照实标注。

优化了什么内容

- 回归测试新增两条防漂移断言：工作流、打包脚本、安装器三处的 sing-box 版本必须一致，amd64 的 SHA256 必须一致，任何一处忘改都会让构建失败。
- 透明代理测试改为断言 tproxy 监听地址、`sniff` 是挂在 `tproxy-in` 上的路由动作，并且入站不再出现 1.13 已删除的三个旧字段，覆盖升级后的真实配置形态。
- 发布资产新增三架构 sing-box/dae 内核包、`KERNEL-VERSIONS` 与 `SHA256SUMS`，可以逐个下载后按官方口径复核校验值。
NOTES_EOF
[ -s "$NOTES" ] || { echo "::error title=empty notes::release notes are empty"; exit 1; }
for h in "修复了什么问题" "修改了什么功能" "优化了什么内容"; do
  grep -q "$h" "$NOTES" || { echo "::error title=notes section missing::$h"; exit 1; }
  grep -A2 "$h" "$NOTES" | grep -q '^- ' || { echo "::error title=notes section empty::$h"; exit 1; }
done

gh release create "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --target "$SHA" \
  --title "EasyProxy ${VER}" \
  --notes-file "$NOTES" \
  dist/easyproxy* dist/sing-box_* dist/dae_* dist/SHA256SUMS dist/KERNEL-VERSIONS || { echo "::error title=release::gh release create failed"; exit 1; }
echo "created release $TAG from $SHA"
cat "$NOTES"
