const jwt = require('jsonwebtoken');
const { JWT_SECRET, TOKEN_EXPIRES } = require('./config');
const { get } = require('./db');
const { HttpError } = require('./util');

function signToken(user) {
  return jwt.sign({ uid: user.id }, JWT_SECRET, { expiresIn: TOKEN_EXPIRES });
}

// تحميل المستخدم بالصلاحيات بتاعته
function loadUser(id) {
  const row = get(`
    SELECT u.id, u.name, u.username, u.phone, u.branch_id, u.role_id, u.is_active,
           r.name AS role_name, r.key AS role_key, r.permissions, b.name AS branch_name
    FROM users u
    JOIN roles r ON r.id = u.role_id
    LEFT JOIN branches b ON b.id = u.branch_id
    WHERE u.id = ?`, id);
  if (!row || !row.is_active) return null;
  let permissions = [];
  try { permissions = JSON.parse(row.permissions); } catch { /* ignore */ }
  return { ...row, permissions, is_admin: row.role_key === 'admin' };
}

function userFromToken(token) {
  if (!token) return null;
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    return loadUser(payload.uid);
  } catch {
    return null;
  }
}

const can = (user, perm) => !!user && (user.is_admin || user.permissions.includes(perm));
const canAny = (user, ...perms) => perms.some((p) => can(user, p));

function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const user = userFromToken(token);
  if (!user) return next(new HttpError(401, 'لازم تسجل دخول'));
  req.user = user;
  next();
}

// يسمح لو المستخدم عنده أي صلاحية من المذكورين
function requirePerm(...perms) {
  return (req, res, next) => {
    if (!canAny(req.user, ...perms)) return next(new HttpError(403, 'مش مسموح لك بالعملية دي'));
    next();
  };
}

// تحويل المستخدم لشكل آمن يرجع للواجهة
function publicUser(u) {
  return {
    id: u.id, name: u.name, username: u.username, phone: u.phone,
    branch_id: u.branch_id, branch_name: u.branch_name,
    role_id: u.role_id, role_name: u.role_name, role_key: u.role_key,
    permissions: u.is_admin ? require('./constants').ALL_PERMISSIONS : u.permissions,
    is_admin: u.is_admin,
  };
}

module.exports = { signToken, loadUser, userFromToken, can, canAny, authenticate, requirePerm, publicUser };
