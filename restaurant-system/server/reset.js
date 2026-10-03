// مسح قاعدة البيانات وإعادة إنشائها بالبيانات الافتراضية
const fs = require('fs');
const { DB_FILE } = require('./config');

for (const f of [DB_FILE, `${DB_FILE}-wal`, `${DB_FILE}-shm`]) {
  if (fs.existsSync(f)) fs.unlinkSync(f);
}
require('./db');
console.log('✔ تم إعادة ضبط قاعدة البيانات:', DB_FILE);
