const express = require('express');
const { get, all, run } = require('../db');
const { requirePerm } = require('../auth');
const { PERMISSIONS, ALL_PERMISSIONS } = require('../constants');
const { str, idParam, bad, notFound } = require('../util');

const router = express.Router();
router.use(requirePerm('users.manage'));

const shape = (r) => ({ ...r, permissions: JSON.parse(r.permissions) });

router.get('/', (req, res) => {
  const roles = all(`SELECT r.*, (SELECT COUNT(*) FROM users u WHERE u.role_id = r.id) AS users_count FROM roles r ORDER BY r.id`);
  res.json({ roles: roles.map(shape), permissions: PERMISSIONS });
});

function readBody(body) {
  const name = str(body.name, 'اسم الدور', { required: true, max: 60 });
  const perms = Array.isArray(body.permissions) ? body.permissions.filter((p) => ALL_PERMISSIONS.includes(p)) : [];
  return { name, permissions: [...new Set(perms)] };
}

router.post('/', (req, res) => {
  const d = readBody(req.body);
  const r = run('INSERT INTO roles(name, permissions) VALUES(?, ?)', d.name, JSON.stringify(d.permissions));
  res.status(201).json(shape(get('SELECT * FROM roles WHERE id = ?', Number(r.lastInsertRowid))));
});

router.put('/:id', (req, res) => {
  const id = idParam(req);
  const role = get('SELECT * FROM roles WHERE id = ?', id);
  if (!role) throw notFound('الدور غير موجود');
  const d = readBody(req.body);
  // المدير العام دايماً معاه كل الصلاحيات
  const perms = role.key === 'admin' ? ALL_PERMISSIONS : d.permissions;
  run('UPDATE roles SET name = ?, permissions = ? WHERE id = ?', d.name, JSON.stringify(perms), id);
  res.json(shape(get('SELECT * FROM roles WHERE id = ?', id)));
});

router.delete('/:id', (req, res) => {
  const id = idParam(req);
  const role = get('SELECT * FROM roles WHERE id = ?', id);
  if (!role) throw notFound('الدور غير موجود');
  if (role.is_system) throw bad('مينفعش تمسح الدور ده');
  if (get('SELECT 1 FROM users WHERE role_id = ? LIMIT 1', id)) throw bad('في مستخدمين على الدور ده، غيّر دورهم الأول');
  run('DELETE FROM roles WHERE id = ?', id);
  res.json({ ok: true });
});

module.exports = router;
