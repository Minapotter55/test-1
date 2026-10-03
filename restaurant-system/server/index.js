const os = require('os');
const path = require('path');
const http = require('http');
const express = require('express');
const cors = require('cors');
const config = require('./config');
require('./db');
const realtime = require('./realtime');
const { authenticate } = require('./auth');
const C = require('./constants');

const app = express();
const server = http.createServer(app);
realtime.init(server);

app.disable('x-powered-by');
app.set('trust proxy', true);
app.use(cors());
app.use(express.json({ limit: '6mb' }));

// ---------- API ----------
app.use('/api/public', require('./routes/public'));
app.use('/api/auth', require('./routes/auth'));

app.use('/api', authenticate);
app.get('/api/meta', (req, res) => res.json({
  statuses: C.STATUSES, status_labels: C.STATUS_LABELS, active_statuses: C.ACTIVE_STATUSES,
  order_types: C.ORDER_TYPES, payment_methods: C.PAYMENT_METHODS, permissions: C.PERMISSIONS,
}));
app.use('/api/dashboard', require('./routes/dashboard'));
app.use('/api/orders', require('./routes/orders').router);
app.use('/api/customers', require('./routes/customers').router);
app.use('/api/menu', require('./routes/menu'));
app.use('/api/branches', require('./routes/branches'));
app.use('/api/users', require('./routes/users'));
app.use('/api/roles', require('./routes/roles'));
app.use('/api/settings', require('./routes/settings').router);

app.use('/api', (req, res) => res.status(404).json({ error: 'المسار غير موجود' }));

// ---------- الواجهة ----------
app.use('/uploads', express.static(path.join(config.DATA_DIR, 'uploads'), { maxAge: '30d' }));
app.use(express.static(config.PUBLIC_DIR, { index: 'index.html' }));

// ---------- الأخطاء ----------
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'البيانات المرسلة كبيرة جداً' });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'بيانات غير صحيحة' });
  const status = err.status || 500;
  if (status >= 500) console.error(err);
  res.status(status).json({ error: status >= 500 ? 'حصل خطأ في السيرفر' : err.message });
});

server.listen(config.PORT, config.HOST, () => {
  const ips = Object.values(os.networkInterfaces()).flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
  console.log('\n🍽️  سيستم إدارة طلبات المطعم شغال');
  console.log(`   على الكمبيوتر:   http://localhost:${config.PORT}`);
  for (const ip of ips) console.log(`   من الموبايل:     http://${ip}:${config.PORT}`);
  console.log('\n   أول دخول: admin / admin123  (غيّرها فوراً من الإعدادات)\n');
});

module.exports = { app, server };
