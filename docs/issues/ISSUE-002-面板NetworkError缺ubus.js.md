# ISSUE-002 面板整页报 NetworkError：app.js 依赖固件已删除的 ubus.js

- 状态：待修复（未改代码）
- 发现时间：2026-11-18
- 发现方式：真机安装后浏览器打开 LuCI 面板
- 严重度：高（面板内容区完全打不开，所有页面都进不去）

## 现象

打开 `http://10.10.10.13/cgi-bin/luci/admin/services/easyproxy`，页面顶部菜单条正常渲染（运行总览 / 节点管理 / 订阅管理 / 智能分流 / 内核管理 / DNS 设置 / 规则管理 / 日志中心 / 备份与恢复 / 系统设置 / 版本更新），但内容区显示：

```
NetworkError

HTTP error 404 while loading class file "/luci-static/resources/ubus.js?v=27.307.53063-b064eba-1794938726"
    at compileClass (http://10.10.10.13/luci-static/resources/ubus.js?v=27.307...)
    at async Promise.all (index 1)
    at async Promise.all (index 0)
```

即：菜单渲染成功，但页面内容类加载失败，整页不可用。

## 取证（真机只读检查）

| 检查项 | 实测结果 |
|---|---|
| `/www/luci-static/resources/ubus.js` | **不存在**（`No such file or directory`） |
| `/www/luci-static/resources/rpc.js` | 存在，4089 字节，`Nov 3 22:46` |
| 资源目录内容 | `cbi` / `cbi.js` / `easyproxy` / `firewall.js` / `form.js` / `fs.js` / `icons` / `luci.js` / `menu-*.js` / `network.js` / `oui` / `protocol` / **`rpc.js`** / `svg` / `tools` / `uci.js` / `ui.js` / `uqr.js` / `validation.js` / `vantage*` / `xhr.js` |
| `luci-base` 版本 | `27.307.53063~b064eba` |
| 我们的前端文件 | `/www/luci-static/resources/easyproxy/app.js`，51034 字节 |
| `app.js` 第 3 行 | **`'require ubus';`** |
| `app.js` 第 78 行 | `ubus.call('easyproxy', 'run', { payload: JSON.stringify(args) })` |
| `rpc.js` 开头 | `'require baseclass';'require request';` … `rpcBaseURL = L.url('admin/ubus')` |

## 根因

LuCI 在较新版本里把前端 ubus 模块从 `ubus.js` 换成了 `rpc.js`（对外仍是 `admin/ubus` 这个 RPC 端点，但模块名变了）。这台固件的 `luci-base 27.307.53063` 属于新版，只发布 `rpc.js`，**不再提供 `ubus.js`**。

我们的 `app.js` 第一行依赖声明是 `'require ubus'`，LuCI 解析依赖时按名字去找 `/luci-static/resources/ubus.js` → 404 → `compileClass` 抛 NetworkError → 整页内容区失败。

菜单条之所以正常，是因为菜单由 `menu.d/*.json` 渲染，不加载 `app.js`。

## 影响面

- 所有使用新版 LuCI（`luci-base` 27.x，如 Kwrt 25.12-SNAPSHOT）的固件，面板内容区全部打不开
- **0.8.11 和 0.8.12 表现完全一样**：`app.js` 这两个版本没有改动，升级版本不会解决这个现象
- 旧固件（带 `ubus.js` 的 LuCI 22.03/23.05）不受影响 —— 这也是这个缺陷在早前验收中没暴露的原因

## 实测闭环（0.8.12 真机复现，2026-11-18）

第一次现象来自 0.8.11（一键安装装到的版本）。为排除"换版本就好"的误判，还原虚拟机后手动安装 0.8.12 复验。

环境还原确认：`uptime` 1 分钟；`/usr/sbin/easyproxy` 不存在；`/etc/config/easyproxy` 不存在；`opkg list-installed` 无 easyproxy；`/usr/share/rpcd/ucode/` 无 easyproxy 插件。

安装 0.8.12：

