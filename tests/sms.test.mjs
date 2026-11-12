import { createRequire } from 'module';
const require = createRequire(import.meta.url);
require('../www/parser.js');
const S = require('../www/sms.js');
let fail = 0;
function check(address, body, exp) {
  const got = S.parse({ address, body, date: Date.UTC(2026, 10, 12, 10) });
  const ok = exp === null ? got === null : got && Object.entries(exp).every(([k, v]) => (k === 'provider' ? (got.provider && got.provider.id) : got[k]) === v);
  if (!ok) { fail++; console.log('FAIL', address, body, '\n  got', got && JSON.stringify({ ...got, provider: got.provider && got.provider.id, date: undefined })); }
  else console.log('ok  ', address, body.slice(0, 60));
}
// بنوك
check('CIB', 'Your CIB credit card ending with 4321 was charged for EGP 1,250.50 at CARREFOUR MAADI on 12/11/26 14:05. Available limit EGP 23,400.00', { kind: 'expense', amount: 1250.5, provider: 'cib', merchant: 'CARREFOUR MAADI' });
check('NBE', 'تم خصم مبلغ 500.00 جم من حسابكم رقم ***1234 لدى طلبات بتاريخ 12/11/2026 الرصيد المتاح 8,200.00 جم', { kind: 'expense', amount: 500, provider: 'nbe', balance: 8200, merchant: 'طلبات' });
check('BanqueMisr', 'تم إضافة مبلغ 15,000.00 جنيه إلى حسابكم رقم ***9988 مرتب شهر نوفمبر. رصيدكم الحالي 22,350.00 جنيه', { kind: 'income', amount: 15000, provider: 'misr', balance: 22350 });
check('QNB', 'Dear Customer, your account has been debited with EGP 2000.00 for ATM cash withdrawal at QNB ATM Nasr City. Avl Bal EGP 5,431.20', { kind: 'atm', amount: 2000, provider: 'qnb', balance: 5431.2 });
check('CIB', 'تم سحب نقدي بمبلغ 1000 جنيه من ماكينة الصراف الآلي باستخدام بطاقتك المنتهية بـ 4321', { kind: 'atm', amount: 1000 });
// انستاباي
check('InstaPay', 'You have received EGP 3,000.00 from AHMED MOHAMED via InstaPay. Ref: 123456789', { kind: 'income', amount: 3000, isTransfer: true, provider: 'instapay', merchant: 'AHMED MOHAMED' });
check('CIB', 'InstaPay: Transfer of EGP 750.00 to MONA ALI was successful. Ref 99887766', { kind: 'expense', amount: 750, isTransfer: true, merchant: 'MONA ALI' });
check('NBE', 'تم تحويل مبلغ 400 جنيه الى محمد احمد بنجاح عن طريق انستاباي', { kind: 'expense', amount: 400, isTransfer: true, merchant: 'محمد احمد' });
check('NBE', 'تم استلام تحويل لحظي بمبلغ 1,200 جنيه من سارة حسن على حسابك عبر انستاباي', { kind: 'income', amount: 1200, isTransfer: true });
// محافظ
check('VF-Cash', 'تم تحويل 200.00 جنيه لرقم 01012345678 بنجاح. رصيدك الحالي 1,300.00 جنيه. رقم العملية 12345', { kind: 'expense', amount: 200, provider: 'vodafone', isTransfer: true, balance: 1300 });
check('VF-Cash', 'تم استلام مبلغ 300 جنيه من رقم 01198765432 ، رصيدك الحالي 1600 جنيه', { kind: 'income', amount: 300, provider: 'vodafone', balance: 1600 });
check('Orange Cash', 'You received 250 EGP from 01276543210. Your Orange Cash balance is 900 EGP', { kind: 'income', amount: 250, provider: 'orange', balance: 900 });
check('OrangeMoney', 'تم دفع 150 جنيه لشحن رصيد 01212345678 بنجاح. رصيدك 750 جنيه', { kind: 'expense', amount: 150, provider: 'orange', balance: 750 });
check('etisalat', 'عزيزي العميل تم شراء بمبلغ 85 جنيه من اوبر باستخدام اتصالات كاش', { kind: 'expense', amount: 85, provider: 'etisalat' });
check('CIB', 'Refund of EGP 320.00 from AMAZON EG has been credited to your card ending 4321', { kind: 'income', amount: 320 });
// لازم تتجاهل
check('CIB', 'Your OTP for transaction of EGP 500 at NOON is 482913. Do not share it.', null);
check('Vodafone', 'استمتع بخصم 50% على باقات الانترنت! اتصل ب 888', null);
check('+201001234567', 'حولتلك 500 جنيه يا باشا', null);
check('NBE', 'رصيدك الحالي 4,500 جنيه', null);
console.log(fail ? `\n${fail} failed` : '\nall passed');
process.exit(fail ? 1 : 0);
