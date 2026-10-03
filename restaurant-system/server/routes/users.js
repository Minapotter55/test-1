const express = require('express');
const bcrypt = require('bcryptjs');
const { get, all, run } = require('../db');
const { requirePerm, can } = require('../auth');
const { str, num, bool, idParam, bad, notFound } = require('../util');

const router = express.Router();

const SELECT = `
  SELECT u.id, u.name, u.username, u.phone, u.role_id, u.branch_id, u.is_active, u.last_login, u.created_at,
         r.name AS role_name, r.key AS role_key, b.name AS branch_name
  FROM users u JOIN roles r ON r.id = u.role_id LEFT JOIN branches b ON b.id = u.branch_id`;

// الطيارين (للي بيعين طيار للطلب)
router.get('/drivers', requirePerm('orders.assign_driver', 'users.manage'), (req, res) => {
  const rows = all(`${SELECT} WHERE u.is_active = 1 ORDER BY u.name`);
  const roles = all('SELECT id, key, permissions FROM roles');
  // المدير العام معاه كل الصلاحيات بس مش طيار
  const driverRoles = new Set(roles.filter((r) => r.key !== 'admin' && JSON.parse(r.permissions).includes('orders.delivery')).map((r) => r.id));
  let drivers = rows.filter((u) => driverRoles.has(u.role_id));
  // مدير الفرع يشوف طيارين فرعه + الطيارين اللي مش تابعين لفرع
  if (!can(req.user, 'orders.view_all') && req.user.branch_id) {
    drivers = drivers.filter((d) => !d.branch_id || d.branch_id === req.user.branch_id);
  }
  res.json(drivers.map(({ id, name, phone, branch_id, branch_name }) => ({ id, name, phone, branch_id, branch_name })));
});

router.use(requirePerm('users.manage'));

router.get('/', (req, res) => {
  res.json(all(`${SELECT} ORDER BY u.is_active DESC, u.name`));
});

function readBody(body, isNew) {
  const data = {
    name: str(body.name, 'الاسم', { required: true, max: 100 }),
    username: str(body.username, 'اسم المستخدم', { required: true, max: 50 }),
    phone: str(body.phone, 'الموبايل', { max: 30 }),
    role_id: num(body.role_id, 'الدور', { required: true, int: true, min: 1 }),
    branch_id: body.branch_id ? num(body.branch_id, 'الفرع', { int: true, min: 1 }) : null,
    is_active: bool(body.is_active, true),
    password: str(body.password, 'كلمة المرور', { required: isNew, max: 100 }),
  };
  if (!/^[a-zA-Z0-9_.-]{3,50}$/.test(data.username)) throw bad('اسم المستخدم لازم يكون إنجليزي وأرقام (3 حروف على الأقل)');
  if (data.password && data.password.length < 6) throw bad('كلمة المرور لازم تكون 6 حروف على الأقل');
  if (!get('SELECT id FROM roles WHERE id = ?', data.role_id)) throw bad('الدور غير موجود');
  if (data.branch_id && !get('SELECT id FROM branches WHERE id = ?', data.branch_id)) throw bad('الفرع غير موجود');
  return data;
}

function ensureUniqueUsername(username, exceptId = 0) {
  if (get('SELECT id FROM users WHERE username = ? AND id != ?', username, exceptId)) throw bad('اسم المستخدم ده مستخدم قبل كده');
}

router.post('/', (req, res) => {
  const d = readBody(req.body, true);
  ensureUniqueUsername(d.username);
  const r = run('INSERT INTO users(name, username, password_hash, role_id, branch_id, phone, is_active) VALUES(?,?,?,?,?,?,?)',
    d.name, d.username, bcrypt.hashSync(d.password, 10), d.role_id, d.branch_id, d.phone, d.is_active);
  res.status(201).json(get(`${SELECT} WHERE u.id = ?`, Number(r.lastInsertRowid)));
});

router.put('/:id', (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM users WHERE id = ?', id)) throw notFound('المستخدم غير موجود');
  const d = readBody(req.body, false);
  ensureUniqueUsername(d.username, id);
  if (id === req.user.id) {
    if (!d.is_active) throw bad('مينفعش توقف حسابك');
    if (d.role_id !== req.user.role_id) throw bad('مينفعش تغير الدور بتاعك بنفسك');
  }
  run('UPDATE users SET name=?, username=?, role_id=?, branch_id=?, phone=?, is_active=? WHERE id=?',
    d.name, d.username, d.role_id, d.branch_id, d.phone, d.is_active, id);
  if (d.password) run('UPDATE users SET password_hash = ? WHERE id = ?', bcrypt.hashSync(d.password, 10), id);
  res.json(get(`${SELECT} WHERE u.id = ?`, id));
});

router.delete('/:id', (req, res) => {
  const id = idParam(req);
  if (id === req.user.id) throw bad('مينفعش تمسح حسابك');
  if (!get('SELECT id FROM users WHERE id = ?', id)) throw notFound('المستخدم غير موجود');
  const used = get('SELECT 1 FROM orders WHERE created_by = ? OR driver_id = ? LIMIT 1', id, id);
  if (used) {
    run('UPDATE users SET is_active = 0 WHERE id = ?', id);
    return res.json({ ok: true, deactivated: true, message: 'المستخدم ليه طلبات مسجلة، فتم إيقافه بدل المسح' });
  }
  run('DELETE FROM users WHERE id = ?', id);
  res.json({ ok: true });
});

module.exports = router;
