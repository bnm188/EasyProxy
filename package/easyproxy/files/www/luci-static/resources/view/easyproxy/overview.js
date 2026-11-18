'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return app.loadStatus();
	},
	render: function (status) {
		app.injectStyle();
		return E('div', { class: 'ep-wrap' }, [
			app.topBar(),
			app.kpiLive(status),
			app.pageOverview(status)
		]);
	}
});
