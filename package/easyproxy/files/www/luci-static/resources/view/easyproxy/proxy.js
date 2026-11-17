'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.all([
			app.cliJson(['node', 'list']),
			app.loadStatus(),
			app.loadCfg()
		]).then(function (r) {
			return { list: r[0], status: r[1], cfg: r[2] };
		});
	},
	render: function (d) {
		return E('div', { class: 'ep-stack' }, [
			app.pageNodes({ list: d.list }),
			app.pageSubscription(),
			app.pageSplit({ status: d.status, cfg: d.cfg })
		]);
	}
});
