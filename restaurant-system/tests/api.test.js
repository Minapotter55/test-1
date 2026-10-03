// اختبارات السيستم: npm test
const { test, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'rest-'));
process.env.DB_FILE = path.join(tmp, 'test.db');
process.env.PORT = '3999';
process.env.HOST = '127.0.0.1';
process.env.JWT_SECRET = 'test-secret';

const { io } = require('socket.io-client');
const BASE = 'http://127.0.0.1:3999';
let server;
const tokens = {};

async function api(method, p, body, who = 'admin') {
  const res = await fetch(`${BASE}/api${p}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(tokens[who] ? { Authorization: `Bearer ${tokens[who]}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json() };
}

before(async () => {
  ({ server } = require('../server/index.js'));
  await new Promise((r) => (server.listening ? r() : server.once('listening', r)));
  for (const [who, pass] of [['admin', 'admin123'], ['callcenter', '123456'], ['kitchen1', '123456'], ['kitchen2', '123456'], ['driver1', '123456'], ['manager1', '123456']]) {
    const r = await api('POST', '/auth/login', { username: who, password: pass }, null);
    assert.equal(r.status, 200, `login ${who}`);
    tokens[who] = r.data.token;
  }
});

after(() => {
  server.closeAllConnections();
  server.close();
  setTimeout(() => process.exit(0), 300).unref();
});

test('رفض الدخول بكلمة مرور غلط', async () => {
  const r = await api('POST', '/auth/login', { username: 'admin', password: 'x' }, null);
  assert.equal(r.status, 401);
});

test('الـ API محمي بتسجيل الدخول', async () => {
  const r = await api('GET', '/orders', null, null);
  assert.equal(r.status, 401);
});

test('الصلاحيات: موظف المطبخ مينفعش يدخل المستخدمين أو يعدل المنيو', async () => {
  assert.equal((await api('GET', '/users', null, 'kitchen1')).status, 403);
  assert.equal((await api('POST', '/menu/categories', { name: 'x' }, 'kitchen1')).status, 403);
  assert.equal((await api('GET', '/dashboard', null, 'kitchen1')).status, 403);
});

test('دورة الطلب كاملة + الإرسال اللحظي للفرع', async () => {
  const menu = (await api('GET', '/menu')).data;
  const branches = (await api('GET', '/branches')).data;
  const [item1, item2] = menu.items;

  // اتصال لحظي لمطبخ الفرع 1 و 2
  const connect = (who) => new Promise((resolve, reject) => {
    const s = io(BASE, { auth: { token: tokens[who] }, transports: ['websocket'] });
    s.on('connect', () => resolve(s)); s.on('connect_error', reject);
  });
  const k1 = await connect('kitchen1');
  const k2 = await connect('kitchen2');
  let k2Got = false;
  k2.on('order:new', () => { k2Got = true; });
  const gotNew = new Promise((resolve) => k1.once('order:new', resolve));

  const r = await api('POST', '/orders', {
    branch_id: branches[0].id, type: 'delivery', payment_method: 'cash', discount: 5,
    customer: { name: 'محمد علي', phone: '01011112222' },
    address: { area: 'المعادي', address: 'شارع 9 عمارة 5', landmark: 'جنب البنك' },
    items: [{ item_id: item1.id, qty: 2 }, { item_id: item2.id, qty: 1, notes: 'من غير بصل' }],
    // السعر من الواجهة لازم يتجاهل
    price: 1,
  }, 'callcenter');
  assert.equal(r.status, 201, JSON.stringify(r.data));
  const o = r.data;
  const expectedSub = item1.price * 2 + item2.price;
  assert.equal(o.subtotal, expectedSub);
  assert.equal(o.delivery_fee, branches[0].delivery_fee);
  assert.equal(o.total, expectedSub + branches[0].delivery_fee - 5);
  assert.equal(o.status, 'new');
  assert.match(o.order_no, /^\d{6}-\d{3}$/);

  const pushed = await gotNew;
  assert.equal(pushed.id, o.id);
  await new Promise((res) => setTimeout(res, 150));
  assert.equal(k2Got, false, 'فرع تاني مايوصلوش الطلب');

  // مطبخ فرع 2 مايشوفش الطلب
  assert.equal((await api('GET', `/orders/${o.id}`, null, 'kitchen2')).status, 404);

  // العميل اتسجل بالعنوان
  const c = (await api('GET', '/customers/lookup?phone=01011112222', null, 'callcenter')).data;
  assert.equal(c.name, 'محمد علي');
  assert.equal(c.addresses.length, 1);

  // تحديث الحالة من المطبخ
  const gotUpdate = new Promise((resolve) => k1.once('order:updated', resolve));
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'accepted' }, 'kitchen1')).status, 200);
  assert.equal((await gotUpdate).status, 'accepted');
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'new' }, 'kitchen1')).status, 403, 'مينفعش يرجع لورا');
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'cancelled', note: 'x' }, 'kitchen1')).status, 403, 'المطبخ مايلغيش');
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'ready' }, 'kitchen1')).status, 200);

  // الطيار
  const drivers = (await api('GET', '/users/drivers', null, 'manager1')).data;
  assert.ok(drivers.length >= 1);
  assert.equal((await api('GET', `/orders/${o.id}`, null, 'driver1')).status, 404, 'الطيار مايشوفش طلب مش بتاعه');
  assert.equal((await api('PATCH', `/orders/${o.id}/driver`, { driver_id: drivers[0].id }, 'manager1')).status, 200);
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'out_for_delivery' }, 'driver1')).status, 200);
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'delivered' }, 'driver1')).status, 200);
  const done = (await api('GET', `/orders/${o.id}`)).data;
  assert.equal(done.status, 'delivered');
  assert.ok(done.history.length >= 5);

  // صفحة متابعة العميل
  const tr = await fetch(`${BASE}/api/public/track/${done.track_token}`).then((x) => x.json());
  assert.equal(tr.status, 'delivered');
  assert.equal(tr.customer_phone, undefined, 'رابط المتابعة مايكشفش الموبايل');

  k1.close(); k2.close();
});

