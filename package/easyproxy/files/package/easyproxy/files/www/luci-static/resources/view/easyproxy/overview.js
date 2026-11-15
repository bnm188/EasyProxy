
'use strict';
'require view';

return view.extend({
	render: function() {
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', { 'class': 'content-title' }, _('EasyProxy')),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Dashboard')),
				E('p', {}, _('EasyProxy proxy management system')),

				E('div', {
					'class': 'alert-message warning'
				}, [
					E('strong', {}, _('Development Stage 1')),
					E('p', {}, _('The proxy runtime is not implemented yet.'))
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Engine Status')),
				E('p', {}, _('Current engine: Not configured')),
				E('p', {}, _('dae: Not available')),
				E('p', {}, _('sing-box: Not available'))
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Routing Policy')),
				E('p', {}, _('China mainland traffic: DIRECT')),
				E('p', {}, _('Fail-closed protection: Enabled'))
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Notice')),
				E('p', {}, _('This is an initial interface preview.')),
				E('p', {}, _('No proxy traffic is currently being processed.')),
				E('p', {}, _('Proxy engine switching and routing are not available yet.'))
			])
		]);
	}
});
