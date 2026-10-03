'use strict';

Pages.login = {
  show() {
    const isApp = !!window.Capacitor || !!API.base;
    $('#root').innerHTML = `
      <div class="login-wrap">
        <form class="card login-card stack" id="login-form" autocomplete="on">
          <div>
            <div class="brand-logo">${icon('chef')}</div>
            <h1>${esc(App.settings.restaurant_name || 'إدارة طلبات المطعم')}</h1>
            <p class="sub">سجل دخول عشان تكمل</p>
          </div>
          <div class="stack ${isApp ? '' : 'hidden'}" id="server-box">
            <label class="field"><span>عنوان السيرفر</span>
              <input class="input ltr" name="server" placeholder="http://192.168.1.10:3000" value="${esc(API.base)}" inputmode="url"></label>
          </div>
          <label class="field"><span>اسم المستخدم</span>
            <input class="input ltr" name="username" autocomplete="username" required autocapitalize="off"></label>
          <label class="field"><span>كلمة المرور</span>
            <input class="input ltr" name="password" type="password" autocomplete="current-password" required></label>
          <button class="btn primary lg block" type="submit">دخول</button>
          <button type="button" class="btn ghost sm ${isApp ? 'hidden' : ''}" id="show-server">إعدادات الاتصال بالسيرفر</button>
        </form>
      </div>`;
    $('#show-server').onclick = (e) => { $('#server-box').classList.remove('hidden'); e.target.classList.add('hidden'); };
    $('#login-form').onsubmit = async (e) => {
      e.preventDefault();
      const d = formData(e.target);
      const btn = e.target.querySelector('[type=submit]');
      await busy(btn, async () => {
        if (!$('#server-box').classList.contains('hidden')) API.base = d.server.trim();
        const r = await API.post('/auth/login', { username: d.username.trim(), password: d.password });
        API.token = r.token;
        App.user = r.user;
        try { const info = await API.get('/public/info'); App.settings = { ...App.settings, ...info }; } catch { /* ignore */ }
        await App.start();
        // طلب إذن الإشعارات
        if ('Notification' in window && Notification.permission === 'default') Notification.requestPermission().catch(() => {});
      });
    };
  },
  render() { App.route(); },
};