test('تحويل طلب لفرع تاني', async () => {
  const menu = (await api('GET', '/menu')).data;
  const branches = (await api('GET', '/branches')).data;
  const o = (await api('POST', '/orders', {
    branch_id: branches[0].id, type: 'pickup', customer: { name: 'سارة', phone: '01233334444' },
    items: [{ item_id: menu.items[0].id, qty: 1 }],
  }, 'callcenter')).data;
  assert.equal(o.delivery_fee, 0);
  const t = await api('PATCH', `/orders/${o.id}/branch`, { branch_id: branches[1].id }, 'callcenter');
  assert.equal(t.status, 200);
  assert.equal(t.data.branch_id, branches[1].id);
  assert.equal((await api('GET', `/orders/${o.id}`, null, 'kitchen2')).status, 200);
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'cancelled' }, 'callcenter')).status, 400, 'الإلغاء محتاج سبب');
  assert.equal((await api('PATCH', `/orders/${o.id}/status`, { status: 'cancelled', note: 'العميل لغى' }, 'callcenter')).status, 200);
});

test('صنف غير متاح مايتطلبش', async () => {
  const menu = (await api('GET', '/menu')).data;
  const it = menu.items[2];
  await api('PATCH', `/menu/items/${it.id}/availability`, { is_available: false });
  const r = await api('POST', '/orders', { branch_id: 1, type: 'pickup', customer: { name: 'x', phone: '0100000000' }, items: [{ item_id: it.id, qty: 1 }] }, 'callcenter');
  assert.equal(r.status, 400);
  await api('PATCH', `/menu/items/${it.id}/availability`, { is_available: true });
});

test('إدارة المنيو والفروع والمستخدمين والأدوار', async () => {
  const cat = await api('POST', '/menu/categories', { name: 'عروض' });
  assert.equal(cat.status, 201);
  const item = await api('POST', '/menu/items', { category_id: cat.data.id, name: 'عرض العيلة', price: 450 });
  assert.equal(item.status, 201);
  assert.equal((await api('PUT', `/menu/items/${item.data.id}`, { ...item.data, price: 420 })).data.price, 420);

  const br = await api('POST', '/branches', { name: 'فرع الشيخ زايد', delivery_fee: 25 });
  assert.equal(br.status, 201);

  const role = await api('POST', '/roles', { name: 'كاشير', permissions: ['orders.create', 'orders.view_branch', 'fake.perm'] });
  assert.equal(role.status, 201);
  assert.deepEqual(role.data.permissions, ['orders.create', 'orders.view_branch']);

  const u = await api('POST', '/users', { name: 'كاشير زايد', username: 'cashier3', password: '123456', role_id: role.data.id, branch_id: br.data.id });
  assert.equal(u.status, 201);
  assert.equal((await api('POST', '/users', { name: 'x', username: 'cashier3', password: '123456', role_id: role.data.id })).status, 400, 'اسم مستخدم مكرر');

  // الكاشير يسجل طلب بيروح لفرعه حتى لو بعت فرع تاني
  const login = await api('POST', '/auth/login', { username: 'cashier3', password: '123456' }, null);
  tokens.cashier3 = login.data.token;
  const o = await api('POST', '/orders', { branch_id: 1, type: 'dine_in', customer: { name: 'زبون صالة', phone: '01500000000' }, items: [{ item_id: item.data.id, qty: 1 }] }, 'cashier3');
  assert.equal(o.status, 201);
  assert.equal(o.data.branch_id, br.data.id);
});

test('لوحة التحكم', async () => {
  const d = (await api('GET', '/dashboard')).data;
  assert.ok(d.summary.orders >= 2);
  assert.ok(d.summary.revenue > 0);
  assert.ok(d.topItems.length > 0);
  // مدير الفرع يشوف فرعه بس
  const m = (await api('GET', '/dashboard?branch_id=2', null, 'manager1')).data;
  assert.equal(m.branch_id, 1);
});