| 项 | 结果 |
|---|---|
| 下载 | CDN 短链 `https://aka.doubaocdn.com/s/7HLzqVoVk5` → 73141 字节，rc=0 |
| sha256 | `4de10015f675ab2a980d07e6a46f2b45b99a962e184d1b4e315dfc386a7c0a03`，与 Release 记录一致 |
| opkg | `Installing easyproxy (0.8.12-1) to root... / Configuring easyproxy.`，rc=0 |
| 版本 | `easyproxy version` → `0.8.12` |
| rpcd 插件 | `/usr/share/rpcd/ucode/luci.easyproxy.uc` 2239 B |
| ubus 对象 | `ubus list` 含 `easyproxy` |
| 前端 | `/www/luci-static/resources/easyproxy/app.js` 51034 B，md5 `cdb92e4ceb272d8946bfc1e76f3d9b37` |

`app.js` 第 3 行仍为 `'require ubus';`（第 1~4 行：`'use strict';` / `'require fs';` / `'require ubus';` / `'require uci';`）。

真机本机 HTTP 探测（nginx）：

```
GET /luci-static/resources/easyproxy/app.js  →  HTTP/1.1 200 OK
GET /luci-static/resources/ubus.js           →  HTTP/1.1 404 Not Found
```

浏览器实测（0.8.12，用户真机截图）：内容区仍是

```
NetworkError
HTTP error 404 while loading class file "/luci-static/resources/ubus.js?v=27.307.53063-b064eba-1794940043"
    at compileClass (.../luci.js:162:16)
    at async Promise.all (index 1) / (index 0)
```

与 0.8.11 完全一致。**结论：这不是版本问题，是前端依赖与固件 LuCI 版本不匹配，换 0.8.12 无法规避。**

## 排除 Open-Box 干扰（2026-11-18 只读核查）

怀疑过：这台机器预装了 Open-Box，是不是它把 LuCI 的 ubus.js 弄没了。核查结论：**无关**。

| 核查项 | 结果 | 说明 |
|---|---|---|
| `find / -name ubus.js`（排除 /proc /sys） | **无任何结果** | 系统里根本没有这个文件，不是被某个包删除或改名 |
| `luci-base.control` | Version `27.307.53063~b064eba`，Source `feeds/kiddin9/feeds/kiddin9/luci-base` | 固件自带（Kwrt 就是 kiddin9 的 feed） |
| `luci-base.list` / `luci-app-open-box.list` / `rpc.js` 的 mtime | 三者全部是 **Nov 3 22:46** | 同一时刻落盘 = 刷固件镜像时就在，不是后来装 open-box 带进来的 |
| open-box 包信息 | `Installed-Size: 197191680`，Description 写 "Pre-packaged with full sing-box core, embedded Node.js runtime…" | 预装在固件镜像里 |
| open-box 占用的 luci-static 文件 | 只有 `/www/luci-static/resources/view/openbox/main.js`（另有一份在 `/opt/open-box/openwrt/`） | 只写自己的 view，没覆盖 luci-base 的公共资源 |
| open-box 前端依赖声明 | 第 3 行 `'require rpc';` | 它自己早就适配了新版 LuCI |

**反过来的有用发现**：Open-Box 面板在同一台固件上能正常打开，用的就是 `'require rpc'` —— 说明 rpc.js 这条路在这代固件上已被实践证明可用。但旧固件（LuCI 22.03 / 23.05）是否都带 `rpc.js` 仍需逐个核实，因此修复方案仍优先推荐 B（自带 ubus 模块），A 作为备选。

## 修复方案（三选，尚未实施）

- **方案 A：改用 `rpc`** —— `app.js` 改成 `'require rpc';`，调用改成 `rpc.call(...)`。但旧固件是否都有 `rpc.js` 需要逐一核对，兼容性有风险
- **方案 B（推荐）：自带 ubus 模块** —— 把一份 `ubus.js` 打进包（`files/www/luci-static/resources/easyproxy/ubus.js`），`app.js` 改成 `'require easyproxy.ubus'`，完全不依赖固件 LuCI 版本，新旧固件都能跑
- **方案 C：双路探测** —— 运行时判断固件有无 `rpc.js`，有则用 rpc 否则用自带 ubus。实现复杂度最高，收益不如 B

推荐 B 的理由：`rpc.js` 与 `ubus.js` 的差异只在外层封装，我们只用到一个方法（`easyproxy.run`），自带一份实现最可控，也彻底摆脱固件版本差异。

## 关联

- 与 ISSUE-001（一键安装装到旧版本 ipk）**无关**，是独立缺陷
- 这个缺陷解释了为什么早前"面板按钮全部点了没反应"——在部分固件上不是按钮逻辑问题，而是整个前端类加载失败
