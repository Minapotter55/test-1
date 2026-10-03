/* =========================================================
   الأساسيات: الاتصال بالسيرفر، الحالة، الأدوات المشتركة
   ========================================================= */
'use strict';

const Store = {
  get(k, def = null) { try { const v = localStorage.getItem(k); return v === null ? def : v; } catch { return def; } },
  set(k, v) { try { v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* ignore */ } },
};

// ---------- الاتصال بالـ API ----------
const API = {
  // عنوان السيرفر: فاضي = نفس العنوان (الويب). في تطبيق الموبايل بيتحدد من شاشة الدخول
  get base() { return (Store.get('apiBase') || window.APP_CONFIG?.apiBase || '').replace(/\/+$/, ''); },
  set base(v) { Store.set('apiBase', v ? v.replace(/\/+$/, '') : null); },
  get token() { return Store.get('token'); },
  set token(v) { Store.set('token', v); },

  async request(method, path, body) {
    const headers = { 'Content-Type': 'application/json' };
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    let res;
    try {
      res = await fetch(`${this.base}/api${path}`, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
    } catch {
      throw new Error('مفيش اتصال بالسيرفر - اتأكد إن السيرفر شغال والنت متوصل');
    }
    let data = null;
    try { data = await res.json(); } catch { /* ignore */ }
    if (res.status === 401 && path !== '/auth/login') {
      App.logout(true);
      throw new Error((data && data.error) || 'انتهت الجلسة، سجل دخول تاني');
    }
    if (!res.ok) throw new Error((data && data.error) || `خطأ ${res.status}`);
    return data;
  },
  get(p) { return this.request('GET', p); },
  post(p, b) { return this.request('POST', p, b || {}); },
  put(p, b) { return this.request('PUT', p, b || {}); },
  patch(p, b) { return this.request('PATCH', p, b || {}); },
  del(p) { return this.request('DELETE', p); },
};

// ---------- أدوات ----------
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];
const qs = (obj) => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(obj)) if (v !== '' && v !== null && v !== undefined) p.set(k, v); const s = p.toString(); return s ? `?${s}` : ''; };
const debounce = (fn, ms = 300) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

const fmt = {
  num: (n) => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 2 }),
  money: (n) => `<span class="num">${fmt.num(n)}</span> ${esc(App.settings.currency || '')}`,
  moneyText: (n) => `${fmt.num(n)} ${App.settings.currency || ''}`,
  parse: (s) => (s ? new Date(String(s).replace(' ', 'T')) : null),
  time: (s) => { const d = fmt.parse(s); return d ? d.toLocaleTimeString('ar-EG', { hour: 'numeric', minute: '2-digit' }) : ''; },
  date: (s) => { const d = fmt.parse(s); return d ? d.toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' }) : ''; },
  dateTime: (s) => (s ? `${fmt.date(s)} - ${fmt.time(s)}` : ''),
  minutesSince: (s) => { const d = fmt.parse(s); return d ? Math.max(0, Math.floor((Date.now() - d.getTime()) / 60000)) : 0; },
  ago: (s) => {
    const m = fmt.minutesSince(s);
    if (m < 1) return 'دلوقتي';
    if (m < 60) return `من ${m} دقيقة`;
    const h = Math.floor(m / 60);
    if (h < 24) return `من ${h} ساعة`;
    return fmt.date(s);
  },
  today: () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); },
  addDays: (iso, n) => { const d = new Date(`${iso}T12:00:00`); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); },
};

const statusLabel = (s) => App.meta?.status_labels?.[s] || s;
const statusBadge = (s) => `<span class="badge s-${esc(s)}">${esc(statusLabel(s))}</span>`;
const typeLabel = (t) => App.meta?.order_types?.[t] || t;
const payLabel = (p) => App.meta?.payment_methods?.[p] || p;
const telLink = (p) => (p ? `<a href="tel:${esc(p)}" class="num">${esc(p)}</a>` : '');
const mapsLink = (addr) => `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(addr)}`;
const waLink = (phone, text) => {
  let p = String(phone || '').replace(/\D/g, '');
  if (p.startsWith('0')) p = `2${p}`; // أرقام مصر
  return `https://wa.me/${p}?text=${encodeURIComponent(text)}`;
};

