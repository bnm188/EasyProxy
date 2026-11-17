# ISSUE-002 修复方案 B：自带 ubus 模块

- 对应缺陷：ISSUE-002（面板整页 NetworkError，`'require ubus'` 404）
- 状态：**方案待用户确认，未改任何代码**
- 编写时间：2026-11-18

## 一、方案要点

前端不再引用固件提供的 `ubus` 模块，改为引用随包一起发布的 `easyproxy.ubus`。该模块自包含，行为与原 `ubus.call` 一致，因此 11 个 view 和 app.js 的 993 行其余逻辑**一行都不用改**。

共 3 处改动：

| # | 文件 | 改动 |
|---|---|---|
| 1 | `package/easyproxy/files/www/luci-static/resources/easyproxy/ubus.js` | **新增**，约 40 行，自包含 RPC 客户端 |
| 2 | `package/easyproxy/files/www/luci-static/resources/easyproxy/app.js` | 第 3 行 `'require ubus';` → `'require easyproxy.ubus as ubus';`（全文件仅此一行） |
| 3 | `package/easyproxy/Makefile` | `Package/easyproxy/install` 段加一行 `$(INSTALL_DATA) ./files/www/luci-static/resources/easyproxy/ubus.js $(1)/www/luci-static/resources/easyproxy/ubus.js` |

不改动：11 个 view 文件、`luci.easyproxy.uc`、ACL、菜单 json、CLI。

## 二、模块设计草案

```js
'use strict';
'require baseclass';
'require request';

// 随包发布的 ubus 客户端。新版 LuCI（27.x）不再发布
// /luci-static/resources/ubus.js（改用 rpc.js），而固件版本无法预知，
// 因此这一层由 EasyProxy 自带，行为与原 ubus.call 保持一致。

var seq = 0;

return baseclass.extend({
	call: function(object, method, params) {
		var sid = (L.env && L.env.sessionid) || '00000000000000000000000000000000';
		var body = {
			jsonrpc: '2.0',
			id: ++seq,
			method: 'call',
			params: [ sid, object, method, params || {} ]
		};
		return request.post(L.url('admin/ubus'), body, { timeout: 60, credentials: true }).then(function(res) {
			if (!res.ok)
				throw new Error('RPC call to ' + object + '/' + method + ' failed with HTTP error ' + res.status);
			return res.json();
		}).then(function(msg) {
			if (!msg || !msg.result)
				throw new Error('RPC call to ' + object + '/' + method + ' returned no result');
			if (msg.result[0] !== 0)
				throw new Error('ubus error ' + msg.result[0] + ' from ' + object + '.' + method);
			return msg.result[1];
		});
	}
});
```

设计依据（逐条来自真机/仓库取证）：

- **必须 `return baseclass.extend({...})`**。LuCI 的 `compileClass` 里有 `if (!Class.isSubclass(_class)) raise('TypeError', 'factory yields invalid constructor')`，返回普通对象会被判非法。
- **必须解包 `msg.result[1]`**。后端 `luci.easyproxy.uc` 的 `run.call` 直接 `return { code, stdout, stderr }`，而 ubus 会把返回值包进 `result[1]`；不解包则 app.js 第 79 行 `r.code` 恒为 undefined，所有请求都会落到 `viaExec()` 兜底。
- **URL 走 `L.url('admin/ubus')`**，不硬编码 `/cgi-bin/luci/admin/ubus`（不同固件前缀不同）。
- **不用 `String.prototype.format`**，改字符串拼接，避免依赖 luci.js 给 String 加的原型方法。
- **不拷贝固件里的 `rpc.js`**：那是 LuCI 的 Apache-2.0 代码，与本仓库 MIT 许可不一致，自写这一层更干净。

## 三、已核实、不构成风险的点

