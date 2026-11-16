'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.all([app.loadStatus(), app.loadCfg()]).then(function (r) {
			return { status: r[0], cfg: r[1] };
		});
	},
	render: function (data) {
		return app.pageSplit(data);
	}
});
