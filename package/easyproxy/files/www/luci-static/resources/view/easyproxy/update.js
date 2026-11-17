'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

return view.extend({
	load: function () {
		return fs.exec('/usr/sbin/easyproxy', ['status', '--json']).then(function (r) {
			try {
				return { status: JSON.parse(r.stdout) };
			} catch (e) {
				return { status: null };
			}
		}).catch(function () {
			return { status: null };
		});
	},
	render: function (data) {
		return app.pageUpdate(data);
	}
});
