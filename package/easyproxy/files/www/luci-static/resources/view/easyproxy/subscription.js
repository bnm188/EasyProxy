'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return Promise.resolve(true);
	},
	render: function () {
		return app.pageSubscription();
	}
});
