// Service Worker: يخلي الواجهة تفتح بسرعة وتتثبت كتطبيق على الموبايل
// الـ API دايماً من السيرفر مباشرة (البيانات لازم تكون لحظية)
const CACHE = 'restaurant-v1';
const ASSETS = [
  './', 'index.html', 'css/app.css', 'manifest.webmanifest',
  'js/vendor/socket.io.min.js', 'js/core.js', 'js/app.js',
  'js/pages/login.js', 'js/pages/dashboard.js', 'js/pages/orders.js', 'js/pages/new-order.js',
  'js/pages/customers.js', 'js/pages/menu.js', 'js/pages/branches.js', 'js/pages/users.js', 'js/pages/settings.js',
  'icons/icon.svg', 'icons/icon-192.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  if (url.pathname.includes('/api/') || url.pathname.includes('/socket.io/') || url.pathname.includes('/uploads/')) return;
  // الشبكة أولاً عشان أي تحديث يظهر فوراً، والكاش لو مفيش نت
  e.respondWith(
    fetch(e.request)
      .then((res) => { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return res; })
      .catch(() => caches.match(e.request).then((r) => r || caches.match('index.html'))),
  );
});
