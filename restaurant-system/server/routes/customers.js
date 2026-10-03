const express = require('express');
const { get, all, run } = require('../db');
const { requirePerm } = require('../auth');
const { str, num, idParam, bad, notFound } = require('../util');

const router = express.Router();

const normalizePhone = (p) => String(p || '').replace(/[^\d+]/g, '');

function readAddress(body) {
  return {
    label: str(body.label, 'اسم العنوان', { max: 50 }),
    area: str(body.area, 'المنطقة', { max: 100 }),
    address: str(body.address, 'العنوان', { required: true, max: 400 }),
    landmark: str(body.landmark, 'علامة مميزة', { max: 200 }),
  };
}

function customerDetails(id) {
  const customer = get('SELECT * FROM customers WHERE id = ?', id);
  if (!customer) return null;
  customer.addresses = all('SELECT * FROM customer_addresses WHERE customer_id = ? ORDER BY id DESC', id);
  customer.orders = all(`SELECT o.id, o.order_no, o.status, o.total, o.type, o.created_at, b.name AS branch_name
    FROM orders o JOIN branches b ON b.id = o.branch_id WHERE o.customer_id = ? ORDER BY o.id DESC LIMIT 50`, id);
  customer.stats = get(`SELECT COUNT(*) AS orders_count, COALESCE(SUM(total),0) AS total_spent, MAX(created_at) AS last_order
    FROM orders WHERE customer_id = ? AND status != 'cancelled'`, id);
  return customer;
}

// البحث برقم التليفون وقت تسجيل الطلب
router.get('/lookup', requirePerm('orders.create', 'customers.view'), (req, res) => {
  const phone = normalizePhone(req.query.phone);
  if (phone.length < 3) return res.json(null);
  const row = get('SELECT id FROM customers WHERE phone = ? OR phone2 = ?', phone, phone);
  res.json(row ? customerDetails(row.id) : null);
});

router.get('/', requirePerm('customers.view', 'orders.create'), (req, res) => {
  const q = str(req.query.q, 'بحث', { max: 100 });
  const limit = num(req.query.limit, 'limit', { int: true, min: 1, max: 500, def: 100 });
  const offset = num(req.query.offset, 'offset', { int: true, min: 0, def: 0 });
  const where = q ? 'WHERE c.name LIKE ? OR c.phone LIKE ? OR c.phone2 LIKE ?' : '';
  const params = q ? [`%${q}%`, `%${q}%`, `%${q}%`] : [];
  const rows = all(`
    SELECT c.*,
      (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.id AND o.status != 'cancelled') AS orders_count,
      (SELECT COALESCE(SUM(total),0) FROM orders o WHERE o.customer_id = c.id AND o.status != 'cancelled') AS total_spent,
      (SELECT MAX(created_at) FROM orders o WHERE o.customer_id = c.id) AS last_order
    FROM customers c ${where} ORDER BY c.id DESC LIMIT ? OFFSET ?`, ...params, limit, offset);
  const total = get(`SELECT COUNT(*) AS c FROM customers c ${where}`, ...params).c;
  res.json({ rows, total });
});

router.get('/:id', requirePerm('customers.view', 'orders.create'), (req, res) => {
  const c = customerDetails(idParam(req));
  if (!c) throw notFound('العميل غير موجود');
  res.json(c);
});

function readCustomer(body) {
  const d = {
    name: str(body.name, 'اسم العميل', { required: true, max: 100 }),
    phone: normalizePhone(str(body.phone, 'رقم الموبايل', { required: true, max: 30 })),
    phone2: normalizePhone(str(body.phone2, 'رقم تاني', { max: 30 })),
    notes: str(body.notes, 'ملاحظات', { max: 500 }),
  };
  if (d.phone.length < 5) throw bad('رقم الموبايل غير صحيح');
  return d;
}

router.post('/', requirePerm('customers.manage', 'orders.create'), (req, res) => {
  const d = readCustomer(req.body);
  if (get('SELECT id FROM customers WHERE phone = ?', d.phone)) throw bad('في عميل مسجل بنفس الرقم');
  const r = run('INSERT INTO customers(name, phone, phone2, notes) VALUES(?,?,?,?)', d.name, d.phone, d.phone2, d.notes);
  const id = Number(r.lastInsertRowid);
  if (req.body.address && req.body.address.address) {
    const a = readAddress(req.body.address);
    run('INSERT INTO customer_addresses(customer_id, label, area, address, landmark) VALUES(?,?,?,?,?)', id, a.label, a.area, a.address, a.landmark);
  }
  res.status(201).json(customerDetails(id));
});

router.put('/:id', requirePerm('customers.manage'), (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM customers WHERE id = ?', id)) throw notFound('العميل غير موجود');
  const d = readCustomer(req.body);
  if (get('SELECT id FROM customers WHERE phone = ? AND id != ?', d.phone, id)) throw bad('في عميل تاني مسجل بنفس الرقم');
  run('UPDATE customers SET name=?, phone=?, phone2=?, notes=? WHERE id=?', d.name, d.phone, d.phone2, d.notes, id);
  res.json(customerDetails(id));
});

router.delete('/:id', requirePerm('customers.manage'), (req, res) => {
  const id = idParam(req);
  run('DELETE FROM customers WHERE id = ?', id);
  res.json({ ok: true });
});

// ---------- العناوين ----------
router.post('/:id/addresses', requirePerm('customers.manage', 'orders.create'), (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM customers WHERE id = ?', id)) throw notFound('العميل غير موجود');
  const a = readAddress(req.body);
  const r = run('INSERT INTO customer_addresses(customer_id, label, area, address, landmark) VALUES(?,?,?,?,?)', id, a.label, a.area, a.address, a.landmark);
  res.status(201).json(get('SELECT * FROM customer_addresses WHERE id = ?', Number(r.lastInsertRowid)));
});

router.put('/addresses/:aid', requirePerm('customers.manage'), (req, res) => {
  const aid = idParam(req, 'aid');
  if (!get('SELECT id FROM customer_addresses WHERE id = ?', aid)) throw notFound('العنوان غير موجود');
  const a = readAddress(req.body);
  run('UPDATE customer_addresses SET label=?, area=?, address=?, landmark=? WHERE id=?', a.label, a.area, a.address, a.landmark, aid);
  res.json(get('SELECT * FROM customer_addresses WHERE id = ?', aid));
});

router.delete('/addresses/:aid', requirePerm('customers.manage'), (req, res) => {
  run('DELETE FROM customer_addresses WHERE id = ?', idParam(req, 'aid'));
  res.json({ ok: true });
});

module.exports = { router, normalizePhone, readAddress };
