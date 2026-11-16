'use strict';

'require view';
'require rpc';
'require ui';

var callExec = rpc.declare({
	object: 'file',
	method: 'exec',
	params: [ 'command', 'params', 'env' ]
});

var EP_BIN = '/usr/sbin/easyproxy';

function runCli(args) {
	return callExec(EP_BIN, args).then(function(res) {
		var out = res && typeof res.stdout === 'string' ? res.stdout : '';
		var err = res && typeof res.stderr === 'string' ? res.stderr : '';
		var code = res && res.code != null ? Number(res.code) : -1;
		var data = null;

		try {
			data = JSON.parse(out.trim());
		} catch (e) {
			data = null;
		}

		return { code: code, data: data, raw: out, err: err };
	}).catch(function(e) {
		return { code: -1, data: null, raw: '', err: String((e && e.message) || e) };
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			runCli([ 'status', '--json' ]),
			runCli([ 'validate', '--json' ])
		]);
	},

	render: function(results) {
		var status = results[0] || {};
		var check = results[1] || {};
		var d = status.data || {};
		var v = check.data || {};

		var ok = !!(status.data && status.data.ok);
		var enabled = Number(d.enabled || 0) === 1;
		var engine = d.engine || 'none';
		var binaryOk = Number(d.binary_ok || 0) === 1;
		var binary = d.binary || '';
		var china = d.china_policy || 'direct';
		var proxy = d.proxy_policy || 'proxy';
		var failClosed = Number(d.fail_closed || 0) === 1;
		var nodes = Number(d.nodes || 0);
		var version = d.version || '—';
		var stage = d.stage != null ? d.stage : '—';
		var generated = d.generated || '—';
		var validOk = !!(v && v.ok);
		var messages = (v && v.messages) || [];
		var runtime = d.runtime || 'stopped';
		var runPid = Number(d.runtime_pid || 0);
		var runUp = Number(d.runtime_uptime || 0);
		var nodesEnabled = Number(d.nodes_enabled || 0);
		var configState = d.config_state || 'missing';
		var chinaRule = Number(d.china_rule || 0) === 1;
		var routeRules = Number(d.route_rules || 0);
		var dnsMode = d.dns_mode || 'local';
		var ruleSetState = d.rule_set_state || 'missing';

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
		.ep-logo h2 {color:white;margin:8px 0;font-size:22px}
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
		.ep-nav:hover {background:#12345b;transform:translateX(4px);color:white}
		.ep-nav.active {
			background:linear-gradient(90deg,#06458e,#102c55);
			border-left-color:#16c9ff;
			color:white;
			box-shadow:0 0 15px #087bc744;
		}
		.ep-main {flex:1;min-width:0;padding:22px}
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
			margin-right:7px;
			animation:epPulse 1.8s infinite;
		}
		.ep-light.on {background:#19e58a;box-shadow:0 0 10px #19e58a;color:#19e58a}
		.ep-light.warn {background:#f0b43b;box-shadow:0 0 10px #f0b43b;color:#f0b43b}
		.ep-light.off {background:#5d7ea6;box-shadow:none;animation:none;color:#5d7ea6}
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
		.ep-banner h1 {font-size:29px;margin:0 0 10px;color:white;position:relative;z-index:1}
		.ep-banner p {color:#b8d8ff;margin:0;position:relative;z-index:1}
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
		.ep-card small {display:block;color:#9dbce2;margin-bottom:9px;font-size:12px}
		.ep-number {font-size:25px;font-weight:bold;color:white;margin-bottom:8px;word-break:break-word}
		.ep-green {color:#19e58a!important}
		.ep-blue {color:#18aaff!important}
		.ep-amber {color:#f0b43b!important}
		.ep-gray {color:#8caed5!important}
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
		.ep-empty {
			height:210px;
			border:1px dashed #315477;
			border-radius:8px;
			display:flex;
			flex-direction:column;
			align-items:center;
			justify-content:center;
			gap:10px;
			color:#8caed5;
			background-image:
				linear-gradient(#19385c 1px,transparent 1px),
				linear-gradient(90deg,#19385c 1px,transparent 1px);
			background-size:20% 25%;
			background-blend-mode:overlay;
		}
		.ep-empty span {font-size:34px;color:#2f6fae}
		.ep-engine {
			padding:14px;
			border:1px solid #315477;
			border-radius:8px;
			margin-bottom:10px;
			background:#0a1b35;
			transition:all .25s ease;
		}
		.ep-engine:hover {border-color:#12aaff;transform:translateX(3px)}
		.ep-engine.selected {border-color:#16c9ff;background:#0b2444;box-shadow:0 0 14px #087bff33}
		.ep-engine strong {font-size:18px}
		.ep-engine p {font-size:12px;color:#a9c8ee;margin:7px 0 0}
		.ep-button {
			display:block;
			width:100%;
			text-align:center;
			padding:12px;
			border:0;
			border-radius:7px;
			background:linear-gradient(90deg,#075fd1,#087fe8);
			color:white;
			font-weight:bold;
			font-size:14px;
			margin-top:12px;
			cursor:pointer;
		}
		.ep-button:hover {filter:brightness(1.12)}
		.ep-bottom {display:grid;grid-template-columns:1fr 1.1fr;gap:14px}
		.ep-policy,.ep-notice {line-height:2.3;color:#c9ddf8}
		.ep-muted {color:#8caed5;font-size:12px;line-height:1.8;margin-top:9px}
		.ep-foot {margin-top:16px;color:#7fa3cd;font-size:12px;text-align:center}
		.ep-alert {
			border:1px solid #8a5a1d;
			background:#2a1d09;
			color:#f5c76a;
			border-radius:8px;
			padding:12px 14px;
			margin-bottom:14px;
			font-size:13px;
			line-height:1.7;
			word-break:break-all;
		}
		@keyframes epFade {from {opacity:0;transform:translateY(12px)} to {opacity:1;transform:translateY(0)}}
		@keyframes epPulse {0%,100% {opacity:1;box-shadow:0 0 5px currentColor} 50% {opacity:.45;box-shadow:0 0 16px currentColor}}
		@keyframes epFloat {0%,100% {transform:translateY(0)} 50% {transform:translateY(-7px)}}
		@keyframes epOrbit {from {transform:rotate(0deg)} to {transform:rotate(360deg)}}
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
			.ep-shell,.ep-shell * {animation:none!important;transition:none!important}
		}
		`;

		function card(icon, title, value, note, color) {
			return E('div', { 'class': 'ep-card' }, [
				E('small', {}, icon + '  ' + title),
				E('div', { 'class': 'ep-number ' + (color || '') }, value),
				E('small', {}, note)
			]);
		}

		function fmtDuration(sec) {
			if (!sec) return '—';
			if (sec < 60) return sec + ' 秒';
			if (sec < 3600) return Math.floor(sec / 60) + ' 分';
			return Math.floor(sec / 3600) + ' 小时 ' + Math.floor((sec % 3600) / 60) + ' 分';
		}

		function panel(title, content) {
			return E('div', { 'class': 'ep-card' }, [
				E('div', { 'class': 'ep-title' }, title),
				content
			]);
		}

		var menu = [
			'运行总览', '节点管理', '订阅管理', '智能分流', '内核管理',
			'DNS 设置', '规则管理', '日志中心', '配置备份与恢复', '系统设置'
		];
		var icons = [ '⌂', '▤', '☁', '◇', '▣', '◎', '◆', '▤', '▥', '⚙' ];

		var sidebar = E('div', { 'class': 'ep-side' }, [
			E('div', { 'class': 'ep-logo' }, [
				E('div', { 'class': 'ep-logo-icon' }, '◆'),
				E('h2', {}, 'EasyProxy'),
				E('p', {}, '智能代理管理')
			]),
			E('div', {}, menu.map(function(name, index) {
				return E('div', { 'class': 'ep-nav' + (index === 0 ? ' active' : '') },
					icons[index] + '  ' + name);
			}))
		]);

		var lightClass = !ok ? 'off'
			: (runtime === 'running' ? 'on' : (enabled ? 'warn' : 'off'));
		var lightText = !ok ? '状态读取失败'
			: (runtime === 'running' ? '运行中'
				: (enabled ? (binaryOk ? '已启用 · 未运行' : '已启用 · 内核未安装') : '未启用'));

		var engineLabel = engine === 'none' ? '未选择' : engine;
		var engineNote = engine === 'none' ? '尚未选择内核'
			: (binaryOk ? '二进制已就绪' : '二进制未安装');

		var serviceNote = enabled
			? (runtime === 'running' ? ('已运行 ' + fmtDuration(runUp))
				: (binaryOk ? '内核已就绪 · 待启动' : '内核未安装'))
			: '配置未启用';

		var serviceValue = enabled ? (runtime === 'running' ? '运行中' : '已停止') : '未启用';
		var configText = configState === 'ok' ? '已生成且有效'
			: (configState === 'invalid' ? '已生成但校验失败' : '尚未生成');

		var splitText = chinaRule ? '大陆直连' : '全代理';
		var splitNote = chinaRule
			? ('规则 ' + routeRules + ' 条 · DNS ' + dnsMode)
			: (ruleSetState === 'missing' ? '规则集缺失 · 已降级' : 'china_policy=proxy');
		var ruleSetText = ruleSetState === 'ready' ? '已就绪' : '缺失';
		var dnsText = dnsMode === 'split' ? '分流（国内 DNS / 远程 DoH）' : '单上游（国内 DNS）';
		var failNote = failClosed ? '故障保护：开启' : '故障保护：关闭';

		var enginePanel = E('div', {}, [
			E('div', { 'class': 'ep-engine' + (engine === 'dae' ? ' selected' : '') }, [
				E('strong', {}, '◆ dae'),
				E('p', {}, engine === 'dae'
					? ('已选择 · ' + (binaryOk ? '二进制已就绪' : '二进制未安装'))
					: '高性能代理内核 · 尚未接入')
			]),
			E('div', { 'class': 'ep-engine' + (engine === 'sing-box' ? ' selected' : '') }, [
				E('strong', {}, '◇ sing-box'),
				E('p', {}, engine === 'sing-box'
					? ('已选择 · ' + (binaryOk ? '二进制已就绪' : '二进制未安装'))
					: '多协议代理内核 · 尚未接入')
			]),
			E('div', { 'class': 'ep-muted' }, binary ? ('二进制路径：' + binary) : '二进制路径：未设置'),
			E('button', {
				'class': 'ep-button',
				'click': function(ev) {
					ev.preventDefault();
					window.location.reload();
				}
			}, '重新读取状态')
		]);

		var policyPanel = E('div', { 'class': 'ep-policy' }, [
			E('div', {}, '🛡 中国大陆流量：' + (china === 'direct' ? 'DIRECT 直连' : china.toUpperCase())),
			E('div', {}, '✓ 国外流量：' + String(proxy).toUpperCase()),
			E('div', {}, (failClosed ? '✓ ' : '⚠ ') + '故障保护：' + (failClosed ? '已开启（fail-closed）' : '已关闭（fail-open）')),
			E('div', {}, (enabled ? '✓ ' : '⚠ ') + '总开关：' + (enabled ? '已启用' : '未启用')),
			E('div', {}, (ruleSetState === 'ready' ? '✓ ' : '⚠ ') + '大陆规则集：' + ruleSetText),
			E('div', {}, '◎ DNS：' + dnsText),
			E('div', { 'class': 'ep-muted' },
				'大陆规则集由 easyproxy config generate 下载到本地后引用，内核启动不再联网下载。')
		]);

		var checkLines = messages.length
			? messages.map(function(m) { return E('div', {}, (validOk ? '✓ ' : '⚠ ') + m); })
			: [ E('div', {}, '⚠ 配置校验未返回结果') ];

		var noticePanel = E('div', { 'class': 'ep-notice' }, [
			E('div', { 'class': validOk ? 'ep-green' : 'ep-amber' },
				(validOk ? '✓ 配置校验通过' : '⚠ 配置校验未通过')),
			checkLines,
			E('div', {}, (runtime === 'running' ? '✓ ' : '⚠ ') + '运行状态：'
				+ (runtime === 'running' ? ('运行中 · PID ' + runPid + ' · 已运行 ' + fmtDuration(runUp)) : '未运行')),
			E('div', {}, (configState === 'ok' ? '✓ ' : '⚠ ') + '内核配置：' + configText),
			E('div', {}, '版本：' + version + ' · Stage ' + stage),
			E('div', {}, '数据时间：' + generated),
			E('div', { 'class': 'ep-muted' },
				'本页数据来自 easyproxy status --json 的真实输出；流量统计、节点列表等仍待后续阶段实现。')
		]);

		var trafficPanel = E('div', {}, [
			E('div', { 'class': 'ep-muted' }, '蓝色：代理流量　绿色：直连流量'),
			E('div', { 'class': 'ep-empty' }, [
				E('span', {}, '▤'),
				E('div', {}, '暂无流量采集数据'),
				E('div', { 'class': 'ep-muted', 'style': 'margin-top:0' }, '流量曲线待后续阶段接入')
			])
		]);

		var alert = ok ? E('div', {}) : E('div', { 'class': 'ep-alert' }, [
			E('strong', {}, '无法读取 EasyProxy 状态'),
			E('div', {}, '退出码：' + status.code + (status.err ? '　输出：' + status.err : '')),
			E('div', { 'class': 'ep-muted' },
				'请确认 /usr/sbin/easyproxy 已安装且 rpcd 已放行（/usr/share/rpcd/acl.d/luci-app-easyproxy.json）。')
		]);

		return E('div', {}, [
			E('style', {}, css),
			E('div', { 'class': 'ep-shell' }, [
				sidebar,
				E('div', { 'class': 'ep-main' }, [
					E('div', { 'class': 'ep-top' }, [
						E('strong', {}, 'OpenWrt  |  EasyProxy'),
						E('span', {}, [
							E('span', { 'class': 'ep-light ' + lightClass }),
							lightText
						])
					]),
					alert,
					E('div', { 'class': 'ep-banner' }, [
						E('h1', {}, 'EasyProxy 智能代理'),
						E('p', {}, '为您的网络连接提供更智能的代理管理方案')
					]),
					E('div', { 'class': 'ep-grid' }, [
						card('●', '代理服务', serviceValue, serviceNote,
							runtime === 'running' ? 'ep-green' : (enabled ? 'ep-amber' : 'ep-gray')),
						card('▣', '当前内核', engineLabel, engineNote,
							binaryOk ? 'ep-blue' : 'ep-amber'),
						card('◆', '节点数量', nodesEnabled + ' / ' + nodes,
							nodes > 0 ? ('已启用 ' + nodesEnabled + ' 个') : '尚未配置节点', 'ep-blue'),
						card('▥', '分流模式', splitText, splitNote,
							chinaRule ? 'ep-green' : 'ep-amber')
					]),
					E('div', { 'class': 'ep-layout' }, [
						panel('流量统计', trafficPanel),
						panel('代理内核', enginePanel)
					]),
					E('div', { 'class': 'ep-bottom' }, [
						panel('智能分流策略', policyPanel),
						panel('配置与校验', noticePanel)
					]),
					E('div', { 'class': 'ep-foot' },
						'EasyProxy · 智能代理管理系统 · Stage ' + stage + ' · 配置：' + d.config_path)
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
