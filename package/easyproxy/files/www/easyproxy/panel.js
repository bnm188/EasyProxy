/* EasyProxy 控制台 —— 原生 JS，hash 路由，数据全部来自 cgi-bin/api.sh */

const API_URL = 'cgi-bin/api.sh';

const $ = (s, el) => (el || document).querySelector(s);
const el = (tag, cls, txt) => {
	const n = document.createElement(tag);
	if (cls) n.className = cls;
	if (txt !== undefined) n.textContent = txt;
	return n;
};
const esc = (s) => String(s === undefined || s === null ? '' : s)
	.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
	.replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const ICONS = {
	overview: '<path d="M12 3a9 9 0 1 0 9 9"/><path d="M12 12l4.5-3"/><path d="M21 3v5h-5"/>',
	nodes: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3c2.6 3 2.6 15 0 18"/><path d="M12 3c-2.6 3-2.6 15 0 18"/>',
	routing: '<path d="M4 6h6"/><path d="M14 6h6"/><path d="M4 18h16"/><circle cx="12" cy="6" r="2"/><path d="M7 18v-4h10v4"/>',
	dns: '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>',
	kernel: '<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M10 3v3M14 3v3M10 18v3M14 18v3M3 10h3M3 14h3M18 10h3M18 14h3"/>',
	monitor: '<path d="M3 17l5-5 4 3 5-8 4 4"/><path d="M3 21h18"/>',
	settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9L17 7M7 17l-2.1 2.1"/>',
	update: '<path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v5h-5"/>',
};

const PAGES = [
	{ id: 'overview', name: '概览', icon: 'overview', sub: '运行状态与实时指标' },
	{ id: 'nodes', name: '节点中心', icon: 'nodes', sub: '节点、订阅与测速' },
	{ id: 'routing', name: '智能分流', icon: 'routing', sub: '出口选择与分流策略' },
	{ id: 'dns', name: 'DNS 与网络', icon: 'dns', sub: 'DNS 策略与网络参数' },
	{ id: 'kernel', name: '内核管理', icon: 'kernel', sub: 'sing-box / mihomo 引擎' },
	{ id: 'monitor', name: '连接与监控', icon: 'monitor', sub: '实时连接与日志' },
	{ id: 'settings', name: '系统设置', icon: 'settings', sub: '密码、端口与备份' },
	{ id: 'update', name: '更新与诊断', icon: 'update', sub: '版本、校验与自检' },
];

const S = {
	version: '—',
	host: '—',
	status: null,
	cpu: null,
	mem: null,
	uptime: 0,
	prev: { t: 0, up: 0, down: 0, rateUp: 0, rateDown: 0 },
	none: null,
	timer: null,
	timerSlow: null,
};

/* ---------------- 通用请求 ---------------- */
async function api(cmd, body) {
	const opts = { credentials: 'same-origin', cache: 'no-store' };
	if (body) {
		opts.method = 'POST';
		opts.headers = { 'Content-Type': 'application/json' };
		opts.body = JSON.stringify(Object.assign({ cmd }, body));
	}
	try {
		const r = await fetch(API_URL + '?cmd=' + encodeURIComponent(cmd), opts);
		return await r.json();
	} catch (e) {
		return { ok: false, error: '接口不可达' };
	}
}

let toastTimer = null;
function toast(msg) {
	const t = $('#toast');
	t.textContent = msg;
	t.classList.add('show');
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => t.classList.remove('show'), 2600);
}

/* ---------------- 格式化 ---------------- */
function fmtBytes(b) {
	b = Number(b) || 0;
	if (b < 1024) return b.toFixed(0) + ' B';
	if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB';
	if (b < 1024 * 1024 * 1024) return (b / 1048576).toFixed(1) + ' MB';
	return (b / 1073741824).toFixed(2) + ' GB';
}
function fmtRate(bps) {
	if (!bps || bps <= 0) return '0.0';
	const v = Number(bps);
	if (v < 1024) return v.toFixed(0) + ' B/s';
	if (v < 1048576) return (v / 1024).toFixed(1) + ' KB/s';
	return (v / 1048576).toFixed(2) + ' MB/s';
}
function fmtUptime(sec) {
	sec = Math.max(0, Math.floor(Number(sec) || 0));
	const d = Math.floor(sec / 86400);
	const h = Math.floor((sec % 86400) / 3600);
	const m = Math.floor((sec % 3600) / 60);
	if (d > 0) return d + ' 天 ' + h + ' 小时';
	if (h > 0) return h + ' 小时 ' + m + ' 分';
	if (m > 0) return m + ' 分';
	return sec % 60 + ' 秒';
}
function fmtTime(d) {
	const p = (n) => String(n).padStart(2, '0');
	return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}
const WEEK = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
function fmtDate(d) {
	return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + WEEK[d.getDay()];
}

/* ---------------- 时钟（真实本地时间） ---------------- */
function tickClock() {
	const c = $('#clock');
	if (!c) return;
	const d = new Date();
	c.textContent = fmtDate(d) + ' ' + fmtTime(d);
}

/* ---------------- 主题 ---------------- */
function initTheme() {
	let t = localStorage.getItem('ep.theme');
	if (!t) t = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
	document.documentElement.setAttribute('data-theme', t);
}
function toggleTheme() {
	const cur = document.documentElement.getAttribute('data-theme');
	const next = cur === 'dark' ? 'light' : 'dark';
	document.documentElement.setAttribute('data-theme', next);
	localStorage.setItem('ep.theme', next);
}

/* ---------------- 侧栏与 dock ---------------- */
function buildNav() {
	const nav = $('#nav');
	const dock = $('#dockInner');
	nav.innerHTML = '';
	dock.innerHTML = '';
	PAGES.forEach((p) => {
		const b = el('button', 'nav-item');
		b.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + ICONS[p.icon] + '</svg><span class="nav-label">' + p.name + '</span>';
		b.dataset.page = p.id;
		b.onclick = () => go(p.id);
		nav.appendChild(b);

		const d = el('button', 'dock-item');
		d.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + ICONS[p.icon] + '</svg><span>' + p.name.slice(0, 4) + '</span>';
		d.dataset.page = p.id;
		d.onclick = () => go(p.id);
		dock.appendChild(d);
	});
}

function markActive(id) {
	document.querySelectorAll('.nav-item').forEach((n) => n.classList.toggle('active', n.dataset.page === id));
	document.querySelectorAll('.dock-item').forEach((n) => n.classList.toggle('active', n.dataset.page === id));
	const p = PAGES.find((x) => x.id === id) || PAGES[0];
	$('#pageTitle').textContent = p.name;
	$('#pageSub').textContent = p.sub;
}

function go(id) {
	if (!PAGES.some((p) => p.id === id)) id = 'overview';
	location.hash = '#/' + id;
}

function currentPage() {
	const h = location.hash.replace('#/', '');
	return PAGES.some((p) => p.id === h) ? h : 'overview';
}

/* ---------------- 状态轮询 ---------------- */
function stopTimers() {
	clearInterval(S.timer);
	clearInterval(S.timerSlow);
	S.timer = S.timerSlow = null;
}

async function pullStatus() {
	const r = await api('status');
	if (!r.ok) return null;
	S.status = r.status;
	S.cpu = r.cpu;
	S.mem = r.mem;
	S.uptime = r.uptime;

	const now = Date.now();
	const up = Number(r.status.conn_up) || 0;
	const down = Number(r.status.conn_down) || 0;
	if (S.prev.t) {
		const dt = (now - S.prev.t) / 1000;
		if (dt > 0) {
			const du = up - S.prev.up;
			const dd = down - S.prev.down;
			S.prev.rateUp = du >= 0 ? du / dt : 0;
			S.prev.rateDown = dd >= 0 ? dd / dt : 0;
		}
	}
	S.prev.t = now;
	S.prev.up = up;
	S.prev.down = down;

	renderEngineChip();
	return r;
}

function renderEngineChip() {
	const st = S.status;
	const chip = $('#engineChip');
	const txt = $('#engineText');
	if (!st) { chip.className = 'chip'; txt.textContent = '读取中'; return; }
	const running = st.runtime === 'running';
	chip.className = 'chip ' + (running ? 'ok' : 'bad');
	txt.textContent = (st.engine || '—') + ' · ' + (running ? '运行中' : '已停止');
}

/* =================================================================
   页面：概览
   ================================================================= */
