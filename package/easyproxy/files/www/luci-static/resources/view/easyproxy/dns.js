'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.all([
			app.loadCfg(),
			app.cliJson(['rule', 'list'])
		]).then(function (r) {
			return { cfg: r[0], rules: (r[1] && r[1].rules) || [] };
		});
	},
	render: function (d) {
		return E('div', { class: 'ep-stack' }, [
			app.pageDns({ cfg: d.cfg }),
			app.pageRules({ rules: d.rules })
		]);
	}
});
