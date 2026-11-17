'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.all([
			app.loadCfg(),
			app.loadStatus()
		]).then(function (r) {
			return { cfg: r[0], status: r[1] };
		});
	},
	render: function (d) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.tabs([
				['dns', 'DNS 与网络', app.pageDns({ cfg: d.cfg, status: d.status })]
			])
		]);
	}
});
