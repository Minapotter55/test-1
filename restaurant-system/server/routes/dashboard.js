const express = require('express');
const { get, all } = require('../db');
const { requirePerm, can } = require('../auth');
const { str, num } = require('../util');

const router = express.Router();
router.use(requirePerm('dashboard.view'));

router.get('/', (req, res) => {
  const today = get("SELECT date('now','localtime') AS d").d;
  const from = str(req.query.from, 'من', { max: 20 }) || today;
  const to = str(req.query.to, 'إلى', { max: 20 }) || today;

  const where = ['date(o.created_at) BETWEEN date(?) AND date(?)'];
  const params = [from, to];
  let branchId = req.query.branch_id ? num(req.query.branch_id, 'الفرع', { int: true }) : null;
  // مدير الفرع يشوف فرعه بس
  if (!can(req.user, 'orders.view_all')) branchId = req.user.branch_id || -1;
  if (branchId) { where.push('o.branch_id = ?'); params.push(branchId); }
  const w = where.join(' AND ');
  const notCancelled = `${w} AND o.status != 'cancelled'`;

  const summary = get(`SELECT COUNT(*) AS orders, COALESCE(SUM(o.total),0) AS revenue, COALESCE(AVG(o.total),0) AS avg_order,
      COALESCE(SUM(o.delivery_fee),0) AS delivery_fees, COALESCE(SUM(o.discount),0) AS discounts
    FROM orders o WHERE ${notCancelled}`, ...params);
  summary.cancelled = get(`SELECT COUNT(*) AS c FROM orders o WHERE ${w} AND o.status = 'cancelled'`, ...params).c;
  summary.new_customers = get(`SELECT COUNT(*) AS c FROM customers WHERE date(created_at) BETWEEN date(?) AND date(?)`, from, to).c;

  // الطلبات الشغالة دلوقتي (بغض النظر عن التاريخ)
  const activeWhere = branchId ? 'AND o.branch_id = ?' : '';
  const activeParams = branchId ? [branchId] : [];
  const active = all(`SELECT o.status, COUNT(*) AS count FROM orders o
    WHERE o.status NOT IN ('delivered','cancelled') ${activeWhere} GROUP BY o.status`, ...activeParams);

  const byStatus = all(`SELECT o.status, COUNT(*) AS count FROM orders o WHERE ${w} GROUP BY o.status`, ...params);
  const byType = all(`SELECT o.type, COUNT(*) AS count, COALESCE(SUM(o.total),0) AS revenue FROM orders o WHERE ${notCancelled} GROUP BY o.type`, ...params);
  const byPayment = all(`SELECT o.payment_method, COUNT(*) AS count, COALESCE(SUM(o.total),0) AS revenue FROM orders o WHERE ${notCancelled} GROUP BY o.payment_method`, ...params);
  const byBranch = all(`SELECT b.id, b.name, COUNT(o.id) AS orders, COALESCE(SUM(o.total),0) AS revenue
    FROM orders o JOIN branches b ON b.id = o.branch_id WHERE ${notCancelled} GROUP BY b.id ORDER BY revenue DESC`, ...params);
  const byDay = all(`SELECT date(o.created_at) AS day, COUNT(*) AS orders, COALESCE(SUM(o.total),0) AS revenue
    FROM orders o WHERE ${notCancelled} GROUP BY day ORDER BY day`, ...params);
  const byHour = all(`SELECT CAST(strftime('%H', o.created_at) AS INTEGER) AS hour, COUNT(*) AS orders
    FROM orders o WHERE ${notCancelled} GROUP BY hour ORDER BY hour`, ...params);
  const topItems = all(`SELECT oi.name, SUM(oi.qty) AS qty, SUM(oi.line_total) AS revenue
    FROM order_items oi JOIN orders o ON o.id = oi.order_id WHERE ${notCancelled}
    GROUP BY oi.name ORDER BY qty DESC LIMIT 10`, ...params);
  const topCustomers = all(`SELECT o.customer_name AS name, o.customer_phone AS phone, COUNT(*) AS orders, SUM(o.total) AS revenue
    FROM orders o WHERE ${notCancelled} GROUP BY o.customer_phone ORDER BY revenue DESC LIMIT 5`, ...params);

  // متوسط وقت التسليم بالدقايق
  const avgTime = get(`SELECT AVG((julianday(h.created_at) - julianday(o.created_at)) * 1440) AS minutes
    FROM orders o JOIN order_status_history h ON h.order_id = o.id AND h.status = 'delivered'
    WHERE ${w} AND o.status = 'delivered'`, ...params);
  summary.avg_delivery_minutes = avgTime.minutes ? Math.round(avgTime.minutes) : null;

  res.json({ from, to, branch_id: branchId, summary, active, byStatus, byType, byPayment, byBranch, byDay, byHour, topItems, topCustomers });
});

module.exports = router;
