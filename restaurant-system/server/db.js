const { DatabaseSync } = require('node:sqlite');
const bcrypt = require('bcryptjs');
const { DB_FILE } = require('./config');
const { DEFAULT_ROLES, ALL_PERMISSIONS } = require('./constants');

const db = new DatabaseSync(DB_FILE);
db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');

db.exec(`
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS roles (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  key         TEXT UNIQUE,
  name        TEXT NOT NULL,
  permissions TEXT NOT NULL DEFAULT '[]',
  is_system   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS branches (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT NOT NULL,
  address      TEXT DEFAULT '',
  phone        TEXT DEFAULT '',
  delivery_fee REAL NOT NULL DEFAULT 0,
  is_active    INTEGER NOT NULL DEFAULT 1,
  created_at   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT NOT NULL,
  username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  role_id       INTEGER NOT NULL REFERENCES roles(id),
  branch_id     INTEGER REFERENCES branches(id) ON DELETE SET NULL,
  phone         TEXT DEFAULT '',
  is_active     INTEGER NOT NULL DEFAULT 1,
  last_login    TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS categories (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS menu_items (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  category_id  INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  description  TEXT DEFAULT '',
  price        REAL NOT NULL DEFAULT 0,
  image_url    TEXT DEFAULT '',
  is_available INTEGER NOT NULL DEFAULT 1,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS customers (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  phone      TEXT NOT NULL UNIQUE,
  phone2     TEXT DEFAULT '',
  notes      TEXT DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS customer_addresses (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  label       TEXT DEFAULT '',
  area        TEXT DEFAULT '',
  address     TEXT NOT NULL,
  landmark    TEXT DEFAULT '',
  created_at  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS orders (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  order_no       TEXT NOT NULL UNIQUE,
  track_token    TEXT NOT NULL UNIQUE,
  branch_id      INTEGER NOT NULL REFERENCES branches(id),
  customer_id    INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  customer_name  TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  address_id     INTEGER REFERENCES customer_addresses(id) ON DELETE SET NULL,
  address_text   TEXT DEFAULT '',
  type           TEXT NOT NULL DEFAULT 'delivery',
  status         TEXT NOT NULL DEFAULT 'new',
  payment_method TEXT NOT NULL DEFAULT 'cash',
  subtotal       REAL NOT NULL DEFAULT 0,
  delivery_fee   REAL NOT NULL DEFAULT 0,
  discount       REAL NOT NULL DEFAULT 0,
  total          REAL NOT NULL DEFAULT 0,
  notes          TEXT DEFAULT '',
  driver_id      INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_by     INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at     TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  updated_at     TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_orders_branch_status ON orders(branch_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);

CREATE TABLE IF NOT EXISTS order_items (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id   INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  item_id    INTEGER REFERENCES menu_items(id) ON DELETE SET NULL,
  name       TEXT NOT NULL,
  price      REAL NOT NULL,
  qty        INTEGER NOT NULL,
  notes      TEXT DEFAULT '',
  line_total REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS order_status_history (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id   INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  status     TEXT NOT NULL,
  note       TEXT DEFAULT '',
  user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_history_order ON order_status_history(order_id);
`);