function pageOverview() {
	const wrap = el('div', 'grid', '');
	wrap.style.gap = '12px';

	const kpi = el('div', 'grid g4');
	kpi.id = 'kpiGrid';
	wrap.appendChild(kpi);

	const bottom = el('div', 'grid g2');
	bottom.style.marginTop = '0';
	bottom.innerHTML = ''
		+ '<div class="card" style="grid-column:1/-1">'
		+ '  <div class="card-head"><div class="card-title">运行概况</div><div class="card-note">节点流量口径 · 自本次启动累计</div></div>'
		+ '  <div id="runGrid" class="grid g4"></div>'
		+ '</div>';
	wrap.appendChild(bottom);

	const sites = el('div', 'card');
	sites.style.marginTop = '0';
	sites.innerHTML = ''
		+ '<div class="card-head"><div class="card-title">站点连通性</div>'
		+ '<div class="card-note" id="siteNote">本机直连检测</div></div>'
		+ '<div id="siteList" class="skeleton">检测中…</div>'
		+ '<div style="margin-top:12px"><button class="btn sm" id="reSite">重新检测</button></div>';
	wrap.appendChild(sites);

	setTimeout(() => {
		renderKpi();
		renderRun();
		$('#reSite').onclick = checkSites;
		checkSites();
	}, 0);

	return wrap;
}

function kpiCard(label, valueHtml, foot, barPct, barCls, id) {
	const c = el('div', 'card kpi');
	c.innerHTML = ''
		+ '<div class="kpi-label">' + label + '</div>'
		+ '<div class="kpi-value" id="' + id + 'v">' + valueHtml + '</div>'
		+ '<div class="bar"><div class="bar-fill ' + (barCls || '') + '" id="' + id + 'b"></div></div>'
		+ '<div class="kpi-foot" id="' + id + 'f">' + (foot || '') + '</div>';
	return c;
}

function renderKpi() {
	const g = $('#kpiGrid');
	if (!g) return;
	const st = S.status || {};
	const cpu = S.cpu || { usage: 0, user: 0, sys: 0 };
	const mem = S.mem || { used_mb: 0, total_mb: 0, pct: 0 };
	const cpuPct = Math.min(100, Number(cpu.usage) || 0);
	const cls = cpuPct >= 85 ? 'e' : (cpuPct >= 60 ? 'w' : '');

	g.innerHTML = '';
	g.appendChild(kpiCard('CPU 使用', cpuPct + '<span class="kpi-unit">%</span>',
		'usr ' + (cpu.user || 0) + '% · sys ' + (cpu.sys || 0) + '%', cpuPct, cls, 'kcpu'));

	g.appendChild(kpiCard('内存', (mem.used_mb || 0) + '<span class="kpi-unit">MB</span>',
		'已用 ' + (mem.pct || 0) + '% · 共 ' + (mem.total_mb || 0) + ' MB', Math.min(100, mem.pct || 0), '', 'kmem'));

	g.appendChild(kpiCard('实时下行', fmtRateNum(S.prev.rateDown) + '<span class="kpi-unit">' + fmtRateUnit(S.prev.rateDown) + '</span>',
		'节点累计 ' + fmtBytes(st.conn_down || 0), ratePct(S.prev.rateDown), '', 'kdown'));

	g.appendChild(kpiCard('实时上行', fmtRateNum(S.prev.rateUp) + '<span class="kpi-unit">' + fmtRateUnit(S.prev.rateUp) + '</span>',
		'节点累计 ' + fmtBytes(st.conn_up || 0), ratePct(S.prev.rateUp), '', 'kup'));

	setBar('kcpu', cpuPct, cls);
	setBar('kmem', Math.min(100, mem.pct || 0), '');
	setBar('kdown', ratePct(S.prev.rateDown), '');
	setBar('kup', ratePct(S.prev.rateUp), '');
}

function fmtRateNum(bps) {
	const v = Number(bps) || 0;
	if (v < 1048576) return (v / 1024).toFixed(1);
	return (v / 1048576).toFixed(2);
}
function fmtRateUnit(bps) {
	return (Number(bps) || 0) < 1048576 ? 'KB/s' : 'MB/s';
}
function ratePct(bps) {
	const v = Number(bps) || 0;
	// 以 10 MB/s 为满格参考
	return Math.min(100, Math.round(v / (10 * 1048576) * 100));
}

function setBar(id, pct, cls) {
	const b = document.getElementById(id + 'b');
	if (!b) return;
	b.style.width = Math.max(0, Math.min(100, pct || 0)) + '%';
	b.className = 'bar-fill ' + (cls || '');
}

function renderRun() {
	const g = $('#runGrid');
	if (!g) return;
	const st = S.status || {};
	const running = st.runtime === 'running';
	const total = Number(st.nodes) || 0;
	const en = Number(st.nodes_enabled) || 0;
	g.innerHTML = ''
		+ miniKpi('本次流量', fmtBytes((Number(st.conn_up) || 0) + (Number(st.conn_down) || 0)), '↑' + fmtBytes(st.conn_up || 0) + ' / ↓' + fmtBytes(st.conn_down || 0))
		+ miniKpi('运行时间', fmtUptime(st.runtime_uptime || S.uptime), running ? 'PID ' + (st.runtime_pid || '—') : '未运行')
		+ miniKpi('代理状态', running ? '运行中' : '已停止', '监听 :' + (st.listen_port || '—') + (st.listen_open ? ' 已开' : ' 未开'))
		+ miniKpi('节点健康', en + ' / ' + total, '规则集 ' + (st.rule_set_state === 'ready' ? '就绪' : (st.rule_set_state || '—')));
}

function miniKpi(label, value, foot) {
	return ''
		+ '<div>'
		+ '  <div class="kpi-label">' + label + '</div>'
		+ '  <div class="kpi-value" style="font-size:20px">' + value + '</div>'
		+ '  <div class="kpi-foot">' + foot + '</div>'
		+ '</div>';
}

async function checkSites() {
	const box = $('#siteList');
	if (!box) return;
	box.className = 'skeleton';
	box.textContent = '检测中…';
	const r = await api('sites');
	if (!r.ok) { box.className = 'notice err'; box.textContent = r.error || '检测失败'; return; }
	const rows = r.data || [];
	const note = $('#siteNote');
	if (note) note.textContent = '本机出口检测 · ' + (r.mode || '');
	box.className = '';
	box.innerHTML = '<table class="tbl"><colgroup><col style="width:44%"><col style="width:18%"><col style="width:18%"><col style="width:20%"></colgroup>'
		+ '<thead><tr><th>站点</th><th>结果</th><th>耗时</th><th>走法</th></tr></thead><tbody>'
		+ rows.map((x) => '<tr><td>' + esc(x.host) + '</td>'
			+ '<td><span class="pill ' + (x.code === '200' || x.code === '204' ? 'ok' : 'bad') + '">' + esc(x.code) + '</span></td>'
			+ '<td class="num">' + esc(x.time) + '</td>'
			+ '<td class="dim">' + esc(x.via || '—') + '</td></tr>').join('')
		+ '</tbody></table>';
}

/* =================================================================
   页面：节点中心
   ================================================================= */
const REGION_NAME = {
	jp: '日本', hk: '香港', tw: '台湾', sg: '新加坡', kr: '韩国',
	us: '美国', ru: '俄罗斯', de: '德国', it: '意大利', cn: '中国', gb: '英国', fr: '法国',
};

/* =================================================================
   页面：节点中心（照 open-box 的 ProxiesPage 形态：分组 Tab + 节点卡）
   ================================================================= */
let CLASH = { proxies: {} };
let CUR_GROUP = '全部节点';
let NODE_CACHE = [];
let SORT_MODE = 'default';
let ONLY_ALIVE = false;

function isGroupType(t) {
	return t === 'Selector' || t === 'URLTest' || t === 'Fallback' || t === 'LoadBalance' || t === 'Relay';
}
function isBuiltinType(t) {
	return t === 'Direct' || t === 'Reject' || t === 'Pass' || t === 'Rule' || t === 'PassRule' || t === 'RejectDrop' || t === 'Compatible';
}

