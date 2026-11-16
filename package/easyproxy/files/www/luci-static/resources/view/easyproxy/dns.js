'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return app.loadCfg();
	},
	render: function (cfg) {
		return app.pageDns({ cfg: cfg });
	}
});
