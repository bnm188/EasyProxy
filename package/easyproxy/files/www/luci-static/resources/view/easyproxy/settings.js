'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

var DIR = '/etc/easyproxy/backups';

return view.extend({
	load: function () {
		var cfgP = Promise.all([app.loadCfg(), app.cliJson(['doctor'])]).then(function (r) {
			return { cfg: r[0], doctor: (r[1] && r[1].checks) || [] };
		});
		var backP = fs.list(DIR).catch(function () { return []; }).then(function (files) {
			return {
				dir: DIR,
				files: (files || []).filter(function (f) { return /^easyproxy-.*\.tar\.gz$/.test(f.name); })
			};
		});
		return Promise.all([cfgP, backP]).then(function (r) {
			return { set: r[0], back: r[1] };
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.topBar(),
			app.tabs([
				['basic', '基础设置', app.pageSettings(d.set)],
				['safety', '管理密码', app.pageSafety()],
				['backup', '备份与恢复', app.pageBackup(d.back)]
			])
		]);
	}
});