function groupList() {
	const ps = CLASH.proxies || {};
	const out = [];
	for (const name in ps) {
		const p = ps[name];
		if (!isGroupType(p.type)) continue;
		out.push({ name: name, type: p.type, now: p.now || '', all: p.all || [] });
	}
	const pri = (n) => {
		if (n === 'PROXY') return 0;
		if (n.indexOf('所有-自动') === 0) return 1;
		if (n.indexOf('所有-手动') === 0) return 2;
		if (n.indexOf('自动-') === 0) return 3;
		if (n === '直连' || n === '拒绝') return 9;
		return 5;
	};
	return out.sort((a, b) => pri(a.name) - pri(b.name));
}
function delayOf(name) {
	const p = (CLASH.proxies || {})[name];
	if (!p) return -1;
	let h = p.history;
	if ((!h || !h.length) && p.extra) {
		for (const k in p.extra) {
			if (p.extra[k] && p.extra[k].history && p.extra[k].history.length) { h = p.extra[k].history; break; }
		}
	}
	if (!h || !h.length) return -1;
	const last = h[h.length - 1];
	return (last && typeof last.delay === 'number' && last.delay > 0) ? last.delay : -1;
}
function delayBand(ms) {
	if (ms < 0) return 'none';
	if (ms < 120) return 'fast';
	if (ms < 350) return 'mid';
	return 'slow';
}

let PTAB = 'policy';
const EXPANDED = {};

function pageNodes() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">节点中心</div><div class="card-note" id="grpMeta">读取中…</div></div>'
		+ '  <div class="pmtabs" id="pmtabs"></div>'
		+ '  <div class="ntools">'
		+ '    <input class="input" id="nodeSearch" placeholder="搜索节点 / 地区" style="flex:1;min-width:130px">'
		+ '    <button class="btn sm" id="btnSort">排序：默认</button>'
		+ '    <button class="btn sm" id="btnAlive">仅可用</button>'
		+ '    <button class="btn primary sm" id="btnDelayAll">全组测速</button>'
		+ '  </div>'
		+ '  <div id="pcBody" class="skeleton">读取中…</div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">节点开关</div><div class="card-note">启用 / 停用，修改后自动重载配置</div></div>'
		+ '  <div id="nodeAdvList" class="skeleton">读取中…</div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">订阅导入</div><div class="card-note">Clash / v2ray 订阅链接</div></div>'
		+ '  <input class="input" id="subUrl" placeholder="https://…（订阅地址，含 token 请自行保管）">'
		+ '  <div style="display:flex;gap:8px;margin-top:10px;flex-wrap:wrap">'
		+ '    <button class="btn primary sm" id="subImport">导入为节点</button>'
		+ '    <button class="btn sm" id="subPreviewNote">说明</button>'
		+ '  </div>'
		+ '  <div class="notice" style="margin-top:12px">导入后会替换同名节点，订阅 token 不会出现在面板任何位置。</div>'
		+ '</div>';

	setTimeout(() => {
		$('#btnSort').onclick = () => {
			SORT_MODE = SORT_MODE === 'default' ? 'delay' : (SORT_MODE === 'delay' ? 'name' : 'default');
			$('#btnSort').textContent = '排序：' + (SORT_MODE === 'delay' ? '延迟' : (SORT_MODE === 'name' ? '名称' : '默认'));
			renderBody();
		};
		$('#btnAlive').onclick = () => {
			ONLY_ALIVE = !ONLY_ALIVE;
			$('#btnAlive').className = 'btn sm' + (ONLY_ALIVE ? ' primary' : '');
			renderBody();
		};
		$('#btnDelayAll').onclick = doDelayAll;
		$('#nodeSearch').oninput = () => renderBody();
		$('#subImport').onclick = importSub;
		$('#subPreviewNote').onclick = () => toast('订阅导入走 easyproxy node import-clash，节点按地区进入对应分组');
		loadProxyBoard();
		loadNodes();
	}, 0);
	return wrap;
}

async function loadProxyBoard() {
	const r = await api('clash-proxies');
	if (!r.ok) {
		const box = $('#pcBody');
		if (box) { box.className = 'notice err'; box.textContent = r.error || '读取失败'; }
		return;
	}
	CLASH = (r.data && r.data.proxies) ? r.data : { proxies: {} };
	if (!CLASH.proxies) CLASH = { proxies: {} };
	renderMainTabs();
	renderBody();
}

function renderMainTabs() {
	const bar = $('#pmtabs');
	if (!bar) return;
	const gs = groupList().filter((g) => g.name !== 'GLOBAL');
	const nodes = nodeMembers('全部节点').length;
	const subs = 0;
	const items = [['policy', '策略组', gs.length], ['node', '节点', nodes], ['sub', '订阅', subs]];
	bar.innerHTML = items.map((it) => '<button class="pmt' + (PTAB === it[0] ? ' on' : '') + '" data-t="' + it[0] + '">'
		+ it[1] + '<em>' + it[2] + '</em></button>').join('');
	bar.querySelectorAll('.pmt').forEach((b) => {
		b.onclick = () => { PTAB = b.dataset.t; renderMainTabs(); renderBody(); };
	});
	const meta = $('#grpMeta');
	if (meta) meta.textContent = gs.length + ' 个策略组 · ' + nodes + ' 个节点';
}

function renderBody() {
	if (PTAB === 'policy') renderPolicyCards();
	else if (PTAB === 'node') renderNodeList();
	else renderSubTab();
}

function nodeMembers(gname) {
	const ps = CLASH.proxies || {};
	if (gname === '全部节点') {
		const out = [];
		for (const n in ps) {
			const t = ps[n].type;
			if (isGroupType(t) || isBuiltinType(t)) continue;
			out.push(n);
		}
		return out;
	}
	const g = ps[gname];
	return (g && g.all) ? g.all.slice() : [];
}

function flagOf(name) {
	const m = String(name).match(/([\u{1F1E6}-\u{1F1FF}]{2})/u);
	return m ? m[0] : '';
}

function memberRow(g, n, i) {
	const ps = CLASH.proxies || {};
	const p = ps[n] || {};
	const isG = isGroupType(p.type);
	const ms = isG ? -1 : delayOf(n);
	const band = isG ? 'grp' : delayBand(ms);
	const on = (n === g.now);
	const flag = isG ? '◆' : flagOf(n);
	return '<div class="prow' + (on ? ' on' : '') + '" data-g="' + esc(g.name) + '" data-n="' + esc(n) + '">'
		+ '<span class="pidx">' + (i + 1) + '</span>'
		+ '<span class="pflag">' + (flag || '·') + '</span>'
		+ '<span class="pnm" title="' + esc(n) + '">' + esc(n) + '</span>'
		+ '<span class="plat ' + band + '">' + (isG ? '组' : (ms < 0 ? '—' : ms + 'ms')) + '</span>'
		+ '</div>';
}

function renderPolicyCards() {
	const box = $('#pcBody');
	if (!box) return;
	const q = ($('#nodeSearch') ? $('#nodeSearch').value : '').trim().toLowerCase();
	const gs = groupList().filter((g) => g.name !== 'GLOBAL');
	if (!gs.length) { box.className = 'skeleton'; box.textContent = '没有可用策略组'; return; }
	const ps = CLASH.proxies || {};
	box.className = 'pggrid';
	box.innerHTML = gs.map((g) => {
		let members = g.all.slice();
		if (q) members = members.filter((n) => String(n).toLowerCase().includes(q));
		if (ONLY_ALIVE) members = members.filter((n) => delayOf(n) >= 0 || isGroupType((ps[n] || {}).type));
		if (SORT_MODE === 'delay') members.sort((a, b) => (delayOf(a) < 0 ? 1e9 : delayOf(a)) - (delayOf(b) < 0 ? 1e9 : delayOf(b)));
		else if (SORT_MODE === 'name') members.sort((a, b) => String(a).localeCompare(String(b), 'zh'));
		const expanded = !!EXPANDED[g.name];
		const shown = expanded ? members : members.slice(0, 6);
		const manual = g.type !== 'URLTest';
		return '<div class="pgcard' + (g.name === 'PROXY' ? ' wide' : '') + '">'
			+ '<div class="pghead">'
			+ '<span class="pgdot ' + (manual ? 'm' : 'a') + '"></span>'
			+ '<span class="pgname" title="' + esc(g.name) + '">' + esc(g.name) + '</span>'
			+ '<span class="pgtype">' + (manual ? '手动' : '自动') + '</span>'
			+ '<button class="btn sm pgbtn" data-speed="' + esc(g.name) + '">测速</button>'
			+ '</div>'
			+ '<div class="pgnowline">当前：' + esc(g.now || '—') + '</div>'
			+ '<div class="pgbody">' + shown.map((n, i) => memberRow(g, n, i)).join('')
			+ (members.length === 0 ? '<div class="pempty">无匹配成员</div>' : '') + '</div>'
			+ (members.length > 6 ? '<button class="pgmore" data-exp="' + esc(g.name) + '">' + (expanded ? '收起' : '展开 ' + (members.length - 6) + ' 项') + '</button>' : '')
			+ '</div>';
	}).join('');

	box.querySelectorAll('.pgmore').forEach((b) => {
		b.onclick = () => { EXPANDED[b.dataset.exp] = !EXPANDED[b.dataset.exp]; renderPolicyCards(); };
	});
	box.querySelectorAll('[data-speed]').forEach((b) => {
		b.onclick = () => speedGroup(b.dataset.speed, b);
	});
	box.querySelectorAll('.prow').forEach((r) => {
		r.onclick = () => pickNode(r.dataset.n, r.dataset.g);
	});
}

