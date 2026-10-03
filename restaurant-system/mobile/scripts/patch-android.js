// السماح للتطبيق بالاتصال بسيرفر محلي على http (زي http://192.168.1.10:3000)
const fs = require('fs');
const path = require('path');

const manifest = path.join(__dirname, '..', 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
if (!fs.existsSync(manifest)) process.exit(0);
let xml = fs.readFileSync(manifest, 'utf8');
if (!xml.includes('usesCleartextTraffic')) {
  xml = xml.replace('<application', '<application\n        android:usesCleartextTraffic="true"');
  fs.writeFileSync(manifest, xml);
  console.log('✔ تم السماح باتصال http في AndroidManifest.xml');
}
