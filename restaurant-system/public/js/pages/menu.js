'use strict';

// تصغير الصورة قبل الرفع
function resizeImage(file, max = 800) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('مقدرناش نقرا الصورة'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('الملف ده مش صورة'));
      img.onload = () => {
        const scale = Math.min(1, max / Math.max(img.width, img.height));
        const c = document.createElement('canvas');
        c.width = Math.round(img.width * scale); c.height = Math.round(img.height * scale);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        resolve(c.toDataURL('image/jpeg', 0.82));
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}
const imgSrc = (url) => (url && url.startsWith('/') ? API.base + url : url);

Pages.menu = {
  async render(el) {
    App.setTitle('المنيو والأسعار', `<button class="btn" id="add-cat">${icon('plus')}<span>قسم</span></button><button class="btn primary" id="add-item">${icon('plus')}<span>صنف</span></button>`);
    let menu = await App.getMenu(true);
    let q = '';

    const draw = () => {
      const ql = q.toLowerCase();
      el.innerHTML = `
        <div class="toolbar"><input class="input search" type="search" id="q" placeholder="بحث عن صنف" value="${esc(q)}">
          <span class="muted small">${menu.items.length} صنف في ${menu.categories.length} قسم</span></div>
        <div class="stack" style="gap:16px">
        ${menu.categories.map((c) => {
          const items = menu.items.filter((i) => i.category_id === c.id && (!ql || i.name.toLowerCase().includes(ql)));
          if (ql && !items.length) return '';
          return `<div class="card">
            <div class="card-head">
              <h3>${esc(c.name)} <span class="muted small">(${items.length})</span> ${c.is_active ? '' : '<span class="badge off">مخفي</span>'}</h3>
              <div class="row" style="gap:4px">
                <button class="btn sm" data-add-in="${c.id}">${icon('plus')}صنف</button>
                <button class="btn icon ghost" data-edit-cat="${c.id}" title="تعديل القسم">${icon('edit')}</button>
                <button class="btn icon ghost danger" data-del-cat="${c.id}" title="مسح القسم">${icon('trash')}</button>
              </div>
            </div>
            ${items.length ? items.map((i) => `
              <div class="menu-item-row">
                <div class="thumb" style="${i.image_url ? `background-image:url('${esc(imgSrc(i.image_url))}')` : ''}"></div>
                <div class="grow"><div style="font-weight:700">${esc(i.name)}</div>${i.description ? `<div class="small muted">${esc(i.description)}</div>` : ''}</div>
                <div style="font-weight:800" class="nowrap">${fmt.money(i.price)}</div>
                <label class="switch" title="متاح"><input type="checkbox" data-avail="${i.id}" ${i.is_available ? 'checked' : ''}><span></span></label>
                <button class="btn icon ghost" data-edit-item="${i.id}">${icon('edit')}</button>
              </div>`).join('') : '<div class="empty small">مفيش أصناف في القسم ده</div>'}
          </div>`;
        }).join('') || `<div class="empty">${icon('menu')}<div>ابدأ بإضافة قسم (مثلاً: ساندوتشات، مشروبات)</div></div>`}
        </div>`;
      const qi = $('#q', el);
      qi.oninput = debounce((e) => { q = e.target.value.trim(); draw(); const n = $('#q', el); n.focus(); n.setSelectionRange(n.value.length, n.value.length); }, 300);
    };

    const reload = async () => { menu = await App.getMenu(true); draw(); };

    const catForm = (c = {}) => {
      const m = modal({
        title: c.id ? 'تعديل القسم' : 'قسم جديد', size: 'sm',
        body: `<form class="stack" id="cat-form">
          <label class="field"><span>اسم القسم *</span><input class="input" name="name" value="${esc(c.name)}" required></label>
          <label class="field"><span>الترتيب</span><input class="input" type="number" name="sort_order" value="${c.sort_order ?? menu.categories.length}" min="0"></label>
          <label class="check"><input type="checkbox" name="is_active" ${c.is_active === 0 ? '' : 'checked'}> ظاهر في المنيو</label>
        </form>`,
        footer: '<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>',
      });
      const ok = m.el.querySelector('[data-ok]');
      ok.onclick = () => busy(ok, async () => {
        const d = formData($('#cat-form', m.el));
        if (c.id) await API.put(`/menu/categories/${c.id}`, d); else await API.post('/menu/categories', d);
        m.close(); toast('تم الحفظ', 'success'); reload();
      });
    };

    const itemForm = (i = {}, catId = null) => {
      if (!menu.categories.length) { toast('ضيف قسم الأول', 'error'); return; }
      let imageData = null;
      let imageUrl = i.image_url || '';
      const m = modal({
        title: i.id ? 'تعديل الصنف' : 'صنف جديد',
        body: `<form class="stack" id="item-form">
          <div class="grid-2">
            <label class="field"><span>اسم الصنف *</span><input class="input" name="name" value="${esc(i.name)}" required></label>
            <label class="field"><span>السعر *</span><input class="input" type="number" step="0.5" min="0" name="price" value="${i.price ?? ''}" required inputmode="decimal"></label>
            <label class="field"><span>القسم</span><select class="input" name="category_id">${menu.categories.map((c) => `<option value="${c.id}" ${(i.category_id || catId) === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></label>
            <label class="field"><span>الترتيب</span><input class="input" type="number" name="sort_order" value="${i.sort_order ?? 0}" min="0"></label>
          </div>
          <label class="field"><span>الوصف / المكونات</span><input class="input" name="description" value="${esc(i.description)}"></label>
          <div class="field"><span>الصورة</span>
            <div class="img-preview" id="preview" style="${imageUrl ? `background-image:url('${esc(imgSrc(imageUrl))}')` : ''}">${imageUrl ? '' : 'مفيش صورة'}</div>
            <div class="row" style="margin-top:6px"><label class="btn sm">${icon('image')}اختيار صورة<input type="file" accept="image/*" id="img-file" hidden></label>
              <button type="button" class="btn sm ghost" id="img-clear">إزالة الصورة</button></div>
          </div>
          <label class="check"><input type="checkbox" name="is_available" ${i.is_available === 0 ? '' : 'checked'}> متاح للطلب</label>
        </form>`,
        footer: `<button class="btn primary" data-ok>حفظ</button><button class="btn" data-close>رجوع</button>${i.id ? `<button class="btn danger" data-del style="margin-inline-start:auto">${icon('trash')}مسح</button>` : ''}`,
      });
      const preview = $('#preview', m.el);
      $('#img-file', m.el).onchange = async (e) => {
        const f = e.target.files[0]; if (!f) return;
        try { imageData = await resizeImage(f); preview.style.backgroundImage = `url('${imageData}')`; preview.textContent = ''; } catch (err) { toastError(err); }
      };
      $('#img-clear', m.el).onclick = () => { imageData = null; imageUrl = ''; preview.style.backgroundImage = ''; preview.textContent = 'مفيش صورة'; };
      const ok = m.el.querySelector('[data-ok]');
      ok.onclick = () => busy(ok, async () => {
        const d = { ...formData($('#item-form', m.el)), image_url: imageUrl };
        if (imageData) d.image_data = imageData;
        if (i.id) await API.put(`/menu/items/${i.id}`, d); else await API.post('/menu/items', d);
        m.close(); toast('تم الحفظ', 'success'); reload();
      });
      const del = m.el.querySelector('[data-del]');
      if (del) del.onclick = async () => {
        if (!await confirmDialog(`مسح "${esc(i.name)}" نهائياً؟`, { danger: true, okText: 'مسح' })) return;
        busy(del, async () => { await API.del(`/menu/items/${i.id}`); m.close(); toast('تم المسح', 'success'); reload(); });
      };
    };

    el.addEventListener('click', async (e) => {
      const t = (s) => e.target.closest(s);
      if (t('[data-add-in]')) itemForm({}, Number(t('[data-add-in]').dataset.addIn));
      else if (t('[data-edit-item]')) itemForm(menu.items.find((i) => i.id === Number(t('[data-edit-item]').dataset.editItem)));
      else if (t('[data-edit-cat]')) catForm(menu.categories.find((c) => c.id === Number(t('[data-edit-cat]').dataset.editCat)));
      else if (t('[data-del-cat]')) {
        const id = Number(t('[data-del-cat]').dataset.delCat);
        if (!await confirmDialog('مسح القسم ده؟', { danger: true, okText: 'مسح' })) return;
        try { await API.del(`/menu/categories/${id}`); toast('تم المسح', 'success'); reload(); } catch (err) { toastError(err); }
      }
    });
    el.addEventListener('change', async (e) => {
      const a = e.target.closest('[data-avail]');
      if (!a) return;
      try {
        await API.patch(`/menu/items/${a.dataset.avail}/availability`, { is_available: a.checked });
        const it = menu.items.find((i) => i.id === Number(a.dataset.avail)); if (it) it.is_available = a.checked ? 1 : 0;
        toast(a.checked ? 'الصنف متاح' : 'الصنف اتقفل', 'success', 1800);
      } catch (err) { a.checked = !a.checked; toastError(err); }
    });
    $('#add-cat').onclick = () => catForm();
    $('#add-item').onclick = () => itemForm();
    draw();
  },
};
