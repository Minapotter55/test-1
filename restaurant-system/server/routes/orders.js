const crypto = require('crypto');
const express = require('express');
const { get, all, run, tx } = require('../db');
const { requirePerm, can } = require('../auth');
const { STATUSES, FINAL_STATUSES, ACTIVE_STATUSES, ORDER_TYPES, PAYMENT_METHODS } = require('../constants');
const { str, num, idParam, bad, notFound, forbidden, round2 } = require('../util');
const { normalizePhone, readAddress } = require('./customers');
const realtime = require('../realtime');

const router = express.Router();

const SELECT = `
  SELECT o.*, b.name AS branch_name, b.phone AS branch_phone,
         d.name AS driver_name, d.phone AS driver_phone, cu.name AS created_by_name,
         (SELECT COALESCE(SUM(qty),0) FROM order_items oi WHERE oi.order_id = o.id) AS items_count
  FROM orders o
  JOIN branches b ON b.id = o.branch_id
  LEFT JOIN users d ON d.id = o.driver_id
  LEFT JOIN users cu ON cu.id = o.created_by`;

// تحديد الطلبات اللي المستخدم يقدر يشوفها
function scope(user) {
  if (can(user, 'orders.view_all')) return { sql: '1=1', params: [] };
  const parts = [];
  const params = [];
  if (can(user, 'orders.view_branch') && user.branch_id) { parts.push('o.branch_id = ?'); params.push(user.branch_id); }
  if (can(user, 'orders.delivery')) { parts.push('o.driver_id = ?'); params.push(user.id); }
  if (can(user, 'orders.create')) { parts.push('o.created_by = ?'); params.push(user.id); }
  if (!parts.length) return { sql: '0=1', params: [] };
  return { sql: `(${parts.join(' OR ')})`, params };
}

function loadOrder(id) {
  return get(`${SELECT} WHERE o.id = ?`, id);
}

function loadOrderFull(id) {
  const order = loadOrder(id);
  if (!order) return null;
  order.items = all('SELECT * FROM order_items WHERE order_id = ? ORDER BY id', id);
  order.history = all(`SELECT h.*, u.name AS user_name FROM order_status_history h
    LEFT JOIN users u ON u.id = h.user_id WHERE h.order_id = ? ORDER BY h.id`, id);
  return order;
}

function getVisibleOrder(req) {
  const id = idParam(req);
  const s = scope(req.user);
  const row = get(`SELECT o.id FROM orders o WHERE o.id = ? AND ${s.sql}`, id, ...s.params);
  if (!row) throw notFound('الطلب غير موجود');
  return loadOrderFull(id);
}

// ---------- قائمة الطلبات ----------
router.get('/', (req, res) => {
  const s = scope(req.user);
  const where = [s.sql];
  const params = [...s.params];

  if (req.query.active === '1') {
    where.push(`o.status IN (${ACTIVE_STATUSES.map(() => '?').join(',')})`);
    params.push(...ACTIVE_STATUSES);
  }
  if (req.query.status) {
    const list = String(req.query.status).split(',').filter((x) => STATUSES.includes(x));
    if (list.length) { where.push(`o.status IN (${list.map(() => '?').join(',')})`); params.push(...list); }
  }
  if (req.query.branch_id) { where.push('o.branch_id = ?'); params.push(num(req.query.branch_id, 'الفرع', { int: true })); }
  if (req.query.type && ORDER_TYPES[req.query.type]) { where.push('o.type = ?'); params.push(req.query.type); }
  if (req.query.from) { where.push('date(o.created_at) >= date(?)'); params.push(str(req.query.from, 'من', { max: 20 })); }
  if (req.query.to) { where.push('date(o.created_at) <= date(?)'); params.push(str(req.query.to, 'إلى', { max: 20 })); }
  if (req.query.mine === '1') { where.push('o.driver_id = ?'); params.push(req.user.id); }
  const q = str(req.query.q, 'بحث', { max: 100 });
  if (q) {
    where.push('(o.order_no LIKE ? OR o.customer_phone LIKE ? OR o.customer_name LIKE ?)');
    params.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }

  const limit = num(req.query.limit, 'limit', { int: true, min: 1, max: 1000, def: 200 });
  const offset = num(req.query.offset, 'offset', { int: true, min: 0, def: 0 });
  const whereSql = where.join(' AND ');
  const rows = all(`${SELECT} WHERE ${whereSql} ORDER BY o.id DESC LIMIT ? OFFSET ?`, ...params, limit, offset);
  const total = get(`SELECT COUNT(*) AS c FROM orders o WHERE ${whereSql}`, ...params).c;
  res.json({ rows, total });
});

