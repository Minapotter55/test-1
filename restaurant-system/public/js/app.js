/* =========================================================
   التطبيق: التخطيط، التنقل، الاتصال اللحظي
   ========================================================= */
'use strict';

const NAV = [
  { route: 'dashboard', label: 'لوحة التحكم', icon: 'dashboard', perms: ['dashboard.view'], bottom: true },
  { route: 'orders', label: 'الطلبات', icon: 'orders', perms: ['orders.view_all', 'orders.view_branch', 'orders.delivery', 'orders.create'], bottom: true, badge: true },
  { route: 'new', label: 'طلب جديد', icon: 'plus', perms: ['orders.create'], bottom: true },
  { route: 'customers', label: 'العملاء', icon: 'users', perms: ['customers.view'], bottom: true },
  { sep: true },
  { route: 'menu', label: 'المنيو والأسعار', icon: 'menu', perms: ['menu.manage'] },
  { route: 'branches', label: 'الفروع', icon: 'store', perms: ['branches.manage'] },
  { route: 'users', label: 'المستخدمين', icon: 'user', perms: ['users.manage'] },
  { route: 'roles', label: 'الأدوار والصلاحيات', icon: 'shield', perms: ['users.manage'] },
  { route: 'settings', label: 'الإعدادات', icon: 'settings', perms: [], bottom: true },
];

