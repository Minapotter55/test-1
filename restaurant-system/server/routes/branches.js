const express = require('express');
const { get, all, run } = require('../db');
const { requirePerm, can } = require('../auth');
const { str, num, bool, idParam, notFound } = require('../util');
const realtime = require('../realtime');

const router = express.Router();

router.get('/', (req, res) => {
  const showAll = can(req.user, 'branches.manage');
  const rows = all(`
    SELECT b.*,
      (SELECT COUNT(*) FROM orders o WHERE o.branch_id = b.id AND o.status NOT IN ('delivered','cancelled')) AS active_orders,
      (SELECT COUNT(*) FROM users u WHERE u.branch_id = b.id) AS users_count
    FROM branches b ${showAll ? '' : 'WHERE b.is_active = 1'} ORDER BY b.id`);
  res.json(rows);
});

function readBody(body) {
  return {
    name: str(body.name, 'اسم الفرع', { required: true, max: 100 }),
    address: str(body.address, 'العنوان', { max: 300 }),
    phone: str(body.phone, 'التليفون', { max: 50 }),
    delivery_fee: num(body.delivery_fee, 'مصاريف التوصيل', { min: 0, max: 100000 }),
    is_active: bool(body.is_active, true),
  };
}

router.post('/', requirePerm('branches.manage'), (req, res) => {
  const d = readBody(req.body);
  const r = run('INSERT INTO branches(name, address, phone, delivery_fee, is_active) VALUES(?,?,?,?,?)',
    d.name, d.address, d.phone, d.delivery_fee, d.is_active);
  realtime.emitAll('branches:changed', {});
  res.status(201).json(get('SELECT * FROM branches WHERE id = ?', Number(r.lastInsertRowid)));
});

router.put('/:id', requirePerm('branches.manage'), (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM branches WHERE id = ?', id)) throw notFound('الفرع غير موجود');
  const d = readBody(req.body);
  run('UPDATE branches SET name=?, address=?, phone=?, delivery_fee=?, is_active=? WHERE id=?',
    d.name, d.address, d.phone, d.delivery_fee, d.is_active, id);
  realtime.emitAll('branches:changed', {});
  res.json(get('SELECT * FROM branches WHERE id = ?', id));
});

router.delete('/:id', requirePerm('branches.manage'), (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM branches WHERE id = ?', id)) throw notFound('الفرع غير موجود');
  if (get('SELECT 1 FROM orders WHERE branch_id = ? LIMIT 1', id)) {
    run('UPDATE branches SET is_active = 0 WHERE id = ?', id);
    realtime.emitAll('branches:changed', {});
    return res.json({ ok: true, deactivated: true, message: 'الفرع عليه طلبات مسجلة، فتم إيقافه بدل المسح' });
  }
  run('DELETE FROM branches WHERE id = ?', id);
  realtime.emitAll('branches:changed', {});
  res.json({ ok: true });
});

module.exports = router;
