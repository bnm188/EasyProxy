'use strict';
'require fs';
'require uci';
'require ui';

// The panel's only exec target is this CLI. The ACL next to it grants exec on
// exactly this path and nothing else: no /bin/sh, no helper script. A generic
// shell in the ACL would let any ubus caller holding this ACL run arbitrary
// commands as root, because `file exec` takes the program *and* its arguments
// from the caller. Helper scripts are reached through `easyproxy traffic` /
// `easyproxy subscribe`, which validate their arguments themselves.
var BIN = '/usr/sbin/easyproxy';

var CSS = [
'.ep-wrap{font-family:"Noto Sans SC","Segoe UI",system-ui,sans-serif;color:#c9d6e8}',
'.ep-hero{position:relative;padding:16px 20px;border-radius:14px;background:linear-gradient(135deg,#0c1424,#10203a 55%,#0a1a2c);border:1px solid #1d2f4d;box-shadow:0 0 22px rgba(34,211,238,.08);margin-bottom:14px}',
'.ep-hero h2{margin:0 0 4px;font-size:19px;letter-spacing:.5px;color:#e8f1ff}',
'.ep-hero .ep-sub{font-size:12px;color:#7f93ad}',
'.ep-hero-line{height:2px;margin-top:12px;background:linear-gradient(90deg,#22d3ee,#6366f1,transparent)}',
'.ep-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(168px,1fr));gap:10px;margin-bottom:14px}',
'.ep-tile{background:#0e1727;border:1px solid #1b2a44;border-radius:11px;padding:11px 13px;transition:border-color .2s,box-shadow .2s}',
'.ep-tile:hover{border-color:#2b6c8f;box-shadow:0 0 14px rgba(34,211,238,.14)}',
'.ep-tile .ep-lab{font-size:11px;color:#7f93ad;letter-spacing:.4px;margin-bottom:6px}',
'.ep-tile .ep-val{font-size:15px;color:#e8f1ff;font-family:ui-monospace,Menlo,Consolas,monospace;word-break:break-all}',
'.ep-card{background:#0e1727;border:1px solid #1b2a44;border-radius:12px;padding:14px 16px;margin-bottom:14px}',
'.ep-card h3{margin:0 0 10px;font-size:14px;color:#cfe6ff;font-weight:600;letter-spacing:.4px}',
'.ep-card .ep-hint{font-size:12px;color:#7f93ad;line-height:1.6;margin-top:8px}',
'.ep-dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:7px;vertical-align:middle;box-shadow:0 0 9px currentColor}',
'.ep-ok{color:#22c55e}.ep-warn{color:#f59e0b}.ep-bad{color:#ef4444}.ep-off{color:#64748b}',
'.ep-ok .ep-dot,.ep-warn .ep-dot{animation:epPulse 2s ease-in-out infinite}',
'@keyframes epPulse{0%,100%{opacity:.55}50%{opacity:1}}',
'.ep-tbl{width:100%;border-collapse:collapse;font-size:13px}',
'.ep-tbl th{text-align:left;color:#7f93ad;font-weight:500;font-size:11px;letter-spacing:.4px;padding:6px 8px;border-bottom:1px solid #1b2a44}',
'.ep-tbl td{padding:7px 8px;border-bottom:1px solid #14213a;color:#c9d6e8;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}',
'.ep-tbl tr:hover td{background:#101c30}',
'.ep-btn{background:#132038;border:1px solid #24395a;color:#cfe6ff;border-radius:8px;padding:6px 12px;font-size:12px;cursor:pointer;margin:0 6px 6px 0;transition:all .18s}',
'.ep-btn:hover{border-color:#22d3ee;color:#e8f1ff;box-shadow:0 0 10px rgba(34,211,238,.2)}',
'.ep-btn.ep-primary{background:linear-gradient(135deg,#0e7490,#1d4ed8);border-color:#22d3ee}',
'.ep-btn.ep-danger{background:#3b1220;border-color:#7f1d3a;color:#fecdd3}',
'.ep-in{background:#0a1322;border:1px solid #22344f;color:#d6e2f3;border-radius:8px;padding:6px 9px;font-size:12px;font-family:ui-monospace,Menlo,Consolas,monospace;min-width:120px}',
'.ep-in:focus{outline:none;border-color:#22d3ee;box-shadow:0 0 8px rgba(34,211,238,.25)}',
'.ep-row{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:9px;font-size:13px}',
'.ep-row label{min-width:170px;color:#9db0c9}',
'.ep-pre{background:#0a1322;border:1px solid #1b2a44;border-radius:10px;padding:10px 12px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:#a9c0da;white-space:pre-wrap;max-height:320px;overflow:auto;line-height:1.6}',
'.ep-tag{display:inline-block;padding:2px 8px;border-radius:999px;font-size:11px;margin:2px 4px 2px 0;border:1px solid #24395a;color:#9db0c9}',
'.ep-tag.ep-hit{border-color:#22d3ee;color:#a5f3fc}',
'.ep-chart{width:100%;height:150px;display:block;background:#0a1322;border:1px solid #1b2a44;border-radius:11px}',
'.ep-err{background:#2b1220;border:1px solid #7f1d3a;color:#fecdd3;border-radius:10px;padding:12px 14px;font-size:13px;margin-bottom:14px}',
'.ep-switch{appearance:none;-webkit-appearance:none;width:38px;height:20px;background:#1b2a44;border-radius:999px;position:relative;cursor:pointer;transition:background .2s;border:none}',
'.ep-switch:checked{background:#0e7490}',
'.ep-switch:after{content:"";position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#c9d6e8;transition:left .2s}',
'.ep-switch:checked:after{left:20px;background:#e8f1ff}'
].join('\n');

