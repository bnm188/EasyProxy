'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

return view.extend({
	load: function () {
		var connP = app.loadCfg().then(function (cfg) { return { cfg: cfg }; });
		var logP = fs.exec('/usr/sbin/easyproxy', ['log']).then(function (r) {
			return (r.stdout || r.stderr || '').trim() || '暂无日志';
		}).catch(function (e) { return '读取日志失败：' + e; });
		return Promise.all([connP, logP]).then(function (r) {
			return { conn: r[0], log: r[1] };
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.tabs([
				['conn', '实时连接', app.pageConn(d.conn)],
				['logs', '运行日志', app.pageLogs({ log: d.log })]
			])
		]);
	}
});
