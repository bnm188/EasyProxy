'use strict';
'require fs';
'require easyproxy.ubus as ubus';
'require uci';
'require ui';
'require baseclass';

// The panel's only exec target is this CLI.
//
// fs.exec goes through ubus `file exec`, and rpcd-mod-file no longer
// exports that method on current OpenWrt/Kwrt images (only read / write /
// list / lstat), which made every button on this panel a no-op while the ACL
// and the CLI were both fine. The package therefore ships
// /usr/share/rpcd/ucode/luci.easyproxy.uc: an `easyproxy.run` ubus method that
// spawns only this binary, refuses unknown subcommands and shell-quotes every
// argument. `fs.exec` stays as the fallback for older images that still have
// `file exec`.
var BIN = '/usr/sbin/easyproxy';

var CSS = [
'.ep-wrap{position:relative;isolation:isolate;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans SC","Segoe UI",system-ui,sans-serif;color:#1b2229;padding:16px 16px 28px;border-radius:18px;background:linear-gradient(155deg,rgba(230,240,251,.96) 0%,rgba(234,242,247,.96) 30%,rgba(242,240,251,.96) 62%,rgba(248,243,236,.96) 100%)}',
'.ep-wrap::before{content:"";position:absolute;inset:0;border-radius:18px;pointer-events:none;background:radial-gradient(720px 460px at 4% 0%,rgba(56,132,232,.16),transparent 66%),radial-gradient(680px 420px at 100% 6%,rgba(38,196,214,.14),transparent 66%),radial-gradient(720px 460px at 96% 100%,rgba(255,168,124,.11),transparent 66%)}',
'.ep-wrap>*{position:relative;z-index:1}',
'.ep-hero{padding:16px 20px;border-radius:20px;border:1px solid rgba(255,255,255,.72);box-shadow:0 14px 38px rgba(22,60,110,.10),inset 0 1px 0 rgba(255,255,255,.9);background:rgba(255,255,255,.52);-webkit-backdrop-filter:blur(32px) saturate(180%);backdrop-filter:blur(32px) saturate(180%);margin-bottom:14px}',
'.ep-hero h2{margin:0 0 5px;font-size:22px;font-weight:650;letter-spacing:-.3px;color:#141c24}',
'.ep-hero .ep-sub{font-size:12.5px;color:#63727f;line-height:1.6}',
'.ep-hero-line{height:0;margin:0}',
'.ep-grid{display:grid;grid-template-columns:1fr;gap:1px;margin:0;background:rgba(120,150,190,.14);border-top:1px solid rgba(255,255,255,.5)}',
'@media(min-width:560px){.ep-grid{grid-template-columns:repeat(2,1fr)}}',
'@media(min-width:960px){.ep-grid{grid-template-columns:repeat(4,1fr)}}',
'.ep-tile{background:rgba(255,255,255,.44);padding:15px 17px;min-width:0;transition:background .2s}',
'.ep-tbl{width:100%;border-collapse:collapse;table-layout:fixed;font-size:12.5px}',
'.ep-tbl th,.ep-tbl td{padding:7px 9px;text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
'.ep-tbl thead th{font-weight:600;color:#5c6b78;border-bottom:1px solid rgba(120,150,190,.26)}',
'.ep-tbl tbody tr{border-bottom:1px solid rgba(120,150,190,.12)}',
'.ep-tbl tbody tr:hover{background:rgba(255,255,255,.5)}',
'.ep-tbl .ep-num{text-align:right;font-variant-numeric:tabular-nums}',
'.ep-mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}',
'.ep-kpi-inline{display:flex;flex-wrap:wrap;gap:8px 18px;font-size:12.5px;color:#41505c}',
'.ep-kpi-inline span{font-variant-numeric:tabular-nums}',
'.ep-kpi-inline .ep-muted{color:#8794a1;font-size:11.5px}',

'.ep-tile:hover{background:rgba(255,255,255,.62)}',
'.ep-tile .ep-lab{font-size:11.5px;color:#5e6d7d;letter-spacing:.02em;margin-bottom:7px}',
'.ep-tile .ep-val{font-size:22px;font-weight:600;letter-spacing:-.4px;color:#16202a;line-height:1.3;word-break:break-all}',
'.ep-card{background:rgba(255,255,255,.46);-webkit-backdrop-filter:blur(36px) saturate(180%);backdrop-filter:blur(36px) saturate(180%);border:1px solid rgba(255,255,255,.72);border-radius:20px;box-shadow:0 14px 38px rgba(22,60,110,.10),inset 0 1px 0 rgba(255,255,255,.9);padding:0;margin-bottom:14px;overflow:hidden}',
'.ep-card h3{margin:0;padding:13px 17px;font-size:13px;font-weight:600;letter-spacing:.01em;color:#2b3846;border-bottom:1px solid rgba(255,255,255,.52);background:rgba(255,255,255,.20)}',
'.ep-card>*:not(h3){margin-left:16px;margin-right:16px}',
'.ep-card>*:not(h3):first-child{margin-top:16px}',
'.ep-card>*:not(h3):last-child{margin-bottom:16px}',
'.ep-card .ep-hint{font-size:12px;color:#66737f;line-height:1.62}',
'.ep-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:7px;vertical-align:middle;box-shadow:0 0 0 3px rgba(255,255,255,.55)}',
'.ep-ok{color:#0b7a44}.ep-warn{color:#a86500}.ep-bad{color:#b0362d}.ep-off{color:#7e8c9b}',
'.ep-ok .ep-dot,.ep-warn .ep-dot{animation:epPulse 2.4s ease-in-out infinite}',
'@keyframes epPulse{0%,100%{opacity:.5}50%{opacity:1}}',
'@media (prefers-reduced-motion: reduce){.ep-ok .ep-dot,.ep-warn .ep-dot{animation:none}}',
'.ep-tbl{width:100%;border-collapse:collapse;font-size:13px;table-layout:fixed}',
'.ep-tbl th{text-align:left;color:#5e6d7d;font-weight:500;font-size:11.5px;padding:9px 17px;border-bottom:1px solid rgba(255,255,255,.55);background:rgba(255,255,255,.20)}',
'.ep-tbl td{padding:10px 17px;border-bottom:1px solid rgba(255,255,255,.5);color:#2b3846;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;word-break:break-all}',
'.ep-tbl tr:hover td{background:rgba(255,255,255,.42)}',
'.ep-btn{background:rgba(255,255,255,.86);border:1px solid rgba(255,255,255,.94);color:#22303d;border-radius:999px;padding:6px 15px;font-size:13px;cursor:pointer;margin:0 8px 8px 0;box-shadow:0 2px 10px rgba(22,60,110,.09);transition:background .18s,box-shadow .18s}',
'.ep-btn:hover{background:#fff;box-shadow:0 4px 16px rgba(22,60,110,.14)}',
'.ep-btn.ep-primary{background:linear-gradient(180deg,#0f8bff,#0a6ee0);border-color:transparent;color:#fff;box-shadow:0 6px 18px rgba(10,132,255,.30)}',
'.ep-btn.ep-primary:hover{filter:brightness(1.05)}',
'.ep-btn.ep-danger{background:rgba(255,255,255,.9);color:#c0342b;border-color:rgba(255,255,255,.94)}',
'.ep-in{background:rgba(255,255,255,.8);border:1px solid rgba(255,255,255,.95);color:#16202a;border-radius:12px;padding:7px 11px;font-size:13px;font-family:ui-monospace,Menlo,Consolas,monospace;min-width:130px;box-shadow:inset 0 1px 2px rgba(22,60,110,.06)}',
'.ep-in:focus{outline:none;border-color:#0f8bff;box-shadow:0 0 0 3px rgba(15,139,255,.16)}',
'.ep-row{display:flex;flex-wrap:wrap;align-items:center;gap:10px;padding:10px 0;font-size:13px;border-bottom:1px solid rgba(255,255,255,.42)}',
'.ep-row:last-child{border-bottom:0}',
'.ep-row label{min-width:180px;color:#4c5b6a}',
'.ep-pre{background:rgba(255,255,255,.62);border:1px solid rgba(255,255,255,.9);border-radius:14px;padding:12px 14px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:#2b3846;white-space:pre-wrap;max-height:320px;overflow:auto;line-height:1.62}',
'.ep-tag{display:inline-block;padding:3px 10px;border-radius:999px;font-size:11.5px;margin:2px 5px 2px 0;border:1px solid rgba(255,255,255,.9);background:rgba(255,255,255,.6);color:#4c5b6a}',
'.ep-tag.ep-hit{border-color:#0f8bff;color:#0b63c5;background:rgba(15,139,255,.10)}',
'.ep-chart{width:100%;height:150px;display:block;background:rgba(255,255,255,.6);border:1px solid rgba(255,255,255,.9);border-radius:14px}',
'.ep-err{background:rgba(255,243,242,.66);border:1px solid rgba(255,255,255,.8);border-left:3px solid #c0342b;color:#8d2b23;border-radius:14px;padding:13px 16px;font-size:13px;margin-bottom:14px;-webkit-backdrop-filter:blur(24px);backdrop-filter:blur(24px);box-shadow:0 8px 24px rgba(150,40,30,.08)}',
'.ep-switch{appearance:none;-webkit-appearance:none;width:44px;height:26px;background:rgba(120,140,165,.32);border-radius:999px;position:relative;cursor:pointer;transition:background .2s;border:none;flex:0 0 44px}',
'.ep-switch:checked{background:#0a84ff}',
'.ep-switch:after{content:"";position:absolute;top:2px;left:2px;width:22px;height:22px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.18);transition:left .2s}',
'.ep-switch:checked:after{left:20px}',
'.ep-stack>.ep-wrap{padding:0;background:none;border-radius:0}',
'.ep-stack>.ep-wrap::before{display:none}',
'.ep-stack>.ep-wrap>.ep-hero{padding:6px 4px 10px;background:none;border:0;box-shadow:none;-webkit-backdrop-filter:none;backdrop-filter:none}',
'.ep-stack>.ep-wrap>.ep-hero h2{font-size:16px;color:#2b3846}',
'.ep-stack>.ep-wrap>*{margin-bottom:12px}',
'@media (prefers-reduced-transparency: reduce){.ep-card,.ep-hero,.ep-tile{background:#fff;-webkit-backdrop-filter:none;backdrop-filter:none}}',
'.ep-subnav{display:flex;gap:8px;flex-wrap:wrap;margin:2px 2px 14px}',
'.ep-tabs .ep-tab{background:rgba(255,255,255,.52);border:1px solid rgba(255,255,255,.8);color:#41505f;border-radius:999px;padding:6px 15px;font-size:12.5px;cursor:pointer;margin:0 8px 8px 0;box-shadow:none;transition:background .18s,color .18s}',
'.ep-tabs .ep-tab:hover{background:#fff;color:#16202a}',
'.ep-tabs .ep-tab.on{background:linear-gradient(180deg,#0f8bff,#0a6ee0);color:#fff;border-color:transparent;box-shadow:0 6px 16px rgba(10,132,255,.26)}',
'.ep-kpis{display:grid;grid-template-columns:1fr;gap:12px;margin-bottom:14px}',
'@media(min-width:700px){.ep-kpis{grid-template-columns:repeat(2,1fr)}}',
'@media(min-width:1040px){.ep-kpis{grid-template-columns:repeat(4,1fr)}}',
'.ep-kpi{background:rgba(255,255,255,.46);-webkit-backdrop-filter:blur(36px) saturate(180%);backdrop-filter:blur(36px) saturate(180%);border:1px solid rgba(255,255,255,.72);border-radius:18px;box-shadow:0 12px 32px rgba(22,60,110,.09),inset 0 1px 0 rgba(255,255,255,.9);padding:14px 16px;min-width:0}',
'.ep-kpi .ep-lab{font-size:11.5px;color:#5e6d7d;margin-bottom:6px}',
'.ep-kpi .ep-val{font-size:21px;font-weight:600;letter-spacing:-.4px;color:#16202a;line-height:1.25;word-break:break-all}',
'.ep-kpi .ep-lab2{font-size:10.5px;color:#8494a6;margin-top:5px;font-family:ui-monospace,Menlo,Consolas,monospace}',
'.ep-bar{height:4px;background:rgba(120,145,175,.18);border-radius:99px;margin-top:10px;overflow:hidden}',
'.ep-bar-in{height:100%;width:0;border-radius:99px;background-color:#22c55e;transition:width .85s cubic-bezier(.2,.8,.2,1),background-color .3s linear}',
'.ep-clock{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin:0 0 12px;font-size:12px;color:#4c5b6a}',
'.ep-clock b{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:15px;color:#16202a;letter-spacing:.4px}',
'.ep-clock .ep-dot-live{width:7px;height:7px;border-radius:50%;background:#0f8bff;display:inline-block;box-shadow:0 0 0 3px rgba(15,139,255,.16)}',
'.ep-pw{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end}',
'.ep-pw .ep-in{min-width:180px}',
'@media (prefers-reduced-transparency: reduce){.ep-kpi{background:#fff;-webkit-backdrop-filter:none;backdrop-filter:none}}'
].join('\n');

