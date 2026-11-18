'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

return view.extend({
	load: function () {
		var statusP = app.loadStatus().catch(function () { return {}; });
		var cfgP = app.loadCfg().catch(function () { return {}; });
		var connP = app.liveConnections();
		var logP = fs.exec('/usr/sbin/easyproxy', ['log']).then(function (r) {
			return (r.stdout || r.stderr || '').trim() || '暂无日志';
		}).catch(function (e) { return '读取日志失败：' + e; });
		return Promise.all([statusP, cfgP, connP, logP]).then(function (r) {
			return { status: r[0], cfg: r[1], conn: r[2], log: r[3] };
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.topBar(),
			app.tabs([
				['live', '实时连接', app.pageLive(d.status, d.conn)],
				['conn', '入站设置', app.pageConn({ cfg: d.cfg })],
				['logs', '运行日志', app.pageLogs({ log: d.log })]
			])
		]);
	}
});
