'use strict';

Pages.new = {
  async render(el, params, query) {
    App.setTitle('طلب جديد');
    const menu = await App.getMenu();
    const lockedBranch = !App.can('orders.view_all') && App.user.branch_id;
    const activeBranches = App.branches.filter((b) => b.is_active);
    const S = {
      customer: { id: null, name: '', phone: query.phone || '', phone2: '' },
      found: null, // بيانات العميل المسجل
      addressId: 'new',
      addr: { area: '', address: '', landmark: '', label: '' },
      type: 'delivery',
      branch_id: lockedBranch || Number(Store.get('lastBranch')) || activeBranches[0]?.id || '',
      payment: 'cash',
      discount: 0,
      notes: '',
      cart: [],
      cat: 'all',
      search: '',
    };
    if (!activeBranches.find((b) => b.id === S.branch_id) && !lockedBranch) S.branch_id = activeBranches[0]?.id || '';

    const branch = () => App.branches.find((b) => b.id === Number(S.branch_id));
    const deliveryFee = () => (S.type === 'delivery' ? Number(branch()?.delivery_fee || 0) : 0);
    const subtotal = () => S.cart.reduce((s, l) => s + l.price * l.qty, 0);
    const total = () => Math.max(0, subtotal() + deliveryFee() - Number(S.discount || 0));
    const cartCount = () => S.cart.reduce((s, l) => s + l.qty, 0);

    el.innerHTML = `
      <div class="pos">
        <div class="stack">
          <div class="card">
            <div class="card-head"><h3>${icon('user').replace('<svg', '<svg style="width:18px;height:18px;vertical-align:-3px"')} بيانات العميل</h3><div id="cust-status"></div></div>
            <div class="card-body stack">
              <div class="grid-2">
                <label class="field"><span>رقم الموبايل *</span><input class="input" type="tel" id="c-phone" inputmode="tel" autocomplete="off" placeholder="01xxxxxxxxx" value="${esc(S.customer.phone)}"></label>
                <label class="field"><span>اسم العميل *</span><input class="input" id="c-name" autocomplete="off"></label>
              </div>
              <div id="last-orders"></div>
              <div class="row">
                <div class="segmented" id="type">${Object.entries(App.meta.order_types).map(([k, v]) => `<button data-type="${k}">${esc(v)}</button>`).join('')}</div>
                ${lockedBranch ? `<span class="badge plain">${icon('store').replace('<svg', '<svg style="width:14px;height:14px"')} ${esc(App.user.branch_name || '')}</span>`
                  : `<select class="input" id="branch" style="width:auto;flex:1;min-width:160px">${activeBranches.map((b) => `<option value="${b.id}">${esc(b.name)}</option>`).join('')}</select>`}
              </div>
              <div id="addr-box"></div>
            </div>
          </div>

          <div class="card">
            <div class="card-head"><h3>المنيو</h3><input class="input" id="m-search" type="search" placeholder="بحث عن صنف" style="max-width:240px"></div>
            <div class="card-body stack">
              <div class="cats" id="cats"></div>
              <div class="items-grid" id="items"></div>
            </div>
          </div>
        </div>

        <div class="pos-side" id="cart-panel">
          <div class="card">
            <div class="card-head"><h3>الطلب <span class="muted small" id="cart-count"></span></h3><button class="btn sm ghost" id="clear-cart">تفريغ</button></div>
            <div class="card-body" style="padding-top:4px;padding-bottom:4px" id="cart"></div>
          </div>
          <div class="card card-pad stack">
            <div class="grid-2">
              <label class="field"><span>طريقة الدفع</span><select class="input" id="payment">${Object.entries(App.meta.payment_methods).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('')}</select></label>
              <label class="field"><span>خصم</span><input class="input" id="discount" type="number" min="0" step="0.5" value="0" inputmode="decimal"></label>
            </div>
            <label class="field"><span>ملاحظات للمطبخ / الطيار</span><textarea class="input" id="notes" rows="2" placeholder="مثلاً: من غير بصل، الدور الثالث..."></textarea></label>
            <div class="totals" id="totals"></div>
            <button class="btn primary lg block" id="submit">${icon('check')}إرسال الطلب للفرع</button>
          </div>
        </div>
      </div>
      <button class="mobile-cart-bar" id="mobile-bar"><span id="mb-count"></span><span id="mb-total"></span></button>`;

    // ---------- رسم الأجزاء ----------
    const drawType = () => {
      $$('#type button', el).forEach((b) => b.classList.toggle('active', b.dataset.type === S.type));
      drawAddress(); drawTotals();
    };

    const drawAddress = () => {
      const box = $('#addr-box', el);
      if (S.type !== 'delivery') { box.innerHTML = ''; return; }
      const addrs = S.found ? S.found.addresses : [];
      const newForm = `
        <div class="grid-2" style="margin-top:${addrs.length ? '8px' : '0'}">
          <label class="field"><span>المنطقة</span><input class="input" data-addr="area" value="${esc(S.addr.area)}"></label>
          <label class="field"><span>علامة مميزة</span><input class="input" data-addr="landmark" value="${esc(S.addr.landmark)}"></label>
        </div>
        <label class="field" style="margin-top:8px"><span>العنوان بالتفصيل *</span><input class="input" data-addr="address" value="${esc(S.addr.address)}" placeholder="الشارع - رقم العمارة - الدور - الشقة"></label>`;
      box.innerHTML = `<div class="field"><span>عنوان التوصيل</span></div>
        ${addrs.length ? `<div class="stack" style="gap:8px">${addrs.map((a) => `
          <label class="addr-option"><input type="radio" name="addr" value="${a.id}" ${String(S.addressId) === String(a.id) ? 'checked' : ''}>
            <div>${a.label ? `<b>${esc(a.label)}</b> - ` : ''}${esc([a.area, a.address].filter(Boolean).join(' - '))}${a.landmark ? `<div class="small muted">${esc(a.landmark)}</div>` : ''}</div></label>`).join('')}
          <label class="addr-option"><input type="radio" name="addr" value="new" ${S.addressId === 'new' ? 'checked' : ''}><div>${icon('plus').replace('<svg', '<svg style="width:14px;height:14px;vertical-align:-2px"')} عنوان جديد</div></label>
        </div>` : ''}
        ${S.addressId === 'new' || !addrs.length ? newForm : ''}`;
    };

    const drawCats = () => {
      const cats = menu.categories.filter((c) => c.is_active);
      $('#cats', el).innerHTML = `<button data-cat="all" class="${S.cat === 'all' ? 'active' : ''}">الكل</button>${cats.map((c) => `<button data-cat="${c.id}" class="${String(S.cat) === String(c.id) ? 'active' : ''}">${esc(c.name)}</button>`).join('')}`;
    };

    const drawItems = () => {
      const activeCats = new Set(menu.categories.filter((c) => c.is_active).map((c) => c.id));
      const q = S.search.toLowerCase();
      const items = menu.items.filter((i) => activeCats.has(i.category_id) && (S.cat === 'all' || String(i.category_id) === String(S.cat)) && (!q || i.name.toLowerCase().includes(q)));
      $('#items', el).innerHTML = items.length ? items.map((i) => {
        const inCart = S.cart.filter((l) => l.item_id === i.id).reduce((s, l) => s + l.qty, 0);
        const img = i.image_url ? `style="background-image:url('${esc((i.image_url.startsWith('/') ? API.base : '') + i.image_url)}')"` : '';
        return `<button class="item-tile" data-add="${i.id}" ${i.is_available ? '' : 'disabled'}>
          <div class="img" ${img}>${i.image_url ? '' : icon('food')}</div>
          <div class="body"><span class="nm">${esc(i.name)}</span>
            <span class="pr">${i.is_available ? fmt.money(i.price) : 'غير متاح'}</span></div>
          ${inCart ? `<span class="badge-count qty-badge">${inCart}</span>` : ''}</button>`;
      }).join('') : '<div class="empty" style="grid-column:1/-1">مفيش أصناف</div>';
    };

    const drawCart = () => {
      $('#cart', el).innerHTML = S.cart.length ? S.cart.map((l, idx) => `
        <div class="cart-line">
          <div><div class="nm">${esc(l.name)}</div><div class="small muted">${fmt.money(l.price)}</div></div>
          <div class="row" style="gap:8px;justify-content:flex-end">
            <div class="qty"><button data-inc="${idx}">+</button><span class="num">${l.qty}</span><button data-dec="${idx}">−</button></div>
          </div>
          <div class="note"><input class="input" data-note="${idx}" value="${esc(l.notes)}" placeholder="ملاحظة على الصنف"></div>
        </div>`).join('') : `<div class="empty" style="padding:24px 0">${icon('food')}<div>اختار أصناف من المنيو</div></div>`;
      $('#cart-count', el).textContent = S.cart.length ? `(${cartCount()})` : '';
      drawTotals(); drawItems();
    };

    const drawTotals = () => {
      $('#totals', el).innerHTML = `
        <div><span>المجموع</span><span>${fmt.money(subtotal())}</span></div>
        ${S.type === 'delivery' ? `<div><span>التوصيل</span><span>${fmt.money(deliveryFee())}</span></div>` : ''}
        ${Number(S.discount) ? `<div><span>الخصم</span><span>- ${fmt.money(S.discount)}</span></div>` : ''}
        <div class="grand"><span>الإجمالي</span><span>${fmt.money(total())}</span></div>`;
      $('#mb-count', el).textContent = cartCount() ? `${cartCount()} صنف - عرض الطلب` : 'السلة فاضية';
      $('#mb-total', el).innerHTML = fmt.money(total());
    };

    const drawCustomerStatus = () => {
      const f = S.found;
      $('#cust-status', el).innerHTML = f ? `<span class="badge on">عميل مسجل - ${f.stats.orders_count} طلب</span>` : (S.customer.phone.length >= 8 ? '<span class="badge plain">عميل جديد</span>' : '');
      $('#last-orders', el).innerHTML = f && f.orders.length ? `
        <div class="customer-found row between">
          <span>آخر طلب: ${esc(fmt.date(f.orders[0].created_at))} - ${fmt.money(f.orders[0].total)}${f.notes ? ` | ${esc(f.notes)}` : ''}</span>
          <button class="btn sm" id="reorder">${icon('repeat')}كرر آخر طلب</button>
        </div>` : '';
      const re = $('#reorder', el);
      if (re) re.onclick = () => busy(re, async () => {
        const o = await API.get(`/orders/${f.orders[0].id}`);
        let skipped = 0;
        for (const it of o.items) {
          const item = menu.items.find((m) => m.id === it.item_id);
          if (!item || !item.is_available) { skipped++; continue; }
          addToCart(item, it.qty, it.notes);
        }
        if (o.type) { S.type = o.type; drawType(); }
        toast(skipped ? `تم إضافة الأصناف (${skipped} صنف مش متاح)` : 'تم إضافة أصناف آخر طلب', 'success');
      });
    };

    const addToCart = (item, qty = 1, notes = '') => {
      const line = S.cart.find((l) => l.item_id === item.id && l.notes === notes);
      if (line) line.qty += qty; else S.cart.push({ item_id: item.id, name: item.name, price: item.price, qty, notes });
      drawCart();
    };

    // ---------- البحث عن العميل ----------
    let lookupSeq = 0;
    const lookup = async () => {
      const phone = S.customer.phone.replace(/[^\d+]/g, '');
      const seq = ++lookupSeq;
      if (phone.length < 8) { S.found = null; drawCustomerStatus(); drawAddress(); return; }
      try {
        const c = await API.get(`/customers/lookup?phone=${encodeURIComponent(phone)}`);
        if (seq !== lookupSeq) return;
        S.found = c;
        if (c) {
          S.customer.id = c.id;
          if (!$('#c-name', el).value) { $('#c-name', el).value = c.name; S.customer.name = c.name; }
          S.addressId = c.addresses.length ? c.addresses[0].id : 'new';
        } else { S.customer.id = null; S.addressId = 'new'; }
        drawCustomerStatus(); drawAddress();
      } catch (e) { toastError(e); }
    };

    // ---------- الأحداث ----------
    $('#c-phone', el).oninput = debounce((e) => { S.customer.phone = e.target.value.trim(); lookup(); }, 400);
    $('#c-name', el).oninput = (e) => { S.customer.name = e.target.value; };
    $('#type', el).onclick = (e) => { const b = e.target.closest('[data-type]'); if (b) { S.type = b.dataset.type; drawType(); } };
    if ($('#branch', el)) { $('#branch', el).value = S.branch_id; $('#branch', el).onchange = (e) => { S.branch_id = Number(e.target.value); Store.set('lastBranch', S.branch_id); drawTotals(); }; }
    $('#addr-box', el).addEventListener('change', (e) => { if (e.target.name === 'addr') { S.addressId = e.target.value; drawAddress(); } });
    $('#addr-box', el).addEventListener('input', (e) => { if (e.target.dataset.addr) S.addr[e.target.dataset.addr] = e.target.value; });
    $('#cats', el).onclick = (e) => { const b = e.target.closest('[data-cat]'); if (b) { S.cat = b.dataset.cat; drawCats(); drawItems(); } };
    $('#m-search', el).oninput = (e) => { S.search = e.target.value.trim(); drawItems(); };
    $('#items', el).onclick = (e) => { const b = e.target.closest('[data-add]'); if (b) addToCart(menu.items.find((i) => i.id === Number(b.dataset.add))); };
    $('#cart', el).addEventListener('click', (e) => {
      const inc = e.target.closest('[data-inc]'); const dec = e.target.closest('[data-dec]');
      if (inc) { S.cart[inc.dataset.inc].qty++; drawCart(); }
      if (dec) { const l = S.cart[dec.dataset.dec]; l.qty--; if (l.qty <= 0) S.cart.splice(dec.dataset.dec, 1); drawCart(); }
    });
    $('#cart', el).addEventListener('input', (e) => { if (e.target.dataset.note !== undefined) S.cart[e.target.dataset.note].notes = e.target.value; });
    $('#clear-cart', el).onclick = () => { S.cart = []; drawCart(); };
    $('#payment', el).onchange = (e) => { S.payment = e.target.value; };
    $('#discount', el).oninput = (e) => { S.discount = Math.max(0, Number(e.target.value) || 0); drawTotals(); };
    $('#notes', el).oninput = (e) => { S.notes = e.target.value; };
    $('#mobile-bar', el).onclick = () => $('#cart-panel', el).scrollIntoView({ behavior: 'smooth' });

    $('#submit', el).onclick = (e) => busy(e.currentTarget, async () => {
      S.customer.name = $('#c-name', el).value.trim();
      if (!S.customer.phone) throw new Error('اكتب رقم موبايل العميل');
      if (!S.customer.name) throw new Error('اكتب اسم العميل');
      if (!S.cart.length) throw new Error('الطلب فاضي، اختار أصناف');
      if (!S.branch_id) throw new Error('اختار الفرع');
      const body = {
        branch_id: Number(S.branch_id), type: S.type, payment_method: S.payment,
        discount: Number(S.discount) || 0, notes: S.notes,
        customer: { name: S.customer.name, phone: S.customer.phone },
        items: S.cart.map((l) => ({ item_id: l.item_id, qty: l.qty, notes: l.notes })),
      };
      if (S.type === 'delivery') {
        if (S.addressId !== 'new' && S.found) body.address = { id: Number(S.addressId) };
        else {
          if (!S.addr.address.trim()) throw new Error('اكتب عنوان التوصيل');
          body.address = { ...S.addr };
        }
      }
      const o = await API.post('/orders', body);
      success(o);
    });

    const success = (o) => {
      const m = modal({
        title: 'تم تسجيل الطلب ✔', size: 'sm',
        body: `<div class="stack" style="text-align:center">
          <div style="font-size:30px;font-weight:800" class="num">#${esc(o.order_no)}</div>
          <div>اتبعت لـ <b>${esc(o.branch_name)}</b> - الإجمالي ${fmt.money(o.total)}</div>
          <div class="row" style="justify-content:center">
            <button class="btn" data-print>${icon('print')}طباعة</button>
            <a class="btn" target="_blank" rel="noopener" href="${esc(waLink(o.customer_phone, `أهلاً ${o.customer_name}، طلبك رقم ${o.order_no} اتسجل بنجاح ✔ الإجمالي ${fmt.moneyText(o.total)}. تابع حالة طلبك من هنا: ${trackUrl(o)}`))}">${icon('whatsapp')}إرسال للعميل</a>
          </div></div>`,
        footer: '<button class="btn primary" data-new>طلب جديد</button><button class="btn" data-view>عرض الطلب</button>',
        onClose: () => { if (location.hash.startsWith('#/new')) App.route(); },
      });
      m.el.querySelector('[data-print]').onclick = () => printReceipt(o);
      m.el.querySelector('[data-new]').onclick = () => m.close();
      m.el.querySelector('[data-view]').onclick = () => { m.close(); location.hash = '#/orders'; setTimeout(() => OrderView.open(o.id), 100); };
    };

    App.on('menu:changed', async () => {
      const fresh = await App.getMenu(true);
      menu.categories = fresh.categories; menu.items = fresh.items;
      drawCats(); drawItems();
    });

    drawType(); drawCats(); drawCart(); drawCustomerStatus();
    if (S.customer.phone) lookup();
  },
};
