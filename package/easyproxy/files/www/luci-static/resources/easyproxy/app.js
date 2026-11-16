'use strict';
'require fs';
'require uci';
'require ui';

var BIN = '/usr/sbin/easyproxy';
var TRAFFIC = '/usr/lib/easyproxy/traffic.sh';
var SUBSCRIBE = '/usr/lib/easyproxy/subscribe.sh';

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
'.ep-switch{appearance:none;width:38px;height:20px;background:#1b2a44;border-radius:999px;position:relative;cursor:pointer;transition:background .2s}',
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
		click: ui.createHandlerFn(this, function () {
			return handler();
		})
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
	if (!status)
		return 'ep-off';
	if (status === 'running' || status === 'active' || status === 'ready' || status === 'ok')
		return 'ep-ok';
	if (status === 'inactive' || status === 'off' || status === 'disabled')
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

/* ---------------------------------------------------------------- overview */

function trafficChart(status) {
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
		fs.exec('/bin/sh', [TRAFFIC]).then(function (r) {
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

function pageOverview(status) {
	injectStyle();
	if (!status)
		return E('div', { class: 'ep-wrap' }, [
			herrCard('无法读取 EasyProxy 状态：未安装或 /usr/sbin/easyproxy 不可执行。'),
			card('下一步', E('div', { class: 'ep-hint' }, '在路由器上执行 opkg list-installed | grep easyproxy 确认安装；opkg install <ipk> 重新安装后再回到本页刷新。'))
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
		tile('生成配置', status.config_state === 'ok' ? '校验通过' : status.config_state, status.config_state === 'ok' ? 'ep-ok' : 'ep-warn'),
		tile('内核状态下', status.engine_dev == 1 ? '开发中' : '稳定', status.engine_dev == 1 ? 'ep-warn' : 'ep-ok')
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
			button('开启/关闭透明代理', '', function () {
				return run(['transparent', status.tproxy_state === 'active' ? 'remove' : 'apply']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('自检', '', function () {
				return run(['doctor']).then(function (r) {
					ui.showModal('EasyProxy 自检', [
						E('pre', { class: 'ep-pre' }, (r.stdout || '') + (r.stderr || '')),
						E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))
					]);
				});
			})
		]),
		'所有操作都调用 easyproxy 命令行，面板不做隐式改写。'
	]);

	var chart = card('流量统计（' + (status.transparent == 1 ? 'LAN 接口' : 'br-lan') + '）', trafficChart(status), '每 2 秒采一次 /proc/net/dev，只显示速率，不写任何文件。');

	return E('div', { class: 'ep-wrap' }, [
		hero('EasyProxy 运行总览', '先用它确认四件事：内核在跑、规则集在、中国大陆直连、内网没被劫持。', tags),
		grid,
		actions,
		chart,
		card('结构说明', E('div', {}, [
			E('div', { class: 'ep-hint' }, '浏览器 → 路由面板：只走管理员通道。'),
			E('div', { class: 'ep-hint' }, '内网设备（10.0.0.0/8、172.16.0.0/12、192.168.0.0/16、回环地址、路由器自身地址）→ 永远 DIREC，不进入内核。'),
			E('div', { class: 'ep-hint' }, '大陆域名/IP → 命中 geosite-cn / geoip-cn 后直连；规则集缺失时按 fail_closed 生成纯直连配置，宁可国外网站暂时打不开，也不变成全局代理。'),
			E('div', { class: 'ep-hint' }, '其它域名 → proxy 组（延迟测速选择）。')
		]))
	]);
}

/* ------------------------------------------------------------------- nodes */

function nodeTable(nodes) {
	if (!nodes || !nodes.length)
		return E('div', { class: 'ep-hint' }, '还没有节点。用「导入链接」粘一条 ss:// vmess:// vless:// trojan:// hysteria2:// 链接，或在下面的订阅页拉一份订阅。');
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
							notify(hit ? (hit.name + '：' + hit.state + (hit.latency_ms == null ? '' : ' ' + hit.latency_ms + ' ms')) : '未找到测速结果', hit && hit.state === 'reachable' ? 'success' : 'error');
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
				if (!path) return;
				return run(['node', 'import', path]).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('全部测速', '', function () {
				return run(['node', 'test']).then(function (r) {
					ui.showModal('节点测速', [
						E('pre', { class: 'ep-pre' }, (r.stdout || '') + (r.stderr || '')),
						E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))
					]);
				});
			})
		], '导入后可点「重新生成配置」让内核用上新节点。')
	]);
}