// تنفيذ مجموعة عمليات كوحدة واحدة
function tx(fn) {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

const get = (sql, ...params) => db.prepare(sql).get(...params);
const all = (sql, ...params) => db.prepare(sql).all(...params);
const run = (sql, ...params) => db.prepare(sql).run(...params);

function getSetting(key, def = '') {
  const row = get('SELECT value FROM settings WHERE key = ?', key);
  return row ? row.value : def;
}
function setSetting(key, value) {
  run('INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', key, String(value));
}

// بيانات أول تشغيل
function seed() {
  const hasRoles = get('SELECT COUNT(*) AS c FROM roles').c > 0;
  if (hasRoles) {
    // نتأكد إن المدير العام دايماً معاه كل الصلاحيات (لو اتضافت صلاحيات جديدة في تحديث)
    run("UPDATE roles SET permissions = ? WHERE key = 'admin'", JSON.stringify(ALL_PERMISSIONS));
    return;
  }

  tx(() => {
    setSetting('restaurant_name', 'مطعمي');
    setSetting('currency', 'ج.م');
    setSetting('restaurant_phone', '');
    setSetting('receipt_footer', 'شكراً لطلبكم - بالهنا والشفا');

    const roleIds = {};
    for (const r of DEFAULT_ROLES) {
      roleIds[r.key] = Number(run('INSERT INTO roles(key, name, permissions, is_system) VALUES(?,?,?,?)',
        r.key, r.name, JSON.stringify(r.permissions), r.is_system).lastInsertRowid);
    }

    const b1 = Number(run('INSERT INTO branches(name, address, phone, delivery_fee) VALUES(?,?,?,?)',
      'الفرع الرئيسي', 'وسط البلد', '01000000001', 15).lastInsertRowid);
    const b2 = Number(run('INSERT INTO branches(name, address, phone, delivery_fee) VALUES(?,?,?,?)',
      'فرع مدينة نصر', 'عباس العقاد', '01000000002', 20).lastInsertRowid);

    const addUser = (name, username, password, role, branch = null) =>
      run('INSERT INTO users(name, username, password_hash, role_id, branch_id) VALUES(?,?,?,?,?)',
        name, username, bcrypt.hashSync(password, 10), roleIds[role], branch);

    addUser('المدير العام', 'admin', 'admin123', 'admin');
    addUser('مدير الفرع الرئيسي', 'manager1', '123456', 'manager', b1);
    addUser('موظف الكول سنتر', 'callcenter', '123456', 'call_center');
    addUser('مطبخ الفرع الرئيسي', 'kitchen1', '123456', 'branch_staff', b1);
    addUser('مطبخ مدينة نصر', 'kitchen2', '123456', 'branch_staff', b2);
    addUser('طيار - أحمد', 'driver1', '123456', 'driver', b1);

    const menu = {
      'ساندوتشات': [['شاورما فراخ', 'خبز سوري، ثومية، مخلل', 65], ['شاورما لحمة', 'طحينة وبصل', 85], ['برجر كلاسيك', 'لحم بقري 150 جم، جبنة شيدر', 110], ['كريسبي تشيكن', 'صدور فراخ مقرمشة', 95]],
      'وجبات': [['وجبة شاورما فراخ', 'شاورما + بطاطس + ثومية + مخلل', 140], ['وجبة برجر', 'برجر + بطاطس + مشروب', 165], ['نص فرخة مشوية', 'أرز + سلطة + عيش', 175]],
      'بيتزا': [['بيتزا مارجريتا', 'وسط', 120], ['بيتزا خضار', 'وسط', 130], ['بيتزا بيبروني', 'وسط', 155]],
      'مقبلات': [['بطاطس محمرة', '', 35], ['حلقات بصل', '', 45], ['سلطة سيزر', '', 70]],
      'مشروبات': [['بيبسي', 'كانز', 20], ['مياه معدنية', '', 10], ['عصير برتقال فريش', '', 40]],
      'حلويات': [['أم علي', '', 55], ['تشيز كيك', '', 75]],
    };
    let catOrder = 0;
    for (const [cat, items] of Object.entries(menu)) {
      const catId = Number(run('INSERT INTO categories(name, sort_order) VALUES(?,?)', cat, catOrder++).lastInsertRowid);
      items.forEach(([name, desc, price], i) =>
        run('INSERT INTO menu_items(category_id, name, description, price, sort_order) VALUES(?,?,?,?,?)', catId, name, desc, price, i));
    }
  });
  console.log('✔ تم إنشاء قاعدة البيانات بالبيانات الافتراضية');
}

seed();

module.exports = { db, tx, get, all, run, getSetting, setSetting };
