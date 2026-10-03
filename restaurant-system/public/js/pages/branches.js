'use strict';

Pages.branches = {
  async render(el) {
    App.setTitle('الفروع', `<button class="btn primary" id="add-branch">${icon('plus')}<span>فرع جديد</span></button>`);
    const load = async () => {
      await App.reloadBranches();
      const rows = App.branches;
      el.innerHTML = rows.length ? `<div class="orders-list">${rows.map((b) => `
        <div class="card card-pad stack" style="gap:8px">
          <div class="row between"><h3 style="font-size:17px">${esc(b.name)}</h3><span class="badge ${b.is_active ? 'on' : 'off'}">${b.is_active ? 'شغال' : 'موقوف'}</span></div>
          <div class="info-list">
            ${b.address ? `<div>${icon('pin').replace('<svg', '<svg style="width:14px;height:14px;vertical-align:-2px"')} ${esc(b.address)}</div>` : ''}
            ${b.phone ? `<div>${icon('phone').replace('<svg', '<svg style="width:14px;height:14px;vertical-align:-2px"')} ${telLink(b.phone)}</div>` : ''}
            <div><span class="k">التوصيل</span> ${fmt.money(b.delivery_fee)}</div>
            <div><span class="k">طلبات شغالة</span> <b class="num">${b.active_orders}</b></div>
            <div><span class="k">الموظفين</span> <span class="num">${b.users_count}</span></div>
          </div>
          <div class="row"><button class="btn sm" data-edit="${b.id}">${icon('edit')}تعديل</button>
            <a class="btn sm ghost" href="#/orders?branch=${b.id}">الطلبات</a></div>
        </div>`).join('')}</div>` : `<div class="empty">${icon('store')}<div>ضيف أول فرع</div></div>`;
    };

    const form = (b = {}) => {
      const m = modal({
        title: b.id ? 'تعديل الفرع' : 'فرع جديد',
        body: `<form class="stack" id="br-form">
          <label class="field"><span>اسم الفرع *</span><input class="input" name="name" value="${esc(b.name)}" required></label>
          <label class="field"><span>العنوان</span><input class="input" name="address" value="${esc(b.address)}"></label>
          <div class="grid-2">
            <label class="field"><span>التليفون</span><input class="input" type="tel" name="phone" value="${esc(b.phone)}"></label>
            <label class="field"><span>مصاريف التوصيل</span><input class="input" type="number" min="0" step="0.5" name="delivery_fee" value="${b.delivery_fee ?? 0}"></label>
          </div>
          <label class="check"><input type="checkbox" name="is_active" ${b.is_active === 0 ? '' : 'checked'}> الفرع شغال ويستقبل طلبات</label>
        </form>`,
        footer: `<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>${b.id ? `<button class="btn danger" data-del style="margin-inline-start:auto">${icon('trash')}مسح</button>` : ''}`,
      });
      const ok = m.el.querySelector('[data-ok]');
      ok.onclick = () => busy(ok, async () => {
        const d = formData($('#br-form', m.el));
        if (b.id) await API.put(`/branches/${b.id}`, d); else await API.post('/branches', d);
        m.close(); toast('تم الحفظ', 'success'); load();
      });
      const del = m.el.querySelector('[data-del]');
      if (del) del.onclick = async () => {
        if (!await confirmDialog(`مسح فرع "${esc(b.name)}"؟`, { danger: true, okText: 'مسح' })) return;
        busy(del, async () => { const r = await API.del(`/branches/${b.id}`); m.close(); toast(esc(r.message || 'تم المسح'), 'success'); load(); });
      };
    };

    el.addEventListener('click', (e) => { const b = e.target.closest('[data-edit]'); if (b) form(App.branches.find((x) => x.id === Number(b.dataset.edit))); });
    $('#add-branch').onclick = () => form();
    await load();
  },
};