/* -------------------------------------------------------------- subscription */

function pageSubscription() {
	injectStyle();
	return E('div', { class: 'ep-wrap' }, [
		hero('订阅管理', '拉一份订阅到本地逐行导入；订阅只存节点，不存你的订阅地址到日志。'),
		card('从订阅地址导入', [
			row('订阅地址', textInput('ep-sub-url', '', 'https://example.com/sub?token=...'), '支持 base64 编码的 v2ray 订阅'),
			row('名称前缀（可选）', textInput('ep-sub-name', '', '例如 sub1')),
			button('拉取并导入', 'ep-primary', function () {
				var url = valOf('ep-sub-url');
				if (!url)
					return notify('请先填写订阅地址', 'error');
				var name = valOf('ep-sub-name');
				var args = ['/bin/sh', [SUBSCRIBE, url].concat(name ? [name] : []).join('\\0')];
				return fs.exec('/bin/sh', [SUBSCRIBE, url].concat(name ? [name] : [])).then(function (r) {
					ui.showModal('订阅导入结果', [
						E('pre', { class: 'ep-pre' }, (r.stdout || '') + (r.stderr || '')),
						E('div', { class: 'right' }, [
							E('button', { class: 'btn', click: ui.hideModal }, '关闭'),
							E('button', { class: 'btn cbi-button-apply', click: function () { ui.hideModal(); reload(); } }, '刷新节点列表')
						])
					]);
					return r;
				});
			})
		], '订阅导入用的是 curl/wget + easyproxy node add，可随时在节点管理里单独删除。'),
		card('手动剪贴', E('div', { class: 'ep-hint' }, '网络受限时把订阅粘贴成本地文件 /tmp/nodes.txt（一行一条），再在节点管理页「从文件导入」。')),
		card('注意', E('div', { class: 'ep-hint' }, '订阅地址可能带账号令牌，脚本不会把它写进 /etc/config/easyproxy 或日志。'))
	]);
}

/* -------------------------------------------------------------------- split */

function pageSplit(data) {
	injectStyle();
	var st = data && data.status;
	if (!st)
		return E('div', { class: 'ep-wrap' }, errCard('无法读取分流状态。'));
	var cfg = data.cfg || {};
	var split = st.route_mode === 'split';
	return E('div', { class: 'ep-wrap' }, [
		hero('智能分流', '大陆直连、平台专线走代理、内网永不出网；规则集缺失时整机退回直连。'),
		card('当前模式', [
			tile(split ? '智能分流（大陆直连，其它代理）' : '仅直连（不代理任何流量）', '', split ? 'ep-ok' : 'ep-warn'),
			E('div', { class: 'ep-hint' }, split ? '规则顺序：内网 → 节点服务器 → 自定义 → 平台 → geosite-cn/geoip-cn → 兜底 proxy。' : '因为失败闭合锁死了：规则集缺失或没有启用节点时，绝不生成全局代理。'),
			E('div', { class: 'ep-hint' }, '中国大陆策略当前恒为 direct，自动生成。china_policy=proxy 会被拒绝，不会生效。')
		]),
		card('平台规则', [
			row('YouTube', switchInput('ep-plat-youtube', cfg.youtube == '1')),
			row('Netflix', switchInput('ep-plat-netflix', cfg.netflix == '1')),
			row('TikTok', switchInput('ep-plat-tiktok', cfg.tiktok == '1')),
			button('保存', 'ep-primary', function () {
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
				});
			})
		], '平台的域名列表写在内核配置里，不依赖订阅。'),
		card('内网保护（不可关闭）', E('div', {}, [
			tag('10.0.0.0/8', true), tag('172.16.0.0/12', true), tag('192.168.0.0/16', true), tag('127.0.0.0/8', true), tag('路由器自身地址', true), tag('内网 DNS/管理页面', true)
		]), '这些网段命中 ip_is_private 与 lan 地址集合时一律直连，永远不进内核；改 UCI 也关不掉。'),
		card('跳转', E('div', {}, [
			button('去规则管理', '', function () { window.location.href = '\'' + '\''; })
		]), '自定义规则请到「规则管理」页面维护。')
	]);
}

