'use strict';

Pages.settings = {
  render(el) {
    App.setTitle('الإعدادات');
    const s = App.settings;
    const canManage = App.can('settings.manage');
    const serverUrl = API.base || location.origin;
    el.innerHTML = `
      <div class="stack" style="max-width:760px;gap:16px">
        ${canManage ? `
        <form class="card" id="s-form">
          <div class="card-head"><h3>بيانات المطعم</h3></div>
          <div class="card-body stack">
            <div class="grid-2">
              <label class="field"><span>اسم المطعم</span><input class="input" name="restaurant_name" value="${esc(s.restaurant_name)}"></label>
              <label class="field"><span>العملة</span><input class="input" name="currency" value="${esc(s.currency)}"></label>
              <label class="field"><span>تليفون المطعم / الخط الساخن</span><input class="input" type="tel" name="restaurant_phone" value="${esc(s.restaurant_phone)}"></label>
              <label class="field"><span>رسالة آخر الفاتورة</span><input class="input" name="receipt_footer" value="${esc(s.receipt_footer)}"></label>
            </div>
            <div><button class="btn primary" type="submit">حفظ</button></div>
          </div>
        </form>` : ''}

        <div class="card">
          <div class="card-head"><h3>الجهاز ده</h3></div>
          <div class="card-body stack">
            <div class="row between"><div><b>صوت تنبيه الطلبات الجديدة</b><div class="small muted">يشتغل أول ما طلب جديد يوصل</div></div>
              <div class="row"><button class="btn sm" id="test-sound">${icon('bell')}تجربة</button><label class="switch"><input type="checkbox" id="sound" ${Sound.enabled() ? 'checked' : ''}><span></span></label></div></div>
            <div class="row between"><div><b>إشعارات المتصفح</b><div class="small muted">تنبيه حتى لو الصفحة مش مفتوحة قدامك</div></div>
              <button class="btn sm" id="notif">${'Notification' in window && Notification.permission === 'granted' ? 'مفعلة ✔' : 'تفعيل'}</button></div>
            <div class="row between"><div><b>المظهر</b></div>
              <div class="segmented" id="theme"><button data-t="">تلقائي</button><button data-t="light">فاتح</button><button data-t="dark">غامق</button></div></div>
          </div>
        </div>

        <div class="card">
          <div class="card-head"><h3>ربط الموبايل والتطبيق</h3></div>
          <div class="card-body stack">
            <div>عنوان السيرفر: <b class="num">${esc(serverUrl)}</b></div>
            <div class="small muted">افتح العنوان ده من متصفح الموبايل (لازم يكون على نفس الواي فاي لو السيرفر على جهاز في المطعم)، وبعدين من قائمة المتصفح اختار <b>"إضافة إلى الشاشة الرئيسية"</b> وهيشتغل كتطبيق. ولو بتستخدم تطبيق الأندرويد، اكتب العنوان ده في خانة "عنوان السيرفر" في شاشة الدخول.</div>
          </div>
        </div>

        <form class="card" id="pw-form">
          <div class="card-head"><h3>تغيير كلمة المرور</h3><span class="muted small">${esc(App.user.name)} (${esc(App.user.username)})</span></div>
          <div class="card-body stack">
            <div class="grid-3">
              <label class="field"><span>الحالية</span><input class="input ltr" type="password" name="current_password" required autocomplete="current-password"></label>
              <label class="field"><span>الجديدة</span><input class="input ltr" type="password" name="new_password" required autocomplete="new-password"></label>
              <label class="field"><span>تأكيد الجديدة</span><input class="input ltr" type="password" name="confirm" required autocomplete="new-password"></label>
            </div>
            <div><button class="btn primary" type="submit">تغيير</button></div>
          </div>
        </form>

        <div><button class="btn danger" id="logout2">${icon('logout')}تسجيل خروج</button></div>
      </div>`;

    const sf = $('#s-form', el);
    if (sf) sf.onsubmit = (e) => {
      e.preventDefault();
      busy(sf.querySelector('[type=submit]'), async () => {
        App.settings = await API.put('/settings', formData(sf));
        $$('.brand-name').forEach((b) => { b.textContent = App.settings.restaurant_name; });
        toast('تم الحفظ', 'success');
      });
    };
    const pf = $('#pw-form', el);
    pf.onsubmit = (e) => {
      e.preventDefault();
      const d = formData(pf);
      if (d.new_password !== d.confirm) return toast('كلمة المرور الجديدة مش متطابقة', 'error');
      busy(pf.querySelector('[type=submit]'), async () => {
        await API.post('/auth/change-password', d);
        pf.reset(); toast('تم تغيير كلمة المرور', 'success');
      });
    };
    $('#sound', el).onchange = (e) => Store.set('sound', e.target.checked ? '1' : '0');
    $('#test-sound', el).onclick = () => { const was = Store.get('sound', '1'); Store.set('sound', '1'); Sound.play(); Store.set('sound', was); };
    $('#notif', el).onclick = async (e) => {
      if (!('Notification' in window)) return toast('المتصفح ده مش بيدعم الإشعارات', 'error');
      const p = await Notification.requestPermission();
      e.target.textContent = p === 'granted' ? 'مفعلة ✔' : 'تفعيل';
      if (p !== 'granted') toast('لازم تسمح بالإشعارات من إعدادات المتصفح', 'error');
    };
    const drawTheme = () => $$('#theme button', el).forEach((b) => b.classList.toggle('active', b.dataset.t === (Store.get('theme') || '')));
    $('#theme', el).onclick = (e) => { const b = e.target.closest('[data-t]'); if (!b) return; Store.set('theme', b.dataset.t || null); App.applyTheme(); drawTheme(); };
    drawTheme();
    $('#logout2', el).onclick = async () => { if (await confirmDialog('تسجيل خروج؟')) App.logout(); };
  },
};
