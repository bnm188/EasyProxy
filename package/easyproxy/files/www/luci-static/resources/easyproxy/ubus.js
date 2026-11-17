'use strict';
'require baseclass';
'require request';

// EasyProxy 自带的 ubus 客户端。
//
// 新版 LuCI（27.x，例如 Kwrt 25.12）不再发布 /luci-static/resources/ubus.js，
// 改用 rpc.js，于是面板里的 'require ubus' 直接 404，整页报 NetworkError。
// 这一层因此由包自己提供，对外行为与原 ubus.call 保持一致：
// 发一条 jsonrpc call，校验 result[0] 的错误码，返回 result[1]（方法返回值）。

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
