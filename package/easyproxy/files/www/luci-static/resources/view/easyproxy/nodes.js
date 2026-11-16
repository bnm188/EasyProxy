'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return app.cliJson(['node', 'list']);
	},
	render: function (list) {
		return app.pageNodes({ list: list });
	}
});