async function speedGroup(grp, btn) {
	btn.disabled = true;
	btn.textContent = '…';
	const r = await api('delay-all', { group_enc: encodeURIComponent(grp), timeout: 5000 });
	btn.disabled = false;
	btn.textContent = '测速';
	if (!r.ok) { toast(r.error || '测速失败'); return; }
	const res = r.data || {};
	let ok = 0;
	for (const n in res) {
		const p = CLASH.proxies[n];
		if (!p) continue;
		const ms = Number(res[n]);
		if (!ms || !isFinite(ms)) continue;
		p.history = p.history || [];
		p.history.push({ time: new Date().toISOString(), delay: ms });
		if (p.history.length > 8) p.history = p.history.slice(-8);
		ok++;
	}
	toast(grp + '：' + ok + ' 个成员有响应');
	renderPolicyCards();
}

function providerOf(name) {
	const rec = (NODE_CACHE || []).find((x) => x.name === name);
	return (rec && rec.provider) || '';
}

// "<region> <count>" pairs for a card header: an airport card that only says
// "25 个" tells you nothing about where those 25 nodes actually sit.
function regionSummary(names) {
	const m = {};
	names.forEach((n) => {
		const rec = (NODE_CACHE || []).find((x) => x.name === n) || {};
		const lab = REGION_NAME[rec.region] || rec.region || '—';
		m[lab] = (m[lab] || 0) + 1;
	});
	return Object.keys(m).sort((a, b) => m[b] - m[a]).slice(0, 4).map((k) => k + ' ' + m[k]).join(' · ');
}

function renderNodeList() {
	const box = $('#pcBody');
	if (!box) return;
	const q = ($('#nodeSearch') ? $('#nodeSearch').value : '').trim().toLowerCase();
	const ps = CLASH.proxies || {};
	let list = nodeMembers('全部节点').filter((n) => q ? String(n).toLowerCase().includes(q) : true);
	if (ONLY_ALIVE) list = list.filter((n) => delayOf(n) >= 0);
	if (SORT_MODE === 'delay') list.sort((a, b) => (delayOf(a) < 0 ? 1e9 : delayOf(a)) - (delayOf(b) < 0 ? 1e9 : delayOf(b)));
	else if (SORT_MODE === 'name') list.sort((a, b) => String(a).localeCompare(String(b), 'zh'));
	if (!list.length) { box.className = 'skeleton'; box.textContent = '没有匹配的节点'; return; }
	const groups = {};
	list.forEach((n) => {
		const t = providerOf(n) || '未标注机场';
		groups[t] = groups[t] || [];
		groups[t].push(n);
	});
	box.className = 'pgbody-wrap';
	box.innerHTML = Object.keys(groups).sort().map((t) =>
		'<div class="pgcard wide">'
		+ '<div class="pghead"><span class="pgdot m"></span><span class="pgname">' + esc(t) + '</span>'
		+ '<span class="pgtype">' + groups[t].length + ' 个 · ' + esc(regionSummary(groups[t])) + '</span></div>'
		+ '<div class="pgbody">' + groups[t].map((n, i) =>
			'<div class="prow' + (delayOf(n) < 0 ? ' dead' : '') + '" data-n="' + esc(n) + '">'
			+ '<span class="pidx">' + (i + 1) + '</span>'
			+ '<span class="pflag">' + (flagOf(n) || '·') + '</span>'
			+ '<span class="pnm" title="' + esc(n) + '">' + esc(n) + '</span>'
			+ '<span class="plat ' + delayBand(delayOf(n)) + '">' + (delayOf(n) < 0 ? '—' : delayOf(n) + 'ms') + '</span>'
			+ '</div>').join('') + '</div></div>'
	).join('');
	box.querySelectorAll('.prow').forEach((r) => {
		r.onclick = () => pickNode(r.dataset.n, 'PROXY');
	});
}

function renderSubTab() {
	const box = $('#pcBody');
	if (!box) return;
	box.className = '';
	box.innerHTML = '<div class="notice">'
		+ '当前 EasyProxy 后端没有「多订阅」模型：<code>easyproxy node import-clash &lt;url&gt;</code> 只是把节点一次性导入 UCI，'
		+ '不保存订阅地址、到期时间、流量用量与自动更新。'
		+ '<br>要让这一屏和 open-box 一样（订阅卡 + 用量条 + 到期 + 自动更新），得先给 CLI 补 <code>subscribe</code> 子命令，'
		+ '否则只能做成假卡片。<br>下方的导入框是当前真实可用的能力。'
		+ '</div>';
}

async function pickNode(name, group) {
	const target = group || (CUR_GROUP === '全部节点' ? 'PROXY' : CUR_GROUP);
	const ps = CLASH.proxies || {};
	const t = ps[target] || {};
	if (!t.type) { toast('当前分组不支持直接切换'); return; }
	if (t.type === 'URLTest') { toast('「' + target + '」是自动选路，不能手动指定'); return; }
	const r = await api('select', { group_enc: encodeURIComponent(target), name: name });
	if (!r.ok) { toast(r.error || '切换失败'); return; }
	toast('已切到 ' + name);
	setTimeout(loadProxyBoard, 600);
}

async function doDelayAll() {
	const btn = $('#btnDelayAll');
	const grp = (CUR_GROUP === '全部节点') ? (CLASH.proxies['PROXY'] ? 'PROXY' : '') : CUR_GROUP;
	if (!grp) { toast('请先选择一个分组再测速'); return; }
	btn.disabled = true;
	btn.textContent = '测速中…';
	const r = await api('delay-all', { group_enc: encodeURIComponent(grp), timeout: 5000 });
	btn.disabled = false;
	btn.textContent = '全部测速';
	if (!r.ok) { toast(r.error || '测速失败'); return; }
	const res = r.data || {};
	let okc = 0;
	for (const n in res) {
		const p = CLASH.proxies[n];
		if (!p) continue;
		const ms = Number(res[n]);
		if (!ms || !isFinite(ms)) continue;
		p.history = p.history || [];
		p.history.push({ time: new Date().toISOString(), delay: ms });
		if (p.history.length > 8) p.history = p.history.slice(-8);
		okc++;
	}
	toast('测速完成：' + okc + ' 个节点有响应');
	renderBody();
}

async function loadNodes() {
	const box = $('#nodeAdvList');
	if (!box) return;
	box.className = 'skeleton';
	box.textContent = '读取中…';
	const r = await api('nodes');
	if (!r.ok) { box.className = 'notice err'; box.textContent = r.error || '读取失败'; return; }
	NODE_CACHE = (r.data && r.data.nodes) || [];
	renderNodeTable();
}