router.get('/:id', (req, res) => {
  res.json(getVisibleOrder(req));
});

// ---------- تسجيل طلب جديد ----------
function nextOrderNo() {
  const today = get("SELECT substr(strftime('%Y%m%d', 'now', 'localtime'), 3) AS d").d;
  const last = get('SELECT order_no FROM orders WHERE order_no LIKE ? ORDER BY id DESC LIMIT 1', `${today}-%`);
  const n = last ? Number(last.order_no.split('-')[1]) + 1 : 1;
  return `${today}-${String(n).padStart(3, '0')}`;
}

router.post('/', requirePerm('orders.create'), (req, res) => {
  const b = req.body || {};
  const type = ORDER_TYPES[b.type] ? b.type : 'delivery';
  const payment = PAYMENT_METHODS[b.payment_method] ? b.payment_method : 'cash';

  // الفرع: لو المستخدم تابع لفرع ومعندوش صلاحية كل الفروع، الطلب يروح لفرعه
  let branchId = num(b.branch_id, 'الفرع', { int: true, min: 1, def: 0 });
  if (!can(req.user, 'orders.view_all') && req.user.branch_id) branchId = req.user.branch_id;
  if (!branchId) throw bad('اختار الفرع');
  const branch = get('SELECT * FROM branches WHERE id = ? AND is_active = 1', branchId);
  if (!branch) throw bad('الفرع غير موجود أو موقوف');

  // العميل
  const c = b.customer || {};
  const customerName = str(c.name, 'اسم العميل', { required: true, max: 100 });
  const customerPhone = normalizePhone(str(c.phone, 'رقم الموبايل', { required: true, max: 30 }));
  if (customerPhone.length < 5) throw bad('رقم الموبايل غير صحيح');

  // الأصناف - الأسعار بتتحسب من السيرفر مش من الواجهة
  if (!Array.isArray(b.items) || !b.items.length) throw bad('الطلب لازم يكون فيه صنف واحد على الأقل');
  if (b.items.length > 100) throw bad('عدد الأصناف كبير جداً');
  const lines = b.items.map((it) => {
    const itemId = num(it.item_id, 'الصنف', { required: true, int: true, min: 1 });
    const qty = num(it.qty, 'الكمية', { required: true, int: true, min: 1, max: 999 });
    const item = get('SELECT * FROM menu_items WHERE id = ?', itemId);
    if (!item) throw bad('في صنف مش موجود في المنيو');
    if (!item.is_available) throw bad(`الصنف "${item.name}" مش متاح حالياً`);
    return { item_id: item.id, name: item.name, price: item.price, qty, notes: str(it.notes, 'ملاحظات الصنف', { max: 200 }), line_total: round2(item.price * qty) };
  });

  const subtotal = round2(lines.reduce((s, l) => s + l.line_total, 0));
  const deliveryFee = type === 'delivery'
    ? num(b.delivery_fee, 'مصاريف التوصيل', { min: 0, max: 100000, def: branch.delivery_fee })
    : 0;
  const discount = num(b.discount, 'الخصم', { min: 0, max: subtotal + deliveryFee });
  const total = round2(subtotal + deliveryFee - discount);
  const notes = str(b.notes, 'ملاحظات', { max: 500 });

  const orderId = tx(() => {
    // إنشاء أو تحديث العميل بالرقم
    let customer = get('SELECT * FROM customers WHERE phone = ?', customerPhone);
    if (customer) {
      if (customer.name !== customerName) run('UPDATE customers SET name = ? WHERE id = ?', customerName, customer.id);
    } else {
      const r = run('INSERT INTO customers(name, phone, phone2) VALUES(?,?,?)', customerName, customerPhone, normalizePhone(c.phone2));
      customer = { id: Number(r.lastInsertRowid) };
    }

    // العنوان
    let addressId = null;
    let addressText = '';
    if (type === 'delivery') {
      const a = b.address || {};
      if (a.id) {
        const addr = get('SELECT * FROM customer_addresses WHERE id = ? AND customer_id = ?', num(a.id, 'العنوان', { int: true }), customer.id);
        if (!addr) throw bad('العنوان غير موجود');
        addressId = addr.id;
        addressText = [addr.area, addr.address, addr.landmark && `(${addr.landmark})`].filter(Boolean).join(' - ');
      } else {
        if (!a.address) throw bad('عنوان التوصيل مطلوب');
        const addr = readAddress(a);
        addressId = Number(run('INSERT INTO customer_addresses(customer_id, label, area, address, landmark) VALUES(?,?,?,?,?)',
          customer.id, addr.label, addr.area, addr.address, addr.landmark).lastInsertRowid);
        addressText = [addr.area, addr.address, addr.landmark && `(${addr.landmark})`].filter(Boolean).join(' - ');
      }
    }

    const r = run(`INSERT INTO orders(order_no, track_token, branch_id, customer_id, customer_name, customer_phone,
        address_id, address_text, type, status, payment_method, subtotal, delivery_fee, discount, total, notes, created_by)
      VALUES(?,?,?,?,?,?,?,?,?,'new',?,?,?,?,?,?,?)`,
      nextOrderNo(), crypto.randomBytes(12).toString('hex'), branchId, customer.id, customerName, customerPhone,
      addressId, addressText, type, payment, subtotal, deliveryFee, discount, total, notes, req.user.id);
    const id = Number(r.lastInsertRowid);
    for (const l of lines) {
      run('INSERT INTO order_items(order_id, item_id, name, price, qty, notes, line_total) VALUES(?,?,?,?,?,?,?)',
        id, l.item_id, l.name, l.price, l.qty, l.notes, l.line_total);
    }
    run("INSERT INTO order_status_history(order_id, status, note, user_id) VALUES(?, 'new', ?, ?)", id, 'تم تسجيل الطلب', req.user.id);
    return id;
  });

  const order = loadOrderFull(orderId);
  realtime.emitOrder('order:new', order);
  res.status(201).json(order);
});