function injectStyle() {
	if (typeof document === 'undefined' || document.getElementById('ep-dark-style'))
		return;
	document.head.appendChild(E('style', { id: 'ep-dark-style', type: 'text/css' }, CSS));
}

function notify(text, level) {
	ui.addNotification(null, E('p', {}, text), level || 'info');
}

function run(args) {
	return fs.exec(BIN, args).catch(function (e) {
		return { code: -1, stdout: '', stderr: String((e && e.message) || e) };
	});
}

function cliJson(args) {
	return run(args.concat(['--json'])).then(function (r) {
		try {
			return JSON.parse(r.stdout);
		} catch (e) {
			return null;
		}
	});
}

function loadStatus() {
	return cliJson(['status']);
}

function errCard(text) {
	return E('div', { class: 'ep-err' }, text);
}

// The dae adapter is still 开发中: a dae engine cannot start, because the
// renderer refuses a config it cannot run. The panel therefore keeps the
// previous choice and says why instead of writing dae into main.engine, which
// would leave the service unable to start after the next reload.
function saveEngine(pick) {
	if (pick === 'dae') {
		notify('dae 适配器开发中，暂不可选：请继续使用 sing-box', 'error');
		return Promise.resolve();
	}
	return saveUci({ 'main.engine': pick }).then(function () {
		notify('已保存内核选择', 'success');
		reload();
	}).catch(function (e) {
		notify('保存失败：' + e, 'error');
	});
}

function hero(title, sub, tags) {
	return E('div', { class: 'ep-hero' }, [
		E('h2', {}, title),
		E('div', { class: 'ep-sub' }, sub),
		tags ? E('div', { style: 'margin-top:10px' }, tags) : '',
		E('div', { class: 'ep-hero-line' })
	]);
}

function tile(label, value, cls) {
	return E('div', { class: 'ep-tile' }, [
		E('div', { class: 'ep-lab' }, label),
		E('div', { class: 'ep-val ' + (cls || '') }, value)
	]);
}

function card(title, body, hint) {
	var kids = [];
	if (title)
		kids.push(E('h3', {}, title));
	if (Array.isArray(body))
		kids = kids.concat(body);
	else if (body)
		kids.push(body);
	if (hint)
		kids.push(E('div', { class: 'ep-hint' }, hint));
	return E('div', { class: 'ep-card' }, kids);
}

function button(label, cls, handler) {
	return E('button', {
		class: 'ep-btn ' + (cls || ''),
		type: 'button',
		click: function (ev) {
			if (ev && ev.preventDefault) ev.preventDefault();
			try {
				return handler();
			} catch (e) {
				notify('操作失败：' + e, 'error');
			}
		}
	}, label);
}

function tag(text, hit) {
	return E('span', { class: 'ep-tag' + (hit ? ' ep-hit' : '') }, text);
}

function row(label, input, hint) {
	var kids = [E('label', {}, label), input];
	if (hint)
		kids.push(E('span', { class: 'ep-hint', style: 'margin:0' }, hint));
	return E('div', { class: 'ep-row' }, kids);
}

function textInput(id, value, placeholder) {
	return E('input', {
		id: id, class: 'ep-in', type: 'text',
		value: value == null ? '' : String(value),
		placeholder: placeholder || ''
	});
}

function switchInput(id, checked) {
	return E('input', {
		id: id, class: 'ep-switch', type: 'checkbox',
		checked: checked ? 'checked' : null
	});
}

function valOf(id) {
	var el = document.getElementById(id);
	if (!el)
		return '';
	return el.type === 'checkbox' ? (el.checked ? '1' : '0') : String(el.value).trim();
}

function lite(status) {
	if (status === 'running' || status === 'active' || status === 'ready' || status === 'ok')
		return 'ep-ok';
	if (status === 'inactive' || status === 'off' || status === 'disabled' || status === 'not running')
		return 'ep-off';
	if (status === 'unsupported' || status === 'missing')
		return 'ep-warn';
	return 'ep-bad';
}

function saveUci(values) {
	uci.unload('easyproxy');
	return uci.load('easyproxy').then(function () {
		Object.keys(values).forEach(function (k) {
			var p = k.split('.');
			uci.set('easyproxy', p[0], p[1], values[k]);
		});
		return uci.save();
	});
}

function reload(msg) {
	if (msg)
		notify(msg, 'success');
	window.setTimeout(function () { window.location.reload(); }, 700);
}

function showOutput(title, text) {
	ui.showModal(title, [
		E('pre', { class: 'ep-pre' }, (text || '').trim() || '(无输出)'),
		E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))
	]);
}