// ---------- أيقونات ----------
const ICONS = {
  dashboard: '<path d="M3 3h7v9H3zM14 3h7v5h-7zM14 12h7v9h-7zM3 16h7v5H3z"/>',
  orders: '<path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1"/><path d="M9 12h6M9 16h4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  menu: '<path d="M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z"/>',
  store: '<path d="M3 9l1.5-5h15L21 9M3 9v11h18V9M3 9h18M9 20v-6h6v6"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="M9 12l2 2 4-4"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68 1.65 1.65 0 0 0 10 3.17V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
  phone: '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>',
  pin: '<path d="M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
  clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  bike: '<circle cx="5.5" cy="17.5" r="3.5"/><circle cx="18.5" cy="17.5" r="3.5"/><path d="M15 6a1 1 0 1 0 0-2 1 1 0 0 0 0 2zM12 17.5V14l-3-3 4-3 2 3h2"/>',
  print: '<path d="M6 9V2h12v7M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>',
  x: '<path d="M18 6L6 18M6 6l12 12"/>',
  hamburger: '<path d="M3 6h18M3 12h18M3 18h18"/>',
  edit: '<path d="M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  trash: '<path d="M3 6h18M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6M10 11v6M14 11v6M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
  check: '<path d="M20 6L9 17l-5-5"/>',
  chef: '<path d="M6 13.87A4 4 0 0 1 7.41 6a5.11 5.11 0 0 1 1.05-1.54 5 5 0 0 1 7.08 0A5.11 5.11 0 0 1 16.59 6 4 4 0 0 1 18 13.87V21H6z"/><path d="M6 17h12"/>',
  food: '<path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2M7 2v20M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3zm0 0v7"/>',
  refresh: '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>',
  board: '<rect x="3" y="3" width="5" height="18" rx="1"/><rect x="10" y="3" width="5" height="12" rx="1"/><rect x="17" y="3" width="4" height="8" rx="1"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  whatsapp: '<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>',
  bell: '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/>',
  moon: '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
  repeat: '<path d="M17 1l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
  transfer: '<path d="M16 3h5v5M4 20L21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/>',
};
const icon = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;

// ---------- التنبيهات ----------
function toast(msg, type = '', ms = 3500) {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = msg;
  el.onclick = () => el.remove();
  $('#toasts').appendChild(el);
  setTimeout(() => el.remove(), ms);
  return el;
}
const toastError = (err) => toast(esc(err && err.message ? err.message : err), 'error', 5000);

// ---------- المودال ----------
function modal({ title = '', body = '', footer = '', size = '', onClose } = {}) {
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';
  overlay.innerHTML = `
    <div class="modal ${size}" role="dialog" aria-modal="true">
      <div class="modal-head"><h3>${title}</h3><button class="btn icon ghost" data-close aria-label="إغلاق">${icon('x')}</button></div>
      <div class="modal-body">${body}</div>
      ${footer ? `<div class="modal-foot">${footer}</div>` : ''}
    </div>`;
  const detach = () => { overlay.remove(); document.removeEventListener('keydown', onKey); window.removeEventListener('hashchange', detach); };
  const close = () => { if (!overlay.isConnected) return; detach(); if (onClose) onClose(); };
  const onKey = (e) => { if (e.key === 'Escape' && overlay === $$('.modal-overlay').pop()) close(); };
  overlay.addEventListener('click', (e) => { if (e.target === overlay || e.target.closest('[data-close]')) close(); });
  document.addEventListener('keydown', onKey);
  // التنقل لصفحة تانية (أو زرار الرجوع في الموبايل) يقفل المودال
  window.addEventListener('hashchange', detach);
  document.body.appendChild(overlay);
  const first = overlay.querySelector('input:not([type=hidden]):not([type=checkbox]), select, textarea');
  if (first && window.matchMedia('(min-width: 900px)').matches) setTimeout(() => first.focus(), 50);
  return { el: overlay, body: overlay.querySelector('.modal-body'), close, setBody(html) { overlay.querySelector('.modal-body').innerHTML = html; } };
}

function confirmDialog(message, { okText = 'تأكيد', danger = false } = {}) {
  return new Promise((resolve) => {
    let done = false;
    const m = modal({
      title: 'تأكيد', size: 'sm', body: `<p style="margin:0">${message}</p>`,
      footer: `<button class="btn ${danger ? 'danger solid' : 'primary'}" data-ok>${okText}</button><button class="btn" data-close>رجوع</button>`,
      onClose: () => { if (!done) resolve(false); },
    });
    m.el.querySelector('[data-ok]').onclick = () => { done = true; m.close(); resolve(true); };
  });
}

