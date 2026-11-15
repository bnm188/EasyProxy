
'use strict';

'require view';

return view.extend({
	render: function() {
		var css = `
		.ep-shell {
			display:flex;
			min-height:760px;
			background:#071326;
			color:#eaf3ff;
			border-radius:12px;
			overflow:hidden;
			font-family:Arial,"Microsoft YaHei",sans-serif;
			animation:epFade .7s ease both;
		}
		.ep-shell * {box-sizing:border-box}
		.ep-side {
			width:205px;
			flex-shrink:0;
			background:#091a32;
			border-right:1px solid #18385e;
			padding:18px 12px;
		}
		.ep-logo {
			text-align:center;
			padding:15px 5px 25px;
			border-bottom:1px solid #18385e;
			margin-bottom:15px;
		}
		.ep-logo-icon {
			font-size:42px;
			color:#16a7ff;
			text-shadow:0 0 20px #168dff;
			animation:epFloat 3s ease-in-out infinite;
		}
		.ep-logo h2 {
			color:white;
			margin:8px 0;
			font-size:22px;
		}
		.ep-logo p {color:#8daed5;margin:0}
		.ep-nav {
			display:block;
			padding:13px 10px;
			margin:5px 0;
			border-radius:6px;
			color:#d5e6ff;
			font-size:14px;
			border-left:3px solid transparent;
			transition:all .25s ease;
		}
		.ep-nav:hover {
			background:#12345b;
			transform:translateX(4px);
			color:white;
		}
		.ep-nav.active {
			background:linear-gradient(90deg,#06458e,#102c55);
			border-left-color:#16c9ff;
			color:white;
			box-shadow:0 0 15px #087bc744;
		}
		.ep-main {
			flex:1;
			min-width:0;
			padding:22px;
		}
		.ep-top {
			display:flex;
			justify-content:space-between;
			align-items:center;
			gap:10px;
			margin-bottom:20px;
			color:#a9c8ee;
		}
		.ep-light {
			display:inline-block;
			width:9px;
			height:9px;
			border-radius:50%;
			background:#f0b43b;
			margin-right:7px;
			box-shadow:0 0 10px #f0b43b;
			animation:epPulse 1.8s infinite;
		}
		.ep-banner {
			padding:28px;
			border-radius:12px;
			background:linear-gradient(110deg,#073c82,#071b3a 75%);
			border:1px solid #1463b2;
			margin-bottom:18px;
			position:relative;
			overflow:hidden;
		}
		.ep-banner:after {
			content:'';
			position:absolute;
			width:220px;
			height:220px;
			right:8%;
			top:-100px;
			border:1px solid #1b91ff66;
			border-radius:50%;
			box-shadow:0 0 35px #087bff44,inset 0 0 35px #087bff33;
			animation:epOrbit 12s linear infinite;
		}
		.ep-banner h1 {
			font-size:29px;
			margin:0 0 10px;
			color:white;
			position:relative;
			z-index:1;
		}
		.ep-banner p {
			color:#b8d8ff;
			margin:0;
			position:relative;
			z-index:1;
		}
		.ep-grid {
			display:grid;
			grid-template-columns:repeat(4,minmax(0,1fr));
			gap:12px;
			margin-bottom:16px;
		}
		.ep-card {
			background:linear-gradient(145deg,#10294d,#091a34);
			border:1px solid #24538b;
			border-radius:10px;
			padding:17px;
			min-width:0;
			transition:transform .25s ease,border-color .25s ease,box-shadow .25s ease;
			animation:epFade .65s ease both;
		}
		.ep-card:hover {
			transform:translateY(-4px);
			border-color:#13aaff;
			box-shadow:0 0 18px #087bff44;
		}
		.ep-card small {
			display:block;
			color:#9dbce2;
			margin-bottom:9px;
			font-size:12px;
		}
		.ep-number {
			font-size:25px;
			font-weight:bold;
			color:white;
			margin-bottom:8px;
		}
		.ep-green {color:#19e58a!important}
		.ep-blue {color:#18aaff!important}
		.ep-layout {
			display:grid;
			grid-template-columns:minmax(0,2fr) minmax(220px,1fr);
			gap:14px;
			margin-bottom:15px;
		}
		.ep-title {
			font-size:18px;
			font-weight:bold;
			margin-bottom:17px;
			color:white;
			border-left:4px solid #12aaff;
			padding-left:10px;
		}
		.ep-chart {
			height:210px;
			position:relative;
			border-bottom:1px solid #315477;
			background-image:
				linear-gradient(#19385c 1px,transparent 1px),
				linear-gradient(90deg,#19385c 1px,transparent 1px);
			background-size:20% 25%;
			overflow:hidden;
		}
		.ep-chart svg {
			width:100%;
			height:100%;
		}
		.ep-line-blue {
			stroke-dasharray:1200;
			stroke-dashoffset:1200;
			animation:epDraw 4s ease forwards,epFlow 7s linear 4s infinite;
		}
		.ep-line-green {
			stroke-dasharray:1200;
			stroke-dashoffset:1200;
			animation:epDraw 4s ease forwards,epFlow 7s linear 4s infinite;
		}
		.ep-engine {
			padding:14px;
			border:1px solid #315477;
			border-radius:8px;
			margin-bottom:10px;
			background:#0a1b35;
			transition:all .25s ease;
		}
		.ep-engine:hover {
			border-color:#12aaff;
			transform:translateX(3px);
		}
		.ep-engine strong {font-size:18px}
		.ep-engine p {
			font-size:12px;
			color:#a9c8ee;
			margin:7px 0 0;
		}
		.ep-button {
			display:block;
			text-align:center;
			padding:12px;
			border-radius:7px;
			background:linear-gradient(90deg,#075fd1,#087fe8);
			color:white;
			font-weight:bold;
			margin-top:12px;
		}
		.ep-bottom {
			display:grid;
			grid-template-columns:1fr 1.1fr;
			gap:14px;
		}
		.ep-policy,.ep-notice {
			line-height:2.3;
			color:#c9ddf8;
		}
		.ep-muted {
			color:#8caed5;
			font-size:12px;
			line-height:1.8;
			margin-top:9px;
		}
		@keyframes epFade {
			from {opacity:0;transform:translateY(12px)}
			to {opacity:1;transform:translateY(0)}
		}
		@keyframes epPulse {
			0%,100% {opacity:1;box-shadow:0 0 5px currentColor}
			50% {opacity:.45;box-shadow:0 0 16px currentColor}
		}
		@keyframes epFloat {
			0%,100% {transform:translateY(0)}
			50% {transform:translateY(-7px)}
		}
		@keyframes epOrbit {
			from {transform:rotate(0deg)}
			to {transform:rotate(360deg)}
		}
		@keyframes epDraw {
			to {stroke-dashoffset:0}
		}
		@keyframes epFlow {
			to {stroke-dashoffset:-1200}
		}
		@media(max-width:850px) {
			.ep-side {width:145px}
			.ep-grid {grid-template-columns:repeat(2,minmax(0,1fr))}
			.ep-layout,.ep-bottom {grid-template-columns:1fr}
		}
		@media(max-width:560px) {
			.ep-side {width:105px;padding:9px 5px}
			.ep-nav {font-size:11px;padding:10px 4px}
			.ep-main {padding:10px}
			.ep-banner h1 {font-size:21px}
			.ep-number {font-size:20px}
			.ep-card {padding:12px}
		}
		@media(prefers-reduced-motion:reduce) {
			.ep-shell,.ep-shell * {
				animation:none!important;
				transition:none!important;
			}
		}
		`;

		function card(icon, title, value, note, color) {
			return E('div', {'class':'ep-card'}, [
				E('small', {}, icon + '  ' + title),
				E('div', {'class':'ep-number ' + (color || '')}, value),
				E('small', {}, note)
			]);
		}

		function panel(title, content) {
			return E('div', {'class':'ep-card'}, [
				E('div', {'class':'ep-title'}, title),
				content
			]);
		}

		var menu = [
			'运行总览',
			'节点管理',
			'订阅管理',
			'智能分流',
			'内核管理',
			'DNS 设置',
			'规则管理',
			'日志中心',
			'配置备份与恢复',
			'系统设置'
		];

		var icons = ['⌂','▤','☁','◇','▣','◎','◆','▤','▥','⚙'];

		var sidebar = E('div', {'class':'ep-side'}, [
			E('div', {'class':'ep-logo'}, [
				E('div', {'class':'ep-logo-icon'}, '◆'),
				E('h2', {}, 'EasyProxy'),
				E('p', {}, '智能代理管理')
			]),
			E('div', {}, menu.map(function(name,index) {
				return E('div', {
					'class':'ep-nav' + (index === 0 ? ' active' : '')
				}, icons[index] + '  ' + name);
			}))
		]);

		var chart = E('svg', {
			'viewBox':'0 0 600 210',
			'preserveAspectRatio':'none'
		}, [
			E('path', {
				'd':'M0 160 L55 125 L105 145 L160 75 L215 120 L270 100 L325 135 L380 65 L435 110 L490 35 L545 85 L600 55',
				'fill':'none',
				'stroke':'#168dff',
				'stroke-width':'4',
				'class':'ep-line-blue'
			}),
			E('path', {
				'd':'M0 185 L55 165 L105 175 L160 155 L215 170 L270 145 L325 165 L380 155 L435 175 L490 150 L545 170 L600 155',
				'fill':'none',
				'stroke':'#19d88b',
				'stroke-width':'3',
				'class':'ep-line-green'
			})
		]);

		var enginePanel = E('div', {}, [
			E('div', {'class':'ep-engine'}, [
				E('strong', {}, '◆ dae'),
				E('p', {}, '高性能代理内核 · 尚未接入')
			]),
			E('div', {'class':'ep-engine'}, [
				E('strong', {}, '◇ sing-box'),
				E('p', {}, '多协议代理内核 · 尚未接入')
			]),
			E('div', {'class':'ep-button'}, '内核切换 · 开发中')
		]);

		var policyPanel = E('div', {'class':'ep-policy'}, [
			E('div', {}, '🛡 中国大陆流量：DIRECT 直连'),
			E('div', {}, '✓ 国内流量强制直连'),
			E('div', {}, '✓ 国外流量：PROXY'),
			E('div', {}, '✓ 故障保护：待实现'),
			E('div', {'class':'ep-muted'},
				'以上为设计目标，尚未启用实际路由')
		]);

		var noticePanel = E('div', {'class':'ep-notice'}, [
			E('div', {'class':'ep-green'}, '✓ 中文管理面板设计预览'),
			E('div', {}, '⚠ 当前处于开发阶段'),
			E('div', {}, '⚠ 代理内核尚未接入'),
			E('div', {}, '⚠ 暂无真实流量统计'),
			E('div', {'class':'ep-muted'},
				'当前展示为示意内容，不代表实际运行状态')
		]);

		return E('div', {}, [
			E('style', {}, css),
			E('div', {'class':'ep-shell'}, [
				sidebar,
				E('div', {'class':'ep-main'}, [
					E('div', {'class':'ep-top'}, [
						E('strong', {}, 'OpenWrt  |  EasyProxy'),
						E('span', {}, [
							E('span', {'class':'ep-light'}),
							'开发预览'
						])
					]),
					E('div', {'class':'ep-banner'}, [
						E('h1', {}, 'EasyProxy 智能代理'),
						E('p', {}, '为您的网络连接提供更智能的代理管理方案')
					]),
					E('div', {'class':'ep-grid'}, [
						card('●','代理服务','未启动','等待内核接入','ep-green'),
						card('▣','当前内核','未选择','dae / sing-box','ep-blue'),
						card('◆','节点数量','0 个','等待导入节点','ep-blue'),
						card('▥','代理流量','0 MB','暂无真实流量数据','ep-blue')
					]),
					E('div', {'class':'ep-layout'}, [
						panel('流量统计', E('div', {}, [
							E('div', {'class':'ep-muted'}, '蓝色：代理流量　绿色：直连流量'),
							E('div', {'class':'ep-chart'}, chart),
							E('div', {'class':'ep-muted'}, '当前为动画示意曲线，并非真实流量')
						])),
						panel('代理内核', enginePanel)
					]),
					E('div', {'class':'ep-bottom'}, [
						panel('智能分流策略', policyPanel),
						panel('系统提示', noticePanel)
					]),
					E('div', {'class':'ep-foot'},
						'EasyProxy · 智能代理管理系统 · 开发预览版本')
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
