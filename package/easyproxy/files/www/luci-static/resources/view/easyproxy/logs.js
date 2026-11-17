'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

return view.extend({
	load: function () {
		return fs.exec('/usr/sbin/easyproxy', ['log']).then(function (r) {
			return (r.stdout || r.stderr || '').trim() || '暂无日志';
		}).catch(function (e) {
			return '读取日志失败：' + e;
		});
	},
	render: function (log) {
		return app.pageLogs({ log: log });
	}
});