/* ------------------------------------------------------------------- engines */

function pageEngines(data) {
	injectStyle();
	var st = data && data.status;
	var health = data && data.health;
	var list = (data && data.list) || '';
	if (!st)
		return E('div', { class: 'ep-wrap' }, errCard('无法读取内核状态。'));
	var rows = list.split('\n').filter(function (l) { return l.trim().length; }).map(function (l) { return E('div', { class: 'ep-hint', style: 'margin:0' }, l.replace(/^\s+/, '')); });
	var items = (health && health.checks || []).map(function (c) {
		var cls = c.status === 'ok' ? 'ep-ok' : (c.status === 'warn' ? 'ep-warn' : 'ep-bad');
		return E('div', { class: 'ep-row' }, [
			E('span', { class: cls }, [E('span', { class: 'ep-dot' }), c.check]),
			E('span', { class: 'ep-hint', style: 'margin:0' }, c.detail)
		]);
	});
	return E('div', { class: 'ep-wrap' }, [
		hero('内核管理', 'sing-box 为稳定内核；dae 只保留适配器框架，标为开发中，启动会被拒绝。'),
		card('当前选择', [
			tile('内核', st.engine || '未选择', st.engine_dev == 1 ? 'ep-warn' : 'ep-ok'),
			tile('二进制', st.binary || '-', st.binary_ok == 1 ? 'ep-ok' : 'ep-bad'),
			tile('稳定性', st.engine_dev == 1 ? '开发中' : '稳定', st.engine_dev == 1 ? 'ep-warn' : 'ep-ok'),
			row('切换内核', E('select', { id: 'ep-engine', class: 'ep-in' }, [
				E('option', { value: 'sing-box', selected: st.engine === 'sing-box' ? 'selected' : null }, 'sing-box（稳定）'),
				E('option', { value: 'dae', selected: st.engine === 'dae' ? 'selected' : null }, 'dae（开发中）'),
				E('option', { value: 'none', selected: st.engine === 'none' ? 'selected' : null }, '不选择')
			])),
			button('保存选择', 'ep-primary', function () {
				return saveUci({ 'main.engine': valOf('ep-engine') }).then(function () {
					notify('已保存内核选择', 'success');
					reload();
				});
			}))
		], '切换内核后需要重新生成配置并重启。'),
		card('健康检查', items.length ? E('div', {}, items) : E('div', { class: 'ep-hint' }, '未获取到检查结果'), health && health.ok ? '全部通过' : '有失败项：按上面提示逐条处理。'),
		card('可用内核', E('div', {}, rows.length ? rows : [E('div', { class: 'ep-hint' }, '未读取到内核列表')])),
		card('版本', E('div', {}, [
			button('读取内核版本', '', function () {
				return run(['engine', 'version']).then(function (r) {
					ui.showModal('内核版本', [E('pre', { class: 'ep-pre' }, (r.stdout || r.stderr || '').trim()), E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))]);
				});
			})
		]))
	]);
}

/* ----------------------------------------------------------------------- dns */

