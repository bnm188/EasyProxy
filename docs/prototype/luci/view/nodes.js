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
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.tabs([
				['nodes', '节点管理', app.pageNodes({ list: d.list })],
				['sub', '订阅管理', app.pageSubscription()],
				['split', '分流策略', app.pageSplit({ status: d.status, cfg: d.cfg })]
			])
		]);
	}
});