function injectStyle() {
	if (typeof document === 'undefined' || document.getElementById('ep-glass-style'))
		return;
	document.head.appendChild(E('style', { id: 'ep-glass-style', type: 'text/css' }, CSS));
}

function notify(text, level) {
	ui.addNotification(null, E('p', {}, text), level || 'info');
}

function run(args) {
	function viaExec() {
		return fs.exec(BIN, args).catch(function (e) {
			return { code: -1, stdout: '', stderr: String((e && e.message) || e) };
		});
	}

	return ubus.call('easyproxy', 'run', { payload: JSON.stringify(args) }).then(function (r) {
		if (r && typeof r.code !== 'undefined')
			return { code: r.code, stdout: r.stdout || '', stderr: r.stderr || '' };
		return viaExec();
	}).catch(viaExec);
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
			if (!d) {
				cap.textContent = '流量采样失败：返回内容无法解析';
				return;
			}
			if (!d.ok) {
				// A missing interface used to draw a flat zero line, which reads
				// like "no traffic" instead of "this interface does not exist".
				cap.textContent = '流量采样失败：网卡 ' + (d.iface || '?') + ' 不存在';
				last = null;
				return;
			}
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


/* ===== 子导航：页内二级目录 ===== */
function tabs(items) {
	var cur = 0;
	var btns = [];
	var panels = [];
	var nav = E('div', { class: 'ep-subnav' });

	items.forEach(function (it, i) {
		var b = E('button', {
			class: 'ep-tab' + (i === 0 ? ' on' : ''),
			type: 'button',
			click: function (ev) {
				if (ev && ev.preventDefault) ev.preventDefault();
				cur = i;
				apply();
			}
		}, it[1]);
		btns.push(b);
		nav.appendChild(b);

		var panel = E('div', { class: 'ep-panel' }, it[2]);
		if (i > 0) panel.style.display = 'none';
		panels.push(panel);
	});

	function apply() {
		btns.forEach(function (b, i) { b.classList.toggle('on', i === cur); });
		panels.forEach(function (p, i) { p.style.display = (i === cur) ? '' : 'none'; });
	}

	return E('div', { class: 'ep-tabs' }, [nav, E('div', { class: 'ep-subbody' }, panels)]);
}

/* ===== 北京时间时钟 ===== */
function clockBar() {
	var time = E('b', {}, '--:--:--');
	var dateEl = E('span', {}, '');

	function tick() {
		try {
			var now = new Date();
			var opt = { timeZone: 'Asia/Shanghai', hour12: false };
			time.textContent = now.toLocaleTimeString('zh-CN', {
				timeZone: 'Asia/Shanghai', hour12: false,
				hour: '2-digit', minute: '2-digit', second: '2-digit'
			});
			dateEl.textContent = '· ' + now.toLocaleDateString('zh-CN', {
				timeZone: 'Asia/Shanghai',
				year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short'
			}).replace(/\//g, '-');
			if (opt) return;
		} catch (e) {
			time.textContent = new Date().toTimeString().slice(0, 8);
		}
	}
	tick();
	window.setInterval(tick, 1000);

	return E('div', { class: 'ep-clock' }, [
		E('span', { class: 'ep-dot-live' }, ''),
		E('span', {}, '当前时间'), time, dateEl
	]);
}

/* ===== 实时硬件与流量（真实 /proc 采样） ===== */
function kpiLive(status) {
	var cpuVal = E('div', { class: 'ep-val' }, '—');
	var cpuSub = E('div', { class: 'ep-lab2' }, '');
	var cpuBar = E('div', { class: 'ep-bar-in' });
	var cpuBox = E('div', { class: 'ep-kpi' }, [
		E('div', { class: 'ep-lab' }, 'CPU 使用'), cpuVal, cpuSub,
		E('div', { class: 'ep-bar' }, cpuBar)
	]);

	var memVal = E('div', { class: 'ep-val' }, '—');
	var memSub = E('div', { class: 'ep-lab2' }, '');
	var memBar = E('div', { class: 'ep-bar-in' });
	var memBox = E('div', { class: 'ep-kpi' }, [
		E('div', { class: 'ep-lab' }, '内存'), memVal, memSub,
		E('div', { class: 'ep-bar' }, memBar)
	]);

	var rxVal = E('div', { class: 'ep-val' }, '—');
	var rxSub = E('div', { class: 'ep-lab2' }, '');
	var rxBar = E('div', { class: 'ep-bar-in' });
	var rxBox = E('div', { class: 'ep-kpi' }, [
		E('div', { class: 'ep-lab' }, '实时下行'), rxVal, rxSub,
		E('div', { class: 'ep-bar' }, rxBar)
	]);

	var txVal = E('div', { class: 'ep-val' }, '—');
	var txSub = E('div', { class: 'ep-lab2' }, '');
	var txBar = E('div', { class: 'ep-bar-in' });
	var txBox = E('div', { class: 'ep-kpi' }, [
		E('div', { class: 'ep-lab' }, '实时上行'), txVal, txSub,
		E('div', { class: 'ep-bar' }, txBar)
	]);

	var K = {
		cpu: { val: cpuVal, sub: cpuSub, bar: cpuBar },
		mem: { val: memVal, sub: memSub, bar: memBar },
		rx: { val: rxVal, sub: rxSub, bar: rxBar },
		tx: { val: txVal, sub: txSub, bar: txBar }
	};

	var cpuPrev = null, netPrev = null, sessionRx = 0, sessionTx = 0;

	function setBar(node, pct, color) {
		pct = Math.max(0, Math.min(100, pct));
		node.bar.style.width = pct.toFixed(1) + '%';
		if (color) node.bar.style.backgroundColor = color;
	}

	function fmtBytes(v) {
		if (v >= 1073741824) return (v / 1073741824).toFixed(2) + ' GB';
		if (v >= 1048576) return (v / 1048576).toFixed(1) + ' MB';
		if (v >= 1024) return (v / 1024).toFixed(0) + ' KB';
		return v + ' B';
	}

	function sample() {
		Promise.all([
			fs.read('/proc/stat').catch(function () { return null; }),
			fs.read('/proc/meminfo').catch(function () { return null; }),
			fs.read('/proc/net/dev').catch(function () { return null; })
		]).then(function (r) {
			var line = r[0] ? String(r[0]).split('\n')[0] : '';
			var m = /^cpu\s+(.+)$/.exec(line);
			if (m) {
				var parts = m[1].trim().split(/\s+/).map(Number);
				var idle = (parts[3] || 0) + (parts[4] || 0);
				var total = 0;
				parts.forEach(function (x) { total += x; });
				if (cpuPrev) {
					var dt = total - cpuPrev.total, di = idle - cpuPrev.idle;
					if (dt > 0) {
						var used = Math.max(0, Math.min(100, 100 * (dt - di) / dt));
						cpuVal.textContent = used.toFixed(0) + '%';
						cpuSub.textContent = '核数 ' + (navigator.hardwareConcurrency || 1) + ' · 采样 1.5s';
						setBar(K.cpu, used, used < 50 ? '#22c55e' : (used <= 80 ? '#f59e0b' : '#ef4444'));
					}
				}
				cpuPrev = { idle: idle, total: total };
			}

			if (r[1]) {
				var t = /MemTotal:\s+(\d+)/.exec(r[1]);
				var a = /MemAvailable:\s+(\d+)/.exec(r[1]);
				if (t) {
					var totalMb = (+t[1]) / 1024;
					var availMb = a ? (+a[1]) / 1024 : 0;
					var usedMb = totalMb - availMb;
					memVal.textContent = usedMb.toFixed(0) + ' MB';
					memSub.textContent = (totalMb ? (usedMb / totalMb * 100).toFixed(0) : '0') + '% · 共 ' + totalMb.toFixed(0) + ' MB';
					setBar(K.mem, totalMb ? usedMb / totalMb * 100 : 0, '#22c55e');
				}
			}

			if (r[2]) {
				var sum = { rx: 0, tx: 0 };
				String(r[2]).split('\n').slice(2).forEach(function (l) {
					var mm = /^\s*([^:]+):\s*(\d+)(?:\s+\d+){6}\s+(\d+)/.exec(l);
					if (!mm || mm[1].trim() === 'lo') return;
					sum.rx += +mm[2];
					sum.tx += +mm[3];
				});
				if (netPrev) {
					var drx = Math.max(0, sum.rx - netPrev.rx);
					var dtx = Math.max(0, sum.tx - netPrev.tx);
					sessionRx += drx; sessionTx += dtx;
					var rateRx = drx / 1.5, rateTx = dtx / 1.5;
					rxVal.textContent = fmtBytes(rateRx) + '/s';
					txVal.textContent = fmtBytes(rateTx) + '/s';
					rxSub.textContent = '会话累计 ' + fmtBytes(sessionRx);
					txSub.textContent = '会话累计 ' + fmtBytes(sessionTx);
					setBar(K.rx, Math.min(100, rateRx / 1048576 * 25), '#22c55e');
					setBar(K.tx, Math.min(100, rateTx / 1048576 * 25), '#22c55');
				}
				netPrev = sum;
			}
		}).catch(function () {});
	}

	sample();
	window.setInterval(sample, 1500);

	return E('div', { class: 'ep-kpis' }, [cpuBox, memBox, rxBox, txBox]);
}

/* ===== 管理密码 ===== */
function pageSafety() {
	var p1 = textInput('ep-pw-new', '', '新管理密码（至少 8 位）');
	p1.type = 'password';
	var p2 = textInput('ep-pw-rep', '', '再输入一次');
	p2.type = 'password';

	var body = [
		E('div', { class: 'ep-hint', style: 'margin:0 0 10px' }, '管理密码用于进入本面板；密码以 600 权限存放在 /etc/easyproxy/auth，不上传、不写入节点配置。'),
		E('div', { class: 'ep-pw' }, [p1, p2,
			button('保存密码', 'ep-primary', function () {
				var a = (valOf('ep-pw-new') || ''), b = (valOf('ep-pw-rep') || '');
				if (a.length < 8) { notify('密码至少 8 位', 'error'); return; }
				if (a !== b) { notify('两次输入的密码不一致', 'error'); return; }
				return run(['auth', 'set', a]).then(function (r) {
					var ok = r.code === 0;
					notify(ok ? '管理密码已更新' : ((r.stderr || r.stdout || '设置失败').trim()), ok ? 'success' : 'error');
					if (ok) { p1.value = ''; p2.value = ''; }
				});
			})
		]),
		E('div', { class: 'ep-hint', style: 'margin-top:10px' }, '需要 easyproxy auth set（0.8.14 起由后端提供）；当前版本执行会在下方回显中提示未支持。')
	];

	return card('管理密码', body);
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
					button(n.enabled ? '停用' : '启用', n.enabled ? '' : 'ep-primary', function () {
						return run(['node', n.enabled ? 'disable' : 'enable', n.section]).then(function (r) {
							notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
							if (r.code === 0) reload();
						});
					}),
					button('导出', '', function () {
						return run(['node', 'export', n.section]).then(function (r) {
							if (r.code !== 0)
								return notify((r.stderr || r.stdout || '导出失败').trim(), 'error');
							// 分享链接很长，用可复制的输入框而不是 toast
							window.prompt('分享链接（Ctrl+C 复制）', (r.stdout || '').trim());
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
		hero('订阅管理', '拉一份订阅到本地逐行导入，同一端点只会存在一次；订阅地址不写入 UCI，也不写日志。'),
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
		card('每日自动更新', [
			E('div', { class: 'ep-hint', style: 'margin:0' }, '记住这份订阅地址，每天 04:37 重跑一次：只补新增节点，已有端点直接跳过，不会重复建节点。'),
			E('div', { class: 'ep-row' }, [
				button('立即按记住的地址更新', '', function () {
					return run(['subscribe', '--update']).then(function (r) {
						ui.showModal('增量更新结果', [
							E('pre', { class: 'ep-pre' }, ((r.stdout || '') + (r.stderr || '')).trim() || '(无输出)'),
							E('div', { class: 'right' }, [
								E('button', { class: 'btn', click: ui.hideModal }, '关闭'),
								E('button', { class: 'btn cbi-button-apply', click: function () { ui.hideModal(); reload(); } }, '刷新节点列表')
							])
						]);
						return r;
					});
				}),
				button('开启每日更新', '', function () {
					return run(['subscribe', '--daily', 'on']).then(function (r) {
						notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					});
				}),
				button('关闭每日更新', 'ep-danger', function () {
					return run(['subscribe', '--daily', 'off']).then(function (r) {
						notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					});
				}),
				button('忘记此订阅', 'ep-danger', function () {
					if (!window.confirm('清除记住的订阅地址？节点本身不会被删除。'))
						return;
					return run(['subscribe', '--forget']).then(function (r) {
						notify((r.stdout || r.stderr || 'done').trim(), r.code === 0 ? 'success' : 'error');
					});
				})
			])
		], '订阅地址含令牌，只存在 /etc/easyproxy/subscribe.conf（权限 600），不进 UCI、不进诊断包。'),
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
		], '日志文件 /var/log/easyproxy.log；超过 main.log_max_bytes 时轮转为 .1。'),
		card('诊断上报', [
			row('客户编号', textInput('ep-cust-id', '', '例如 001，按交付顺序分配'), '决定日志传到 diagnostics/ 下的哪个目录；只写本机，不进 UCI。'),
			button('保存编号', '', function () {
				var id = (valOf('ep-cust-id') || '').trim();
				if (!id)
					return notify('先填编号，例如 001', 'error');
				return run(['diag', '--set-id', id]).then(function (r) {
					notify(((r.stdout || '') + (r.stderr || '')).trim(), r.code === 0 ? 'success' : 'error');
				});
			}),
			row('每天 03:17 自动上报', switchInput('ep-diag-daily', false), '开：本机每天自动传一份脱敏日志；关：只在点「立即上报」时传。'),
			button('保存自动上报', '', function () {
				var on = valOf('ep-diag-daily') === '1';
				return run(['diag', '--daily', on ? 'on' : 'off']).then(function (r) {
					notify(((r.stdout || '') + (r.stderr || '')).trim(), r.code === 0 ? 'success' : 'error');
				});
			}),
			button('立即上报', 'ep-primary', function () {
				return run(['diag', '--upload']).then(function (r) {
					showOutput('诊断上报结果', (r.stdout || '') + (r.stderr || ''));
				});
			})
		], '脱敏在路由器上完成：节点链接、订阅 token、UUID、JSON 里的密码都会先打码再上传。仓库是私有的，只有持有 token 的账号能读。')
	]);
}

function pageUpdate(data) {
	injectStyle();
	var st = (data && data.status) || {};
	var cur = st.version || 'unknown';
	var repo = 'bnm188/EasyProxy';

	function setInfo(txt) {
		var el = document.getElementById('ep-up-info');
		if (!el)
			return;
		while (el.firstChild)
			el.removeChild(el.firstChild);
		el.appendChild(E('pre', { class: 'ep-pre' }, txt));
	}

	return E('div', { class: 'ep-wrap' }, [
		hero('版本更新', '检查新版本并直接安装；升级前自动备份当前程序，失败自动回滚。', [
			E('span', { class: 'ep-tag' }, 'v' + cur),
			E('span', { class: 'ep-tag' }, '通道 stable')
		]),
		card('当前状态', [
			E('div', { class: 'ep-grid' }, [
				tile('当前版本', 'v' + cur, 'ep-ok'),
				tile('最新版本', '点「检查更新」获取', 'ep-off'),
				tile('可升级', '未知', 'ep-off'),
				tile('回滚包', '读取中…', 'ep-off')
			]),
			E('div', { id: 'ep-up-info' }, E('pre', { class: 'ep-pre' }, '尚未检查。点下面的按钮向 GitHub 查询最新版本。'))
		], '只对比版本号，不上传任何本机信息。'),
		card('操作', [
			button('检查更新', '', function () {
				setInfo('正在查询 GitHub…');
				return cliJson(['update', 'check']).then(function (r) {
					if (!r) {
						setInfo('无法读取 Release 信息。常见原因：路由器访问不了 api.github.com。\n改用 SSH 手动升级：easyproxy update apply');
						return notify('检查更新失败', 'error');
					}
					setInfo('当前 v' + r.current + ' / 最新 v' + r.latest
						+ (r.available ? '\n可升级到 v' + r.latest : '\n已是最新版本'));
					notify(r.available ? ('有新版本 v' + r.latest) : '已是最新版本',
						r.available ? 'warning' : 'success');
				});
			}),
			button('立即更新', 'ep-primary', function () {
				if (!window.confirm('将下载并安装最新版本。\n\n· 升级前自动备份当前程序\n· 只替换程序文件，节点/配置/日志不动\n· 面板会重启，本页会断开约 10-20 秒\n\n确认现在升级？'))
					return;
				setInfo('正在下载并校验，请勿关闭页面…');
				return run(['update', 'apply']).then(function (r) {
					var text = ((r.stdout || '') + (r.stderr || '')).trim() || '(无输出)';
					setInfo(text);
					showOutput(r.code === 0 ? '升级完成' : '升级失败（已检查回滚）', text);
					if (r.code === 0)
						notify('升级完成，刷新页面查看新版本', 'success');
					else
						notify('升级失败，详见弹窗', 'error');
				});
			}),
			button('查看更新说明', '', function () {
				window.open('https://github.com/' + repo + '/releases', '_blank');
			}),
			button('回滚到上一版', 'ep-danger', function () {
				if (!window.confirm('用最近一次备份覆盖当前程序？只在升级出问题时使用。'))
					return;
				return run(['update', 'rollback']).then(function (r) {
					showOutput('回滚结果', ((r.stdout || '') + (r.stderr || '')).trim());
					notify(r.code === 0 ? '已回滚，刷新页面' : '回滚失败', r.code === 0 ? 'success' : 'error');
				});
			})
		], '升级走 GitHub Releases 资产，先校验 SHA256 再解包；校验不过不动任何文件。'),
		card('安全说明', E('div', { class: 'ep-hint', style: 'margin:0' },
			'① 下载后先比对 SHA256SUMS，不符直接中止；'
			+ '② 覆盖前把当前程序打包到 /etc/easyproxy/backups/，只保留最近一份；'
			+ '③ 装完检查面板文件与 CLI 版本，任一不对就自动还原；'
			+ '④ /etc/config/easyproxy 与 /etc/easyproxy/（节点、规则集、token）全程不碰。'))
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

function pageConn(data) {
	injectStyle();
	var cfg = (data && data.cfg) || {};

	function collect() {
		return {
			'main.enabled': valOf('ep-enabled'),
			'main.listen': valOf('ep-listen'),
			'main.listen_port': valOf('ep-listen-port'),
			'transparent.enabled': valOf('ep-transparent'),
			'transparent.lan_interfaces': valOf('ep-lan-ifaces'),
			'transparent.tproxy_port': valOf('ep-tproxy-port'),
			'transparent.ipv6_policy': valOf('ep-ipv6')
		};
	}

	return E('div', { class: 'ep-wrap' }, [
		hero('连接', '总开关、监听入口、透明代理与 IPv6 策略；保存会 uci commit，重启后仍生效。'),
		card('入口', [
			row('总开关', switchInput('ep-enabled', cfg.enabled == '1'), '0=停用，1=启用'),
			row('监听地址', textInput('ep-listen', cfg.listen || '127.0.0.1'), '默认只监听回环，由 tproxy 接 LAN'),
			row('监听端口', textInput('ep-listen-port', cfg.listen_port || '7890'), 'HTTP/SOCKS 混合入站')
		], '面板的启停按钮走 /etc/init.d/easyproxy，这里的总开关只控制开机自启时的状态。'),
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
			]))
		], 'block 会丢弃不属于 fc00::/7、fe80::/10、::1/128、ff00::/8 与 LAN 链路上地址的 IPv6 流量；direct 完全不干预 IPv6。'),
		card('保存', E('div', {}, [
			button('保存', 'ep-primary', function () {
				return saveUci(collect()).then(function () {
					notify('连接设置已保存（uci commit 完成）', 'success');
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
		]), '保存只写 /etc/config/easyproxy，不碰 network、firewall、dhcp。')
	]);
}

// Live connections come from mihomo's Clash API through the CLI. They are the
// only place the panel can show what a flow actually used: which node carried
// it, where it came from, how long it has been open. sing-box offers no
// equivalent, so the page has to say that plainly instead of showing an empty
// table that looks like a bug.
function liveConnections() {
	return cliJson(['connections']).catch(function () {
		return { ok: false, error: '无法读取连接列表' };
	});
}

function fmtBytes(n) {
	n = Number(n) || 0;
	if (n < 1024) return n + ' B';
	if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
	if (n < 1073741824) return (n / 1048576).toFixed(1) + ' MB';
	return (n / 1073741824).toFixed(2) + ' GB';
}

function fmtDuration(ms) {
	if (ms == null) return '\u2014';
	var sec = Math.round(Number(ms) / 1000);
	if (!(sec >= 0)) return '\u2014';
	if (sec < 60) return sec + 's';
	var min = Math.floor(sec / 60);
	if (min < 60) return min + 'm' + (sec % 60 ? (sec % 60) + 's' : '');
	return Math.floor(min / 60) + 'h' + (min % 60 ? (min % 60) + 'm' : '');
}

function connRows(list) {
	if (!list || !list.length)
		return [E('tr', {}, [E('td', { colspan: '6', class: 'ep-hint', style: 'margin:0' }, '当前没有活动连接')])];
	var out = [];
	list.forEach(function (c) {
		out.push(E('tr', {}, [
			E('td', { class: 'ep-mono', title: c.host || '' }, c.host || '\u2014'),
			E('td', { class: 'ep-mono' }, c.source || '\u2014'),
			E('td', {}, c.node || '\u2014'),
			E('td', { class: 'ep-num' }, fmtBytes(c.upload)),
			E('td', { class: 'ep-num' }, fmtBytes(c.download)),
			E('td', { class: 'ep-num' }, fmtDuration(c.elapsed_ms))
		]));
	});
	return out;
}

function connTable(list) {
	return E('table', { class: 'ep-tbl' }, [
		E('colgroup', {}, [
			E('col', { style: 'width:34%' }), E('col', { style: 'width:16%' }),
			E('col', { style: 'width:16%' }), E('col', { style: 'width:12%' }),
			E('col', { style: 'width:12%' }), E('col', { style: 'width:10%' })
		]),
		E('thead', {}, [E('tr', {}, [
			E('th', {}, '目标'), E('th', {}, '来源 IP'), E('th', {}, '节点'),
			E('th', { class: 'ep-num' }, '上行'), E('th', { class: 'ep-num' }, '下行'),
			E('th', { class: 'ep-num' }, '时长')
		])]),
		E('tbody', {}, connRows(list))
	]);
}

function pageLive(status, conn) {
	injectStyle();
	var engine = (status && status.engine) || '';
	var api = (status && status.clash_api) || 'absent';

	if (engine !== 'mihomo') {
		return E('div', { class: 'ep-wrap' }, [
			hero('实时连接', '连接级可观测性来自 mihomo 的 Clash API；当前引擎没有这个接口。'),
			card('当前引擎没有连接接口',
				E('div', {}, '实时连接、来源 IP、目标域名、所用节点这些数据只有 mihomo 提供。当前引擎是 ' +
					(engine || 'none') + '，切到 mihomo 后这里会自动出现连接表。'),
				'切换内核在「内核管理」里；切过去之后需要重启一次服务。')
		]);
	}

	var body = E('tbody', {}, connRows((conn && conn.connections) || []));
	var countEl = E('span', { class: 'ep-tag' }, ((conn && conn.connections) || []).length + ' 条活动连接');
	var table = E('table', { class: 'ep-tbl' }, [
		E('colgroup', {}, [
			E('col', { style: 'width:34%' }), E('col', { style: 'width:16%' }),
			E('col', { style: 'width:16%' }), E('col', { style: 'width:12%' }),
			E('col', { style: 'width:12%' }), E('col', { style: 'width:10%' })
		]),
		E('thead', {}, [E('tr', {}, [
			E('th', {}, '目标'), E('th', {}, '来源 IP'), E('th', {}, '节点'),
			E('th', { class: 'ep-num' }, '上行'), E('th', { class: 'ep-num' }, '下行'),
			E('th', { class: 'ep-num' }, '时长')
		])]),
		body
	]);

	// Built by appending rather than in one literal: the wrapper is referenced by
	// the refresh timer below, and a self-referencing array element would be
	// undefined at construction time.
	var wrap = E('div', { class: 'ep-wrap' }, []);
	wrap.appendChild(hero('实时连接', '每 3 秒从本机 Clash API 拉一次：目标域名、来源 IP、实际承载节点与字节数。'));
	if (api === 'absent')
		wrap.appendChild(errCard('Clash API 当前不可达（127.0.0.1:9090）：引擎可能没在运行，或 controller 端口被改过。'));
	var kConn = E('span', {}, '连接数 \u2014');
	var kUp = E('span', {}, '本会话上行 \u2014');
	var kDown = E('span', {}, '本会话下行 \u2014');
	var kMem = E('span', {}, '内核内存 \u2014');
	var kStamp = E('span', { class: 'ep-muted' }, '');
	function paintKpi(st, list) {
		var n = (list && list.length) || (st && st.connections) || 0;
		kConn.textContent = '连接数 ' + n;
		kUp.textContent = '本会话上行 ' + fmtBytes(st && st.conn_up);
		kDown.textContent = '本会话下行 ' + fmtBytes(st && st.conn_down);
		// mihomo reports memory as 0 on builds without gopsutil support; showing
		// "0 B" there reads as a broken gauge, so an unreported value is a dash.
		kMem.textContent = '内核内存 ' + ((st && Number(st.conn_memory)) > 0 ? fmtBytes(st.conn_memory) : '\u2014');
		kStamp.textContent = '更新于 ' + new Date().toLocaleTimeString('zh-CN', {
			timeZone: 'Asia/Shanghai', hour12: false,
			hour: '2-digit', minute: '2-digit', second: '2-digit'
		});
	}
	paintKpi(status, (conn && conn.connections) || []);
	wrap.appendChild(card('KPI', [
		E('div', { class: 'ep-kpi-inline' }, [kConn, kUp, kDown, kMem, kStamp])
	], 'Clash 的累计值在引擎重启后归零，面板把它当作本会话的流量。'));
	wrap.appendChild(card('活动连接', [E('div', { class: 'ep-row', style: 'margin-bottom:8px' }, countEl), table],
		'列表只显示当前仍在传输的连接；已关闭的连接不会被保留。'));

	// Refresh in place so the page does not flicker; stop as soon as the view is
	// torn down, otherwise every visit would leave another timer behind.
	var timer = setInterval(function () {
		if (!document.body.contains(wrap)) { clearInterval(timer); return; }
		Promise.all([liveConnections(), cliJson(['status']).catch(function () { return null; })]).then(function (r) {
			if (!document.body.contains(wrap)) return;
			var list = (r[0] && r[0].connections) || [];
			while (body.firstChild) body.removeChild(body.firstChild);
			connRows(list).forEach(function (tr) { body.appendChild(tr); });
			countEl.textContent = list.length + ' 条活动连接';
			paintKpi(r[1], list);
		});
	}, 3000);

	return wrap;
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
			'main.log_level': valOf('ep-log-level'),
			'routing.probe_timeout': valOf('ep-probe'),
			'routing.rule_set_update_days': valOf('ep-update-days')
		};
	}

	return E('div', { class: 'ep-wrap' }, [
		hero('设置', '日志级别、规则集更新周期、系统自检与卸载清理；入口开关与透明代理在「连接」页。'),
		card('日志与规则集', [
			row('日志级别', E('select', { id: 'ep-log-level', class: 'ep-in' }, ['trace', 'debug', 'info', 'notice', 'warn', 'error'].map(function (l) {
				return E('option', { value: l, selected: (cfg.log_level || 'notice') === l ? 'selected' : null }, l);
			}))),
			row('探测超时（秒）', textInput('ep-probe', cfg.probe_timeout || '3')),
			row('规则集更新周期（天）', textInput('ep-update-days', cfg.rule_set_update_days || '7'))
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

// This module has to be a class: luci.js (>= 27.x) checks Class.isSubclass()
// on whatever a factory returns and then instantiates it with `new`. A plain
// object or a bare function therefore throws "factory yields invalid
// constructor". Views keep calling the members as app.xxx() — they get the
// instance that the loader builds.
return baseclass.extend({
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
	pageUpdate: pageUpdate,
	pageBackup: pageBackup,
	pageConn: pageConn,
	pageSettings: pageSettings,
	tabs: tabs,
	clockBar: clockBar,
	kpiLive: kpiLive,
	pageSafety: pageSafety,
	pageLive: pageLive,
	liveConnections: liveConnections,
	fmtBytes: fmtBytes,
	fmtDuration: fmtDuration
});