function pageDns(data) {
	injectStyle();
	var cfg = (data && data.cfg) || {};
	return E('div', { class: 'ep-wrap' }, [
		hero('DNS 设置', '大陆域名走本地解析器，其它域名走节点组内的 DoH；不做 fake-ip，避免内网 DNS 被改写。'),
		card('解析器', [
			row('大陆 DNS', textInput('ep-dns-local', cfg.local || '223.5.5.5'), '默认 223.5.5.5'),
			row('远程 DoH', textInput('ep-dns-remote', cfg.remote || 'https://1.1.1.1/dns-query'), '只在走代理的域名上用它'),
			button('保存并重生成', 'ep-primary', function () {
				return saveUci({ 'routing.dns_local_server': valOf('ep-dns-local'), 'routing.dns_remote_server': valOf('ep-dns-remote') })
					.then(function () { return run(['config', 'generate']); })
					.then(function (r) {
						notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					});
			})
		], 'DNS 只影响内核内的解析；路由器自身的 dnsmasq 不动。'),
		card('为什么不激进', E('div', {}, [
			E('div', { class: 'ep-hint' }, 'fake-ip 会让内网设备拿到假地址，一旦内核挂了整网 DNS 就不可用，也会把 10.10.10.10 这类内网地址污染。当前实现用本地规则集判断，不做 fake-ip。'),
			E('div', { class: 'ep-hint' }, '失败闭合：规则集缺失时不会退回全局代理，DNS 也不会被强制绕路。')
		]))
	]);
}

/* --------------------------------------------------------------------- rules */

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
		]) : E('div', { class: 'ep-hint' }, '还没有自定义规则。'), '类型：domain / domain-suffix / domain-keyword / ip-cidr；出站：direct / proxy / block。'),
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
					ui.showModal('规则集更新', [E('pre', { class: 'ep-pre' }, (r.stdout || '') + (r.stderr || '')), E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))]);
				});
			}),
			button('完整性检查', '', function () {
				return run(['ruleset', 'verify']).then(function (r) {
					ui.showModal('规则完整性', [E('pre', { class: 'ep-pre' }, (r.stdout || '') + (r.stderr || '')), E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))]);
				});
			})
		]), '更新先下到临时文件再替换，失败保留旧文件；校验会检查 SRS 魔数与文件大小。')
	]);
}

/* ---------------------------------------------------------------------- logs */

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
					ui.showModal('EasyProxy 诊断', [E('pre', { class: 'ep-pre' }, (r.stdout || '') + (r.stderr || '')), E('div', { class: 'right' }, E('button', { class: 'btn', click: ui.hideModal }, '关闭'))]);
				});
			})
		], '日志文件 /var/log/easyproxy.log；超过 main.log_max_bytes 时轮转为 .1。')
	]);
}

/* -------------------------------------------------------------------- backup */

