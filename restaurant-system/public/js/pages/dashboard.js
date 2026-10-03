'use strict';

// رسم أعمدة رأسية (سلسلة واحدة)
function vBars(rows, { label, value, tip }) {
  if (!rows.length) return '<div class="empty small">لا توجد بيانات</div>';
  const max = Math.max(...rows.map(value), 1);
  const step = Math.ceil(rows.length / 12);
  return `<div class="chart"><div class="vbars">${rows.map((r) => `<div class="col" data-tip="${esc(tip(r))}"><div class="bar" style="height:${(value(r) / max) * 100}%"></div></div>`).join('')}</div>
    <div class="vbars-labels">${rows.map((r, i) => `<span>${i % step === 0 ? esc(label(r)) : ''}</span>`).join('')}</div></div>`;
}

// رسم أشرطة أفقية
function hBars(rows, { name, value, display }) {
  if (!rows.length) return '<div class="empty small">لا توجد بيانات</div>';
  const max = Math.max(...rows.map(value), 1);
  return `<div class="hbars">${rows.map((r) => `
    <div class="hbar-row" data-tip="${esc(`${name(r)}: ${display(r).replace(/<[^>]+>/g, '')}`)}">
      <span class="name">${esc(name(r))}</span>
      <div class="hbar-track"><div class="hbar-fill" style="width:${(value(r) / max) * 100}%"></div></div>
      <span class="val">${display(r)}</span>
    </div>`).join('')}</div>`;
}

