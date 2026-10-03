'use strict';

Pages.users = {
  async render(el) {
    App.setTitle('المستخدمين', `<button class="btn primary" id="add-user">${icon('plus')}<span>مستخدم جديد</span></button>`);
    let users = [];
    let roles = [];
    const load = async () => {
      const [u, r] = await Promise.all([API.get('/users'), API.get('/roles')]);
      users = u; roles = r.roles;
      el.innerHTML = `<div class="card"><div class="table-wrap"><table class="table">
        <thead><tr><th>الاسم</th><th>اسم الدخول</th><th>الدور</th><th>الفرع</th><th>الحالة</th><th>آخر دخول</th></tr></thead>
        <tbody>${users.map((x) => `<tr class="clickable" data-id="${x.id}">
          <td><b>${esc(x.name)}</b>${x.phone ? `<div class="small muted num">${esc(x.phone)}</div>` : ''}</td>
          <td class="num">${esc(x.username)}</td><td>${esc(x.role_name)}</td><td>${esc(x.branch_name || 'كل الفروع')}</td>
          <td><span class="badge ${x.is_active ? 'on' : 'off'}">${x.is_active ? 'نشط' : 'موقوف'}</span></td>
          <td class="small">${x.last_login ? esc(fmt.ago(x.last_login)) : '—'}</td></tr>`).join('')}</tbody></table></div></div>`;
    };

    const form = (u = {}) => {
      const m = modal({
        title: u.id ? 'تعديل المستخدم' : 'مستخدم جديد',
        body: `<form class="stack" id="u-form" autocomplete="off">
          <div class="grid-2">
            <label class="field"><span>الاسم *</span><input class="input" name="name" value="${esc(u.name)}" required></label>
            <label class="field"><span>الموبايل</span><input class="input" type="tel" name="phone" value="${esc(u.phone)}"></label>
            <label class="field"><span>اسم الدخول (إنجليزي) *</span><input class="input ltr" name="username" value="${esc(u.username)}" required autocapitalize="off"></label>
            <label class="field"><span>${u.id ? 'كلمة مرور جديدة (سيبها فاضية لو مش هتغيرها)' : 'كلمة المرور *'}</span><input class="input ltr" name="password" type="password" autocomplete="new-password"></label>
            <label class="field"><span>الدور *</span><select class="input" name="role_id">${roles.map((r) => `<option value="${r.id}" ${u.role_id === r.id ? 'selected' : ''}>${esc(r.name)}</option>`).join('')}</select></label>
            <label class="field"><span>الفرع</span><select class="input" name="branch_id"><option value="">كل الفروع / غير تابع لفرع</option>${App.branches.map((b) => `<option value="${b.id}" ${u.branch_id === b.id ? 'selected' : ''}>${esc(b.name)}</option>`).join('')}</select></label>
          </div>
          <div class="small muted">موظف الفرع ومدير الفرع لازم يكون ليهم فرع عشان يشوفوا طلباته.</div>
          <label class="check"><input type="checkbox" name="is_active" ${u.is_active === 0 ? '' : 'checked'}> الحساب نشط</label>
        </form>`,
        footer: `<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>${u.id && u.id !== App.user.id ? `<button class="btn danger" data-del style="margin-inline-start:auto">${icon('trash')}مسح</button>` : ''}`,
      });
      const ok = m.el.querySelector('[data-ok]');
      ok.onclick = () => busy(ok, async () => {
        const d = formData($('#u-form', m.el));
        if (u.id) await API.put(`/users/${u.id}`, d); else await API.post('/users', d);
        m.close(); toast('تم الحفظ', 'success'); load();
      });
      const del = m.el.querySelector('[data-del]');
      if (del) del.onclick = async () => {
        if (!await confirmDialog(`مسح "${esc(u.name)}"؟`, { danger: true, okText: 'مسح' })) return;
        busy(del, async () => { const r = await API.del(`/users/${u.id}`); m.close(); toast(esc(r.message || 'تم المسح'), 'success'); load(); });
      };
    };

    el.addEventListener('click', (e) => { const tr = e.target.closest('[data-id]'); if (tr) form(users.find((x) => x.id === Number(tr.dataset.id))); });
    $('#add-user').onclick = () => form();
    await load();
  },
};

Pages.roles = {
  async render(el) {
    App.setTitle('الأدوار والصلاحيات', `<button class="btn primary" id="add-role">${icon('plus')}<span>دور جديد</span></button>`);
    let data = { roles: [], permissions: {} };
    const load = async () => {
      data = await API.get('/roles');
      el.innerHTML = `
        <p class="muted" style="margin-top:0">كل مستخدم ليه دور، والدور بيحدد هو يقدر يعمل إيه. تقدر تعدل صلاحيات أي دور أو تعمل أدوار جديدة.</p>
        <div class="orders-list">${data.roles.map((r) => `
          <div class="card card-pad stack" style="gap:8px">
            <div class="row between"><h3 style="font-size:17px">${esc(r.name)}</h3><span class="muted small">${r.users_count} مستخدم</span></div>
            <div class="row" style="gap:6px">${(r.key === 'admin' ? ['كل الصلاحيات'] : r.permissions.map((p) => data.permissions[p] || p)).map((p) => `<span class="badge plain">${esc(p)}</span>`).join('') || '<span class="muted small">مفيش صلاحيات</span>'}</div>
            <div><button class="btn sm" data-edit="${r.id}">${icon('edit')}تعديل</button></div>
          </div>`).join('')}</div>`;
    };

    const form = (r = { permissions: [] }) => {
      const isAdmin = r.key === 'admin';
      const m = modal({
        title: r.id ? `تعديل دور: ${esc(r.name)}` : 'دور جديد',
        body: `<form class="stack" id="r-form">
          <label class="field"><span>اسم الدور *</span><input class="input" name="name" value="${esc(r.name)}" required></label>
          ${isAdmin ? '<div class="customer-found">المدير العام معاه كل الصلاحيات دايماً</div>' : ''}
          <div class="stack" style="gap:8px">${Object.entries(data.permissions).map(([k, label]) => `
            <label class="check"><input type="checkbox" data-perm="${k}" ${isAdmin || r.permissions.includes(k) ? 'checked' : ''} ${isAdmin ? 'disabled' : ''}> ${esc(label)}</label>`).join('')}</div>
        </form>`,
        footer: `<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>${r.id && !r.is_system ? `<button class="btn danger" data-del style="margin-inline-start:auto">${icon('trash')}مسح</button>` : ''}`,
      });
      const ok = m.el.querySelector('[data-ok]');
      ok.onclick = () => busy(ok, async () => {
        const body = { name: m.el.querySelector('[name=name]').value, permissions: $$('[data-perm]', m.el).filter((c) => c.checked).map((c) => c.dataset.perm) };
        if (r.id) await API.put(`/roles/${r.id}`, body); else await API.post('/roles', body);
        m.close(); toast('تم الحفظ - المستخدمين هيحتاجوا يعملوا تحديث للصفحة', 'success'); load();
      });
      const del = m.el.querySelector('[data-del]');
      if (del) del.onclick = async () => {
        if (!await confirmDialog(`مسح دور "${esc(r.name)}"؟`, { danger: true, okText: 'مسح' })) return;
        busy(del, async () => { await API.del(`/roles/${r.id}`); m.close(); toast('تم المسح', 'success'); load(); });
      };
    };

    el.addEventListener('click', (e) => { const b = e.target.closest('[data-edit]'); if (b) form(data.roles.find((x) => x.id === Number(b.dataset.edit))); });
    $('#add-role').onclick = () => form();
    await load();
  },
};
