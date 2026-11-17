'use strict';
'require easyproxy.app as app';
'require view';
'require fs';

var DIR = '/etc/easyproxy/backups';

return view.extend({
	load: function () {
		return fs.list(DIR).catch(function () { return []; }).then(function (files) {
			return {
				dir: DIR,
				files: (files || []).filter(function (f) { return /^easyproxy-.*\.tar\.gz$/.test(f.name); })
			};
		});
	},
	render: function (data) {
		return app.pageBackup(data);
	}
});