Pages.dashboard = {
  render(el) {
    App.setTitle('لوحة التحكم', App.can('orders.create') ? `<a class="btn primary" href="#/new">${icon('plus')}<span>طلب جديد</span></a>` : '');
    const today = fmt.today();
    const RANGES = {
      today: ['اليوم', today, today],
      yesterday: ['أمس', fmt.addDays(today, -1), fmt.addDays(today, -1)],
      week: ['آخر 7 أيام', fmt.addDays(today, -6), today],
      month: ['الشهر ده', `${today.slice(0, 8)}01`, today],
      d30: ['آخر 30 يوم', fmt.addDays(today, -29), today],
    };
    const S = { range: Store.get('dash.range', 'today'), from: today, to: today, branch: '' };
    if (RANGES[S.range]) [, S.from, S.to] = RANGES[S.range];
    const showBranch = App.can('orders.view_all') && App.branches.length > 1;

    el.innerHTML = `
      <div class="toolbar">
        <div class="segmented" id="ranges">${Object.entries(RANGES).map(([k, [l]]) => `<button data-r="${k}">${l}</button>`).join('')}</div>
        <input class="input" type="date" id="from" value="${S.from}" style="min-width:0">
        <input class="input" type="date" id="to" value="${S.to}" style="min-width:0">
        ${showBranch ? `<select class="input" id="branch"><option value="">كل الفروع</option>${App.branches.map((b) => `<option value="${b.id}">${esc(b.name)}</option>`).join('')}</select>` : ''}
      </div>
      <div id="dash"><div class="loading"><div class="spinner"></div></div></div>`;

    const drawRanges = () => $$('#ranges button', el).forEach((b) => b.classList.toggle('active', b.dataset.r === S.range));

    const load = async () => {
      try {
        const d = await API.get(`/dashboard${qs({ from: S.from, to: S.to, branch_id: S.branch })}`);
        draw(d);
      } catch (e) { $('#dash', el).innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
    };

    const draw = (d) => {
      const s = d.summary;
      const activeTotal = d.active.reduce((a, r) => a + r.count, 0);
      const activeMap = Object.fromEntries(d.active.map((r) => [r.status, r.count]));
      const multiDay = d.from !== d.to;
      // تعبئة الأيام الفاضية
      let days = d.byDay;
      if (multiDay) {
        const map = Object.fromEntries(d.byDay.map((r) => [r.day, r]));
        days = [];
        for (let x = d.from; x <= d.to; x = fmt.addDays(x, 1)) days.push(map[x] || { day: x, orders: 0, revenue: 0 });
      }
      const hours = Array.from({ length: 24 }, (_, h) => d.byHour.find((r) => r.hour === h) || { hour: h, orders: 0 });
      const hourLabel = (h) => `${h % 12 || 12}${h < 12 ? 'ص' : 'م'}`;

      $('#dash', el).innerHTML = `
        <div class="kpis">
          <div class="card kpi"><div class="label">المبيعات</div><div class="value">${fmt.money(s.revenue)}</div><div class="sub">بدون الملغي</div></div>
          <div class="card kpi"><div class="label">عدد الطلبات</div><div class="value num">${fmt.num(s.orders)}</div><div class="sub">${s.cancelled ? `${s.cancelled} ملغي` : 'مفيش طلبات ملغية'}</div></div>
          <div class="card kpi"><div class="label">متوسط الطلب</div><div class="value">${fmt.money(s.avg_order)}</div></div>
          <div class="card kpi"><div class="label">متوسط وقت التسليم</div><div class="value">${s.avg_delivery_minutes !== null ? `<span class="num">${s.avg_delivery_minutes}</span> <span style="font-size:16px">دقيقة</span>` : '—'}</div></div>
          <div class="card kpi"><div class="label">عملاء جدد</div><div class="value num">${fmt.num(s.new_customers)}</div></div>
          <div class="card kpi"><div class="label">مصاريف التوصيل</div><div class="value">${fmt.money(s.delivery_fees)}</div><div class="sub">خصومات: ${fmt.moneyText(s.discounts)}</div></div>
        </div>

        <div class="dash-grid">
          <div class="card span-12">
            <div class="card-head"><h3>الطلبات الشغالة دلوقتي <span class="muted num">(${activeTotal})</span></h3><a class="btn sm" href="#/orders?tab=active">عرض الكل</a></div>
            <div class="card-body"><div class="live-status">
              ${['new', 'accepted', 'preparing', 'ready', 'out_for_delivery'].map((st) => `
                <a href="#/orders?tab=active">${statusBadge(st)}<div class="n num">${activeMap[st] || 0}</div></a>`).join('')}
            </div></div>
          </div>

          <div class="card span-8">
            <div class="card-head"><h3>${multiDay ? 'المبيعات اليومية' : 'الطلبات حسب الساعة'}</h3></div>
            <div class="card-body">${multiDay
              ? vBars(days, { label: (r) => r.day.slice(5).split('-').reverse().join('/'), value: (r) => r.revenue, tip: (r) => `${r.day}: ${fmt.moneyText(r.revenue)} - ${r.orders} طلب` })
              : vBars(hours, { label: (r) => hourLabel(r.hour), value: (r) => r.orders, tip: (r) => `${hourLabel(r.hour)}: ${r.orders} طلب` })}</div>
          </div>

          <div class="card span-4">
            <div class="card-head"><h3>نوع الطلب</h3></div>
            <div class="card-body">${hBars(d.byType, { name: (r) => typeLabel(r.type), value: (r) => r.count, display: (r) => `<span class="num">${r.count}</span>` })}
              <div class="section-title" style="margin-top:20px">طرق الدفع</div>
              ${hBars(d.byPayment, { name: (r) => payLabel(r.payment_method), value: (r) => r.revenue, display: (r) => fmt.money(r.revenue) })}</div>
          </div>

          ${showBranch && !S.branch ? `<div class="card span-6">
            <div class="card-head"><h3>المبيعات حسب الفرع</h3></div>
            <div class="card-body">${hBars(d.byBranch, { name: (r) => r.name, value: (r) => r.revenue, display: (r) => `${fmt.money(r.revenue)} <span class="muted small">(${r.orders})</span>` })}</div>
          </div>` : ''}

          <div class="card span-6">
            <div class="card-head"><h3>الأصناف الأكثر مبيعاً</h3></div>
            <div class="card-body">${hBars(d.topItems, { name: (r) => r.name, value: (r) => r.qty, display: (r) => `<span class="num">${r.qty}</span>` })}</div>
          </div>

          <div class="card span-6">
            <div class="card-head"><h3>أفضل العملاء</h3></div>
            ${d.topCustomers.length ? `<div class="table-wrap"><table class="table"><thead><tr><th>العميل</th><th>الطلبات</th><th>الإجمالي</th></tr></thead>
              <tbody>${d.topCustomers.map((c) => `<tr><td><b>${esc(c.name)}</b><div class="small muted num">${esc(c.phone)}</div></td><td class="num">${c.orders}</td><td>${fmt.money(c.revenue)}</td></tr>`).join('')}</tbody></table></div>`
              : '<div class="empty small">لا توجد بيانات</div>'}
          </div>
        </div>`;
    };

    drawRanges();
    load();
    $('#ranges', el).onclick = (e) => {
      const b = e.target.closest('[data-r]'); if (!b) return;
      S.range = b.dataset.r; Store.set('dash.range', S.range);
      [, S.from, S.to] = RANGES[S.range];
      $('#from', el).value = S.from; $('#to', el).value = S.to;
      drawRanges(); load();
    };
    $('#from', el).onchange = (e) => { S.from = e.target.value; S.range = ''; drawRanges(); load(); };
    $('#to', el).onchange = (e) => { S.to = e.target.value; S.range = ''; drawRanges(); load(); };
    if ($('#branch', el)) $('#branch', el).onchange = (e) => { S.branch = e.target.value; load(); };

    const reload = debounce(load, 1500);
    App.on('orders:changed', reload);
    App.on('reconnect', reload);
  },
};