function trafficChart() {
	var canvas = E('canvas', { class: 'ep-chart' });
	var cap = E('div', { class: 'ep-hint', style: 'margin:6px 0 0' }, '采样中…');
	var samples = [];
	var last = null;
	var timer = null;

	function draw() {
		var box = canvas.getBoundingClientRect();
		if (!box.width)
			return;
		var dpr = window.devicePixelRatio || 1;
		canvas.width = Math.floor(box.width * dpr);
		canvas.height = Math.floor(box.height * dpr);
		var ctx = canvas.getContext('2d');
		ctx.scale(dpr, dpr);
		ctx.clearRect(0, 0, box.width, box.height);
		var max = 1;
		samples.forEach(function (s) { max = Math.max(max, s.rx, s.tx); });
		[[ 'rx', '#22d3ee' ], [ 'tx', '#a78bfa' ]].forEach(function (p) {
			ctx.beginPath();
			ctx.strokeStyle = p[1];
			ctx.lineWidth = 1.6;
			samples.forEach(function (s, i) {
				var x = box.width - (samples.length - i - 1) * (box.width / 59);
				var y = box.height - 6 - (s[p[0]] / max) * (box.height - 18);
				if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
			});
			ctx.stroke();
		});
	}

	function fmt(v) {
		if (v > 1048576) return (v / 1048576).toFixed(2) + ' MB/s';
		if (v > 1024) return (v / 1024).toFixed(1) + ' KB/s';
		return Math.round(v) + ' B/s';
	}

	function sample() {
		if (!document.body.contains(canvas)) {
			window.clearInterval(timer);
			return;
		}
		run(['traffic']).then(function (r) {
			var d = null;
			try { d = JSON.parse(r.stdout); } catch (e) { d = null; }
			if (!d || !d.ok)
				return;
			var now = Date.now();
			if (last) {
				var dt = Math.max(0.5, (now - last.t) / 1000);
				samples.push({ rx: Math.max(0, (d.rx - last.rx) / dt), tx: Math.max(0, (d.tx - last.tx) / dt) });
				if (samples.length > 60) samples.shift();
				var cur = samples[samples.length - 1];
				cap.textContent = (d.iface || 'br-lan') + ' · 下行 ' + fmt(cur.rx) + ' · 上行 ' + fmt(cur.tx);
				draw();
			}
			last = { t: now, rx: d.rx, tx: d.tx };
		}).catch(function () {});
	}

	timer = window.setInterval(sample, 2000);
	sample();
	return E('div', {}, [canvas, cap]);
}


function bypassText(state) {
	switch (state) {
	case 'active': return '已启用';
	case 'ready': return '已就绪（未下发）';
	case 'missing': return '地址表缺失';
	case 'disabled': return '已关闭';
	case 'unavailable': return '模块缺失';
	default: return '不支持';
	}
}

function bypassClass(state) {
	switch (state) {
	case 'active': case 'ready': return 'ep-ok';
	case 'disabled': return 'ep-off';
	case 'unavailable': return 'ep-bad';
	default: return 'ep-warn';
	}
}

function bypassHint(state) {
	switch (state) {
	case 'active': return '国内流量在 nft 入口放行，不进内核进程；这条状态为 active 才算真的生效。';
	case 'ready': return '地址表已通过校验，但规则还没下发：先开启透明代理，再回本页刷新。';
	case 'missing': return '地址表缺失或校验失败。此时不会退回全局代理，国内流量仍按直连处理。';
	case 'disabled': return '入口旁路已关闭：国内流量会进入内核再按 direct 直连，比旁路多一层处理。';
	case 'unavailable': return '未找到 bypass 模块（/usr/lib/easyproxy/bypass.sh），请重装本包。';
	default: return '本机 nftables 不可用，入口旁路无法启用。';
	}
}

