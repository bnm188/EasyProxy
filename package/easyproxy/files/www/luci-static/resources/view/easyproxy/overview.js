'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return app.loadStatus();
	},
	render: function (status) {
		return app.pageOverview(status);
	}
});
