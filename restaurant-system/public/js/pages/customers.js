'use strict';

const CustomerView = {
  async open(id, onChange) {
    const m = modal({ title: 'بيانات العميل', size: 'lg', body: '<div class="loading"><div class="spinner"></div></div>' });
    const load = async () => {
      try { this.fill(m, await API.get(`/customers/${id}`), load, onChange); } catch (e) { m.setBody(`<div class="empty">${esc(e.message)}</div>`); }
    };
    load();
  },

  fill(m, c, reload, onChange) {
    const canEdit = App.can('customers.manage');
    m.el.querySelector('.modal-head h3').textContent = c.name;
    m.setBody(`
      <div class="stack">
        <div class="row">
          ${App.can('orders.create') ? `<a class="btn primary" href="#/new?phone=${encodeURIComponent(c.phone)}" data-close>${icon('plus')}طلب جديد للعميل</a>` : ''}
          <a class="btn" href="tel:${esc(c.phone)}">${icon('phone')}اتصال</a>
          <a class="btn" target="_blank" rel="noopener" href="${esc(waLink(c.phone, `أهلاً ${c.name}`))}">${icon('whatsapp')}واتساب</a>
        </div>
        <div class="kpis" style="margin:0">
          <div class="card kpi"><div class="label">عدد الطلبات</div><div class="value num">${c.stats.orders_count}</div></div>
          <div class="card kpi"><div class="label">إجمالي المشتريات</div><div class="value">${fmt.money(c.stats.total_spent)}</div></div>
          <div class="card kpi"><div class="label">آخر طلب</div><div class="value" style="font-size:16px">${c.stats.last_order ? esc(fmt.date(c.stats.last_order)) : '—'}</div></div>
        </div>
        <form class="card card-pad stack" id="cust-form">
          <div class="section-title">البيانات</div>
          <div class="grid-2">
            <label class="field"><span>الاسم</span><input class="input" name="name" value="${esc(c.name)}" ${canEdit ? '' : 'disabled'}></label>
            <label class="field"><span>الموبايل</span><input class="input" type="tel" name="phone" value="${esc(c.phone)}" ${canEdit ? '' : 'disabled'}></label>
            <label class="field"><span>رقم تاني</span><input class="input" type="tel" name="phone2" value="${esc(c.phone2)}" ${canEdit ? '' : 'disabled'}></label>
            <label class="field"><span>ملاحظات</span><input class="input" name="notes" value="${esc(c.notes)}" ${canEdit ? '' : 'disabled'}></label>
          </div>
          ${canEdit ? '<div><button class="btn primary" type="submit">حفظ البيانات</button></div>' : ''}
        </form>
        <div class="card">
          <div class="card-head"><h3>العناوين</h3>${canEdit ? `<button class="btn sm" data-add-addr>${icon('plus')}إضافة عنوان</button>` : ''}</div>
          ${c.addresses.length ? c.addresses.map((a) => `
            <div class="menu-item-row">
              <div class="grow">${a.label ? `<b>${esc(a.label)}</b> - ` : ''}${esc([a.area, a.address].filter(Boolean).join(' - '))}
                ${a.landmark ? `<div class="small muted">${esc(a.landmark)}</div>` : ''}</div>
              ${canEdit ? `<button class="btn icon ghost" data-edit-addr="${a.id}">${icon('edit')}</button><button class="btn icon ghost danger" data-del-addr="${a.id}">${icon('trash')}</button>` : ''}
            </div>`).join('') : '<div class="empty small">مفيش عناوين</div>'}
        </div>
        <div class="card">
          <div class="card-head"><h3>الطلبات السابقة</h3></div>
          ${c.orders.length ? `<div class="table-wrap"><table class="table"><thead><tr><th>رقم</th><th>التاريخ</th><th>الفرع</th><th>الحالة</th><th>الإجمالي</th></tr></thead>
            <tbody>${c.orders.map((o) => `<tr class="clickable" data-order="${o.id}"><td class="num">#${esc(o.order_no)}</td><td>${esc(fmt.dateTime(o.created_at))}</td>
              <td>${esc(o.branch_name)}</td><td>${statusBadge(o.status)}</td><td>${fmt.money(o.total)}</td></tr>`).join('')}</tbody></table></div>`
            : '<div class="empty small">مفيش طلبات</div>'}
        </div>
        ${canEdit ? `<div><button class="btn danger sm" data-del-cust>${icon('trash')}مسح العميل</button></div>` : ''}
      </div>`);

    const body = m.body;
    const form = $('#cust-form', body);
    form.onsubmit = (e) => {
      e.preventDefault();
      busy(form.querySelector('[type=submit]'), async () => {
        await API.put(`/customers/${c.id}`, formData(form));
        toast('تم الحفظ', 'success'); reload(); if (onChange) onChange();
      });
    };
    body.querySelectorAll('[data-order]').forEach((tr) => { tr.onclick = () => OrderView.open(Number(tr.dataset.order)); });
    const addBtn = body.querySelector('[data-add-addr]');
    if (addBtn) addBtn.onclick = () => this.addressForm(c.id, null, reload);
    body.querySelectorAll('[data-edit-addr]').forEach((b) => { b.onclick = () => this.addressForm(c.id, c.addresses.find((a) => a.id === Number(b.dataset.editAddr)), reload); });
    body.querySelectorAll('[data-del-addr]').forEach((b) => {
      b.onclick = async () => {
        if (!await confirmDialog('مسح العنوان ده؟', { danger: true, okText: 'مسح' })) return;
        busy(b, async () => { await API.del(`/customers/addresses/${b.dataset.delAddr}`); reload(); });
      };
    });
    const delC = body.querySelector('[data-del-cust]');
    if (delC) delC.onclick = async () => {
      if (!await confirmDialog('مسح العميل نهائياً؟ (طلباته القديمة هتفضل موجودة)', { danger: true, okText: 'مسح' })) return;
      busy(delC, async () => { await API.del(`/customers/${c.id}`); m.close(); toast('تم مسح العميل', 'success'); if (onChange) onChange(); });
    };
  },

  addressForm(customerId, a, done) {
    a = a || {};
    const m = modal({
      title: a.id ? 'تعديل العنوان' : 'عنوان جديد', size: 'sm',
      body: `<form class="stack" id="addr-form">
        <label class="field"><span>اسم العنوان (البيت، الشغل...)</span><input class="input" name="label" value="${esc(a.label)}"></label>
        <label class="field"><span>المنطقة</span><input class="input" name="area" value="${esc(a.area)}"></label>
        <label class="field"><span>العنوان بالتفصيل *</span><input class="input" name="address" value="${esc(a.address)}" required></label>
        <label class="field"><span>علامة مميزة</span><input class="input" name="landmark" value="${esc(a.landmark)}"></label>
      </form>`,
      footer: '<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>',
    });
    const ok = m.el.querySelector('[data-ok]');
    ok.onclick = () => busy(ok, async () => {
      const d = formData($('#addr-form', m.el));
      if (a.id) await API.put(`/customers/addresses/${a.id}`, d); else await API.post(`/customers/${customerId}/addresses`, d);
      m.close(); done();
    });
  },
};