// ---------- تحديث حالة الطلب ----------
function canChangeStatus(user, order, status) {
  if (FINAL_STATUSES.includes(order.status) && !user.is_admin) return 'الطلب ده انتهى ومينفعش يتعدل';
  if (status === order.status) return 'الطلب بالفعل في الحالة دي';
  if (status === 'cancelled') return can(user, 'orders.cancel') ? null : 'مش مسموح لك تلغي طلبات';
  if (status === 'out_for_delivery' && order.type !== 'delivery') return 'الحالة دي لطلبات التوصيل بس';

  const forward = STATUSES.indexOf(status) > STATUSES.indexOf(order.status);
  if (can(user, 'orders.update_status')) {
    if (!forward && !user.is_admin) return 'مينفعش ترجّع الطلب لحالة قبل كده';
    return null;
  }
  // الطيار: يستلم الطلب ويسلمه بس للطلبات المسندة له
  if (can(user, 'orders.delivery') && order.driver_id === user.id && ['out_for_delivery', 'delivered'].includes(status) && forward) return null;
  return 'مش مسموح لك تغير حالة الطلب';
}

router.patch('/:id/status', (req, res) => {
  const order = getVisibleOrder(req);
  const status = str(req.body.status, 'الحالة', { required: true, max: 30 });
  if (!STATUSES.includes(status)) throw bad('حالة غير صحيحة');
  const err = canChangeStatus(req.user, order, status);
  if (err) throw forbidden(err);
  const note = str(req.body.note, 'ملاحظة', { max: 300 });
  if (status === 'cancelled' && !note) throw bad('اكتب سبب الإلغاء');

  tx(() => {
    run("UPDATE orders SET status = ?, updated_at = datetime('now','localtime') WHERE id = ?", status, order.id);
    run('INSERT INTO order_status_history(order_id, status, note, user_id) VALUES(?,?,?,?)', order.id, status, note, req.user.id);
  });
  const updated = loadOrderFull(order.id);
  realtime.emitOrder('order:updated', updated);
  res.json(updated);
});

