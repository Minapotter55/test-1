const express = require('express');
const bcrypt = require('bcryptjs');
const { get, run } = require('../db');
const { signToken, loadUser, authenticate, publicUser } = require('../auth');
const { str, HttpError, bad } = require('../util');

const router = express.Router();

// محاولات الدخول الفاشلة (حماية بسيطة من التخمين)
const attempts = new Map();
function checkRate(key) {
  const now = Date.now();
  const a = attempts.get(key) || { count: 0, until: 0 };
  if (a.until > now) throw new HttpError(429, 'محاولات كتير، جرب بعد شوية');
  return a;
}

router.post('/login', (req, res) => {
  const username = str(req.body.username, 'اسم المستخدم', { required: true, max: 50 });
  const password = str(req.body.password, 'كلمة المرور', { required: true, max: 100 });
  const key = `${req.ip}:${username.toLowerCase()}`;
  const a = checkRate(key);

  const row = get('SELECT id, password_hash, is_active FROM users WHERE username = ?', username);
  if (!row || !bcrypt.compareSync(password, row.password_hash)) {
    a.count += 1;
    if (a.count >= 5) { a.until = Date.now() + 5 * 60 * 1000; a.count = 0; }
    attempts.set(key, a);
    throw new HttpError(401, 'اسم المستخدم أو كلمة المرور غلط');
  }
  if (!row.is_active) throw new HttpError(403, 'الحساب ده موقوف، كلم الإدارة');
  attempts.delete(key);

  run("UPDATE users SET last_login = datetime('now','localtime') WHERE id = ?", row.id);
  const user = loadUser(row.id);
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.get('/me', authenticate, (req, res) => {
  res.json({ user: publicUser(req.user) });
});

router.post('/change-password', authenticate, (req, res) => {
  const current = str(req.body.current_password, 'كلمة المرور الحالية', { required: true, max: 100 });
  const next = str(req.body.new_password, 'كلمة المرور الجديدة', { required: true, max: 100 });
  if (next.length < 6) throw bad('كلمة المرور لازم تكون 6 حروف على الأقل');
  const row = get('SELECT password_hash FROM users WHERE id = ?', req.user.id);
  if (!bcrypt.compareSync(current, row.password_hash)) throw bad('كلمة المرور الحالية غلط');
  run('UPDATE users SET password_hash = ? WHERE id = ?', bcrypt.hashSync(next, 10), req.user.id);
  res.json({ ok: true });
});

module.exports = router;
