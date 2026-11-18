'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

return view.extend({
	load: function () {
		return Promise.all([
			app.loadStatus(),
			app.cliJson(['engine', 'health']),
			fs.exec('/usr/sbin/easyproxy', ['engine', 'list']).then(function (r) { return r.stdout; })
				.catch(function () { return ''; })
		]).then(function (r) {
			return { status: r[0], health: r[1], list: r[2] };
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.topBar(),
			app.tabs([
				['kernel', '内核管理', app.pageEngines(d)]
			])
		]);
	}
});