function renderNodeTable() {
	const box = $('#nodeAdvList');
	if (!box) return;
	const q = ($('#nodeSearch') ? $('#nodeSearch').value : '').trim().toLowerCase();
	const list = NODE_CACHE.filter((n) => {
		if (!q) return true;
		return (n.name || '').toLowerCase().includes(q)
			|| (n.server || '').toLowerCase().includes(q)
			|| (REGION_NAME[n.region] || n.region || '').toLowerCase().includes(q);
	});
	const cnt = $('#nodeCount');
	if (cnt) cnt.textContent = list.length + ' / ' + NODE_CACHE.length + ' 个节点';

	if (!list.length) { box.className = 'skeleton'; box.textContent = '没有匹配的节点'; return; }

	box.className = '';
	box.innerHTML = '<table class="tbl"><colgroup><col style="width:38%"><col style="width:12%"><col style="width:26%"><col style="width:10%"><col style="width:14%"></colgroup>'
		+ '<thead><tr><th>节点</th><th>类型</th><th>服务器</th><th>地区</th><th>操作</th></tr></thead><tbody>'
		+ list.map((n) => {
			const idx = NODE_CACHE.indexOf(n);
			return '<tr>'
				+ '<td title="' + esc(n.name) + '">' + esc(n.name)
				+ (n.enabled ? '' : ' <span class="pill">停用</span>') + '</td>'
				+ '<td class="dim">' + esc(n.type || '—') + '</td>'
				+ '<td class="dim" title="' + esc(n.server) + '">' + esc(n.server) + ':' + esc(n.port) + '</td>'
				+ '<td class="dim">' + esc(REGION_NAME[n.region] || n.region || '—') + '</td>'
				+ '<td><button class="btn sm" data-test="' + esc(n.name) + '">测速</button> '
				+ '<button class="btn sm ' + (n.enabled ? 'danger' : '') + '" data-toggle="' + idx + '">' + (n.enabled ? '停用' : '启用') + '</button></td>'
				+ '</tr>';
		}).join('')
		+ '</tbody></table>';

	box.querySelectorAll('[data-test]').forEach((b) => {
		b.onclick = async () => {
			b.disabled = true;
			b.textContent = '测试中';
			const r = await api('node-test', { name: b.dataset.test });
			b.disabled = false;
			b.textContent = '测速';
			toast(r.ok ? (r.message || '已发起测速') : (r.error || '失败'));
		};
	});
	box.querySelectorAll('[data-toggle]').forEach((b) => {
		b.onclick = async () => {
			const n = NODE_CACHE[Number(b.dataset.toggle)];
			b.disabled = true;
			const r = await api('node-toggle', { section: n.section, enable: n.enabled ? 0 : 1 });
			b.disabled = false;
			if (!r.ok) { toast(r.error || '操作失败'); return; }
			toast(n.enabled ? '已停用，生效中…' : '已启用，生效中…');
			setTimeout(loadNodes, 1200);
		};
	});
}

async function importSub() {
	const url = $('#subUrl').value.trim();
	if (!url) { toast('请填写订阅地址'); return; }
	const btn = $('#subImport');
	btn.disabled = true;
	btn.textContent = '导入中…';
	const r = await api('node-import', { url });
	btn.disabled = false;
	btn.textContent = '导入为节点';
	if (!r.ok) { toast(r.error || '导入失败'); return; }
	toast(r.message || '导入完成，已重新生成配置');
	setTimeout(loadNodes, 1500);
}

/* =================================================================
   页面：智能分流
   ================================================================= */
function pageRouting() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">出口选择</div><div class="card-note" id="grpNow">—</div></div>'
		+ '  <div id="groupBox" class="skeleton">读取中…</div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">分流策略</div><div class="card-note">只读展示 · 修改走系统设置</div></div>'
		+ '  <div id="policyBox" class="skeleton">读取中…</div>'
		+ '</div>';

	setTimeout(() => { loadGroup(); loadPolicy(); }, 0);
	return wrap;
}

async function loadGroup() {
	const box = $('#groupBox');
	if (!box) return;
	const r = await api('group');
	if (!r.ok) { box.className = 'notice err'; box.textContent = r.error || '读取失败'; return; }
	const g = r.data || {};
	const now = $('#grpNow');
	if (now) now.textContent = '当前：' + (g.now || '—');
	box.className = '';
	const members = g.members || [];
	box.innerHTML = ''
		+ '<div class="group-box">'
		+ '  <div class="group-head"><span class="pill pri">' + esc(g.group || 'PROXY') + '</span>'
		+ '  <span class="group-now">' + esc(g.now || '—') + '</span></div>'
		+ '  <div class="group-members">'
		+ members.map((m) => '<span class="member' + (m === g.now ? ' now' : '') + '" data-m="' + esc(m) + '" title="' + esc(m) + '">' + esc(m) + '</span>').join('')
		+ '  </div>'
		+ '</div>';

	box.querySelectorAll('.member').forEach((n) => {
		n.onclick = async () => {
			if (n.classList.contains('now')) { toast('已经是当前出口'); return; }
			const r2 = await api('group-use', { group: g.group, member: n.dataset.m });
			if (!r2.ok) { toast(r2.error || '切换失败'); return; }
			toast('已切换到 ' + n.dataset.m);
			setTimeout(loadGroup, 600);
		};
	});
}

async function loadPolicy() {
	const box = $('#policyBox');
	if (!box) return;
	const st = S.status;
	if (!st) { await pullStatus(); }
	const s = S.status || {};
	box.className = '';
	box.innerHTML = ''
		+ rowsHtml([
			['国内流量', s.china_policy === 'direct' ? '直连' : (s.china_policy || '—')],
			['国外流量', s.proxy_policy === 'proxy' ? '走代理' : (s.proxy_policy || '—')],
			['路由模式', s.route_mode === 'split' ? '分流' : (s.route_mode || '—')],
			['DNS 模式', s.dns_mode === 'split' ? '国内外分离' : (s.dns_mode || '—')],
			['规则集', s.rule_set_state === 'ready' ? '已就绪' : (s.rule_set_state || '—')],
			['失败回退', s.fail_closed ? '拦截（不开直连）' : '放行'],
			['IPv6', s.ipv6_state === 'off' ? '关闭' : (s.ipv6_state || '—')],
			['透明代理', s.transparent ? '开启' : '关闭'],
		]);
}

function rowsHtml(pairs) {
	return '<div>' + pairs.map((p) =>
		'<div class="row"><div class="row-main"><div class="row-title">' + p[0] + '</div></div>'
		+ '<div class="pill">' + esc(p[1]) + '</div></div>'
	).join('') + '</div>';
}

/* =================================================================
   页面：DNS 与网络
   ================================================================= */
function pageDns() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">DNS 配置</div><div class="card-note">来自 /etc/config/easyproxy</div></div>'
		+ '  <div id="dnsBox" class="skeleton">读取中…</div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">网络与端口</div><div class="card-note" id="netNote">—</div></div>'
		+ '  <div id="netBox" class="skeleton">读取中…</div>'
		+ '</div>';

	setTimeout(async () => {
		const r = await api('dns');
		const box = $('#dnsBox');
		if (!r.ok) { box.className = 'notice err'; box.textContent = r.error || '读取失败'; }
		else {
			const d = r.data || {};
			box.className = '';
			box.innerHTML = rowsHtml([
				['本地 DNS', d.dns_local || '—'],
				['远程 DNS', d.dns_remote || '—'],
				['DNS 模式', d.dns_mode || '—'],
				['Fake-IP 段', d.fakeip || '未启用'],
				['DNS 缓存', d.cache ? '开启' : '关闭'],
				['规则集目录', d.ruleset_dir || '—'],
			]);
		}
		const s = S.status || {};
		$('#netBox').className = '';
		$('#netBox').innerHTML = rowsHtml([
			['代理端口', ':' + (s.listen_port || '—')],
			['透明代理端口', s.tproxy_state === 'active' ? ':' + (s.tproxy_port || '—') : '未启用'],
			['监听状态', s.listen_open ? '已监听' : '未监听'],
			['配置状态', s.config_state === 'ok' ? '正常' : (s.config_state || '—')],
			['配置路径', s.config_path || '—'],
		]);
	}, 0);
	return wrap;
}

/* =================================================================
   页面：内核管理
   ================================================================= */
function pageKernel() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">当前内核</div><div class="card-note" id="kernNote">—</div></div>'
		+ '  <div id="kernBox" class="skeleton">读取中…</div>'
		+ '  <div style="margin-top:14px;display:flex;gap:8px;flex-wrap:wrap">'
		+ '    <button class="btn sm primary" data-act="start">启动</button>'
		+ '    <button class="btn sm" data-act="restart">重启</button>'
		+ '    <button class="btn sm danger" data-act="stop">停止</button>'
		+ '  </div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">内核切换</div><div class="card-note">切换会重写配置并重启</div></div>'
		+ '  <div class="group-members" id="engineList"></div>'
		+ '  <div class="notice" style="margin-top:12px">sing-box 与 mihomo 共用同一份节点数据；dae 为可选内核，未安装时不可选。</div>'
		+ '</div>';

	setTimeout(() => {
		renderKernel();
		$('#kernBox').parentNode.querySelectorAll('[data-act]').forEach((b) => {
			b.onclick = async () => {
				const act = b.dataset.act;
				if (act === 'stop' && !confirm('停止内核会中断当前代理，确定？')) return;
				b.disabled = true;
				const r = await api('engine', { action: act });
				b.disabled = false;
				if (!r.ok) { toast(r.error || '操作失败'); return; }
				toast('已' + ({ start: '启动', stop: '停止', restart: '重启' })[act]);
				setTimeout(async () => { await pullStatus(); renderKernel(); }, 2500);
			};
		});
		loadEngines();
	}, 0);
	return wrap;
}

