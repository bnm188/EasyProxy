'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

var DIR = '/etc/easyproxy/backups';

return view.extend({
	load: function () {
		function safe(p, fallback) {
			return p.catch(function (e) { return fallback(e); });
		}

		var cfgP = Promise.all([app.loadCfg(), app.cliJson(['doctor'])]).then(function (r) {
			return { cfg: r[0], doctor: (r[1] && r[1].checks) || [] };
		});

		var engP = Promise.all([
			app.loadStatus(),
			app.cliJson(['engine', 'health']),
			fs.exec('/usr/sbin/easyproxy', ['engine', 'list']).then(function (r) { return r.stdout; })
				.catch(function () { return ''; })
		]).then(function (r) {
			return { status: r[0], health: r[1], list: r[2] };
		});

		var logP = fs.exec('/usr/sbin/easyproxy', ['log']).then(function (r) {
			return (r.stdout || r.stderr || '').trim() || '暂无日志';
		}).catch(function (e) {
			return '读取日志失败：' + e;
		});

		var backP = fs.list(DIR).catch(function () { return []; }).then(function (files) {
			return {
				dir: DIR,
				files: (files || []).filter(function (f) { return /^easyproxy-.*\.tar\.gz$/.test(f.name); })
			};
		});

		var updP = fs.exec('/usr/sbin/easyproxy', ['status', '--json']).then(function (r) {
			try {
				return { status: JSON.parse(r.stdout) };
			} catch (e) {
				return { status: null };
			}
		}).catch(function () {
			return { status: null };
		});

		return Promise.all([cfgP, engP, logP, backP, updP]).then(function (r) {
			return { set: r[0], eng: r[1], log: r[2], back: r[3], upd: r[4] };
		});
	},
	render: function (d) {
		return E('div', { class: 'ep-stack' }, [
			app.pageSettings(d.set),
			app.pageEngines(d.eng),
			app.pageLogs({ log: d.log }),
			app.pageBackup(d.back),
			app.pageUpdate(d.upd)
		]);
	}
});
