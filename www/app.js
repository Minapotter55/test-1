/* مصروفي: منطق التطبيق */
(function () {
  'use strict';
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  const clone = o => JSON.parse(JSON.stringify(o));
  const KEY = 'masroofy.v1';
  const Cap = window.Capacitor;
  const isNative = !!(Cap && Cap.isNativePlatform && Cap.isNativePlatform());
  const plugins = {};
  function plugin(name) {
    if (!isNative) return null;
    if (!plugins[name]) plugins[name] = Cap.registerPlugin ? Cap.registerPlugin(name) : (Cap.Plugins || {})[name];
    return plugins[name];
  }

  const ACC_TYPES = { cash: 'كاش', wallet: 'محفظة موبايل', instapay: 'انستاباي / بنك', bank: 'حساب بنكي', other: 'تاني' };
  const ACC_COLORS = { cash: '#1E9E4A', wallet: '#E0364F', instapay: '#0866FF', bank: '#7B61FF', other: '#7A8BA8' };
  const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  const DAYS = ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت'];

  /* ---------- الحفظ ---------- */
  const SMS_DEFAULTS = { enabled: false, lastSync: 0, review: false, minAmount: 0, atmMode: 'transfer', pair: true, ignored: [] };
  function fresh() {
    return {
      version: 1,
      accounts: clone(MasroofyDefaults.accounts),
      categories: clone(MasroofyDefaults.categories),
      txns: [],
      budget: { monthly: 0 },
      settings: { theme: 'system', defaultAccount: 'cash', currency: 'ج.م', voiceLang: 'ar-EG', autoSave: true, sms: clone(SMS_DEFAULTS) },
      smsSeen: [], smsRules: [], smsPending: []
    };
  }
  function load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const d = JSON.parse(raw);
        const f = fresh();
        return migrate(Object.assign(f, d, { settings: Object.assign(f.settings, d.settings || {}), budget: Object.assign(f.budget, d.budget || {}) }));
      }
    } catch (e) { /* storage غير متاح */ }
    return fresh();
  }
  // تصنيفات جديده بتتضاف للبيانات القديمه من غير ما نلمس اللي المستخدم عدّله
  function migrate(d) {
    MasroofyDefaults.categories.forEach((c, i) => {
      if (!d.categories.some(x => x.id === c.id)) {
        const fbIdx = d.categories.findIndex(x => x.kind === c.kind && x.fallback);
        d.categories.splice(fbIdx >= 0 ? fbIdx : d.categories.length, 0, clone(c));
      }
    });
    d.settings.sms = Object.assign(clone(SMS_DEFAULTS), d.settings.sms || {});
    d.smsSeen = d.smsSeen || [];
    d.smsRules = d.smsRules || [];
    d.smsPending = d.smsPending || [];
    return d;
  }
  let S = load();
  function save() { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) { /* ignore */ } }

  /* ---------- أدوات ---------- */
  const fmt = n => {
    const v = Math.round((+n || 0) * 100) / 100;
    return v.toLocaleString('en-US', { maximumFractionDigits: 2 });
  };
  const money = n => `<span class="num">${fmt(n)}</span>`;
  const today = () => iso(new Date());
  function iso(d) { const z = n => String(n).padStart(2, '0'); return d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate()); }
  const accById = id => S.accounts.find(a => a.id === id);
  const catById = id => S.categories.find(c => c.id === id);
  let cur = new Date(); cur = { y: cur.getFullYear(), m: cur.getMonth() };
  const monthKey = (y, m) => y + '-' + String(m + 1).padStart(2, '0');
  const inMonth = t => t.date.slice(0, 7) === monthKey(cur.y, cur.m);

  function balance(accId) {
    const a = accById(accId); let b = a ? +a.initial || 0 : 0;
    S.txns.forEach(t => {
      if (t.type === 'expense' && t.accountId === accId) b -= t.amount;
      else if (t.type === 'income' && t.accountId === accId) b += t.amount;
      else if (t.type === 'transfer') { if (t.accountId === accId) b -= t.amount; if (t.toAccountId === accId) b += t.amount; }
    });
    return b;
  }
  function dayLabel(d) {
    const t = today(); const y = new Date(); y.setDate(y.getDate() - 1);
    if (d === t) return 'النهارده';
    if (d === iso(y)) return 'امبارح';
    const dt = new Date(d + 'T00:00:00');
    return `${DAYS[dt.getDay()]} ${dt.getDate()} ${MONTHS[dt.getMonth()]}`;
  }

  /* ---------- الثيم ---------- */
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  function applyTheme() {
    const t = S.settings.theme;
    if (t === 'system') document.documentElement.removeAttribute('data-theme');
    else document.documentElement.setAttribute('data-theme', t);
    const dark = t === 'dark' || (t === 'system' && mq.matches);
    const meta = $('meta[name="theme-color"]'); if (meta) meta.content = dark ? '#0A111C' : '#F3F6FB';
    const sb = plugin('StatusBar');
    if (sb && sb.setStyle) sb.setStyle({ style: dark ? 'DARK' : 'LIGHT' }).catch(() => {});
  }
  mq.addEventListener && mq.addEventListener('change', applyTheme);

  /* ---------- التنقل ---------- */
  let view = 'home';
  function go(v) {
    view = v; sel = null;
    $$('.tab').forEach(b => b.setAttribute('aria-selected', String(b.dataset.view === v)));
    ['home', 'tx', 'acc', 'set'].forEach(k => { $('#v-' + k).hidden = k !== v; });
    $('#monthNav').style.visibility = (v === 'home' || v === 'tx') ? 'visible' : 'hidden';
    render();
    window.scrollTo({ top: 0 });
  }
  $$('.tab').forEach(b => b.addEventListener('click', () => go(b.dataset.view)));
  $('#mPrev').addEventListener('click', () => { sel = null; cur.m--; if (cur.m < 0) { cur.m = 11; cur.y--; } render(); });
  $('#mNext').addEventListener('click', () => { sel = null; cur.m++; if (cur.m > 11) { cur.m = 0; cur.y++; } render(); });

  function render() {
    $('#monthLabel').textContent = `${MONTHS[cur.m]} ${cur.y}`;
    if (view === 'home') renderHome();
    if (view === 'tx') renderTx();
    if (view === 'acc') renderAcc();
    if (view === 'set') renderSet();
  }

  /* ---------- الداشبورد ---------- */
  function monthStats() {
    const list = S.txns.filter(inMonth);
    let spent = 0, income = 0; const byCat = {};
    list.forEach(t => {
      if (t.type === 'expense') { spent += t.amount; byCat[t.categoryId] = (byCat[t.categoryId] || 0) + t.amount; }
      if (t.type === 'income') income += t.amount;
    });
    return { list, spent, income, byCat };
  }

  function renderHome() {
    const el = $('#v-home');
    const { list, spent, income, byCat } = monthStats();
    const total = S.accounts.reduce((s, a) => s + balance(a.id), 0);
    const cur$ = esc(S.settings.currency);
    const hasAny = S.txns.length > 0;

    let html = `
      <div class="hero">
        <div class="label">إجمالي فلوسك في كل الحسابات</div>
        <div class="big">${money(total)}<small>${cur$}</small></div>
        <div class="hero-row">
          <div><div class="k">صرفت الشهر ده</div><div class="v num">${fmt(spent)}</div></div>
          <div><div class="k">دخل الشهر ده</div><div class="v num">${fmt(income)}</div></div>
          <div><div class="k">الصافي</div><div class="v num">${income - spent >= 0 ? '' : '−'}${fmt(Math.abs(income - spent))}</div></div>
        </div>
      </div>
      <div class="accounts-strip">
        ${S.accounts.map(a => `<button class="acc-chip" data-acc="${esc(a.id)}"><span class="n"><span class="acc-dot" style="background:${ACC_COLORS[a.type] || ACC_COLORS.other}"></span>${esc(a.name)}</span><span class="b">${money(balance(a.id))}</span></button>`).join('')}
      </div>`;

    if (S.budget.monthly > 0) {
      const pct = spent / S.budget.monthly * 100;
      const cls = pct >= 100 ? 'over' : pct >= 80 ? 'warn' : '';
      const d = new Date(); const isCur = d.getFullYear() === cur.y && d.getMonth() === cur.m;
      const daysIn = new Date(cur.y, cur.m + 1, 0).getDate();
      const left = S.budget.monthly - spent;
      const perDay = isCur && left > 0 ? left / (daysIn - d.getDate() + 1) : 0;
      html += `<div class="card">
        <div class="card-head"><h2>الميزانية الشهرية</h2><span class="sub">${money(spent)} من ${money(S.budget.monthly)}</span></div>
        <div class="budget-bar"><i class="${cls}" style="width:${Math.min(100, pct).toFixed(1)}%"></i></div>
        <div class="budget-meta"><span>${left >= 0 ? `فاضل ${money(left)} ${cur$}` : `عديت الميزانية بـ ${money(-left)} ${cur$}`}</span><span>${perDay ? `تقدر تصرف ${money(perDay)} في اليوم` : `${Math.round(pct)}%`}</span></div>
      </div>`;
    }

    if (S.smsPending.length) {
      html += `<button class="card pend-card" id="pendOpen"><span>📩 <b class="num">${S.smsPending.length}</b> ${S.smsPending.length === 1 ? 'عملية' : 'عمليات'} من الرسايل مستنية موافقتك</span><span class="link">راجع</span></button>`;
    }

    if (!hasAny) {
      html += `<div class="card empty">
        <h2>ابدأ سجّل أول مصروف</h2>
        <div>دوس على المايك وقول اللي دفعته، أو اكتبه في الخانة تحت. التطبيق هيعرف المبلغ والتصنيف والحساب لوحده.</div>
        <div class="examples">
          ${['دفعت 120 جنيه أكل من الكاش', 'اوبر 85 انستاباي', 'قبضت المرتب 15000 على انستاباي', 'سحبت 2000 من انستاباي', 'قهوة 60 و بنزين 400'].map(x => `<button data-example="${esc(x)}">«${esc(x)}»</button>`).join('')}
        </div>
        <button class="btn small" id="loadDemo">جرّب ببيانات تجريبية</button>
      </div>`;
      el.innerHTML = html; bindHome(el); return;
    }

    // الصرف حسب التصنيف
    const cats = Object.entries(byCat).map(([id, v]) => ({ id, c: catById(id) || { name: 'محذوف', color: '#7A8BA8', icon: '•' }, v })).sort((a, b) => b.v - a.v);
    html += `<div class="card">
      <div class="card-head"><h2>صرفت على إيه؟</h2><span class="sub">${MONTHS[cur.m]}</span></div>
      ${cats.length ? `<div class="donut-wrap">${donut(cats, spent)}<div class="legend">${cats.slice(0, 7).map(x => `<div class="legend-row" data-legend-cat="${esc(x.id)}" role="button" tabindex="0"><span class="sw" style="background:${x.c.color}"></span><span class="nm">${esc(x.c.icon)} ${esc(x.c.name)}</span><span><span class="num">${fmt(x.v)}</span> <span class="pc num">${Math.round(x.v / spent * 100)}%</span></span></div>`).join('')}</div></div>` : `<div class="hint">مفيش مصاريف في الشهر ده.</div>`}
    </div>`;

    html += `<div class="card"><div class="card-head"><h2>الصرف اليومي</h2><span class="sub">متوسط ${money(spent / dayCountForAvg())} في اليوم</span></div>${dailyBars()}</div>`;

    html += `<div class="card"><div class="card-head"><h2>آخر العمليات</h2><button class="link" id="seeAll">عرض الكل</button></div><div class="list">${S.txns.slice().sort(sortTx).slice(0, 6).map(txRow).join('')}</div></div>`;
    el.innerHTML = html; bindHome(el);
  }
  function dayCountForAvg() {
    const d = new Date();
    if (d.getFullYear() === cur.y && d.getMonth() === cur.m) return d.getDate();
    return new Date(cur.y, cur.m + 1, 0).getDate();
  }
  function bindHome(el) {
    $$('[data-example]', el).forEach(b => b.addEventListener('click', () => { $('#smartInput').value = b.dataset.example; handleText(b.dataset.example); }));
    const demo = $('#loadDemo', el); if (demo) demo.addEventListener('click', loadDemo);
    const pend = $('#pendOpen', el); if (pend) pend.addEventListener('click', pendingSheet);
    const all = $('#seeAll', el); if (all) all.addEventListener('click', () => go('tx'));
    $$('[data-tx]', el).forEach(b => b.addEventListener('click', () => openTxSheet(S.txns.find(t => t.id === b.dataset.tx))));
    $$('[data-acc]', el).forEach(b => b.addEventListener('click', () => { txFilter = { type: 'all', acc: b.dataset.acc, cat: '', q: '' }; go('tx'); }));
    $$('[data-legend-cat]', el).forEach(b => b.addEventListener('click', () => { txFilter = { type: 'expense', acc: '', cat: b.dataset.legendCat, q: '' }; go('tx'); }));
  }

  function donut(cats, total) {
    const R = 60, r = 40, cx = 75, cy = 75; let a0 = -Math.PI / 2; let paths = '';
    if (cats.length === 1) {
      paths = `<circle cx="${cx}" cy="${cy}" r="${(R + r) / 2}" fill="none" stroke="${cats[0].c.color}" stroke-width="${R - r}"/>`;
    } else cats.forEach(x => {
      const a1 = a0 + (x.v / total) * Math.PI * 2; const gap = 0.012;
      const s = a0 + gap, e = a1 - gap; if (e <= s) { a0 = a1; return; }
      const large = e - s > Math.PI ? 1 : 0;
      const p = (rad, ang) => `${(cx + rad * Math.cos(ang)).toFixed(2)} ${(cy + rad * Math.sin(ang)).toFixed(2)}`;
      paths += `<path d="M${p(R, s)} A${R} ${R} 0 ${large} 1 ${p(R, e)} L${p(r, e)} A${r} ${r} 0 ${large} 0 ${p(r, s)} Z" fill="${x.c.color}"/>`;
      a0 = a1;
    });
    return `<svg viewBox="0 0 150 150" width="150" height="150" role="img" aria-label="توزيع المصاريف">${paths}
      <text x="75" y="70" text-anchor="middle" class="chart-text" style="font-size:11px">إجمالي</text>
      <text x="75" y="90" text-anchor="middle" style="font-size:17px;font-weight:700;fill:var(--fg);font-family:var(--font-display)">${fmt(total)}</text></svg>`;
  }

  function dailyBars() {
    const days = new Date(cur.y, cur.m + 1, 0).getDate();
    const vals = Array(days).fill(0);
    S.txns.filter(t => inMonth(t) && t.type === 'expense').forEach(t => { vals[+t.date.slice(8, 10) - 1] += t.amount; });
    const max = Math.max(...vals, 1);
    const nice = niceMax(max);
    const W = 320, H = 130, padL = 34, padB = 18, padT = 8;
    const bw = (W - padL - 4) / days;
    const now = new Date(); const isCur = now.getFullYear() === cur.y && now.getMonth() === cur.m;
    let g = '';
    [0, .5, 1].forEach(f => {
      const y = padT + (H - padT - padB) * (1 - f);
      g += `<line x1="${padL}" x2="${W}" y1="${y}" y2="${y}" class="chart-grid"/><text x="${padL - 6}" y="${y + 3}" text-anchor="end" class="chart-text">${shortNum(nice * f)}</text>`;
    });
    // الأيام من الشمال لليمين زي أي تقويم أرقام
    vals.forEach((v, i) => {
      const h = (H - padT - padB) * (v / nice);
      const x = padL + 2 + i * bw;
      const today = isCur && i + 1 === now.getDate();
      if (v > 0) g += `<rect x="${(x + bw * 0.15).toFixed(1)}" y="${(H - padB - h).toFixed(1)}" width="${(bw * 0.7).toFixed(1)}" height="${h.toFixed(1)}" rx="2" fill="${today ? 'var(--blue-2)' : 'var(--blue)'}" opacity="${today ? 1 : 0.8}"><title>${i + 1}: ${fmt(v)}</title></rect>`;
      if ((i + 1) % 5 === 0 || i === 0) g += `<text x="${(x + bw / 2).toFixed(1)}" y="${H - 4}" text-anchor="middle" class="chart-text">${i + 1}</text>`;
    });
    return `<div style="direction:ltr"><svg viewBox="0 0 ${W} ${H}" width="100%" role="img" aria-label="الصرف اليومي">${g}</svg></div>`;
  }
  function niceMax(v) { const p = Math.pow(10, Math.floor(Math.log10(v))); const n = v / p; return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p; }
  function shortNum(v) { return v >= 1000 ? (v / 1000).toLocaleString('en-US', { maximumFractionDigits: 1 }) + 'k' : String(Math.round(v)); }

  const sortTx = (a, b) => (b.date + b.createdAt).localeCompare(a.date + a.createdAt);
  function txRow(t, selSet) {
    if (!(selSet instanceof Set)) selSet = null;
    const c = catById(t.categoryId); const a = accById(t.accountId); const to = accById(t.toAccountId);
    const checked = selSet && selSet.has(t.id);
    const icon = t.type === 'transfer' ? '⇄' : (c ? c.icon : '•');
    const title = t.type === 'transfer' ? `تحويل ${a ? a.name : ''} ← ${to ? to.name : ''}` : (t.note || (c ? c.name : ''));
    const sub = t.type === 'transfer' ? (t.note || dayLabel(t.date)) : `${c ? c.name : ''} · ${a ? a.name : ''}`;
    const sign = t.type === 'expense' ? '−' : t.type === 'income' ? '+' : '';
    const ic = selSet ? `<span class="tx-ic tx-check${checked ? ' on' : ''}" aria-hidden="true">${checked ? '✓' : ''}</span>`
      : `<span class="tx-ic" style="${c && t.type !== 'transfer' ? `background:color-mix(in srgb, ${c.color} 16%, var(--surface))` : ''}">${esc(icon)}</span>`;
    return `<button class="tx${checked ? ' selected' : ''}" data-tx="${esc(t.id)}"${selSet ? ` role="checkbox" aria-checked="${!!checked}"` : ''}>${ic}
      <span class="tx-main"><div class="tx-t">${esc(title)}${t.source === 'voice' ? ' <span class="pill">🎙</span>' : t.source === 'sms' ? ' <span class="pill">📩</span>' : ''}</div><div class="tx-s">${esc(sub)}</div></span>
      <span class="tx-a ${t.type} num">${sign}${fmt(t.amount)}</span></button>`;
  }

  /* ---------- العمليات ---------- */
  let txFilter = { type: 'all', acc: '', cat: '', q: '' };
  let sel = null; // Set فيها العمليات المتحدده لما وضع التحديد شغال
  let longFired = false, ignoreClickUntil = 0;
  // الضغطه الطويله بتخلص بـ click لازم نتجاهله، بس الضغطات اللي بعده تشتغل عادي
  document.addEventListener('pointerup', () => { if (longFired) { longFired = false; ignoreClickUntil = Date.now() + 350; } }, true);
  function renderTx() {
    const el = $('#v-tx');
    const q = MasroofyParser.normalize(txFilter.q);
    const list = S.txns.filter(inMonth).filter(t => {
      if (txFilter.type !== 'all' && t.type !== txFilter.type) return false;
      if (txFilter.acc && t.accountId !== txFilter.acc && t.toAccountId !== txFilter.acc) return false;
      if (txFilter.cat && t.categoryId !== txFilter.cat) return false;
      if (q) { const c = catById(t.categoryId); const hay = MasroofyParser.normalize([t.note, c && c.name, t.amount].join(' ')); if (!hay.includes(q)) return false; }
      return true;
    }).sort(sortTx);
    const groups = {};
    list.forEach(t => { (groups[t.date] = groups[t.date] || []).push(t); });
    // شريط التصنيفات: كل تصنيفات التطبيق (حسب نوع الفلتر)، واللي فيها عمليات الشهر ده الأول ومعاها إجماليها
    const catSum = {};
    S.txns.filter(inMonth).forEach(t => { if (t.categoryId) catSum[t.categoryId] = (catSum[t.categoryId] || 0) + t.amount; });
    const catList = S.categories
      .filter(c => c.id === txFilter.cat || (txFilter.type === 'all' ? true : txFilter.type === c.kind))
      .map((c, i) => ({ c, v: catSum[c.id] || 0, i }))
      .sort((a, b) => (b.c.id === txFilter.cat) - (a.c.id === txFilter.cat) || (b.v > 0) - (a.v > 0) || b.v - a.v || a.i - b.i);
    const catTotal = txFilter.cat ? list.reduce((s, t) => s + t.amount, 0) : 0;
    const typeChips = [['all', 'الكل'], ['expense', 'مصاريف'], ['income', 'دخل'], ['transfer', 'تحويلات']];
    if (sel) [...sel].forEach(id => { if (!list.some(t => t.id === id)) sel.delete(id); });
    const allOn = sel && list.length && list.every(t => sel.has(t.id));
    const selTotal = sel ? list.filter(t => sel.has(t.id)).reduce((s, t) => s + t.amount, 0) : 0;
    el.innerHTML = `
      ${sel ? `<div class="selbar">
          <button class="btn small" id="selCancel">إلغاء</button>
          <div class="selinfo"><b class="num">${sel.size}</b> متحدد${sel.size ? ` · <span class="num">${fmt(selTotal)}</span>` : ''}</div>
          <button class="btn small" id="selAll" ${list.length ? '' : 'disabled'}>${allOn ? 'شيل الكل' : 'تحديد الكل'}</button>
          <button class="btn small danger" id="selDel" ${sel.size ? '' : 'disabled'}>حذف</button>
        </div>`
      : `<div class="search-row"><input class="search" id="txSearch" type="search" placeholder="دوّر: أكل، اوبر، 150…" value="${esc(txFilter.q)}"><button class="btn small" id="selStart" ${list.length ? '' : 'disabled'}>تحديد</button></div>`}
      <div class="filters">${typeChips.map(([k, n]) => `<button class="chip" data-ft="${k}" aria-pressed="${txFilter.type === k}">${n}</button>`).join('')}
        ${S.accounts.map(a => `<button class="chip" data-fa="${esc(a.id)}" aria-pressed="${txFilter.acc === a.id}">${esc(a.name)}</button>`).join('')}</div>
      ${catList.length ? `<div class="filters">${catList.map(({ c, v }) => `<button class="chip${v ? '' : ' dim'}" data-fc="${esc(c.id)}" aria-pressed="${txFilter.cat === c.id}">${esc(c.icon)} ${esc(c.name)}${v ? ` <span class="num">${fmt(v)}</span>` : ''}</button>`).join('')}</div>` : ''}
      ${txFilter.cat ? `<div class="hint">إجمالي «${esc((catById(txFilter.cat) || {}).name || '')}» في ${MONTHS[cur.m]}: <b class="num">${fmt(catTotal)}</b> ${esc(S.settings.currency)} · ${list.length} ${list.length === 1 ? 'عملية' : 'عمليات'}</div>` : ''}
      <div class="card" style="padding-block:4px 8px">
        ${list.length ? Object.keys(groups).map(d => {
          const dayOut = groups[d].filter(t => t.type === 'expense').reduce((s, t) => s + t.amount, 0);
          return `<div class="day-head"><span>${dayLabel(d)}</span><span>${dayOut ? '−' + money(dayOut) : ''}</span></div><div class="list">${groups[d].map(t => txRow(t, sel)).join('')}</div>`;
        }).join('') : `<div class="empty">مفيش عمليات في ${MONTHS[cur.m]} ${txFilter.q || txFilter.acc || txFilter.type !== 'all' ? 'بالفلتر ده' : ''}.</div>`}
      </div>`;
    const s = $('#txSearch', el);
    if (s) s.addEventListener('input', () => { txFilter.q = s.value; const pos = s.selectionStart; renderTx(); const n = $('#txSearch'); n.focus(); n.setSelectionRange(pos, pos); });
    const startSel = $('#selStart', el); if (startSel) startSel.onclick = () => { sel = new Set(); renderTx(); };
    if (sel) {
      $('#selCancel', el).onclick = () => { sel = null; renderTx(); };
      $('#selAll', el).onclick = () => { if (allOn) sel.clear(); else list.forEach(t => sel.add(t.id)); renderTx(); };
      $('#selDel', el).onclick = () => deleteSelected();
    }
    $$('[data-ft]', el).forEach(b => b.addEventListener('click', () => { txFilter.type = b.dataset.ft; const c = catById(txFilter.cat); if (c && txFilter.type !== 'all' && c.kind !== txFilter.type) txFilter.cat = ''; renderTx(); }));
    $$('[data-fa]', el).forEach(b => b.addEventListener('click', () => { txFilter.acc = txFilter.acc === b.dataset.fa ? '' : b.dataset.fa; renderTx(); }));
    $$('[data-fc]', el).forEach(b => b.addEventListener('click', () => { txFilter.cat = txFilter.cat === b.dataset.fc ? '' : b.dataset.fc; renderTx(); }));
    $$('[data-tx]', el).forEach(b => {
      b.addEventListener('click', () => {
        if (Date.now() < ignoreClickUntil) return;
        const id = b.dataset.tx;
        if (sel) { sel.has(id) ? sel.delete(id) : sel.add(id); renderTx(); }
        else openTxSheet(S.txns.find(t => t.id === id));
      });
      // ضغطه طويله على أي عمليه تبدأ التحديد بيها
      let timer, x0, y0;
      b.addEventListener('pointerdown', e => {
        x0 = e.clientX; y0 = e.clientY; clearTimeout(timer);
        if (sel) return;
        timer = setTimeout(() => { longFired = true; sel = new Set([b.dataset.tx]); if (navigator.vibrate) navigator.vibrate(15); renderTx(); }, 480);
      });
      b.addEventListener('pointermove', e => { if (Math.abs(e.clientX - x0) > 10 || Math.abs(e.clientY - y0) > 10) clearTimeout(timer); });
      ['pointerup', 'pointercancel', 'pointerleave'].forEach(ev => b.addEventListener(ev, () => clearTimeout(timer)));
      b.addEventListener('contextmenu', e => e.preventDefault());
    });
  }

  async function deleteSelected() {
    const ids = new Set(sel);
    const items = S.txns.filter(t => ids.has(t.id));
    if (!items.length) return;
    const total = items.reduce((s, t) => s + t.amount, 0);
    if (!(await confirmSheet(`تمسح ${items.length} ${items.length === 1 ? 'عملية' : 'عمليات'}؟`, `إجمالي ${fmt(total)} ${S.settings.currency}. أرصدة الحسابات هتتعدل على كده.`, 'امسح'))) return;
    S.txns = S.txns.filter(t => !ids.has(t.id));
    sel = null; save(); render();
    toast(`اتمسح ${items.length} ${items.length === 1 ? 'عملية' : 'عمليات'}`, 'تراجع', () => { S.txns.push(...items); save(); render(); toast('رجعت ✓'); });
  }

  /* ---------- الحسابات ---------- */
  function renderAcc() {
    const el = $('#v-acc');
    const total = S.accounts.reduce((s, a) => s + balance(a.id), 0);
    el.innerHTML = `
      <div class="card">
        <div class="card-head"><h2>حساباتك</h2><span class="sub">الإجمالي ${money(total)} ${esc(S.settings.currency)}</span></div>
        <div class="list">${S.accounts.map(a => `
          <button class="tx" data-edit-acc="${esc(a.id)}"><span class="tx-ic" style="background:color-mix(in srgb, ${ACC_COLORS[a.type] || ACC_COLORS.other} 16%, var(--surface));color:${ACC_COLORS[a.type] || ACC_COLORS.other}">${accIcon(a.type)}</span>
          <span class="tx-main"><div class="tx-t">${esc(a.name)}</div><div class="tx-s">${ACC_TYPES[a.type] || ''}${a.id === S.settings.defaultAccount ? ' · الافتراضي' : ''}</div></span>
          <span class="tx-a num">${fmt(balance(a.id))}</span></button>`).join('')}</div>
      </div>
      <div class="actions"><button class="btn primary" id="addAcc">+ حساب جديد</button><button class="btn" id="doTransfer">⇄ تحويل بين حساباتك</button></div>
      <p class="hint">الرصيد = الرصيد الافتتاحي + الدخل − المصاريف ± التحويلات. عدّل الرصيد الافتتاحي لو عايز الرقم يطابق اللي معاك فعلاً.</p>`;
    $$('[data-edit-acc]', el).forEach(b => b.addEventListener('click', () => openAccSheet(accById(b.dataset.editAcc))));
    $('#addAcc', el).addEventListener('click', () => openAccSheet(null));
    $('#doTransfer', el).addEventListener('click', () => openTxSheet({ type: 'transfer' }));
  }
  function accIcon(type) {
    const p = { cash: '<path d="M3 7h18v10H3z"/><circle cx="12" cy="12" r="2.5"/>', wallet: '<rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/>', instapay: '<path d="M3 10l9-6 9 6M5 10v8M19 10v8M9.5 10v8M14.5 10v8M3 20h18"/>', bank: '<path d="M3 10l9-6 9 6M5 10v8M19 10v8M3 20h18"/>', other: '<circle cx="12" cy="12" r="8"/>' }[type] || '<circle cx="12" cy="12" r="8"/>';
    return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${p}</svg>`;
  }

  /* ---------- الإعدادات ---------- */
  function renderSet() {
    const el = $('#v-set');
    el.innerHTML = `
      <div class="card"><div class="card-head"><h2>الشكل</h2></div>
        <div class="seg" id="themeSeg">${[['system', 'زي الموبايل'], ['light', 'فاتح'], ['dark', 'دارك']].map(([k, n]) => `<button data-theme-opt="${k}" aria-pressed="${S.settings.theme === k}">${n}</button>`).join('')}</div>
      </div>
      <div class="card"><div class="card-head"><h2>الإعدادات العامة</h2></div>
        <div class="field"><label for="setBudget">الميزانية الشهرية (${esc(S.settings.currency)})</label><input class="input num" id="setBudget" inputmode="decimal" value="${S.budget.monthly || ''}" placeholder="مثلاً 8000"></div>
        <div class="field"><label for="setDefAcc">الحساب الافتراضي لما متقولش الحساب</label><select class="input" id="setDefAcc">${S.accounts.map(a => `<option value="${esc(a.id)}" ${a.id === S.settings.defaultAccount ? 'selected' : ''}>${esc(a.name)}</option>`).join('')}</select></div>
        <div class="field"><label for="setCur">العملة</label><input class="input" id="setCur" value="${esc(S.settings.currency)}"></div>
        <div class="set-row"><div><div class="t">حفظ مباشر بعد الصوت</div><div class="d">لو مقفولة، هيوريك العملية تراجعها الأول</div></div><button class="btn small" id="setAuto">${S.settings.autoSave ? 'شغّال' : 'مقفول'}</button></div>
      </div>
      <div class="card"><div class="card-head"><h2>التصنيفات</h2><button class="link" id="addCat">+ تصنيف</button></div>
        <div class="list">${S.categories.map(c => `<button class="tx" data-edit-cat="${esc(c.id)}"><span class="tx-ic" style="background:color-mix(in srgb, ${c.color} 16%, var(--surface))">${esc(c.icon)}</span><span class="tx-main"><div class="tx-t">${esc(c.name)}</div><div class="tx-s">${c.kind === 'income' ? 'دخل' : 'مصروف'} · ${(c.keywords || []).length} كلمة بيتعرف بيها</div></span><span></span></button>`).join('')}</div>
      </div>
      ${smsCard()}
      <div class="card"><div class="card-head"><h2>البيانات</h2></div>
        <div class="actions" style="flex-wrap:wrap"><button class="btn" id="expCsv">تصدير Excel (CSV)</button><button class="btn" id="expJson">نسخة احتياطية (JSON)</button></div>
        <div class="actions" style="flex-wrap:wrap"><button class="btn" id="impJson">استرجاع نسخة احتياطية</button><button class="btn danger" id="wipe">مسح كل البيانات</button></div>
        <p class="hint">البيانات متخزنة على موبايلك بس. اعمل نسخة احتياطية كل فترة وابعتها لنفسك على الواتساب أو الدرايف.</p>
      </div>
      <div class="card"><div class="card-head"><h2>إزاي تتكلم معاه</h2></div>
        <p class="hint">قول المبلغ والحاجة، والحساب لو مش الافتراضي:<br>
        <code>دفعت 120 أكل</code> · <code>اوبر 85 انستاباي</code> · <code>اشتريت هدوم بألف ونص من فودافون كاش</code><br>
        أكتر من حاجة مرة واحدة: <code>قهوة 60 و بنزين 400</code><br>
        دخل: <code>قبضت المرتب 15000 على انستاباي</code> · تحويل: <code>سحبت 2000 من انستاباي</code><br>
        تاريخ: <code>امبارح دفعت 30 ميكروباص</code><br>
        لو غيرت تصنيف حاجة سجلتها بالصوت، التطبيق بيتعلم ويحطها صح المرة الجاية.</p>
      </div>
      <p class="hint" style="text-align:center">مصروفي 1.0</p>`;
    $$('[data-theme-opt]', el).forEach(b => b.addEventListener('click', () => { S.settings.theme = b.dataset.themeOpt; save(); applyTheme(); renderSet(); }));
    $('#setBudget', el).addEventListener('change', e => { S.budget.monthly = Math.max(0, parseFloat(MasroofyParser.normalize(e.target.value)) || 0); save(); toast('اتحفظت الميزانية'); });
    $('#setDefAcc', el).addEventListener('change', e => { S.settings.defaultAccount = e.target.value; save(); });
    $('#setCur', el).addEventListener('change', e => { S.settings.currency = e.target.value.trim() || 'ج.م'; save(); });
    $('#setAuto', el).addEventListener('click', () => { S.settings.autoSave = !S.settings.autoSave; save(); renderSet(); });
    $$('[data-edit-cat]', el).forEach(b => b.addEventListener('click', () => openCatSheet(catById(b.dataset.editCat))));
    $('#addCat', el).addEventListener('click', () => openCatSheet(null));
    bindSmsCard(el);
    $('#expCsv', el).addEventListener('click', exportCsv);
    $('#expJson', el).addEventListener('click', exportJson);
    $('#impJson', el).addEventListener('click', () => $('#importFile').click());
    $('#wipe', el).addEventListener('click', async () => {
      if (await confirmSheet('تمسح كل البيانات؟', 'كل العمليات والحسابات هتتمسح ومش هترجع. اعمل نسخة احتياطية الأول لو محتاجها.', 'امسح كله')) { S = fresh(); save(); applyTheme(); toast('اتمسح كل حاجة'); go('home'); }
    });
  }

  /* ---------- الشيتات ---------- */
  function openSheet(html, onMount) {
    const host = $('#sheetHost');
    host.innerHTML = `<div class="scrim" id="scrim"><div class="sheet" role="dialog" aria-modal="true"><div class="grip"></div>${html}</div></div>`;
    const scrim = $('#scrim');
    scrim.addEventListener('click', e => { if (e.target === scrim) closeSheet(); });
    document.body.style.overflow = 'hidden';
    onMount && onMount($('.sheet', host));
  }
  function closeSheet() { $('#sheetHost').innerHTML = ''; document.body.style.overflow = ''; }
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSheet(); });

  function confirmSheet(title, body, okText) {
    return new Promise(res => {
      openSheet(`<h3>${esc(title)}</h3><p class="hint" style="font-size:14px">${esc(body)}</p><div class="actions"><button class="btn" id="cNo">إلغاء</button><button class="btn danger" id="cYes">${esc(okText)}</button></div>`, sh => {
        $('#cNo', sh).onclick = () => { closeSheet(); res(false); };
        $('#cYes', sh).onclick = () => { closeSheet(); res(true); };
      });
    });
  }

  function openTxSheet(tx, opts = {}) {
    const isNew = !tx || !tx.id;
    const d = Object.assign({ type: 'expense', amount: '', categoryId: null, accountId: S.settings.defaultAccount, toAccountId: null, date: today(), note: '' }, tx || {});
    if (d.type === 'transfer' && !d.toAccountId) d.toAccountId = (S.accounts.find(a => a.id !== d.accountId) || {}).id;
    const draw = sh => {
      const cats = S.categories.filter(c => c.kind === d.type);
      if (d.type !== 'transfer' && !cats.some(c => c.id === d.categoryId)) d.categoryId = (cats.find(c => c.fallback) || cats[0] || {}).id;
      sh.innerHTML = `<div class="grip"></div><h3>${isNew ? 'عملية جديدة' : 'تعديل العملية'}</h3>
        <div class="field"><div class="seg">${[['expense', 'مصروف'], ['income', 'دخل'], ['transfer', 'تحويل']].map(([k, n]) => `<button data-type="${k}" aria-pressed="${d.type === k}">${n}</button>`).join('')}</div></div>
        <div class="field"><label for="fAmount">المبلغ (${esc(S.settings.currency)})</label><input class="input amount-input" id="fAmount" inputmode="decimal" placeholder="0" value="${d.amount === '' || d.amount == null ? '' : d.amount}"></div>
        ${d.type === 'transfer' ? `<div class="row2">
            <div class="field"><label for="fAcc">من</label><select class="input" id="fAcc">${accOptions(d.accountId)}</select></div>
            <div class="field"><label for="fTo">إلى</label><select class="input" id="fTo">${accOptions(d.toAccountId)}</select></div></div>`
          : `<div class="field"><span class="lbl">التصنيف</span><div class="cat-grid">${cats.map(c => `<button class="cat-btn" data-cat="${esc(c.id)}" aria-pressed="${d.categoryId === c.id}"><span>${esc(c.icon)}</span><span>${esc(c.name)}</span></button>`).join('')}</div></div>
            <div class="field"><label for="fAcc">${d.type === 'income' ? 'دخل على' : 'دفعت من'}</label><select class="input" id="fAcc">${accOptions(d.accountId)}</select></div>`}
        <div class="row2">
          <div class="field"><label for="fDate">التاريخ</label><input class="input" type="date" id="fDate" value="${esc(d.date)}"></div>
          <div class="field"><label for="fNote">ملاحظة</label><input class="input" id="fNote" value="${esc(d.note)}" placeholder="مثلاً: غدا مع الشغل"></div>
        </div>
        ${d.sms ? `<div class="field"><span class="lbl">الرسالة اللي اتسجلت منها</span><div class="sms-box">${esc(d.sms)}</div></div>` : ''}
        <div class="actions">${isNew ? '' : '<button class="btn danger" id="fDel">حذف</button>'}<button class="btn primary" id="fSave">${isNew ? 'حفظ' : 'حفظ التعديل'}</button></div>`;
      const sync = () => { d.amount = $('#fAmount', sh).value; d.accountId = $('#fAcc', sh).value; d.date = $('#fDate', sh).value || today(); d.note = $('#fNote', sh).value; if ($('#fTo', sh)) d.toAccountId = $('#fTo', sh).value; };
      $$('[data-type]', sh).forEach(b => b.onclick = () => { sync(); d.type = b.dataset.type; if (d.type === 'transfer' && (!d.toAccountId || d.toAccountId === d.accountId)) d.toAccountId = (S.accounts.find(a => a.id !== d.accountId) || {}).id; draw(sh); });
      $$('[data-cat]', sh).forEach(b => b.onclick = () => { d.categoryId = b.dataset.cat; $$('[data-cat]', sh).forEach(x => x.setAttribute('aria-pressed', String(x === b))); });
      $('#fSave', sh).onclick = () => {
        sync();
        const amt = parseFloat(MasroofyParser.wordsToNumbers(MasroofyParser.normalize(String(d.amount))).replace(/[^\d.]/g, ''));
        if (!(amt > 0)) { $('#fAmount', sh).focus(); toast('اكتب المبلغ الأول'); return; }
        if (d.type === 'transfer' && d.accountId === d.toAccountId) { toast('اختار حسابين مختلفين'); return; }
        const rec = { id: d.id || uid(), type: d.type, amount: amt, categoryId: d.type === 'transfer' ? null : d.categoryId, accountId: d.accountId, toAccountId: d.type === 'transfer' ? d.toAccountId : null, date: d.date, note: d.note.trim(), createdAt: d.createdAt || new Date().toISOString(), source: d.source || 'manual', text: d.text };
        ['sms', 'merchant', 'time', 'smsFrom'].forEach(k => { if (d[k] != null) rec[k] = d[k]; });
        if (!isNew) {
          const old = S.txns.find(t => t.id === rec.id);
          if (old && old.categoryId !== rec.categoryId && rec.categoryId) {
            if (old.source === 'sms' && old.merchant) upsertRule(old.merchant, rec.categoryId);
            else if (old.source === 'voice' || old.source === 'sms') learn(Object.assign({}, rec, { note: old.merchant || rec.note }));
          }
          Object.assign(old, rec);
        } else S.txns.push(rec);
        save(); closeSheet(); render(); toast(isNew ? 'اتسجلت ✓' : 'اتعدلت ✓');
        opts.onSaved && opts.onSaved(rec);
      };
      const del = $('#fDel', sh);
      if (del) del.onclick = () => { const i = S.txns.findIndex(t => t.id === d.id); const [removed] = S.txns.splice(i, 1); save(); closeSheet(); render(); toast('اتحذفت', 'تراجع', () => { S.txns.push(removed); save(); render(); }); };
    };
    openSheet('', sh => { draw(sh); if (isNew && !d.amount) setTimeout(() => { const a = $('#fAmount', sh); a && a.focus(); }, 250); });
  }
  const accOptions = sel => S.accounts.map(a => `<option value="${esc(a.id)}" ${a.id === sel ? 'selected' : ''}>${esc(a.name)}</option>`).join('');

  // لما المستخدم يصحح تصنيف عملية صوتيه، نحفظ الكلمه عشان المره الجايه
  function learn(rec) {
    const words = MasroofyParser.normalize(rec.note || '').split(' ').filter(w => w.length > 1).slice(0, 3);
    const phrase = words.join(' ');
    if (!phrase) return;
    S.categories.forEach(c => { if (c.keywords) c.keywords = c.keywords.filter(k => MasroofyParser.normalize(k) !== phrase); });
    const c = catById(rec.categoryId); if (c) { c.keywords = c.keywords || []; c.keywords.push(phrase); }
  }

  function openAccSheet(acc) {
    const isNew = !acc;
    const a = Object.assign({ name: '', type: 'wallet', initial: 0, keywords: [] }, acc || {});
    openSheet(`<h3>${isNew ? 'حساب جديد' : 'تعديل الحساب'}</h3>
      <div class="field"><label for="aName">اسم الحساب</label><input class="input" id="aName" value="${esc(a.name)}" placeholder="مثلاً: فودافون كاش، بنك مصر، الحصالة"></div>
      <div class="field"><label for="aType">النوع</label><select class="input" id="aType">${Object.entries(ACC_TYPES).map(([k, n]) => `<option value="${k}" ${a.type === k ? 'selected' : ''}>${n}</option>`).join('')}</select></div>
      <div class="field"><label for="aInit">الرصيد الافتتاحي (اللي كان فيه قبل ما تبدأ تسجل)</label><input class="input num" id="aInit" inputmode="decimal" value="${a.initial || ''}" placeholder="0"></div>
      ${!isNew ? `<div class="field"><label for="aBal">أو اكتب الرصيد الحالي الفعلي وهو يظبط الافتتاحي</label><input class="input num" id="aBal" inputmode="decimal" placeholder="${fmt(balance(a.id))}"></div>` : ''}
      ${!isNew && (a.smsSenders || []).length ? `<div class="field"><span class="lbl">بيتسجل تلقائي من رسايل</span><div style="display:flex;gap:6px;flex-wrap:wrap">${a.smsSenders.map(sd => `<button class="chip" data-unlink="${esc(sd)}">${esc(senderLabel(sd))} ✕</button>`).join('')}</div><div class="hint">دوس على أي واحدة عشان تفصلها عن الحساب ده.</div></div>` : ''}
      ${!isNew && a.smsBalance != null ? `<div class="field"><span class="lbl">آخر رصيد في رسالة البنك (${esc(dayLabel(iso(new Date(a.smsBalanceAt))))})</span><div style="display:flex;gap:10px;align-items:center;justify-content:space-between"><b class="num" style="font-size:18px">${fmt(a.smsBalance)}</b>${Math.abs(a.smsBalance - balanceAt(a.id, a.smsBalanceAt)) > 0.5 ? '<button class="btn small" id="aSync">ظبط رصيدي عليه</button>' : '<span class="pill">مطابق ✓</span>'}</div></div>` : ''}
      <div class="field"><label for="aKw">كلمات بتقولها عن الحساب ده (افصل بفاصلة)</label><input class="input" id="aKw" value="${esc((a.keywords || []).join('، '))}" placeholder="مثلاً: بنك مصر، الفيزا"></div>
      <div class="actions">${isNew ? '' : '<button class="btn danger" id="aDel">حذف</button>'}<button class="btn primary" id="aSave">حفظ</button></div>`, sh => {
      $$('[data-unlink]', sh).forEach(b => b.onclick = () => { acc.smsSenders = acc.smsSenders.filter(x => x !== b.dataset.unlink); b.remove(); save(); toast('اتفصلت. الرسايل الجاية منها هتروح لحساب لوحدها'); });
      const sync = $('#aSync', sh);
      if (sync) sync.onclick = () => { acc.initial += acc.smsBalance - balanceAt(acc.id, acc.smsBalanceAt); acc.calibrated = true; save(); closeSheet(); render(); toast('الرصيد بقى زي البنك ✓'); };
      $('#aSave', sh).onclick = () => {
        const name = $('#aName', sh).value.trim(); if (!name) { toast('اكتب اسم الحساب'); return; }
        const rec = isNew ? { id: uid() } : acc;
        rec.name = name; rec.type = $('#aType', sh).value;
        const newInit = parseFloat(MasroofyParser.normalize($('#aInit', sh).value)) || 0;
        if (!isNew && Math.abs(newInit - (+rec.initial || 0)) > 0.001) rec.calibrated = false;
        rec.initial = newInit;
        rec.keywords = $('#aKw', sh).value.split(/[،,]/).map(s => s.trim()).filter(Boolean);
        const bal = $('#aBal', sh) && $('#aBal', sh).value.trim();
        if (bal) { const target = parseFloat(MasroofyParser.normalize(bal)); if (!isNaN(target)) rec.initial += target - balance(rec.id); }
        if (isNew) S.accounts.push(rec);
        save(); closeSheet(); render(); toast('اتحفظ الحساب');
      };
      const del = $('#aDel', sh);
      if (del) del.onclick = async () => {
        if (S.accounts.length <= 1) { toast('لازم يفضل حساب واحد على الأقل'); return; }
        const n = S.txns.filter(t => t.accountId === acc.id || t.toAccountId === acc.id).length;
        if (await confirmSheet(`تحذف «${acc.name}»؟`, n ? `هيتحذف معاه ${n} عملية مسجلة عليه.` : 'الحساب فاضي ومفيش عليه عمليات.', 'احذف')) {
          S.txns = S.txns.filter(t => t.accountId !== acc.id && t.toAccountId !== acc.id);
          S.accounts = S.accounts.filter(x => x.id !== acc.id);
          if (S.settings.defaultAccount === acc.id) S.settings.defaultAccount = S.accounts[0].id;
          save(); render(); toast('اتحذف الحساب');
        }
      };
    });
  }

  function openCatSheet(cat) {
    const isNew = !cat;
    const c = Object.assign({ name: '', icon: '🏷️', kind: 'expense', color: '#0866FF', keywords: [] }, cat || {});
    const colors = ['#0866FF', '#00A3A3', '#E8A317', '#E0457B', '#2BA84A', '#7B61FF', '#F26B38', '#37B4F0', '#C2410C', '#7A8BA8'];
    openSheet(`<h3>${isNew ? 'تصنيف جديد' : 'تعديل التصنيف'}</h3>
      <div class="row2"><div class="field"><label for="cName">الاسم</label><input class="input" id="cName" value="${esc(c.name)}" placeholder="مثلاً: القطة"></div>
      <div class="field"><label for="cIcon">أيقونة (إيموجي)</label><input class="input" id="cIcon" value="${esc(c.icon)}" maxlength="4" style="text-align:center"></div></div>
      <div class="field"><label for="cKind">النوع</label><select class="input" id="cKind"><option value="expense" ${c.kind === 'expense' ? 'selected' : ''}>مصروف</option><option value="income" ${c.kind === 'income' ? 'selected' : ''}>دخل</option></select></div>
      <div class="field"><span class="lbl">اللون</span><div style="display:flex;gap:8px;flex-wrap:wrap" id="cColors">${colors.map(x => `<button data-color="${x}" aria-label="لون" style="width:30px;height:30px;border-radius:50%;background:${x};border:3px solid ${x === c.color ? 'var(--fg)' : 'transparent'}"></button>`).join('')}</div></div>
      <div class="field"><label for="cKw">الكلمات اللي لما تقولها تتحط هنا (افصل بفاصلة)</label><textarea class="input" id="cKw" rows="3">${esc((c.keywords || []).join('، '))}</textarea></div>
      <div class="actions">${isNew || c.fallback ? '' : '<button class="btn danger" id="cDel">حذف</button>'}<button class="btn primary" id="cSave">حفظ</button></div>`, sh => {
      $$('[data-color]', sh).forEach(b => b.onclick = () => { c.color = b.dataset.color; $$('[data-color]', sh).forEach(x => x.style.borderColor = x === b ? 'var(--fg)' : 'transparent'); });
      $('#cSave', sh).onclick = () => {
        const name = $('#cName', sh).value.trim(); if (!name) { toast('اكتب اسم التصنيف'); return; }
        const rec = isNew ? { id: uid() } : cat;
        Object.assign(rec, { name, icon: $('#cIcon', sh).value.trim() || '🏷️', kind: $('#cKind', sh).value, color: c.color, keywords: $('#cKw', sh).value.split(/[،,\n]/).map(s => s.trim()).filter(Boolean) });
        if (isNew) S.categories.push(rec);
        save(); closeSheet(); render(); toast('اتحفظ التصنيف');
      };
      const del = $('#cDel', sh);
      if (del) del.onclick = async () => {
        const fb = S.categories.find(x => x.kind === cat.kind && x.fallback && x.id !== cat.id);
        const n = S.txns.filter(t => t.categoryId === cat.id).length;
        if (await confirmSheet(`تحذف «${cat.name}»؟`, n ? `الـ ${n} عملية اللي فيه هيتنقلوا لـ «${fb ? fb.name : 'تاني'}».` : 'مفيش عمليات في التصنيف ده.', 'احذف')) {
          S.txns.forEach(t => { if (t.categoryId === cat.id) t.categoryId = fb ? fb.id : null; });
          S.categories = S.categories.filter(x => x.id !== cat.id);
          save(); render(); toast('اتحذف التصنيف');
        }
      };
    });
  }

  /* ---------- التوست ---------- */
  let toastTimer;
  function toast(msg, actionText, action, secondText, second) {
    clearTimeout(toastTimer);
    const host = $('#toastHost');
    host.innerHTML = `<div class="toast" role="status"><div class="toast-inner"><div class="msg">${msg}</div>${actionText ? `<button id="tA">${esc(actionText)}</button>` : ''}${secondText ? `<button id="tB">${esc(secondText)}</button>` : ''}</div></div>`;
    if (actionText) $('#tA').onclick = () => { host.innerHTML = ''; action(); };
    if (secondText) $('#tB').onclick = () => { host.innerHTML = ''; second(); };
    toastTimer = setTimeout(() => { host.innerHTML = ''; }, actionText ? 6000 : 2200);
  }

  /* ---------- الإدخال الذكي ---------- */
  function parseCtx() { return { accounts: S.accounts, categories: S.categories, defaultAccountId: S.settings.defaultAccount, today: new Date() }; }

  function handleText(text) {
    text = (text || '').trim(); if (!text) return;
    if (window.MasroofySms && MasroofySms.looksLikeSms(text)) {
      const msg = { address: '', body: text, date: Date.now() };
      const check = analyzeSms(msg, { dry: true, pasted: true });
      if (check.skip) { toast('مش هتتسجل: ' + esc(check.skip), 'إعدادات', () => smsControlSheet()); return; }
      const added = ingestSms([msg], { pasted: true });
      $('#smartInput').value = '';
      if (added.length) announceSms(added); else toast('الرسالة دي اتسجلت قبل كده');
      return;
    }
    const drafts = MasroofyParser.parse(text, parseCtx());
    if (!drafts.length) return;
    const complete = drafts.filter(d => d.amount > 0);
    if (!complete.length) { openTxSheet(Object.assign({}, drafts[0], { amount: '', source: 'voice' })); toast('مسمعتش المبلغ، كمّله هنا'); return; }
    if (!S.settings.autoSave) { reviewDrafts(complete, text); return; }
    const recs = complete.map(d => ({ id: uid(), type: d.type, amount: d.amount, categoryId: d.categoryId, accountId: d.accountId, toAccountId: d.toAccountId, date: d.date, note: d.note, createdAt: new Date().toISOString(), source: 'voice', text: d.text }));
    S.txns.push(...recs); save(); render();
    $('#smartInput').value = '';
    const r = recs[0]; const c = catById(r.categoryId); const a = accById(r.accountId);
    const msg = recs.length > 1 ? `اتسجلوا ${recs.length} عمليات · ${fmt(recs.reduce((s, x) => s + x.amount, 0))} ${esc(S.settings.currency)}`
      : r.type === 'transfer' ? `تحويل ${fmt(r.amount)} من ${esc(a.name)} لـ ${esc(accById(r.toAccountId).name)} ✓`
      : `${esc(c ? c.icon + ' ' + c.name : '')} · <b class="num">${fmt(r.amount)}</b> · ${esc(a ? a.name : '')} ✓`;
    toast(msg, 'تراجع', () => { S.txns = S.txns.filter(t => !recs.includes(t)); save(); render(); toast('اتلغت'); },
      recs.length > 1 ? 'راجع' : 'عدّل', () => recs.length > 1 ? reviewDrafts(recs, text, true) : openTxSheet(recs[0]));
    if (complete.length < drafts.length) setTimeout(() => toast('في جزء مفهمتش مبلغه، ضيفه يدوي'), 6200);
  }

  function reviewDrafts(items, text, saved) {
    const html = `<h3>${saved ? 'العمليات اللي اتسجلت' : 'راجع قبل الحفظ'}</h3><p class="hint">«${esc(text)}»</p>
      ${items.map((d, i) => { const c = catById(d.categoryId); const a = accById(d.accountId); const to = accById(d.toAccountId);
        return `<button class="parsed-item" data-i="${i}"><span class="tx-ic">${d.type === 'transfer' ? '⇄' : esc(c ? c.icon : '•')}</span><span class="tx-main"><div class="tx-t">${esc(d.type === 'transfer' ? 'تحويل' : (c ? c.name : ''))}${d.note ? ' · ' + esc(d.note) : ''}</div><div class="tx-s">${esc(a ? a.name : '')}${to ? ' ← ' + esc(to.name) : ''} · ${dayLabel(d.date)}</div></span><span class="tx-a ${d.type} num">${fmt(d.amount)}</span></button>`; }).join('')}
      <p class="hint">دوس على أي عملية عشان تعدلها.</p>
      <div class="actions">${saved ? '<button class="btn primary" id="rOk">تمام</button>' : '<button class="btn" id="rNo">إلغاء</button><button class="btn primary" id="rOk">احفظ الكل</button>'}</div>`;
    openSheet(html, sh => {
      $$('[data-i]', sh).forEach(b => b.onclick = () => {
        const d = items[+b.dataset.i];
        if (saved) openTxSheet(d);
        else openTxSheet(Object.assign({}, d, { source: 'voice' }), { onSaved: rec => { items.splice(+b.dataset.i, 1); if (items.length) setTimeout(() => reviewDrafts(items, text), 50); } });
      });
      $('#rOk', sh).onclick = () => {
        if (!saved) { items.forEach(d => S.txns.push({ id: uid(), type: d.type, amount: d.amount, categoryId: d.categoryId, accountId: d.accountId, toAccountId: d.toAccountId, date: d.date, note: d.note, createdAt: new Date().toISOString(), source: 'voice', text: d.text })); save(); render(); toast('اتسجل ✓'); $('#smartInput').value = ''; }
        closeSheet();
      };
      const no = $('#rNo', sh); if (no) no.onclick = closeSheet;
    });
  }

  $('#smartForm').addEventListener('submit', e => { e.preventDefault(); handleText($('#smartInput').value); $('#smartInput').blur(); });
  $('#addBtn').addEventListener('click', () => openTxSheet(null));

  /* ---------- الصوت ---------- */
  const micBtn = $('#micBtn');
  let rec = null;
  micBtn.addEventListener('click', async () => {
    if (rec) { try { rec.stop(); } catch (e) { /* ignore */ } return; }
    const SR = plugin('SpeechRecognition');
    if (SR) return nativeListen(SR);
    const WebSR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!WebSR) return noVoice();
    webListen(WebSR);
  });

  async function nativeListen(SR) {
    try {
      const av = await SR.available();
      if (!av.available) { toast('التعرف على الصوت مش متاح. نزّل تطبيق Google من المتجر وجرب تاني.'); return; }
      const perm = await SR.requestPermissions();
      if (perm && perm.speechRecognition && perm.speechRecognition !== 'granted') { toast('محتاج إذن المايك عشان يسمعك'); return; }
      micBtn.classList.add('listening');
      const res = await SR.start({ language: S.settings.voiceLang, maxResults: 1, prompt: 'قول اللي دفعته…', partialResults: false, popup: true });
      micBtn.classList.remove('listening');
      const text = res && res.matches && res.matches[0];
      if (text) { $('#smartInput').value = text; handleText(text); }
    } catch (e) {
      micBtn.classList.remove('listening');
      toast('مسمعتش حاجة، جرب تاني');
    }
  }

  function webListen(WebSR) {
    rec = new WebSR();
    rec.lang = S.settings.voiceLang; rec.interimResults = true; rec.continuous = false; rec.maxAlternatives = 1;
    let finalText = '';
    openSheet(`<div class="listen-panel"><div class="wave" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div><div class="live" id="live">سامعك… قول اللي دفعته</div><button class="btn" id="stopL">خلصت</button></div>`, sh => { $('#stopL', sh).onclick = () => { try { rec && rec.stop(); } catch (e) { /* ignore */ } }; });
    micBtn.classList.add('listening');
    rec.onresult = e => {
      let interim = ''; finalText = '';
      for (let i = 0; i < e.results.length; i++) { const r = e.results[i]; if (r.isFinal) finalText += r[0].transcript; else interim += r[0].transcript; }
      const live = $('#live'); if (live) live.textContent = finalText + interim;
    };
    rec.onerror = e => {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') { rec = null; closeSheet(); micBtn.classList.remove('listening'); noVoice(true); }
    };
    rec.onend = () => {
      micBtn.classList.remove('listening'); rec = null;
      const live = $('#live'); const text = (finalText || (live && live.textContent !== 'سامعك… قول اللي دفعته' ? live.textContent : '')).trim();
      closeSheet();
      if (text) { $('#smartInput').value = text; handleText(text); }
    };
    try { rec.start(); } catch (e) { rec = null; closeSheet(); micBtn.classList.remove('listening'); noVoice(); }
  }

  function noVoice(denied) {
    const inp = $('#smartInput'); inp.focus();
    toast(denied ? 'المايك مقفول للتطبيق ده. استخدم مايك الكيبورد 🎙 واتكلم في الخانة.' : 'اضغط على مايك الكيبورد 🎙 واتكلم، وبعدين دوس إرسال.');
  }

  /* ---------- التصدير والاستيراد ---------- */
  function exportCsv() {
    const typeName = { expense: 'مصروف', income: 'دخل', transfer: 'تحويل' };
    const rows = [['التاريخ', 'النوع', 'المبلغ', 'التصنيف', 'الحساب', 'إلى حساب', 'ملاحظة', 'الطريقة']];
    S.txns.slice().sort((a, b) => a.date.localeCompare(b.date)).forEach(t => {
      const c = catById(t.categoryId), a = accById(t.accountId), to = accById(t.toAccountId);
      rows.push([t.date, typeName[t.type], t.amount, c ? c.name : '', a ? a.name : '', to ? to.name : '', t.note || '', t.source === 'voice' ? 'صوت' : t.source === 'sms' ? 'رسالة' : 'يدوي']);
    });
    const csv = '﻿' + rows.map(r => r.map(v => { v = String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }).join(',')).join('\r\n');
    shareFile(`masroofy-${today()}.csv`, csv, 'text/csv');
  }
  function exportJson() { shareFile(`masroofy-backup-${today()}.json`, JSON.stringify(S, null, 1), 'application/json'); }

  async function shareFile(name, content, mime) {
    const FS = plugin('Filesystem'), SH = plugin('Share');
    if (FS && SH) {
      try {
        const r = await FS.writeFile({ path: name, data: content, directory: 'CACHE', encoding: 'utf8' });
        await SH.share({ title: name, files: [r.uri], dialogTitle: 'احفظ أو ابعت الملف' });
        return;
      } catch (e) { if (String(e && e.message).toLowerCase().includes('cancel')) return; }
    }
    try {
      const file = new File([content], name, { type: mime });
      if (navigator.canShare && navigator.canShare({ files: [file] }) && /iphone|ipad|android/i.test(navigator.userAgent)) { await navigator.share({ files: [file], title: name }); return; }
    } catch (e) { if (e && e.name === 'AbortError') return; }
    try {
      const url = URL.createObjectURL(new Blob([content], { type: mime + ';charset=utf-8' }));
      const a = document.createElement('a'); a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 4000);
      toast('اتحمل الملف ' + esc(name), 'مش لاقيه؟', () => showCopy(content));
    } catch (e) { showCopy(content); }
  }
  function showCopy(content) {
    openSheet(`<h3>انسخ البيانات</h3><p class="hint">لو الملف متحملش، انسخ النص ده والصقه في ملف أو ابعته لنفسك.</p><textarea class="input" id="copyArea" rows="8" readonly style="direction:ltr;font-size:12px">${esc(content)}</textarea><div class="actions"><button class="btn primary" id="doCopy">نسخ</button></div>`, sh => {
      $('#doCopy', sh).onclick = () => { const ta = $('#copyArea', sh); (navigator.clipboard ? navigator.clipboard.writeText(content) : Promise.reject()).then(() => toast('اتنسخ ✓')).catch(() => { ta.select(); toast('النص متحدد، انسخه'); }); };
    });
  }

  $('#importFile').addEventListener('change', async e => {
    const f = e.target.files[0]; e.target.value = ''; if (!f) return;
    try {
      const d = JSON.parse(await f.text());
      if (!Array.isArray(d.txns) || !Array.isArray(d.accounts)) throw new Error('bad');
      if (await confirmSheet('تسترجع النسخة دي؟', `فيها ${d.txns.length} عملية و${d.accounts.length} حساب. البيانات الحالية هتتبدل بيها.`, 'استرجع')) {
        const f0 = fresh(); S = Object.assign(f0, d, { settings: Object.assign(f0.settings, d.settings || {}), budget: Object.assign(f0.budget, d.budget || {}) }); save(); applyTheme(); render(); toast('اترجعت البيانات ✓');
      }
    } catch (err) { toast('الملف ده مش نسخة احتياطية من مصروفي'); }
  });

  /* ---------- بيانات تجريبيه ---------- */
  function loadDemo() {
    const now = new Date(); const y = now.getFullYear(), m = now.getMonth(), D = now.getDate();
    const day = n => iso(new Date(y, m, Math.max(1, Math.min(D, n))));
    S.accounts.forEach(a => { a.initial = { cash: 3500, wallet: 800, instapay: 4000 }[a.id] || 0; });
    const lines = [[1, 'قبضت المرتب 15000 على انستاباي'], [1, 'دفعت الايجار 4000 من انستاباي'], [2, 'سحبت 2000 من انستاباي'], [3, 'سوبر ماركت 650'], [4, 'اوبر 85 انستاباي'], [5, 'كشري 60'], [6, 'فاتورة النت 250 فودافون كاش'], [7, 'قهوة 75 و بنزين 400'], [8, 'صيدلية 180'], [9, 'هدوم 1200 انستاباي'], [10, 'سينما 220'], [11, 'طلبات 310 فودافون كاش'], [12, 'ميكروباص 20'], [13, 'كورس 900 انستاباي'], [14, 'فراخ وخضار 540'], [16, 'جالي 3000 من عميل على فودافون كاش'], [17, 'غدا 190'], [19, 'كهربا 430'], [21, 'اوبر 120 انستاباي'], [23, 'هدية 500'], [25, 'سوبر ماركت 820']];
    lines.forEach(([n, text]) => {
      if (n > D && D > 3) return;
      MasroofyParser.parse(text, Object.assign(parseCtx(), { today: new Date(day(n) + 'T12:00:00') })).forEach(d => { if (d.amount) S.txns.push(Object.assign({ id: uid(), createdAt: new Date().toISOString(), source: 'voice' }, d, { date: day(n) })); });
    });
    save(); render(); toast('دي بيانات تجريبية. امسحها من الإعدادات لما تبدأ بجد.');
  }

  /* ---------- رسايل البنك والمحافظ ---------- */
  const N = s => MasroofyParser.normalize(s);
  function senderLabel(id) {
    const p = MasroofySms.PROVIDERS.find(x => x.id === id);
    return p ? p.name : id.replace(/^sender:/, '');
  }
  // الرصيد لحد لحظه معينه (عشان نقارنه برصيد رسالة البنك)
  function balanceAt(accId, ms) {
    const a = accById(accId); let b = a ? +a.initial || 0 : 0;
    S.txns.forEach(t => {
      const tm = t.time || Date.parse(t.date + 'T23:59:59');
      if (tm > ms) return;
      if (t.type === 'expense' && t.accountId === accId) b -= t.amount;
      else if (t.type === 'income' && t.accountId === accId) b += t.amount;
      else if (t.type === 'transfer') { if (t.accountId === accId) b -= t.amount; if (t.toAccountId === accId) b += t.amount; }
    });
    return b;
  }
  let createdAccounts = [];
  const pidFor = (address, provider) => provider ? provider.id : 'sender:' + (address || '').trim();
  function accountForSms(address, provider, pasted, dry) {
    if (!provider && pasted) return accById(S.settings.defaultAccount) || S.accounts[0];
    const pid = pidFor(address, provider);
    const linked = x => (x.smsSenders || []).filter(k => k !== 'instapay');
    let a = S.accounts.find(x => (x.smsSenders || []).includes(pid));
    if (!a && provider && provider.id === 'instapay') a = S.accounts.find(x => x.type === 'instapay');
    if (!a && provider) {
      const pn = N(provider.name);
      // نفس نوع الحساب بس: محفظه لمحفظه، بنك لبنك/انستاباي (عشان «فودافون كاش» متروحش للكاش اللي في إيدك)
      const fits = x => provider.type === 'wallet' ? x.type === 'wallet' : ['bank', 'instapay', 'other'].includes(x.type);
      a = S.accounts.find(x => fits(x) && !linked(x).length && [x.name].concat(x.keywords || []).some(k => { const kk = N(k); return kk.length > 3 && (kk === pn || kk.includes(pn) || pn.includes(kk)); }));
    }
    if (!a && provider) {
      const def = provider.type === 'wallet' ? 'wallet' : (provider.type === 'bank' ? 'instapay' : null);
      a = S.accounts.find(x => x.id === def && !linked(x).length);
    }
    if (dry) return a || { id: null, isNew: true, name: provider ? provider.name : (address || 'حساب من الرسايل') };
    if (!a) {
      a = { id: uid(), name: provider ? provider.name : (address || 'حساب من الرسايل'), type: provider ? provider.type : 'bank', initial: 0, keywords: provider ? [provider.name] : [], smsSenders: [] };
      if (!ACC_TYPES[a.type]) a.type = 'other';
      S.accounts.push(a); createdAccounts.push(a.name);
    }
    a.smsSenders = a.smsSenders || [];
    if (!a.smsSenders.includes(pid)) a.smsSenders.push(pid);
    return a;
  }

  function categoryForSms(p, body) {
    const kind = p.kind === 'expense' ? 'expense' : 'income';
    if (kind === 'income') {
      if (/(refund|استرداد|مرتجع|reversal)/i.test(N(body))) return 'refund';
      if (/(مرتب|راتب|salary|payroll)/.test(N(body))) return 'salary';
    }
    // التصنيف من اسم المحل الأول، ولو مفيش محل من نص الرساله من غير جملة الرصيد
    const text = p.merchant || N(body).replace(/(رصيد|balance|avl|available).*$/, '');
    const learned = text && MasroofyParser.findCategory(text, S.categories, kind);
    if (learned && !(p.isTransfer && !p.merchant)) return learned.id;
    if (p.isTransfer) return kind === 'expense' ? 'transfer_out' : 'transfer_in';
    const fb = S.categories.find(c => c.kind === kind && c.fallback);
    return fb ? fb.id : null;
  }

  // قواعد المستخدم: أطول كلمه بتكسب
  function ruleFor(text) {
    const t = N(text);
    return S.smsRules.slice().sort((a, b) => b.match.length - a.match.length).find(r => { const m = N(r.match); return m && t.includes(m); }) || null;
  }
  function upsertRule(match, categoryId) {
    match = String(match || '').trim(); if (!match) return null;
    let r = S.smsRules.find(x => N(x.match) === N(match));
    if (r) r.categoryId = categoryId; else { r = { id: uid(), match, categoryId }; S.smsRules.push(r); }
    return r;
  }

  // بيقرر الرساله هتتسجل إزاي، أو ليه مش هتتسجل. dry = تجربه من غير ما يعمل حسابات أو يربط جهات
  function analyzeSms(m, opts = {}) {
    const st = S.settings.sms;
    if (!opts.pasted && MasroofySms.isPhoneSender(m.address)) return { skip: 'رسالة من رقم موبايل عادي، مش من بنك أو محفظة' };
    const p = MasroofySms.parse(m);
    if (!p) return { skip: 'مفيهاش عملية فلوس واضحة (ممكن تكون كود أو عرض أو رصيد بس)' };
    const pid = pidFor(m.address, p.provider);
    if ((st.ignored || []).includes(pid)) return { skip: `رسايل «${senderLabel(pid)}» متجاهلة من إعداداتك`, p };
    if (st.minAmount > 0 && p.amount < st.minAmount) return { skip: `المبلغ ${fmt(p.amount)} أقل من الحد اللي حطيته (${fmt(st.minAmount)})`, p };
    const rule = ruleFor((p.merchant || '') + ' ' + m.body);
    if (rule && rule.categoryId === '__ignore') return { skip: `قاعدتك «${rule.match}»: متسجلهاش`, p, rule };
    const acc = accountForSms(m.address, p.provider, opts.pasted, opts.dry);
    const base = { id: uid(), amount: p.amount, date: iso(p.date), time: p.time, createdAt: new Date().toISOString(), source: 'sms', sms: m.body, merchant: p.merchant || '', smsFrom: pid };
    let rec;
    if (p.kind === 'atm') {
      const cash = S.accounts.find(a => a.type === 'cash' && a.id !== acc.id);
      rec = cash && st.atmMode !== 'expense' ? Object.assign(base, { type: 'transfer', accountId: acc.id, toAccountId: cash.id, categoryId: null, note: 'سحب من الماكينة' })
        : Object.assign(base, { type: 'expense', accountId: acc.id, categoryId: 'other', note: 'سحب من الماكينة' });
    } else {
      const type = p.kind === 'expense' ? 'expense' : 'income';
      const note = p.merchant ? (p.isTransfer ? (type === 'expense' ? 'تحويل لـ ' : 'تحويل من ') + p.merchant : p.merchant) : (p.isTransfer ? (type === 'expense' ? 'تحويل' : 'تحويل جالك') : '');
      rec = Object.assign(base, { type, accountId: acc.id, toAccountId: null, categoryId: categoryForSms(p, m.body), note });
    }
    if (rule && rec.type !== 'transfer') { const rc = catById(rule.categoryId); if (rc && rc.kind === rec.type) rec.categoryId = rc.id; }
    return { rec, acc, p, pid, rule };
  }

  function ingestSms(messages, opts = {}) {
    createdAccounts = [];
    const seen = new Set(S.smsSeen);
    const added = [], pending = [];
    const review = S.settings.sms.review && !opts.pasted;
    messages.slice().sort((a, b) => a.date - b.date).forEach(m => {
      if (!opts.pasted && MasroofySms.isPhoneSender(m.address)) return; // رسايل الناس العاديه
      const key = MasroofySms.keyOf(m);
      if (seen.has(key)) return;
      const a = analyzeSms(m, opts);
      if (!a.p) return;
      seen.add(key); S.smsSeen.push(key);
      if (a.skip) return;
      const { rec, acc, p } = a;
      if (p.balance != null && (!acc.smsBalanceAt || p.time >= acc.smsBalanceAt)) { acc.smsBalance = p.balance; acc.smsBalanceAt = p.time; }
      if (review) { S.smsPending.push(rec); pending.push(rec); }
      else { S.txns.push(rec); added.push(rec); }
    });
    if (S.smsSeen.length > 4000) S.smsSeen = S.smsSeen.slice(-3000);
    if (S.settings.sms.pair) pairOwnTransfers(added);
    calibrate(added);
    save();
    const out = added.filter(r => S.txns.includes(r));
    out.pending = pending;
    return out;
  }

  // العمليات اللي مستنيه موافقتك
  function approvePending(list) {
    list.forEach(r => S.txns.push(r));
    S.smsPending = S.smsPending.filter(x => !list.includes(x));
    if (S.settings.sms.pair) pairOwnTransfers(list);
    calibrate(list);
    save();
  }
  function pendingSheet() {
    const items = S.smsPending;
    if (!items.length) { closeSheet(); render(); return; }
    $('#toastHost').innerHTML = '';
    openSheet(`<h3>مستنية موافقتك (<span class="num">${items.length}</span>)</h3>
      <p class="hint">✓ تسجلها، ✕ تتجاهلها، أو دوس على العملية نفسها عشان تعدلها قبل ما تتسجل.</p>
      ${items.map((d, i) => { const c = catById(d.categoryId); const a = accById(d.accountId); const to = accById(d.toAccountId);
        return `<div class="pend-row"><button class="parsed-item" data-pedit="${i}"><span class="tx-ic">${d.type === 'transfer' ? '⇄' : esc(c ? c.icon : '•')}</span><span class="tx-main"><div class="tx-t">${esc(d.note || (c ? c.name : ''))}</div><div class="tx-s">${esc(c ? c.name + ' · ' : '')}${esc(a ? a.name : '')}${to ? ' ← ' + esc(to.name) : ''} · ${esc(dayLabel(d.date))}</div></span><span class="tx-a ${d.type} num">${d.type === 'expense' ? '−' : d.type === 'income' ? '+' : ''}${fmt(d.amount)}</span></button>
          <button class="icon-btn sm ok" data-pok="${i}" aria-label="سجّلها">✓</button><button class="icon-btn sm no" data-pno="${i}" aria-label="تجاهلها">✕</button></div>`; }).join('')}
      <div class="actions"><button class="btn" id="pNo">تجاهل الكل</button><button class="btn primary" id="pOk">سجّل الكل</button></div>`, sh => {
      $$('[data-pok]', sh).forEach(b => b.onclick = () => { approvePending([items[+b.dataset.pok]]); toast('اتسجلت ✓'); pendingSheet(); });
      $$('[data-pno]', sh).forEach(b => b.onclick = () => { S.smsPending.splice(+b.dataset.pno, 1); save(); pendingSheet(); });
      $$('[data-pedit]', sh).forEach(b => b.onclick = () => {
        const d = items[+b.dataset.pedit];
        openTxSheet(Object.assign({}, d, { id: undefined }), { onSaved: () => { S.smsPending = S.smsPending.filter(x => x !== d); save(); setTimeout(pendingSheet, 60); } });
      });
      $('#pOk', sh).onclick = () => { const n = items.length; approvePending(items.slice()); closeSheet(); render(); toast(`اتسجل ${n} ${n === 1 ? 'عملية' : 'عمليات'} ✓`); };
      $('#pNo', sh).onclick = () => { S.smsPending = []; save(); closeSheet(); render(); toast('اتجاهلت'); };
    });
  }

  // تحويل من حساب ليك لحساب تاني ليك بييجي في رسالتين (خصم هنا وإيداع هناك): نخليهم عملية تحويل واحده
  function pairOwnTransfers(added) {
    if (!added.length) return;
    const recent = S.txns.filter(t => t.source === 'sms' && t.type !== 'transfer' && t.time);
    recent.filter(t => t.type === 'expense' && t.categoryId === 'transfer_out').forEach(out => {
      const inc = recent.find(t => t.type === 'income' && t.categoryId === 'transfer_in' && t.accountId !== out.accountId && Math.abs(t.amount - out.amount) < 0.01 && Math.abs(t.time - out.time) < 20 * 60 * 1000 && S.txns.includes(t));
      if (!inc || !S.txns.includes(out) || (!added.includes(out) && !added.includes(inc))) return;
      Object.assign(out, { type: 'transfer', toAccountId: inc.accountId, categoryId: null, note: 'تحويل بين حساباتك', sms: out.sms + '\n\n' + inc.sms });
      S.txns = S.txns.filter(t => t !== inc);
    });
  }

  // أول مره حساب يتربط برسايل فيها رصيد، نظبط رصيده الافتتاحي على رصيد البنك
  function calibrate(added) {
    S.accounts.forEach(a => {
      if (a.calibrated || a.smsBalance == null || !added.some(r => r.accountId === a.id || r.toAccountId === a.id)) return;
      if (+a.initial === 0) a.initial = a.smsBalance - balanceAt(a.id, a.smsBalanceAt);
      a.calibrated = true;
    });
  }

  function announceSms(added) {
    render();
    if (!added.length && added.pending && added.pending.length) {
      const n = added.pending.length;
      toast(`📩 ${n === 1 ? 'عملية جديدة' : n + ' عمليات جديدة'} من الرسايل مستنية موافقتك`, 'راجع', pendingSheet);
      return;
    }
    if (!added.length) return;
    const total = added.reduce((s, r) => s + r.amount, 0);
    const extra = createdAccounts.length ? ` · حساب جديد: ${createdAccounts.map(esc).join('، ')}` : '';
    const r = added[0]; const c = catById(r.categoryId); const a = accById(r.accountId);
    const msg = added.length === 1
      ? `📩 ${r.type === 'transfer' ? 'تحويل' : esc(c ? c.name : '')} · <b class="num">${fmt(r.amount)}</b> · ${esc(a ? a.name : '')}${extra}`
      : `📩 اتسجل ${added.length} عمليات من الرسايل${extra}`;
    toast(msg, 'راجع', () => added.length === 1 ? openTxSheet(added[0]) : reviewDrafts(added, 'من رسايل البنك والمحافظ', true));
  }

  const smsPlugin = () => plugin('SmsReader');
  const monthStart = () => { const d = new Date(); return new Date(d.getFullYear(), d.getMonth(), 1).getTime(); };
  let syncing = false;
  async function smsSync(opts = {}) {
    const R = smsPlugin();
    if (!R || !S.settings.sms.enabled || syncing) return;
    syncing = true;
    try {
      const since = opts.since != null ? opts.since : (S.settings.sms.lastSync || monthStart());
      const res = await R.read({ since, limit: 3000 });
      const msgs = ((res && res.messages) || []).filter(m => +m.date > since);
      const newest = msgs.reduce((m, x) => Math.max(m, +x.date || 0), since);
      const added = ingestSms(msgs);
      S.settings.sms.lastSync = Math.max(S.settings.sms.lastSync || 0, newest);
      save();
      if (added.length || added.pending.length) announceSms(added); else if (opts.manual) toast('مفيش رسايل جديدة');
    } catch (e) {
      if (String(e && (e.code || e.message)).includes('PERMISSION')) { S.settings.sms.enabled = false; save(); if (opts.manual) smsGuide(); }
    } finally { syncing = false; }
  }

  async function enableSms() {
    const R = smsPlugin(); if (!R) return;
    let st = {};
    try { st = await R.checkPermissions(); if (st.sms !== 'granted') st = await R.requestPermissions(); } catch (e) { /* ignore */ }
    if (st.sms !== 'granted') { smsGuide(); return; }
    const since = await pickSince('تسجّل الرسايل من إمتى؟', 'الرسايل اللي بعد كده هتتسجل لوحدها.');
    if (since == null) return;
    S.settings.sms.enabled = true; save();
    await smsSync({ since, manual: true });
    if (view === 'set') renderSet();
  }

  // اختيار بداية سحب الرسايل
  function pickSince(title, hint) {
    const d = new Date();
    const opts = [
      ['today', 'من النهارده بس', new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()],
      ['month', 'من أول الشهر ده', monthStart()],
      ['last', 'من أول الشهر اللي فات', new Date(d.getFullYear(), d.getMonth() - 1, 1).getTime()]
    ];
    return new Promise(res => {
      openSheet(`<h3>${esc(title)}</h3><p class="hint">${esc(hint)}</p>
        <div style="display:grid;gap:8px;margin-bottom:12px">${opts.map(([k, n]) => `<button class="btn" data-since="${k}">${n}</button>`).join('')}</div>
        <div class="actions"><button class="btn" id="sCancel">إلغاء</button></div>`, sh => {
        $$('[data-since]', sh).forEach(b => b.onclick = () => { closeSheet(); res(opts.find(o => o[0] === b.dataset.since)[2]); });
        $('#sCancel', sh).onclick = () => { closeSheet(); res(null); };
      });
    });
  }

  // مسح اللي اتسجل من الرسايل (كله، أو القديم بس)
  function clearSmsSheet() {
    const all = S.txns.filter(t => t.source === 'sms');
    const ms = monthStart();
    const old = all.filter(t => (t.time || Date.parse(t.date)) < ms);
    openSheet(`<h3>مسح اللي اتسجل من الرسايل</h3>
      <p class="hint" style="font-size:14px">اتسجل من الرسايل <b class="num">${all.length}</b> عملية، منهم <b class="num">${old.length}</b> قبل الشهر ده. العمليات اللي سجلتها بإيدك أو بالصوت مش هتتلمس.</p>
      <div style="display:grid;gap:8px;margin-bottom:12px">
        <button class="btn" id="cOld" ${old.length ? '' : 'disabled'}>امسح اللي قبل الشهر ده بس</button>
        <button class="btn danger" id="cAll" ${all.length ? '' : 'disabled'}>امسح كل اللي جه من الرسايل</button>
      </div>
      <div class="actions"><button class="btn" id="cCancel">إلغاء</button></div>`, sh => {
      $('#cCancel', sh).onclick = closeSheet;
      $('#cOld', sh).onclick = () => doClear(old, false);
      $('#cAll', sh).onclick = () => doClear(all, true);
    });
  }
  function doClear(list, everything) {
    const backup = JSON.stringify({ txns: S.txns, accounts: S.accounts, smsSeen: S.smsSeen, sms: S.settings.sms, def: S.settings.defaultAccount });
    const gone = new Set(list.map(t => t.id));
    S.txns = S.txns.filter(t => !gone.has(t.id));
    if (everything) { S.smsSeen = []; S.settings.sms.lastSync = Date.now(); }
    // الحسابات اللي اتعملت من الرسايل وفضيت تتشال، والباقي رصيده يتظبط على آخر رسالة بنك
    const keep = new Set(MasroofyDefaults.accounts.map(a => a.id));
    S.accounts = S.accounts.filter(a => keep.has(a.id) || !(a.smsSenders || []).length || S.txns.some(t => t.accountId === a.id || t.toAccountId === a.id));
    if (!accById(S.settings.defaultAccount)) S.settings.defaultAccount = S.accounts[0].id;
    S.accounts.forEach(a => {
      if (everything) a.smsSenders = [];
      if (a.calibrated && a.smsBalance != null) {
        if (everything) { a.initial = 0; a.calibrated = false; delete a.smsBalance; delete a.smsBalanceAt; }
        else { a.initial = 0; a.initial = a.smsBalance - balanceAt(a.id, a.smsBalanceAt); }
      }
    });
    save(); closeSheet(); render();
    toast(`اتمسح ${list.length} عملية`, 'تراجع', () => {
      const b = JSON.parse(backup);
      S.txns = b.txns; S.accounts = b.accounts; S.smsSeen = b.smsSeen; S.settings.sms = b.sms; S.settings.defaultAccount = b.def;
      save(); render(); toast('رجعت ✓');
    });
  }

  function smsGuide() {
    openSheet(`<h3>محتاج إذن الرسايل</h3>
      <p class="hint" style="font-size:14px">أندرويد بيقفل إذن الرسايل للتطبيقات اللي اتثبتت من ملف APK. افتحه مرة واحدة كده:</p>
      <ol class="hint steps">
        <li>دوس «افتح إعدادات التطبيق» تحت.</li>
        <li>دوس على النقط التلاتة ⋮ فوق، واختار <b>«السماح بالإعدادات المقيدة»</b> (Allow restricted settings)، وأكد ببصمتك.</li>
        <li>ادخل <b>الأذونات ← الرسائل القصيرة (SMS)</b> واختار «سماح».</li>
        <li>ارجع للتطبيق ودوس «شغّل قراءة الرسايل» تاني.</li>
      </ol>
      <p class="hint">لو مش لاقي «السماح بالإعدادات المقيدة»: ادخل على الأذونات على طول، وأول ما تحاول تفعل الرسايل هيطلع لك تنبيه، ارجع بعده للنقط التلاتة هتلاقيه ظهر.</p>
      <div class="actions"><button class="btn" id="gClose">بعدين</button><button class="btn primary" id="gOpen">افتح إعدادات التطبيق</button></div>`, sh => {
      $('#gClose', sh).onclick = closeSheet;
      $('#gOpen', sh).onclick = () => { closeSheet(); const R = smsPlugin(); R && R.openAppSettings().catch(() => {}); };
    });
  }

  function smsCard() {
    const st = S.settings.sms;
    const linked = S.accounts.filter(a => (a.smsSenders || []).length);
    if (!isNative) {
      return `<div class="card"><div class="card-head"><h2>رسايل البنك والمحافظ</h2></div>
        <p class="hint">التسجيل التلقائي من الرسايل شغال على نسخة الأندرويد. على الآيفون أبل مش بتسمح لأي تطبيق يقرا الرسايل، فانسخ رسالة البنك أو المحفظة والصقها في خانة الكتابة تحت، وهو هيعرف المبلغ والحساب ويسجلها.</p>
        <div class="actions"><button class="btn" id="smsCtl">تحكم في الرسايل</button></div></div>`;
    }
    return `<div class="card"><div class="card-head"><h2>رسايل البنك والمحافظ</h2><span class="pill">${st.enabled ? 'شغّال ✓' : 'مقفول'}</span></div>
      <p class="hint">أي رسالة خصم أو إيداع أو تحويل أو سحب من البنك، فودافون كاش، اورنج كاش، اتصالات كاش، وي باي أو انستاباي بتتسجل لوحدها في الحساب الصح. رسايل الأكواد والعروض بيتجاهلها.</p>
      ${st.enabled ? `<div class="set-row"><div><div class="t">آخر تحديث</div><div class="d">${st.lastSync ? esc(dayLabel(iso(new Date(st.lastSync)))) + ' ' + new Date(st.lastSync).toLocaleTimeString('ar-EG', { hour: 'numeric', minute: '2-digit' }) : '—'}</div></div><button class="btn small" id="smsNow">حدّث دلوقتي</button></div>
        <div class="set-row"><div><div class="t">الحسابات المربوطة</div><div class="d">${linked.length ? linked.map(a => esc(a.name)).join('، ') : 'لسه مفيش رسايل اتقرت'}</div></div></div>
        <div class="actions"><button class="btn" id="smsMonth">اسحب رسايل قديمة</button><button class="btn" id="smsOff">وقّف</button></div>`
      : `<div class="actions"><button class="btn primary" id="smsOn">شغّل قراءة الرسايل</button></div>`}
      ${S.smsPending.length ? `<div class="set-row"><div><div class="t">مستنية موافقتك</div><div class="d"><span class="num">${S.smsPending.length}</span> عملية</div></div><button class="btn small primary" id="smsPend">راجع</button></div>` : ''}
      <div class="actions"><button class="btn" id="smsCtl">تحكم في الرسايل</button></div>
      ${S.txns.some(t => t.source === 'sms') ? '<div class="actions"><button class="btn danger" id="smsClear">امسح اللي اتسجل من الرسايل</button></div>' : ''}
    </div>`;
  }
  function bindSmsCard(el) {
    const on = $('#smsOn', el); if (on) on.onclick = enableSms;
    const now = $('#smsNow', el); if (now) now.onclick = async () => { await smsSync({ manual: true }); renderSet(); };
    const month = $('#smsMonth', el); if (month) month.onclick = async () => { const since = await pickSince('تسحب الرسايل من إمتى؟', 'الرسايل اللي اتسجلت قبل كده مش هتتكرر.'); if (since == null) return; await smsSync({ since, manual: true }); renderSet(); };
    const clr = $('#smsClear', el); if (clr) clr.onclick = clearSmsSheet;
    const ctl = $('#smsCtl', el); if (ctl) ctl.onclick = () => smsControlSheet();
    const pnd = $('#smsPend', el); if (pnd) pnd.onclick = pendingSheet;
    const off = $('#smsOff', el); if (off) off.onclick = () => { S.settings.sms.enabled = false; save(); renderSet(); toast('وقفت قراءة الرسايل'); };
  }

  function smsControlSheet(keepTest) {
    const st = S.settings.sms;
    const owner = pid => S.accounts.find(a => (a.smsSenders || []).includes(pid));
    const pids = [...new Set([].concat(...S.accounts.map(a => a.smsSenders || []), st.ignored || [], S.txns.map(t => t.smsFrom).filter(Boolean)))];
    const catOpts = sel => `<optgroup label="مصاريف">${S.categories.filter(c => c.kind === 'expense').map(c => `<option value="${esc(c.id)}" ${sel === c.id ? 'selected' : ''}>${esc(c.icon + ' ' + c.name)}</option>`).join('')}</optgroup>
      <optgroup label="دخل">${S.categories.filter(c => c.kind === 'income').map(c => `<option value="${esc(c.id)}" ${sel === c.id ? 'selected' : ''}>${esc(c.icon + ' ' + c.name)}</option>`).join('')}</optgroup>
      <option value="__ignore" ${sel === '__ignore' ? 'selected' : ''}>🚫 متسجلهاش</option>`;
    const ruleLabel = r => r.categoryId === '__ignore' ? '🚫 متسجلهاش' : (c => c ? esc(c.icon + ' ' + c.name) : 'تصنيف محذوف')(catById(r.categoryId));
    const testVal = keepTest || { body: '', from: '' };
    openSheet(`<h3>تحكم في الرسايل</h3>

      <div class="sec-title">طريقة التسجيل</div>
      <div class="set-row"><div><div class="t">اسألني قبل ما يسجل</div><div class="d">الرسايل الجديدة تستنى موافقتك بدل ما تتسجل على طول</div></div><button class="btn small ${st.review ? 'primary' : ''}" id="cReview">${st.review ? 'شغّال' : 'مقفول'}</button></div>
      <div class="set-row"><div><div class="t">تجاهل المبالغ الصغيرة</div><div class="d">زي رسوم التحويل (جنيه أو اتنين). سيبها فاضية عشان يسجل كله</div></div><input class="input num mini" id="cMin" inputmode="decimal" placeholder="مثلاً 5" value="${st.minAmount || ''}"></div>
      <div class="set-row"><div><div class="t">السحب من الماكينة</div><div class="d">يتسجل إزاي</div></div><select class="input mini" id="cAtm"><option value="transfer" ${st.atmMode !== 'expense' ? 'selected' : ''}>تحويل للكاش اللي معايا</option><option value="expense" ${st.atmMode === 'expense' ? 'selected' : ''}>مصروف</option></select></div>
      <div class="set-row"><div><div class="t">التحويل بين حساباتي</div><div class="d">خصم من حساب وإيداع في حساب تاني بنفس المبلغ خلال ربع ساعة = تحويل واحد</div></div><button class="btn small ${st.pair ? 'primary' : ''}" id="cPair">${st.pair ? 'شغّال' : 'مقفول'}</button></div>

      <div class="sec-title">الجهات</div>
      ${pids.length ? pids.map(pid => { const o = owner(pid); const ign = (st.ignored || []).includes(pid);
        return `<div class="set-row"><div><div class="t">${esc(senderLabel(pid))}</div><div class="d">${S.txns.filter(t => t.smsFrom === pid).length} عملية</div></div>
          <select class="input mini" data-sender="${esc(pid)}">${S.accounts.map(a => `<option value="${esc(a.id)}" ${!ign && o && o.id === a.id ? 'selected' : ''}>${esc(a.name)}</option>`).join('')}<option value="__ignore" ${ign ? 'selected' : ''}>🚫 تجاهل رسايلها</option></select></div>`; }).join('')
        : '<p class="hint">لسه مفيش جهات. أول ما رسالة من بنك أو محفظة تتقري هتظهر هنا، وتقدر تختار تروح لأنهي حساب أو تتجاهلها.</p>'}

      <div class="sec-title">قواعدك</div>
      <p class="hint">لو اسم المحل أو نص الرسالة فيه الكلمة، يتحط في التصنيف ده أو ميتسجلش خالص. ولما تغيّر تصنيف عملية جت من رسالة، القاعدة بتتعمل لوحدها.</p>
      ${S.smsRules.length ? S.smsRules.map(r => `<div class="set-row"><div><div class="t">«${esc(r.match)}»</div><div class="d">← ${ruleLabel(r)}</div></div><button class="btn small danger" data-rdel="${esc(r.id)}">حذف</button></div>`).join('') : ''}
      <div class="rule-add"><input class="input" id="rMatch" placeholder="كلمة، مثلاً: CARREFOUR أو اسم شخص"><select class="input" id="rCat">${catOpts('food')}</select><button class="btn small primary" id="rAdd">ضيف</button></div>

      <div class="sec-title">جرّب رسالة</div>
      <p class="hint">الصق رسالة وشوف هتتقري إزاي من غير ما تتسجل.</p>
      <textarea class="input" id="tBody" rows="3" placeholder="الصق الرسالة هنا">${esc(testVal.body)}</textarea>
      <div class="rule-add"><input class="input" id="tFrom" placeholder="اسم المرسل، مثلاً CIB (اختياري)" value="${esc(testVal.from)}"><button class="btn small primary" id="tRun">جرّب</button></div>
      <div id="tOut"></div>

      <div class="actions" style="margin-top:14px"><button class="btn primary" id="cDone">تمام</button></div>`, sh => {
      const redraw = () => { const sc = sh.scrollTop; smsControlSheet({ body: $('#tBody', sh).value, from: $('#tFrom', sh).value }); const n = $('.sheet'); if (n) n.scrollTop = sc; };
      $('#cDone', sh).onclick = () => { closeSheet(); render(); };
      $('#cReview', sh).onclick = () => { st.review = !st.review; save(); redraw(); };
      $('#cPair', sh).onclick = () => { st.pair = !st.pair; save(); redraw(); };
      $('#cMin', sh).onchange = e => { st.minAmount = Math.max(0, parseFloat(N(e.target.value)) || 0); save(); toast(st.minAmount ? `هيتجاهل أي مبلغ أقل من ${fmt(st.minAmount)}` : 'هيسجل كل المبالغ'); };
      $('#cAtm', sh).onchange = e => { st.atmMode = e.target.value; save(); toast('اتحفظ. ده للرسايل الجاية'); };
      $$('[data-sender]', sh).forEach(sel => sel.onchange = () => {
        const pid = sel.dataset.sender, target = sel.value;
        S.accounts.forEach(a => { a.smsSenders = (a.smsSenders || []).filter(x => x !== pid); });
        st.ignored = (st.ignored || []).filter(x => x !== pid);
        if (target === '__ignore') { st.ignored.push(pid); save(); toast(`مش هيسجل رسايل «${esc(senderLabel(pid))}» تاني`); return redraw(); }
        const a = accById(target); a.smsSenders = a.smsSenders || []; a.smsSenders.push(pid);
        let moved = 0;
        S.txns.forEach(t => { if (t.smsFrom === pid && t.accountId !== a.id && t.toAccountId !== a.id) { t.accountId = a.id; moved++; } });
        save(); toast(`رسايل «${esc(senderLabel(pid))}» هتروح لـ «${esc(a.name)}»${moved ? ` · اتنقل ${moved} عملية قديمة` : ''}`); redraw();
      });
      $$('[data-rdel]', sh).forEach(b => b.onclick = () => { S.smsRules = S.smsRules.filter(r => r.id !== b.dataset.rdel); save(); redraw(); });
      $('#rAdd', sh).onclick = () => {
        const match = $('#rMatch', sh).value.trim(); const cat = $('#rCat', sh).value;
        if (N(match).length < 2) { toast('اكتب كلمة من حرفين على الأقل'); return; }
        upsertRule(match, cat);
        // نطبّقها على اللي اتسجل قبل كده من الرسايل
        let n = 0; const c = catById(cat);
        if (c) S.txns.forEach(t => { if (t.source === 'sms' && t.type === c.kind && t.categoryId !== c.id && N((t.merchant || '') + ' ' + (t.sms || '')).includes(N(match))) { t.categoryId = c.id; n++; } });
        save(); toast(cat === '__ignore' ? 'الرسايل الجاية اللي فيها الكلمة دي مش هتتسجل' : `اتضافت القاعدة${n ? ` واتطبقت على ${n} عملية قديمة` : ''}`); redraw();
      };
      $('#tRun', sh).onclick = () => {
        const body = $('#tBody', sh).value.trim(); const from = $('#tFrom', sh).value.trim();
        const out = $('#tOut', sh);
        if (!body) { out.innerHTML = '<div class="test-out">الصق رسالة الأول.</div>'; return; }
        const a = analyzeSms({ address: from, body, date: Date.now() }, { dry: true, pasted: !from });
        if (a.skip) { out.innerHTML = `<div class="test-out bad">✕ مش هتتسجل: ${esc(a.skip)}</div>`; return; }
        const r = a.rec; const c = catById(r.categoryId); const to = accById(r.toAccountId);
        const typeName = { expense: 'مصروف', income: 'دخل', transfer: 'تحويل' }[r.type];
        out.innerHTML = `<div class="test-out good">✓ هتتسجل كده:<br>
          <b>${typeName}</b> · <b class="num">${fmt(r.amount)}</b> ${esc(S.settings.currency)}<br>
          ${r.type === 'transfer' ? `من «${esc(a.acc.name)}» لـ «${esc(to ? to.name : '')}»` : `${esc(c ? c.icon + ' ' + c.name : '')} · ${r.type === 'income' ? 'على' : 'من'} «${esc(a.acc.name)}»${a.acc.isNew ? ' (هيتعمل حساب جديد)' : ''}`}<br>
          ${r.note ? `ملاحظة: ${esc(r.note)}<br>` : ''}${a.p.balance != null ? `الرصيد في الرسالة: <span class="num">${fmt(a.p.balance)}</span><br>` : ''}${a.rule ? `بسبب قاعدتك «${esc(a.rule.match)}»` : ''}</div>`;
      };
      if (keepTest && keepTest.body) $('#tRun', sh).onclick();
    });
  }

  /* ---------- تشغيل ---------- */
  applyTheme();
  go('home');
  if ('serviceWorker' in navigator && !isNative && location.protocol === 'https:') {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
  if (isNative) {
    const App = plugin('App');
    if (App && App.addListener) {
      App.addListener('backButton', () => { if ($('#scrim')) closeSheet(); else if (sel) { sel = null; renderTx(); } else if (view !== 'home') go('home'); else App.exitApp(); });
      App.addListener('resume', () => smsSync());
    }
    const R = smsPlugin();
    if (R && R.addListener) R.addListener('sms', m => { if (!S.settings.sms.enabled) return; const added = ingestSms([m]); if (added.length || added.pending.length) announceSms(added); });
    smsSync();
  }
})();