function renderKernel() {
	const box = $('#kernBox');
	if (!box) return;
	const s = S.status || {};
	const running = s.runtime === 'running';
	box.className = '';
	box.innerHTML = rowsHtml([
		['引擎', s.engine || '—'],
		['二进制', s.binary || '—'],
		['运行状态', running ? '运行中' : '已停止'],
		['PID', running ? String(s.runtime_pid || '—') : '—'],
		['运行时长', running ? fmtUptime(s.runtime_uptime || 0) : '—'],
		['Clash API', s.clash_api === 'ok' ? '可用' : (s.clash_api || '—')],
		['配置校验', s.config_state === 'ok' ? '通过' : (s.config_state || '—')],
	]);
	const note = $('#kernNote');
	if (note) note.textContent = s.engine_stability === 'stable' ? '稳定内核' : '开发内核';
}

async function loadEngines() {
	const box = $('#engineList');
	if (!box) return;
	const r = await api('engines');
	box.innerHTML = '';
	if (!r.ok) { box.innerHTML = '<div class="notice err">' + esc(r.error || '读取失败') + '</div>'; return; }
	const list = r.data || [];
	const cur = (S.status && S.status.engine) || '';
	box.innerHTML = list.map((e) =>
		'<span class="member' + (e.name === cur ? ' now' : '') + '" data-eng="' + esc(e.name) + '" '
		+ 'title="' + esc(e.name + (e.installed ? '' : '（未安装）')) + '" '
		+ 'style="' + (e.installed ? '' : 'opacity:.45;') + '">'
		+ esc(e.name) + (e.installed ? '' : ' · 未装') + '</span>'
	).join('');
	box.querySelectorAll('[data-eng]').forEach((n) => {
		n.onclick = async () => {
			if (n.classList.contains('now')) { toast('已是当前内核'); return; }
			if (!confirm('切换到 ' + n.dataset.eng + ' 并重启代理？')) return;
			const r2 = await api('engine-use', { name: n.dataset.eng });
			if (!r2.ok) { toast(r2.error || '切换失败'); return; }
			toast('已切换，等待内核启动…');
			setTimeout(async () => { await pullStatus(); renderKernel(); loadEngines(); }, 3000);
		};
	});
}

/* =================================================================
   页面：连接与监控
   ================================================================= */
let WK_TAB = 'conns';
let CONNS = [];
let CONN_TOT = { up: 0, down: 0 };
let LOGS = [];
let CONN_FILTER = '';
let LOG_LEVEL = 'all';
let LOG_FOLLOW = true;
let LOG_DOMAIN = '';

function pageMonitor() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">连接与监控</div><div class="card-note" id="wkMeta">读取中…</div></div>'
		+ '  <div class="pmtabs" id="wktabs"></div>'
		+ '  <div id="wkTools" class="ntools"></div>'
		+ '  <div id="wkBody" class="skeleton">读取中…</div>'
		+ '</div>';
	setTimeout(() => {
		renderWkTabs();
		renderWkTools();
		renderWkBody();
		startWkTimer();
	}, 0);
	return wrap;
}

function renderWkTabs() {
	const bar = $('#wktabs');
	if (!bar) return;
	const items = [['conns', '连接', CONNS.length], ['logs', '日志', LOGS.length], ['rules', '路由', '']];
	bar.innerHTML = items.map((it) => '<button class="pmt' + (WK_TAB === it[0] ? ' on' : '') + '" data-t="' + it[0] + '">'
		+ it[1] + (it[2] === '' ? '' : '<em>' + it[2] + '</em>') + '</button>').join('');
	bar.querySelectorAll('.pmt').forEach((b) => {
		b.onclick = () => {
			WK_TAB = b.dataset.t;
			renderWkTabs();
			renderWkTools();
			renderWkBody();
			startWkTimer();
		};
	});
}

function renderWkTools() {
	const t = $('#wkTools');
	if (!t) return;
	if (WK_TAB === 'conns') {
		t.innerHTML = '<input class="input" id="connFilter" placeholder="筛选域名 / 出口" style="flex:1;min-width:120px" value="' + esc(CONN_FILTER) + '">'
			+ '<button class="btn sm" id="connView">视图：' + (WK_VIEW_MODE === 'card' ? '卡片' : '表格') + '</button>'
			+ '<button class="btn sm" id="connReload">刷新</button>';
		$('#connFilter').oninput = () => { CONN_FILTER = $('#connFilter').value.trim().toLowerCase(); renderConnBody(); };
		$('#connView').onclick = () => {
			WK_VIEW_MODE = WK_VIEW_MODE === 'card' ? 'table' : 'card';
			renderWkTools();
			renderConnBody();
		};
		$('#connReload').onclick = loadConns;
	} else if (WK_TAB === 'logs') {
		t.innerHTML = '<select class="input" id="logLevel" style="max-width:130px">'
			+ '<option value="all">全部级别</option><option value="info">info</option><option value="warn">warn</option><option value="error">error</option>'
			+ '</select>'
			+ '<button class="btn sm" id="logFollow">跟随：开</button>'
			+ '<button class="btn sm" id="logReload">刷新</button>'
			+ '<button class="btn sm" id="logCopy">复制原文</button>';
		$('#logLevel').value = LOG_LEVEL;
		$('#logLevel').onchange = () => { LOG_LEVEL = $('#logLevel').value; renderLogBody(); };
		$('#logFollow').onclick = () => {
			LOG_FOLLOW = !LOG_FOLLOW;
			$('#logFollow').textContent = '跟随：' + (LOG_FOLLOW ? '开' : '关');
			startWkTimer();
		};
		$('#logReload').onclick = loadLogs;
		$('#logCopy').onclick = () => {
			const txt = LOGS.join('\n');
			if (navigator.clipboard) { navigator.clipboard.writeText(txt).then(() => toast('已复制 ' + LOGS.length + ' 行'), () => toast('复制失败')); }
			else toast('浏览器不支持剪贴板');
		};
	} else {
		t.innerHTML = '<input class="input" id="domInput" placeholder="输入域名，查它走了哪条规则、哪个出口" style="flex:1;min-width:160px" value="' + esc(LOG_DOMAIN) + '">'
			+ '<button class="btn primary sm" id="domQuery">查询</button>';
		$('#domInput').oninput = () => { LOG_DOMAIN = $('#domInput').value.trim(); };
		$('#domInput').onkeydown = (e) => { if (e.key === 'Enter') loadLogs(); };
		$('#domQuery').onclick = loadLogs;
	}
}

function startWkTimer() {
	clearInterval(S.connTimer);
	S.connTimer = null;
	if (WK_TAB === 'conns') S.connTimer = setInterval(loadConns, 3000);
	else if (WK_TAB === 'logs') { if (LOG_FOLLOW) S.connTimer = setInterval(loadLogs, 3000); }
}

function renderWkBody() {
	if (WK_TAB === 'conns') loadConns();
	else if (WK_TAB === 'logs') loadLogs();
	else loadLogs();
}

async function loadConns() {
	const box = $('#wkBody');
	if (!box) return;
	const r = await api('clash-conns');
	if (!r.ok) { box.className = 'notice err'; box.textContent = r.error || '读取失败'; return; }
	const d = r.data || {};
	CONNS = d.connections || [];
	CONN_TOT = { up: d.uploadTotal || 0, down: d.downloadTotal || 0 };
	renderConnBody();
	renderWkTabs();
}

function fmtDur(ms) {
	if (!ms || ms < 0) return '—';
	const s = Math.floor(ms / 1000);
	if (s < 60) return s + 's';
	const m = Math.floor(s / 60);
	if (m < 60) return m + 'm' + (s % 60) + 's';
	return Math.floor(m / 60) + 'h' + (m % 60) + 'm';
}

function connHost(c) {
	const m = c.metadata || {};
	return m.host || m.destinationIP || '—';
}

