// نسخ واجهة الويب (public) جوه التطبيق
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', '..', 'public');
const dest = path.join(__dirname, '..', 'www');

fs.rmSync(dest, { recursive: true, force: true });
fs.cpSync(src, dest, { recursive: true });
// صفحة متابعة العميل بتتفتح من السيرفر مش من التطبيق
fs.rmSync(path.join(dest, 'track.html'), { force: true });
console.log('✔ تم نسخ الواجهة إلى', dest);