function pageBackup(data) {
	injectStyle();
	var files = (data && data.files) || [];
	var rows = files.map(function (f) {
		return E('tr', {}, [
			E('td', {}, f.name),
			E('td', {}, String(f.size || 0) + ' B'),
			E('td', {}, [
				button('恢复', '', function () {
					if (!window.confirm('用 ' + f.name + ' 覆盖当前配置？旧配置会保留为 .before-restore')) return;
					return run(['config', 'restore', (data.dir || '') + '/' + f.name]).then(function (r) {
						notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
						if (r.code === 0) reload();
					});
				})
			])
		]);
	});
	return E('div', { class: 'ep-wrap' }, [
		hero('配置备份与恢复', '备份内容包含 /etc/config/easyproxy 与两份 CN 规则集，路径时间戳命名。'),
		card('立即备份', [
			button('备份一次', 'ep-primary', function () {
				return run(['config', 'backup']).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			}),
			button('从文件干扰恢复', '', function () {
				var p = window.prompt('备份文件完整路径', (data.dir || '/etc/easyproxy/backups') + '/easyproxy-YYYYmmdd-HHMMSS.tar.gz');
				if (!p) return;
				return run(['config', 'restore', p]).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		], '备份目录：' + ((data && data.dir) || '/etc/easyproxy/backups')),
		card('已有备份', files.length ? E('table', { class: 'ep-tbl' }, [
			E('thead', {}, E('tr', {}, ['文件', '大小', ''].map(function (h) { return E('th', {}, h); }))),
			E('tbody', {}, rows)
		]) : E('div', { class: 'ep-hint' }, '还没有备份文件。')),
		card('一键恢复默认', E('div', {}, [
			button('恢复默认配置', 'ep-danger', function () {
				if (!window.confirm('将 /etc/config/easyproxy 重置为包内默认值？当前配置会保留为 .before-reset')) return;
				return run(['config', 'reset']).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		]), '只重置 EasyProxy 自己的配置，不碰 ImmortalWrt 的 network/firewall/dhcp。')
	]);
}

/* ------------------------------------------------------------------ settings */

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
	return E('div', { class: 'ep-wrap' }, [
		hero('系统设置', '开关、监听、透明代理与 IPv6 策略；改完保存会 uci commit，重启后仍生效。'),
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
			row('开启透明代理', switchInput('ep-transparent', cfg.transparent == '1'), '关闭时路由器不做任何 iptables/nftables 改写'),
			row('LAN 接口', textInput('ep-lan-ifaces', cfg.lan_ifaces || 'br-lan'), '多个用空格分隔'),
			row('tproxy 端口', textInput('ep-tproxy-port', cfg.tproxy_port || '7891')),
			row('局域网流路由方式（不可关）', E('span', { class: 'ep-hint', style: 'margin:0' }, 'DIRECT'),
				'内网、回环、路由器自身地址始终直连，不经过内核'),
		]),
		card('IPv6', [
			row('IPv6 策略', E('select', { id: 'ep-ipv6', class: 'ep-in' }, [
				E('option', { value: 'direct', selected: (cfg.ipv6_policy || 'direct') === 'direct' ? 'selected' : null }, 'direct（IPv6 不接管，直连）'),
				E('option', { value: 'block', selected: cfg.ipv6_policy === 'block' ? 'selected' : null }, 'block（阻断内网 IPv6，防绕过）')
			])),
			E('div', { class: 'ep-hint' }, 'block 会丢掉不属于 fc00::/7、fe80::/10、::1/128、ff00::/8 与 LAN 链路上地址的 IPv6 流量；direct 完全不干预 IPv6。')
		]),
		card('保存', E('div', {}, [
			button('保存设置', 'ep-primary', function () {
				return saveUci({
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
				}).then(function () {
					notify('设置已保存（uci commit 完成）', 'success');
				}).catch(function (e) {
					notify('保存失败：' + e, 'error');
				});
			}),
			button('保存并重启服务', '', function () {
				return saveUci({
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
				}).then(function () { return run(['restart']); }).then(function (r) {
					notify((r.stdout || r.stderr || '').trim(), r.code === 0 ? 'success' : 'error');
					if (r.code === 0) reload();
				});
			})
		]), '保存只写 /etc/config/easyproxy；不碰 network、firewall、dhcp。'),
		card('系统自检', docRows.length ? E('div', {}, docRows) : E('div', { class: 'ep-hint' }, '未获取到自检结果'), '覆盖版本、内核、配置、规则集、运行状态、监听、透明代理、IPv6、日志九类。'),
		card('卸载清理', E('div', {}, [
			button('仅清理自身规则', 'ep-danger', function () {
				if (!window.confirm('删除 EasyProxy 自己的 nft 表与 fwmark 规则？不影响系统防火墙。')) return;
				return run(['uninstall-clean']).then(function (r) {
					notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
				});
			})
		]), '等价于 easyproxy uninstall-clean；只删 table ip easyproxy / ip6 easyproxy 与那条 ip rule。')
	]);
}

return {
	injectStyle: injectStyle,
	run: run,
	cliJson: cliJson,
	loadStatus: loadStatus,
	loadCfg: function () {
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