function renderConnBody() {
	const box = $('#wkBody');
	if (!box) return;
	const meta = $('#wkMeta');
	if (meta) meta.textContent = CONNS.length + ' 条连接 · 累计 ↓' + fmtBytes(CONN_TOT.down) + ' ↑' + fmtBytes(CONN_TOT.up) + ' · 每 3 秒';
	let list = CONNS.filter((c) => {
		if (!CONN_FILTER) return true;
		const h = String(connHost(c)).toLowerCase();
		const ch = ((c.chains || []).join('.')).toLowerCase();
		return h.includes(CONN_FILTER) || ch.includes(CONN_FILTER);
	});
	if (!list.length) { box.className = 'skeleton'; box.textContent = CONNS.length ? '没有匹配的连接' : '当前没有活动连接（代理空闲时是正常的）'; return; }
	box.className = '';
	let html = '';
	if (WK_VIEW_MODE === 'card') {
		html = '<div class="ccards">' + list.slice(0, 80).map((c) => {
			const m = c.metadata || {};
			const chain = (c.chains || []).join(' → ');
			return '<div class="ccard">'
				+ '<div class="ccard-top"><span class="chost">' + esc(connHost(c)) + '</span>'
				+ '<span class="ctag">' + esc(m.network || 'tcp') + '</span></div>'
				+ '<div class="clines">'
				+ '<span>规则 <b>' + esc((c.rule || '—') + (c.rulePayload ? '(' + c.rulePayload + ')' : '')) + '</b></span>'
				+ '<span>出口 <b>' + esc(chain || '—') + '</b></span>'
				+ '<span>来源 ' + esc((m.sourceIP || '—') + ':' + (m.sourcePort || '')) + '</span>'
				+ '<span>↓' + fmtBytes(c.download || 0) + ' ↑' + fmtBytes(c.upload || 0) + ' · ' + fmtDur(Date.now() - new Date(c.start).getTime()) + '</span>'
				+ '</div>'
				+ '<button class="btn sm danger" data-close="' + esc(c.id) + '">断开</button>'
				+ '</div>';
		}).join('') + '</div>';
	} else {
		html = '<table class="tbl"><colgroup><col style="width:26%"><col style="width:17%"><col style="width:17%"><col style="width:18%"><col style="width:9%"><col style="width:9%"></colgroup>'
			+ '<thead><tr><th>目标</th><th>类型</th><th>来源</th><th>规则 → 出口</th><th>上下行</th><th></th></tr></thead><tbody>'
			+ list.slice(0, 80).map((c) => {
				const m = c.metadata || {};
				const chain = (c.chains || []).join(' → ');
				return '<tr>'
					+ '<td title="' + esc(connHost(c)) + '">' + esc(connHost(c)) + '</td>'
					+ '<td class="dim">' + esc(m.network || 'tcp') + '</td>'
					+ '<td class="dim">' + esc((m.sourceIP || '—')) + '</td>'
					+ '<td class="dim" title="' + esc(chain) + '">' + esc((c.rule || '—') + (c.rulePayload ? '(' + c.rulePayload + ')' : '')) + ' <span class="carrow">→</span> ' + esc(chain || '—') + '</td>'
					+ '<td class="num">↓' + fmtBytes(c.download || 0) + '<br>↑' + fmtBytes(c.upload || 0) + '</td>'
					+ '<td><button class="btn sm" data-close="' + esc(c.id) + '">断开</button></td>'
					+ '</tr>';
			}).join('') + '</tbody></table>';
	}
	box.innerHTML = html;
	box.querySelectorAll('[data-close]').forEach((b) => {
		b.onclick = async () => {
			b.disabled = true;
			const r = await api('conn-close', { id: b.dataset.close });
			if (!r.ok) { toast(r.error || '断开失败'); b.disabled = false; return; }
			toast('已断开');
			loadConns();
		};
	});
}

let WK_VIEW_MODE = 'table';

function parseLogLine(l) {
	const out = { raw: l, time: '', level: '', proto: '', src: '', host: '', rule: '', chain: '' };
	const tm = l.match(/time="([^"]+)"/);
	if (tm) out.time = tm[1].replace('T', ' ').slice(11, 19);
	const lv = l.match(/level=(\w+)/);
	if (lv) out.level = lv[1];
	const m = l.match(/msg="\[(\w+)\] (\S+) --> (\S+) ([^"]*?) using ([^"]+)"/);
	if (m) {
		out.proto = m[1];
		out.src = m[2];
		out.host = m[3];
		const mid = m[4];
		out.rule = (mid.match(/match (\S+) ?(?:\(([^)]*)\))?/) || [])[1] || mid.replace(/match /, '');
		out.chain = m[5];
	} else {
		const m2 = l.match(/msg="([^"]+)"/);
		if (m2) out.host = m2[1];
	}
	return out;
}

async function loadLogs() {
	const box = $('#wkBody');
	if (!box) return;
	const r = await api('logs', { lines: 160 });
	if (!r.ok) { box.className = 'notice err'; box.textContent = r.error || '读取失败'; return; }
	LOGS = r.lines || [];
	if (WK_TAB === 'logs') renderLogBody();
	else renderRuleBody();
	renderWkTabs();
}

function renderLogBody() {
	const box = $('#wkBody');
	if (!box) return;
	const parsed = LOGS.map(parseLogLine);
	const list = parsed.filter((p) => LOG_LEVEL === 'all' ? true : p.level === LOG_LEVEL);
	if (!list.length) { box.className = 'skeleton'; box.textContent = '暂无日志'; return; }
	box.className = '';
	box.innerHTML = '<div class="llog">' + list.slice(-160).map((p) =>
		'<div class="lrow lv-' + esc(p.level || 'info') + '">'
		+ '<span class="ltime">' + esc(p.time) + '</span>'
		+ (p.proto ? '<span class="ltag">' + esc(p.proto) + '</span>' : '')
		+ '<span class="lhost" title="' + esc(p.raw) + '">' + esc(p.host) + '</span>'
		+ (p.rule ? '<span class="lrule">' + esc(p.rule) + '</span>' : '')
		+ (p.chain ? '<span class="lchain">' + esc(p.chain) + '</span>' : '')
		+ '</div>').join('') + '</div>';
}

function renderRuleBody() {
	const box = $('#wkBody');
	if (!box) return;
	const parsed = LOGS.map(parseLogLine).filter((p) => p.host);
	const ruleCnt = {};
	const chainCnt = {};
	parsed.forEach((p) => {
		if (p.rule) ruleCnt[p.rule] = (ruleCnt[p.rule] || 0) + 1;
		if (p.chain) chainCnt[p.chain] = (chainCnt[p.chain] || 0) + 1;
	});
	const topRules = Object.keys(ruleCnt).sort((a, b) => ruleCnt[b] - ruleCnt[a]).slice(0, 8);
	const topChains = Object.keys(chainCnt).sort((a, b) => chainCnt[b] - chainCnt[a]).slice(0, 6);
	const q = LOG_DOMAIN.toLowerCase();
	const hits = q ? parsed.filter((p) => p.host.toLowerCase().includes(q)).slice(-6).reverse() : [];

	box.className = '';
	box.innerHTML = '<div class="rgrid">'
		+ '<div class="pgcard"><div class="pghead"><span class="pgdot m"></span><span class="pgname">规则命中 Top</span>'
		+ '<span class="pgtype">近 ' + LOGS.length + ' 行日志</span></div><div class="pgbody">'
		+ (topRules.length ? topRules.map((r, i) => '<div class="prow"><span class="pidx">' + (i + 1) + '</span>'
			+ '<span class="pnm">' + esc(r) + '</span><span class="plat grp">' + ruleCnt[r] + ' 次</span></div>').join('')
			: '<div class="pempty">暂无命中</div>')
		+ '</div></div>'
		+ '<div class="pgcard"><div class="pghead"><span class="pgdot a"></span><span class="pgname">出口分布</span>'
		+ '<span class="pgtype">按连接数</span></div><div class="pgbody">'
		+ (topChains.length ? topChains.map((c, i) => '<div class="prow"><span class="pidx">' + (i + 1) + '</span>'
			+ '<span class="pnm" title="' + esc(c) + '">' + esc(c) + '</span><span class="plat fast">' + chainCnt[c] + '</span></div>').join('')
			: '<div class="pempty">暂无数据</div>')
		+ '</div></div>'
		+ '</div>'
		+ (q ? '<div class="card" style="margin-top:10px;border:1px solid var(--line);border-radius:14px;padding:12px">'
			+ '<div class="card-title" style="margin-bottom:8px">「' + esc(LOG_DOMAIN) + '」的判定记录</div>'
			+ (hits.length ? hits.map((p) => '<div class="lrow"><span class="ltime">' + esc(p.time) + '</span>'
				+ '<span class="ltag">' + esc(p.proto) + '</span><span class="lhost">' + esc(p.host) + '</span>'
				+ '<span class="lrule">' + esc(p.rule) + '</span><span class="lchain">' + esc(p.chain) + '</span></div>').join('')
				: '<div class="notice">最近日志里没有该域名的记录。请先在路由器上访问一次，或确认域名拼写。</div>')
			+ '</div>'
			: '<div class="notice" style="margin-top:10px">这里的数据来自引擎运行日志的实时解析：每条连接的「规则 → 出口链」都能核对。'
			+ 'open-box 的逐阶段穿透（入口→DNS→规则→出口→终端）需要规则引擎侧的结构化查询接口，EasyProxy 目前以日志取证实现，结论同源。</div>');
}