const App = {
  user: null, meta: null, settings: {}, branches: [], menu: null,
  socket: null, listeners: {}, cleanup: null, newCount: 0,

  can(p) { return !!this.user && (this.user.is_admin || this.user.permissions.includes(p)); },
  canAny(...ps) { return ps.length === 0 || ps.some((p) => this.can(p)); },

  // أحداث خاصة بالصفحة الحالية (بتتمسح مع التنقل)
  on(evt, fn) { (this.listeners[evt] = this.listeners[evt] || []).push(fn); },
  emit(evt, data) { (this.listeners[evt] || []).forEach((fn) => { try { fn(data); } catch (e) { console.error(e); } }); },

  async boot() {
    Tip.init();
    this.applyTheme();
    window.addEventListener('hashchange', () => this.route());
    try { const info = await API.get('/public/info'); this.settings = { ...this.settings, ...info }; } catch { /* السيرفر مش متاح */ }
    if (!API.token) return Pages.login.show();
    try {
      const { user } = await API.get('/auth/me');
      this.user = user;
      await this.start();
    } catch (e) {
      if (!API.token) return; // اتعمل logout
      $('#root').innerHTML = `<div class="login-wrap"><div class="card login-card stack" style="text-align:center">
        <p>${esc(e.message)}</p>
        <button class="btn primary" onclick="location.reload()">حاول تاني</button>
        <button class="btn" onclick="App.logout()">تسجيل خروج</button></div></div>`;
    }
  },

  async start() {
    const [meta, settings, branches] = await Promise.all([API.get('/meta'), API.get('/settings'), API.get('/branches')]);
    this.meta = meta; this.settings = settings; this.branches = branches;
    this.renderLayout();
    this.connectSocket();
    this.refreshNewCount();
    if (!location.hash || location.hash === '#/' || location.hash === '#/login') location.hash = `#/${this.homeRoute()}`;
    else this.route();
  },

  homeRoute() {
    const first = NAV.find((n) => n.route && this.canAny(...n.perms));
    return first ? first.route : 'settings';
  },

  async getMenu(force = false) {
    if (!this.menu || force) this.menu = await API.get('/menu');
    return this.menu;
  },
  async reloadBranches() { this.branches = await API.get('/branches'); },

  // ---------- الاتصال اللحظي ----------
  connectSocket() {
    if (typeof io === 'undefined') return;
    if (this.socket) this.socket.disconnect();
    this.socket = io(API.base || undefined, { auth: { token: API.token }, transports: ['websocket', 'polling'] });
    const dot = () => $$('.conn-dot').forEach((d) => d.classList.toggle('on', this.socket.connected));
    this.socket.on('connect', () => { dot(); this.emit('reconnect'); });
    this.socket.on('disconnect', dot);
    this.socket.on('connect_error', dot);

    this.socket.on('order:new', (o) => {
      this.refreshNewCount();
      // متنبهش اللي سجل الطلب بنفسه
      if (o.created_by !== this.user.id || this.can('orders.view_branch')) this.notifyNewOrder(o);
      this.emit('order:new', o);
      this.emit('orders:changed', o);
    });
    this.socket.on('order:updated', (o) => {
      this.refreshNewCount();
      OrderView.refreshIfOpen(o.id);
      this.emit('order:updated', o);
      this.emit('orders:changed', o);
    });
    this.socket.on('menu:changed', () => { this.menu = null; this.emit('menu:changed'); });
    this.socket.on('branches:changed', async () => { await this.reloadBranches(); this.emit('branches:changed'); });
    this.socket.on('settings:changed', (s) => { this.settings = s; $$('.brand-name').forEach((e) => { e.textContent = s.restaurant_name; }); });
  },

  notifyNewOrder(o) {
    Sound.play();
    const t = toast(`${icon('bell')} طلب جديد <b class="num">#${esc(o.order_no)}</b> - ${esc(o.branch_name)} - ${fmt.money(o.total)}`, 'order', 8000);
    t.onclick = () => { t.remove(); OrderView.open(o.id); };
    try {
      if ('Notification' in window && Notification.permission === 'granted' && document.hidden) {
        const n = new Notification(`طلب جديد #${o.order_no}`, { body: `${o.customer_name} - ${o.branch_name} - ${fmt.moneyText(o.total)}`, icon: 'icons/icon-192.png', tag: `order-${o.id}` });
        n.onclick = () => { window.focus(); OrderView.open(o.id); };
      }
    } catch { /* ignore */ }
  },

  refreshNewCount: debounce(async function refresh() {
    if (!App.canAny('orders.view_all', 'orders.view_branch')) return;
    try {
      const r = await API.get('/orders?status=new&limit=1');
      App.newCount = r.total;
      $$('[data-badge]').forEach((b) => { b.textContent = r.total; b.classList.toggle('hidden', !r.total); });
      document.title = `${r.total ? `(${r.total}) ` : ''}${App.settings.restaurant_name || 'إدارة الطلبات'}`;
    } catch { /* ignore */ }
  }, 400),

  // ---------- التخطيط ----------
  renderLayout() {
    const items = NAV.filter((n) => n.sep || this.canAny(...n.perms));
    const navHtml = items.map((n) => (n.sep ? '<div class="nav-sep"></div>' : `
      <a href="#/${n.route}" data-route="${n.route}">${icon(n.icon)}<span>${n.label}</span>
        ${n.badge ? '<span class="badge-count hidden" data-badge>0</span>' : ''}</a>`)).join('');
    const bottom = items.filter((n) => n.bottom).slice(0, 5).map((n) => `
      <a href="#/${n.route}" data-route="${n.route}">${icon(n.icon)}<span>${n.label}</span>
        ${n.badge ? '<span class="badge-count hidden" data-badge>0</span>' : ''}</a>`).join('');
    const u = this.user;
    $('#root').innerHTML = `
      <div class="app">
        <aside class="sidebar">
          <div class="brand"><div class="brand-logo">${icon('chef')}</div><div class="brand-name">${esc(this.settings.restaurant_name)}</div></div>
          <nav class="nav">${navHtml}</nav>
          <div class="sidebar-foot">
            <div class="user-chip">
              <div class="avatar">${esc((u.name || '?').trim().charAt(0))}</div>
              <div class="grow"><div style="font-weight:700;font-size:14px">${esc(u.name)}</div>
                <div class="small muted">${esc(u.role_name)}${u.branch_name ? ` - ${esc(u.branch_name)}` : ''}</div></div>
              <button class="btn icon ghost" id="logout-btn" title="تسجيل خروج">${icon('logout')}</button>
            </div>
          </div>
        </aside>
        <div class="backdrop" id="backdrop"></div>
        <div class="main">
          <header class="topbar">
            <button class="btn icon ghost menu-toggle" id="menu-toggle" aria-label="القائمة">${icon('hamburger')}</button>
            <h1 id="page-title"></h1>
            <span class="conn-dot" title="الاتصال اللحظي"></span>
            <div id="page-actions" class="row"></div>
          </header>
          <main class="content" id="page"></main>
        </div>
        <nav class="bottom-nav">${bottom}</nav>
      </div>`;
    $('#menu-toggle').onclick = () => document.body.classList.toggle('nav-open');
    $('#backdrop').onclick = () => document.body.classList.remove('nav-open');
    $('#logout-btn').onclick = async () => { if (await confirmDialog('تسجيل خروج؟')) this.logout(); };
  },

  setTitle(title, actionsHtml = '') {
    $('#page-title').textContent = title;
    $('#page-actions').innerHTML = actionsHtml;
    document.title = `${title} - ${this.settings.restaurant_name || ''}`;
  },

  // ---------- التنقل ----------
  route() {
    if (!this.user) return;
    const raw = location.hash.replace(/^#\/?/, '');
    const [pathPart, queryPart] = raw.split('?');
    const [name, ...params] = pathPart.split('/');
    const query = Object.fromEntries(new URLSearchParams(queryPart || ''));
    const page = Pages[name];
    const navItem = NAV.find((n) => n.route === name);
    if (!page || name === 'login' || (navItem && !this.canAny(...navItem.perms))) {
      location.hash = `#/${this.homeRoute()}`;
      return;
    }
    if (typeof this.cleanup === 'function') { try { this.cleanup(); } catch { /* ignore */ } }
    this.cleanup = null;
    this.listeners = {};
    document.body.classList.remove('nav-open');
    $$('[data-route]').forEach((a) => a.classList.toggle('active', a.dataset.route === name));
    // كل صفحة بتترسم في عنصر جديد، فلو صفحة قديمة خلصت تحميل متأخر مش هتكتب فوق الصفحة الجديدة
    const host = $('#page');
    host.innerHTML = '';
    const el = document.createElement('div');
    el.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    host.appendChild(el);
    window.scrollTo(0, 0);
    Promise.resolve(page.render(el, params, query)).then((c) => { this.cleanup = c; }).catch((e) => {
      el.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
    });
  },

  logout(expired = false) {
    API.token = null;
    this.user = null;
    if (this.socket) { this.socket.disconnect(); this.socket = null; }
    if (expired) toast('انتهت الجلسة، سجل دخول تاني', 'error');
    location.hash = '';
    Pages.login.show();
  },

  applyTheme() {
    const t = Store.get('theme');
    if (t) document.documentElement.dataset.theme = t; else delete document.documentElement.dataset.theme;
  },
};

// تسجيل الـ Service Worker عشان التطبيق يتثبت على الموبايل
if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
}

App.boot();