Pages.customers = {
  render(el) {
    App.setTitle('العملاء', App.can('customers.manage') ? `<button class="btn primary" id="add-cust">${icon('plus')}<span>عميل جديد</span></button>` : '');
    el.innerHTML = `
      <div class="toolbar"><input class="input search" type="search" id="q" placeholder="بحث بالاسم أو رقم الموبايل"><span class="muted small" id="count"></span></div>
      <div class="card"><div id="list"><div class="loading"><div class="spinner"></div></div></div></div>`;
    let q = '';
    const load = async () => {
      try {
        const r = await API.get(`/customers${qs({ q, limit: 200 })}`);
        $('#count', el).textContent = `${r.total} عميل`;
        $('#list', el).innerHTML = r.rows.length ? `<div class="table-wrap"><table class="table">
          <thead><tr><th>العميل</th><th>الموبايل</th><th>الطلبات</th><th>الإجمالي</th><th>آخر طلب</th></tr></thead>
          <tbody>${r.rows.map((c) => `<tr class="clickable" data-id="${c.id}"><td><b>${esc(c.name)}</b>${c.notes ? `<div class="small muted">${esc(c.notes)}</div>` : ''}</td>
            <td class="num">${esc(c.phone)}</td><td class="num">${c.orders_count}</td><td>${fmt.money(c.total_spent)}</td>
            <td class="small">${c.last_order ? esc(fmt.ago(c.last_order)) : '—'}</td></tr>`).join('')}</tbody></table></div>`
          : `<div class="empty">${icon('users')}<div>مفيش عملاء</div></div>`;
      } catch (e) { toastError(e); }
    };
    load();
    $('#q', el).oninput = debounce((e) => { q = e.target.value.trim(); load(); }, 350);
    $('#list', el).onclick = (e) => { const tr = e.target.closest('[data-id]'); if (tr) CustomerView.open(Number(tr.dataset.id), load); };
    const add = $('#add-cust');
    if (add) add.onclick = () => {
      const m = modal({
        title: 'عميل جديد',
        body: `<form class="stack" id="new-cust">
          <div class="grid-2">
            <label class="field"><span>الاسم *</span><input class="input" name="name" required></label>
            <label class="field"><span>الموبايل *</span><input class="input" type="tel" name="phone" required></label>
            <label class="field"><span>رقم تاني</span><input class="input" type="tel" name="phone2"></label>
            <label class="field"><span>ملاحظات</span><input class="input" name="notes"></label>
          </div>
          <div class="section-title" style="margin:8px 0 0">العنوان (اختياري)</div>
          <div class="grid-2">
            <label class="field"><span>المنطقة</span><input class="input" name="area"></label>
            <label class="field"><span>علامة مميزة</span><input class="input" name="landmark"></label>
          </div>
          <label class="field"><span>العنوان بالتفصيل</span><input class="input" name="address"></label>
        </form>`,
        footer: '<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>',
      });
      const ok = m.el.querySelector('[data-ok]');
      ok.onclick = () => busy(ok, async () => {
        const d = formData($('#new-cust', m.el));
        await API.post('/customers', { name: d.name, phone: d.phone, phone2: d.phone2, notes: d.notes, address: d.address ? { area: d.area, address: d.address, landmark: d.landmark } : null });
        m.close(); toast('تم إضافة العميل', 'success'); load();
      });
    };
  },
};
