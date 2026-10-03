const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const { get, all, run } = require('../db');
const { requirePerm } = require('../auth');
const { DATA_DIR } = require('../config');
const { str, num, bool, idParam, bad, notFound } = require('../util');
const realtime = require('../realtime');

const router = express.Router();
const UPLOADS = path.join(DATA_DIR, 'uploads');
fs.mkdirSync(UPLOADS, { recursive: true });

const changed = () => realtime.emitAll('menu:changed', {});

// المنيو كامل (أقسام + أصناف)
router.get('/', (req, res) => {
  res.json({
    categories: all('SELECT * FROM categories ORDER BY sort_order, id'),
    items: all(`SELECT i.*, c.name AS category_name FROM menu_items i JOIN categories c ON c.id = i.category_id
                ORDER BY c.sort_order, i.sort_order, i.id`),
  });
});

// ---------- الأقسام ----------
function readCategory(body) {
  return {
    name: str(body.name, 'اسم القسم', { required: true, max: 100 }),
    sort_order: num(body.sort_order, 'الترتيب', { int: true, min: 0, max: 10000 }),
    is_active: bool(body.is_active, true),
  };
}

router.post('/categories', requirePerm('menu.manage'), (req, res) => {
  const d = readCategory(req.body);
  const r = run('INSERT INTO categories(name, sort_order, is_active) VALUES(?,?,?)', d.name, d.sort_order, d.is_active);
  changed();
  res.status(201).json(get('SELECT * FROM categories WHERE id = ?', Number(r.lastInsertRowid)));
});

router.put('/categories/:id', requirePerm('menu.manage'), (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM categories WHERE id = ?', id)) throw notFound('القسم غير موجود');
  const d = readCategory(req.body);
  run('UPDATE categories SET name=?, sort_order=?, is_active=? WHERE id=?', d.name, d.sort_order, d.is_active, id);
  changed();
  res.json(get('SELECT * FROM categories WHERE id = ?', id));
});

router.delete('/categories/:id', requirePerm('menu.manage'), (req, res) => {
  const id = idParam(req);
  if (get('SELECT 1 FROM menu_items WHERE category_id = ? LIMIT 1', id)) throw bad('القسم فيه أصناف، امسحها أو انقلها الأول');
  run('DELETE FROM categories WHERE id = ?', id);
  changed();
  res.json({ ok: true });
});

// ---------- الأصناف ----------
// حفظ صورة مرفوعة كـ data URL
function saveImage(dataUrl) {
  const m = /^data:image\/(png|jpe?g|webp|gif);base64,(.+)$/.exec(dataUrl || '');
  if (!m) throw bad('صيغة الصورة غير مدعومة');
  const buf = Buffer.from(m[2], 'base64');
  if (buf.length > 3 * 1024 * 1024) throw bad('الصورة كبيرة (أقصى حجم 3 ميجا)');
  const name = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}.${m[1].replace('jpeg', 'jpg')}`;
  fs.writeFileSync(path.join(UPLOADS, name), buf);
  return `/uploads/${name}`;
}

function removeImage(url) {
  if (url && url.startsWith('/uploads/')) {
    const file = path.join(UPLOADS, path.basename(url));
    fs.rm(file, { force: true }, () => {});
  }
}

function readItem(body) {
  const d = {
    category_id: num(body.category_id, 'القسم', { required: true, int: true, min: 1 }),
    name: str(body.name, 'اسم الصنف', { required: true, max: 150 }),
    description: str(body.description, 'الوصف', { max: 500 }),
    price: num(body.price, 'السعر', { required: true, min: 0, max: 1000000 }),
    image_url: str(body.image_url, 'رابط الصورة', { max: 500 }),
    is_available: bool(body.is_available, true),
    sort_order: num(body.sort_order, 'الترتيب', { int: true, min: 0, max: 10000 }),
  };
  if (!get('SELECT id FROM categories WHERE id = ?', d.category_id)) throw bad('القسم غير موجود');
  if (body.image_data) d.image_url = saveImage(body.image_data);
  return d;
}

router.post('/items', requirePerm('menu.manage'), (req, res) => {
  const d = readItem(req.body);
  const r = run('INSERT INTO menu_items(category_id, name, description, price, image_url, is_available, sort_order) VALUES(?,?,?,?,?,?,?)',
    d.category_id, d.name, d.description, d.price, d.image_url, d.is_available, d.sort_order);
  changed();
  res.status(201).json(get('SELECT * FROM menu_items WHERE id = ?', Number(r.lastInsertRowid)));
});

router.put('/items/:id', requirePerm('menu.manage'), (req, res) => {
  const id = idParam(req);
  const old = get('SELECT * FROM menu_items WHERE id = ?', id);
  if (!old) throw notFound('الصنف غير موجود');
  const d = readItem(req.body);
  run('UPDATE menu_items SET category_id=?, name=?, description=?, price=?, image_url=?, is_available=?, sort_order=? WHERE id=?',
    d.category_id, d.name, d.description, d.price, d.image_url, d.is_available, d.sort_order, id);
  if (old.image_url !== d.image_url) removeImage(old.image_url);
  changed();
  res.json(get('SELECT * FROM menu_items WHERE id = ?', id));
});

router.patch('/items/:id/availability', requirePerm('menu.manage'), (req, res) => {
  const id = idParam(req);
  if (!get('SELECT id FROM menu_items WHERE id = ?', id)) throw notFound('الصنف غير موجود');
  run('UPDATE menu_items SET is_available = ? WHERE id = ?', bool(req.body.is_available), id);
  changed();
  res.json(get('SELECT * FROM menu_items WHERE id = ?', id));
});

router.delete('/items/:id', requirePerm('menu.manage'), (req, res) => {
  const id = idParam(req);
  const old = get('SELECT * FROM menu_items WHERE id = ?', id);
  if (!old) throw notFound('الصنف غير موجود');
  run('DELETE FROM menu_items WHERE id = ?', id);
  removeImage(old.image_url);
  changed();
  res.json({ ok: true });
});

module.exports = router;
