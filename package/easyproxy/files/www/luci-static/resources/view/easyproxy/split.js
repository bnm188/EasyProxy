'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.all([
			app.loadStatus(),
			app.loadCfg(),
			app.cliJson(['rule', 'list'])
		]).then(function (r) {
			return { status: r[0], cfg: r[1], rules: (r[2] && r[2].rules) || [] };
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.topBar(),
			app.tabs([
				['split', '分流策略', app.pageSplit({ status: d.status, cfg: d.cfg })],
				['rules', '规则集', app.pageRules({ rules: d.rules })]
			])
		]);
	}
});
