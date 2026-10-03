const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.join(__dirname, '..');

// تحميل ملف .env لو موجود
try { process.loadEnvFile(path.join(ROOT, '.env')); } catch { /* مفيش .env */ }

const DATA_DIR = path.join(ROOT, 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

// لو مفيش JWT_SECRET بنولّد واحد ونحفظه عشان تسجيل الدخول يفضل شغال بعد إعادة التشغيل
function loadSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET;
  const file = path.join(DATA_DIR, '.secret');
  if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8').trim();
  const secret = crypto.randomBytes(48).toString('hex');
  fs.writeFileSync(file, secret, { mode: 0o600 });
  return secret;
}

module.exports = {
  ROOT,
  DATA_DIR,
  PUBLIC_DIR: path.join(ROOT, 'public'),
  PORT: Number(process.env.PORT) || 3000,
  HOST: process.env.HOST || '0.0.0.0',
  JWT_SECRET: loadSecret(),
  TOKEN_EXPIRES: process.env.TOKEN_EXPIRES || '7d',
  DB_FILE: path.resolve(ROOT, process.env.DB_FILE || 'data/restaurant.db'),
};