function promptDialog(title, { label = '', placeholder = '', required = false, okText = 'تأكيد', multiline = false } = {}) {
  return new Promise((resolve) => {
    let done = false;
    const input = multiline ? `<textarea class="input" name="v" placeholder="${esc(placeholder)}"></textarea>` : `<input class="input" name="v" placeholder="${esc(placeholder)}">`;
    const m = modal({
      title, size: 'sm', body: `<label class="field"><span>${esc(label)}</span>${input}</label>`,
      footer: `<button class="btn primary" data-ok>${okText}</button><button class="btn" data-close>رجوع</button>`,
      onClose: () => { if (!done) resolve(null); },
    });
    const ok = () => {
      const v = m.el.querySelector('[name=v]').value.trim();
      if (required && !v) { toast('الحقل ده مطلوب', 'error'); return; }
      done = true; m.close(); resolve(v);
    };
    m.el.querySelector('[data-ok]').onclick = ok;
    if (!multiline) m.el.querySelector('[name=v]').addEventListener('keydown', (e) => { if (e.key === 'Enter') ok(); });
  });
}

// قراءة بيانات فورم كـ object
function formData(form) {
  const out = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    if (el.type === 'checkbox') out[el.name] = el.checked;
    else if (el.type === 'radio') { if (el.checked) out[el.name] = el.value; }
    else out[el.name] = el.value;
  }
  return out;
}

// زرار بيعمل عملية: يتقفل لحد ما تخلص
async function busy(btn, fn) {
  if (btn) { btn.disabled = true; btn.dataset.txt = btn.innerHTML; btn.innerHTML = '<span class="spinner" style="width:18px;height:18px;border-width:2px"></span>'; }
  try { return await fn(); } catch (e) { toastError(e); return undefined; } finally {
    if (btn && btn.isConnected) { btn.disabled = false; btn.innerHTML = btn.dataset.txt; }
  }
}

// ---------- صوت التنبيه بالطلب الجديد ----------
const Sound = {
  ctx: null,
  enabled() { return Store.get('sound', '1') === '1'; },
  // المتصفحات بتمنع الصوت لحد أول ضغطة على الصفحة
  unlock() {
    try {
      this.ctx = this.ctx || new (window.AudioContext || window.webkitAudioContext)();
      if (this.ctx.state === 'suspended') this.ctx.resume();
    } catch { /* ignore */ }
  },
  play() {
    if (!this.enabled()) return;
    try {
      this.unlock();
      const ctx = this.ctx;
      [0, 0.18, 0.36].forEach((t, i) => {
        const o = ctx.createOscillator(); const g = ctx.createGain();
        o.type = 'sine'; o.frequency.value = i === 2 ? 1320 : 880;
        g.gain.setValueAtTime(0.0001, ctx.currentTime + t);
        g.gain.exponentialRampToValueAtTime(0.35, ctx.currentTime + t + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + t + 0.16);
        o.connect(g).connect(ctx.destination); o.start(ctx.currentTime + t); o.stop(ctx.currentTime + t + 0.17);
      });
    } catch { /* ignore */ }
  },
};

// ---------- tooltip للرسوم البيانية ----------
const Tip = {
  el: null,
  init() {
    document.addEventListener('mouseover', (e) => {
      const t = e.target.closest('[data-tip]');
      if (!t) { this.hide(); return; }
      if (!this.el) { this.el = document.createElement('div'); this.el.className = 'tooltip'; document.body.appendChild(this.el); }
      this.el.textContent = t.dataset.tip;
      this.el.style.display = 'block';
    });
    document.addEventListener('mousemove', (e) => {
      if (!this.el || this.el.style.display === 'none') return;
      const w = this.el.offsetWidth;
      this.el.style.left = `${Math.min(window.innerWidth - w - 8, Math.max(8, e.clientX - w / 2))}px`;
      this.el.style.top = `${e.clientY - 44}px`;
    });
  },
  hide() { if (this.el) this.el.style.display = 'none'; },
};

// سجل الصفحات - كل صفحة بتسجل نفسها هنا
const Pages = {};

document.addEventListener('pointerdown', () => Sound.unlock(), { once: true });