| 点 | 结论 | 依据 |
|---|---|---|
| view 的 `'require X as Y'` 语法在 LuCI 27 是否支持 | **支持** | `luci.js` 里解析正则为 `/^require[ \t]+(\S+)(?:[ \t]+as[ \t]+([a-zA-Z_]\S*))?$/` |
| `easyproxy.ubus` 的解析路径 | 正确落到 `/luci-static/resources/easyproxy/ubus.js` | `luci.js`：`url='%s/%s.js'.format(env.base_url, name.replace(/\./g,'/'))` |
| `baseclass` 在新固件是否存在 | **存在，是 luci.js 内置映射**（`baseclass:Class`），无独立文件 | 真机 `resources/` 无 baseclass.js，但 404 只报 ubus，说明 baseclass 走的是内置类 |
| `request` 依赖 | 新固件由 luci.js 内置（rpc.js 就靠它且能正常工作），旧固件有 request.js 文件 | 真机 rpc.js 首行即 `'require request'`，Open-Box 面板正常 |
| ACL 是否允许 `easyproxy.run` | 已允许 | `acl.d/luci-app-easyproxy.json` 的 `write.ubus` 含 `"easyproxy": ["run"]` |
| 11 个 view 是否需要改 | 不需要，它们 `'require easyproxy.app as app'`，app.js 内部自理 | 仓库 grep：11 个文件统一写法 |
| 现有测试会不会因这行被改而红 | 不会 | `tests/test-security.sh` 断言的是 `grep -q "ubus.call('easyproxy', 'run'"`，调用形式保留 |

## 四、必须处理 / 必须验证的问题

| # | 问题 | 严重度 | 处理 |
|---|---|---|---|
| P1 | **Makefile 是逐文件列举打包**，不是递归拷目录。新文件不加 `INSTALL_DATA` 行就不会进 ipk，装完仍 404 | 高 | 改动 3 必须同时做，并解包 `data.tar.gz` 核对 |
| P2 | 模块工厂必须返回 Class 子类，否则 TypeError | 高 | 用 `baseclass.extend` |
| P3 | 返回值必须解包 `result[1]`，否则所有按钮静默落到 `viaExec` | 高 | 见草案 |
| P4 | **`viaExec` 兜底在新固件并不可靠**：注释里写明 24.10+ 的 `rpcd-mod-file` 只导出 read/write/list/lstat，没有 exec。ubus 一旦失败就无路可走 | 高 | 必须让 ubus 一次走通，且测试时专门验证"ubus 路径成功"而非"界面不报错" |
| P5 | `request` 若在某些第三方固件里不存在，自带模块会二次 404 | 中 | 备选：改为原生 `fetch` 零依赖版；实施方案时二选一并在真机验证 |
| P6 | 浏览器静态缓存：升级后可能仍加载旧 `app.js`（表现为"修了但没效果"） | 中 | 测试必须 Ctrl+F5；发布说明里写明强刷 |
| P7 | 版本号需递增（0.8.13），否则 opkg 判定无更新、`resource_version` 不变 | 中 | 改 `Makefile PKG_VERSION` 与 `common.sh EP_VERSION` |
| P8 | 没有旧 LuCI（22.03/23.05）真机可验，旧固件回归只能靠"自带模块不依赖 rpc.js"来保证 | 中 | 代码层面已解耦；如需实证要另找一台旧固件机器 |
| P9 | ipk 布局测试目前只 `want_file` 了 app.js 等，没有 ubus.js，打包遗漏测不出来 | 中 | `tests/test-ipk-layout.sh` 加 `want_file www/luci-static/resources/easyproxy/ubus.js` |
| P10 | `app.js` 有 `node --check` 断言，新 ubus.js 没有 | 低 | 在 test-bypass 里同步加 `node --check` |
| P11 | payload 走 ubus 有消息体上限，节点数量很大时可能截断（既有风险，非新引入） | 低 | 批量导入节点时观察，不阻塞本次修复 |

## 五、验证计划（确认后执行）

1. 静态：`node --check` 两个 JS 文件
2. 打包：`sh scripts/make-ipk.sh package/easyproxy dist x86_64`，解 ipk 确认 `ubus.js` 存在
3. 测试：`sh tests/run-all.sh`，全套不得回归（当前基线 869 通过 0 失败）
4. 真机（10.10.10.13，Kwrt 25.12 / LuCI 27.307）：
   - 装新包 → 强刷面板 → 内容区应正常渲染（不再 NetworkError）
   - 逐个打开 11 个页面
   - 点一个真实按钮（如"运行状态"刷新），确认走的是 ubus 路径而不是 viaExec
   - 重启后配置仍在
5. 旧固件（若有机器）：同 4

## 六、不做的事

- 不删 ISSUE-001 的 install.sh 修复（两者独立）
- 不顺手改 11 个 view 的写法
- 不动后端 ucode / ACL
- 不在此轮发版，只出一个可安装的验证包
