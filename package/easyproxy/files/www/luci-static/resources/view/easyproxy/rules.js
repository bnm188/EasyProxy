'use strict';
'require easyproxy.app as app';
'require view';

return view.extend({
	load: function () {
		return app.cliJson(['rule', 'list']).then(function (r) {
			return (r && r.rules) || [];
		});
	},
	render: function (rules) {
		return app.pageRules({ rules: rules });
	}
});
