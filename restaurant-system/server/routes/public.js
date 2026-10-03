// روابط عامة بدون تسجيل دخول (متابعة الطلب للعميل)
const express = require('express');
const { get, all } = require('../db');
const { readSettings } = require('./settings');
const { STATUS_LABELS, ORDER_TYPES } = require('../constants');
const { notFound } = require('../util');

const router = express.Router();

router.get('/info', (req, res) => {
  const s = readSettings();
  res.json({ restaurant_name: s.restaurant_name, currency: s.currency, restaurant_phone: s.restaurant_phone });
});

router.get('/track/:token', (req, res) => {
  const token = String(req.params.token || '');
  if (!/^[a-f0-9]{24}$/.test(token)) throw notFound('الطلب غير موجود');
  const o = get(`SELECT o.id, o.order_no, o.status, o.type, o.total, o.subtotal, o.delivery_fee, o.discount,
      o.customer_name, o.created_at, b.name AS branch_name, b.phone AS branch_phone, d.name AS driver_name
    FROM orders o JOIN branches b ON b.id = o.branch_id LEFT JOIN users d ON d.id = o.driver_id
    WHERE o.track_token = ?`, token);
  if (!o) throw notFound('الطلب غير موجود');
  o.items = all('SELECT name, qty, line_total FROM order_items WHERE order_id = ?', o.id);
  o.history = all(`SELECT status, MIN(created_at) AS created_at FROM order_status_history WHERE order_id = ? GROUP BY status ORDER BY MIN(id)`, o.id);
  delete o.id;
  res.json({ ...o, status_label: STATUS_LABELS[o.status], type_label: ORDER_TYPES[o.type], ...readSettings() });
});

module.exports = router;
