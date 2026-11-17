'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.all([app.loadCfg(), app.cliJson(['doctor'])]).then(function (r) {
			return { cfg: r[0], doctor: (r[1] && r[1].checks) || [] };
		});
	},
	render: function (data) {
		return app.pageSettings(data);
	}
});
