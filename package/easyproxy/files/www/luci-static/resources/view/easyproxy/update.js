'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

return view.extend({
	load: function () {
		return app.cliJson(['doctor']).catch(function () { return {}; }).then(function (doc) {
			return fs.exec('/usr/sbin/easyproxy', ['status', '--json']).then(function (r) {
				var st = null;
				try { st = JSON.parse(r.stdout); } catch (e) { st = null; }
				return { status: st, doctor: (doc && doc.checks) || [] };
			}).catch(function () {
				return { status: null, doctor: (doc && doc.checks) || [] };
			});
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.topBar(),
			app.tabs([
				['upd', '更新与诊断', app.pageUpdate({ status: d.status, doctor: d.doctor })]
			])
		]);
	}
});