/* =================================================================
   页面：系统设置
   ================================================================= */
function pageSettings() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">管理密码</div><div class="card-note">仅用于本面板登录</div></div>'
		+ '  <div class="auth-field"><label>当前密码</label><input class="input" id="pwOld" type="password" autocomplete="current-password"></div>'
		+ '  <div class="auth-field"><label>新密码（6 位以上）</label><input class="input" id="pwNew" type="password" autocomplete="new-password"></div>'
		+ '  <button class="btn primary sm" id="pwSave" style="margin-top:4px">保存新密码</button>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">运行参数</div><div class="card-note">只读展示</div></div>'
		+ '  <div id="setBox" class="skeleton">读取中…</div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">设备</div><div class="card-note" id="devNote">—</div></div>'
		+ '  <div class="row"><div class="row-main"><div class="row-title">面板端口</div><div class="row-sub">独立进程，与 LuCI(80) 互不影响</div></div><span class="pill">8090</span></div>'
+ '  <div style="margin-top:12px"><button class="btn sm danger" id="doLogout">退出登录</button></div>'
		+ '</div>';

	setTimeout(() => {
		const s = S.status || {};
		$('#setBox').className = '';
		$('#setBox').innerHTML = rowsHtml([
			['开机自启', s.enabled ? '已启用' : '未启用'],
			['管理端口', '8090'],
			['代理端口', String(s.listen_port || '—')],
			['版本', S.version],
		]);
		$('#devNote').textContent = S.host;
		$('#pwSave').onclick = savePw;
		$('#doLogout').onclick = logout;
	}, 0);
	return wrap;
}

async function savePw() {
	const o = $('#pwOld').value.trim();
	const n = $('#pwNew').value.trim();
	if (!o || !n) { toast('请填写当前密码与新密码'); return; }
	if (n.length < 6) { toast('新密码至少 6 位'); return; }
	const btn = $('#pwSave');
	btn.disabled = true;
	const r = await api('passwd', { old: o, new: n });
	btn.disabled = false;
	if (!r.ok) { toast(r.error || '修改失败'); return; }
	toast('密码已更新，请重新登录');
	setTimeout(() => { location.reload(); }, 1800);
}

/* =================================================================
   页面：更新与诊断
   ================================================================= */
function pageUpdate() {
	const wrap = el('div');
	wrap.style.display = 'grid';
	wrap.style.gap = '12px';
	wrap.innerHTML = ''
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">版本</div><div class="card-note" id="verNote">—</div></div>'
		+ '  <div id="verBox" class="skeleton">读取中…</div>'
		+ '</div>'
		+ '<div class="card">'
		+ '  <div class="card-head"><div class="card-title">运行自检</div><div class="card-note">只读，不改配置</div></div>'
		+ '  <button class="btn sm" id="docBtn">运行 easyproxy doctor</button>'
		+ '  <div id="docBox" class="skeleton" style="margin-top:12px">点上方按钮开始</div>'
		+ '</div>';

	setTimeout(() => {
		const s = S.status || {};
		$('#verBox').className = '';
		$('#verBox').innerHTML = rowsHtml([
			['版本', S.version],
			['包状态', s.stage ? '阶段 ' + s.stage : '—'],
			['内核', s.engine || '—'],
			['节点', (s.nodes_enabled || 0) + ' / ' + (s.nodes || 0) + ' 启用'],
			['主机', S.host],
		]);
		$('#verNote').textContent = 'EasyProxy ' + S.version;
		$('#docBtn').onclick = runDoctor;
	}, 0);
	return wrap;
}

async function runDoctor() {
	const box = $('#docBox');
	box.className = 'skeleton';
	box.textContent = '自检中…（可能需要 10 秒）';
	const r = await api('diag');
	box.className = r.ok ? 'notice' : 'notice err';
	box.textContent = r.ok ? (r.text || '（无输出）') : (r.error || '自检失败');
}

/* =================================================================
   启动
   ================================================================= */
async function logout() {
	await api('logout');
	location.reload();
}

const RENDER = {
	overview: pageOverview,
	nodes: pageNodes,
	routing: pageRouting,
	dns: pageDns,
	kernel: pageKernel,
	monitor: pageMonitor,
	settings: pageSettings,
	update: pageUpdate,
};

async function render() {
	const id = currentPage();
	markActive(id);
	stopPageTimers();
	const c = $('#content');
	c.innerHTML = '';
	c.appendChild(RENDER[id]());
}

function stopPageTimers() {
	clearInterval(S.timer);
	clearInterval(S.connTimer);
	S.timer = S.connTimer = null;
}

function onStatus() {
	const id = currentPage();
	if (id === 'overview') { renderKpi(); renderRun(); }
	else if (id === 'kernel') { renderKernel(); }
}

function boot() {
	initTheme();
	tickClock();
	setInterval(tickClock, 1000);
	$('#themeBtn').onclick = toggleTheme;
	$('#foldBtn').onclick = () => $('#sidebar').classList.toggle('collapsed');
	$('#logoutBtn').onclick = logout;
	window.addEventListener('hashchange', render);
	checkAuth();
}

async function checkAuth() {
	const r = await api('state');
	if (!r.ok) { showAuth('无法连接面板接口', r.error || '请刷新重试', false, false); return; }
	S.version = r.version || '—';
	S.host = r.host || '—';
	if (r.need_setup) { showAuth('初始设置', '首次使用，请设置一个管理密码（仅本面板使用）', true, true); return; }
	if (!r.logged_in) { showAuth('登录', '请输入管理密码以进入控制台', false, true); return; }
	enterApp();
}

function showAuth(title, sub, setupMode, showForm) {
	$('#app').classList.add('hidden');
	$('#auth').classList.remove('hidden');
	$('#authTitle').textContent = title;
	$('#authSub').textContent = sub;
	$('#authErr').classList.add('hidden');
	const form = $('#authForm');
	if (!showForm) { form.classList.add('hidden'); return; }
	form.classList.remove('hidden');
	$('#pw2Wrap').classList.toggle('hidden', !setupMode);
	$('#authBtn').textContent = setupMode ? '设置并进入' : '登录';
	$('#pw1').value = '';
	$('#pw2').value = '';
	// 注意：handler 必须同步返回 false 并显式 preventDefault，
	// 否则 async 函数返回 Promise，表单仍会走默认提交，导致页面刷新把请求打断。
	form.onsubmit = (e) => {
		if (e && e.preventDefault) e.preventDefault();
		doAuth(setupMode);
		return false;
	};
	$('#authBtn').onclick = (e) => {
		if (e && e.preventDefault) e.preventDefault();
		doAuth(setupMode);
		return false;
	};
	setTimeout(() => $('#pw1').focus(), 100);
}

async function doAuth(setupMode) {
	const p1 = $('#pw1').value.trim();
	const p2 = $('#pw2').value.trim();
	const err = $('#authErr');
	const btn = $('#authBtn');
	btn.disabled = true;
	const label = setupMode ? '设置并进入' : '登录';
	err.classList.add('hidden');
	if (p1.length < 6) { err.textContent = '密码至少 6 位'; err.classList.remove('hidden'); btn.disabled = false; return; }
	if (setupMode && p1 !== p2) { err.textContent = '两次输入不一致'; err.classList.remove('hidden'); btn.disabled = false; return; }
	btn.textContent = '处理中…';
	const r = await api(setupMode ? 'setup' : 'login', { password: p1 });
	if (!r.ok) {
		btn.disabled = false;
		btn.textContent = label;
		err.textContent = r.error || '操作失败';
		err.classList.remove('hidden');
		return;
	}
	const st = await api('state');
	btn.disabled = false;
	btn.textContent = label;
	if (st.ok && st.logged_in) { enterApp(); return; }
	err.textContent = '登录成功，但会话未能保持。请确认浏览器未禁用 Cookie（如无痕模式、第三方 Cookie 限制）。';
	err.classList.remove('hidden');
}

async function enterApp() {
	$('#auth').classList.add('hidden');
	$('#app').classList.remove('hidden');
	$('#footVer').textContent = 'v' + S.version;
	$('#brandSub').textContent = S.host;
	buildNav();
	await pullStatus();
	clearInterval(S.timerSlow);
	S.timerSlow = setInterval(async () => {
		await pullStatus();
		onStatus();
	}, 1500);
	if (!location.hash) location.hash = '#/overview';
	render();
}

document.addEventListener('DOMContentLoaded', boot);