function pageOverview(status) {
	injectStyle();
	if (!status)
		return E('div', { class: 'ep-wrap' }, [
			errCard('无法读取 EasyProxy 状态：未安装，或 /usr/sbin/easyproxy 不可执行。'),
			card('下一步', E('div', { class: 'ep-hint', style: 'margin:0' }, '在路由器上执行 opkg list-installed | grep easyproxy 确认安装；用 opkg install <ipk> 重装后再回本页刷新。'))
		]);

	var on = status.enabled == 1;
	var running = status.runtime === 'running';
	var split = status.route_mode === 'split';

	var tags = [
		tag('v' + status.version, true),
		tag(split ? '智能分流' : '仅直连'),
		tag(status.engine || '无内核'),
		tag(status.ipv6_policy === 'block' ? 'IPv6 阻断' : 'IPv6 直连')
	];

	var grid = E('div', { class: 'ep-grid' }, [
		tile('运行状态', running ? '运行中 ' + (status.runtime_pid || '') : '未运行', running ? 'ep-ok' : 'ep-off'),
		tile('总开关', on ? '已启用' : '已停用', on ? 'ep-ok' : 'ep-off'),
		tile('中国大陆', '直连（锁定）', 'ep-ok'),
		tile('失败闭合', '已锁定 1', 'ep-ok'),
		tile('内网设备', '强制直连', 'ep-ok'),
		tile('节点', (status.nodes_enabled || 0) + ' / ' + (status.nodes || 0) + ' 启用', (status.nodes_enabled > 0) ? 'ep-ok' : 'ep-warn'),
		tile('CN 规则集', status.rule_set_state === 'ready' ? '已就绪' : '缺失', status.rule_set_state === 'ready' ? 'ep-ok' : 'ep-bad'),
		tile('透明代理', status.tproxy_state === 'active' ? '接管中' : (status.transparent == 1 ? '已配置未生效' : '已关闭'), lite(status.tproxy_state)),
		tile('内核二进制', status.binary_ok == 1 ? '就绪' : '缺失', status.binary_ok == 1 ? 'ep-ok' : 'ep-bad'),
		tile('监听端口', String(status.listen_port || '-') + (status.listen_open == 1 ? ' 已监听' : ' 未监听'), status.listen_open == 1 ? 'ep-ok' : 'ep-warn'),
		tile('生成配置', status.config_state === 'ok' ? '校验通过' : String(status.config_state), status.config_state === 'ok' ? 'ep-ok' : 'ep-warn'),
		tile('内核稳定性', status.engine_dev == 1 ? '开发中' : '稳定', status.engine_dev == 1 ? 'ep-warn' : 'ep-ok')
	]);

	var actions = card('快捷操作', [
		E('div', {}, [
			button(running ? '停止' : '启动', 'ep-primary', function () {
				return run([running ? 'stop' : 'start']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('重启', '', function () {
				return run(['restart']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('重新生成配置', '', function () {
				return run(['config', 'generate']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
				});
			}),
			button(status.tproxy_state === 'active' ? '关闭透明代理' : '开启透明代理', '', function () {
				return run(['transparent', status.tproxy_state === 'active' ? 'remove' : 'apply']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('一键自检', '', function () {
				return run(['doctor']).then(function (r) {
					showOutput('EasyProxy 自检', (r.stdout || '') + (r.stderr || ''));
				});
			})
		]),
		'所有操作都调用 easyproxy 命令行，面板不做隐式改写。'
	]);

	var chart = card('流量统计', trafficChart(), '每 2 秒采一次 /proc/net/dev，只算速率，不写任何文件。');


	var bypass = card('入口旁路（国内不进内核）', [
		E('div', { class: 'ep-grid' }, [
			tile('入口状态', bypassText(status.bypass_state), bypassClass(status.bypass_state)),
			tile('国内地址表', String(status.bypass_cidr || 0) + ' 条', (status.bypass_cidr > 0) ? 'ep-ok' : 'ep-warn'),
			tile('判定口径', '域名优先 + IP 兜底', 'ep-ok')
		]),
		E('div', { class: 'ep-hint', style: 'margin:0' }, bypassHint(status.bypass_state)),
		E('div', {}, [
			button('一键恢复直连', 'ep-danger', function () {
				if (!confirm('将立即删除 nft 接管规则、切回纯直连，确定继续？'))
					return;
				return run(['bypass', 'restore']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		])
	], '开启后，命中国内地址表的流量在 nft 入口直接放行，不进入内核进程。');

	return E('div', { class: 'ep-wrap' }, [
		hero('EasyProxy 运行总览', '先用它确认四件事：内核在跑、规则集在、中国大陆直连、内网没被劫持。', tags),
		bypass,
		grid,
		actions,
		chart,
		card('流量路径说明', [
			E('div', { class: 'ep-hint', style: 'margin:0' }, '内网设备（10.0.0.0/8、172.16.0.0/12、192.168.0.0/16、10.10.10.10、回环地址、路由器自身地址）→ 永远 DIRECT，不进内核。'),
			E('div', { class: 'ep-hint', style: 'margin:0' }, '大陆域名/IP → 命中 geosite-cn / geoip-cn 后直连。'),
			E('div', { class: 'ep-hint', style: 'margin:0' }, '规则集缺失时按 fail_closed 生成纯直连配置：国外网站可能暂时打不开，但绝不会变成全局代理。'),
			E('div', { class: 'ep-hint', style: 'margin:0' }, '其它域名 → proxy 组（延迟测速选择）。')
		])
	]);
}

function nodeTable(nodes) {
	if (!nodes || !nodes.length)
		return E('div', { class: 'ep-hint', style: 'margin:0' }, '还没有节点。用「导入链接」粘一条 ss:// vmess:// vless:// trojan:// hysteria2:// 链接，或到订阅管理页拉一份订阅。');
	return E('table', { class: 'ep-tbl' }, [
		E('thead', {}, E('tr', {}, ['名称', '类型', '服务器', '区域', '分组', '状态', ''].map(function (h) { return E('th', {}, h); }))),
		E('tbody', {}, nodes.map(function (n) {
			return E('tr', {}, [
				E('td', {}, n.name || n.section),
				E('td', {}, n.type || '-'),
				E('td', {}, (n.server || '-') + ':' + (n.port || '')),
				E('td', {}, n.region || '-'),
				E('td', {}, n.group || '-'),
				E('td', {}, n.enabled ? E('span', { class: 'ep-ok' }, '启用') : E('span', { class: 'ep-off' }, '停用')),
				E('td', {}, [
					button('测速', '', function () {
						return cliJson(['node', 'test']).then(function (t) {
							if (!t)
								return notify('测速失败', 'error');
							var hit = (t.nodes || []).filter(function (x) { return x.section === n.section; })[0];
							notify(hit ? (hit.name + '：' + hit.state + (hit.latency_ms == null ? '' : ' ' + hit.latency_ms + ' ms')) : '未找到测速结果',
								hit && hit.state === 'reachable' ? 'success' : 'error');
						});
					}),
					button('删除', 'ep-danger', function () {
						if (!window.confirm('确定删除节点 ' + (n.name || n.section) + '？'))
							return;
						return run(['node', 'del', n.section]).then(function (r) {
							notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
							if (r.code === 0) reload();
						});
					})
				])
			]);
		}))
	]);
}

function pageNodes(data) {
	injectStyle();
	var list = data && data.list;
	if (!list)
		return E('div', { class: 'ep-wrap' }, errCard('无法读取节点列表。'));
	var groups = (list.groups || []).map(function (g) {
		return tag(g.label + '（' + g.nodes + '）', g.nodes > 0);
	});
	return E('div', { class: 'ep-wrap' }, [
		hero('节点管理', '导入、查看、测速、删除；区域按名称自动归组，生成 auto-hk / auto-us 等 urltest 组。'),
		card('节点分组', E('div', {}, groups.length ? groups : [E('span', { class: 'ep-hint' }, '暂无分组')])),
		card('节点列表', nodeTable(list.nodes), '区域由节点名称里的 hk/tw/jp/sg/us/uk/de/kr/ru 或中文地名推断。'),
		card('导入链接', [
			row('分享链接', textInput('ep-node-uri', '', 'ss:// / vmess:// / vless:// / trojan:// / hysteria2:// / tuic://'), '支持带 #名称 的完整链接'),
			row('名称（可选）', textInput('ep-node-name', '', '例如 hk-01')),
			button('导入', 'ep-primary', function () {
				var uri = valOf('ep-node-uri');
				var name = valOf('ep-node-name');
				if (!uri)
					return notify('请先粘贴分享链接', 'error');
				var args = ['node', 'add', uri];
				if (name) args.push(name);
				return run(args).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('从文件导入', '', function () {
				var path = window.prompt('路由器上的文件路径（每行一条链接）', '/tmp/nodes.txt');
				if (!path)
					return;
				return run(['node', 'import', path]).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('全部测速', '', function () {
				return run(['node', 'test']).then(function (r) {
					showOutput('节点测速', (r.stdout || '') + (r.stderr || ''));
				});
			})
		], '导入后点「重新生成配置」让内核用上新节点。')
	]);
}

function pageSubscription() {
	injectStyle();
	return E('div', { class: 'ep-wrap' }, [
		hero('订阅管理', '拉一份订阅到本地逐行导入；订阅地址不写入 UCI，也不写日志。'),
		card('从订阅地址导入', [
			row('订阅地址', textInput('ep-sub-url', '', 'https://example.com/sub?token=...'), '支持 base64 编码的 v2ray 订阅'),
			row('名称前缀（可选）', textInput('ep-sub-name', '', '例如 sub1')),
			button('拉取并导入', 'ep-primary', function () {
				var url = valOf('ep-sub-url');
				if (!url)
					return notify('请先填写订阅地址', 'error');
				var name = valOf('ep-sub-name');
				return run(['subscribe', url].concat(name ? [name] : [])).then(function (r) {
					ui.showModal('订阅导入结果', [
						E('pre', { class: 'ep-pre' }, ((r.stdout || '') + (r.stderr || '')).trim() || '(无输出)'),
						E('div', { class: 'right' }, [
							E('button', { class: 'btn', click: ui.hideModal }, '关闭'),
							E('button', { class: 'btn cbi-button-apply', click: function () { ui.hideModal(); reload(); } }, '刷新节点列表')
						])
					]);
					return r;
				}).catch(function (e) {
					notify('订阅拉取失败：' + e, 'error');
				});
			})
		], '订阅导入走 curl/wget + easyproxy node add，导入的节点可在节点管理里单独删除。'),
		card('网络受限时', E('div', { class: 'ep-hint', style: 'margin:0' }, '把订阅内容存成本地文件 /tmp/nodes.txt（一行一条），再在节点管理页用「从文件导入」。')),
		card('安全提醒', E('div', { class: 'ep-hint', style: 'margin:0' }, '订阅地址可能带账号令牌：脚本只把它当一次性参数，不写入 /etc/config/easyproxy，也不回显到日志。'))
	]);
}

function pageSplit(data) {
	injectStyle();
	var st = data && data.status;
	if (!st)
		return E('div', { class: 'ep-wrap' }, errCard('无法读取分流状态。'));
	var cfg = (data && data.cfg) || {};
	var split = st.route_mode === 'split';
	return E('div', { class: 'ep-wrap' }, [
		hero('智能分流', '大陆直连、平台专线走代理、内网永不出网；规则集缺失时整机退回直连。'),
		card('当前模式', [
			E('div', { class: 'ep-grid' }, [
				tile('分流模式', split ? '智能分流' : '仅直连', split ? 'ep-ok' : 'ep-warn'),
				tile('启用节点', String(st.nodes_enabled || 0), st.nodes_enabled > 0 ? 'ep-ok' : 'ep-warn'),
				tile('CN 规则集', st.rule_set_state === 'ready' ? '已就绪' : '缺失', st.rule_set_state === 'ready' ? 'ep-ok' : 'ep-bad'),
				tile('中国大陆', '直连（锁定）', 'ep-ok')
			]),
			E('div', { class: 'ep-hint', style: 'margin:0' }, split
				? '规则顺序：内网 → 节点服务器 → 自定义 → 平台 → geosite-cn/geoip-cn → 兜底 proxy。'
				: '失败闭合已锁死：规则集缺失或没有启用节点时，绝不生成全局代理，只直连。'),
			E('div', { class: 'ep-hint', style: 'margin:0' }, 'china_policy 恒为 direct，写 proxy 会被 validate 拒绝，不会生效。')
		]),
		card('平台规则', [
			row('YouTube', switchInput('ep-plat-youtube', cfg.youtube == '1')),
			row('Netflix', switchInput('ep-plat-netflix', cfg.netflix == '1')),
			row('TikTok', switchInput('ep-plat-tiktok', cfg.tiktok == '1')),
			button('保存', '', function () {
				return saveUci({
					'routing.platform_youtube': valOf('ep-plat-youtube'),
					'routing.platform_netflix': valOf('ep-plat-netflix'),
					'routing.platform_tiktok': valOf('ep-plat-tiktok')
				}).then(function () {
					notify('已保存，记得重新生成配置', 'success');
				}).catch(function (e) {
					notify('保存失败：' + e, 'error');
				});
			}),
			button('保存并重生成', 'ep-primary', function () {
				return saveUci({
					'routing.platform_youtube': valOf('ep-plat-youtube'),
					'routing.platform_netflix': valOf('ep-plat-netflix'),
					'routing.platform_tiktok': valOf('ep-plat-tiktok')
				}).then(function () { return run(['config', 'generate']); }).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				}).catch(function (e) {
					notify('保存失败：' + e, 'error');
				});
			})
		], '平台域名列表写在内核配置里，不依赖订阅，规则集缺失时也生效。'),
		card('内网保护（不可关闭）', [
			E('div', {}, [
				tag('10.0.0.0/8', true), tag('10.10.10.10', true), tag('172.16.0.0/12', true),
				tag('192.168.0.0/16', true), tag('127.0.0.0/8', true), tag('路由器自身地址', true)
			]),
			E('div', { class: 'ep-hint', style: 'margin:0' }, '这些网段命中 ip_is_private 与 lan 地址集合时一律直连，永不进内核；改 UCI 也关不掉。')
		]),
		card('自定义规则', E('div', { class: 'ep-hint', style: 'margin:0' }, '按顺序插在平台规则之前。到「规则管理」页维护。'))
	]);
}

function pageEngines(data) {
	injectStyle();
	var st = data && data.status;
	var health = data && data.health;
	var list = (data && data.list) || '';
	if (!st)
		return E('div', { class: 'ep-wrap' }, errCard('无法读取内核状态。'));
	var rows = list.split('\n').filter(function (l) { return l.trim().length; }).map(function (l) {
		return E('div', { class: 'ep-hint', style: 'margin:0' }, l.replace(/^\s+/, ''));
	});
	var items = ((health && health.checks) || []).map(function (c) {
		var cls = c.status === 'ok' ? 'ep-ok' : (c.status === 'warn' ? 'ep-warn' : 'ep-bad');
		return E('div', { class: 'ep-row' }, [
			E('span', { class: cls }, [E('span', { class: 'ep-dot' }), c.check]),
			E('span', { class: 'ep-hint', style: 'margin:0' }, c.detail)
		]);
	});
	return E('div', { class: 'ep-wrap' }, [
		hero('内核管理', 'sing-box 是稳定内核；dae 只保留适配器框架，标记开发中，启动会被拒绝。'),
		card('当前选择', [
			E('div', { class: 'ep-grid' }, [
				tile('内核', st.engine || '未选择', st.engine_dev == 1 ? 'ep-warn' : 'ep-ok'),
				tile('二进制', st.binary || '-', st.binary_ok == 1 ? 'ep-ok' : 'ep-bad'),
				tile('稳定性', st.engine_dev == 1 ? '开发中' : '稳定', st.engine_dev == 1 ? 'ep-warn' : 'ep-ok')
			]),
			row('切换内核', E('select', { id: 'ep-engine', class: 'ep-in' }, [
				E('option', { value: 'sing-box', selected: st.engine === 'sing-box' ? 'selected' : null }, 'sing-box（稳定）'),
				E('option', { value: 'dae', disabled: 'disabled', selected: st.engine === 'dae' ? 'selected' : null }, 'dae（开发中）'),
				E('option', { value: 'none', selected: st.engine === 'none' ? 'selected' : null }, '不选择')
			])),
			button('保存选择', 'ep-primary', function () {
				return saveEngine(valOf('ep-engine'));
			})
		], '切换内核后需要重新生成配置并重启服务。'),
		card('健康检查', items.length ? E('div', {}, items) : E('div', { class: 'ep-hint', style: 'margin:0' }, '未获取到检查结果'),
			(health && health.ok) ? '全部通过。' : '有失败项：按上面提示逐条处理。'),
		card('可用内核', E('div', {}, rows.length ? rows : [E('div', { class: 'ep-hint', style: 'margin:0' }, '未读取到内核列表')])),
		card('版本与复检', E('div', {}, [
			button('读取内核版本', '', function () {
				return run(['engine', 'version']).then(function (r) {
					showOutput('内核版本', (r.stdout || r.stderr || ''));
				});
			}),
			button('重新检查', '', function () {
				return run(['engine', 'health']).then(function (r) {
					showOutput('内核健康检查', (r.stdout || '') + (r.stderr || ''));
				});
			})
		]))
	]);
}

function pageDns(data) {
	injectStyle();
	var cfg = (data && data.cfg) || {};
	return E('div', { class: 'ep-wrap' }, [
		hero('DNS 设置', '大陆域名走本地解析器，其它域名走节点组内的 DoH；不做 fake-ip，避免内网地址被污染。'),
		card('解析器', [
			row('大陆 DNS', textInput('ep-dns-local', cfg.local || '223.5.5.5'), '默认 223.5.5.5'),
			row('远程 DoH', textInput('ep-dns-remote', cfg.remote || 'https://1.1.1.1/dns-query'), '只在走代理的域名上用它'),
			button('保存并重生成', 'ep-primary', function () {
				return saveUci({ 'routing.dns_local_server': valOf('ep-dns-local'), 'routing.dns_remote_server': valOf('ep-dns-remote') })
					.then(function () { return run(['config', 'generate']); })
					.then(function (r) {
						notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					}).catch(function (e) {
						notify('保存失败：' + e, 'error');
					});
			})
		], 'DNS 只影响内核内解析，路由器自身的 dnsmasq 不动。'),
		card('为什么不激进', [
			E('div', { class: 'ep-hint', style: 'margin:0' }, 'fake-ip 会让内网设备拿到假地址，内核一挂整网 DNS 就不可用，也会污染 10.10.10.10 这类内网地址。当前用规则集判断，不做 fake-ip。'),
			E('div', { class: 'ep-hint', style: 'margin:0' }, '失败闭合：规则集缺失时不会退回全局代理，DNS 也不会被强制绕路。')
		])
	]);
}

function pageRules(data) {
	injectStyle();
	var rules = (data && data.rules) || [];
	var rows = rules.map(function (r) {
		return E('tr', {}, [
			E('td', {}, String(r.index)),
			E('td', {}, r.type),
			E('td', {}, r.value),
			E('td', {}, r.outbound),
			E('td', {}, button('删除', 'ep-danger', function () {
				return run(['rule', 'del', String(r.index)]).then(function (x) {
					notify((x.stdout || x.stderr || '').trim(), x.code === 0 ? 'success' : 'error');
					if (x.code === 0) reload();
				});
			}))
		]);
	});
	return E('div', { class: 'ep-wrap' }, [
		hero('规则管理', '自定义规则按顺序插在平台规则之前；CN 规则集决定哪些流量直连。'),
		card('自定义规则', rules.length ? E('table', { class: 'ep-tbl' }, [
			E('thead', {}, E('tr', {}, ['#', '类型', '值', '出站', ''].map(function (h) { return E('th', {}, h); }))),
			E('tbody', {}, rows)
		]) : E('div', { class: 'ep-hint', style: 'margin:0' }, '还没有自定义规则。'), '类型：domain / domain-suffix / domain-keyword / ip-cidr；出站：direct / proxy / block。'),
		card('新增规则', [
			row('类型', E('select', { id: 'ep-rule-type', class: 'ep-in' }, [
				E('option', { value: 'domain' }, 'domain（精确域名）'),
				E('option', { value: 'domain-suffix' }, 'domain-suffix（域名后缀）'),
				E('option', { value: 'domain-keyword' }, 'domain-keyword（关键字）'),
				E('option', { value: 'ip-cidr' }, 'ip-cidr（IP 段）')
			])),
			row('值', textInput('ep-rule-value', '', 'example.com 或 203.0.113.0/24')),
			row('出站', E('select', { id: 'ep-rule-out', class: 'ep-in' }, [
				E('option', { value: 'proxy' }, 'proxy（走节点）'),
				E('option', { value: 'direct' }, 'direct（直连）'),
				E('option', { value: 'block' }, 'block（阻断）')
			])),
			button('添加', 'ep-primary', function () {
				var v = valOf('ep-rule-value');
				if (!v)
					return notify('请填写规则值', 'error');
				return run(['rule', 'add', valOf('ep-rule-type') + ':' + v + ':' + valOf('ep-rule-out')]).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		]),
		card('CN 规则集', E('div', {}, [
			button('更新规则集', 'ep-primary', function () {
				return run(['ruleset', 'update']).then(function (r) {
					showOutput('规则集更新', (r.stdout || '') + (r.stderr || ''));
				});
			}),
			button('完整性检查', '', function () {
				return run(['ruleset', 'verify']).then(function (r) {
					showOutput('规则完整性', (r.stdout || '') + (r.stderr || ''));
				});
			})
		]), '更新先下到临时文件再替换，失败保留旧文件；校验会检查 SRS 魔数与文件大小。')
	]);
}

function pageLogs(data) {
	injectStyle();
	return E('div', { class: 'ep-wrap' }, [
		hero('日志中心', '最近 40 行运行日志；错误也会写进这里，方便 SSH 对照排查。'),
		card('最近日志', [
			E('pre', { class: 'ep-pre' }, (data && data.log) || '暂无日志'),
			button('刷新', '', function () { reload(); }),
			button('轮转日志', '', function () {
				return run(['log', 'rotate']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('完整诊断', '', function () {
				return run(['doctor']).then(function (r) {
					showOutput('EasyProxy 诊断', (r.stdout || '') + (r.stderr || ''));
				});
			})
		], '日志文件 /var/log/easyproxy.log；超过 main.log_max_bytes 时轮转为 .1。')
	]);
}

function pageBackup(data) {
	injectStyle();
	var files = (data && data.files) || [];
	var dir = (data && data.dir) || '/etc/easyproxy/backups';
	var rows = files.map(function (f) {
		return E('tr', {}, [
			E('td', {}, f.name),
			E('td', {}, String(f.size || 0) + ' B'),
			E('td', {}, button('恢复', '', function () {
				if (!window.confirm('用 ' + f.name + ' 覆盖当前配置？旧配置保留为 .before-restore'))
					return;
				return run(['config', 'restore', dir + '/' + f.name]).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}))
		]);
	});
	return E('div', { class: 'ep-wrap' }, [
		hero('配置备份与恢复', '备份包含 /etc/config/easyproxy 与两份 CN 规则集，按时间戳命名。'),
		card('立即备份', [
			button('备份一次', 'ep-primary', function () {
				return run(['config', 'backup']).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('从文件恢复', '', function () {
				var p = window.prompt('备份文件完整路径', dir + '/easyproxy-YYYYmmdd-HHMMSS.tar.gz');
				if (!p)
					return;
				return run(['config', 'restore', p]).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		], '备份目录：' + dir),
		card('已有备份', files.length ? E('table', { class: 'ep-tbl' }, [
			E('thead', {}, E('tr', {}, ['文件', '大小', ''].map(function (h) { return E('th', {}, h); }))),
			E('tbody', {}, rows)
		]) : E('div', { class: 'ep-hint', style: 'margin:0' }, '还没有备份文件。')),
		card('一键恢复默认', E('div', {}, [
			button('恢复默认配置', 'ep-danger', function () {
				if (!window.confirm('把 /etc/config/easyproxy 重置为包内默认值？当前配置保留为 .before-reset'))
					return;
				return run(['config', 'reset']).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		]), '只重置 EasyProxy 自己的配置，不碰 ImmortalWrt 的 network/firewall/dhcp。')
	]);
}

function pageSettings(data) {
	injectStyle();
	var cfg = (data && data.cfg) || {};
	var doc = (data && data.doctor) || [];
	var docRows = doc.map(function (c) {
		var cls = c.status === 'ok' ? 'ep-ok' : (c.status === 'warn' ? 'ep-warn' : 'ep-bad');
		return E('div', { class: 'ep-row' }, [
			E('span', { class: cls }, [E('span', { class: 'ep-dot' }), c.check]),
			E('span', { class: 'ep-hint', style: 'margin:0' }, c.detail)
		]);
	});

	function collect() {
		return {
			'main.enabled': valOf('ep-enabled'),
			'main.listen': valOf('ep-listen'),
			'main.listen_port': valOf('ep-listen-port'),
			'main.log_level': valOf('ep-log-level'),
			'routing.probe_timeout': valOf('ep-probe'),
			'routing.rule_set_update_days': valOf('ep-update-days'),
			'transparent.enabled': valOf('ep-transparent'),
			'transparent.lan_interfaces': valOf('ep-lan-ifaces'),
			'transparent.tproxy_port': valOf('ep-tproxy-port'),
			'transparent.ipv6_policy': valOf('ep-ipv6')
		};
	}

	return E('div', { class: 'ep-wrap' }, [
		hero('系统设置', '开关、监听、透明代理与 IPv6 策略；保存会 uci commit，重启后仍生效。'),
		card('基本', [
			row('总开关', switchInput('ep-enabled', cfg.enabled == '1'), '0=停用，1=启用'),
			row('监听地址', textInput('ep-listen', cfg.listen || '127.0.0.1'), '默认只监听回环，由 tproxy 接 LAN'),
			row('监听端口', textInput('ep-listen-port', cfg.listen_port || '7890')),
			row('日志级别', E('select', { id: 'ep-log-level', class: 'ep-in' }, ['trace', 'debug', 'info', 'notice', 'warn', 'error'].map(function (l) {
				return E('option', { value: l, selected: (cfg.log_level || 'notice') === l ? 'selected' : null }, l);
			}))),
			row('探测超时（秒）', textInput('ep-probe', cfg.probe_timeout || '3')),
			row('规则集更新周期（天）', textInput('ep-update-days', cfg.rule_set_update_days || '7'))
		]),
		card('透明代理', [
			row('开启透明代理', switchInput('ep-transparent', cfg.transparent == '1'), '关闭时路由器不做任何 nftables 改写'),
			row('LAN 接口', textInput('ep-lan-ifaces', cfg.lan_ifaces || 'br-lan'), '多个用空格分隔'),
			row('tproxy 端口', textInput('ep-tproxy-port', cfg.tproxy_port || '7891')),
			row('内网流量', E('span', { class: 'ep-hint', style: 'margin:0' }, '始终 DIRECT（不可改）'), '内网、回环、路由器自身地址永不进内核')
		]),
		card('IPv6', [
			row('IPv6 策略', E('select', { id: 'ep-ipv6', class: 'ep-in' }, [
				E('option', { value: 'direct', selected: (cfg.ipv6_policy || 'direct') === 'direct' ? 'selected' : null }, 'direct（IPv6 不接管，直连）'),
				E('option', { value: 'block', selected: cfg.ipv6_policy === 'block' ? 'selected' : null }, 'block（阻断内网 IPv6，防绕过）')
			])),
			E('div', { class: 'ep-hint', style: 'margin:0' }, 'block 会丢弃不属于 fc00::/7、fe80::/10、::1/128、ff00::/8 与 LAN 链路上地址的 IPv6 流量；direct 完全不干预 IPv6。')
		]),
		card('保存', E('div', {}, [
			button('保存设置', 'ep-primary', function () {
				return saveUci(collect()).then(function () {
					notify('设置已保存（uci commit 完成）', 'success');
				}).catch(function (e) {
					notify('保存失败：' + e, 'error');
				});
			}),
			button('保存并重启服务', '', function () {
				return saveUci(collect()).then(function () { return run(['restart']); }).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				}).catch(function (e) {
					notify('失败：' + e, 'error');
				});
			})
		]), '保存只写 /etc/config/easyproxy，不碰 network、firewall、dhcp。'),
		card('系统自检', docRows.length ? E('div', {}, docRows) : E('div', { class: 'ep-hint', style: 'margin:0' }, '未获取到自检结果'),
			'覆盖版本、内核、配置、规则集、运行状态、监听、透明代理、IPv6、日志九类。'),
		card('卸载清理', E('div', {}, [
			button('仅清理自身规则', 'ep-danger', function () {
				if (!window.confirm('删除 EasyProxy 自己的 nft 表与 fwmark 规则？不影响系统防火墙。'))
					return;
				return run(['uninstall-clean']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
				});
			})
		]), '等价于 easyproxy uninstall-clean：只删 table ip easyproxy / ip6 easyproxy 与那条 ip rule。')
	]);
}

return {
	injectStyle: injectStyle,
	run: run,
	cliJson: cliJson,
	loadStatus: loadStatus,
	loadCfg: function () {
		uci.unload('easyproxy');
		return uci.load('easyproxy').then(function () {
			return {
				enabled: uci.get('easyproxy', 'main', 'enabled'),
				listen: uci.get('easyproxy', 'main', 'listen'),
				listen_port: uci.get('easyproxy', 'main', 'listen_port'),
				log_level: uci.get('easyproxy', 'main', 'log_level'),
				probe_timeout: uci.get('easyproxy', 'routing', 'probe_timeout'),
				rule_set_update_days: uci.get('easyproxy', 'routing', 'rule_set_update_days'),
				youtube: uci.get('easyproxy', 'routing', 'platform_youtube'),
				netflix: uci.get('easyproxy', 'routing', 'platform_netflix'),
				tiktok: uci.get('easyproxy', 'routing', 'platform_tiktok'),
				local: uci.get('easyproxy', 'routing', 'dns_local_server'),
				remote: uci.get('easyproxy', 'routing', 'dns_remote_server'),
				transparent: uci.get('easyproxy', 'transparent', 'enabled'),
				lan_ifaces: uci.get('easyproxy', 'transparent', 'lan_interfaces'),
				tproxy_port: uci.get('easyproxy', 'transparent', 'tproxy_port'),
				ipv6_policy: uci.get('easyproxy', 'transparent', 'ipv6_policy')
			};
		});
	},
	pageOverview: pageOverview,
	pageNodes: pageNodes,
	pageSubscription: pageSubscription,
	pageSplit: pageSplit,
	pageEngines: pageEngines,
	pageDns: pageDns,
	pageRules: pageRules,
	pageLogs: pageLogs,
	pageBackup: pageBackup,
	pageSettings: pageSettings
};

