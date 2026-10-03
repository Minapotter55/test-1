class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const bad = (msg) => new HttpError(400, msg);
const notFound = (msg = 'غير موجود') => new HttpError(404, msg);
const forbidden = (msg = 'مش مسموح لك بالعملية دي') => new HttpError(403, msg);

// قراءة نص من الـ body مع التحقق
function str(value, label, { required = false, max = 500 } = {}) {
  if (value === undefined || value === null) value = '';
  if (typeof value !== 'string' && typeof value !== 'number') throw bad(`قيمة غير صحيحة: ${label}`);
  const s = String(value).trim();
  if (required && !s) throw bad(`${label} مطلوب`);
  if (s.length > max) throw bad(`${label} طويل جداً`);
  return s;
}

function num(value, label, { required = false, min = -Infinity, max = Infinity, int = false, def = 0 } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw bad(`${label} مطلوب`);
    return def;
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max || (int && !Number.isInteger(n))) {
    throw bad(`قيمة غير صحيحة: ${label}`);
  }
  return n;
}

function bool(value, def = true) {
  if (value === undefined || value === null) return def ? 1 : 0;
  return value === true || value === 1 || value === '1' || value === 'true' ? 1 : 0;
}

function idParam(req, name = 'id') {
  const id = Number(req.params[name]);
  if (!Number.isInteger(id) || id <= 0) throw bad('رقم غير صحيح');
  return id;
}

const round2 = (n) => Math.round(n * 100) / 100;

module.exports = { HttpError, bad, notFound, forbidden, str, num, bool, idParam, round2 };
