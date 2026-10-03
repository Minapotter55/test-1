'use strict';

// تسلسل الحالات حسب نوع الطلب
const Flow = {
  steps(o) { return o.type === 'delivery' ? ['new', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered'] : ['new', 'accepted', 'preparing', 'ready', 'delivered']; },
  next(o) { const s = this.steps(o); const i = s.indexOf(o.status); return i >= 0 && i < s.length - 1 ? s[i + 1] : null; },
  actionLabel: { accepted: 'قبول الطلب', preparing: 'بدء التحضير', ready: 'الطلب جاهز', out_for_delivery: 'خرج للتوصيل', delivered: 'تم التسليم' },
  // هل المستخدم الحالي يقدر يحرك الطلب للحالة دي؟
  canMove(o, status) {
    if (!status || ['delivered', 'cancelled'].includes(o.status)) return false;
    if (App.can('orders.update_status')) return true;
    return App.can('orders.delivery') && o.driver_id === App.user.id && ['out_for_delivery', 'delivered'].includes(status);
  },
};

const trackUrl = (o) => `${API.base || location.origin}/track.html#${o.track_token}`;

// ---------- كارت الطلب ----------
function orderCard(o, { highlight = false } = {}) {
  const next = Flow.next(o);
  const mins = fmt.minutesSince(o.created_at);
  const late = !['delivered', 'cancelled'].includes(o.status) && mins > 45;
  return `
    <div class="order-card ${highlight ? 'is-new' : ''}" data-order="${o.id}">
      <div class="oc-top">
        <span class="oc-no num">#${esc(o.order_no)}</span>
        ${statusBadge(o.status)}
      </div>
      <div style="font-weight:700">${esc(o.customer_name)} <span class="muted small num">${esc(o.customer_phone)}</span></div>
      <div class="oc-meta">
        <span>${icon('store')}${esc(o.branch_name)}</span>
        <span>${icon(o.type === 'delivery' ? 'bike' : 'food')}${esc(typeLabel(o.type))}</span>
        <span>${icon('food')}${o.items_count} صنف</span>
        ${o.driver_name ? `<span>${icon('user')}${esc(o.driver_name)}</span>` : ''}
      </div>
      ${o.type === 'delivery' && o.address_text ? `<div class="small muted" style="line-height:1.4">${icon('pin').replace('<svg', '<svg style="width:13px;height:13px;vertical-align:-2px"')} ${esc(o.address_text)}</div>` : ''}
      <div class="oc-foot">
        <div><div class="oc-total">${fmt.money(o.total)}</div><div class="age ${late ? 'late' : ''}">${icon('clock').replace('<svg', '<svg style="width:12px;height:12px;vertical-align:-1px"')} ${esc(fmt.ago(o.created_at))}</div></div>
        ${Flow.canMove(o, next) ? `<button class="btn sm ${next === 'accepted' ? 'primary' : ''}" data-quick="${o.id}" data-status="${next}">${Flow.actionLabel[next]}</button>` : ''}
      </div>
    </div>`;
}

async function moveStatus(orderId, status) {
  let note = '';
  if (status === 'cancelled') {
    note = await promptDialog('إلغاء الطلب', { label: 'سبب الإلغاء', required: true, okText: 'إلغاء الطلب' });
    if (note === null) return null;
  }
  const o = await API.patch(`/orders/${orderId}/status`, { status, note });
  toast(`الطلب #${esc(o.order_no)}: ${esc(statusLabel(o.status))}`, 'success');
  return o;
}

// ---------- تفاصيل الطلب (مودال) ----------
const OrderView = {
  current: null,

  async open(id) {
    const m = modal({ title: 'تفاصيل الطلب', size: 'lg', body: '<div class="loading"><div class="spinner"></div></div>', onClose: () => { OrderView.current = null; } });
    this.current = { id, m };
    try {
      const o = await API.get(`/orders/${id}`);
      this.fill(m, o);
    } catch (e) { m.setBody(`<div class="empty">${esc(e.message)}</div>`); }
  },

  // تحديث المودال لو الطلب اتغير من جهاز تاني
  async refreshIfOpen(orderId) {
    if (!this.current || this.current.id !== orderId || !this.current.m.el.isConnected) return;
    try { this.fill(this.current.m, await API.get(`/orders/${orderId}`)); } catch { /* ignore */ }
  },

  fill(m, o) {
    m.el.querySelector('.modal-head h3').innerHTML = `طلب <span class="num">#${esc(o.order_no)}</span> ${statusBadge(o.status)}`;
    const next = Flow.next(o);
    const finished = ['delivered', 'cancelled'].includes(o.status);
    const actions = [];
    if (Flow.canMove(o, next)) actions.push(`<button class="btn primary" data-act="status" data-status="${next}">${icon('check')}${Flow.actionLabel[next]}</button>`);
    if (!finished && App.can('orders.update_status')) {
      const others = Flow.steps(o).filter((s) => s !== o.status && s !== next && Flow.steps(o).indexOf(s) > Flow.steps(o).indexOf(o.status));
      if (others.length) actions.push(`<select class="input" style="width:auto" data-act="status-select"><option value="">تغيير الحالة...</option>${others.map((s) => `<option value="${s}">${esc(statusLabel(s))}</option>`).join('')}</select>`);
    }
    if (App.user.is_admin && finished) {
      actions.push(`<select class="input" style="width:auto" data-act="status-select"><option value="">تعديل الحالة (مدير)...</option>${Flow.steps(o).filter((s) => s !== o.status).map((s) => `<option value="${s}">${esc(statusLabel(s))}</option>`).join('')}</select>`);
    }
    if (!finished && App.can('orders.cancel')) actions.push(`<button class="btn danger" data-act="status" data-status="cancelled">${icon('x')}إلغاء الطلب</button>`);
    actions.push(`<button class="btn" data-act="print">${icon('print')}طباعة</button>`);
    actions.push(`<a class="btn" target="_blank" rel="noopener" href="${esc(waLink(o.customer_phone, `أهلاً ${o.customer_name}، طلبك رقم ${o.order_no} من ${App.settings.restaurant_name} - تقدر تتابع حالته من هنا: ${trackUrl(o)}`))}">${icon('whatsapp')}واتساب العميل</a>`);
    actions.push(`<button class="btn ghost" data-act="copy-track">${icon('link')}رابط المتابعة</button>`);

    const canDriver = o.type === 'delivery' && !finished && App.can('orders.assign_driver');
    const canTransfer = !finished && App.can('orders.transfer');

    m.setBody(`
      <div class="stack">
        <div class="row">${actions.join('')}</div>
        <div class="od-grid">
          <div class="card card-pad">
            <div class="section-title">العميل</div>
            <div class="info-list">
              <div><span class="k">الاسم</span> <b>${esc(o.customer_name)}</b></div>
              <div><span class="k">الموبايل</span> ${telLink(o.customer_phone)}</div>
              ${o.type === 'delivery' ? `<div><span class="k">العنوان</span> ${esc(o.address_text)}
                ${o.address_text ? `<a class="small" target="_blank" rel="noopener" href="${mapsLink(o.address_text)}">(الخريطة)</a>` : ''}</div>` : ''}
              ${o.notes ? `<div><span class="k">ملاحظات</span> <b style="color:var(--warn)">${esc(o.notes)}</b></div>` : ''}
            </div>
          </div>
          <div class="card card-pad">
            <div class="section-title">الطلب</div>
            <div class="info-list">
              <div><span class="k">الفرع</span> ${esc(o.branch_name)} ${canTransfer ? '<button class="btn sm ghost" data-act="transfer">تحويل</button>' : ''}</div>
              <div><span class="k">النوع</span> ${esc(typeLabel(o.type))}</div>
              <div><span class="k">الدفع</span> ${esc(payLabel(o.payment_method))}</div>
              <div><span class="k">الوقت</span> ${esc(fmt.dateTime(o.created_at))}</div>
              <div><span class="k">سجله</span> ${esc(o.created_by_name || '-')}</div>
              ${o.type === 'delivery' ? `<div><span class="k">الطيار</span> ${o.driver_name ? `${esc(o.driver_name)} ${telLink(o.driver_phone)}` : '<span class="muted">لم يحدد</span>'}
                ${canDriver ? '<button class="btn sm ghost" data-act="driver">تعيين</button>' : ''}</div>` : ''}
            </div>
          </div>
        </div>
        <div class="card">
          <div class="table-wrap"><table class="table">
            <thead><tr><th>الصنف</th><th>الكمية</th><th>السعر</th><th>الإجمالي</th></tr></thead>
            <tbody>${o.items.map((i) => `<tr><td><b>${esc(i.name)}</b>${i.notes ? `<div class="small" style="color:var(--warn)">${esc(i.notes)}</div>` : ''}</td>
              <td class="num">${i.qty}</td><td>${fmt.money(i.price)}</td><td>${fmt.money(i.line_total)}</td></tr>`).join('')}</tbody>
          </table></div>
          <div class="card-body totals">
            <div><span>المجموع</span><span>${fmt.money(o.subtotal)}</span></div>
            ${o.delivery_fee ? `<div><span>التوصيل</span><span>${fmt.money(o.delivery_fee)}</span></div>` : ''}
            ${o.discount ? `<div><span>الخصم</span><span>- ${fmt.money(o.discount)}</span></div>` : ''}
            <div class="grand"><span>الإجمالي</span><span>${fmt.money(o.total)}</span></div>
          </div>
        </div>
        <div class="card card-pad">
          <div class="section-title">سجل الطلب</div>
          <ul class="timeline">${o.history.map((h) => `<li><b>${esc(statusLabel(h.status))}</b>${h.note ? ` - ${esc(h.note)}` : ''}
            <div class="t">${esc(fmt.dateTime(h.created_at))}${h.user_name ? ` - ${esc(h.user_name)}` : ''}</div></li>`).join('')}</ul>
        </div>
      </div>`);

    const body = m.body;
    body.querySelectorAll('[data-act="status"]').forEach((b) => {
      b.onclick = () => busy(b, async () => { const r = await moveStatus(o.id, b.dataset.status); if (r) this.fill(m, r); });
    });
    body.querySelectorAll('[data-act="status-select"]').forEach((s) => {
      s.onchange = async () => {
        if (!s.value) return;
        try { const r = await moveStatus(o.id, s.value); if (r) this.fill(m, r); else s.value = ''; } catch (e) { toastError(e); s.value = ''; }
      };
    });
    body.querySelector('[data-act="print"]').onclick = () => printReceipt(o);
    body.querySelector('[data-act="copy-track"]').onclick = async () => {
      try { await navigator.clipboard.writeText(trackUrl(o)); toast('تم نسخ رابط المتابعة', 'success'); } catch { promptDialog('رابط متابعة الطلب', { label: trackUrl(o) }); }
    };
    const drv = body.querySelector('[data-act="driver"]');
    if (drv) drv.onclick = () => this.assignDriver(m, o);
    const tr = body.querySelector('[data-act="transfer"]');
    if (tr) tr.onclick = () => this.transfer(m, o);
  },

  async assignDriver(parent, o) {
    let drivers = [];
    try { drivers = await API.get('/users/drivers'); } catch (e) { return toastError(e); }
    const m = modal({
      title: 'تعيين طيار', size: 'sm',
      body: drivers.length ? `<div class="stack">${drivers.map((d) => `<label class="addr-option"><input type="radio" name="driver" value="${d.id}" ${d.id === o.driver_id ? 'checked' : ''}>
        <div><b>${esc(d.name)}</b><div class="small muted">${esc(d.branch_name || 'كل الفروع')} ${d.phone ? `- <span class="num">${esc(d.phone)}</span>` : ''}</div></div></label>`).join('')}
        <label class="addr-option"><input type="radio" name="driver" value="" ${!o.driver_id ? 'checked' : ''}><div>بدون طيار</div></label></div>`
        : '<div class="empty">مفيش طيارين. ضيف مستخدم بدور "طيار توصيل" من صفحة المستخدمين.</div>',
      footer: drivers.length ? '<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>' : '',
    });
    const ok = m.el.querySelector('[data-ok]');
    if (ok) ok.onclick = () => busy(ok, async () => {
      const v = m.el.querySelector('[name=driver]:checked')?.value || null;
      const r = await API.patch(`/orders/${o.id}/driver`, { driver_id: v ? Number(v) : null });
      m.close(); this.fill(parent, r); toast('تم تعيين الطيار', 'success');
    });
  },

  async transfer(parent, o) {
    const options = App.branches.filter((b) => b.id !== o.branch_id && b.is_active);
    if (!options.length) return toast('مفيش فروع تانية متاحة', 'error');
    const m = modal({
      title: 'تحويل الطلب لفرع تاني', size: 'sm',
      body: `<div class="stack"><label class="field"><span>الفرع</span><select class="input" name="branch">${options.map((b) => `<option value="${b.id}">${esc(b.name)}</option>`).join('')}</select></label>
        <label class="field"><span>السبب (اختياري)</span><input class="input" name="note"></label></div>`,
      footer: '<button class="btn primary" data-ok>تحويل</button><button class="btn" data-close>رجوع</button>',
    });
    const ok = m.el.querySelector('[data-ok]');
    ok.onclick = () => busy(ok, async () => {
      const r = await API.patch(`/orders/${o.id}/branch`, { branch_id: Number(m.el.querySelector('[name=branch]').value), note: m.el.querySelector('[name=note]').value });
      m.close(); this.fill(parent, r); toast('تم تحويل الطلب', 'success');
    });
  },
};

// ---------- طباعة الفاتورة ----------
function printReceipt(o) {
  const s = App.settings;
  $('#print-area').innerHTML = `
    <div class="receipt">
      <h2>${esc(s.restaurant_name)}</h2>
      <div class="c">${esc(o.branch_name)}${o.branch_phone ? ` - ${esc(o.branch_phone)}` : ''}</div>
      <hr>
      <div class="c big">طلب #${esc(o.order_no)}</div>
      <div class="c">${esc(typeLabel(o.type))} - ${esc(fmt.dateTime(o.created_at))}</div>
      <hr>
      <div>العميل: <b>${esc(o.customer_name)}</b></div>
      <div>الموبايل: ${esc(o.customer_phone)}</div>
      ${o.type === 'delivery' ? `<div>العنوان: ${esc(o.address_text)}</div>` : ''}
      ${o.driver_name ? `<div>الطيار: ${esc(o.driver_name)}</div>` : ''}
      <hr>
      <table>${o.items.map((i) => `<tr><td>${i.qty} × ${esc(i.name)}${i.notes ? `<br><small>(${esc(i.notes)})</small>` : ''}</td><td style="text-align:left">${fmt.num(i.line_total)}</td></tr>`).join('')}</table>
      <hr>
      <table>
        <tr><td>المجموع</td><td style="text-align:left">${fmt.num(o.subtotal)}</td></tr>
        ${o.delivery_fee ? `<tr><td>التوصيل</td><td style="text-align:left">${fmt.num(o.delivery_fee)}</td></tr>` : ''}
        ${o.discount ? `<tr><td>الخصم</td><td style="text-align:left">-${fmt.num(o.discount)}</td></tr>` : ''}
        <tr class="big"><td>الإجمالي</td><td style="text-align:left">${fmt.num(o.total)} ${esc(s.currency)}</td></tr>
      </table>
      <div>الدفع: ${esc(payLabel(o.payment_method))}</div>
      ${o.notes ? `<hr><div><b>ملاحظات:</b> ${esc(o.notes)}</div>` : ''}
      <hr>
      <div class="c">${esc(s.receipt_footer || '')}</div>
    </div>`;
  setTimeout(() => window.print(), 50);
}

// ---------- صفحة الطلبات ----------
Pages.orders = {
  render(el, params, query) {
    const isDriverOnly = App.can('orders.delivery') && !App.canAny('orders.view_all', 'orders.view_branch', 'orders.create');
    const TABS = [
      { key: 'active', label: 'الشغالة', q: { active: 1 } },
      { key: 'new', label: 'جديد', q: { status: 'new' } },
      { key: 'kitchen', label: 'في المطبخ', q: { status: 'accepted,preparing' } },
      { key: 'ready', label: 'جاهز', q: { status: 'ready' } },
      { key: 'out', label: 'مع الطيار', q: { status: 'out_for_delivery' } },
      { key: 'done', label: 'المنتهية', q: { status: 'delivered,cancelled' }, dated: true },
      { key: 'all', label: 'الكل', q: {}, dated: true },
    ];
    const state = {
      tab: query.tab || Store.get('orders.tab', 'active'),
      view: Store.get('orders.view', window.innerWidth > 900 && !isDriverOnly ? 'board' : 'list'),
      branch: query.branch || '',
      q: '',
      date: fmt.today(),
      rows: [],
      fresh: new Set(),
    };
    if (!TABS.find((t) => t.key === state.tab)) state.tab = 'active';

    App.setTitle(isDriverOnly ? 'طلباتي' : 'الطلبات', App.can('orders.create') ? `<a class="btn primary" href="#/new">${icon('plus')}<span>طلب جديد</span></a>` : '');

    const showBranch = App.can('orders.view_all') && App.branches.length > 1;
    el.innerHTML = `
      <div class="tabs" id="tabs"></div>
      <div class="toolbar">
        <input class="input search" id="q" type="search" placeholder="بحث برقم الطلب أو الموبايل أو الاسم">
        ${showBranch ? `<select class="input" id="branch"><option value="">كل الفروع</option>${App.branches.map((b) => `<option value="${b.id}" ${String(b.id) === state.branch ? 'selected' : ''}>${esc(b.name)}</option>`).join('')}</select>` : ''}
        <input class="input" id="date" type="date" value="${state.date}">
        <div class="segmented" id="view">
          <button data-v="board" title="لوحة">${icon('board').replace('<svg', '<svg style="width:16px;height:16px;vertical-align:-3px"')}</button>
          <button data-v="list" title="قائمة">${icon('list').replace('<svg', '<svg style="width:16px;height:16px;vertical-align:-3px"')}</button>
        </div>
        <button class="btn icon" id="reload" title="تحديث">${icon('refresh')}</button>
      </div>
      <div id="orders-wrap"></div>`;

    const tab = () => TABS.find((t) => t.key === state.tab);
    const renderTabs = () => {
      $('#tabs', el).innerHTML = TABS.map((t) => `<button data-tab="${t.key}" class="${t.key === state.tab ? 'active' : ''}">${t.label}</button>`).join('');
      $('#date', el).classList.toggle('hidden', !tab().dated);
      $$('#view button', el).forEach((b) => b.classList.toggle('active', b.dataset.v === state.view));
    };

    const load = async () => {
      const t = tab();
      const params2 = { ...t.q, q: state.q, branch_id: state.branch, limit: 300 };
      if (t.dated && state.date) { params2.from = state.date; params2.to = state.date; }
      try {
        const r = await API.get(`/orders${qs(params2)}`);
        state.rows = r.rows;
        draw();
      } catch (e) { $('#orders-wrap', el).innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
    };

    const draw = () => {
      const wrap = $('#orders-wrap', el);
      if (!wrap) return;
      const rows = state.rows;
      const card = (o) => orderCard(o, { highlight: state.fresh.has(o.id) });
      if (state.view === 'board' && ['active', 'all'].includes(state.tab)) {
        const cols = ['new', 'accepted', 'preparing', 'ready', 'out_for_delivery'];
        if (state.tab === 'all') cols.push('delivered', 'cancelled');
        wrap.innerHTML = `<div class="board">${cols.map((s) => {
          const list = rows.filter((o) => o.status === s);
          return `<div class="board-col"><div class="board-col-head">${statusBadge(s)}<span class="num muted">${list.length}</span></div>
            <div class="board-col-body">${list.map(card).join('') || '<div class="muted small" style="text-align:center;padding:10px">لا يوجد</div>'}</div></div>`;
        }).join('')}</div>`;
      } else {
        wrap.innerHTML = rows.length ? `<div class="orders-list">${rows.map(card).join('')}</div>`
          : `<div class="empty">${icon('orders')}<div>مفيش طلبات هنا</div></div>`;
      }
    };

    renderTabs();
    load();

    el.addEventListener('click', async (e) => {
      const tabBtn = e.target.closest('[data-tab]');
      if (tabBtn) { state.tab = tabBtn.dataset.tab; Store.set('orders.tab', state.tab); renderTabs(); load(); return; }
      const viewBtn = e.target.closest('#view [data-v]');
      if (viewBtn) { state.view = viewBtn.dataset.v; Store.set('orders.view', state.view); renderTabs(); draw(); return; }
      const quick = e.target.closest('[data-quick]');
      if (quick) {
        e.stopPropagation();
        await busy(quick, async () => { await moveStatus(Number(quick.dataset.quick), quick.dataset.status); });
        return;
      }
      const cardEl = e.target.closest('[data-order]');
      if (cardEl) { const id = Number(cardEl.dataset.order); state.fresh.delete(id); OrderView.open(id); }
    });
    $('#reload', el).onclick = load;
    $('#q', el).oninput = debounce((e) => { state.q = e.target.value.trim(); load(); }, 350);
    if ($('#branch', el)) $('#branch', el).onchange = (e) => { state.branch = e.target.value; load(); };
    $('#date', el).onchange = (e) => { state.date = e.target.value; load(); };

    // تحديث لحظي
    const reload = debounce(load, 250);
    App.on('order:new', (o) => { state.fresh.add(o.id); reload(); });
    App.on('order:updated', reload);
    App.on('reconnect', reload);
    // تحديث "من كام دقيقة" كل دقيقة
    const timer = setInterval(draw, 60000);
    return () => clearInterval(timer);
  },
};