// ---------- تعيين طيار ----------
router.patch('/:id/driver', requirePerm('orders.assign_driver'), (req, res) => {
  const order = getVisibleOrder(req);
  if (order.type !== 'delivery') throw bad('الطلب ده مش توصيل');
  if (FINAL_STATUSES.includes(order.status)) throw bad('الطلب ده انتهى');
  const driverId = req.body.driver_id ? num(req.body.driver_id, 'الطيار', { int: true, min: 1 }) : null;
  let driverName = '';
  if (driverId) {
    const d = get('SELECT u.id, u.name, r.key, r.permissions FROM users u JOIN roles r ON r.id = u.role_id WHERE u.id = ? AND u.is_active = 1', driverId);
    if (!d || d.key === 'admin' || !JSON.parse(d.permissions).includes('orders.delivery')) throw bad('المستخدم ده مش طيار');
    driverName = d.name;
  }
  const oldDriver = order.driver_id;
  tx(() => {
    run("UPDATE orders SET driver_id = ?, updated_at = datetime('now','localtime') WHERE id = ?", driverId, order.id);
    run('INSERT INTO order_status_history(order_id, status, note, user_id) VALUES(?,?,?,?)',
      order.id, order.status, driverId ? `تم تعيين الطيار: ${driverName}` : 'تم إلغاء تعيين الطيار', req.user.id);
  });
  const updated = loadOrderFull(order.id);
  realtime.emitOrder('order:updated', updated, oldDriver ? [`user:${oldDriver}`] : []);
  res.json(updated);
});

// ---------- تحويل الطلب لفرع تاني ----------
router.patch('/:id/branch', requirePerm('orders.transfer'), (req, res) => {
  const order = getVisibleOrder(req);
  if (FINAL_STATUSES.includes(order.status)) throw bad('الطلب ده انتهى');
  const branchId = num(req.body.branch_id, 'الفرع', { required: true, int: true, min: 1 });
  if (branchId === order.branch_id) throw bad('الطلب بالفعل في الفرع ده');
  const branch = get('SELECT * FROM branches WHERE id = ? AND is_active = 1', branchId);
  if (!branch) throw bad('الفرع غير موجود أو موقوف');
  const reason = str(req.body.note, 'السبب', { max: 300 });
  tx(() => {
    run("UPDATE orders SET branch_id = ?, status = 'new', driver_id = NULL, updated_at = datetime('now','localtime') WHERE id = ?", branchId, order.id);
    run("INSERT INTO order_status_history(order_id, status, note, user_id) VALUES(?, 'new', ?, ?)",
      order.id, `تم تحويل الطلب من ${order.branch_name} إلى ${branch.name}${reason ? ` - ${reason}` : ''}`, req.user.id);
  });
  const updated = loadOrderFull(order.id);
  // الفرع القديم يتشال منه الطلب، والفرع الجديد يوصله كطلب جديد
  realtime.emitOrder('order:updated', updated, [`branch:${order.branch_id}`]);
  realtime.emitOrder('order:new', updated);
  res.json(updated);
});

module.exports = { router, scope };
